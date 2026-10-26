//! The trash (M2-26, design 05 §5, 07 §6, ADR-0022): an asset trashed on a device stays recoverable until its owner
//! empties the trash or its retention ends. Then the `trash-empty` and `trash-expire` jobs delete the asset's rows and
//! its files and objects through the intent log, each asset in a transaction that switches the delete intents with the
//! rows' removal, so that a crash leaves no row without its file and no file without its row. The deletion leaves
//! sync's tombstones, which tell every device; nothing relies on bucket versioning or object lock.

use photolib_authz::{Action, Kind, Principal, scope};
use photolib_jobs::NewJob;
use photolib_storage::journal::Journal;
use sqlx::{PgPool, QueryBuilder};
use uuid::Uuid;

use crate::{guard::Dry, library::text};

/// The job that deletes an account's trash up to the instant its count was confirmed at.
pub const EMPTY: &str = "trash-empty";
/// The daily job that deletes what stayed in the trash for the console's `trash_retention_days` (30 unless set).
pub const EXPIRE: &str = "trash-expire";

/// What emptying `me`'s trash for `who` would delete, and the instant (microseconds since the epoch) of the newest of
/// it, which the job deletes up to.
pub async fn plan(pool: &PgPool, who: Principal, me: Uuid) -> sqlx::Result<(Dry, i64)> {
    let mut q = QueryBuilder::new(format!(
        "SELECT count(*), coalesce((extract(epoch FROM max(a.trashed_at)) * 1000000)::bigint, 0)
         FROM assets a WHERE {TRASHED} AND a.owner_id = "
    ));
    q.push_bind(me).push(" AND a.id IN (");
    scope(who, Action::Delete, Kind::Asset, &mut q);
    let (count, upto): (i64, i64) = q.push(")").build_query_as().fetch_one(pool).await?;
    let total = sqlx::query_scalar("SELECT count(*) FROM assets WHERE owner_id = $1");
    let total = total.bind(me).fetch_one(pool).await?;
    Ok((
        Dry::new(
            "trash.empty",
            me,
            Uuid::from_u128(u128::try_from(upto).unwrap_or_default()),
            count,
            total,
        ),
        upto,
    ))
}

/// Queues the emptying of `me`'s trash for `who`: the number of assets it will delete, or, when that is more than
/// `guard` lets through unconfirmed and `token` is not the one of its count, what to show the user to confirm.
pub async fn empty(pool: &PgPool, who: Principal, me: Uuid, token: &str) -> sqlx::Result<Result<i64, Dry>> {
    let (dry, upto) = plan(pool, who, me).await?;
    if dry.count == 0 || !dry.allows(token) {
        return Ok(if dry.count == 0 { Ok(0) } else { Err(dry) });
    }
    let payload = serde_json::json!({ "owner": me, "upto": upto }).to_string();
    let mut conn = pool.acquire().await?;
    photolib_jobs::enqueue(&mut conn, &NewJob::new(EMPTY, payload.as_bytes())).await?;
    Ok(Ok(dry.count))
}

/// The instant (microseconds since the epoch) before which a trashed asset has stayed past the console's
/// `trash_retention_days`.
pub async fn expired(pool: &PgPool) -> sqlx::Result<i64> {
    sqlx::query_scalar(
        "SELECT (extract(epoch FROM now() - trash_retention_days * interval '1 day') * 1000000)::bigint
         FROM instance_settings",
    )
    .fetch_one(pool)
    .await
}

/// Runs a `trash-empty` job (payload: owner and instant) or a `trash-expire` one (everything past the retention).
pub async fn run(pool: &PgPool, journal: &Journal, job: &photolib_jobs::Job) -> Result<(), String> {
    let (owner, upto) = if job.kind == EXPIRE {
        (None, expired(pool).await.map_err(text)?)
    } else {
        let payload: serde_json::Value = serde_json::from_slice(&job.payload).map_err(text)?;
        let owner = payload
            .get("owner")
            .and_then(|owner| owner.as_str())
            .and_then(|id| id.parse::<Uuid>().ok());
        let (owner, upto) =
            (owner.zip(payload.get("upto").and_then(serde_json::Value::as_i64))).ok_or("a malformed payload")?;
        (Some(owner), upto)
    };
    let purged = purge(pool, journal, owner, upto).await?;
    if purged > 0 {
        tracing::info!(purged, "trashed assets deleted");
    }
    Ok(())
}

/// The trashed assets that emptying deletes: not those of an external library, which is never written and would be
/// found again by its next scan.
const TRASHED: &str = "a.trashed_at IS NOT NULL
    AND EXISTS (SELECT FROM libraries l WHERE l.id = a.library_id AND l.kind <> 'external')";
