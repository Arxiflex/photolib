//! Workers killed or frozen in the middle of jobs never lose or duplicate a job's side effects. The workers are
//! processes: this test binary started again with `PHOTOLIB_CHAOS_WORKER` set to the database URL.

use std::{
    process::Stdio,
    time::{Duration, Instant},
};

use async_trait::async_trait;
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{Handler, Job, NewJob, Timing, Worker, enqueue, retry};
use photolib_spawn::{Group, Running, Signal, command};
use sqlx::{PgConnection, PgPool};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const TEST: &str = "killing_and_freezing_workers_mid_job_never_loses_or_duplicates_a_side_effect";
const WORKER: &str = "PHOTOLIB_CHAOS_WORKER";
const JOBS: usize = 300;
const WORKERS: usize = 4;
const UNFINISHED: &str = "SELECT count(*) FROM jobs WHERE status IN ('queued', 'running')";

/// Writes the side effect first, then works for the milliseconds its payload says, so that kills land mid-job.
struct Effect;

#[async_trait]
impl Handler for Effect {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        sqlx::query("INSERT INTO effects (job) VALUES ($1)")
            .bind(job.id)
            .execute(&mut *tx)
            .await
            .map_err(|error| error.to_string())?;
        tokio::time::sleep(Duration::from_millis(job.payload[0].into())).await;
        Ok(())
    }
}

async fn work(url: &str) {
    let timing = Timing {
        lease: Duration::from_secs(1),
        retry: Duration::from_millis(50),
        poll_min: Duration::from_millis(10),
        poll_max: Duration::from_millis(100),
        ..Timing::default()
    };
    let owner = format!("chaos-{}", std::process::id());
    let pool = PgPool::connect(url).await.unwrap();
    let worker = Worker::new(pool, &owner, 2, timing).handle("effect", Effect);
    worker.run(CancellationToken::new()).await;
}

/// A fixed-seed xorshift, so that every run plays the same schedule of kills and freezes.
struct Dice(u64);

impl Dice {
    fn roll(&mut self, sides: u64) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0 % sides
    }
}

/// The worker processes, all killed when the test ends however it ends.
struct Workers(String, Vec<Group>);

impl Workers {
    fn start(&self) -> Group {
        let mut worker = command(std::env::current_exe().unwrap(), Signal::SIGKILL);
        worker
            .args(["--exact", TEST, "--test-threads", "1"])
            .env(WORKER, &self.0)
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        Group::start(worker, Signal::SIGKILL)
    }
}

async fn count(pool: &PgPool, sql: &str) -> i64 {
    sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn killing_and_freezing_workers_mid_job_never_loses_or_duplicates_a_side_effect() {
    if let Ok(url) = std::env::var(WORKER) {
        return work(&url).await;
    }
    let db = testpg::database().await;
    let pool = db.pool.clone();
    upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
    // No unique constraint: a duplicated side effect would be a second row.
    sqlx::query("CREATE TABLE effects (job uuid NOT NULL)")
        .execute(&pool)
        .await
        .unwrap();
    let mut dice = Dice(0x9e37_79b9_7f4a_7c15);
    let mut conn = pool.acquire().await.unwrap();
    for _ in 0..JOBS {
        let millis = [20 + dice.roll(150) as u8];
        enqueue(&mut conn, &NewJob::new("effect", &millis)).await.unwrap();
    }
    let mut workers = Workers(db.url.clone(), Vec::new());
    for _ in 0..WORKERS {
        let child = workers.start();
        workers.1.push(child);
    }
    let (mut kills, mut freezes) = (0, 0);
    let mut frozen: Option<(usize, Instant)> = None;
    let started = Running::start();
    while count(&pool, UNFINISHED).await > 0 {
        assert!(started.elapsed() < Duration::from_secs(90), "the jobs did not finish");
        tokio::time::sleep(Duration::from_millis(100 + dice.roll(150))).await;
        if let Some((worker, at)) = frozen
            && at <= Instant::now()
        {
            workers.1[worker].signal(Signal::SIGCONT);
            frozen = None;
        }
        let victim = dice.roll(WORKERS as u64) as usize;
        if frozen.is_some_and(|(worker, _)| worker == victim) {
            continue;
        }
        if frozen.is_none() && dice.roll(2) == 0 {
            // For longer than a lease, so that the other workers take its jobs over and its late commits must fail.
            workers.1[victim].signal(Signal::SIGSTOP);
            frozen = Some((victim, Instant::now() + Duration::from_millis(1500)));
            freezes += 1;
        } else {
            workers.1[victim].signal(Signal::SIGKILL);
            workers.1[victim].wait().unwrap();
            workers.1[victim] = workers.start();
            kills += 1;
        }
    }
    drop(workers);
    let interrupted = count(&pool, "SELECT count(*) FROM jobs WHERE attempts > 1").await;
    // A job interrupted on every attempt is dead-lettered with nothing applied, and a retry finishes it.
    let dead: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM jobs WHERE status = 'dead'")
        .fetch_all(&pool)
        .await
        .unwrap();
    eprintln!(
        "{kills} kills, {freezes} freezes, {interrupted} jobs interrupted, {} dead",
        dead.len()
    );
    assert!(kills > 0 && freezes > 0 && interrupted > 0);
    for id in &dead {
        assert!(retry(&mut pool.acquire().await.unwrap(), *id).await.unwrap());
    }
    let calm = tokio::spawn(async move { work(&db.url).await });
    while count(&pool, UNFINISHED).await > 0 {
        assert!(
            started.elapsed() < Duration::from_secs(120),
            "the retried jobs did not finish"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    calm.abort();
    let done = "SELECT count(*) FROM jobs WHERE status = 'done'";
    assert_eq!(count(&pool, done).await, JOBS as i64);
    let once = "SELECT count(*) FROM jobs j WHERE (SELECT count(*) FROM effects e WHERE e.job = j.id) = 1";
    assert_eq!(count(&pool, once).await, JOBS as i64);
    assert_eq!(count(&pool, "SELECT count(*) FROM effects").await, JOBS as i64);
}
