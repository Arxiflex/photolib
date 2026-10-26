//! External libraries (photolib-design docs/07 §4, ADR-0093): folders an administrator assigns to a user, read in
//! place and never written. A scan is a `scan` job per folder that records the folder's new files and queues their
//! ingest and a job per subfolder, in one transaction: each folder is a checkpoint, and a restarted server goes on with
//! the folders still queued. Ingest reads metadata in ranges, renderers read copies; the `hash` jobs that read every
//! byte again come after, at the lowest priority. A library's jobs share its rate limits. What the ignore rules name
//! is never recorded or read (ADR-0259).

use std::{
    collections::HashMap,
    fs::File,
    os::unix::fs::FileExt,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use async_trait::async_trait;
use photolib_jobs::{Handler, Job, NewJob};
use photolib_storage::{
    Error, Hash, Local,
    fs::{FsStore, Identity},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::PgConnection;
use tokio::time::Instant;
use uuid::Uuid;

use crate::ingest::INGEST;

/// The `storage` of external files, whose key is their path under the library's root.
pub const STORE: &str = "external";
pub const SCAN: &str = "scan";
pub const HASH: &str = "hash";
/// Below every other job: hashing waits for scans, ingest and thumbnails.
const HASH_PRIORITY: i16 = -10;
/// Above every other job: what a hint names becomes visible before a scan's backlog.
const HINT_PRIORITY: i16 = 10;
/// Files per ingest job.
pub(crate) const BATCH: usize = 500;
/// What a hash job reads per call.
const CHUNK: u64 = 8 << 20;

/// The rate limits of a library whose administrator set none: a spinning disk or a NAS stays responsive.
pub const FILES_PER_SECOND: u32 = 1000;
pub const BYTES_PER_SECOND: u64 = 64 << 20;

/// Why a folder cannot be an external library's root.
#[derive(Debug, PartialEq, Eq)]
pub enum Refused {
    /// Not an absolute path to a folder photolibd can list.
    Unreadable,
    /// Under none of the configured `external_roots`.
    NotAllowed,
    /// It holds or lies in one of the folders taken.
    Overlaps,
}

/// The canonical path of `root` when it is a folder under one of `allowed` that neither holds nor lies in one of
/// `taken`; symlinks are resolved first, so none leads elsewhere.
pub fn root(root: &Path, allowed: &[PathBuf], taken: &[PathBuf]) -> Result<PathBuf, Refused> {
    let canonical = |path: &Path| std::fs::canonicalize(path).ok();
    let root = (canonical(root))
        .filter(|dir| root.is_absolute() && std::fs::read_dir(dir).is_ok())
        .ok_or(Refused::Unreadable)?;
    if !allowed.iter().filter_map(|a| canonical(a)).any(|a| root.starts_with(a)) {
        return Err(Refused::NotAllowed);
    }
    let taken = taken.iter().map(|t| canonical(t).unwrap_or_else(|| t.clone()));
    match taken.into_iter().any(|t| root.starts_with(&t) || t.starts_with(&root)) {
        true => Err(Refused::Overlaps),
        false => Ok(root),
    }
}

mod scan;
mod watch;

pub use scan::{HIDE, RESCAN, Rescan, Scanner};
pub(crate) use scan::{confirm, hint};
pub use watch::watch;

/// Starts a scan of the external library `library` in the caller's transaction; `None` while one runs. A scan that
/// waited for a confirmation waits no longer.
pub async fn scan(tx: &mut PgConnection, library: Uuid) -> sqlx::Result<Option<Uuid>> {
    let scan: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO library_scans (id, library_id, pending) VALUES ($1, $2, 1)
         ON CONFLICT (library_id) WHERE finished_at IS NULL DO NOTHING RETURNING id",
    )
    .bind(Uuid::now_v7())
    .bind(library)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(scan) = scan {
        sqlx::query("UPDATE library_scans SET held = false WHERE library_id = $1 AND held")
            .bind(library)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE libraries SET state = 'scanning' WHERE id = $1 AND state <> 'offline'")
            .bind(library)
            .execute(&mut *tx)
            .await?;
        scan::Folder::new(Some(scan), library, "").enqueue(tx).await?;
    }
    Ok(scan)
}

/// The external libraries' roots as this process's jobs open them, with one set of rate limits per library.
pub struct Libraries {
    timeout: Duration,
    limits: Mutex<HashMap<Uuid, Arc<Limits>>>,
}

/// An external library as a job reads it.
pub struct Library {
    /// Whose library it is.
    pub owner: Uuid,
    /// Where its root is.
    pub root: PathBuf,
    /// Its root, opened.
    pub store: FsStore,
    /// What its jobs may read.
    pub limits: Arc<Limits>,
}

/// What a library's jobs may read per second together: files listed or opened, and bytes read whole.
pub struct Limits {
    pub files: Throttle,
    pub bytes: Throttle,
}

impl Libraries {
    /// `timeout` bounds every call to a root.
    pub fn new(timeout: Duration) -> Libraries {
        Libraries {
            timeout,
            limits: Mutex::default(),
        }
    }

    /// The external library `id` with its root opened; `None` when there is none.
    pub async fn open(&self, conn: &mut PgConnection, id: Uuid) -> Result<Option<Library>, String> {
        let library = self.root(conn, id).await.map_err(|e| e.to_string())?;
        library.transpose().map_err(|e| e.to_string())
    }

    /// The external library `id`, or why its root cannot be opened; `None` when there is none.
    pub(crate) async fn root(&self, conn: &mut PgConnection, id: Uuid) -> sqlx::Result<Option<Result<Library, Error>>> {
        let row: Option<(Uuid, String, Option<Value>)> =
            sqlx::query_as("SELECT owner_id, root_uri, scan_policy FROM libraries WHERE id = $1 AND kind = 'external'")
                .bind(id)
                .fetch_optional(conn)
                .await?;
        let Some((owner, root, policy)) = row else {
            return Ok(None);
        };
        let rate = |key: &str| policy.as_ref().and_then(|p| p[key].as_u64()).unwrap_or(0);
        let (files, bytes) = (rate("files_per_second"), rate("bytes_per_second"));
        let limits = {
            let mut all = self.limits.lock().expect("no thread panics holding the limits");
            let limits = all.entry(id).or_insert_with(|| Limits::new(files, bytes));
            if (limits.files.rate, limits.bytes.rate) != (files, bytes) {
                *limits = Limits::new(files, bytes);
            }
            limits.clone()
        };
        let store = FsStore::open(Path::new(&root), self.timeout).await;
        Ok(Some(store.map(|store| Library {
            owner,
            root: root.into(),
            store,
            limits,
        })))
    }

    /// A copy in `dir` of the file `key` of the external library `id`, for a renderer: read whole at its rates.
    pub(crate) async fn copy(
        &self,
        conn: &mut PgConnection,
        id: Uuid,
        key: &str,
        size: i64,
        dir: &Path,
    ) -> Result<Local, String> {
        let library = (self.open(conn, id).await?).ok_or("no such external library")?;
        library.limits.files.take(1).await;
        library.limits.bytes.take(size as u64).await;
        let to = dir.join(Uuid::now_v7().to_string());
        let copy = to.clone();
        let copied = library.store.with_file(key, move |mut file, _| {
            let copied = File::create(&to).and_then(|mut out| std::io::copy(&mut file, &mut out));
            if copied.is_err() {
                let _ = std::fs::remove_file(&to);
            }
            copied
        });
        (copied.await.map_err(|e| e.to_string())?).map_err(|e| format!("cannot copy {key:?}: {e}"))?;
        Ok(Local::Copy(copy))
    }
}

impl Limits {
    fn new(files: u64, bytes: u64) -> Arc<Limits> {
        Arc::new(Limits {
            files: Throttle::new(files),
            bytes: Throttle::new(bytes),
        })
    }
}

/// Spaces work out to `rate` units per second, 0 being unlimited: each `take` waits for its turn, and the next turn
/// comes as much later as its units take at that rate.
pub struct Throttle {
    rate: u64,
    next: Mutex<Instant>,
}

impl Throttle {
    fn new(rate: u64) -> Throttle {
        Throttle {
            rate,
            next: Mutex::new(Instant::now()),
        }
    }

    pub async fn take(&self, units: u64) {
        if self.rate == 0 {
            return;
        }
        let turn = {
            let mut next = self.next.lock().expect("no thread panics holding a throttle");
            let turn = (*next).max(Instant::now());
            *next = turn + Duration::from_secs_f64(units as f64 / self.rate as f64);
            turn
        };
        tokio::time::sleep_until(turn).await;
    }
}

/// Files of one folder of a library: what an ingest or a hash job works on.
#[derive(Serialize, Deserialize)]
pub(crate) struct Batch {
    pub library: Uuid,
    pub dir: String,
    pub names: Vec<String>,
}

/// The path of `name` in the folder `dir`.
pub(crate) fn join(dir: &str, name: &str) -> String {
    match dir {
        "" => name.into(),
        dir => format!("{dir}/{name}"),
    }
}

/// Splits sorted names into batches of about `size`, never between names with the same stem (up to the first dot),
/// as a Live Photo's or a RAW+JPEG pair's files have.
pub(crate) fn batches(names: &[String], size: usize) -> Vec<&[String]> {
    let stem = |name: &str| name.split('.').next().unwrap_or_default().to_owned();
    let (mut batches, mut start) = (vec![], 0);
    for end in 1..=names.len() {
        if end == names.len() || (end - start >= size && stem(&names[end]) != stem(&names[end - 1])) {
            batches.push(&names[start..end]);
            start = end;
        }
    }
    batches
}

/// Queues an `ingest` or `hash` job of `batch`; an ingest of what a hint found comes before other work.
pub(crate) async fn enqueue(tx: &mut PgConnection, kind: &str, batch: &Batch, hint: bool) -> sqlx::Result<Uuid> {
    let payload = serde_json::to_vec(batch).expect("a batch serializes");
    let priority = match (kind, hint) {
        (HASH, _) => HASH_PRIORITY,
        (_, true) => HINT_PRIORITY,
        _ => 0,
    };
    photolib_jobs::enqueue(
        tx,
        &NewJob {
            priority,
            ..NewJob::new(kind, &payload)
        },
    )
    .await
}

/// Queues the ingest of every file found no photo or video in again, by folder: the first `retype` job of a type
/// detection version's (ADR-0066).
pub(crate) async fn retype(tx: &mut PgConnection) -> sqlx::Result<()> {
    let folders: Vec<(Uuid, String, Vec<String>)> = sqlx::query_as(
        "WITH f AS (UPDATE library_files SET state = 'pending' WHERE state = 'unsupported' RETURNING library_id, dir, name)
         SELECT library_id, dir, array_agg(name ORDER BY name COLLATE \"C\") FROM f GROUP BY 1, 2 ORDER BY 1, 2",
    )
    .fetch_all(&mut *tx)
    .await?;
    for (library, dir, names) in folders {
        for names in batches(&names, BATCH) {
            let names = names.to_vec();
            let batch = Batch {
                library,
                dir: dir.clone(),
                names,
            };
            enqueue(tx, INGEST, &batch, false).await?;
        }
    }
    Ok(())
}

/// The `hash` job of ingested files, on a `worker:io` role: their BLAKE3 hashes, read at the library's byte rate. A
/// file that changed since ingest keeps none; a scan sees the change.
pub struct Hasher(pub Arc<Libraries>);

#[async_trait]
impl Handler for Hasher {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        let batch: Batch = serde_json::from_slice(&job.payload).map_err(|_| "a malformed payload")?;
        let Some(library) = self.0.open(tx, batch.library).await? else {
            return Ok(());
        };
        let files: Vec<(String, Uuid, i64, i64, i64, i64)> = sqlx::query_as(
            "SELECT name, asset_id, dev, inode, size, mtime_ns FROM library_files
             WHERE library_id = $1 AND dir = $2 AND name = ANY($3) AND state = 'ingested' AND asset_id IS NOT NULL
             ORDER BY name",
        )
        .bind(batch.library)
        .bind(&batch.dir)
        .bind(&batch.names)
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        let (count, mut assets) = (files.len(), vec![]);
        for (n, (name, asset, dev, inode, size, mtime_ns)) in files.into_iter().enumerate() {
            let path = join(&batch.dir, &name);
            let identity = Identity {
                dev: dev as u64,
                inode: inode as u64,
                size: size as u64,
                mtime_ns,
            };
            match hash(&library, &path, identity).await? {
                Read::Hashed(hash) => {
                    sqlx::query(
                        "UPDATE asset_files SET content_hash = $3
                         WHERE asset_id = $1 AND storage = 'external' AND key = $2 AND byte_offset IS NULL",
                    )
                    .bind(asset)
                    .bind(&path)
                    .bind(hash.0.to_vec())
                    .execute(&mut *tx)
                    .await
                    .map_err(|e| e.to_string())?;
                    assets.push(asset);
                }
                Read::Changed | Read::Failed(_) => {
                    tracing::info!(library = %batch.library, "a file changed since ingest");
                }
            }
            job.progress((n + 1) as f32 / count as f32);
        }
        sqlx::query(
            "UPDATE assets a SET content_hash = f.content_hash FROM asset_files f
             WHERE f.asset_id = a.id AND f.role = 'original' AND a.id = ANY($1)",
        )
        .bind(&assets)
        .execute(&mut *tx)
        .await
        .map_err(|e| e.to_string())?;
        Ok(())
    }
}

/// What reading an external file whole found.
pub(crate) enum Read {
    Hashed(Hash),
    /// It is gone, or no longer the file it was.
    Changed,
    /// It cannot be opened or read.
    Failed(String),
}

/// The BLAKE3 hash of the file at `path`, read in chunks at the library's byte rate while it stays `expected`.
pub(crate) async fn hash(library: &Library, path: &str, expected: Identity) -> Result<Read, String> {
    let (mut hasher, mut at) = (blake3::Hasher::new(), 0);
    loop {
        let length = CHUNK.min(expected.size - at);
        library.limits.bytes.take(length).await;
        let read = library.store.with_file(path, move |file, identity| {
            let mut buffer = vec![0; length as usize];
            if identity != expected {
                return Ok(None);
            }
            file.read_exact_at(&mut buffer, at).map(|()| {
                hasher.update(&buffer);
                Some(hasher)
            })
        });
        hasher = match read.await {
            Err(error @ Error::Timeout(_)) => return Err(error.to_string()),
            Err(Error::NotFound(_) | Error::InvalidKey(_)) | Ok(Ok(None)) => return Ok(Read::Changed),
            Err(error) => return Ok(Read::Failed(error.to_string())),
            Ok(Err(error)) => return Ok(Read::Failed(error.to_string())),
            Ok(Ok(Some(hasher))) => hasher,
        };
        at += length;
        if at == expected.size {
            return Ok(Read::Hashed(Hash::from(hasher.finalize())));
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::{os::unix::fs::PermissionsExt, path::PathBuf};

    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_jobs::{Timing, Worker, reconcile::Profile};
    use photolib_storage::{journal::Journal, marker::Stores};
    use tokio_util::sync::CancellationToken;

    use serde_json::json;

    use super::*;
    use crate::ingest::{
        Ingest, RETYPE, Retype,
        extract::tests::xmp::{bag, with_xmp, xmp},
        sweep,
    };

    #[tokio::test(start_paused = true)]
    async fn a_throttle_spaces_work_out_at_its_rate() {
        let throttle = Throttle::new(100);
        let started = Instant::now();
        for _ in 0..3 {
            throttle.take(50).await;
        }
        assert_eq!(started.elapsed(), Duration::from_secs(1));
        tokio::time::sleep(Duration::from_secs(5)).await;
        let started = Instant::now();
        throttle.take(50).await;
        assert_eq!(started.elapsed(), Duration::ZERO, "idle time is no debt");
        throttle.take(1).await;
        assert_eq!(started.elapsed(), Duration::from_millis(500));
        let started = Instant::now();
        Throttle::new(0).take(u64::MAX).await;
        Throttle::new(0).take(u64::MAX).await;
        assert_eq!(started.elapsed(), Duration::ZERO, "0 is unlimited");
    }

    #[test]
    fn batches_never_split_a_stem() {
        let names: Vec<String> = ["a.jpg", "b.HEIC", "b.MOV", "b.json", "c.jpg", "d.CR2", "d.JPG"]
            .map(String::from)
            .into();
        let sizes = |size| -> Vec<usize> { batches(&names, size).iter().map(|b| b.len()).collect() };
        assert_eq!(sizes(2), [4, 3]);
        assert_eq!(sizes(1), [1, 3, 1, 2]);
        assert_eq!(sizes(100), [7]);
        assert!(batches(&[], 2).is_empty());
    }

    /// A database with Ann and her external library on a folder, and the jobs that scan, ingest and hash it.
    pub(crate) struct Instance {
        pub pool: sqlx::PgPool,
        pub library: Uuid,
        pub owner: Uuid,
        pub root: PathBuf,
        pub libraries: Arc<Libraries>,
        ingest: Arc<Ingest>,
        _dirs: tempfile::TempDir,
        _db: testpg::TestDb,
    }

    pub(crate) async fn instance(policy: Value) -> Instance {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let dirs = tempfile::tempdir().unwrap();
        let root = dirs.path().join("photos");
        std::fs::create_dir(&root).unwrap();
        let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
            .bind(owner)
            .execute(&db.pool)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO libraries (id, owner_id, name, kind, access, root_uri, scan_policy)
             VALUES ($1, $2, 'NAS', 'external', 'ro', $3, $4)",
        )
        .bind(library)
        .bind(owner)
        .bind(root.to_str().unwrap())
        .bind(policy)
        .execute(&db.pool)
        .await
        .unwrap();
        let journal = Journal::start(db.pool.clone(), Stores::default()).await;
        let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
        let ingest = Ingest::new(
            Arc::new(journal.unwrap()),
            dirs.path(),
            "photolibd".into(),
            vec![],
            Profile::default(),
            libraries.clone(),
        );
        Instance {
            pool: db.pool.clone(),
            library,
            owner,
            root,
            libraries,
            ingest: Arc::new(ingest.unwrap()),
            _dirs: dirs,
            _db: db,
        }
    }

    impl Instance {
        /// Runs the jobs of `kinds` until none is left.
        pub(crate) async fn run(&self, kinds: &[&str]) {
            let timing = Timing {
                poll_min: Duration::from_millis(10),
                poll_max: Duration::from_millis(50),
                ..Timing::default()
            };
            let mut worker = Worker::new(self.pool.clone(), "test", 4, timing);
            for kind in kinds {
                worker = match *kind {
                    SCAN => worker.handle(SCAN, Scanner(self.libraries.clone())),
                    HASH => worker.handle(HASH, Hasher(self.libraries.clone())),
                    RETYPE => worker.handle(RETYPE, Retype(self.ingest.clone())),
                    RESCAN => worker.handle(RESCAN, Rescan),
                    _ => worker.handle(INGEST, self.ingest.clone()),
                };
            }
            let shutdown = CancellationToken::new();
            let running = tokio::spawn(worker.run(shutdown.clone()));
            let open = "SELECT count(*) FROM jobs WHERE type = ANY($1) AND status IN ('queued', 'running')";
            while sqlx::query_scalar::<_, i64>(open)
                .bind(kinds)
                .fetch_one(&self.pool)
                .await
                .unwrap()
                > 0
            {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
            shutdown.cancel();
            running.await.unwrap();
            let failed = "SELECT count(*) FROM jobs WHERE status <> 'done' AND type = ANY($1)";
            let failed: i64 = sqlx::query_scalar(failed)
                .bind(kinds)
                .fetch_one(&self.pool)
                .await
                .unwrap();
            assert_eq!(failed, 0);
        }

        pub(crate) async fn scan(&self) -> Option<Uuid> {
            let mut tx = self.pool.begin().await.unwrap();
            let scan = scan(&mut tx, self.library).await.unwrap();
            tx.commit().await.unwrap();
            scan
        }

        /// The library's files: path, state and error.
        pub(crate) async fn files(&self) -> Vec<(String, String, Option<String>)> {
            sqlx::query_as(
                "SELECT CASE dir WHEN '' THEN name ELSE dir || '/' || name END, state, error FROM library_files
                 WHERE library_id = $1 ORDER BY 1",
            )
            .bind(self.library)
            .fetch_all(&self.pool)
            .await
            .unwrap()
        }

        /// Each original's path, source, name, capture time, owner and hash.
        pub(crate) async fn assets(&self) -> Vec<(String, String, String, bool, Uuid, Option<Vec<u8>>)> {
            sqlx::query_as(
                "SELECT f.key, a.source, a.original_filename, a.taken_local IS NOT NULL, a.owner_id, a.content_hash
                 FROM assets a JOIN asset_files f ON f.asset_id = a.id AND f.role = 'original'
                 WHERE a.library_id = $1 AND f.storage = 'external' ORDER BY 1",
            )
            .bind(self.library)
            .fetch_all(&self.pool)
            .await
            .unwrap()
        }
    }

    /// A small JPEG with a capture time, from the corpus.
    pub(crate) fn jpeg() -> Vec<u8> {
        let corpus = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../testdata/corpus/files");
        std::fs::read(format!("{corpus}/time/dst-overlap.jpg")).unwrap()
    }

    pub(crate) fn write(root: &Path, path: &str, data: &[u8]) {
        let file = root.join(path);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(file, data).unwrap();
    }

    /// Every file of every folder is found once; media become assets of the library's owner, other files are recorded
    /// as unsupported, an unreadable one as failed with its reason, and symlinks, FIFOs and what lies outside the root
    /// are never touched. Hashes come last, and a rescan ingests only what is new.
    #[tokio::test]
    async fn a_scan_ingests_every_folder_records_what_it_skips_and_hashes_last() {
        let at = instance(Value::Null).await;
        let (jpeg, root) = (jpeg(), &at.root);
        for path in ["a.jpg", "2024/b.jpg", "2024/05/c.jpg", "locked.jpg"] {
            write(root, path, &jpeg);
        }
        write(root, "2024/notes.txt", b"not a photo");
        let outside = root.parent().unwrap().join("outside");
        write(&outside, "secret.jpg", &jpeg);
        std::os::unix::fs::symlink(&outside, root.join("out")).unwrap();
        std::os::unix::fs::symlink("a.jpg", root.join("link.jpg")).unwrap();
        let fifo = root.join("2024/pipe");
        nix::unistd::mkfifo(&fifo, nix::sys::stat::Mode::S_IRUSR).unwrap();
        let locked = root.join("locked.jpg");
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o000)).unwrap();
        // Whoever may read anything (root) reads it anyway.
        let unreadable = std::fs::File::open(&locked).is_err();

        assert!(at.scan().await.is_some());
        assert_eq!(at.scan().await, None, "one scan at a time");
        at.run(&[SCAN, INGEST]).await;
        let mut files = vec![
            ("2024/05/c.jpg".to_string(), "ingested".to_string(), None),
            ("2024/b.jpg".into(), "ingested".into(), None),
            ("2024/notes.txt".into(), "unsupported".into(), None),
            ("a.jpg".into(), "ingested".into(), None),
            ("locked.jpg".into(), "ingested".into(), None),
        ];
        if unreadable {
            files[4].1 = "failed".into();
            files[4].2 = Some("cannot open \"locked.jpg\": Permission denied (os error 13)".into());
        }
        assert_eq!(at.files().await, files);
        let ingested: Vec<_> = (files.iter())
            .filter(|f| f.1 == "ingested")
            .map(|f| f.0.clone())
            .collect();
        let assets = at.assets().await;
        assert_eq!(assets.iter().map(|a| a.0.clone()).collect::<Vec<_>>(), ingested);
        for (path, source, name, dated, owner, hash) in &assets {
            assert_eq!(
                (source.as_str(), name.as_str()),
                ("scan", path.rsplit('/').next().unwrap())
            );
            assert!(*dated && *owner == at.owner && hash.is_none(), "{path}");
        }
        let state: (String, i32, bool) = sqlx::query_as(
            "SELECT l.state, s.pending, s.finished_at IS NOT NULL FROM libraries l
             JOIN library_scans s ON s.library_id = l.id WHERE l.id = $1",
        )
        .bind(at.library)
        .fetch_one(&at.pool)
        .await
        .unwrap();
        assert_eq!(state, ("online".into(), 0, true));

        at.run(&[HASH]).await;
        let hashes: Vec<_> = at.assets().await.into_iter().map(|a| a.5).collect();
        assert_eq!(hashes, vec![Some(Hash::of(&jpeg).0.to_vec()); ingested.len()]);
        let files: i64 =
            sqlx::query_scalar("SELECT count(*) FROM asset_files WHERE storage = 'external' AND content_hash = $1")
                .bind(Hash::of(&jpeg).0.to_vec())
                .fetch_one(&at.pool)
                .await
                .unwrap();
        assert_eq!(files, ingested.len() as i64);

        write(root, "2024/05/d.jpg", &jpeg);
        assert!(at.scan().await.is_some(), "the first scan is over");
        at.run(&[SCAN, INGEST]).await;
        let assets = at.assets().await;
        assert_eq!(assets.len(), ingested.len() + 1);
        let new: Vec<_> = assets.iter().filter(|a| a.5.is_none()).map(|a| a.0.as_str()).collect();
        assert_eq!(new, ["2024/05/d.jpg"], "a rescan ingests only what is new");
    }

    /// What the defaults and each folder's `.photolibignore` name, from its folder down, is never recorded or read:
    /// NAS thumbnails, recycle bins, desktop litter and what a user excludes, by case as the volume tells it apart.
    #[tokio::test]
    async fn a_scan_skips_what_the_ignore_rules_name() {
        let at = instance(Value::Null).await;
        let kept = [
            "2024/DRAFTS/i.jpg",
            "2024/h.jpg",
            "2024/keep.png",
            "2024/private/e.jpg",
            "a.jpg",
        ];
        let ignored = [
            "@eaDir/a.jpg/SYNOPHOTO_THUMB_XL.jpg",
            "#recycle/b.jpg",
            ".Trash-1000/files/c.jpg",
            "2024/.DS_Store",
            "2024/Thumbs.db",
            "private/d.jpg",
            "2024/drafts/f.jpg",
            "2024/g.png",
            "2024/x/drafts/j.jpg",
            "2024/x/k.png",
        ];
        for path in kept.iter().chain(&ignored) {
            write(&at.root, path, &jpeg());
        }
        write(&at.root, ".photolibignore", b"/private/\n");
        write(&at.root, "2024/.photolibignore", b"drafts/\n*.png\n!keep.png\n");
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        let files: Vec<String> = at.files().await.into_iter().map(|f| f.0).collect();
        assert_eq!(files, kept);
    }

    /// A library of photos with Lightroom's and digiKam's sidecars, named either way, scanned: one photo with keywords of
    /// its own, one with two sidecars, a RAW+JPEG pair's from the corpus, one named after two photos that are no pair
    /// and a sidecar of no photo.
    async fn sidecars() -> Instance {
        let at = instance(Value::Null).await;
        let (root, jpeg) = (&at.root, jpeg());
        let embedded = xmp(&format!(r#"xmp:Rating="2">{}"#, bag("dc:subject", &["embedded"])));
        write(root, "lr/IMG_1.jpg", &with_xmp(&jpeg, &embedded));
        let lightroom = format!(
            r#"xmp:Rating="4" xmp:Label="Red" crs:Exposure2012="+0.50" exif:GPSLatitude="45,45.0N"
 exif:GPSLongitude="4,51.0E">{}{}<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Eiffel</rdf:li></rdf:Alt></dc:title>"#,
            bag("dc:subject", &["Paris", "France", "Places", "sunset"]),
            bag("lr:hierarchicalSubject", &["Places|France|Paris"]),
        );
        write(root, "lr/IMG_1.xmp", xmp(&lightroom).as_bytes());
        let digikam = format!(
            r#"xmp:Rating="5">{}{}"#,
            bag("dc:subject", &["Lyon", "Wedding"]),
            bag("digiKam:TagsList", &["Places/France/Lyon", "Events/Wedding"]),
        );
        write(root, "dk/IMG_2.jpg.xmp", xmp(&digikam).as_bytes());
        let dated = |date, rating, keyword| {
            let subject = bag("dc:subject", &[keyword]);
            xmp(&format!(r#"xmp:MetadataDate="{date}" xmp:Rating="{rating}">{subject}"#))
        };
        write(
            root,
            "both/IMG_3.xmp",
            dated("2024-05-01T10:00:00", 3, "newer").as_bytes(),
        );
        write(
            root,
            "both/IMG_3.jpg.xmp",
            dated("2020-01-01T10:00:00", 1, "older").as_bytes(),
        );
        write(root, "rej/IMG_4.jpg.xmp", xmp(r#"xmp:Rating="-1">"#).as_bytes());
        write(root, "lonely.xmp", xmp(r#"xmp:Rating="5">"#).as_bytes());
        write(root, "two/IMG_5.xmp", xmp(r#"xmp:Rating="2">"#).as_bytes());
        for path in [
            "dk/IMG_2.jpg",
            "both/IMG_3.jpg",
            "rej/IMG_4.jpg",
            "two/IMG_5.jpg",
            "two/IMG_5.png",
        ] {
            write(root, path, &jpeg);
        }
        let corpus = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../testdata/corpus/files/compound/raw-jpeg"
        );
        for name in ["_MG_0123.CR2", "_MG_0123.JPG", "_MG_0123.xmp"] {
            write(
                root,
                &format!("pair/{name}"),
                &std::fs::read(format!("{corpus}/{name}")).unwrap(),
            );
        }
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        at
    }

    /// Sidecars give the asset of their photo, or of its RAW+JPEG pair, their rating, label, title and location over the
    /// photo's own (of two photos that are no pair, the first's), and their keywords beside the photo's own: hierarchical ones as trees of the owner's tags, flat ones
    /// as tags unless a tree names them. Of two sidecars of a photo, the newer metadata wins.
    #[tokio::test]
    async fn sidecar_keywords_and_ratings_become_tags_and_ratings() {
        let at = sidecars().await;
        let assets: Vec<String> = sqlx::query_scalar(
            "SELECT concat_ws(' ', f.key, a.rating, a.title, a.color_label, a.location_source, round(a.lat::numeric, 2),
               round(a.lon::numeric, 2), string_agg(t.path, ',' ORDER BY t.path))
             FROM assets a JOIN asset_files f ON f.asset_id = a.id AND f.role = 'original'
             LEFT JOIN asset_tags x ON x.asset_id = a.id AND x.origin = 'import' LEFT JOIN tags t ON t.id = x.tag_id
             WHERE a.library_id = $1 GROUP BY a.id, f.key ORDER BY f.key",
        )
        .bind(at.library)
        .fetch_all(&at.pool)
        .await
        .unwrap();
        assert_eq!(
            assets,
            [
                "both/IMG_3.jpg 3 exif 48.86 2.29 newer,older",
                "dk/IMG_2.jpg 5 exif 48.86 2.29 Events|Wedding,Places|France|Lyon",
                "lr/IMG_1.jpg 4 Eiffel Red sidecar 45.75 4.85 Places|France|Paris,embedded,sunset",
                "pair/_MG_0123.JPG 4",
                "rej/IMG_4.jpg -1 exif 48.86 2.29",
                "two/IMG_5.jpg 2 exif 48.86 2.29",
                "two/IMG_5.png 0 exif 48.86 2.29",
            ]
        );
        let tree: Vec<String> = sqlx::query_scalar(
            "SELECT concat_ws(' ', t.path, t.origin, 'under ' || p.path) FROM tags t
             LEFT JOIN tags p ON p.id = t.parent_id WHERE t.owner_id = $1 ORDER BY 1",
        )
        .bind(at.owner)
        .fetch_all(&at.pool)
        .await
        .unwrap();
        assert_eq!(
            tree,
            [
                "Events import",
                "Events|Wedding import under Events",
                "Places import",
                "Places|France import under Places",
                "Places|France|Lyon import under Places|France",
                "Places|France|Paris import under Places|France",
                "embedded import",
                "newer import",
                "older import",
                "sunset import",
            ]
        );
    }

    /// Sidecars become files of their photo's asset, kept as they are, served only as downloads and hashed with it; one
    /// named after two photos is the first's, and a sidecar of no photo stays unsupported.
    #[tokio::test]
    async fn sidecars_become_files_of_their_photos_asset() {
        let at = sidecars().await;
        let files: Vec<String> = sqlx::query_scalar(
            "SELECT concat_ws(' ', l.path, l.state, o.key, s.mime) FROM
               (SELECT CASE dir WHEN '' THEN name ELSE dir || '/' || name END AS path, * FROM library_files) l
             LEFT JOIN asset_files s ON s.asset_id = l.asset_id AND s.role = 'sidecar' AND s.key = l.path
             LEFT JOIN asset_files o ON o.asset_id = s.asset_id AND o.role = 'original'
             WHERE l.library_id = $1 AND l.name LIKE '%.xmp' ORDER BY 1",
        )
        .bind(at.library)
        .fetch_all(&at.pool)
        .await
        .unwrap();
        let download = "application/octet-stream";
        assert_eq!(
            files,
            [
                format!("both/IMG_3.jpg.xmp ingested both/IMG_3.jpg {download}"),
                format!("both/IMG_3.xmp ingested both/IMG_3.jpg {download}"),
                format!("dk/IMG_2.jpg.xmp ingested dk/IMG_2.jpg {download}"),
                "lonely.xmp unsupported".into(),
                format!("lr/IMG_1.xmp ingested lr/IMG_1.jpg {download}"),
                format!("pair/_MG_0123.xmp ingested pair/_MG_0123.JPG {download}"),
                format!("rej/IMG_4.jpg.xmp ingested rej/IMG_4.jpg {download}"),
                format!("two/IMG_5.xmp ingested two/IMG_5.jpg {download}"),
            ]
        );
        at.run(&[HASH]).await;
        let hashes: Vec<(String, Option<Vec<u8>>)> =
            sqlx::query_as("SELECT key, content_hash FROM asset_files WHERE role = 'sidecar' ORDER BY 1")
                .fetch_all(&at.pool)
                .await
                .unwrap();
        assert_eq!(hashes.len(), 7);
        for (key, hash) in hashes {
            let file = std::fs::read(at.root.join(&key)).unwrap();
            assert_eq!(hash, Some(Hash::of(&file).0.to_vec()), "{key}");
        }
    }

    /// A file that changed after ingest keeps no hash until a scan sees the change.
    #[tokio::test]
    async fn a_file_that_changed_since_ingest_is_not_hashed() {
        let at = instance(Value::Null).await;
        write(&at.root, "a.jpg", &jpeg());
        write(&at.root, "b.jpg", &jpeg());
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        let mut changed = jpeg();
        changed.push(0);
        write(&at.root, "b.jpg", &changed);
        at.run(&[HASH]).await;
        let hashed: Vec<bool> = at.assets().await.iter().map(|a| a.5.is_some()).collect();
        assert_eq!(hashed, [true, false]);
    }

    /// The first `retype` job of a release that learns a format reads again every file a scan found no photo or video
    /// in: one that is media now becomes an asset, with its hash to come, any other stays unsupported. A version
    /// sweeps once.
    #[tokio::test]
    async fn a_format_a_release_learns_surfaces_in_an_external_library() {
        let at = instance(Value::Null).await;
        write(&at.root, "2024/notes.txt", b"not a photo");
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        write(&at.root, "2024/b.jpg", &jpeg());
        write(&at.root, "old.txt", b"not a photo either");
        sqlx::query(
            "INSERT INTO library_files (library_id, dir, name, dev, inode, size, mtime_ns, state)
             VALUES ($1, '2024', 'b.jpg', 0, 0, 0, 0, 'unsupported'), ($1, '', 'old.txt', 0, 0, 0, 0, 'unsupported')",
        )
        .bind(at.library)
        .execute(&at.pool)
        .await
        .unwrap();

        for _ in 0..2 {
            sweep(&at.pool).await.unwrap();
            at.run(&[RETYPE, INGEST, HASH]).await;
        }
        let files: Vec<(String, String)> =
            sqlx::query_as("SELECT name, state FROM library_files WHERE library_id = $1 ORDER BY name")
                .bind(at.library)
                .fetch_all(&at.pool)
                .await
                .unwrap();
        let state = |name: &str, state: &str| (name.to_string(), state.to_string());
        assert_eq!(
            files,
            [
                state("b.jpg", "ingested"),
                state("notes.txt", "unsupported"),
                state("old.txt", "unsupported")
            ]
        );
        let assets = at.assets().await;
        assert_eq!(assets.len(), 1);
        assert_eq!((assets[0].0.as_str(), assets[0].3), ("2024/b.jpg", true));
        assert_eq!(assets[0].5, Some(Hash::of(&jpeg()).0.to_vec()));
        let read: Vec<Vec<String>> = sqlx::query_scalar("SELECT payload FROM jobs WHERE type = $1 ORDER BY id")
            .bind(INGEST)
            .fetch_all(&at.pool)
            .await
            .unwrap()
            .into_iter()
            .map(|payload: Vec<u8>| serde_json::from_slice::<Batch>(&payload).unwrap().names)
            .collect();
        assert_eq!(read, [vec!["notes.txt"], vec!["old.txt"], vec!["b.jpg", "notes.txt"]]);
    }

    /// Listing and opening files keep to `files_per_second`, hashing to `bytes_per_second`.
    #[tokio::test]
    async fn a_library_is_read_at_its_rates() {
        let jpeg = jpeg();
        let at = instance(json!({ "files_per_second": 20, "bytes_per_second": 10 * jpeg.len() })).await;
        for n in 0..30 {
            write(&at.root, &format!("{n:02}.jpg"), &jpeg);
        }
        let started = std::time::Instant::now();
        at.scan().await;
        at.run(&[SCAN, INGEST]).await;
        // 30 files listed, then 30 opened: the last turn comes (60 - 1) / 20 s after the first.
        assert!(
            started.elapsed() >= Duration::from_millis(2950),
            "{:?}",
            started.elapsed()
        );
        let started = std::time::Instant::now();
        at.run(&[HASH]).await;
        assert!(
            started.elapsed() >= Duration::from_millis(2900),
            "{:?}",
            started.elapsed()
        );
        // A renderer's copies are read whole at the byte rate too.
        let (dir, started) = (tempfile::tempdir().unwrap(), std::time::Instant::now());
        let mut conn = at.pool.acquire().await.unwrap();
        for n in 0..10 {
            let key = format!("{n:02}.jpg");
            let copy = at
                .libraries
                .copy(&mut conn, at.library, &key, jpeg.len() as i64, dir.path());
            let (Local::Copy(copy) | Local::InPlace(copy)) = copy.await.unwrap();
            assert_eq!(std::fs::read(copy).unwrap(), jpeg);
        }
        assert!(
            started.elapsed() >= Duration::from_millis(850),
            "{:?}",
            started.elapsed()
        );
    }
}
