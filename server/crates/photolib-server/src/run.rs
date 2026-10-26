use std::{sync::Arc, time::Duration};

use photolib_db::{
    cluster::{self, Cluster},
    data, migrate,
};
use prometheus_client::metrics::gauge::Gauge;
use tokio::{
    net::TcpListener,
    signal::unix::{SignalKind, signal},
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    accounts::Accounts,
    auth::load_key,
    backup::{self, Backups},
    config::Config,
    db::Database,
    discovery,
    doctor::{Doctor, Seen},
    events::Deliveries,
    external::Libraries,
    faces::FaceJob,
    hls::{Hls, Room},
    http::{self, Health},
    ingest::Ingest,
    instance,
    jobs::{self, JobQueue, NoJobs, PgJobs},
    keys::ApiKeys,
    library::StorageJobs,
    logging,
    media::{self, Media},
    metrics::{self, Metrics},
    ml,
    models::{self, Models},
    mounts,
    ocr::{self, Ocr},
    oidc::Oidc,
    pg::PgDatabase,
    policy,
    proxy::{self, Proxies},
    render::{self, Render},
    role::{Role, WorkerClass},
    rpc,
    scrub::{self, Scrub},
    secret::Secret,
    storage, sync, upgrade,
    uploads::{self, Disks, Uploads},
    video::{Ffmpeg, Transcode},
};

/// How often the API role looks for abandoned uploads.
const EXPIRY_PERIOD: Duration = Duration::from_secs(15 * 60);

/// The collaborators of a running process, so that tests can replace them.
pub struct Deps {
    pub db: Option<Arc<dyn Database>>,
    pub queue: Arc<dyn JobQueue>,
    /// The epoch of the instance `prepare` verified, which the API reports.
    pub epoch: Option<String>,
    /// Set after a failed schema upgrade: only the listener runs, and it reports this.
    pub maintenance: Option<String>,
    /// The setup and user services of the API role, on a current schema.
    pub users: Option<Arc<rpc::Users>>,
    /// Password sign-in and sessions, with the users.
    pub auth: Option<Arc<rpc::Auth>>,
    /// The upload endpoints of the API role, beside its services.
    pub uploads: Option<Arc<Uploads>>,
    /// Its media endpoints.
    pub media: Option<Arc<Media>>,
    /// Names this process in the leases of its jobs.
    pub owner: String,
    /// The admin console's service of the API role, on a current schema.
    pub admin: Option<rpc::Admin>,
    /// What answers `/diagnostics` beside `/metrics`.
    pub doctor: Arc<Doctor>,
}

/// Everything that can refuse a start before anything listens: network-FS state directories and the instance
/// marker. Returns the instance id when the process works on an instance.
pub async fn prepare(
    config: &Config,
    db: Option<&dyn Database>,
    mountinfo: Option<&str>,
) -> Result<Option<Uuid>, String> {
    mounts::check_state_dirs(&config.state_dirs(), config.allow_network_fs, mountinfo)
        .map_err(|errors| errors.join("\n"))?;
    if !config.roles.iter().any(|role| role.needs_instance()) {
        return Ok(None);
    }
    let (Some(data_dir), Some(db)) = (&config.data_dir, db) else {
        return Err("the roles of this process need a data directory and a database".into());
    };
    instance::verify(data_dir, db).await.map(Some)
}

