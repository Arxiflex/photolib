//! Managed libraries (photolib-design docs/07 §3, ADR-0022, ADR-0089). A library lives under `libraries/<id>/` of the
//! store `placement.libraries` named when it was created, behind its marker. Ingest places each original once where
//! the library's storage template says; only the re-layout job moves originals: to the current template and, with the
//! whole library, to another store. Each account that may upload gets one, "Photos", as its upload target (docs/07
//! §2) from the `library-create` job.

pub mod template;

use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use async_trait::async_trait;
use photolib_authz::Capability;
use photolib_jobs::{Handler, Job, NewJob};
use photolib_storage::{
    Error, Hash,
    journal::{Journal, Op},
    marker::{self, LIBRARY_MARKER},
};
use serde_json::{Value, json};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use template::{Fields, Template};

/// The job types.
pub const RELAYOUT: &str = "relayout";
pub const PURGE: &str = "storage-purge";
/// Creates the managed library of each account that may upload and has none.
pub const CREATE: &str = "library-create";
/// How long the source of a store move stays readable.
pub const GRACE: Duration = Duration::from_secs(7 * 86_400);

/// What the template reads of an asset: its capture time on its wall clock, else in UTC, else when it was ingested.
const FIELDS: &str = "to_char(coalesce(a.taken_local, a.taken_utc AT TIME ZONE 'UTC', a.created_at AT TIME ZONE 'UTC'),
    'YYYY MM DD HH24 MI SS'), a.make, a.model";

pub fn root(library: Uuid) -> String {
    format!("libraries/{library}")
}

pub(crate) fn text(error: impl std::fmt::Display) -> String {
    error.to_string()
}

/// Writes the marker of `library` in `store`, to switch with the row that names the store.
async fn put_marker<'a>(journal: &'a Journal, store: &str, library: Uuid) -> Result<Op<'a>, String> {
    let marker = format!("{}/{LIBRARY_MARKER}", root(library));
    (journal.put_bytes(store, &marker, &marker::library_json(library)))
        .await
        .map_err(text)
}

/// Whether the server's policy lets `owner` have managed libraries (ADR-0240).
async fn managed_libraries(pool: &PgPool, owner: Uuid) -> Result<bool, String> {
    let policy = photolib_authz::policy(pool, Some(owner), None).await.map_err(text)?;
    Ok(!policy
        .iter()
        .any(|(capability, on, _)| *capability == Capability::ManagedLibraries && !on))
}

/// Creates a managed library of `owner` on `store`, with its marker, as their upload target, and returns its id; none
/// where the server's policy switches managed libraries off for `owner` (ADR-0240).
pub async fn create(pool: &PgPool, journal: &Journal, store: &str, owner: Uuid, name: &str) -> Result<Uuid, String> {
    if !managed_libraries(pool, owner).await? {
        return Err("managed libraries are off by the server's policy".into());
    }
    let id = Uuid::now_v7();
    let op = put_marker(journal, store, id).await?;
    let insert = "INSERT INTO libraries (id, owner_id, name, kind, root_uri, store, is_upload_target)
                  VALUES ($1, $2, $3, 'managed', $4, $5, true)";
    switch(pool, Some(op), async |tx| {
        let row = sqlx::query(insert).bind(id).bind(owner).bind(name);
        row.bind(root(id)).bind(store).execute(tx).await?;
        Ok(())
    })
    .await?;
    Ok(id)
}

/// Switches `op` with the rows `record` writes, in one transaction; rolls `op` back when that fails.
async fn switch(
    pool: &PgPool,
    op: Option<Op<'_>>,
    record: impl AsyncFnOnce(&mut PgConnection) -> photolib_storage::Result<()>,
) -> Result<(), String> {
    let switched = async {
        let mut tx = pool.begin().await?;
        record(&mut tx).await?;
        if let Some(op) = &op {
            op.switch(&mut tx).await?;
        }
        Ok::<_, Error>(tx.commit().await?)
    }
    .await;
    if let (Err(_), Some(op)) = (&switched, op) {
        // Should this fail too, recovery after the next start rolls it back.
        let _ = op.abandon().await;
    }
    switched.map_err(text)
}

