use std::{
    collections::HashMap,
    sync::{
        Arc,
        atomic::{AtomicU32, Ordering},
    },
};

use async_trait::async_trait;
use sqlx::{PgConnection, PgPool, postgres::PgListener};
use tokio::{sync::Notify, task::JoinSet};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{CHANNEL, Timing};

/// A job that failed this often, or whose lease expired this often, goes to the dead-letter queue (status `dead`).
const MAX_ATTEMPTS: i32 = 5;

/// The job `$1` is still leased to `$2` in attempt `$3`.
macro_rules! leased {
    () => {
        "id = $1 AND lease_owner = $2 AND attempts = $3 AND status = 'running'"
    };
}

/// The job runs under no grant, or under one that is neither revoked nor expired.
macro_rules! grant_active {
    () => {
        "(jobs.grant_id IS NULL OR EXISTS (SELECT FROM processing_grants g WHERE g.id = jobs.grant_id
          AND g.revoked_at IS NULL AND (g.expires_at IS NULL OR g.expires_at > now())))"
    };
}

/// What a worker does with the jobs of one type.
#[async_trait]
pub trait Handler: Send + Sync {
    /// Does `job`. Writes to `tx` commit together with the job's completion and only while the worker still holds
    /// the lease, so they happen exactly once; work outside the database must be idempotent.
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String>;

    /// Called once `job`'s writes have committed: for what may only follow them, such as deleting replaced files.
    async fn committed(&self, _job: &Job) {}
}

#[async_trait]
impl<H: Handler + ?Sized> Handler for Arc<H> {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        (**self).run(job, tx).await
    }

    async fn committed(&self, job: &Job) {
        (**self).committed(job).await
    }
}

pub struct Job {
    pub id: Uuid,
    pub kind: String,
    pub payload: Vec<u8>,
    /// 1 on the first attempt.
    pub attempt: i32,
    progress: Arc<AtomicU32>,
}

