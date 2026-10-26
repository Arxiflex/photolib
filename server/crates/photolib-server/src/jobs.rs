use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use photolib_jobs::{Timing, Worker, reconcile::Profile, scheduler};
use sqlx::PgPool;
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

use crate::{
    backup::{BACKUP, Backups, DRILL},
    db::DbError,
    edits::{FOLLOW, Follow},
    events::{Deliveries, EVENTS},
    export::{EXPORT, Export},
    external::{self, HASH, Hasher, Libraries, RESCAN, Rescan, SCAN, Scanner},
    faces::{FACES, FaceJob, SWEEP, Sweep},
    ingest::{self, INGEST, Ingest, RETYPE, Retype},
    library::{CREATE, PURGE, RELAYOUT, StorageJobs},
    manifest::{self, MANIFEST},
    ocr::{MODEL, OCR, Ocr},
    render::{self, RENDER, Render},
    role::{Role, WorkerClass},
    scrub::{SCRUB, Scrub},
    video::{self, TRANSCODE, Transcode},
};

/// The derivatives the server wants of every asset: the renditions of images and videos.
pub fn profile(ocr: bool) -> Profile {
    let mut renditions = render::profile(&render::specs()).renditions;
    renditions.extend(video::renditions());
    Profile {
        renditions,
        models: vec![],
        ocr: if ocr { vec![MODEL.into()] } else { vec![] },
        export: Some(crate::edits::EXPORT_SPEC.into()),
    }
}

/// The job system as the roles of a process see it.
#[async_trait]
pub trait JobQueue: Send + Sync {
    /// Runs `role`'s share of the job system until `shutdown`.
    async fn run(&self, role: Role, shutdown: CancellationToken);

    /// Puts every job still leased to `owner` back on the queue and returns how many there were.
    async fn requeue_leased(&self, owner: &str) -> Result<u64, DbError>;
}

/// The queue of a process without a database, or in maintenance: its roles wait for shutdown.
pub struct NoJobs;

#[async_trait]
impl JobQueue for NoJobs {
    async fn run(&self, _role: Role, shutdown: CancellationToken) {
        shutdown.cancelled().await;
    }

    async fn requeue_leased(&self, _owner: &str) -> Result<u64, DbError> {
        Ok(0)
    }
}

/// The job system on PostgreSQL (photolib-jobs): the scheduler ticks, reconciles with `profile`, schedules the
/// storage purge, the scrub, the external libraries' rescans, the events job, the creation of missing libraries, the
/// manifests and the backup and queues the type detection's sweep, `worker:cpu` ingests, re-checks types and renders
/// images, `worker:transcode` renders videos and `worker:io` watches, scans and hashes external libraries, creates and
/// re-lays out libraries, purges, scrubs, delivers webhooks, writes manifests and backs up. The models arrive with
/// M5-04.
pub struct PgJobs {
    pub pool: PgPool,
    /// Names this process in its leases.
    pub owner: String,
    pub cpu: Option<(Arc<Ingest>, Arc<Render>)>,
    pub transcode: Option<Arc<Transcode>>,
    pub storage: Option<Arc<StorageJobs>>,
    /// Scrubs the stores on `worker:io`.
    pub scrub: Option<Arc<Scrub>>,
    /// Purges events and delivers webhooks on `worker:io`.
    pub events: Option<Arc<Deliveries>>,
    pub libraries: Arc<Libraries>,
    /// The `backup` and `restore-drill` handlers of `worker:io`.
    pub backups: Option<Arc<Backups>>,
    /// When the scheduler queues the backup.
    pub backup_cron: String,
    /// Whether the reconciler queues an `ocr` job for every image without text (`ml.ocr`).
    pub queue_ocr: bool,
    /// The `ocr` handler of the `ml` role, which has a database to take jobs from.
    pub ocr: Option<Arc<Ocr>>,
    /// The `faces` and `faces-sweep` handlers of the `ml` role (ADR-0389).
    pub faces: Option<Arc<FaceJob>>,
    /// Whether the scheduler queues the face sweep.
    pub queue_faces: bool,
}

