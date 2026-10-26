//! Scheduled database backups, their retention, the restore drill and restores from the admin console
//! (photolib-design docs/15 §6, ADR-0266). The `backup` job dumps the database at `database.backup_cron` into
//! `backups/backup-<UTC time>.dump` of store `placement.backups`, keeps the newest `database.keep_backups` and queues
//! the `restore-drill` job, which restores the newest dump of that store into a scratch database beside the live one,
//! migrates it to this release and compares its schema. A restore the console asks for happens at the next start.
//! Each run is a row of `backup_runs`.

use std::{fs, os::unix::fs::DirBuilderExt, path::Path, path::PathBuf, sync::Arc, time::Duration};

use async_trait::async_trait;
use photolib_db::{
    doctor, dump,
    migrate::{self, Upgrade, embedded},
};
use photolib_jobs::{Handler, Job, NewJob};
use photolib_storage::{BlobStore, Hash, Local, journal::Journal, marker::Stores};
use serde_json::{Value, json};
use sqlx::{PgConnection, PgPool};

use crate::{config::Config, library::text, storage, upgrade};

/// The job that dumps the database.
pub const BACKUP: &str = "backup";
/// The job that restores the newest dump into a scratch database.
pub const DRILL: &str = "restore-drill";
const PREFIX: &str = "backups/";
/// Where the admin console leaves the restore it asked for, in the data directory.
const REQUEST: &str = ".photolib/restore.json";

/// The time in a dump's key, `…-<UTC time>.dump`.
fn stamp(key: &str) -> Option<&str> {
    key.strip_prefix(PREFIX)?.strip_suffix(".dump")?.rsplit('-').next()
}

/// The Unix time of a dump's key, from its stamp `YYYYMMDDTHHMMSSZ`.
// Fields of at most four digits cannot overflow.
#[allow(clippy::arithmetic_side_effects)]
pub fn created(key: &str) -> Option<i64> {
    let stamp = stamp(key)?;
    let n = |at: usize, len: usize| stamp.get(at..at + len)?.parse::<i64>().ok();
    let (y, m, d) = (n(0, 4)?, n(4, 2)?, n(6, 2)?);
    // Days from the civil date (H. Hinnant's algorithm), the year starting in March.
    let y = if m <= 2 { y - 1 } else { y };
    let (era, doy) = (y.div_euclid(400), (153 * ((m + 9) % 12) + 2) / 5 + d - 1);
    let yoe = y - era * 400;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    Some(days * 86_400 + n(9, 2)? * 3600 + n(11, 2)? * 60 + n(13, 2)?)
}

/// `key` of `store` as a local file: in place, or a copy in `scratch` checked against its hash.
pub(crate) async fn fetch(store: &dyn BlobStore, key: &str, scratch: &Path) -> Result<PathBuf, String> {
    let meta = (store.head(key).await)
        .map_err(text)?
        .ok_or_else(|| format!("{key} is gone"))?;
    // A filesystem without extended attributes keeps no hash; it reads in place.
    let local = store.local(key, meta.hash.unwrap_or(Hash([0; 32])), scratch).await;
    let (Local::InPlace(file) | Local::Copy(file)) = local.map_err(text)?;
    Ok(file)
}

/// The dumps in the online stores, newest first: store, key and size.
pub async fn list(stores: &Stores) -> Vec<(String, String, u64)> {
    let mut dumps = vec![];
    for (name, store) in stores.online() {
        for key in store.list(PREFIX).await.unwrap_or_default() {
            if stamp(&key).is_some()
                && let Ok(Some(meta)) = store.head(&key).await
            {
                dumps.push((name.to_string(), key, meta.size));
            }
        }
    }
    dumps.sort_by(|a, b| stamp(&b.1).cmp(&stamp(&a.1)));
    dumps
}

/// A run of a backup, restore drill or restore, as `backup_runs` records it.
#[derive(Debug, PartialEq, Eq)]
pub struct Run {
    /// `backup`, `drill` or `restore`.
    pub kind: &'static str,
    /// The store of the dump.
    pub store: String,
    /// The dump's key in the store.
    pub dump: String,
    /// Whether it worked.
    pub ok: bool,
    /// What a drill restored, or why a run failed.
    pub detail: String,
}

/// Records `run` in `backup_runs`.
pub async fn record(conn: &mut PgConnection, run: &Run) -> Result<(), String> {
    sqlx::query(
        "INSERT INTO backup_runs (id, kind, store, dump, ok, detail) VALUES (photolib_uuidv7(), $1, $2, $3, $4, $5)",
    )
    .bind(run.kind)
    .bind(&run.store)
    .bind(&run.dump)
    .bind(run.ok)
    .bind(&run.detail)
    .execute(conn)
    .await
    .map(drop)
    .map_err(text)
}