/// Assets handled between two looks at what is left.
const BATCH: i64 = 100;

/// Deletes the trashed assets of `owner` (all accounts when `None`) trashed at or before `upto` (microseconds since the
/// epoch), with their files; returns how many assets.
pub async fn purge(pool: &PgPool, journal: &Journal, owner: Option<Uuid>, upto: i64) -> Result<usize, String> {
    let ids = format!(
        "SELECT a.id FROM assets a WHERE {TRASHED} AND a.trashed_at <= {AT}
         AND ($2::uuid IS NULL OR a.owner_id = $2) ORDER BY a.id LIMIT {BATCH}"
    );
    let mut purged = 0;
    loop {
        let batch: Vec<Uuid> = (sqlx::query_scalar(&ids).bind(upto).bind(owner))
            .fetch_all(pool)
            .await
            .map_err(text)?;
        if batch.is_empty() {
            return Ok(purged);
        }
        for asset in batch {
            purged = purged.saturating_add(remove(pool, journal, asset, upto).await?);
        }
    }
}

/// The instant `$1` microseconds after the epoch.
const AT: &str = "('epoch'::timestamptz + $1 * interval '1 microsecond')";

/// Deletes `asset` if it is still in the trash at `upto`: a delete intent for each file no other asset names, then in
/// one transaction its rows and the intents' switch, then the files. Returns whether it was deleted.
async fn remove(pool: &PgPool, journal: &Journal, asset: Uuid, upto: i64) -> Result<usize, String> {
    let files: Vec<(String, String)> = sqlx::query_as(
        "SELECT DISTINCT f.storage, f.key FROM asset_files f WHERE f.asset_id = $1 AND f.storage <> 'external'
         AND NOT EXISTS (SELECT FROM asset_files o WHERE o.storage = f.storage AND o.key = f.key AND o.asset_id <> $1)",
    )
    .bind(asset)
    .fetch_all(pool)
    .await
    .map_err(text)?;
    let mut ops = vec![];
    for (store, key) in &files {
        match journal.delete(store, key).await {
            Ok(op) => ops.push(op),
            Err(error) => {
                for op in ops {
                    drop(op.abandon().await);
                }
                return Err(text(error));
            }
        }
    }
    let switched = async {
        let mut tx = pool.begin().await?;
        let gone = format!("DELETE FROM assets a WHERE a.id = $2 AND {TRASHED} AND a.trashed_at <= {AT}");
        let gone = sqlx::query(&gone).bind(upto).bind(asset).execute(&mut *tx).await?;
        if gone.rows_affected() == 0 {
            return Ok::<_, photolib_storage::Error>(false);
        }
        for op in &ops {
            op.switch(&mut tx).await?;
        }
        tx.commit().await?;
        Ok(true)
    }
    .await;
    if !matches!(switched, Ok(true)) {
        for op in ops {
            drop(op.abandon().await);
        }
        return switched.map(usize::from).map_err(text);
    }
    for op in ops {
        op.finish().await.map_err(text)?;
    }
    Ok(1)
}

#[cfg(test)]
mod tests {
    use std::{
        os::unix::process::ExitStatusExt,
        path::{Path, PathBuf},
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
        time::Duration,
    };

    use photolib_authz::Role;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_storage::{
        Hook,
        fs::FsStore,
        marker::{Candidate, Stores},
    };
    use serde::{Deserialize, Serialize};

    use super::*;
    use crate::library;

    const TIMEOUT: Duration = Duration::from_secs(30);
    const CRASH: &str = "PHOTOLIB_CRASH";
    const FAR: i64 = i64::MAX / 2;

    async fn journal(pool: &PgPool, dir: &Path, hook: Hook) -> Journal {
        let store = Arc::new(FsStore::open(dir, TIMEOUT).await.unwrap());
        let candidates = vec![Candidate {
            name: "disk".into(),
            store,
            adopt: true,
        }];
        let stores = Stores::check(pool, Uuid::from_u128(1), candidates).await;
        Journal::start(pool.clone(), stores).await.unwrap().with_hook(hook)
    }

    fn no_hook() -> Hook {
        Arc::new(|_| Ok(()))
    }