/// Runs the roles and the listener until `shutdown`, then drains within the grace period.
pub async fn serve(
    config: &Config,
    deps: Deps,
    listener: TcpListener,
    shutdown: CancellationToken,
) -> Result<(), String> {
    let data_dir = config.data_dir.clone().map(|dir| ("data_dir", dir));
    let upkeep = (deps.db.clone())
        .filter(|_| deps.maintenance.is_none() && config.roles.contains(&Role::Scheduler))
        .map(|db| (db, Gauge::default()));
    let metrics = Arc::new(Metrics::new(metrics::Sources {
        db: deps.db.clone(),
        dirs: data_dir.into_iter().chain(config.state_dirs()).collect(),
        backups: upgrade::backups(config).ok(),
        sync_lag: upkeep.as_ref().map(|(_, lag)| lag.clone()),
        ml: deps.doctor.ml.clone(),
    }));
    let health = Arc::new(Health {
        roles: config.roles.clone(),
        db: deps.db.clone(),
        shutdown: shutdown.clone(),
        maintenance: deps.maintenance.clone(),
    });
    let mut tasks = JoinSet::new();
    // No role may work on a schema that the upgrade left behind.
    for role in config.roles.iter().filter(|role| **role != Role::Api) {
        if deps.maintenance.is_none() || !role.needs_instance() {
            let (role, queue, shutdown) = (*role, deps.queue.clone(), shutdown.clone());
            tasks.spawn(async move {
                tracing::info!(%role, "role started");
                queue.run(role, shutdown).await;
                tracing::info!(%role, "role stopped");
            });
        }
    }
    tasks.extend(upkeep.map(|(db, lag)| sync::maintain(db, lag, shutdown.clone())));
    tasks.extend(discoverable(config, deps.epoch.as_deref(), &listener, &shutdown));
    let reports = (deps.doctor.ml.clone().zip(config.ml.token.clone())).filter(|_| config.roles.contains(&Role::Api));
    let grace = Duration::from_secs(config.shutdown_grace_secs);
    let models = (deps.users.clone().zip(config.models_dir())).map(|(users, dir)| Arc::new(Models::new(dir, users)));
    let api = (deps.epoch)
        .filter(|_| config.roles.contains(&Role::Api))
        .map(|epoch| {
            let hints = (deps.users.clone()).map(|users| rpc::hints(epoch.clone(), users, shutdown.clone()));
            rpc::api_serving(epoch, deps.users, deps.auth, deps.admin, config.web_root.clone())
                .merge(hints.unwrap_or_default())
        })
        .unwrap_or_default()
        .merge(deps.uploads.map(uploads::router).unwrap_or_default())
        .merge(deps.media.map(media::router).unwrap_or_default())
        .merge(models.map(models::router).unwrap_or_default())
        .merge(reports.map(|(ml, token)| ml::router(ml, token)).unwrap_or_default())
        .merge(metrics::router(
            metrics.clone(),
            deps.doctor,
            config.metrics.token.clone(),
        ))
        .layer(axum::middleware::from_fn_with_state(
            Arc::new(Proxies::new(config.trusted_proxies.clone(), config.allow_insecure_http)),
            proxy::guard,
        ));
    let listening = async {
        let result = http::serve(
            listener,
            http::under(&config.base_path, http::router(health, api, metrics)),
            shutdown.clone(),
            grace,
        )
        .await;
        shutdown.cancel();
        result
    };
    let (listened, drained) = tokio::join!(
        listening,
        jobs::drain(tasks, &shutdown, grace, deps.queue.as_ref(), &deps.owner)
    );
    listened.map_err(|error| format!("the listener failed: {error}"))?;
    let drained = drained.map_err(|error| format!("leased jobs could not be re-queued: {error}"))?;
    tracing::info!(
        finished = drained.finished,
        aborted = drained.aborted,
        requeued = drained.requeued,
        "drained"
    );
    Ok(())
}

/// With `database.cluster`, starts photolibd's own PostgreSQL, which stops when the cluster drops, and points
/// `database.url` and `database.bin_dir` at it.
pub async fn own_cluster(mut config: Config) -> Result<(Option<Cluster>, Config), String> {
    let Some(dir) = config.database.cluster.clone() else {
        return Ok((None, config));
    };
    let grace = Duration::from_secs(config.shutdown_grace_secs);
    let cluster = cluster::start(&dir, config.database.bin_dir.as_deref(), grace).await?;
    config.database.url = Some(Secret::new(cluster.url.clone()));
    config.database.bin_dir = Some(cluster.bin.clone());
    Ok((Some(cluster), config))
}

