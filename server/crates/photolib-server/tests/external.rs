//! An external library at scale (ADR-0093): `PHOTOLIB_SCAN_FILES` photos (3,000 unless set; 2,000,000 by hand, too
//! long for a 30-minute workflow job) in folders of 100 become browsable before any of them is hashed, and a scan cut
//! off by a restart goes on with the folders left, ingesting every file exactly once. A rescan of an unchanged tree of
//! `PHOTOLIB_RESCAN_FILES` files (20,000 unless set; 500,000 by hand, ADR-0257) costs a stat per file and writes
//! nothing but its folders.

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use photolib_authz::{Action, Kind, Principal, Role as Account, scope};
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{Timing, Worker};
use photolib_server::{
    external::{self, HASH, Libraries, SCAN, Scanner},
    ingest::Ingest,
    jobs::{JobQueue, PgJobs},
    render::{self, Render},
    role::{Role, WorkerClass},
};
use photolib_storage::{
    Hash,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
};
use sqlx::{PgPool, Postgres, QueryBuilder, postgres::PgPoolOptions};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

/// Files per folder, and folders per parent folder.
const PER_FOLDER: usize = 100;

async fn count(pool: &PgPool, sql: &str) -> i64 {
    sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
}

/// Waits until `sql` counts at least `n`.
async fn until(pool: &PgPool, sql: &str, n: i64) {
    while count(pool, sql).await < n {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

/// The worker roles of a photolibd process, running until `shutdown`.
fn start(jobs: Arc<PgJobs>, shutdown: &CancellationToken) -> Vec<tokio::task::JoinHandle<()>> {
    [WorkerClass::Io, WorkerClass::Cpu]
        .map(|class| {
            let (jobs, shutdown) = (jobs.clone(), shutdown.clone());
            tokio::spawn(async move { jobs.run(Role::Worker(class), shutdown).await })
        })
        .into()
}

#[tokio::test(flavor = "multi_thread")]
async fn a_large_library_is_browsable_before_it_is_hashed_and_its_scan_survives_a_restart() {
    let files: usize = std::env::var("PHOTOLIB_SCAN_FILES").map_or(3000, |n| n.parse().unwrap());
    let db = testpg::database().await;
    let pool = PgPoolOptions::new().max_connections(64).connect(&db.url).await.unwrap();
    upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
    let dirs = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let root = dirs.path().join("nas");
    let corpus = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../testdata/corpus/files");
    let jpeg = std::fs::read(format!("{corpus}/time/dst-overlap.jpg")).unwrap();
    let started = Instant::now();
    let folders: Vec<_> = (0..files.div_ceil(PER_FOLDER))
        .map(|n| root.join(format!("{:04}/{:02}", n / PER_FOLDER, n % PER_FOLDER)))
        .collect();
    std::thread::scope(|threads| {
        for (n, folders) in folders.chunks(PER_FOLDER).enumerate() {
            let jpeg = &jpeg;
            threads.spawn(move || {
                for (m, folder) in folders.iter().enumerate() {
                    std::fs::create_dir_all(folder).unwrap();
                    let first = (n * PER_FOLDER + m) * PER_FOLDER;
                    for file in first..files.min(first + PER_FOLDER) {
                        std::fs::write(folder.join(format!("IMG_{file:07}.jpg")), jpeg).unwrap();
                    }
                }
            });
        }
    });
    std::fs::write(root.join("notes.txt"), "not a photo").unwrap();
    let parents = folders.len().div_ceil(PER_FOLDER);
    eprintln!("{files} files written in {:?}", started.elapsed());

    let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(owner)
        .execute(&pool)
        .await
        .unwrap();
    // Listing and opening every file takes about two seconds, so that the restart comes in the middle of the scan.
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, access, root_uri, scan_policy)
         VALUES ($1, $2, 'NAS', 'external', 'ro', $3, jsonb_build_object('files_per_second', $4::bigint))",
    )
    .bind(library)
    .bind(owner)
    .bind(root.to_str().unwrap())
    .bind(files as i64)
    .execute(&pool)
    .await
    .unwrap();
    let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
    let data = dirs.path().join("data");
    std::fs::create_dir(&data).unwrap();
    let local = Candidate {
        name: "local".into(),
        store: Arc::new(FsStore::open(&data, Duration::from_secs(30)).await.unwrap()),
        adopt: true,
    };
    let stores = Stores::check(&pool, Uuid::now_v7(), vec![local]).await;
    let journal = Arc::new(Journal::start(pool.clone(), stores).await.unwrap());
    let (photolibd, specs) = (env!("CARGO_BIN_EXE_photolibd"), render::specs());
    let ingest = Ingest::new(
        journal.clone(),
        dirs.path(),
        photolibd.into(),
        vec![],
        render::profile(&specs),
        libraries.clone(),
    );
    let ingest = Arc::new(ingest.unwrap());
    let render = Render::new(journal, dirs.path(), photolibd.into(), specs, libraries.clone());
    let render = Arc::new(render.unwrap());
    let process = |owner: &str| {
        Arc::new(PgJobs {
            pool: pool.clone(),
            owner: owner.into(),
            cpu: Some((ingest.clone(), render.clone())),
            transcode: None,
            storage: None,
            scrub: None,
            events: None,
            libraries: libraries.clone(),
            backups: None,
            backup_cron: "0 3 * * *".into(),
            queue_ocr: false,
            ocr: None,
            faces: None,
            queue_faces: false,
        })
    };
    let mut conn = pool.acquire().await.unwrap();
    // Until resumed below: 2M files can take hours to ingest on a loaded machine.
    photolib_jobs::pause(&mut conn, HASH, Duration::from_secs(7 * 86400), None)
        .await
        .unwrap();
    let mut tx = pool.begin().await.unwrap();
    external::scan(&mut tx, library).await.unwrap();
    tx.commit().await.unwrap();
    let started = Instant::now();

    // A quarter of the folders in, photolibd stops without letting its jobs finish, as when its grace period ends,
    // and puts what it held back on the queue.
    let scans = "SELECT count(*) FROM jobs WHERE type = 'scan'";
    let shutdown = CancellationToken::new();
    let first = start(process("first"), &shutdown);
    until(&pool, &format!("{scans} AND status = 'done'"), folders.len() as i64 / 4).await;
    for role in first {
        role.abort();
        assert!(role.await.unwrap_err().is_cancelled());
    }
    photolib_jobs::requeue_leased(&pool, "first").await.unwrap();
    let ingested = "SELECT count(*) FROM library_files WHERE state = 'ingested'";
    let left = count(&pool, &format!("{scans} AND status = 'queued'")).await;
    assert!(left > 0, "the scan was cut off");
    assert!(count(&pool, ingested).await < files as i64);

    let second = start(process("second"), &shutdown);
    let done = "SELECT count(*) FROM library_scans WHERE finished_at IS NOT NULL";
    until(&pool, done, 1).await;
    let open = "SELECT count(*) FROM jobs WHERE type <> 'hash' AND status IN ('queued', 'running')";
    while count(&pool, open).await > 0 {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    let browsable = started.elapsed();

    // Browsable: every photo is one asset of Ann's, with its metadata and its renditions; none is hashed.
    let total = 1 + parents + folders.len();
    assert_eq!(count(&pool, scans).await, total as i64, "each folder listed once");
    assert_eq!(
        count(&pool, "SELECT count(*) FROM jobs WHERE type = 'ingest'").await,
        folders.len() as i64 + 1,
        "a batch per folder and the root's notes: none ingested twice"
    );
    assert_eq!(count(&pool, ingested).await, files as i64);
    assert_eq!(
        count(&pool, "SELECT count(*) FROM library_files WHERE state = 'unsupported'").await,
        1
    );
    let assets = "SELECT count(*) FROM assets a JOIN asset_files f ON f.asset_id = a.id AND f.role = 'original'
        WHERE a.taken_local IS NOT NULL AND a.source = 'scan'";
    assert_eq!(count(&pool, assets).await, files as i64);
    let mut visible = QueryBuilder::<Postgres>::new("SELECT count(*) FROM assets WHERE id IN (");
    scope(
        Principal::User(owner, Account::User),
        Action::View,
        Kind::Asset,
        &mut visible,
    );
    visible.push(")");
    let visible: i64 = visible.build_query_scalar().fetch_one(&pool).await.unwrap();
    assert_eq!(visible, files as i64);
    let rendered = "SELECT count(*) FROM assets a WHERE a.thumbhash IS NOT NULL AND (SELECT count(*) FROM asset_files f
        WHERE f.asset_id = a.id AND f.storage = 'local' AND f.render_spec ->> 'source_hash' IS NULL) = 3";
    assert_eq!(count(&pool, rendered).await, files as i64);
    assert_eq!(
        count(&pool, "SELECT count(*) FROM assets WHERE content_hash IS NOT NULL").await,
        0
    );
    assert_eq!(
        count(
            &pool,
            "SELECT count(*) FROM jobs WHERE type = 'hash' AND status = 'queued'"
        )
        .await,
        folders.len() as i64
    );
    let state: String = sqlx::query_scalar("SELECT state FROM libraries WHERE id = $1")
        .bind(library)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(state, "online");

    photolib_jobs::resume(&mut conn, HASH).await.unwrap();
    let hashed = "SELECT count(*) FROM assets WHERE content_hash = $1";
    let hash = Hash::of(&jpeg).0.to_vec();
    while sqlx::query_scalar::<_, i64>(hashed)
        .bind(&hash)
        .fetch_one(&pool)
        .await
        .unwrap()
        < files as i64
    {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    eprintln!(
        "{files} files: browsable after {browsable:?}, hashed after {:?}",
        started.elapsed()
    );
    shutdown.cancel();
    for role in second {
        role.await.unwrap();
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unchanged_tree_rescans_with_a_stat_per_file_and_changes_nothing() {
    let files: usize = std::env::var("PHOTOLIB_RESCAN_FILES").map_or(20_000, |n| n.parse().unwrap());
    let db = testpg::database().await;
    let pool = PgPoolOptions::new().max_connections(16).connect(&db.url).await.unwrap();
    upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
    let (_dirs, library, folders) = known_tree(&pool, files).await;
    let changed = "SELECT count(*) FROM library_files WHERE found_at > now() - interval '1 hour'
        OR unseen IS NOT NULL OR missing_since IS NOT NULL";
    let started = Instant::now();
    let mut tx = pool.begin().await.unwrap();
    external::scan(&mut tx, library).await.unwrap();
    tx.commit().await.unwrap();
    let libraries = Arc::new(Libraries::new(Duration::from_secs(30)));
    let worker = Worker::new(pool.clone(), "io", 4, Timing::default()).handle(SCAN, Scanner(libraries));
    let shutdown = CancellationToken::new();
    let running = tokio::spawn(worker.run(shutdown.clone()));
    until(
        &pool,
        "SELECT count(*) FROM library_scans WHERE finished_at IS NOT NULL",
        1,
    )
    .await;
    let took = started.elapsed();
    shutdown.cancel();
    running.await.unwrap();
    eprintln!(
        "{files} unchanged files in {} folders rescanned in {took:?}",
        folders.len()
    );
    assert_eq!(count(&pool, changed).await, 0, "no file written");
    assert_eq!(
        count(&pool, "SELECT count(*) FROM jobs WHERE type <> 'scan'").await,
        0,
        "nothing read"
    );
    let (state, missing): (String, Option<i32>) =
        sqlx::query_as("SELECT l.state, s.missing FROM libraries l JOIN library_scans s ON s.library_id = l.id")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!((state.as_str(), missing), ("online", Some(0)));
}

/// A tree of `files` one-byte files in folders of 100 under a temporary root, and Ann's external library of it, which
/// knows every file as a first scan leaves those that are no photos.
async fn known_tree(pool: &PgPool, files: usize) -> (tempfile::TempDir, Uuid, Vec<String>) {
    let dirs = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let root = dirs.path().join("nas");
    let folders: Vec<String> = (0..files.div_ceil(PER_FOLDER))
        .map(|n| format!("{:04}/{:02}", n / PER_FOLDER, n % PER_FOLDER))
        .collect();
    std::thread::scope(|threads| {
        for chunk in folders.chunks(PER_FOLDER) {
            let root = &root;
            threads.spawn(move || {
                for folder in chunk {
                    std::fs::create_dir_all(root.join(folder)).unwrap();
                    for file in 0..PER_FOLDER {
                        std::fs::write(root.join(folder).join(format!("IMG_{file:03}.jpg")), [0]).unwrap();
                    }
                }
            });
        }
    });
    let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(owner)
        .execute(pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, access, root_uri, scan_policy, fingerprint)
         VALUES ($1, $2, 'NAS', 'external', 'ro', $3, '{\"files_per_second\": 1000}', '{0000}')",
    )
    .bind(library)
    .bind(owner)
    .bind(root.to_str().unwrap())
    .execute(pool)
    .await
    .unwrap();
    // Known already, as a first scan leaves them: the files that are no photos.
    for chunk in folders.chunks(50) {
        let mut rows = QueryBuilder::<Postgres>::new(
            "INSERT INTO library_files (library_id, dir, name, dev, inode, size, mtime_ns, state, found_at) ",
        );
        let files = chunk
            .iter()
            .flat_map(|folder| (0..PER_FOLDER).map(move |file| (folder, file)));
        rows.push_values(files, |mut row, (folder, file)| {
            use std::os::unix::fs::MetadataExt;
            let name = format!("IMG_{file:03}.jpg");
            let meta = std::fs::metadata(root.join(folder).join(&name)).unwrap();
            row.push_bind(library)
                .push_bind(folder.clone())
                .push_bind(name)
                .push_bind(meta.dev().cast_signed())
                .push_bind(meta.ino().cast_signed())
                .push_bind(meta.size().cast_signed())
                .push_bind(meta.mtime() * 1_000_000_000 + meta.mtime_nsec())
                .push_bind("unsupported")
                .push_unseparated(", now() - interval '1 day'");
        });
        rows.build().execute(pool).await.unwrap();
    }
    (dirs, library, folders)
}