    async fn user(pool: &PgPool, handle: &str) -> Uuid {
        let id = Uuid::now_v7();
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, $2, $2)")
            .bind(id)
            .bind(handle)
            .execute(pool)
            .await
            .unwrap();
        id
    }

    /// An asset of `owner` in `library` with an original and a thumbnail; trashed `days` ago if it is.
    async fn photo(pool: &PgPool, journal: &Journal, (owner, library): (Uuid, Uuid), trashed: Option<i64>) -> Uuid {
        let asset = Uuid::now_v7();
        sqlx::query(
            "INSERT INTO assets (id, library_id, owner_id, source, media_kind,
                                 trashed_at) VALUES ($1, $2, $3, 'upload', 'image',
                                 now() - $4::bigint * interval '1 day')",
        )
        .bind(asset)
        .bind(library)
        .bind(owner)
        .bind(trashed)
        .execute(pool)
        .await
        .unwrap();
        for role in ["original", "thumb_s"] {
            let key = format!("libraries/{library}/{asset}-{role}");
            file(pool, journal, asset, role, &key).await;
        }
        asset
    }

    /// A present file of `asset` at `key`, written when no other asset has put it.
    async fn file(pool: &PgPool, journal: &Journal, asset: Uuid, role: &str, key: &str) {
        let bytes = format!("{asset} {role}").repeat(100).into_bytes();
        let op = (journal.put_bytes("disk", key, &bytes).await).ok();
        sqlx::query(
            "INSERT INTO asset_files (id, asset_id, role, storage, key, size) VALUES ($1, $2, $3, 'disk', $4, $5)",
        )
        .bind(Uuid::now_v7())
        .bind(asset)
        .bind(role)
        .bind(key)
        .bind(i64::try_from(bytes.len()).unwrap())
        .execute(pool)
        .await
        .unwrap();
        if let Some(op) = op {
            let mut tx = pool.begin().await.unwrap();
            op.switch(&mut tx).await.unwrap();
            tx.commit().await.unwrap();
        }
    }

    /// An account with a managed library on the store.
    async fn account(pool: &PgPool, journal: &Journal, handle: &str) -> (Uuid, Uuid) {
        let owner = user(pool, handle).await;
        (
            owner,
            library::create(pool, journal, "disk", owner, "Photos").await.unwrap(),
        )
    }

    async fn count(pool: &PgPool, sql: &str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
    }

    /// The keys the store holds besides the libraries' markers.
    async fn objects(journal: &Journal) -> Vec<String> {
        let store = journal.stores().get("disk").unwrap();
        let mut keys = store.list("libraries/").await.unwrap();
        keys.retain(|key| !key.ends_with("marker.json") && !key.contains("/.photolib"));
        keys.sort();
        keys
    }

    /// No row without its object, no object without its row, no intent left open.
    async fn consistent(pool: &PgPool, journal: &Journal, what: &str) {
        let mut rows: Vec<String> = sqlx::query_scalar("SELECT DISTINCT key FROM asset_files")
            .fetch_all(pool)
            .await
            .unwrap();
        rows.sort();
        assert_eq!(rows, objects(journal).await, "{what}");
        let open = "SELECT count(*) FROM file_intents WHERE state IN ('planned', 'switched')";
        assert_eq!(count(pool, open).await, 0, "{what}");
    }

    async fn database() -> testpg::TestDb {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db
    }

    #[tokio::test]
    async fn emptying_deletes_the_owners_trashed_assets_with_their_files_and_objects_and_nothing_else() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let (ann, bob) = (
            account(pool, &journal, "ann").await,
            account(pool, &journal, "bob").await,
        );
        let gone = [
            photo(pool, &journal, ann, Some(1)).await,
            photo(pool, &journal, ann, Some(40)).await,
        ];
        let kept = photo(pool, &journal, ann, None).await;
        let bobs = photo(pool, &journal, bob, Some(1)).await;
        sqlx::query("DELETE FROM tombstones").execute(pool).await.unwrap();

        assert_eq!(purge(pool, &journal, Some(ann.0), FAR).await, Ok(2));

        let left: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM assets ORDER BY id")
            .fetch_all(pool)
            .await
            .unwrap();
        assert_eq!(left, [kept, bobs]);
        assert_eq!(
            objects(&journal).await.len(),
            4,
            "the original and thumbnail of the two that stay"
        );
        consistent(pool, &journal, "emptied").await;
        let tombstones: Vec<String> = sqlx::query_scalar("SELECT key::text FROM tombstones WHERE entity = 'assets'")
            .fetch_all(pool)
            .await
            .unwrap();
        assert_eq!(
            tombstones.len(),
            2,
            "every device learns of each deletion: {tombstones:?}"
        );
        assert!(
            gone.iter()
                .all(|id| tombstones.iter().any(|key| key.contains(&id.to_string())))
        );
        assert_eq!(purge(pool, &journal, Some(ann.0), FAR).await, Ok(0), "again, nothing");
    }

    #[tokio::test]
    async fn what_stayed_in_the_trash_longer_than_the_consoles_retention_goes() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let ann = account(pool, &journal, "ann").await;
        for days in [3, 10, 40] {
            photo(pool, &journal, ann, Some(days)).await;
        }
        let kept = photo(pool, &journal, ann, None).await;
        sqlx::query("UPDATE instance_settings SET trash_retention_days = 7")
            .execute(pool)
            .await
            .unwrap();
        assert_eq!(purge(pool, &journal, None, expired(pool).await.unwrap()).await, Ok(2));
        let left: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM assets WHERE trashed_at IS NULL")
            .fetch_all(pool)
            .await
            .unwrap();
        assert_eq!(
            (left, count(pool, "SELECT count(*) FROM assets").await),
            (vec![kept], 2)
        );
        consistent(pool, &journal, "retention").await;
    }

    #[tokio::test]
    async fn only_what_was_trashed_by_the_cutoff_goes() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let ann = account(pool, &journal, "ann").await;
        photo(pool, &journal, ann, Some(2)).await;
        photo(pool, &journal, ann, Some(0)).await;
        let cutoff: i64 = count(
            pool,
            "SELECT (extract(epoch FROM now() - interval '1 day') * 1000000)::bigint",
        )
        .await;
        assert_eq!(purge(pool, &journal, None, cutoff).await, Ok(1));
        assert_eq!(count(pool, "SELECT count(*) FROM assets").await, 1);
        consistent(pool, &journal, "cutoff").await;
    }

    #[tokio::test]
    async fn a_file_another_asset_still_names_stays_and_external_libraries_are_never_touched() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let ann = account(pool, &journal, "ann").await;
        let (trashed, other) = (
            photo(pool, &journal, ann, Some(1)).await,
            photo(pool, &journal, ann, None).await,
        );
        let shared = format!("libraries/{}/{other}-original", ann.1);
        file(pool, &journal, trashed, "original_alt", &shared).await;
        let external = Uuid::now_v7();
        sqlx::query(
            "INSERT INTO libraries (id, owner_id, name, kind, root_uri, access) VALUES ($1, $2, 'NAS', 'external',
             'file:///nas', 'ro')",
        )
        .bind(external)
        .bind(ann.0)
        .execute(pool)
        .await
        .unwrap();
        let outside = photo(pool, &journal, (ann.0, external), Some(1)).await;

        assert_eq!(purge(pool, &journal, Some(ann.0), FAR).await, Ok(1));

        let left: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM assets ORDER BY id")
            .fetch_all(pool)
            .await
            .unwrap();
        assert!(left.contains(&other) && left.contains(&outside) && !left.contains(&trashed));
        assert_eq!(
            objects(&journal).await.len(),
            4,
            "the shared object and the external asset's stay"
        );
        consistent(pool, &journal, "shared").await;
    }

    #[tokio::test]
    async fn the_count_to_confirm_names_what_is_in_the_trash_and_changes_with_it() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let (ann, bob) = (
            account(pool, &journal, "ann").await,
            account(pool, &journal, "bob").await,
        );
        let who = Principal::User(ann.0, Role::User);
        photo(pool, &journal, bob, Some(1)).await;
        assert_eq!(
            plan(pool, who, ann.0).await.unwrap().0.count,
            0,
            "another account's trash is not ours"
        );
        photo(pool, &journal, ann, Some(1)).await;
        photo(pool, &journal, ann, Some(2)).await;
        photo(pool, &journal, ann, None).await;
        let (first, upto) = plan(pool, who, ann.0).await.unwrap();
        assert_eq!((first.count, first.total), (2, 3));
        assert_eq!(
            plan(pool, who, ann.0).await.unwrap().0.token,
            first.token,
            "stable while it stands"
        );
        let sent = Principal::Anonymous;
        assert_eq!(
            plan(pool, sent, ann.0).await.unwrap().0.count,
            0,
            "nobody may delete what they cannot see"
        );
        photo(pool, &journal, ann, Some(0)).await;
        let (second, later) = plan(pool, who, ann.0).await.unwrap();
        assert_eq!(second.count, 3);
        assert!(
            later > upto && second.token != first.token,
            "a token covers no more than it counted"
        );
    }

    async fn queued(pool: &PgPool) -> Vec<(String, serde_json::Value)> {
        let jobs: Vec<(String, Vec<u8>)> = sqlx::query_as("SELECT type, payload FROM jobs ORDER BY created_at")
            .fetch_all(pool)
            .await
            .unwrap();
        jobs.into_iter()
            .map(|(kind, payload)| (kind, serde_json::from_slice(&payload).unwrap()))
            .collect()
    }

    #[tokio::test]
    async fn a_large_trash_waits_for_the_token_of_its_count_before_a_job_is_queued() {
        let db = database().await;
        let (dir, pool) = (tempfile::tempdir().unwrap(), &db.pool);
        let journal = journal(pool, dir.path(), no_hook()).await;
        let ann = account(pool, &journal, "ann").await;
        let who = Principal::User(ann.0, Role::User);
        assert_eq!(
            empty(pool, who, ann.0, "").await.unwrap().ok(),
            Some(0),
            "an empty trash needs no one"
        );
        assert_eq!(queued(pool).await.len(), 0);

        let many = "INSERT INTO assets (id, library_id, owner_id, source, media_kind, trashed_at)
                    SELECT photolib_uuidv7(), $1, $2, 'upload', 'image', now() FROM generate_series(1, $3)";
        let insert = |n: i32| sqlx::query(many).bind(ann.1).bind(ann.0).bind(n).execute(pool);
        insert(1001).await.unwrap();
        let Err(held) = empty(pool, who, ann.0, "").await.unwrap() else {
            panic!("over 1,000 items wait for their confirmation");
        };
        assert_eq!((held.count, held.total), (1001, 1001));
        assert!(queued(pool).await.is_empty(), "nothing is queued, nothing deleted");
        assert!(empty(pool, who, ann.0, "wrong").await.unwrap().is_err());
        insert(1).await.unwrap();
        assert!(
            empty(pool, who, ann.0, &held.token).await.unwrap().is_err(),
            "the token covers the count it was given for"
        );
        let Err(held) = empty(pool, who, ann.0, "").await.unwrap() else {
            unreachable!()
        };
        assert_eq!(empty(pool, who, ann.0, &held.token).await.unwrap().ok(), Some(1002));
        let jobs = queued(pool).await;
        assert_eq!(jobs.len(), 1);
        assert_eq!(jobs[0].0, EMPTY);
        assert_eq!(jobs[0].1["owner"], ann.0.to_string());
    }

    /// What a crash child does: empty `owner`'s trash, killed at the `kill_at`th step of the journal.
    #[derive(Serialize, Deserialize)]
    struct Crash {
        url: String,
        dir: PathBuf,
        owner: Uuid,
        kill_at: usize,
    }

    /// Run only by `emptying_killed_at_any_step_leaves_no_row_without_its_file_and_no_file_without_its_row`.
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
        let journal = journal(&pool, &crash.dir, hook).await;
        purge(&pool, &journal, Some(crash.owner), FAR).await.unwrap();
    }

    #[tokio::test]
    async fn emptying_killed_at_any_step_leaves_no_row_without_its_file_and_no_file_without_its_row() {
        // Per asset: a delete planned for each of two files, then the two deleted.
        let steps = ["planned", "planned", "deleted", "deleted"].repeat(3);
        for kill_at in 1..=steps.len() + 1 {
            let db = database().await;
            let pool = &db.pool;
            let dir = tempfile::tempdir().unwrap();
            let journal = journal(pool, dir.path(), no_hook()).await;
            let ann = account(pool, &journal, "ann").await;
            for _ in 0..3 {
                photo(pool, &journal, ann, Some(1)).await;
            }
            let crash = Crash {
                url: db.url.clone(),
                dir: dir.path().to_owned(),
                owner: ann.0,
                kill_at,
            };
            let child = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "trash::tests::crash_child",
                    "--exact",
                    "--nocapture",
                    "--test-threads=1",
                ])
                .env(CRASH, serde_json::to_string(&crash).unwrap())
                .output()
                .unwrap();
            let log = String::from_utf8_lossy(&child.stderr);
            let seen: Vec<_> = log.lines().filter_map(|line| line.strip_prefix("step ")).collect();
            let what = format!("killed at step {kill_at}: {log}");
            if kill_at <= steps.len() {
                let killed = (child.status.signal(), &seen[..]);
                assert_eq!(killed, (Some(9), &steps[..kill_at]), "{what}");
            } else {
                assert_eq!((child.status.success(), &seen[..]), (true, &steps[..]), "{what}");
            }
            for _ in 0..100 {
                if journal.recover().await.unwrap().busy == 0 {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
            consistent(pool, &journal, &what).await;
            assert_eq!(
                purge(pool, &journal, Some(ann.0), FAR).await.map(|_| ()),
                Ok(()),
                "{what}"
            );
            consistent(pool, &journal, &what).await;
            assert_eq!(
                count(
                    pool,
                    &format!("SELECT count(*) FROM assets WHERE owner_id = '{}'", ann.0)
                )
                .await,
                0,
                "{what}"
            );
        }
    }
}