/// The ladder `api` streams videos with (ADR-0246): its rungs encoded with `ffmpeg_dir`'s FFmpeg where set, its cache
/// in `work_dir`, looked after until `shutdown`.
fn streaming(
    config: &Config,
    pool: sqlx::PgPool,
    journal: Arc<photolib_storage::journal::Journal>,
    work_dir: &std::path::Path,
    shutdown: &CancellationToken,
) -> Result<Arc<Hls>, String> {
    let sessions = config.streaming.sessions;
    let ffmpeg = match &config.ffmpeg_dir {
        Some(dir) if sessions > 0 => {
            let photolibd = std::env::current_exe().map_err(|e| format!("cannot find photolibd: {e}"))?;
            Some(Ffmpeg::new(photolibd, dir.clone(), sessions)?.with_tone_mapping(config.tone_mapping))
        }
        _ => None,
    };
    let room = Room {
        dir: work_dir.join("streaming"),
        bytes: config.streaming.cache_gib << 30,
        sessions,
        idle: Duration::from_secs(30),
    };
    let dir = room.dir.display().to_string();
    let libraries = Arc::new(Libraries::new(storage::LOCAL_TIMEOUT));
    let hls = Hls::new(pool, journal, libraries, ffmpeg, room)
        .map_err(|e| format!("cannot prepare streaming in {dir}: {e}"))?;
    let hls = Arc::new(hls);
    tokio::spawn(hls.clone().run(shutdown.clone()));
    Ok(hls)
}

/// The responder of an API process on its network (`discovery`); none when it listens on loopback only.
fn discoverable(
    config: &Config,
    epoch: Option<&str>,
    listener: &TcpListener,
    shutdown: &CancellationToken,
) -> Option<impl Future<Output = ()> + Send + 'static> {
    let (instance, _) = epoch?.split_once('.')?;
    let at = listener.local_addr().ok()?;
    if !config.discovery || !config.roles.contains(&Role::Api) || at.ip().is_loopback() {
        return None;
    }
    let path = match config.base_path.as_str() {
        "/" => "/".to_string(),
        base => base.to_string() + "/",
    };
    let mut txt = vec![("instance", instance.to_string()), ("path", path)];
    txt.extend(config.public_url.clone().map(|url| ("url", url)));
    let service = discovery::Service {
        label: "photolib-".to_string() + instance.get(..8).unwrap_or(instance),
        host: discovery::host_name(),
        port: at.port(),
        txt,
    };
    match discovery::socket() {
        Ok(socket) => Some(discovery::respond(socket, service, shutdown.clone())),
        Err(error) => {
            tracing::warn!(%error, "the apps cannot find this server on its network");
            None
        }
    }
}

/// Starts `photolibd` for a validated configuration and returns after a SIGTERM or SIGINT has been drained.
pub async fn run(config: Config) -> Result<(), String> {
    let tail = logging::Tail::default();
    let traces = logging::init(&config.log, &config.traces, &tail)?;
    let result = start(config, tail).await;
    if let Some(provider) = traces {
        // Sends the last spans; blocking, and through this runtime.
        let _ = tokio::task::spawn_blocking(move || provider.shutdown()).await;
    }
    result
}