/// How many jobs `role` runs at once: one per core on `worker:cpu`, two on `worker:transcode` (each FFmpeg on half
/// the cores: a second slot lets posters through beside a long R1), four on `worker:io`: re-layouts, purges, and
/// folders or batches of external libraries' files, whose rate limits protect the disks.
pub fn slots(role: Role) -> usize {
    match role {
        Role::Worker(WorkerClass::Cpu) => std::thread::available_parallelism().map_or(1, usize::from),
        Role::Worker(WorkerClass::Transcode) => 2,
        Role::Worker(WorkerClass::Io) => 4,
        Role::Ml => 1,
        _ => 0,
    }
}

#[async_trait]
impl JobQueue for PgJobs {
    async fn run(&self, role: Role, shutdown: CancellationToken) {
        let worker = |slots| Worker::new(self.pool.clone(), &self.owner, slots, Timing::default());
        match (role, &self.cpu, &self.transcode, &self.storage) {
            (Role::Scheduler, ..) => {
                let pool = self.pool.clone();
                let crons = [
                    (PURGE, "*/15 * * * *"),
                    (crate::trash::EXPIRE, "30 4 * * *"),
                    (SCRUB, "*/15 * * * *"),
                    (RESCAN, "*/15 * * * *"),
                    (EVENTS, "* * * * *"),
                    // Besides new accounts', the libraries of accounts from before them and of those whose job died.
                    (CREATE, "*/15 * * * *"),
                    (MANIFEST, manifest::CRON),
                    (BACKUP, &self.backup_cron),
                ];
                let faces = self.queue_faces.then_some((SWEEP, "* * * * *"));
                for (kind, cron) in crons.into_iter().chain(faces) {
                    if let Err(error) = scheduler::schedule(&pool, kind, cron, kind, b"").await {
                        tracing::warn!(%error, kind, "cannot schedule a job");
                    }
                }
                if let Err(error) = ingest::sweep(&pool).await {
                    tracing::warn!(%error, "cannot queue the type detection's sweep");
                }
                scheduler::run(pool, profile(self.queue_ocr), Timing::default(), shutdown).await;
            }
            (Role::Worker(WorkerClass::Cpu), Some((ingest, render)), ..) => {
                worker(slots(role))
                    .handle(INGEST, ingest.clone())
                    .handle(RETYPE, Retype(ingest.clone()))
                    .handle(RENDER, render.clone())
                    .handle(FOLLOW, Follow(ingest.profile().clone()))
                    .handle(EXPORT, Export::new(render.clone()))
                    .run(shutdown)
                    .await;
            }
            (Role::Worker(WorkerClass::Transcode), _, Some(transcode), _) => {
                worker(slots(role))
                    .handle(TRANSCODE, transcode.clone())
                    .run(shutdown)
                    .await;
            }
            (Role::Worker(WorkerClass::Io), _, _, storage) => {
                let mut worker = worker(slots(role))
                    .handle(SCAN, Scanner(self.libraries.clone()))
                    .handle(HASH, Hasher(self.libraries.clone()))
                    .handle(RESCAN, Rescan);
                if let Some(storage) = storage {
                    worker = worker.handle(CREATE, storage.clone());
                    worker = worker.handle(RELAYOUT, storage.clone());
                    worker = worker.handle(PURGE, storage.clone());
                    worker = worker.handle(crate::trash::EMPTY, storage.clone());
                    worker = worker.handle(crate::trash::EXPIRE, storage.clone());
                    worker = worker.handle(MANIFEST, storage.clone());
                }
                if let Some(backups) = &self.backups {
                    worker = worker.handle(BACKUP, backups.clone()).handle(DRILL, backups.clone());
                }
                if let Some(scrub) = &self.scrub {
                    worker = worker.handle(SCRUB, scrub.clone());
                }
                if let Some(events) = &self.events {
                    worker = worker.handle(EVENTS, events.clone());
                }
                let watch = external::watch(self.pool.clone(), None, shutdown.clone());
                tokio::join!(worker.run(shutdown), watch);
            }
            (Role::Ml, ..) => self.run_ml(role, shutdown).await,
            _ => shutdown.cancelled().await,
        }
    }

    async fn requeue_leased(&self, owner: &str) -> Result<u64, DbError> {
        Ok(photolib_jobs::requeue_leased(&self.pool, owner).await?)
    }
}