/// Sets the storage template of `library`, `None` for the default. Originals already placed stay where they are.
pub async fn set_template(pool: &PgPool, library: Uuid, template: Option<&str>) -> Result<(), String> {
    if let Some(template) = template {
        template.parse::<Template>()?;
    }
    sqlx::query("UPDATE libraries SET storage_template = $2 WHERE id = $1")
        .bind(library)
        .bind(template)
        .execute(pool)
        .await
        .map_err(text)?;
    Ok(())
}

/// The store and template of `library`'s new originals.
pub async fn target(conn: &mut PgConnection, library: Uuid) -> Result<(String, Template), String> {
    let (store, template): (String, Option<String>) =
        sqlx::query_as("SELECT store, storage_template FROM libraries WHERE id = $1")
            .bind(library)
            .fetch_one(conn)
            .await
            .map_err(text)?;
    Ok((store, template.as_deref().unwrap_or(template::DEFAULT).parse()?))
}

/// What the template reads of an asset: the time as `YYYY MM DD HH MI SS`, the make and the model.
pub type Asset = (String, Option<String>, Option<String>);

pub async fn asset(conn: &mut PgConnection, id: Uuid) -> sqlx::Result<Asset> {
    sqlx::query_as(&format!("SELECT {FIELDS} FROM assets a WHERE a.id = $1"))
        .bind(id)
        .fetch_one(conn)
        .await
}

/// Where `template` puts the file `name` of `asset` in `library`, before numbering.
pub fn base(library: Uuid, template: &Template, (time, make, model): &Asset, name: &str) -> String {
    let fields = Fields {
        time,
        make: make.as_deref(),
        model: model.as_deref(),
        filename: name,
    };
    format!("{}/originals/{}", root(library), template.render(&fields))
}

/// Copies `from` (store, key) to the first free key of `base` in `store`, `base (2)` and so on when it is taken.
pub async fn place<'a>(
    journal: &'a Journal,
    from: (&str, &str),
    store: &str,
    base: &str,
    hash: Hash,
    scratch: &Path,
) -> photolib_storage::Result<(String, Op<'a>)> {
    let mut n = 1;
    loop {
        let key = template::numbered(base, n);
        match journal.copy(from, (store, &key), hash, scratch).await {
            Err(Error::Exists(_)) => n += 1,
            copied => return copied.map(|op| (key, op)),
        }
    }
}

/// Queues the re-layout of `library` to its current template in `store`.
pub async fn enqueue_relayout(conn: &mut PgConnection, library: Uuid, store: &str) -> sqlx::Result<Uuid> {
    let payload = json!({ "library": library, "store": store }).to_string();
    photolib_jobs::enqueue(conn, &NewJob::new(RELAYOUT, payload.as_bytes())).await
}