/// The handler of the `backup` and `restore-drill` jobs, on `worker:io`.
pub struct Backups {
    pool: PgPool,
    journal: Arc<Journal>,
    url: String,
    bin_dir: Option<PathBuf>,
    data_dir: PathBuf,
    store: String,
    keep: usize,
    scratch: PathBuf,
}

impl Backups {
    /// The jobs of `config`'s database and `placement.backups`, staging dumps in `work_dir`.
    pub fn new(config: &Config, pool: PgPool, journal: Arc<Journal>, work_dir: &Path) -> Result<Self, String> {
        let scratch = work_dir.join("backups");
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&scratch)
            .map_err(|error| format!("cannot create {}: {error}", scratch.display()))?;
        Ok(Self {
            pool,
            journal,
            url: config
                .database
                .url
                .as_ref()
                .ok_or("database.url is not set")?
                .expose()
                .clone(),
            bin_dir: config.database.bin_dir.clone(),
            data_dir: config.data_dir.clone().ok_or("data_dir is not set")?,
            store: config.placement.backups.clone(),
            keep: config.database.keep_backups,
            scratch,
        })
    }

    /// Dumps the database into the store, leaves the newest `keep` scheduled dumps and queues the drill.
    async fn backup(&self, tx: &mut PgConnection, key: &str) -> Result<String, String> {
        let staged = tempfile::Builder::new()
            .tempfile_in(&self.scratch)
            .map_err(text)?
            .into_temp_path();
        dump::dump(&self.url, self.bin_dir.as_deref(), &staged).await?;
        let (hash, size) = Hash::of_file(&staged).map_err(text)?;
        if self.store == "local" {
            // Dumps hold every row: only the owner reads them.
            let dir = self.data_dir.join(PREFIX);
            fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(dir)
                .map_err(text)?;
        }
        let op = self.journal.put(&self.store, key, &staged, hash).await.map_err(text)?;
        op.settle(tx).await.map_err(text)?;
        let blobs = self.journal.stores().get(&self.store).map_err(text)?;
        let mut scheduled = blobs.list(PREFIX).await.map_err(text)?;
        scheduled.retain(|key| key.starts_with("backups/backup-") && stamp(key).is_some());
        for old in scheduled.iter().rev().skip(self.keep) {
            (self.journal.delete_after(tx, &self.store, old, Duration::ZERO))
                .await
                .map_err(text)?;
        }
        photolib_jobs::enqueue(tx, &NewJob::new(DRILL, b""))
            .await
            .map_err(text)?;
        Ok(format!("{size} bytes"))
    }

    /// The key of the newest dump in the store.
    async fn newest(&self) -> Result<Option<String>, String> {
        let store = self.journal.stores().get(&self.store).map_err(text)?;
        let dumps = store.list(PREFIX).await.map_err(text)?;
        let stamped = dumps
            .into_iter()
            .filter_map(|key| Some((stamp(&key)?.to_string(), key)));
        Ok(stamped.max().map(|(_, key)| key))
    }

    /// Restores `key` into a scratch database beside the live one, migrates it to this release and checks that its
    /// schema is this release's, then drops it.
    async fn drill(&self, key: &str) -> Result<String, String> {
        let scratch = tempfile::tempdir_in(&self.scratch).map_err(text)?;
        let store = self.journal.stores().get(&self.store).map_err(text)?;
        let meta = store
            .head(key)
            .await
            .map_err(text)?
            .ok_or_else(|| format!("{key} is gone"))?;
        // A filesystem without extended attributes keeps no hash; it reads in place.
        let local = (self
            .journal
            .local(&self.store, key, meta.hash.unwrap_or(Hash([0; 32])), scratch.path()))
        .await;
        let (Local::InPlace(file) | Local::Copy(file)) = local.map_err(text)?;
        let mut conn = self.pool.acquire().await.map_err(text)?;
        let name: String = sqlx::query_scalar("SELECT current_database() || '_drill'")
            .fetch_one(&mut *conn)
            .await
            .map_err(text)?;
        let quoted = format!("\"{}\"", name.replace('"', "\"\""));
        let drop_it = format!("DROP DATABASE IF EXISTS {quoted} WITH (FORCE)");
        sqlx::query(&drop_it).execute(&mut *conn).await.map_err(text)?;
        sqlx::query(&format!("CREATE DATABASE {quoted}"))
            .execute(&mut *conn)
            .await
            .map_err(|error| format!("cannot create the scratch database {name}: {error}; give the role CREATEDB"))?;
        let mut url = url::Url::parse(&self.url).map_err(text)?;
        url.set_path(&name);
        // On a thread of its own: rustc cannot prove the migrations' future Send for every lifetime a job's needs.
        let (url, bin_dir, runtime) = (url.to_string(), self.bin_dir.clone(), tokio::runtime::Handle::current());
        let checked = tokio::task::spawn_blocking(move || runtime.block_on(check(&url, bin_dir.as_deref(), &file)));
        let checked = checked.await.map_err(text).and_then(|checked| checked);
        let dropped = sqlx::query(&drop_it).execute(&mut *conn).await.map_err(text);
        checked.and_then(|detail| dropped.map(|_| detail))
    }
}