impl PgJobs {
    /// The `ml` role: the handlers of the models it was given (`ocr`, and `faces` for accounts that agreed).
    async fn run_ml(&self, role: Role, shutdown: CancellationToken) {
        if self.ocr.is_none() && self.faces.is_none() {
            return shutdown.cancelled().await;
        }
        let mut ml = Worker::new(self.pool.clone(), &self.owner, slots(role), Timing::default());
        if let Some(ocr) = &self.ocr {
            ml = ml.handle(OCR, ocr.clone());
        }
        if let Some(faces) = &self.faces {
            let sweep = Sweep {
                embedder: faces.embedder().to_owned(),
                videos: faces.videos(),
            };
            ml = ml.handle(FACES, faces.clone()).handle(SWEEP, sweep);
        }
        ml.run(shutdown).await;
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct Drained {
    pub finished: usize,
    pub aborted: usize,
    pub requeued: u64,
}

/// Waits for `shutdown`, lets the in-flight tasks finish for up to `grace`, aborts the rest and re-queues
/// every job still leased to `owner`.
pub async fn drain(
    mut tasks: JoinSet<()>,
    shutdown: &CancellationToken,
    grace: Duration,
    queue: &dyn JobQueue,
    owner: &str,
) -> Result<Drained, DbError> {
    shutdown.cancelled().await;
    let mut finished = 0;
    let all_done = async {
        while let Some(result) = tasks.join_next().await {
            if let Err(error) = result {
                tracing::error!(%error, "a task failed while draining");
            }
            finished += 1;
        }
    };
    let timed_out = tokio::time::timeout(grace, all_done).await.is_err();
    let aborted = tasks.len();
    if timed_out {
        tracing::warn!(
            aborted,
            grace_secs = grace.as_secs(),
            "the grace period ended; aborting the remaining tasks"
        );
        tasks.shutdown().await;
    }
    let requeued = queue.requeue_leased(owner).await?;
    Ok(Drained {
        finished,
        aborted,
        requeued,
    })
}

#[cfg(test)]
mod tests {
    use std::{
        collections::BTreeMap,
        sync::{Mutex, atomic::Ordering},
    };

    use photolib_jobs::NewJob;
    use photolib_storage::journal::Journal;

    use super::*;
    use crate::{ingest, scrub::Scrub, testing::FakeQueue};

    type Events = Arc<Mutex<Vec<String>>>;

    struct Dropped(Events);

    impl Drop for Dropped {
        fn drop(&mut self) {
            self.0.lock().unwrap().push("aborted".into());
        }
    }

    async fn run(tasks: JoinSet<()>, grace: u64, queue: &FakeQueue) -> Result<Drained, DbError> {
        let shutdown = CancellationToken::new();
        shutdown.cancel();
        drain(tasks, &shutdown, Duration::from_secs(grace), queue, "me").await
    }

    #[tokio::test(start_paused = true)]
    async fn in_flight_tasks_finish_before_the_leases_are_requeued() {
        let events = Events::default();
        let mut tasks = JoinSet::new();
        for _ in 0..2 {
            let events = events.clone();
            tasks.spawn(async move {
                tokio::time::sleep(Duration::from_secs(2)).await;
                events.lock().unwrap().push("finished".into());
            });
        }
        let drained = run(tasks, 30, &FakeQueue::new(&events)).await.unwrap();
        assert_eq!(
            drained,
            Drained {
                finished: 2,
                aborted: 0,
                requeued: 2
            }
        );
        assert_eq!(*events.lock().unwrap(), ["finished", "finished", "requeue:me"]);
    }

    #[tokio::test(start_paused = true)]
    async fn a_task_that_outlives_the_grace_is_aborted_and_then_its_lease_is_requeued() {
        let events = Events::default();
        let mut tasks = JoinSet::new();
        let guard = Dropped(events.clone());
        tasks.spawn(async move {
            let _guard = guard;
            std::future::pending::<()>().await;
        });
        let drained = run(tasks, 5, &FakeQueue::new(&events)).await.unwrap();
        assert_eq!((drained.finished, drained.aborted), (0, 1));
        assert_eq!(*events.lock().unwrap(), ["aborted", "requeue:me"]);
    }

    #[tokio::test(start_paused = true)]
    async fn nothing_happens_until_shutdown_is_requested() {
        let events = Events::default();
        let shutdown = CancellationToken::new();
        let queue = FakeQueue::new(&events);
        let waiting = drain(JoinSet::new(), &shutdown, Duration::from_secs(1), &queue, "me");
        tokio::pin!(waiting);
        assert!(
            tokio::time::timeout(Duration::from_secs(60), &mut waiting)
                .await
                .is_err()
        );
        assert!(events.lock().unwrap().is_empty());
        shutdown.cancel();
        assert_eq!(waiting.await.unwrap().requeued, 2);
    }

    #[tokio::test(start_paused = true)]
    async fn a_failing_requeue_is_reported() {
        let queue = FakeQueue::new(&Events::default());
        queue.fail.store(true, Ordering::SeqCst);
        let error = run(JoinSet::new(), 1, &queue).await.unwrap_err();
        assert_eq!(error.to_string(), "queue unreachable");
    }

    #[tokio::test]
    async fn a_process_without_jobs_has_nothing_to_requeue() {
        assert_eq!(NoJobs.requeue_leased("me").await.unwrap(), 0);
    }

    #[tokio::test]
    #[allow(
        clippy::too_many_lines,
        reason = "one scene: every worker class takes its job from the one database"
    )]
    async fn on_postgresql_the_workers_ingest_render_and_transcode_and_lease_as_this_process() {
        use photolib_db::{
            migrate::{Upgrade, embedded, upgrade},
            testpg,
        };
        use photolib_storage::{journal::Journal, marker::Stores};

        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
        let journal = Arc::new(Journal::start(pool.clone(), Stores::default()).await.unwrap());
        let work = tempfile::tempdir().unwrap();
        let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
        let ingest = Ingest::new(
            journal.clone(),
            work.path(),
            "photolibd".into(),
            vec![],
            Profile::default(),
            libraries.clone(),
        );
        // An FFmpeg that only lists its encoders: the job's asset is gone, so nothing runs it.
        let bin = work.path().join("bin");
        std::fs::create_dir(&bin).unwrap();
        std::fs::write(bin.join("ffmpeg"), "#!/bin/sh\necho ' V....D libopenh264 H.264'\n").unwrap();
        std::fs::set_permissions(bin.join("ffmpeg"), std::os::unix::fs::PermissionsExt::from_mode(0o755)).unwrap();
        let ffmpeg = video::Ffmpeg::new("photolibd".into(), bin, 2).unwrap();
        let render = Render::new(
            journal.clone(),
            work.path(),
            "photolibd".into(),
            vec![],
            libraries.clone(),
        );
        let transcode = Transcode::new(journal, work.path(), ffmpeg, libraries.clone());
        let jobs = PgJobs {
            pool: pool.clone(),
            owner: "photolibd-1".into(),
            cpu: Some((Arc::new(ingest.unwrap()), Arc::new(render.unwrap()))),
            transcode: Some(Arc::new(transcode.unwrap())),
            storage: None,
            scrub: None,
            events: None,
            libraries,
            backups: None,
            backup_cron: "0 3 * * *".into(),
            queue_ocr: false,
            ocr: None,
            faces: None,
            queue_faces: false,
        };
        let mut conn = pool.acquire().await.unwrap();
        let ingested = ingest::enqueue(&mut conn, &[uuid::Uuid::now_v7()]).await.unwrap();
        ingest::sweep(&pool).await.unwrap();
        let retyped: uuid::Uuid = sqlx::query_scalar("SELECT id FROM jobs WHERE type = 'retype'")
            .fetch_one(&pool)
            .await
            .unwrap();
        let payload = format!(r#"{{"asset": "{}"}}"#, uuid::Uuid::now_v7());
        let job = photolib_jobs::NewJob::new(RENDER, payload.as_bytes());
        let rendered = photolib_jobs::enqueue(&mut conn, &job).await.unwrap();
        let payload = serde_json::json!({"asset": uuid::Uuid::now_v7(), "role": "thumb_s"}).to_string();
        let transcoded = photolib_jobs::enqueue(&mut conn, &photolib_jobs::NewJob::new(TRANSCODE, payload.as_bytes()))
            .await
            .unwrap();
        let shutdown = CancellationToken::new();
        let roles = [WorkerClass::Io, WorkerClass::Cpu, WorkerClass::Transcode].map(Role::Worker);
        let running = roles.map(|role| {
            let (jobs, shutdown) = (&jobs, shutdown.clone());
            async move { jobs.run(role, shutdown).await }
        });
        let finished = async {
            let done = "SELECT count(*) FROM jobs WHERE id = ANY($1) AND status = 'done'";
            while sqlx::query_scalar::<_, i64>(done)
                .bind([ingested, rendered, transcoded, retyped])
                .fetch_one(&pool)
                .await
                .unwrap()
                < 4
            {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
            shutdown.cancel();
        };
        tokio::join!(futures::future::join_all(running), finished);
    }

    /// The `ml` role of a process with a database takes `ocr` jobs: with no models loaded yet, a job is tried and
    /// waits for its next attempt, saying why.
    #[tokio::test]
    async fn on_postgresql_the_ml_role_takes_ocr_jobs() {
        use photolib_db::{
            migrate::{Upgrade, embedded, upgrade},
            testpg,
        };
        use photolib_storage::{journal::Journal, marker::Stores};

        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
        let journal = Arc::new(Journal::start(pool.clone(), Stores::default()).await.unwrap());
        let work = tempfile::tempdir().unwrap();
        let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
        let render = Render::new(journal, work.path(), "photolibd".into(), vec![], libraries.clone());
        let ocr = Ocr::new(Arc::new(render.unwrap()), Arc::default());
        let jobs = PgJobs {
            pool: pool.clone(),
            owner: "photolibd-1".into(),
            cpu: None,
            transcode: None,
            storage: None,
            scrub: None,
            events: None,
            libraries,
            backups: None,
            backup_cron: "0 3 * * *".into(),
            queue_ocr: true,
            ocr: Some(Arc::new(ocr)),
            faces: None,
            queue_faces: false,
        };
        let payload = serde_json::json!({"asset": uuid::Uuid::now_v7(), "model_id": MODEL}).to_string();
        let mut conn = pool.acquire().await.unwrap();
        let queued = photolib_jobs::enqueue(&mut conn, &NewJob::new(OCR, payload.as_bytes()))
            .await
            .unwrap();
        let shutdown = CancellationToken::new();
        let running = tokio::spawn({
            let shutdown = shutdown.clone();
            async move { jobs.run(Role::Ml, shutdown).await }
        });
        let tried = "SELECT error FROM jobs WHERE id = $1 AND attempts > 0";
        let error = loop {
            match sqlx::query_scalar::<_, Option<String>>(tried)
                .bind(queued)
                .fetch_optional(&pool)
                .await
                .unwrap()
            {
                Some(Some(error)) => break error,
                _ => tokio::time::sleep(Duration::from_millis(10)).await,
            }
        };
        assert!(error.contains("OCR models are not loaded yet"), "{error}");
        shutdown.cancel();
        running.await.unwrap();
    }

    /// The scheduler's reconciler queues what the profile wants of every image and video, and the scheduler schedules
    /// the storage purge, the scrub, the external libraries' rescans and the creation of missing libraries every 15
    /// minutes, which `worker:io` runs, and queues the sweep of this release's type detection.
    #[tokio::test]
    async fn on_postgresql_the_scheduler_role_queues_due_schedules_and_renditions_and_shutdown_requeues_leases() {
        use photolib_db::{
            migrate::{Upgrade, embedded, upgrade},
            testpg,
        };

        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
        scheduler::schedule(&pool, "minutely", "* * * * *", "probe", b"")
            .await
            .unwrap();
        sqlx::query("UPDATE job_schedules SET next_run = now()")
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query(
            "WITH ann AS (INSERT INTO users (id, handle, display_name) VALUES (photolib_uuidv7(), 'ann', 'Ann')
               RETURNING id),
             photos AS (INSERT INTO libraries (id, owner_id, name, kind, root_uri)
               SELECT photolib_uuidv7(), id, 'Photos', 'managed', 'photos' FROM ann RETURNING id, owner_id)
             INSERT INTO assets (id, library_id, owner_id, source, media_kind)
             SELECT photolib_uuidv7(), id, owner_id, 'upload', 'video' FROM photos",
        )
        .execute(&pool)
        .await
        .unwrap();
        let shutdown = CancellationToken::new();
        sqlx::raw_sql(
            "INSERT INTO users (id, handle, display_name) VALUES ('00000001-0000-7000-8000-000000000001', 'a', 'A');
             INSERT INTO libraries (id, owner_id, name, kind, root_uri)
             VALUES ('00000003-0000-7000-8000-000000000001', '00000001-0000-7000-8000-000000000001', 'P', 'managed', 'p');
             INSERT INTO assets (id, library_id, owner_id, source, media_kind) VALUES
             ('00000006-0000-7000-8000-000000000001', '00000003-0000-7000-8000-000000000001',
              '00000001-0000-7000-8000-000000000001', 'upload', 'image')",
        )
        .execute(&pool)
        .await
        .unwrap();
        let journal = Arc::new(Journal::start(pool.clone(), Default::default()).await.unwrap());
        let storage = StorageJobs::new(pool.clone(), journal.clone(), &std::env::temp_dir(), "local");
        let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
        let scrub = Scrub::new(pool.clone(), journal, BTreeMap::new(), libraries.clone());
        let jobs = Arc::new(PgJobs {
            pool: pool.clone(),
            owner: "me".into(),
            cpu: None,
            transcode: None,
            storage: Some(Arc::new(storage.unwrap())),
            scrub: Some(Arc::new(scrub)),
            events: Some(Arc::new(Deliveries::new(pool.clone(), false).unwrap())),
            libraries,
            backups: None,
            backup_cron: "0 3 * * *".into(),
            queue_ocr: true,
            ocr: None,
            faces: None,
            queue_faces: false,
        });
        let role = tokio::spawn({
            let (jobs, shutdown) = (jobs.clone(), shutdown.clone());
            async move { jobs.run(Role::Scheduler, shutdown).await }
        });
        // Due schedules, and an image's and a video's renditions from the first reconciliation.
        let queued = "SELECT count(DISTINCT type) FROM jobs WHERE type IN ('probe', 'render', 'transcode')";
        while sqlx::query_scalar::<_, i64>(queued).fetch_one(&pool).await.unwrap() < 3 {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        let transcodes: i64 = sqlx::query_scalar("SELECT count(*) FROM jobs WHERE type = 'transcode'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(transcodes, video::renditions().len() as i64);
        shutdown.cancel();
        role.await.unwrap();
        let renders = "SELECT count(*) FROM jobs WHERE type = 'render'";
        assert_eq!(sqlx::query_scalar::<_, i64>(renders).fetch_one(&pool).await.unwrap(), 3);
        let reads: Vec<String> = sqlx::query_scalar("SELECT idempotency_key FROM jobs WHERE type = 'ocr'")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(
            reads,
            ["ocr:00000006-0000-7000-8000-000000000001:ppocr-v5"],
            "the image is read; the video has no text to read"
        );
        let sweeps: Vec<String> = sqlx::query_scalar("SELECT idempotency_key FROM jobs WHERE type = $1")
            .bind(RETYPE)
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(
            sweeps,
            [format!("retype:{}", ingest::sniff::VERSION)],
            "this release's type detection sweeps"
        );
        let schedules: Vec<(String, String, String)> =
            sqlx::query_as("SELECT name, cron, type FROM job_schedules WHERE name <> 'minutely' ORDER BY name")
                .fetch_all(&pool)
                .await
                .unwrap();
        let schedule = |kind: &str, cron: &str| (kind.to_string(), cron.to_string(), kind.to_string());
        assert_eq!(
            schedules,
            [
                schedule(BACKUP, "0 3 * * *"),
                schedule(EVENTS, "* * * * *"),
                schedule(CREATE, "*/15 * * * *"),
                schedule(MANIFEST, "0 2 * * *"),
                schedule(RESCAN, "*/15 * * * *"),
                schedule(SCRUB, "*/15 * * * *"),
                schedule(PURGE, "*/15 * * * *"),
                schedule(crate::trash::EXPIRE, "30 4 * * *")
            ]
        );
        let mut conn = pool.acquire().await.unwrap();
        let mut queued = vec![];
        for kind in [PURGE, SCRUB, EVENTS, CREATE, RESCAN] {
            queued.push(
                photolib_jobs::enqueue(&mut conn, &NewJob::new(kind, b""))
                    .await
                    .unwrap(),
            );
        }
        let shutdown = CancellationToken::new();
        let io = tokio::spawn({
            let (jobs, shutdown) = (jobs.clone(), shutdown.clone());
            async move { jobs.run(Role::Worker(WorkerClass::Io), shutdown).await }
        });
        let done = "SELECT count(*) FROM jobs WHERE id = ANY($1) AND status = 'done'";
        while sqlx::query_scalar::<_, i64>(done)
            .bind(&queued)
            .fetch_one(&pool)
            .await
            .unwrap()
            < 5
        {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        shutdown.cancel();
        io.await.unwrap();
        sqlx::query("UPDATE jobs SET status = 'running', lease_owner = 'me', attempts = 1 WHERE type = 'probe'")
            .execute(&pool)
            .await
            .unwrap();
        assert_eq!(jobs.requeue_leased("me").await.unwrap(), 1);
    }
}
