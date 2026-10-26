//! Store and library markers, the intent log and its recovery, on the filesystem driver and on Garage.

use std::{
    os::unix::process::ExitStatusExt,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_storage::{
    BlobStore, Error, Hash, Hook, Meta,
    fs::FsStore,
    journal::{Journal, Op, Recovered},
    marker::{self, Candidate, STORE_MARKER, Stores},
    s3::{S3Config, S3Store},
    testing,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

const TIMEOUT: Duration = Duration::from_secs(30);
/// The instance of the journal tests' stores.
const INSTANCE: Uuid = Uuid::from_u128(1);

/// Where a store lives: every call opens a new handle on the same directory or bucket prefix.
#[derive(Clone, Serialize, Deserialize)]
enum Location {
    Fs(std::path::PathBuf),
    S3(S3Config),
}

impl Location {
    async fn open(&self) -> Arc<dyn BlobStore> {
        self.open_with(Arc::new(|_| Ok(()))).await
    }

    /// Writes in 5 MiB parts, so that `big()` is a multipart upload.
    async fn open_with(&self, hook: Hook) -> Arc<dyn BlobStore> {
        match self {
            Location::Fs(root) => Arc::new(FsStore::open(root, TIMEOUT).await.unwrap().with_hook(hook)),
            Location::S3(config) => Arc::new(
                S3Store::open(config, TIMEOUT)
                    .unwrap()
                    .part_size(5 << 20)
                    .with_hook(hook),
            ),
        }
    }
}

/// A fresh, empty location of each kind; the directory lives as long as the returned guard.
fn locations() -> (tempfile::TempDir, [Location; 2]) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("store");
    std::fs::create_dir(&root).unwrap();
    (dir, [Location::Fs(root), Location::S3(testing::garage())])
}

async fn database() -> PgPool {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    db.pool
}

async fn check(pool: &PgPool, instance: Uuid, name: &str, at: &Location, adopt: bool) -> Stores {
    let candidate = Candidate {
        name: name.into(),
        store: at.open().await,
        adopt,
    };
    Stores::check(pool, instance, vec![candidate]).await
}

/// Every key with its size and hash.
async fn contents(store: &dyn BlobStore) -> Vec<(String, Option<Meta>)> {
    let mut all = Vec::new();
    for key in store.list("").await.unwrap() {
        let meta = store.head(&key).await.unwrap();
        all.push((key, meta));
    }
    all
}

async fn put(store: &dyn BlobStore, key: &str, bytes: &[u8]) {
    let dir = tempfile::tempdir().unwrap();
    let (staged, hash) = testing::staged(dir.path(), bytes);
    store.put(key, &staged, hash).await.unwrap();
}

fn offline(stores: &Stores, name: &str, why: &str) {
    let found = stores.offline.get(name).map(String::as_str);
    assert!(
        found.is_some_and(|found| found.contains(why)),
        "{name}: {found:?}, expected {why:?}"
    );
    assert!(matches!(stores.get(name), Err(Error::Offline(_))));
}

#[tokio::test]
async fn a_store_whose_marker_is_missing_or_names_another_store_is_offline_and_unchanged() {
    let pool = database().await;
    let instance = Uuid::now_v7();
    let (_dir, locations) = locations();
    for (n, at) in locations.iter().enumerate() {
        let (a, b, c) = (format!("a{n}"), format!("b{n}"), format!("c{n}"));
        // A new, empty store is initialised; then it is recognised.
        assert!(check(&pool, instance, &a, at, false).await.get(&a).is_ok());
        let store = at.open().await;
        let initialised = contents(store.as_ref()).await;
        assert_eq!(
            initialised.iter().map(|(key, _)| key.as_str()).collect::<Vec<_>>(),
            [STORE_MARKER]
        );
        assert!(check(&pool, instance, &a, at, false).await.get(&a).is_ok());

        // Another name for the same store, or another instance, finds a marker that is not its own.
        offline(&check(&pool, instance, &b, at, false).await, &b, "names store");
        offline(&check(&pool, Uuid::now_v7(), &a, at, false).await, &a, "names store");
        offline(
            &check(&pool, Uuid::now_v7(), &c, at, false).await,
            &c,
            "another instance",
        );

        // An emptied, unmounted or wrongly configured store is never initialised again.
        store.delete(STORE_MARKER).await.unwrap();
        put(store.as_ref(), "x.jpg", b"x").await;
        let before = contents(store.as_ref()).await;
        offline(&check(&pool, instance, &a, at, false).await, &a, "missing");
        // A store with data but no marker is never adopted, unless it is the instance's own data directory.
        offline(&check(&pool, instance, &c, at, false).await, &c, "not empty");
        assert_eq!(contents(store.as_ref()).await, before, "nothing changed");
        assert!(check(&pool, instance, &c, at, true).await.get(&c).is_ok());
    }
    // An unreachable store is offline too, rather than stopping the others.
    let hole = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let mut config = testing::garage();
    config.endpoint = format!("http://{}", hole.local_addr().unwrap());
    let unreachable = Candidate {
        name: "hole".into(),
        store: Arc::new(S3Store::open(&config, Duration::from_millis(300)).unwrap()),
        adopt: false,
    };
    let stores = Stores::check(&pool, instance, vec![unreachable]).await;
    offline(&stores, "hole", "timed out");
    let names: Vec<String> = sqlx::query_scalar("SELECT name FROM stores ORDER BY name")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(names, ["a0", "a1", "c0", "c1"]);
}

#[tokio::test]
async fn verify_reads_a_marker_and_changes_nothing() {
    let pool = database().await;
    let instance = Uuid::now_v7();
    let (_dir, locations) = locations();
    for at in &locations {
        let store = at.open().await;
        let never = marker::verify(&pool, instance, "a", store.as_ref()).await;
        assert!(matches!(never, Err(Error::Offline(why)) if why.contains("never set up")));
        assert!(contents(store.as_ref()).await.is_empty(), "nothing written");
        check(&pool, instance, "a", at, false).await;
        let id: Uuid = sqlx::query_scalar("SELECT id FROM stores WHERE name = 'a'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(marker::verify(&pool, instance, "a", store.as_ref()).await.unwrap(), id);
        let other = marker::verify(&pool, Uuid::now_v7(), "a", store.as_ref()).await;
        assert!(matches!(other, Err(Error::Offline(why)) if why.contains("names store")));
        store.delete(STORE_MARKER).await.unwrap();
        let missing = marker::verify(&pool, instance, "a", store.as_ref()).await;
        assert!(matches!(missing, Err(Error::Offline(why)) if why.contains("missing")));
        sqlx::query("DELETE FROM stores").execute(&pool).await.unwrap();
    }
}

#[tokio::test]
async fn an_object_store_reports_its_clock_and_refuses_a_wrong_key() {
    let config = testing::garage();
    let clock = S3Store::open(&config, TIMEOUT).unwrap().clock().await.unwrap();
    let skew = clock
        .duration_since(std::time::SystemTime::now())
        .unwrap_or_else(|e| e.duration());
    assert!(skew < Duration::from_secs(5), "{skew:?}");
    let wrong = S3Config {
        secret_access_key: "wrong".into(),
        ..config
    };
    let refused = S3Store::open(&wrong, TIMEOUT).unwrap().clock().await.unwrap_err();
    assert!(refused.to_string().contains("403"), "{refused}");
}

#[tokio::test]
async fn a_library_is_online_only_with_its_own_marker() {
    let (_dir, locations) = locations();
    for at in &locations {
        let store = at.open().await;
        let (id, other) = (Uuid::now_v7(), Uuid::now_v7());
        let online = async |root, id| marker::library_online(store.as_ref(), root, id).await.unwrap();
        for root in ["", "libraries/one"] {
            assert!(!online(root, id).await);
            marker::create_library(store.as_ref(), root, id).await.unwrap();
            assert!(online(root, id).await && !online(root, other).await);
        }
        put(store.as_ref(), "garbled/.photolib/library.json", b"{").await;
        assert!(!online("garbled", id).await);
        assert!(matches!(
            marker::create_library(store.as_ref(), "", other).await,
            Err(Error::Exists(_))
        ));
    }
}

/// A journal on one fresh, registered store at `at`, and a table of rows that point at its keys.
async fn journal(pool: &PgPool, at: &Location) -> Journal {
    sqlx::query("CREATE TABLE IF NOT EXISTS files (store text, key text, hash bytea, PRIMARY KEY (store, key))")
        .execute(pool)
        .await
        .unwrap();
    let stores = check(pool, INSTANCE, &format!("s{}", Uuid::now_v7()), at, false).await;
    Journal::start(pool.clone(), stores).await.unwrap()
}

/// Another process's journal on the store `store` at `at`.
async fn reopen(pool: &PgPool, store: &str, at: &Location) -> Journal {
    let stores = check(pool, INSTANCE, store, at, false).await;
    Journal::start(pool.clone(), stores).await.unwrap()
}

fn name(journal: &Journal) -> String {
    journal.stores().online().next().unwrap().0.to_string()
}

async fn open_intents(pool: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM file_intents WHERE state IN ('planned', 'switched')")
        .fetch_one(pool)
        .await
        .unwrap()
}

/// Runs recovery until no intent belongs to a process that still holds its lock: a killed process's connection
/// closes a moment after it dies.
async fn recover(journal: &Journal) -> Recovered {
    let mut total = Recovered::default();
    for _ in 0..100 {
        let r = journal.recover().await.unwrap();
        (total.rolled_back, total.completed) = (total.rolled_back + r.rolled_back, total.completed + r.completed);
        if r.busy == 0 {
            return total;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    panic!("intents stayed busy");
}

/// The keys in the store are exactly the rows' keys, with the rows' hashes: nothing orphaned, nothing missing, no
/// unfinished upload and no open intent.
async fn consistent(pool: &PgPool, journal: &Journal) -> Vec<String> {
    let name = name(journal);
    let store = journal.stores().get(&name).unwrap();
    let rows: Vec<(String, Vec<u8>)> = sqlx::query_as("SELECT key, hash FROM files WHERE store = $1 ORDER BY key")
        .bind(&name)
        .fetch_all(pool)
        .await
        .unwrap();
    let mut stored = Vec::new();
    for (key, meta) in contents(store.as_ref()).await {
        if key != STORE_MARKER {
            stored.push((key, meta.unwrap().hash.unwrap().0.to_vec()));
        }
    }
    assert_eq!(stored, rows, "orphaned or missing objects");
    assert!(store.uploads("").await.unwrap().is_empty(), "unfinished uploads");
    assert_eq!(open_intents(pool).await, 0);
    rows.into_iter().map(|(key, _)| key).collect()
}

// The caller's rows for a put, a move and a delete: `$1` is the store, `$2` the key, `$3` the hash.
const PUT_ROW: &str = "INSERT INTO files VALUES ($1, $2, $3)";
const MOVE_ROW: &str = "UPDATE files SET key = $2 WHERE store = $1 AND hash = $3";
const DELETE_ROW: &str = "DELETE FROM files WHERE store = $1 AND key = $2 AND hash = $3";

const NO_STEP: &dyn Fn(&str) = &|_| {};

/// The caller's side of an operation: its rows and the switch in one transaction, then the finish.
async fn switch(pool: &PgPool, op: Op<'_>, rows: &str, store: &str, key: &str, hash: Hash, step: &dyn Fn(&str)) {
    let mut tx = pool.begin().await.unwrap();
    sqlx::query(rows)
        .bind(store)
        .bind(key)
        .bind(hash.0.to_vec())
        .execute(&mut *tx)
        .await
        .unwrap();
    step("rows");
    op.switch(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    step("committed");
    op.finish().await.unwrap();
    step("finished");
}

/// Puts `key` through the journal and records its row with the switch.
async fn put_row(pool: &PgPool, journal: &Journal, key: &str, bytes: &[u8]) -> Hash {
    let dir = tempfile::tempdir().unwrap();
    let (staged, hash) = testing::staged(dir.path(), bytes);
    let op = journal.put(&name(journal), key, &staged, hash).await.unwrap();
    switch(pool, op, PUT_ROW, &name(journal), key, hash, NO_STEP).await;
    hash
}

#[tokio::test]
async fn journaled_operations_switch_with_the_callers_rows() {
    let pool = database().await;
    let (_dir, locations) = locations();
    for at in &locations {
        let journal = journal(&pool, at).await;
        let store = name(&journal);
        let hash = put_row(&pool, &journal, "2024/a.jpg", b"a").await;
        assert_eq!(consistent(&pool, &journal).await, ["2024/a.jpg"]);

        // Keys are never overwritten, and an open intent reserves its key.
        let dir = tempfile::tempdir().unwrap();
        let (staged, b) = testing::staged(dir.path(), b"b");
        assert!(matches!(
            journal.put(&store, "2024/a.jpg", &staged, b).await,
            Err(Error::Exists(_))
        ));
        let open = journal.put(&store, "2024/b.jpg", &staged, b).await.unwrap();
        assert!(matches!(
            journal.put(&store, "2024/b.jpg", &staged, b).await,
            Err(Error::Exists(_))
        ));
        assert!(matches!(
            journal.delete(&store, "2024/b.jpg").await,
            Err(Error::Exists(_))
        ));
        drop(open);

        // A write that fails verification is rolled back at once.
        let wrong = journal
            .put(&store, "2024/c.jpg", &staged, Hash::of(b"c"))
            .await
            .map(drop);
        assert!(matches!(wrong, Err(Error::Integrity(_))), "{wrong:?}");

        // A move: copy, verify, switch with the rows, then delete the source.
        let op = journal
            .relocate(&store, "2024/a.jpg", "2024/moved.jpg", hash)
            .await
            .unwrap();
        switch(&pool, op, MOVE_ROW, &store, "2024/moved.jpg", hash, NO_STEP).await;
        assert!(matches!(
            journal
                .relocate(&store, "2024/moved.jpg", "x.jpg", Hash::of(b"other"))
                .await,
            Err(Error::Integrity(_))
        ));
        assert!(matches!(
            journal.relocate(&store, "missing.jpg", "x.jpg", hash).await,
            Err(Error::NotFound(_))
        ));

        // A delete: switch with the rows, then delete the object.
        let op = journal.delete(&store, "2024/moved.jpg").await.unwrap();
        switch(&pool, op, DELETE_ROW, &store, "2024/moved.jpg", hash, NO_STEP).await;

        // The abandoned put of b.jpg is still open: recovery by a later process rolls it back.
        assert_eq!(open_intents(&pool).await, 1);
        drop(journal);
        let later = reopen(&pool, &store, at).await;
        let recovered = recover(&later).await;
        assert_eq!((recovered.rolled_back, recovered.completed), (1, 0));
        assert_eq!(consistent(&pool, &later).await, Vec::<String>::new());
    }
}

#[tokio::test]
async fn a_put_settles_with_the_callers_rows_or_not_at_all() {
    let pool = database().await;
    let (_dir, locations) = locations();
    let journal = journal(&pool, &locations[0]).await;
    let store = name(&journal);
    let dir = tempfile::tempdir().unwrap();
    for (key, commit) in [("kept.webp", true), ("dropped.webp", false)] {
        let (staged, hash) = testing::staged(dir.path(), key.as_bytes());
        let op = journal.put(&store, key, &staged, hash).await.unwrap();
        let mut tx = pool.begin().await.unwrap();
        sqlx::query(PUT_ROW)
            .bind(&store)
            .bind(key)
            .bind(hash.0.to_vec())
            .execute(&mut *tx)
            .await
            .unwrap();
        op.settle(&mut tx).await.unwrap();
        if commit {
            tx.commit().await.unwrap();
        }
    }
    assert_eq!(open_intents(&pool).await, 1, "the rolled-back put is still planned");
    let delete = journal.delete(&store, "kept.webp").await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    assert!(
        matches!(delete.settle(&mut tx).await, Err(Error::Other(_))),
        "a delete has a file to delete"
    );
    drop((tx, journal));
    let later = reopen(&pool, &store, &locations[0]).await;
    let recovered = recover(&later).await;
    assert_eq!((recovered.rolled_back, recovered.completed), (2, 0));
    assert_eq!(consistent(&pool, &later).await, ["kept.webp"]);
}

#[tokio::test]
async fn recovery_leaves_the_intents_of_a_running_process_alone() {
    let pool = database().await;
    let (_dir, locations) = locations();
    for at in &locations {
        let running = journal(&pool, at).await;
        let store = name(&running);
        let hash = put_row(&pool, &running, "a.jpg", b"a").await;
        let dir = tempfile::tempdir().unwrap();
        let (staged, b) = testing::staged(dir.path(), b"b");
        let planned = running.put(&store, "b.jpg", &staged, b).await.unwrap();
        let switched = running.relocate(&store, "a.jpg", "moved.jpg", hash).await.unwrap();
        let mut tx = pool.begin().await.unwrap();
        sqlx::query(MOVE_ROW)
            .bind(&store)
            .bind("moved.jpg")
            .bind(hash.0.to_vec())
            .execute(&mut *tx)
            .await
            .unwrap();
        switched.switch(&mut tx).await.unwrap();
        tx.commit().await.unwrap();
        let before = contents(running.stores().get(&store).unwrap().as_ref()).await;

        let other = reopen(&pool, &store, at).await;
        let busy = other.recover().await.unwrap();
        assert_eq!((busy.busy, busy.rolled_back, busy.completed), (2, 0, 0));
        assert_eq!(contents(running.stores().get(&store).unwrap().as_ref()).await, before);

        drop((planned, switched));
        drop(running);
        let recovered = recover(&other).await;
        assert_eq!((recovered.rolled_back, recovered.completed), (1, 1));
        assert_eq!(consistent(&pool, &other).await, ["moved.jpg"]);
    }
}

/// A job's switches commit with the job, after its handler returned: the journal finishes them afterwards, and only
/// those that committed.
#[tokio::test]
async fn a_process_finishes_its_own_committed_switches_later() {
    let pool = database().await;
    let (_dir, [at, _]) = locations();
    let journal = journal(&pool, &at).await;
    let store = name(&journal);
    let (a, b) = (
        put_row(&pool, &journal, "a.jpg", b"a").await,
        put_row(&pool, &journal, "b.jpg", b"b").await,
    );
    for (key, hash, commit) in [("a.jpg", a, true), ("b.jpg", b, false)] {
        let op = journal.delete(&store, key).await.unwrap();
        let mut tx = pool.begin().await.unwrap();
        sqlx::query(DELETE_ROW)
            .bind(&store)
            .bind(key)
            .bind(hash.0.to_vec())
            .execute(&mut *tx)
            .await
            .unwrap();
        op.switch(&mut tx).await.unwrap();
        if commit {
            tx.commit().await.unwrap();
        }
    }
    assert_eq!(journal.finish_switched().await.unwrap(), 1);
    let left = contents(journal.stores().get(&store).unwrap().as_ref()).await;
    assert_eq!(
        left.iter()
            .filter(|(key, _)| key != STORE_MARKER)
            .map(|(key, _)| key.as_str())
            .collect::<Vec<_>>(),
        ["b.jpg"]
    );
    assert_eq!(
        open_intents(&pool).await,
        1,
        "the rolled-back delete stays planned for recovery"
    );
    assert_eq!(journal.finish_switched().await.unwrap(), 0);
}

#[tokio::test]
async fn nothing_changes_in_an_offline_store() {
    let pool = database().await;
    let (_dir, locations) = locations();
    for at in &locations {
        let online = journal(&pool, at).await;
        let store = name(&online);
        let hash = put_row(&pool, &online, "a.jpg", b"a").await;
        let handle = at.open().await;
        handle.delete(STORE_MARKER).await.unwrap();
        let before = contents(handle.as_ref()).await;
        let offline = reopen(&pool, &store, at).await;
        let dir = tempfile::tempdir().unwrap();
        let (staged, b) = testing::staged(dir.path(), b"b");
        for result in [
            offline.put(&store, "b.jpg", &staged, b).await.map(drop),
            offline.relocate(&store, "a.jpg", "c.jpg", hash).await.map(drop),
            offline.delete(&store, "a.jpg").await.map(drop),
            offline.local(&store, "a.jpg", hash, dir.path()).await.map(drop),
        ] {
            assert!(matches!(result, Err(Error::Offline(_))), "{result:?}");
        }
        assert_eq!(contents(handle.as_ref()).await, before);
        assert_eq!(open_intents(&pool).await, 0);
    }
}

#[tokio::test]
async fn a_local_copy_that_does_not_match_fails_with_an_integrity_finding() {
    let pool = database().await;
    let (_dir, locations) = locations();
    for at in &locations {
        let journal = journal(&pool, at).await;
        let store = name(&journal);
        put_row(&pool, &journal, "a.jpg", b"a").await;
        let scratch = tempfile::tempdir().unwrap();
        // A job that fails reads as often as it is retried; the finding stays one while it is open.
        for _ in 0..2 {
            let wrong = journal.local(&store, "a.jpg", Hash::of(b"b"), scratch.path()).await;
            if let Location::S3(_) = at {
                assert!(matches!(wrong, Err(Error::Integrity(_))), "{wrong:?}");
            }
        }
    }
    let findings: Vec<(String, String)> = sqlx::query_as("SELECT key, detail FROM integrity_findings")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(findings.len(), 1, "{findings:?}");
    assert_eq!(findings[0].0, "a.jpg");
    assert!(findings[0].1.contains("expected blake3:"), "{findings:?}");
}

#[tokio::test]
async fn recovery_aborts_uploads_older_than_a_day() {
    let pool = database().await;
    let (_dir, [at, _]) = locations();
    let journal = journal(&pool, &at).await;
    let Location::Fs(root) = &at else { unreachable!() };
    let tmp = root.join(".photolib/tmp/2024");
    std::fs::create_dir_all(&tmp).unwrap();
    for (name, age) in [("old.jpg", 25), ("new.jpg", 23)] {
        let file = std::fs::File::create(tmp.join(name)).unwrap();
        file.set_modified(std::time::SystemTime::now() - Duration::from_secs(age * 3600))
            .unwrap();
    }
    recover(&journal).await;
    let store = journal.stores().get(&name(&journal)).unwrap();
    let left: Vec<_> = store.uploads("").await.unwrap().into_iter().map(|u| u.key).collect();
    assert_eq!(left, ["2024/new.jpg"]);
}

#[tokio::test]
async fn a_file_without_a_recorded_hash_moves_only_when_its_bytes_match() {
    let pool = database().await;
    let (_dir, [at, _]) = locations();
    let journal = journal(&pool, &at).await;
    let Location::Fs(root) = &at else { unreachable!() };
    std::fs::write(root.join("user.jpg"), b"user").unwrap();
    let store = name(&journal);
    let wrong = journal
        .relocate(&store, "user.jpg", "moved.jpg", Hash::of(b"other"))
        .await;
    assert!(matches!(wrong.map(drop), Err(Error::Integrity(_))));
    journal
        .relocate(&store, "user.jpg", "moved.jpg", Hash::of(b"user"))
        .await
        .unwrap();
    let blobs = journal.stores().get(&store).unwrap();
    assert_eq!(blobs.list("").await.unwrap(), [STORE_MARKER, "moved.jpg", "user.jpg"]);
    assert_eq!(
        blobs.head("moved.jpg").await.unwrap().unwrap().hash,
        Some(Hash::of(b"user"))
    );
}

/// A copy to another store switches with the caller's rows; the source stays, reserved, until its delayed delete is
/// due, which recovery and finishing switches leave to the purge.
#[tokio::test]
async fn a_copy_to_another_store_keeps_its_source_until_the_delete_is_due() {
    let pool = database().await;
    let (_dir, locations) = locations();
    let names = [0, 1].map(|n| format!("s{n}-{}", Uuid::now_v7()));
    let mut candidates = vec![];
    for (name, at) in names.iter().zip(&locations) {
        let store = at.open().await;
        candidates.push(Candidate {
            name: name.clone(),
            store,
            adopt: false,
        });
    }
    let stores = Stores::check(&pool, INSTANCE, candidates).await;
    let journal = Journal::start(pool.clone(), stores).await.unwrap();
    let staging = tempfile::tempdir().unwrap();
    let (staged, hash) = testing::staged(staging.path(), &big());
    let op = journal.put(&names[0], "a.jpg", &staged, hash).await.unwrap();
    let mut tx = pool.begin().await.unwrap();
    op.switch(&mut tx).await.unwrap();
    tx.commit().await.unwrap();
    assert_eq!(open_intents(&pool).await, 0, "a switched put is done");
    let scratch = tempfile::tempdir().unwrap();
    let read = async |store: &str, key: &str| {
        let blobs = journal.stores().get(store).unwrap();
        blobs.get(key, None).await.map(|bytes| Hash::of(&bytes))
    };
    for (from, to) in [(&names[0], &names[1]), (&names[1], &names[0])] {
        let (key, moved) = if from == &names[0] {
            ("a.jpg", "b.jpg")
        } else {
            ("b.jpg", "a.jpg")
        };
        let wrong = journal
            .copy((from, key), (to, moved), Hash::of(b"other"), scratch.path())
            .await;
        assert!(matches!(wrong.map(drop), Err(Error::Integrity(_))));
        // A copy the caller abandons is deleted and frees its key.
        let abandoned = journal.copy((from, key), (to, moved), hash, scratch.path());
        abandoned.await.unwrap().abandon().await.unwrap();
        assert!(matches!(read(to, moved).await, Err(Error::NotFound(_))));
        let op = journal
            .copy((from, key), (to, moved), hash, scratch.path())
            .await
            .unwrap();
        let mut tx = pool.begin().await.unwrap();
        op.switch(&mut tx).await.unwrap();
        let week = Duration::from_secs(7 * 86_400);
        journal.delete_after(&mut tx, from, key, week).await.unwrap();
        tx.commit().await.unwrap();
        assert_eq!(std::fs::read_dir(scratch.path()).unwrap().count(), 0);
        assert_eq!(read(to, moved).await.unwrap(), hash);

        // Not due: neither the purge, nor this process finishing its switches, nor another process's recovery deletes
        // the source, which stays reserved.
        assert_eq!(journal.purge().await.unwrap(), 0);
        assert_eq!(journal.finish_switched().await.unwrap(), 0);
        let other = Journal::start(pool.clone(), Stores::default()).await.unwrap();
        assert_eq!(other.recover().await.unwrap().busy, 0);
        assert_eq!(read(from, key).await.unwrap(), hash);
        let (again, _) = testing::staged(staging.path(), &big());
        assert!(matches!(
            journal.put(from, key, &again, hash).await.map(drop),
            Err(Error::Exists(_))
        ));
        assert_eq!(open_intents(&pool).await, 1);

        sqlx::query("UPDATE file_intents SET due = now() WHERE due IS NOT NULL")
            .execute(&pool)
            .await
            .unwrap();
        assert_eq!(journal.purge().await.unwrap(), 1);
        assert!(matches!(read(from, key).await, Err(Error::NotFound(_))));
        assert_eq!(open_intents(&pool).await, 0);
    }
}

/// What the crash child does: `op` on the store `store` at `at`, killed with SIGKILL at its `kill_at`-th step.
#[derive(Serialize, Deserialize)]
struct Crash {
    url: String,
    store: String,
    at: Location,
    op: String,
    kill_at: usize,
}

const CRASH: &str = "PHOTOLIB_CRASH";

/// Run only by `a_process_killed_at_any_step_leaves_nothing_orphaned_or_missing_after_recovery`, as a child.
#[tokio::test]
async fn crash_child() {
    let Ok(crash) = std::env::var(CRASH) else {
        return;
    };
    let crash: Crash = serde_json::from_str(&crash).unwrap();
    let steps = Arc::new(AtomicUsize::new(0));
    let hook: Hook = Arc::new(move |name| {
        let step = steps.fetch_add(1, Ordering::SeqCst) + 1;
        eprintln!("step {name}");
        if step == crash.kill_at {
            rustix::process::kill_process(rustix::process::getpid(), rustix::process::Signal::KILL).unwrap();
        }
        Ok(())
    });
    let pool = PgPool::connect(&crash.url).await.unwrap();
    let candidate = Candidate {
        name: crash.store.clone(),
        store: crash.at.open_with(hook.clone()).await,
        adopt: false,
    };
    let stores = Stores::check(&pool, INSTANCE, vec![candidate]).await;
    let journal = Journal::start(pool.clone(), stores)
        .await
        .unwrap()
        .with_hook(hook.clone());
    let step = |name: &str| hook(name).unwrap();
    let store = crash.store.as_str();
    let data = big();
    let hash = Hash::of(&data);
    match crash.op.as_str() {
        "put" => {
            let dir = tempfile::tempdir().unwrap();
            let (staged, hash) = testing::staged(dir.path(), &data);
            let op = journal.put(store, "a.jpg", &staged, hash).await.unwrap();
            switch(&pool, op, PUT_ROW, store, "a.jpg", hash, &step).await;
        }
        "move" => {
            let op = journal.relocate(store, "a.jpg", "b.jpg", hash).await.unwrap();
            switch(&pool, op, MOVE_ROW, store, "b.jpg", hash, &step).await;
        }
        _ => {
            let op = journal.delete(store, "a.jpg").await.unwrap();
            switch(&pool, op, DELETE_ROW, store, "a.jpg", hash, &step).await;
        }
    }
}

fn big() -> Vec<u8> {
    (0..11 << 20).map(|i: u32| (i % 251) as u8).collect()
}

/// Kills a process with SIGKILL at each step of a put, a move and a delete in turn, on both drivers; after recovery
/// the store holds exactly what the rows name, either before or after the operation.
#[tokio::test]
async fn a_process_killed_at_any_step_leaves_nothing_orphaned_or_missing_after_recovery() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let pool = db.pool;
    // Both drivers write `big()` in more than one part: the filesystem's 8 MiB, the test S3 store's 5 MiB.
    #[rustfmt::skip]
    let cases: [(usize, &str, &[&str]); 6] = [
        (0, "put", &["planned", "part", "part", "synced", "written", "rows", "committed", "finished"]),
        (0, "move", &["planned", "part", "part", "synced", "written", "rows", "committed", "deleted", "finished"]),
        (0, "delete", &["planned", "rows", "committed", "deleted", "finished"]),
        (1, "put", &["planned", "part", "part", "part", "closed", "written", "rows", "committed", "finished"]),
        (1, "move", &["planned", "written", "rows", "committed", "deleted", "finished"]),
        (1, "delete", &["planned", "rows", "committed", "deleted", "finished"]),
    ];
    for (kind, op, steps) in cases {
        let (before, after): (&[&str], &[&str]) = match op {
            "put" => (&[], &["a.jpg"]),
            "move" => (&["a.jpg"], &["b.jpg"]),
            _ => (&["a.jpg"], &[]),
        };
        for kill_at in 1..=steps.len() + 1 {
            let (_dir, locations) = locations();
            let at = &locations[kind];
            let journal = journal(&pool, at).await;
            if op != "put" {
                put_row(&pool, &journal, "a.jpg", &big()).await;
            }
            let crash = Crash {
                url: db.url.clone(),
                store: name(&journal),
                at: at.clone(),
                op: op.into(),
                kill_at,
            };
            let child = std::process::Command::new(std::env::current_exe().unwrap())
                .args(["crash_child", "--exact", "--nocapture", "--test-threads=1"])
                .env(CRASH, serde_json::to_string(&crash).unwrap())
                .output()
                .unwrap();
            let log = String::from_utf8_lossy(&child.stderr);
            let seen: Vec<_> = log.lines().filter_map(|line| line.strip_prefix("step ")).collect();
            let what = format!("{op} on store {kind}, killed at step {kill_at}: {log}");
            if kill_at <= steps.len() {
                assert_eq!(child.status.signal(), Some(9), "{what}");
                assert_eq!(seen, steps[..kill_at], "{what}");
            } else {
                assert!(child.status.success(), "{what}");
                assert_eq!(seen, steps, "{what}");
            }
            recover(&journal).await;
            let expected = if seen.contains(&"committed") { after } else { before };
            assert_eq!(consistent(&pool, &journal).await, expected, "{what}");
        }
    }
}

/// The upper half of code page 437, as old zip tools wrote names.
const CP437: &str = "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{a0}";

/// Names that break naive storage code, then seeded random paths built from their pieces: valid keys and keys that
/// must be refused.
fn names() -> Vec<String> {
    let mut names: Vec<String> = [
        "caf\u{e9}.jpg",
        "cafe\u{301}.jpg",
        "📷 🏳️‍🌈 👨‍👩‍👧.heic",
        "it's \"quoted\" `really`.jpg",
        "new\nline\ttab\rreturn.jpg",
        "a+b c%20d?e#f&g=h;i.jpg",
        " leading and trailing .jpg ",
        "-dash ~tilde .hidden ... CON nul back\\slash",
        "IMG_0001.JPG",
        "img_0001.jpg",
        "Ünïcödé/Ordner mit Leerzeichen/Datei.jpg",
        "╔═╗ PRÄSENTATION/ÇÜÉ ░▒▓.jpg",
    ]
    .map(String::from)
    .into();
    names.push("é".repeat(127) + "x");
    names.push(format!("{}/{}", "x".repeat(255), "ü".repeat(127)));
    names.push("x".repeat(256));
    let pieces: Vec<String> = [
        "e\u{301}",
        "\u{e9}",
        "📷",
        "👨‍👩‍👧",
        "'",
        "\"",
        "\n",
        "\r",
        "\u{1b}",
        " ",
        "+",
        "%",
        ".",
        "..",
        "\\",
        "A",
        "a",
        "日本",
        "/",
    ]
    .iter()
    .map(|piece| piece.to_string())
    .chain(CP437.chars().map(String::from))
    .collect();
    let mut seed = 0x9e37_79b9_7f4a_7c15_u64;
    let mut next = |n: usize| {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        (seed % n as u64) as usize
    };
    for _ in 0..80 {
        let len = [1, 8, 40, 300][next(4)];
        let mut name = String::from("fuzz/");
        while name.len() < len {
            name += &pieces[next(pieces.len())];
        }
        names.push(name + ".bin");
    }
    names.sort();
    names.dedup();
    names
}

#[tokio::test]
async fn a_fuzzed_corpus_of_names_round_trips_through_journaled_writes() {
    let pool = database().await;
    let (_dir, locations) = locations();
    let names = names();
    for at in &locations {
        let journal = journal(&pool, at).await;
        let store = name(&journal);
        let mut written = Vec::new();
        for key in &names {
            let dir = tempfile::tempdir().unwrap();
            let (staged, hash) = testing::staged(dir.path(), key.as_bytes());
            let s3_refuses = matches!(at, Location::S3(_)) && key.trim() != key;
            match photolib_storage::check_key(key).is_ok() && !s3_refuses {
                true => {
                    let op = journal.put(&store, key, &staged, hash).await.unwrap();
                    switch(&pool, op, PUT_ROW, &store, key, hash, NO_STEP).await;
                    written.push(key.clone());
                }
                false => assert!(matches!(
                    journal.put(&store, key, &staged, hash).await.map(drop),
                    Err(Error::InvalidKey(_))
                )),
            }
        }
        assert!(written.len() > 60 && written.len() < names.len(), "{}", written.len());
        assert_eq!(consistent(&pool, &journal).await, written);
        let blobs = journal.stores().get(&store).unwrap();
        for key in &written {
            assert_eq!(blobs.get(key, None).await.unwrap(), key.as_bytes(), "{key:?}");
        }
    }
}