/// Restores `file` into the empty database at `url`, migrates it to this release and compares its schema with the one
/// its migrations build.
async fn check(url: &str, bin_dir: Option<&Path>, file: &Path) -> Result<String, String> {
    dump::restore(url, bin_dir, file).await?;
    let pool = PgPool::connect(url).await.map_err(text)?;
    let checked = verify(&pool).await;
    pool.close().await;
    checked
}

async fn verify(pool: &PgPool) -> Result<String, String> {
    migrate::upgrade(pool, &Upgrade::new(&embedded()))
        .await
        .map_err(|(migrate::Error::Refused(why) | migrate::Error::Failed { error: why, .. })| why)?;
    let drift = doctor::drift(pool, &embedded()).await.map_err(text)?;
    if !drift.is_empty() {
        return Err(format!("the restored schema differs: {}", drift.join("; ")));
    }
    let (schema, users, assets, albums): (i64, i64, i64, i64) = sqlx::query_as(
        "SELECT (SELECT max(version) FROM schema_migrations), (SELECT count(*) FROM users),
           (SELECT count(*) FROM assets), (SELECT count(*) FROM albums)",
    )
    .fetch_one(pool)
    .await
    .map_err(text)?;
    Ok(format!(
        "restored at schema {schema}: {users} accounts, {assets} assets, {albums} albums"
    ))
}

#[async_trait]
impl Handler for Backups {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        let (kind, key, done) = if job.kind == BACKUP {
            let key = format!("{PREFIX}backup-{}.dump", dump::stamp(tx).await.map_err(text)?);
            let done = self.backup(tx, &key).await;
            ("backup", key, done)
        } else if let Some(key) = self.newest().await? {
            let done = self.drill(&key).await;
            ("drill", key, done)
        } else {
            let none = format!("store {} holds no dump", self.store);
            ("drill", String::new(), Err(none))
        };
        let run = Run {
            kind,
            store: self.store.clone(),
            dump: key,
            ok: done.is_ok(),
            detail: done.clone().unwrap_or_else(|error| error),
        };
        match done {
            Ok(_) => record(tx, &run).await,
            Err(error) => {
                // The job's transaction rolls back with the failure, which is recorded beside it.
                let mut conn = self.pool.acquire().await.map_err(text)?;
                record(&mut conn, &run).await?;
                Err(error)
            }
        }
    }
}

/// Asks the next start to restore `key` of `store`.
pub fn request_restore(data_dir: &Path, store: &str, key: &str) -> std::io::Result<()> {
    let path = data_dir.join(REQUEST);
    let temp = path.with_extension("json.tmp");
    fs::write(&temp, json!({ "store": store, "dump": key }).to_string())?;
    fs::rename(&temp, path)
}