async fn start(config: Config, tail: logging::Tail) -> Result<(), String> {
    tracing::info!(?config, "starting");
    if config.allow_insecure_http {
        tracing::warn!(
            "allow_insecure_http is on: passwords and setup tokens are accepted over plain HTTP from any network"
        );
    }
    let (_cluster, config) = own_cluster(config).await?;
    let mountinfo = mounts::current_mountinfo();
    if mountinfo.is_none() {
        tracing::warn!("/proc/self/mountinfo is unreadable; the network filesystem check is skipped");
    }
    let mut pg: Option<Arc<PgDatabase>> = None;
    if config.roles.iter().any(|role| role.needs_instance())
        && let Some(url) = &config.database.url
    {
        let jobs = config.roles.iter().map(|role| jobs::slots(*role)).sum();
        let connected = PgDatabase::connect(url.expose(), jobs).await;
        pg = Some(Arc::new(
            connected.map_err(|error| format!("cannot connect to the database: {error}"))?,
        ));
    }
    let db = pg.clone().map(|pg| pg as Arc<dyn Database>);
    if let Some(db) = &db {
        upgrade::from_previous_major(&config, db.as_ref()).await?;
    }
    let instance = prepare(&config, db.as_deref(), mountinfo.as_deref()).await?;
    if let Some(id) = instance {
        tracing::info!(instance_id = %id, "the data directory and the database belong together");
    }
    let restored = match instance {
        Some(_) => backup::requested_restore(&config).await?,
        None => None,
    };
    let epoch = match (instance, &config.data_dir) {
        (Some(_), Some(data_dir)) => instance::epoch(data_dir)?,
        _ => None,
    };
    let maintenance = match &pg {
        Some(pg) => upgrade::startup(&config, pg.pool(), &migrate::embedded()).await?,
        None => None,
    };
    if let Some(pg) = pg.as_ref().filter(|_| maintenance.is_none()) {
        let pinned = policy::pin(pg.pool(), &config.settings).await;
        pinned.map_err(|error| format!("cannot pin the settings of the configuration: {error}"))?;
    }
    if let (Some(pg), Some(run), None) = (&pg, &restored, &maintenance) {
        let mut conn = pg.pool().acquire().await.map_err(|error| error.to_string())?;
        backup::record(&mut conn, run).await?;
    }
    let doctor = Arc::new(Doctor {
        config: config.clone(),
        pool: pg.as_ref().map(|pg| pg.pool().clone()),
        seen: Some(Seen::default()),
        tail: Some(tail),
        ml: (config.roles.contains(&Role::Ml) || config.roles.contains(&Role::Api) && config.ml.token.is_some())
            .then(Arc::default),
    });
    let (mut users, mut auth, mut console) = (None, None, None);
    if let Some(pg) = &pg
        && let Some(key) = &config.opaque_key_file
        && maintenance.is_none()
        && config.roles.contains(&Role::Api)
    {
        let pool = pg.pool().clone();
        let unreadable = |error| format!("cannot read the accounts: {error}");
        let passwords = rpc::Auth::passwords_exist(&pool).await.map_err(unreadable)?;
        let signin = rpc::Auth::new(pool.clone(), load_key(key, passwords)?);
        let signin = signin.with_passkeys(config.relying_party());
        let signin = match config.oidc.is_empty() {
            true => signin,
            false => signin.with_oidc(Oidc::new(&config.oidc)?),
        };
        let signin = Arc::new(signin);
        let (accounts, keys) = (Accounts::new(pool.clone()), ApiKeys::new(pool));
        let started = rpc::Users::start(accounts, keys, signin.clone()).await;
        users = Some(Arc::new(started.map_err(unreadable)?.with_webhooks(config.webhooks())));
        auth = Some(signin);
        console = Some(rpc::Admin::new(pg.pool().clone(), doctor.clone()));
    }
    // Holds this process's intent-log lock until it stops, so that no other process recovers its operations.
    let journal = match (&pg, instance) {
        (Some(pg), Some(instance)) if maintenance.is_none() => {
            Some(Arc::new(storage::start(&config, pg.pool(), instance).await?))
        }
        _ => None,
    };
    let shutdown = CancellationToken::new();
    let models = ocr::Models::default();
    if let Some(ml) = doctor.ml.clone().filter(|_| config.roles.contains(&Role::Ml)) {
        ml::start(&config, ml, models.clone(), shutdown.clone());
    }
    if let Some(journal) = &journal {
        console = console.map(|console| console.with_backups(journal.clone(), shutdown.clone()));
    }
    let media = match (&pg, &journal, &users, &auth) {
        (Some(pg), Some(journal), Some(users), Some(auth)) => {
            let (pool, journal, users) = (pg.pool().clone(), journal.clone(), users.clone());
            let media = Media::new(pool.clone(), journal.clone(), users, auth.media_key());
            Some(Arc::new(match config.work_dir() {
                Some(work_dir) if config.roles.contains(&Role::Api) => {
                    media.with_hls(streaming(&config, pool, journal, &work_dir, &shutdown)?)
                }
                _ => media,
            }))
        }
        _ => None,
    };
    let mut uploads = None;
    if let (Some(pg), Some(journal), Some(users), Some(work_dir), Some(data_dir)) =
        (&pg, &journal, &users, config.work_dir(), &config.data_dir)
    {
        let staging = work_dir.join("uploads");
        let disks = Disks {
            data_dir: data_dir.clone(),
            database: config.database.data_dir.clone(),
            space: Arc::new(storage::space),
        };
        let libraries = &config.placement.libraries;
        let started = Uploads::new(
            pg.pool().clone(),
            journal.clone(),
            users.clone(),
            &staging,
            disks,
            libraries,
        )
        .map_err(|error| format!("cannot stage uploads in {}: {error}", staging.display()))?;
        let started = Arc::new(started);
        tokio::spawn(started.clone().expire_every(EXPIRY_PERIOD, shutdown.clone()));
        uploads = Some(started);
    }
    if let Some(pg) = &pg
        && maintenance.is_none()
        && config.roles.contains(&Role::Scheduler)
    {
        let (pool, shutdown) = (pg.pool().clone(), shutdown.clone());
        tokio::spawn(async move { upgrade::run_data_migrations(&pool, &data::registry(), &shutdown).await });
    }
    let mut terminate = signal(SignalKind::terminate()).map_err(|error| format!("cannot handle SIGTERM: {error}"))?;
    let mut interrupt = signal(SignalKind::interrupt()).map_err(|error| format!("cannot handle SIGINT: {error}"))?;
    let on_signal = shutdown.clone();
    tokio::spawn(async move {
        tokio::select! { _ = terminate.recv() => {}, _ = interrupt.recv() => {} }
        tracing::info!("shutting down");
        on_signal.cancel();
    });
    let listener = (TcpListener::bind(config.listen).await)
        .map_err(|error| format!("cannot listen on {}: {error}", config.listen))?;
    let roles = config.roles.iter().map(Role::to_string).collect::<Vec<_>>().join(",");
    tracing::info!(
        addr = %listener.local_addr().unwrap_or(config.listen),
        %roles,
        "listening"
    );
    let owner = format!("photolibd-{}", Uuid::now_v7());
    let queue: Arc<dyn JobQueue> = match &pg {
        Some(pg) if maintenance.is_none() => {
            let photolibd = std::env::current_exe().map_err(|e| format!("cannot find photolibd: {e}"))?;
            let runs = |class| config.roles.contains(&Role::Worker(class));
            let libraries = Arc::new(Libraries::new(storage::LOCAL_TIMEOUT));
            let cpu = match (&journal, config.work_dir()) {
                (Some(journal), Some(work_dir)) if runs(WorkerClass::Cpu) => {
                    let unprepared = |e| format!("cannot prepare ingest in {}: {e}", work_dir.display());
                    let ingest = Ingest::new(
                        journal.clone(),
                        &work_dir,
                        photolibd.clone(),
                        config.exiftool.clone(),
                        jobs::profile(config.ml.ocr),
                        libraries.clone(),
                    );
                    let render = Render::new(
                        journal.clone(),
                        &work_dir,
                        photolibd.clone(),
                        render::specs(),
                        libraries.clone(),
                    );
                    Some((
                        Arc::new(ingest.map_err(unprepared)?),
                        Arc::new(render.map_err(unprepared)?),
                    ))
                }
                _ => None,
            };
            // The `ml` role takes `ocr` jobs from the queue, its pictures rendered in a scratch directory of its own.
            let ocr = match (&journal, config.work_dir()) {
                (Some(journal), Some(work_dir)) if config.roles.contains(&Role::Ml) && config.ml.ocr => {
                    let render = Render::new(
                        journal.clone(),
                        &work_dir.join("ocr"),
                        photolibd.clone(),
                        vec![],
                        libraries.clone(),
                    );
                    let render = render.map_err(|e| format!("cannot prepare OCR in {}: {e}", work_dir.display()))?;
                    Some(Arc::new(Ocr::new(Arc::new(render), models.clone())))
                }
                _ => None,
            };
            // ... and `faces` jobs, in a scratch directory of their own, for the accounts that agreed (ADR-0389).
            let faces = match (&journal, config.work_dir()) {
                (Some(journal), Some(work_dir)) if config.roles.contains(&Role::Ml) && config.ml.faces => {
                    let render = Render::new(
                        journal.clone(),
                        &work_dir.join("faces"),
                        photolibd.clone(),
                        vec![],
                        libraries.clone(),
                    );
                    let render = render.map_err(|e| format!("cannot prepare faces in {}: {e}", work_dir.display()))?;
                    let ffmpeg = config
                        .ffmpeg_dir
                        .clone()
                        .and_then(|dir| Ffmpeg::new(photolibd.clone(), dir, 1).ok());
                    let job = FaceJob::new(
                        Arc::new(render),
                        models.clone(),
                        pg.pool().clone(),
                        &config.ml.face_embedder,
                        ffmpeg.map(Arc::new),
                    )?;
                    Some(Arc::new(job))
                }
                _ => None,
            };
            let transcode = match (&journal, config.work_dir(), &config.ffmpeg_dir) {
                (Some(journal), Some(work_dir), Some(dir)) if runs(WorkerClass::Transcode) => {
                    let slots = jobs::slots(Role::Worker(WorkerClass::Transcode));
                    let ffmpeg = Ffmpeg::new(photolibd, dir.clone(), slots)?.with_tone_mapping(config.tone_mapping);
                    let transcode = Transcode::new(journal.clone(), &work_dir, ffmpeg, libraries.clone());
                    Some(Arc::new(transcode.map_err(|e| {
                        format!("cannot prepare transcoding in {}: {e}", work_dir.display())
                    })?))
                }
                _ => None,
            };
            let storage = match (&journal, config.work_dir()) {
                (Some(journal), Some(work_dir)) if runs(WorkerClass::Io) => {
                    let storage = StorageJobs::new(
                        pg.pool().clone(),
                        journal.clone(),
                        &work_dir,
                        &config.placement.libraries,
                    );
                    Some(Arc::new(storage.map_err(|e| {
                        format!("cannot prepare re-layouts in {}: {e}", work_dir.display())
                    })?))
                }
                _ => None,
            };
            let scrub = (journal.as_ref()).filter(|_| runs(WorkerClass::Io)).map(|journal| {
                let reads = scrub::reads(&config);
                Arc::new(Scrub::new(pg.pool().clone(), journal.clone(), reads, libraries.clone()))
            });
            let events = if runs(WorkerClass::Io) {
                Some(Arc::new(Deliveries::new(pg.pool().clone(), config.webhooks())?))
            } else {
                None
            };
            let backups = match (&journal, config.work_dir()) {
                (Some(journal), Some(work_dir)) if runs(WorkerClass::Io) => Some(Arc::new(Backups::new(
                    &config,
                    pg.pool().clone(),
                    journal.clone(),
                    &work_dir,
                )?)),
                _ => None,
            };
            Arc::new(PgJobs {
                pool: pg.pool().clone(),
                owner: owner.clone(),
                cpu,
                transcode,
                storage,
                scrub,
                events,
                libraries,
                backups,
                backup_cron: config.database.backup_cron.clone(),
                queue_ocr: config.ml.ocr,
                ocr,
                faces,
                queue_faces: config.ml.faces,
            })
        }
        _ => Arc::new(NoJobs),
    };
    serve(
        &config,
        Deps {
            db,
            queue,
            epoch,
            maintenance,
            users,
            auth,
            uploads,
            media,
            owner,
            admin: console,
            doctor,
        },
        listener,
        shutdown,
    )
    .await
}