impl Job {
    /// Reports how far the job is, from 0 to 1; the next lease renewal stores it.
    pub fn progress(&self, fraction: f32) {
        self.progress
            .store(fraction.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// Whether a failure now sends the job to the dead-letter queue.
    pub fn last_attempt(&self) -> bool {
        self.attempt >= MAX_ATTEMPTS
    }
}

/// Runs the jobs of the types it has handlers for, at most `slots` at once.
pub struct Worker {
    pool: PgPool,
    owner: Arc<str>,
    slots: usize,
    timing: Timing,
    handlers: HashMap<String, Arc<dyn Handler>>,
}

impl Worker {
    /// `owner` names this process in the leases it takes.
    pub fn new(pool: PgPool, owner: &str, slots: usize, timing: Timing) -> Self {
        Worker {
            pool,
            owner: owner.into(),
            slots,
            timing,
            handlers: HashMap::new(),
        }
    }

    pub fn handle(mut self, kind: &str, handler: impl Handler + 'static) -> Self {
        self.handlers.insert(kind.into(), Arc::new(handler));
        self
    }

    /// Leases and runs jobs until `shutdown`, then lets the running ones finish.
    pub async fn run(self, shutdown: CancellationToken) {
        let kinds: Vec<String> = self.handlers.keys().cloned().collect();
        let (timing, wake) = (self.timing, Arc::new(Notify::new()));
        let listener = tokio::spawn(listen(self.pool.clone(), wake.clone(), timing.poll_max));
        let mut running = JoinSet::new();
        let mut wait = timing.poll_min;
        loop {
            let free = self.slots - running.len();
            if free > 0 {
                match lease(&self.pool, &self.owner, &kinds, free, &timing).await {
                    Ok(jobs) => {
                        if !jobs.is_empty() {
                            wait = timing.poll_min;
                        }
                        for job in jobs {
                            let handler = self.handlers[&job.kind].clone();
                            let (pool, owner) = (self.pool.clone(), self.owner.clone());
                            running.spawn(execute(pool, handler, job, owner, timing));
                        }
                    }
                    Err(error) => tracing::warn!(%error, "cannot lease jobs"),
                }
            }
            // Idle polls back off to poll_max; a notification or a finished job ends the wait at once.
            tokio::select! {
                () = shutdown.cancelled() => break,
                Some(_) = running.join_next() => {}
                () = wake.notified() => wait = timing.poll_min,
                () = tokio::time::sleep(wait) => wait = (wait * 2).min(timing.poll_max),
            }
        }
        listener.abort();
        while running.join_next().await.is_some() {}
    }
}

/// Wakes the worker whenever a job is queued, and keeps trying to listen while the database is unreachable.
async fn listen(pool: PgPool, wake: Arc<Notify>, pause: std::time::Duration) {
    loop {
        let stopped: sqlx::Result<std::convert::Infallible> = async {
            let mut listener = PgListener::connect_with(&pool).await?;
            listener.listen(CHANNEL).await?;
            loop {
                listener.recv().await?;
                wake.notify_one();
            }
        }
        .await;
        let Err(error) = stopped;
        tracing::warn!(%error, "job notifications stopped; polling only");
        tokio::time::sleep(pause).await;
    }
}

/// Leases up to `limit` due jobs of `kinds`, highest priority first. Expired leases belong to workers that stopped:
/// their jobs are retried after a backoff, or dead-lettered after the last attempt.
pub(crate) async fn lease(
    pool: &PgPool,
    owner: &str,
    kinds: &[String],
    limit: usize,
    timing: &Timing,
) -> sqlx::Result<Vec<Job>> {
    sqlx::query(
        "UPDATE jobs SET status = CASE WHEN attempts >= $1 THEN 'dead' ELSE 'queued' END, lease_owner = NULL,
           lease_until = NULL, error = 'the lease expired', run_after = now() + make_interval(secs => $2 * 2 ^ (attempts - 1))
         WHERE id IN (SELECT id FROM jobs WHERE status = 'running' AND lease_until < now() FOR UPDATE SKIP LOCKED)",
    )
    .bind(MAX_ATTEMPTS)
    .bind(timing.retry.as_secs_f64())
    .execute(pool)
    .await?;
    let rows: Vec<(Uuid, String, Option<Vec<u8>>, i32)> = sqlx::query_as(LEASE)
        .bind(owner)
        .bind(timing.lease.as_secs_f64())
        .bind(kinds)
        .bind(limit as i64)
        .fetch_all(pool)
        .await?;
    Ok(rows
        .into_iter()
        .map(|(id, kind, payload, attempt)| Job {
            id,
            kind,
            payload: payload.unwrap_or_default(),
            attempt,
            progress: Arc::default(),
        })
        .collect())
}

/// Leases `$4` due jobs of the types `$3` to `$1` for `$2` seconds: the first of each type's queue (`jobs_queued`), then
/// the first of those.
const LEASE: &str = concat!(
    "UPDATE jobs SET status = 'running', lease_owner = $1, lease_until = now() + make_interval(secs => $2),
       attempts = attempts + 1
     WHERE id IN (SELECT j.id FROM unnest($3::text[]) AS k (type) CROSS JOIN LATERAL (
       SELECT id, priority, run_after FROM jobs WHERE jobs.type = k.type AND status = 'queued' AND run_after <= now()
         AND placement = 'server'
         AND NOT EXISTS (SELECT FROM job_pauses p WHERE p.type = jobs.type AND p.until > now()) AND ",
    grant_active!(),
    " ORDER BY priority DESC, run_after, id LIMIT $4 FOR UPDATE SKIP LOCKED) j
       ORDER BY j.priority DESC, j.run_after, j.id LIMIT $4)
     RETURNING id, type, payload, attempts"
);

/// Runs `job` until it is done, fails, or its lease is lost (cancelled, expired or its grant ended).
async fn execute(pool: PgPool, handler: Arc<dyn Handler>, job: Job, owner: Arc<str>, timing: Timing) {
    let work = async {
        let mut tx = pool.begin().await.map_err(|error| error.to_string())?;
        handler.run(&job, &mut tx).await?;
        if finish(&mut tx, &job, &owner).await.map_err(|error| error.to_string())? {
            tx.commit().await.map_err(|error| error.to_string())?;
            handler.committed(&job).await;
        }
        Ok::<_, String>(())
    };
    let failed = tokio::select! {
        biased;
        result = work => result.err(),
        () = renew(&pool, &job, &owner, &timing) => None,
    };
    if let Some(error) = failed {
        tracing::warn!(job = %job.id, kind = job.kind, attempt = job.attempt, %error, "a job failed");
        if let Err(error) = fail(&pool, &job, &owner, &error, &timing).await {
            tracing::warn!(job = %job.id, %error, "cannot record a failed job");
        }
    }
}

/// Marks the job done in the handler's transaction, which locks its row until the commit; `false` when the lease
/// was lost, and the transaction must roll back.
pub(crate) async fn finish(tx: &mut PgConnection, job: &Job, owner: &str) -> sqlx::Result<bool> {
    let done = sqlx::query(concat!(
        "UPDATE jobs SET status = 'done', progress = 1, error = NULL, lease_owner = NULL, lease_until = NULL WHERE ",
        leased!(),
        " AND ",
        grant_active!()
    ))
    .bind(job.id)
    .bind(owner)
    .bind(job.attempt)
    .execute(tx)
    .await?;
    Ok(done.rows_affected() == 1)
}

/// Queues the job again after a backoff that doubles with each attempt, or dead-letters it after the last one.
async fn fail(pool: &PgPool, job: &Job, owner: &str, error: &str, timing: &Timing) -> sqlx::Result<()> {
    sqlx::query(concat!(
        "UPDATE jobs SET status = CASE WHEN attempts >= $4 THEN 'dead' ELSE 'queued' END, error = $5,
           lease_owner = NULL, lease_until = NULL, run_after = now() + make_interval(secs => $6 * 2 ^ (attempts - 1))
         WHERE ",
        leased!()
    ))
    .bind(job.id)
    .bind(owner)
    .bind(job.attempt)
    .bind(MAX_ATTEMPTS)
    .bind(error)
    .bind(timing.retry.as_secs_f64())
    .execute(pool)
    .await?;
    Ok(())
}

/// Renews the lease and stores the progress four times per lease; returns once the lease is lost.
async fn renew(pool: &PgPool, job: &Job, owner: &str, timing: &Timing) {
    let mut beat = tokio::time::interval(timing.lease / 4);
    beat.tick().await;
    loop {
        beat.tick().await;
        let renewed = sqlx::query(concat!(
            "UPDATE jobs SET lease_until = now() + make_interval(secs => $4), progress = $5 WHERE ",
            leased!(),
            " AND ",
            grant_active!()
        ))
        .bind(job.id)
        .bind(owner)
        .bind(job.attempt)
        .bind(timing.lease.as_secs_f64())
        .bind(f32::from_bits(job.progress.load(Ordering::Relaxed)))
        .execute(pool)
        .await;
        match renewed {
            Ok(renewed) if renewed.rows_affected() == 0 => return,
            Ok(_) => {}
            Err(error) => tracing::warn!(job = %job.id, %error, "cannot renew a lease"),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        sync::atomic::{AtomicBool, AtomicUsize},
        time::Duration,
    };

    use super::*;
    use crate::{
        NewJob, Placement, enqueue,
        testing::{database, exec, fast, grant, scalar, until},
    };

    /// Records each attempt in `effects`, inside the job's transaction; the payload says what else to do.
    #[derive(Clone, Default)]
    struct Probe {
        active: Arc<AtomicUsize>,
        peak: Arc<AtomicUsize>,
        dropped: Arc<AtomicBool>,
        committed: Arc<std::sync::Mutex<Vec<Uuid>>>,
    }

    struct Dropped(Arc<AtomicBool>);

    struct Active(Arc<AtomicUsize>);

    impl Drop for Active {
        fn drop(&mut self) {
            self.0.fetch_sub(1, Ordering::SeqCst);
        }
    }

    impl Drop for Dropped {
        fn drop(&mut self) {
            self.0.store(true, Ordering::SeqCst);
        }
    }

    #[async_trait]
    impl Handler for Probe {
        async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
            sqlx::query("INSERT INTO effects (job) VALUES ($1)")
                .bind(job.id)
                .execute(&mut *tx)
                .await
                .map_err(|error| error.to_string())?;
            match job.payload.as_slice() {
                b"fail" => Err("boom".into()),
                b"hang" => {
                    let _dropped = Dropped(self.dropped.clone());
                    job.progress(0.25);
                    std::future::pending().await
                }
                b"slow" => {
                    let now = self.active.fetch_add(1, Ordering::SeqCst) + 1;
                    // A lease lost under load drops this run mid-sleep: it still ends.
                    let _active = Active(self.active.clone());
                    self.peak.fetch_max(now, Ordering::SeqCst);
                    tokio::time::sleep(Duration::from_millis(100)).await;
                    Ok(())
                }
                _ => Ok(()),
            }
        }

        async fn committed(&self, job: &Job) {
            self.committed.lock().unwrap().push(job.id);
        }
    }

    impl Probe {
        /// Waits until the hanging job's handler was dropped.
        async fn stopped(&self) {
            let started = photolib_spawn::Running::start();
            while !self.dropped.load(Ordering::SeqCst) {
                assert!(started.elapsed() < Duration::from_secs(5), "the job still runs");
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }
    }

    async fn setup() -> PgPool {
        let pool = database().await;
        sqlx::query("CREATE TABLE effects (seq serial PRIMARY KEY, job uuid NOT NULL)")
            .execute(&pool)
            .await
            .unwrap();
        pool
    }

    fn start(pool: &PgPool, slots: usize, timing: Timing, probe: &Probe) {
        let worker = Worker::new(pool.clone(), "w1", slots, timing).handle("probe", probe.clone());
        tokio::spawn(worker.run(CancellationToken::new()));
    }

    async fn queue(pool: &PgPool, job: NewJob<'_>) -> Uuid {
        enqueue(&mut pool.acquire().await.unwrap(), &job).await.unwrap()
    }

    async fn job(pool: &PgPool, payload: &[u8]) -> Uuid {
        queue(pool, NewJob::new("probe", payload)).await
    }

    async fn take(pool: &PgPool, owner: &str) -> Vec<Job> {
        let kinds = ["probe".to_string()];
        lease(pool, owner, &kinds, 1, &Timing::default()).await.unwrap()
    }

    async fn effects(pool: &PgPool) -> Vec<Uuid> {
        sqlx::query_scalar("SELECT job FROM effects ORDER BY seq")
            .fetch_all(pool)
            .await
            .unwrap()
    }

    const STATUS: &str = "SELECT status FROM jobs WHERE id = $1";
    const RUN_NOW: &str = "UPDATE jobs SET run_after = now() WHERE id = $1";
    const EXPIRE: &str = "UPDATE jobs SET lease_until = now() - interval '1 second' WHERE id = $1";
    const EXPIRED: &str = "UPDATE jobs SET status = 'running', lease_until = now() - interval '1 hour' WHERE id = $1";

    /// A handler hears of each commit of its writes, after it, and of nothing that rolled back.
    #[tokio::test]
    async fn a_handler_hears_of_its_commits_only() {
        let pool = setup().await;
        let (ok, failing) = (job(&pool, b"ok").await, job(&pool, b"fail").await);
        let probe = Probe::default();
        start(&pool, 2, fast(), &probe);
        until(&pool, ok, "done").await;
        until(&pool, failing, "queued").await;
        let started = photolib_spawn::Running::start();
        while probe.committed.lock().unwrap().is_empty() && started.elapsed() < Duration::from_secs(5) {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(*probe.committed.lock().unwrap(), [ok]);
    }

    /// A backlog of one type, such as the thumbnails of a new 2M-file library, is never read to lease another of lower
    /// priority.
    #[tokio::test]
    async fn leasing_reads_only_the_queues_of_its_types() {
        let pool = database().await;
        sqlx::raw_sql(
            "INSERT INTO jobs (id, type, status, priority)
             SELECT gen_random_uuid(), CASE WHEN n % 50 = 0 THEN 'hash' ELSE 'render' END, 'queued',
               CASE WHEN n % 50 = 0 THEN -10 ELSE 0 END
             FROM generate_series(1, 100000) n;
             ANALYZE jobs",
        )
        .execute(&pool)
        .await
        .unwrap();
        let plan: Vec<String> = sqlx::query_scalar(&format!("EXPLAIN {LEASE}"))
            .bind("me")
            .bind(60.0)
            .bind(vec!["scan".to_string(), "hash".to_string()])
            .bind(4_i64)
            .fetch_all(&pool)
            .await
            .unwrap();
        let plan = plan.join("\n");
        assert!(plan.contains("Index Scan using jobs_queued "), "{plan}");
    }

    #[tokio::test]
    async fn the_highest_priority_runs_first_and_its_writes_commit_with_it() {
        let pool = setup().await;
        let low = job(&pool, b"ok").await;
        let high = queue(
            &pool,
            NewJob {
                priority: 5,
                ..NewJob::new("probe", b"ok")
            },
        )
        .await;
        start(&pool, 1, fast(), &Probe::default());
        until(&pool, low, "done").await;
        until(&pool, high, "done").await;
        assert_eq!(effects(&pool).await, [high, low]);
        let progress: f32 = scalar(&pool, "SELECT progress FROM jobs WHERE id = $1", low).await;
        assert_eq!(progress, 1.0);
    }

    /// Even when the leases of its running jobs are lost, as a loaded machine's late renewals lose them.
    #[tokio::test]
    async fn a_worker_runs_at_most_its_slots_at_once() {
        let pool = setup().await;
        let probe = Probe::default();
        let mut jobs = Vec::new();
        for _ in 0..5 {
            jobs.push(job(&pool, b"slow").await);
        }
        start(&pool, 2, fast(), &probe);
        while probe.active.load(Ordering::SeqCst) < 2 {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        let lost = "UPDATE jobs SET status = 'queued', lease_owner = NULL, lease_until = NULL WHERE status = 'running'";
        sqlx::query(lost).execute(&pool).await.unwrap();
        for id in jobs {
            until(&pool, id, "done").await;
        }
        assert_eq!(probe.peak.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn a_paused_type_waits_until_its_pause_ends_or_it_is_resumed() {
        let pool = setup().await;
        let id = job(&pool, b"ok").await;
        let mut conn = pool.acquire().await.unwrap();
        let hour = Duration::from_secs(3600);
        crate::pause(&mut conn, "probe", hour, None).await.unwrap();
        crate::pause(&mut conn, "other", hour, None).await.unwrap();
        assert!(take(&pool, "w").await.is_empty());
        sqlx::query("UPDATE job_pauses SET until = now() WHERE type = 'probe'")
            .execute(&pool)
            .await
            .unwrap();
        assert_eq!(take(&pool, "w").await[0].id, id, "the pause ended by itself");
        let next = job(&pool, b"ok").await;
        crate::pause(&mut conn, "probe", hour, None).await.unwrap();
        assert!(take(&pool, "w").await.is_empty());
        assert!(crate::resume(&mut conn, "probe").await.unwrap());
        assert!(!crate::resume(&mut conn, "probe").await.unwrap());
        assert_eq!(take(&pool, "w").await[0].id, next);
    }

    #[tokio::test]
    async fn a_failing_job_is_retried_then_dead_lettered_and_its_writes_roll_back() {
        let pool = setup().await;
        let id = job(&pool, b"fail").await;
        start(&pool, 1, fast(), &Probe::default());
        until(&pool, id, "dead").await;
        let error: String = scalar(&pool, "SELECT error FROM jobs WHERE id = $1", id).await;
        assert_eq!(error, "boom");
        assert!(effects(&pool).await.is_empty());
    }

    #[tokio::test]
    async fn the_backoff_doubles_with_each_attempt() {
        let pool = setup().await;
        let id = job(&pool, b"fail").await;
        let mut waits = Vec::new();
        for _ in 0..MAX_ATTEMPTS {
            let leased = take(&pool, "w").await;
            fail(&pool, &leased[0], "w", "boom", &Timing::default()).await.unwrap();
            let wait = "SELECT status || round(extract(epoch FROM run_after - now())) FROM jobs WHERE id = $1";
            waits.push(scalar::<String>(&pool, wait, id).await);
            exec(&pool, RUN_NOW, id).await;
        }
        assert_eq!(waits, ["queued10", "queued20", "queued40", "queued80", "dead160"]);
    }

    #[tokio::test]
    async fn progress_is_stored_while_the_job_runs_and_cancelling_stops_it_and_rolls_it_back() {
        let pool = setup().await;
        let probe = Probe::default();
        let id = job(&pool, b"hang").await;
        start(&pool, 1, fast(), &probe);
        let started = photolib_spawn::Running::start();
        let progress = "SELECT coalesce(progress, 0) FROM jobs WHERE id = $1";
        while scalar::<f32>(&pool, progress, id).await != 0.25 {
            assert!(started.elapsed() < Duration::from_secs(5));
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert!(crate::cancel(&mut pool.acquire().await.unwrap(), id).await.unwrap());
        probe.stopped().await;
        assert_eq!(scalar::<String>(&pool, STATUS, id).await, "cancelled");
        assert!(effects(&pool).await.is_empty());
        assert!(
            !crate::cancel(&mut pool.acquire().await.unwrap(), id).await.unwrap(),
            "already cancelled"
        );
    }

    #[tokio::test]
    async fn server_workers_take_no_device_or_trusted_node_jobs() {
        let pool = setup().await;
        let mut others = Vec::new();
        for placement in [Placement::Device, Placement::TrustedNode] {
            others.push(
                queue(
                    &pool,
                    NewJob {
                        placement,
                        ..NewJob::new("probe", b"ok")
                    },
                )
                .await,
            );
        }
        let server = job(&pool, b"ok").await;
        start(&pool, 1, fast(), &Probe::default());
        until(&pool, server, "done").await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        for id in others {
            assert_eq!(scalar::<String>(&pool, STATUS, id).await, "queued");
        }
    }

    #[tokio::test]
    async fn a_stopped_workers_job_is_retried_elsewhere_and_its_late_commit_is_refused() {
        let pool = setup().await;
        let id = job(&pool, b"ok").await;
        let stalled = take(&pool, "stalled").await;
        exec(&pool, EXPIRE, id).await;
        // Reaped and retried after the first attempt's backoff.
        assert!(take(&pool, "other").await.is_empty());
        let reaped = "SELECT status || error || round(extract(epoch FROM run_after - now())) FROM jobs WHERE id = $1";
        assert_eq!(scalar::<String>(&pool, reaped, id).await, "queuedthe lease expired10");
        exec(&pool, RUN_NOW, id).await;
        start(&pool, 1, fast(), &Probe::default());
        until(&pool, id, "done").await;
        let mut tx = pool.begin().await.unwrap();
        assert!(!finish(&mut tx, &stalled[0], "stalled").await.unwrap());
        assert_eq!(effects(&pool).await, [id]);
    }

    #[tokio::test]
    async fn a_job_whose_lease_expires_on_every_attempt_is_dead_lettered() {
        let pool = setup().await;
        let id = job(&pool, b"ok").await;
        for attempt in 1..=MAX_ATTEMPTS {
            assert_eq!(take(&pool, "crashing").await[0].attempt, attempt);
            exec(&pool, EXPIRE, id).await;
            assert!(take(&pool, "w").await.is_empty());
            exec(&pool, RUN_NOW, id).await;
        }
        assert_eq!(scalar::<String>(&pool, STATUS, id).await, "dead");
    }

    #[tokio::test]
    async fn a_job_under_a_grant_runs_only_while_the_grant_is_active() {
        let pool = setup().await;
        let probe = Probe::default();
        let grant = grant(&pool).await;
        let under = |payload: &'static [u8]| {
            let pool = pool.clone();
            async move {
                queue(
                    &pool,
                    NewJob {
                        grant: Some(grant),
                        ..NewJob::new("probe", payload)
                    },
                )
                .await
            }
        };
        let done = under(b"ok").await;
        let hanging = under(b"hang").await;
        start(&pool, 2, fast(), &probe);
        until(&pool, done, "done").await;
        until(&pool, hanging, "running").await;
        exec(
            &pool,
            "UPDATE processing_grants SET revoked_at = now() WHERE id = $1",
            grant,
        )
        .await;
        let queued = under(b"ok").await;
        probe.stopped().await;
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(scalar::<String>(&pool, STATUS, queued).await, "queued");
        assert_eq!(effects(&pool).await, [done]);
    }

    #[tokio::test]
    async fn a_graceful_shutdown_requeues_its_leases_without_counting_the_attempt() {
        let pool = setup().await;
        let id = job(&pool, b"ok").await;
        take(&pool, "leaving").await;
        assert_eq!(crate::requeue_leased(&pool, "other").await.unwrap(), 0);
        assert_eq!(crate::requeue_leased(&pool, "leaving").await.unwrap(), 1);
        let row = "SELECT status || attempts || coalesce(lease_owner, '') FROM jobs WHERE id = $1";
        assert_eq!(scalar::<String>(&pool, row, id).await, "queued0");
    }

    #[tokio::test]
    async fn a_dead_job_runs_again_when_retried() {
        let pool = setup().await;
        let id = job(&pool, b"ok").await;
        exec(&pool, "UPDATE jobs SET status = 'dead', attempts = 5 WHERE id = $1", id).await;
        start(&pool, 1, fast(), &Probe::default());
        assert!(crate::retry(&mut pool.acquire().await.unwrap(), id).await.unwrap());
        until(&pool, id, "done").await;
        assert!(
            !crate::retry(&mut pool.acquire().await.unwrap(), id).await.unwrap(),
            "only dead or cancelled jobs"
        );
        let attempts: i32 = scalar(&pool, "SELECT attempts FROM jobs WHERE id = $1", id).await;
        assert_eq!(attempts, 1);
    }

    /// Each poll first requeues the jobs whose lease expired, at its `now()`: a canary of a type nobody handles, its
    /// lease expired again after each, dates the polls by the database's clock, however late the test sees them.
    #[tokio::test]
    async fn an_idle_worker_polls_ever_less_often() {
        let pool = setup().await;
        let canary: Uuid = sqlx::query_scalar(
            "INSERT INTO jobs (id, type, status) VALUES (photolib_uuidv7(), 'canary', 'queued') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        exec(&pool, EXPIRED, canary).await;
        let lazy = Timing {
            poll_min: Duration::from_millis(100),
            poll_max: Duration::from_secs(3600),
            ..fast()
        };
        start(&pool, 1, lazy, &Probe::default());
        let mut polls = Vec::new();
        for _ in 0..5 {
            until(&pool, canary, "queued").await;
            polls.push(
                scalar::<i64>(
                    &pool,
                    "SELECT (extract(EPOCH FROM run_after) * 1e6)::bigint FROM jobs WHERE id = $1",
                    canary,
                )
                .await,
            );
            exec(&pool, EXPIRED, canary).await;
        }
        // A poll missed while the canary was requeued only lengthens a gap.
        let gaps: Vec<i64> = polls.windows(2).map(|pair| (pair[1] - pair[0]) / 1000).collect();
        for (gap, wait) in gaps.iter().zip([100, 200, 400, 800]) {
            assert!(*gap >= wait, "the gaps between polls in ms: {gaps:?}");
        }
    }

    /// Once its first poll leased a job that never ends, the worker leases again only when notified, or in an hour.
    #[tokio::test]
    async fn a_notification_wakes_an_idle_worker() {
        let pool = setup().await;
        let hang = job(&pool, b"hang").await;
        let lazy = Timing {
            lease: Duration::from_secs(3600),
            poll_min: Duration::from_secs(3600),
            poll_max: Duration::from_secs(3600),
            ..fast()
        };
        start(&pool, 2, lazy, &Probe::default());
        until(&pool, hang, "running").await;
        let silent: Uuid = sqlx::query_scalar(
            "INSERT INTO jobs (id, type, status) VALUES (photolib_uuidv7(), 'probe', 'queued') RETURNING id",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(scalar::<String>(&pool, STATUS, silent).await, "queued");
        until(&pool, job(&pool, b"ok").await, "done").await;
        until(&pool, silent, "done").await;
    }

    #[tokio::test]
    async fn a_notification_carries_only_the_job_id() {
        let pool = setup().await;
        let mut listener = PgListener::connect_with(&pool).await.unwrap();
        listener.listen(CHANNEL).await.unwrap();
        let id = job(&pool, b"secret payload").await;
        assert_eq!(listener.recv().await.unwrap().payload(), id.to_string());
    }
}