/// Moves the originals of `library` to where its template puts them in `to`. Each moves on its own: copied, verified,
/// switched with its rows, and its source deleted by the purge, after [`GRACE`] when it left its store; one that is
/// damaged stays. A stopped run resumes where it was, since originals in place are skipped.
pub async fn relayout(pool: &PgPool, journal: &Journal, scratch: &Path, library: Uuid, to: &str) -> Result<(), String> {
    let mut conn = pool.acquire().await.map_err(text)?;
    let (store, template) = target(&mut conn, library).await?;
    let root = root(library);
    if store != to {
        // New originals go to `to` from now on, behind the library's marker there.
        let target = journal.stores().get(to).map_err(text)?;
        let online = marker::library_online(target.as_ref(), &root, library).await;
        let marker = match online.map_err(text)? {
            true => None,
            false => Some(put_marker(journal, to, library).await?),
        };
        switch(pool, marker, async |tx| {
            let moved = sqlx::query("UPDATE libraries SET store = $2 WHERE id = $1");
            moved.bind(library).bind(to).execute(tx).await?;
            Ok(())
        })
        .await?;
    }
    type Row = (
        Uuid,
        String,
        String,
        Option<Vec<u8>>,
        Option<String>,
        String,
        Option<String>,
        Option<String>,
    );
    let mut after = Uuid::nil();
    loop {
        // A motion photo's video is a range of its original's key and moves with it.
        let rows: Vec<Row> = sqlx::query_as(&format!(
            "SELECT f.id, f.storage, f.key, f.content_hash, CASE f.role WHEN 'original' THEN a.original_filename END,
               {FIELDS}
             FROM asset_files f JOIN assets a ON a.id = f.asset_id
             WHERE a.library_id = $1 AND f.byte_offset IS NULL AND f.id > $2 ORDER BY f.id LIMIT 100"
        ))
        .bind(library)
        .bind(after)
        .fetch_all(&mut *conn)
        .await
        .map_err(text)?;
        if rows.is_empty() {
            return Ok(());
        }
        for (id, store, key, hash, original, time, make, model) in rows {
            after = id;
            let name = original.unwrap_or_else(|| key.rsplit('/').next().unwrap_or(&key).to_owned());
            let base = base(library, &template, &(time, make, model), &name);
            if store == to && template::is_numbered(&key, &base) {
                continue;
            }
            let hash =
                Hash((hash.and_then(|h| h.try_into().ok())).ok_or_else(|| format!("{key:?} has no BLAKE3 hash"))?);
            let (moved, op) = match place(journal, (&store, &key), to, &base, hash, scratch).await {
                // A damaged original stays where it is, a finding to repair (ADR-0252); the others move.
                Err(Error::Integrity(why)) => {
                    journal.found(&store, &key, &why).await.map_err(text)?;
                    continue;
                }
                placed => placed.map_err(text)?,
            };
            let grace = if store == to { Duration::ZERO } else { GRACE };
            switch(pool, Some(op), async |tx| {
                sqlx::query(
                    "UPDATE asset_files SET storage = $3, key = $4 WHERE storage = $1 AND key = $2
                       AND asset_id IN (SELECT id FROM assets WHERE library_id = $5)",
                )
                .bind(&store)
                .bind(&key)
                .bind(to)
                .bind(&moved)
                .bind(library)
                .execute(&mut *tx)
                .await?;
                journal.delete_after(tx, &store, &key, grace).await
            })
            .await?;
        }
    }
}

/// The handler of the `relayout`, `storage-purge`, `library-create` and `manifest` jobs. A re-layout commits each
/// original's move on its own and a new library switches with its marker, so they write nothing to the job's
/// transaction.
pub struct StorageJobs {
    pool: PgPool,
    journal: Arc<Journal>,
    /// Copies of originals on their way from one store to another, and manifests.
    scratch: PathBuf,
    /// The store of new libraries.
    store: String,
}

impl StorageJobs {
    pub fn new(pool: PgPool, journal: Arc<Journal>, work_dir: &Path, store: &str) -> std::io::Result<StorageJobs> {
        let scratch = work_dir.join("relayout");
        std::fs::create_dir_all(&scratch)?;
        let store = store.into();
        Ok(StorageJobs {
            pool,
            journal,
            scratch,
            store,
        })
    }

    /// Gives each account that may upload and has no managed library one, unless the policy switches them off for it:
    /// new accounts, accounts from before libraries came with them, and those whose job died.
    async fn create_missing(&self, tx: &mut PgConnection) -> Result<(), String> {
        // One run at a time, so that no account gets two: the lock lasts until the job's transaction ends, and the
        // next run's query, a statement after it, sees what this one committed.
        let lock = sqlx::query("SELECT pg_advisory_xact_lock(hashtext($1))").bind(CREATE);
        lock.execute(&mut *tx).await.map_err(text)?;
        let owners: Vec<Uuid> = sqlx::query_scalar(
            "SELECT id FROM users u WHERE role <> 'viewer' AND status <> 'deleted'
               AND NOT EXISTS (SELECT FROM libraries WHERE owner_id = u.id AND kind = 'managed')",
        )
        .fetch_all(&mut *tx)
        .await
        .map_err(text)?;
        for owner in owners {
            if managed_libraries(&self.pool, owner).await? {
                create(&self.pool, &self.journal, &self.store, owner, "Photos").await?;
            }
        }
        Ok(())
    }
}