#[cfg(test)]
mod tests {
    use std::{
        net::SocketAddr,
        path::Path,
        sync::{Arc, Mutex},
        time::Duration,
    };

    use super::*;
    use crate::{
        role::{Role, WorkerClass},
        secret::Secret,
        testing::{FakeDb, FakeQueue, assert_contains, config, raw, raw_get, raw_post_json},
    };

    const TOKEN: &str = "test-token-test-token-test-token";
    const NFS: &str = "30 22 0:40 / /nas rw - nfs4 nas:/export rw\n";

    #[tokio::test]
    async fn a_work_directory_on_a_network_filesystem_stops_startup_until_overridden() {
        let dir = tempfile::tempdir().unwrap();
        let mut config = config(&[Role::Api], dir.path());
        config.work_dir = Some("/nas/scratch".into());
        let db = FakeDb::default();
        let error = prepare(&config, Some(&db), Some(NFS)).await.unwrap_err();
        assert_contains(&error, &["work_dir", "nfs4", "allow_network_fs"]);
        assert_eq!(db.stored(), None, "nothing is initialised when startup is refused");
        config.allow_network_fs = true;
        assert!(prepare(&config, Some(&db), Some(NFS)).await.is_ok());
    }

    #[tokio::test]
    async fn the_data_directory_itself_may_be_a_network_share() {
        let dir = tempfile::tempdir().unwrap();
        let mut config = config(&[Role::Api], dir.path());
        config.work_dir = Some(dir.path().join("tmp"));
        let mountinfo = format!("30 22 0:40 / {} rw - nfs4 nas:/export rw\n", dir.path().display());
        let mount_of_tmp = format!("31 30 0:41 / {}/tmp rw - ext4 /dev/sda1 rw\n", dir.path().display());
        assert!(
            prepare(
                &config,
                Some(&FakeDb::default()),
                Some(&format!("{mountinfo}{mount_of_tmp}"))
            )
            .await
            .is_ok()
        );
    }