/// Restores the backup the admin console asked for, before the schema upgrade. The request goes first, so that a
/// restore that fails is not tried again at every start. Returns the run, to record once the schema is current.
pub async fn requested_restore(config: &Config) -> Result<Option<Run>, String> {
    let Some(data_dir) = &config.data_dir else {
        return Ok(None);
    };
    let path = data_dir.join(REQUEST);
    let request: Value = match fs::read(&path) {
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        read => serde_json::from_slice(&read.map_err(text)?).map_err(text)?,
    };
    fs::remove_file(&path).map_err(text)?;
    let field = |name| request.get(name).and_then(Value::as_str).unwrap_or_default();
    let (store, key) = (field("store"), field("dump"));
    let restored = async {
        let blobs = storage::open(config, store).await?;
        let work_dir = config.work_dir().unwrap_or_else(|| data_dir.join("tmp"));
        fs::create_dir_all(&work_dir).map_err(text)?;
        let scratch = tempfile::tempdir_in(work_dir).map_err(text)?;
        let file = fetch(blobs.as_ref(), key, scratch.path()).await?;
        upgrade::restore(config, Some(&file)).await
    }
    .await;
    match &restored {
        Ok(_) => tracing::warn!(store, dump = key, "the database was restored from a backup"),
        Err(error) => tracing::error!(store, dump = key, %error, "the restore failed; the database is unchanged"),
    }
    Ok(Some(Run {
        kind: "restore",
        store: store.into(),
        dump: key.into(),
        ok: restored.is_ok(),
        detail: restored.err().unwrap_or_default(),
    }))
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;

    use photolib_db::testpg;
    use photolib_jobs::{Timing, Worker};
    use photolib_storage::testing::garage;
    use tokio_util::sync::CancellationToken;

    use super::*;
    use crate::{instance, pg::PgDatabase, role::Role, secret::Secret, testing};

    struct Instance {
        db: testpg::TestDb,
        data: tempfile::TempDir,
        config: Config,
        journal: Arc<Journal>,
        backups: Arc<Backups>,
    }

    /// An instance whose backups go to `store` and keep two scheduled dumps.
    async fn instance(store: &str) -> Instance {
        let db = testpg::database().await;
        let data = tempfile::tempdir().unwrap();
        let mut config = testing::config(&[Role::Api], data.path());
        config.database.url = Some(Secret::new(db.url.clone()));
        config.database.bin_dir = Some(testpg::bin_dir());
        config.database.keep_backups = 2;
        config.stores.insert("b2".into(), testing::store(&garage()));
        config.placement.backups = store.into();
        let pg = PgDatabase::connect(&db.url, 0).await.unwrap();
        let id = instance::verify(data.path(), &pg).await.unwrap();
        upgrade::startup(&config, &db.pool, &embedded()).await.unwrap();
        let journal = Arc::new(storage::start(&config, &db.pool, id).await.unwrap());
        let work = config.work_dir().unwrap();
        let backups = Arc::new(Backups::new(&config, db.pool.clone(), journal.clone(), &work).unwrap());
        Instance {
            db,
            data,
            config,
            journal,
            backups,
        }
    }

    async fn runs(pool: &PgPool) -> Vec<(String, String, bool, String)> {
        sqlx::query_as("SELECT kind, dump, ok, detail FROM backup_runs ORDER BY finished_at, id")
            .fetch_all(pool)
            .await
            .unwrap()
    }

    async fn scalar(pool: &PgPool, sql: &str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
    }

    /// A restore the console asked for brings the backed-up rows back at the next start, once.
    async fn restores(it: &Instance, store: &str, newest: String) {
        let pool = &it.db.pool;
        sqlx::query("UPDATE users SET handle = 'late'")
            .execute(pool)
            .await
            .unwrap();
        request_restore(it.data.path(), store, &newest).unwrap();
        let restored = requested_restore(&it.config).await.unwrap().unwrap();
        assert_eq!(
            restored,
            Run {
                kind: "restore",
                store: store.into(),
                dump: newest,
                ok: true,
                detail: String::new()
            }
        );
        let handles: Vec<String> = sqlx::query_scalar("SELECT handle FROM users")
            .fetch_all(pool)
            .await
            .unwrap();
        assert_eq!(handles, ["ann"]);
        assert!(
            instance::epoch(it.data.path()).unwrap().unwrap().ends_with(".1"),
            "devices see the restore"
        );
        assert_eq!(requested_restore(&it.config).await, Ok(None), "a request is taken once");
    }

    /// The backup job writes a dump into `store` and queues the drill, which restores it; older dumps go.
    async fn backs_up_drills_and_restores(store: &str) {
        let it = instance(store).await;
        let pool = &it.db.pool;
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES (gen_random_uuid(), 'ann', 'Ann')")
            .execute(pool)
            .await
            .unwrap();
        for stamp in ["20200101T000000Z", "20200102T000000Z"] {
            let mut tx = pool.begin().await.unwrap();
            let key = format!("{PREFIX}backup-{stamp}.dump");
            it.backups.backup(&mut tx, &key).await.unwrap();
            tx.commit().await.unwrap();
        }
        let shutdown = CancellationToken::new();
        let timing = Timing {
            poll_max: Duration::from_millis(200),
            ..Timing::default()
        };
        let worker = Worker::new(pool.clone(), "me", 1, timing)
            .handle(BACKUP, it.backups.clone())
            .handle(DRILL, it.backups.clone());
        let worker = tokio::spawn(worker.run(shutdown.clone()));
        let mut conn = pool.acquire().await.unwrap();
        photolib_jobs::enqueue(&mut conn, &NewJob::new(BACKUP, b""))
            .await
            .unwrap();
        let done = "SELECT count(*) FILTER (WHERE status = 'done') FROM jobs";
        let finished = photolib_spawn::within(Duration::from_secs(120), async {
            while scalar(pool, done).await < 4 {
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        });
        assert!(finished.await.is_some(), "{:?}", runs(pool).await);
        shutdown.cancel();
        worker.await.unwrap();
        assert_eq!(it.journal.purge().await.unwrap(), 1, "the oldest scheduled dump goes");
        let blobs = it.journal.stores().get(store).unwrap();
        let dumps = blobs.list(PREFIX).await.unwrap();
        assert_eq!(dumps.len(), 2, "{dumps:?}");
        assert_eq!(dumps[0], "backups/backup-20200102T000000Z.dump");
        let newest = dumps[1].clone();
        let runs = runs(pool).await;
        let (kind, dump, ok, detail) = &runs[runs.len() - 1];
        assert_eq!((kind.as_str(), dump, ok), ("drill", &newest, &true), "{runs:?}");
        let schema = embedded().last().unwrap().version;
        assert_eq!(
            detail,
            &format!("restored at schema {schema}: 1 accounts, 0 assets, 0 albums")
        );
        assert_eq!(runs.iter().filter(|run| run.0 == "backup").count(), 1, "{runs:?}");
        let drills = "SELECT count(*) FROM pg_database WHERE datname = current_database() || '_drill'";
        assert_eq!(scalar(pool, drills).await, 0, "the scratch database is dropped");
        if store == "local" {
            let mode = |path: &Path| fs::metadata(path).unwrap().permissions().mode() & 0o077;
            assert_eq!(mode(&it.data.path().join(PREFIX)), 0, "only the owner reads the dumps");
        }
        assert_eq!(list(it.journal.stores()).await.len(), 2);

        restores(&it, store, newest).await;
    }

    #[tokio::test]
    async fn backups_in_the_data_directory_are_kept_drilled_and_restored() {
        backs_up_drills_and_restores("local").await;
    }

    #[tokio::test]
    async fn backups_on_an_object_store_are_kept_drilled_and_restored() {
        backs_up_drills_and_restores("b2").await;
    }

    #[tokio::test]
    async fn a_drill_without_a_dump_or_of_a_broken_one_fails_and_drops_its_scratch_database() {
        let it = instance("local").await;
        let pool = &it.db.pool;
        let worker = |shutdown| {
            Worker::new(pool.clone(), "me", 1, Timing::default())
                .handle(DRILL, it.backups.clone())
                .run(shutdown)
        };
        let failed = async |n: usize| {
            let mut conn = pool.acquire().await.unwrap();
            photolib_jobs::enqueue(&mut conn, &NewJob::new(DRILL, b""))
                .await
                .unwrap();
            let shutdown = CancellationToken::new();
            let running = tokio::spawn(worker(shutdown.clone()));
            let recorded = photolib_spawn::within(Duration::from_secs(120), async {
                while runs(pool).await.len() < n {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            });
            assert!(recorded.await.is_some(), "drill {n} recorded nothing");
            shutdown.cancel();
            running.await.unwrap();
            runs(pool).await.pop().unwrap()
        };
        let none = failed(1).await;
        assert_eq!(
            (none.0.as_str(), none.2, none.3.as_str()),
            ("drill", false, "store local holds no dump")
        );
        let op = it
            .journal
            .put_bytes("local", "backups/backup-20991231T000000Z.dump", b"not a dump")
            .await
            .unwrap();
        op.settle(&mut pool.acquire().await.unwrap()).await.unwrap();
        let broken = failed(2).await;
        assert!(!broken.2 && broken.3.contains("pg_restore"), "{broken:?}");
        let drills = "SELECT count(*) FROM pg_database WHERE datname = current_database() || '_drill'";
        assert_eq!(scalar(pool, drills).await, 0);
        let dead = "SELECT count(*) FROM jobs WHERE status = 'done'";
        assert_eq!(scalar(pool, dead).await, 0, "a failed drill fails its job");
    }

    #[test]
    fn a_dumps_time_is_its_utc_stamp() {
        assert_eq!(created("backups/backup-19700101T000000Z.dump"), Some(0));
        assert_eq!(
            created("backups/pre-0005-0006-20261021T123456Z.dump"),
            Some(1_792_586_096)
        );
        assert_eq!(
            created("backups/pre-pg17-pg18-20240229T235959Z.dump"),
            Some(1_709_251_199)
        );
        assert_eq!(created("backups/notes.txt"), None);
        assert_eq!(created("other/backup-20261021T123456Z.dump"), None);
    }
}