#[async_trait]
impl Handler for StorageJobs {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        if job.kind == CREATE {
            return self.create_missing(tx).await;
        }
        if job.kind == crate::manifest::MANIFEST {
            return crate::manifest::write_all(&self.pool, &self.journal, &self.scratch, tx).await;
        }
        if job.kind == crate::trash::EMPTY || job.kind == crate::trash::EXPIRE {
            return crate::trash::run(&self.pool, &self.journal, job).await;
        }
        if job.kind == PURGE {
            let purged = self.journal.purge().await.map_err(text)?;
            if purged > 0 {
                tracing::info!(purged, "sources of moved originals deleted");
            }
            return Ok(());
        }
        let payload: Value = serde_json::from_slice(&job.payload).map_err(text)?;
        let (Some(library), Some(store)) = (
            payload["library"].as_str().and_then(|id| id.parse().ok()),
            payload["store"].as_str(),
        ) else {
            return Err("a malformed payload".into());
        };
        relayout(&self.pool, &self.journal, &self.scratch, library, store).await
    }
}

#[cfg(test)]
mod tests {
    use std::{
        os::unix::process::ExitStatusExt,
        sync::atomic::{AtomicUsize, Ordering},
    };

    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_storage::{
        BlobStore, Hook,
        fs::FsStore,
        marker::{Candidate, Stores},
        s3::{S3Config, S3Store},
        testing,
    };
    use serde::{Deserialize, Serialize};

    use super::*;

    const TIMEOUT: Duration = Duration::from_secs(30);
    const CRASH: &str = "PHOTOLIB_CRASH";

    /// A fresh filesystem store and Garage prefix, which a crash child opens as its parent does.
    #[derive(Clone, Serialize, Deserialize)]
    struct Places {
        fs: PathBuf,
        s3: S3Config,
        names: [String; 2],
        scratch: PathBuf,
    }

    impl Places {
        fn new(dir: &Path) -> Places {
            let (fs, scratch) = (dir.join("store"), dir.join("scratch"));
            std::fs::create_dir(&fs).unwrap();
            std::fs::create_dir(&scratch).unwrap();
            let names = ["fs", "s3"].map(|kind| format!("{kind}-{}", Uuid::now_v7()));
            let s3 = testing::garage();
            Places { fs, s3, names, scratch }
        }

        async fn journal(&self, pool: &PgPool, hook: Hook) -> Journal {
            let fs = FsStore::open(&self.fs, TIMEOUT).await.unwrap();
            let s3 = S3Store::open(&self.s3, TIMEOUT).unwrap();
            let stores: [Arc<dyn BlobStore>; 2] = [
                Arc::new(fs.with_hook(hook.clone())),
                Arc::new(s3.with_hook(hook.clone())),
            ];
            let candidates = (self.names.iter().zip(stores))
                .map(|(name, store)| Candidate {
                    name: name.clone(),
                    store,
                    adopt: false,
                })
                .collect();
            let stores = Stores::check(pool, Uuid::from_u128(1), candidates).await;
            (Journal::start(pool.clone(), stores).await.unwrap()).with_hook(hook)
        }
    }