    #[tokio::test]
    async fn startup_runs_the_instance_check_for_the_roles_that_need_it() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("IMG_0001.jpg"), b"photo").unwrap();
        let error = prepare(&config(&[Role::Scheduler], dir.path()), Some(&FakeDb::default()), None)
            .await
            .unwrap_err();
        assert!(error.contains("never initialise a non-empty root"), "{error}");
        let fresh = tempfile::tempdir().unwrap();
        let id = prepare(
            &config(&[Role::Scheduler], fresh.path()),
            Some(&FakeDb::default()),
            None,
        )
        .await
        .unwrap();
        assert!(id.is_some());
    }

    #[tokio::test]
    async fn an_ml_only_process_needs_no_database_and_no_data_directory() {
        let mut config = config(&[Role::Ml], Path::new("/does/not/exist"));
        (config.data_dir, config.database.url) = (None, None);
        assert_eq!(prepare(&config, None, Some(NFS)).await, Ok(None));
    }

    async fn started(roles: &[Role], db: &Arc<FakeDb>) -> StartedProcess {
        started_in(roles, db, None).await
    }

    async fn started_in(roles: &[Role], db: &Arc<FakeDb>, maintenance: Option<String>) -> StartedProcess {
        let dir = tempfile::tempdir().unwrap();
        let events = Arc::new(Mutex::new(Vec::new()));
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let shutdown = CancellationToken::new();
        let database: Arc<dyn Database> = db.clone();
        let epoch = format!("{}.0", Uuid::now_v7());
        let deps = Deps {
            db: Some(database),
            queue: Arc::new(FakeQueue::new(&events)),
            epoch: Some(epoch.clone()),
            maintenance,
            users: None,
            auth: None,
            uploads: None,
            media: None,
            owner: "photolibd-test".into(),
            admin: None,
            doctor: Arc::new(Doctor {
                config: config(roles, dir.path()),
                pool: None,
                seen: None,
                tail: None,
                ml: None,
            }),
        };
        let mut config = config(roles, dir.path());
        config.metrics.token = Some(Secret::new(TOKEN.into()));
        let server = tokio::spawn({
            let shutdown = shutdown.clone();
            async move { serve(&config, deps, listener, shutdown).await }
        });
        StartedProcess {
            addr,
            epoch,
            shutdown,
            server,
            events,
            _dir: dir,
        }
    }

    struct StartedProcess {
        addr: SocketAddr,
        epoch: String,
        shutdown: CancellationToken,
        server: tokio::task::JoinHandle<Result<(), String>>,
        events: Arc<Mutex<Vec<String>>>,
        _dir: tempfile::TempDir,
    }

    #[tokio::test]
    async fn the_api_role_serves_the_server_info_of_its_instance() {
        let db = Arc::new(FakeDb::default());
        let path = "/photolib.api.v1.ServerInfoService/GetServerInfo";
        let api = started(&[Role::Api], &db).await;
        let (status, body) = raw_post_json(api.addr, path, "{}").await.unwrap();
        assert_eq!(status, 200, "{body}");
        assert!(body.contains(&format!(r#""epoch":"{}""#, api.epoch)), "{body}");
        let scheduler = started(&[Role::Scheduler], &db).await;
        assert_eq!(raw_post_json(scheduler.addr, path, "{}").await.unwrap().0, 404);
    }

    #[tokio::test]
    async fn the_listener_reports_the_directories_and_the_scheduler_its_sampled_watermark_lag() {
        let db = Arc::new(FakeDb::default());
        *db.watermark.lock().unwrap() = (100, 105);
        let process = started(&[Role::Api], &db).await;
        let scheduler = started(&[Role::Scheduler], &db).await;
        let scrape = format!(
            "GET /metrics HTTP/1.1\r\nHost: test\r\nAuthorization: Bearer {TOKEN}\r\nConnection: close\r\n\r\n"
        );
        let (status, body) = raw(process.addr, scrape.clone()).await.unwrap();
        assert_eq!(status, 200, "{body}");
        for series in [
            r#"photolib_storage_free_bytes{dir="data_dir"}"#,
            "photolib_backup_last_timestamp_seconds 0.0",
        ] {
            assert!(body.contains(series), "{series} missing from {body}");
        }
        assert!(
            !body.contains("watermark"),
            "only the scheduler samples the lag: {body}"
        );
        let body = raw(scheduler.addr, scrape).await.unwrap().1;
        assert!(
            body.contains("photolib_sync_watermark_lag_seconds 0.0"),
            "nothing has waited a sample yet: {body}"
        );
    }

    #[tokio::test]
    async fn only_the_scheduler_purges_tombstones() {
        let db = Arc::new(FakeDb::default());
        let api = started(&[Role::Api], &db).await;
        let scheduler = started(&[Role::Scheduler], &db).await;
        for _ in 0..100 {
            if db.purges.lock().unwrap().len() >= 2 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        for process in [scheduler, api] {
            process.shutdown.cancel();
            process.server.await.unwrap().unwrap();
        }
        assert_eq!(
            db.purges.lock().unwrap().len(),
            2,
            "only the scheduler purges tombstones and processed mutations"
        );
    }

    #[tokio::test]
    async fn readiness_follows_the_database_over_a_real_socket() {
        let db = Arc::new(FakeDb::default());
        let process = started(&[Role::Api, Role::Worker(WorkerClass::Cpu)], &db).await;
        assert_eq!(raw_get(process.addr, "/readyz").await.unwrap().0, 200);
        db.set_down(true);
        let (status, body) = raw_get(process.addr, "/readyz/worker:cpu").await.unwrap();
        assert_eq!(status, 503, "{body}");
        assert!(body.contains("connection refused"), "{body}");
        assert_eq!(
            raw_get(process.addr, "/healthz").await.unwrap().0,
            200,
            "liveness does not depend on the database"
        );
        db.set_down(false);
        assert_eq!(raw_get(process.addr, "/readyz").await.unwrap().0, 200);
        process.shutdown.cancel();
        process.server.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn in_maintenance_the_listener_answers_and_says_why_the_roles_are_not_ready() {
        let db = Arc::new(FakeDb::default());
        let reason = "maintenance: the upgrade failed".to_string();
        let process = started_in(&[Role::Api, Role::Scheduler, Role::Ml], &db, Some(reason.clone())).await;
        assert_eq!(raw_get(process.addr, "/healthz").await.unwrap().0, 200);
        let (status, body) = raw_get(process.addr, "/readyz/api").await.unwrap();
        assert_eq!(status, 503, "{body}");
        assert!(body.contains(&reason), "{body}");
        process.shutdown.cancel();
        process.server.await.unwrap().unwrap();
        let events = process.events.lock().unwrap().clone();
        assert_eq!(events[0], "run:ml", "only the role without the database runs");
        assert_eq!(events.len(), 2, "{events:?}");
    }

    #[tokio::test]
    async fn shutdown_stops_the_roles_and_requeues_the_leased_jobs_once() {
        let db = Arc::new(FakeDb::default());
        let process = started(&[Role::Api, Role::Scheduler, Role::Worker(WorkerClass::Io)], &db).await;
        assert_eq!(raw_get(process.addr, "/readyz").await.unwrap().0, 200);
        process.shutdown.cancel();
        photolib_spawn::within(Duration::from_secs(5), process.server)
            .await
            .expect("serve returns")
            .unwrap()
            .unwrap();
        let mut events = process.events.lock().unwrap().clone();
        let requeued = events.pop().unwrap();
        assert!(requeued.starts_with("requeue:photolibd-"), "{requeued}");
        events.sort();
        assert_eq!(events, ["run:scheduler", "run:worker:io"]);
    }
}