    /// A library on `store` with a photo whose motion video is a range of it, and a Live Photo; returns it and the
    /// keys of its files.
    async fn library(pool: &PgPool, journal: &Journal, store: &str) -> (Uuid, Vec<String>) {
        let owner = Uuid::now_v7();
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, $2, 'Ann')")
            .bind(owner)
            .bind(owner.to_string())
            .execute(pool)
            .await
            .unwrap();
        let library = create(pool, journal, store, owner, "Photos").await.unwrap();
        let dir = tempfile::tempdir().unwrap();
        let mut keys = vec![];
        for names in [&["a.jpg"][..], &["b.heic", "b.mov"]] {
            let asset = Uuid::now_v7();
            sqlx::query(
                "INSERT INTO assets (id, library_id, owner_id, original_filename, source, taken_local, make)
                 VALUES ($1, $2, $3, $4, 'upload', '2020-02-29 18:03:11', 'Canon')",
            )
            .bind(asset)
            .bind(library)
            .bind(owner)
            .bind(names[0])
            .execute(pool)
            .await
            .unwrap();
            for (name, role) in names.iter().zip(["original", "live_motion"]) {
                let bytes = name.repeat(1000).into_bytes();
                let (staged, hash) = testing::staged(dir.path(), &bytes);
                let key = format!("{}/originals/2020/2020-02/{name}", root(library));
                let op = journal.put(store, &key, &staged, hash).await.unwrap();
                let file = "INSERT INTO asset_files (id, asset_id, role, storage, key, size, content_hash, byte_offset)
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)";
                let mut rows = vec![(role, bytes.len() as i64, hash, None)];
                if *name == "a.jpg" {
                    rows.push(("motion_extracted", 10, Hash::of(&bytes[5..15]), Some(5)));
                }
                let mut tx = pool.begin().await.unwrap();
                for (role, size, hash, offset) in rows {
                    sqlx::query(file)
                        .bind(Uuid::now_v7())
                        .bind(asset)
                        .bind(role)
                        .bind(store)
                        .bind(&key)
                        .bind(size)
                        .bind(hash.0.to_vec())
                        .bind(offset)
                        .execute(&mut *tx)
                        .await
                        .unwrap();
                }
                op.switch(&mut tx).await.unwrap();
                tx.commit().await.unwrap();
                keys.push(key);
            }
        }
        (library, keys)
    }

    /// Every file of `library` reads back with its hash through its row, and the library's store has its marker.
    async fn readable(pool: &PgPool, journal: &Journal, library: Uuid) {
        type File = (String, String, Option<i64>, i64, Vec<u8>);
        let rows: Vec<File> = sqlx::query_as(
            "SELECT f.storage, f.key, f.byte_offset, f.size, f.content_hash FROM asset_files f
             JOIN assets a ON a.id = f.asset_id WHERE a.library_id = $1",
        )
        .bind(library)
        .fetch_all(pool)
        .await
        .unwrap();
        assert_eq!(rows.len(), 4);
        for (store, key, offset, size, hash) in rows {
            let range = offset.map(|at| at as u64..(at + size) as u64);
            let bytes = journal.stores().get(&store).unwrap().get(&key, range).await;
            assert_eq!(Hash::of(&bytes.unwrap()).0.to_vec(), hash, "{store}: {key}");
        }
        let store: String = sqlx::query_scalar("SELECT store FROM libraries WHERE id = $1")
            .bind(library)
            .fetch_one(pool)
            .await
            .unwrap();
        let store = journal.stores().get(&store).unwrap();
        assert!(
            marker::library_online(store.as_ref(), &root(library), library)
                .await
                .unwrap()
        );
    }

    async fn database() -> testpg::TestDb {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db
    }

    fn no_hook() -> Hook {
        Arc::new(|_| Ok(()))
    }

    /// Makes the delayed deletes due, as a week later.
    async fn week_later(pool: &PgPool) {
        sqlx::query("UPDATE file_intents SET due = now() WHERE state = 'switched'")
            .execute(pool)
            .await
            .unwrap();
    }

    /// A store move switches each original with its rows and leaves its source readable for a week; the purge then
    /// deletes the sources, and the old store keeps only the library's marker.
    /// Where the server's policy switches managed libraries off for an account, none is created for it (ADR-0240).
    #[tokio::test]
    async fn no_managed_library_is_created_where_the_policy_switches_them_off() {
        let db = database().await;
        let dir = tempfile::tempdir().unwrap();
        let places = Places::new(dir.path());
        let journal = places.journal(&db.pool, no_hook()).await;
        let owner = Uuid::now_v7();
        sqlx::query(
            "WITH ann AS (INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann'))
             INSERT INTO policy_switches (capability, enabled) VALUES ('managed_libraries', false)",
        )
        .bind(owner)
        .execute(&db.pool)
        .await
        .unwrap();
        let create = || create(&db.pool, &journal, &places.names[0], owner, "Photos");
        assert_eq!(
            create().await,
            Err("managed libraries are off by the server's policy".into())
        );
        let count = "SELECT count(*) FROM libraries";
        assert_eq!(
            sqlx::query_scalar::<_, i64>(count).fetch_one(&db.pool).await.unwrap(),
            0
        );
        sqlx::query(
            "INSERT INTO policy_switches (capability, user_id, enabled) VALUES ('managed_libraries', $1, true)",
        )
        .bind(owner)
        .execute(&db.pool)
        .await
        .unwrap();
        assert!(create().await.is_ok(), "on for the account, the narrower level");
    }

    #[tokio::test]
    async fn a_store_move_keeps_the_sources_for_the_grace_period() {
        let db = database().await;
        for (from, to) in [(0, 1), (1, 0)] {
            let dir = tempfile::tempdir().unwrap();
            let places = Places::new(dir.path());
            let journal = places.journal(&db.pool, no_hook()).await;
            let [from, to] = [&places.names[from], &places.names[to]];
            let (library, keys) = library(&db.pool, &journal, from).await;
            relayout(&db.pool, &journal, &places.scratch, library, to)
                .await
                .unwrap();
            readable(&db.pool, &journal, library).await;
            let moved: Vec<String> = sqlx::query_scalar(
                "SELECT DISTINCT storage FROM asset_files f JOIN assets a ON a.id = f.asset_id WHERE library_id = $1",
            )
            .bind(library)
            .fetch_all(&db.pool)
            .await
            .unwrap();
            assert_eq!(&moved, std::slice::from_ref(to));
            let due: Vec<f64> = sqlx::query_scalar(
                "SELECT extract(epoch FROM due - now())::float8 FROM file_intents WHERE state = 'switched'",
            )
            .fetch_all(&db.pool)
            .await
            .unwrap();
            assert_eq!(due.len(), keys.len());
            assert!(
                due.iter()
                    .all(|d| (GRACE.as_secs_f64() - 60.0..=GRACE.as_secs_f64()).contains(d)),
                "{due:?}"
            );
            assert_eq!(journal.purge().await.unwrap(), 0);
            let old = journal.stores().get(from).unwrap();
            for key in &keys {
                assert!(old.head(key).await.unwrap().is_some(), "{key}");
            }
            week_later(&db.pool).await;
            assert_eq!(journal.purge().await.unwrap(), keys.len());
            let marker = format!("{}/{LIBRARY_MARKER}", root(library));
            assert_eq!(old.list(&root(library)).await.unwrap(), [marker]);
        }
    }

    /// An original whose bytes no longer have its hash stays where it is, an integrity finding for its repair
    /// (ADR-0252), and the rest of the library moves.
    #[tokio::test]
    async fn a_damaged_original_stays_behind_as_a_finding_and_the_rest_moves() {
        let db = database().await;
        let dir = tempfile::tempdir().unwrap();
        let places = Places::new(dir.path());
        let journal = places.journal(&db.pool, no_hook()).await;
        let [from, to] = &places.names;
        let (library, keys) = library(&db.pool, &journal, from).await;
        std::fs::write(places.fs.join(&keys[1]), "B.HEIC".repeat(1000)).unwrap();
        relayout(&db.pool, &journal, &places.scratch, library, to)
            .await
            .unwrap();
        let rows: Vec<(String, String)> =
            sqlx::query_as("SELECT key, storage FROM asset_files WHERE byte_offset IS NULL ORDER BY key")
                .fetch_all(&db.pool)
                .await
                .unwrap();
        let [a, b, mov] = [0, 1, 2].map(|i| keys[i].clone());
        assert_eq!(rows, [(a, to.clone()), (b, from.clone()), (mov, to.clone())]);
        let found: Vec<(String, String, String)> =
            sqlx::query_as("SELECT store, key, kind FROM integrity_findings WHERE resolved_at IS NULL")
                .fetch_all(&db.pool)
                .await
                .unwrap();
        assert_eq!(found, [(from.clone(), keys[1].clone(), "content".into())]);
    }

    /// What a crash child does: move `library` to `to`, then purge its sources as if a week had passed.
    #[derive(Serialize, Deserialize)]
    struct Crash {
        url: String,
        places: Places,
        library: Uuid,
        to: String,
        kill_at: usize,
    }

    /// Run only by `a_store_move_killed_at_any_step_resumes_and_stays_readable`, as a child.
    #[tokio::test]
    async fn crash_child() {
        let Ok(crash) = std::env::var(CRASH) else {
            return;
        };
        let crash: Crash = serde_json::from_str(&crash).unwrap();
        let steps = Arc::new(AtomicUsize::new(0));
        let hook: Hook = Arc::new(move |name| {
            eprintln!("step {name}");
            if steps.fetch_add(1, Ordering::SeqCst) + 1 == crash.kill_at {
                let pid = std::process::id().to_string();
                std::process::Command::new("kill").args(["-9", &pid]).status().unwrap();
            }
            Ok(())
        });
        let pool = PgPool::connect(&crash.url).await.unwrap();
        let journal = crash.places.journal(&pool, hook).await;
        let scratch = &crash.places.scratch;
        relayout(&pool, &journal, scratch, crash.library, &crash.to)
            .await
            .unwrap();
        week_later(&pool).await;
        journal.purge().await.unwrap();
    }

    /// Kills a store move with SIGKILL at each of its steps, in both directions: the library reads back whole at the
    /// moment it stopped, after recovery, and once the move is run again, which ends with every original in the new
    /// store, the sources gone after the grace and nothing orphaned.
    #[tokio::test]
    async fn a_store_move_killed_at_any_step_resumes_and_stays_readable() {
        let db = database().await;
        let pool = &db.pool;
        #[rustfmt::skip]
        let directions: [(usize, usize, &[&str]); 2] = [
            (0, 1, &["planned", "part", "closed", "written"]),
            (1, 0, &["planned", "part", "synced", "written"]),
        ];
        for (from, to, put) in directions {
            let mut steps: Vec<&str> = (0..4).flat_map(|_| put.iter().copied()).collect();
            steps.extend(["deleted"; 3]);
            for kill_at in 1..=steps.len() + 1 {
                let dir = tempfile::tempdir().unwrap();
                let places = Places::new(dir.path());
                let journal = places.journal(pool, no_hook()).await;
                let [from, to] = [&places.names[from], &places.names[to]];
                let (library, keys) = library(pool, &journal, from).await;
                let crash = Crash {
                    url: db.url.clone(),
                    places: places.clone(),
                    library,
                    to: to.clone(),
                    kill_at,
                };
                let child = std::process::Command::new(std::env::current_exe().unwrap())
                    .args([
                        "library::tests::crash_child",
                        "--exact",
                        "--nocapture",
                        "--test-threads=1",
                    ])
                    .env(CRASH, serde_json::to_string(&crash).unwrap())
                    .output()
                    .unwrap();
                let log = String::from_utf8_lossy(&child.stderr);
                let seen: Vec<_> = log.lines().filter_map(|line| line.strip_prefix("step ")).collect();
                let what = format!("{from} to {to}, killed at step {kill_at}: {log}");
                match kill_at <= steps.len() {
                    true => assert_eq!(
                        (child.status.signal(), &seen[..]),
                        (Some(9), &steps[..kill_at]),
                        "{what}"
                    ),
                    false => assert_eq!((child.status.success(), &seen[..]), (true, &steps[..]), "{what}"),
                }
                readable(pool, &journal, library).await;
                for _ in 0..100 {
                    if journal.recover().await.unwrap().busy == 0 {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
                readable(pool, &journal, library).await;

                relayout(pool, &journal, &places.scratch, library, to).await.unwrap();
                week_later(pool).await;
                journal.purge().await.unwrap();
                readable(pool, &journal, library).await;
                let open: i64 =
                    sqlx::query_scalar("SELECT count(*) FROM file_intents WHERE state IN ('planned', 'switched')")
                        .fetch_one(pool)
                        .await
                        .unwrap();
                assert_eq!(open, 0, "{what}");
                let marker = format!("{}/{LIBRARY_MARKER}", root(library));
                let mut moved = keys.clone();
                moved.push(marker.clone());
                moved.sort();
                for (store, contents) in [(to, moved), (from, vec![marker])] {
                    let store = journal.stores().get(store).unwrap();
                    assert_eq!(store.list(&root(library)).await.unwrap(), contents, "{what}");
                    assert!(store.uploads("").await.unwrap().is_empty(), "{what}");
                }
            }
        }
    }

    /// Queues `n` `library-create` jobs and runs them at once, until each is done.
    async fn create_missing(pool: &PgPool, jobs: &Arc<StorageJobs>, n: usize) {
        let mut conn = pool.acquire().await.unwrap();
        for _ in 0..n {
            photolib_jobs::enqueue(&mut conn, &NewJob::new(CREATE, b""))
                .await
                .unwrap();
        }
        let timing = photolib_jobs::Timing {
            poll_min: Duration::from_millis(10),
            poll_max: Duration::from_millis(50),
            ..Default::default()
        };
        let shutdown = tokio_util::sync::CancellationToken::new();
        let worker = photolib_jobs::Worker::new(pool.clone(), "test", n, timing).handle(CREATE, jobs.clone());
        let running = tokio::spawn(worker.run(shutdown.clone()));
        let open = "SELECT count(*) FROM jobs WHERE status = 'running' OR (status = 'queued' AND attempts = 0)";
        while sqlx::query_scalar::<_, i64>(open).fetch_one(pool).await.unwrap() > 0 {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        shutdown.cancel();
        running.await.unwrap();
        let failed: Vec<String> = sqlx::query_scalar("SELECT coalesce(error, status) FROM jobs WHERE status <> 'done'")
            .fetch_all(pool)
            .await
            .unwrap();
        assert!(failed.is_empty(), "{failed:?}");
    }

    /// Every account that may upload and has no managed library, from before the job existed or new, gets one: "Photos"
    /// on the store of new libraries, behind its marker, as its upload target. Jobs that run at once or again create no
    /// second one, and viewers, deleted accounts and those the policy switches managed libraries off for get none.
    #[tokio::test]
    async fn the_job_gives_each_account_that_may_upload_one_managed_library_to_upload_into() {
        type Managed = (String, Uuid, String, String, bool);
        let db = database().await;
        let (dir, work) = (tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap());
        let store = Arc::new(FsStore::open(dir.path(), TIMEOUT).await.unwrap());
        let (name, adopt) = ("disk".to_string(), true);
        let stores = Stores::check(&db.pool, Uuid::now_v7(), vec![Candidate { name, store, adopt }]).await;
        let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
        let jobs = Arc::new(StorageJobs::new(db.pool.clone(), journal.clone(), work.path(), "disk").unwrap());
        sqlx::raw_sql(
            "INSERT INTO users (id, handle, display_name, role, status, purge_at) VALUES
               (md5('ann')::uuid, 'ann', 'Ann', 'admin', 'active', NULL),
               (md5('bob')::uuid, 'bob', 'Bob', 'user', 'disabled', NULL),
               (md5('cy')::uuid, 'cy', 'Cy', 'user', 'active', NULL),
               (md5('vic')::uuid, 'vic', 'Vic', 'viewer', 'active', NULL),
               (md5('del')::uuid, 'del', 'Del', 'user', 'deleted', now() + interval '7 days'),
               (md5('pat')::uuid, 'pat', 'Pat', 'user', 'active', NULL);
             INSERT INTO policy_switches (capability, user_id, enabled)
               VALUES ('managed_libraries', md5('pat')::uuid, false);
             INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES
               (md5('mine')::uuid, md5('cy')::uuid, 'Mine', 'managed', 'mine'),
               (md5('nas')::uuid, md5('bob')::uuid, 'NAS', 'external', '/nas')",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let managed = "SELECT u.handle, l.id, l.name, l.store, l.is_upload_target FROM libraries l
                       JOIN users u ON u.id = l.owner_id WHERE l.kind = 'managed' ORDER BY u.handle";
        create_missing(&db.pool, &jobs, 2).await;
        let created: Vec<Managed> = sqlx::query_as(managed).fetch_all(&db.pool).await.unwrap();
        let summary: Vec<_> = (created.iter())
            .map(|(handle, _, name, store, target)| (handle.as_str(), name.as_str(), store.as_str(), *target))
            .collect();
        assert_eq!(
            summary,
            [
                ("ann", "Photos", "disk", true),
                ("bob", "Photos", "disk", true),
                ("cy", "Mine", "local", false)
            ]
        );
        let disk = journal.stores().get("disk").unwrap();
        for (_, library, ..) in &created[..2] {
            assert!(
                marker::library_online(disk.as_ref(), &root(*library), *library)
                    .await
                    .unwrap()
            );
        }
        create_missing(&db.pool, &jobs, 1).await;
        let again: Vec<Managed> = sqlx::query_as(managed).fetch_all(&db.pool).await.unwrap();
        assert_eq!(again, created);
    }
}
