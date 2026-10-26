//! Integrity scrubbing (photolib-design docs/07 §8, ADR-0022 point 6, ADR-0234). The `scrub` job, which the scheduler
//! queues every 15 minutes, goes through each online store's files in id order, as fast as covers the store once in
//! the settings' `scrub_days`. On a filesystem it reads and hashes every byte; on an object store its routine cycle
//! HEADs each object for its presence, size and stored hash, and a full re-hash, where the configuration turns it on,
//! downloads them within a monthly egress budget. A routine cycle ends by listing the store's libraries for orphans.
//! What does not match is an integrity finding until a later check finds the object as recorded. External libraries'
//! files are read at their libraries' rates as one more store, `external`: bytes that changed while the file did not
//! are bit-rot, and a file gone or changed since it was hashed is left to rescans.

use std::{
    collections::{BTreeMap, HashMap, HashSet, hash_map::Entry},
    sync::Arc,
};

use async_trait::async_trait;
use photolib_jobs::{Handler, Job};
use photolib_storage::{BlobStore, Error, Hash, Meta, fs::Identity, journal::Journal};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::{
    config::Config,
    external::{self, Libraries, Library, Read},
};

/// The job type.
pub const SCRUB: &str = "scrub";
/// What a read asks a store for at once.
const CHUNK: u64 = 16 << 20;
/// The files a scrub checks: originals and what else no job can make again, each object once, with their library.
const FILES: &str = "SELECT f.id, f.key, f.size, f.content_hash, a.library_id FROM asset_files f
    JOIN assets a ON a.id = f.asset_id WHERE f.storage = $1 AND f.id > $2 AND f.byte_offset IS NULL
      AND f.render_spec IS NULL AND f.size IS NOT NULL AND f.content_hash IS NOT NULL ORDER BY f.id LIMIT 100";
/// Resolves the findings of a store's objects that no file or upload names any longer: nothing is left to repair.
const UNNAMED: &str = "UPDATE integrity_findings i SET resolved_at = now()
    WHERE store = $1 AND kind <> 'orphan' AND resolved_at IS NULL
      AND NOT EXISTS (SELECT FROM asset_files f JOIN assets a ON a.id = f.asset_id WHERE f.storage = i.store
        AND f.key = i.key AND a.library_id = coalesce(i.library_id, a.library_id))
      AND NOT EXISTS (SELECT FROM uploads u WHERE u.store = i.store AND u.key = i.key)";
const CYCLE_BYTES: &str = "UPDATE scrubs SET cycle_bytes = (SELECT coalesce(sum(size), 0)::bigint FROM asset_files
    WHERE storage = $1 AND byte_offset IS NULL AND render_spec IS NULL AND content_hash IS NOT NULL) WHERE store = $1";

/// How the scrub reads a store's objects; a store with neither only has them HEADed.
#[derive(Clone, Copy, Debug)]
pub enum Reads {
    /// Every object in the routine cycle: a filesystem's reads cost only time.
    Always,
    /// A full re-hash besides the routine cycle, downloading at most this many bytes a calendar month (UTC).
    Monthly(u64),
}

/// Which cursor a pass moves: the routine cycle's or the full re-hash's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Pass {
    /// Every object's presence, size and stored hash, and on a filesystem its bytes; then the orphans.
    Check,
    /// Every object's bytes, downloaded within the store's monthly budget.
    Rehash,
}

impl Pass {
    /// The column of `scrubs` that holds the pass's cursor.
    fn cursor(self) -> &'static str {
        match self {
            Self::Check => "checked_after",
            Self::Rehash => "read_after",
        }
    }
}

/// What a pass did.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Done {
    /// The files it checked.
    pub files: usize,
    /// The bytes it read, which on an object store are downloaded.
    pub read: u64,
    /// It went through the last file, so the next pass starts a cycle.
    pub cycle_ended: bool,
}

/// The handler of the `scrub` job.
pub struct Scrub {
    pool: PgPool,
    journal: Arc<Journal>,
    reads: BTreeMap<String, Reads>,
    libraries: Arc<Libraries>,
}

/// How the scrub reads each store of `config`: the data directory always, an object store within its re-hash budget.
pub fn reads(config: &Config) -> BTreeMap<String, Reads> {
    let budgets = (config.stores.iter()).filter_map(|(name, store)| {
        Some((
            name.clone(),
            Reads::Monthly(u64::from(store.rehash_gib_per_month?) << 30),
        ))
    });
    std::iter::once(("local".into(), Reads::Always))
        .chain(budgets)
        .collect()
}

fn text(error: impl std::fmt::Display) -> String {
    error.to_string()
}

impl Scrub {
    /// Scrubs the stores of `journal`, reading them as `reads` says, and the external `libraries`.
    pub fn new(pool: PgPool, journal: Arc<Journal>, reads: BTreeMap<String, Reads>, libraries: Arc<Libraries>) -> Self {
        Self {
            pool,
            journal,
            reads,
            libraries,
        }
    }

    /// Scrubs `store` as far as the time since its last run allows: the bytes of a cycle times that time, at most a
    /// day of it, over `scrub_days`, and at least one file. A store another scrub holds is left to it, so that two
    /// never count the same month's egress.
    pub async fn scrub(&self, store: &str) -> Result<(), String> {
        let mut lock = self.pool.acquire().await.map_err(text)?;
        let name = format!("scrub {store}");
        let held: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock(hashtextextended($1, 0))")
            .bind(&name)
            .fetch_one(&mut *lock)
            .await
            .map_err(text)?;
        if !held {
            return Ok(());
        }
        let scrubbed = self.paced(store).await;
        let unlocked = sqlx::query("SELECT pg_advisory_unlock(hashtextextended($1, 0))")
            .bind(&name)
            .execute(&mut *lock)
            .await;
        if unlocked.is_err() {
            // Closed, the connection lets the lock go.
            drop(lock.detach());
        }
        scrubbed
    }

    async fn paced(&self, store: &str) -> Result<(), String> {
        let mut conn = self.pool.acquire().await.map_err(text)?;
        begin(&mut conn, store).await.map_err(text)?;
        let allowance: i64 = sqlx::query_scalar(
            "UPDATE scrubs s SET ran_at = now() FROM scrubs old, instance_settings i WHERE s.store = $1 AND old.store = $1
             RETURNING greatest(1, floor(s.cycle_bytes * least(extract(EPOCH FROM now() - old.ran_at), 86400)
               / (i.scrub_days * 86400.0)))::bigint",
        )
        .bind(store)
        .fetch_one(&mut *conn)
        .await
        .map_err(text)?;
        let allowance = u64::try_from(allowance).unwrap_or_default();
        self.pass(store, Pass::Check, allowance).await?;
        self.pass(store, Pass::Rehash, allowance).await.map(drop)
    }

    /// Checks the files of `store` after the cursor of `pass` until `allowance` bytes of them are checked, or a
    /// re-hash's next download would exceed the month's budget.
    pub async fn pass(&self, store: &str, pass: Pass, allowance: u64) -> Result<Done, String> {
        let blobs = if store == external::STORE {
            None
        } else {
            Some(self.journal.stores().get(store).map_err(text)?.clone())
        };
        let (read, budget) = match (pass, self.reads.get(store)) {
            (Pass::Check, reads) => (blobs.is_none() || matches!(reads, Some(Reads::Always)), None),
            (Pass::Rehash, Some(Reads::Monthly(budget))) => (true, Some(*budget)),
            (Pass::Rehash, _) => return Ok(Done::default()),
        };
        let cursor = pass.cursor();
        let mut conn = self.pool.acquire().await.map_err(text)?;
        let (mut after, mut egress, open) = start(&mut conn, store, cursor).await.map_err(text)?;
        let (mut done, mut checked, mut opened) = (Done::default(), 0u64, HashMap::new());
        loop {
            let rows: Vec<(Uuid, String, i64, Vec<u8>, Uuid)> = sqlx::query_as(FILES)
                .bind(store)
                .bind(after)
                .fetch_all(&mut *conn)
                .await
                .map_err(text)?;
            if rows.is_empty() {
                break;
            }
            for (id, key, size, hash, library) in rows {
                let size = u64::try_from(size).unwrap_or_default();
                let Ok(hash) = hash.try_into().map(Hash) else {
                    return Err(format!("{key:?} has a malformed hash"));
                };
                let over = budget.is_some_and(|budget| egress.saturating_add(size) > budget);
                if checked >= allowance || over {
                    return Ok(done);
                }
                let (found, library) = if let Some(blobs) = &blobs {
                    (Some(verify(blobs.as_ref(), &key, size, hash, read).await?), None)
                } else {
                    let found = self.external(&mut conn, &mut opened, library, &key, hash).await?;
                    (found, Some(library))
                };
                let at = (store, library, key.as_str());
                match found {
                    Some(Some((kind, detail))) => record(&mut conn, at, kind, &detail).await?,
                    Some(None) if open.contains(&(library, key.clone())) => resolve(&mut conn, at, read).await?,
                    _ => {}
                }
                after = id;
                checked = checked.saturating_add(size.max(1));
                done.files = done.files.saturating_add(1);
                if read {
                    egress = egress.saturating_add(size);
                    done.read = done.read.saturating_add(size);
                }
                sqlx::query(&format!(
                    "UPDATE scrubs SET {cursor} = $2, egress_bytes = $3 WHERE store = $1"
                ))
                .bind(store)
                .bind(after)
                .bind(i64::try_from(egress).unwrap_or(i64::MAX))
                .execute(&mut *conn)
                .await
                .map_err(text)?;
            }
        }
        end(&mut conn, store, pass, blobs.as_deref()).await?;
        done.cycle_ended = true;
        Ok(done)
    }

    /// What is wrong with the file `key` of the external library `id`, hashed as `hash`: bytes that differ while it is
    /// still the file that was hashed, as bit-rot leaves it, or that cannot be read. `None` when it is gone or changed
    /// since, or its library cannot be opened: rescans see to those. `opened` keeps each library a pass opens.
    async fn external(
        &self,
        conn: &mut PgConnection,
        opened: &mut HashMap<Uuid, Option<Library>>,
        id: Uuid,
        key: &str,
        hash: Hash,
    ) -> Result<Option<Option<(&'static str, String)>>, String> {
        if let Entry::Vacant(vacant) = opened.entry(id) {
            let library = self.libraries.open(conn, id).await;
            vacant.insert(library.unwrap_or_else(|error| {
                tracing::warn!(library = %id, error, "an external library cannot be scrubbed");
                None
            }));
        }
        let Some(Some(library)) = opened.get(&id) else {
            return Ok(None);
        };
        let (dir, name) = key.rsplit_once('/').unwrap_or(("", key));
        let identity: Option<(i64, i64, i64, i64)> = sqlx::query_as(
            "SELECT dev, inode, size, mtime_ns FROM library_files WHERE library_id = $1 AND dir = $2 AND name = $3",
        )
        .bind(id)
        .bind(dir)
        .bind(name)
        .fetch_optional(conn)
        .await
        .map_err(text)?;
        let Some((dev, inode, size, mtime_ns)) = identity else {
            return Ok(None);
        };
        let (dev, inode, size) = (dev.cast_unsigned(), inode.cast_unsigned(), size.cast_unsigned());
        let identity = Identity {
            dev,
            inode,
            size,
            mtime_ns,
        };
        Ok(match external::hash(library, key, identity).await? {
            Read::Hashed(found) if found == hash => Some(None),
            Read::Hashed(found) => {
                let detail = format!("it reads as {found:?}, {hash:?} recorded, though it was not written since");
                Some(Some(("content", detail)))
            }
            Read::Failed(error) => Some(Some(("content", format!("it cannot be read: {error}")))),
            Read::Changed => None,
        })
    }
}

/// Ends a pass through the last file: a routine cycle reports a store's orphans, resolves the findings nothing names
/// and measures the next cycle, and the pass's cursor starts over.
async fn end(conn: &mut PgConnection, store: &str, pass: Pass, blobs: Option<&dyn BlobStore>) -> Result<(), String> {
    if pass == Pass::Check {
        if let Some(blobs) = blobs {
            orphans(conn, store, blobs).await?;
        }
        for query in [UNNAMED, CYCLE_BYTES] {
            sqlx::query(query).bind(store).execute(&mut *conn).await.map_err(text)?;
        }
    }
    sqlx::query(&format!(
        "UPDATE scrubs SET {} = '00000000-0000-0000-0000-000000000000',
           cycle_ended_at = CASE WHEN $2 THEN now() ELSE cycle_ended_at END WHERE store = $1",
        pass.cursor()
    ))
    .bind(store)
    .bind(pass == Pass::Check)
    .execute(conn)
    .await
    .map_err(text)?;
    Ok(())
}

/// Gives `store` its row, measuring its first cycle.
async fn begin(conn: &mut PgConnection, store: &str) -> sqlx::Result<()> {
    let started = sqlx::query("INSERT INTO scrubs (store) VALUES ($1) ON CONFLICT DO NOTHING")
        .bind(store)
        .execute(&mut *conn)
        .await?;
    if started.rows_affected() > 0 {
        sqlx::query(CYCLE_BYTES).bind(store).execute(conn).await?;
    }
    Ok(())
}

/// The library (of an external file) and key of each object with an open finding.
type Open = HashSet<(Option<Uuid>, String)>;

/// Where a pass of `store` starts: after the file in `cursor`, with what the month's egress has spent (a new month
/// starts with its whole budget), and the objects with open findings.
async fn start(conn: &mut PgConnection, store: &str, cursor: &str) -> sqlx::Result<(Uuid, u64, Open)> {
    begin(conn, store).await?;
    let (after, egress): (Uuid, i64) = sqlx::query_as(&format!(
        "UPDATE scrubs SET egress_month = date_trunc('month', now() AT TIME ZONE 'UTC')::date,
           egress_bytes = CASE WHEN egress_month = date_trunc('month', now() AT TIME ZONE 'UTC')::date
             THEN egress_bytes ELSE 0 END
         WHERE store = $1 RETURNING {cursor}, egress_bytes"
    ))
    .bind(store)
    .fetch_one(&mut *conn)
    .await?;
    let open =
        sqlx::query_as("SELECT library_id, key FROM integrity_findings WHERE store = $1 AND resolved_at IS NULL")
            .bind(store)
            .fetch_all(conn)
            .await?;
    Ok((
        after,
        u64::try_from(egress).unwrap_or_default(),
        open.into_iter().collect(),
    ))
}

#[async_trait]
impl Handler for Scrub {
    /// Scrubs every online store, then the external libraries; one that fails leaves the others to go on.
    async fn run(&self, _job: &Job, _tx: &mut PgConnection) -> Result<(), String> {
        let mut failed = vec![];
        let external: bool = sqlx::query_scalar("SELECT EXISTS (SELECT FROM libraries WHERE kind = 'external')")
            .fetch_one(&self.pool)
            .await
            .map_err(text)?;
        let stores = self.journal.stores().online().map(|(store, _)| store);
        for store in stores.chain(external.then_some(external::STORE)) {
            if let Err(error) = self.scrub(store).await {
                failed.push(format!("{store}: {error}"));
            }
        }
        if failed.is_empty() {
            Ok(())
        } else {
            Err(failed.join("; "))
        }
    }
}

/// What is wrong with the object `key`, recorded as `size` bytes of `hash`, `None` when it is as recorded; `read`
/// hashes its bytes. A timeout or an offline store fails the pass, which the next run repeats; another error that
/// happens twice makes the object unreadable.
async fn verify(
    blobs: &dyn BlobStore,
    key: &str,
    size: u64,
    hash: Hash,
    read: bool,
) -> Result<Option<(&'static str, String)>, String> {
    let checked = match check(blobs, key, size, hash, read).await {
        Err(Error::Other(_)) => check(blobs, key, size, hash, read).await,
        checked => checked,
    };
    match checked {
        Ok(found) => Ok(found),
        Err(Error::NotFound(_)) => Ok(Some(("missing", "it is gone".into()))),
        Err(error @ (Error::Timeout(_) | Error::Offline(_))) => Err(error.to_string()),
        Err(error) => Ok(Some(("content", format!("it cannot be read: {error}")))),
    }
}

async fn check(
    blobs: &dyn BlobStore,
    key: &str,
    size: u64,
    hash: Hash,
    read: bool,
) -> Result<Option<(&'static str, String)>, Error> {
    Ok(match blobs.head(key).await? {
        None => Some(("missing", "it is gone".into())),
        Some(meta) if meta.size != size => Some(("size", format!("it has {} bytes, {size} recorded", meta.size))),
        Some(Meta { hash: Some(found), .. }) if found != hash => {
            Some(("hash", format!("it carries {found:?}, {hash:?} recorded")))
        }
        Some(_) if read => {
            let found = hash_of(blobs, key, size).await?;
            (found != hash).then(|| ("content", format!("it reads as {found:?}, {hash:?} recorded")))
        }
        Some(_) => None,
    })
}

async fn hash_of(blobs: &dyn BlobStore, key: &str, size: u64) -> Result<Hash, Error> {
    let mut hasher = blake3::Hasher::new();
    let mut offset = 0;
    while offset < size {
        let chunk = blobs
            .get(key, Some(offset..size.min(offset.saturating_add(CHUNK))))
            .await?;
        if chunk.is_empty() {
            break;
        }
        hasher.update(&chunk);
        offset = offset.saturating_add(u64::try_from(chunk.len()).unwrap_or(u64::MAX));
    }
    Ok(hasher.finalize().into())
}

/// An object: its store, the library of an external file, and its key.
type At<'a> = (&'a str, Option<Uuid>, &'a str);

/// Records a finding unless the same one is open.
async fn record(
    conn: &mut PgConnection,
    (store, library, key): At<'_>,
    kind: &str,
    detail: &str,
) -> Result<(), String> {
    tracing::warn!(store, key, kind, detail, "integrity finding");
    sqlx::query(
        "INSERT INTO integrity_findings (id, store, key, kind, detail, library_id) SELECT $1, $2, $3, $4, $5, $6
         WHERE NOT EXISTS (SELECT FROM integrity_findings WHERE store = $2 AND key = $3 AND kind = $4
           AND library_id IS NOT DISTINCT FROM $6 AND resolved_at IS NULL)",
    )
    .bind(Uuid::now_v7())
    .bind(store)
    .bind(key)
    .bind(kind)
    .bind(detail)
    .bind(library)
    .execute(conn)
    .await
    .map_err(text)?;
    Ok(())
}

/// Resolves the open findings of an object found as recorded; bytes count as recorded only once read.
async fn resolve(conn: &mut PgConnection, (store, library, key): At<'_>, read: bool) -> Result<(), String> {
    sqlx::query(
        "UPDATE integrity_findings SET resolved_at = now() WHERE store = $1 AND key = $2
           AND library_id IS NOT DISTINCT FROM $4 AND resolved_at IS NULL AND (kind <> 'content' OR $3)",
    )
    .bind(store)
    .bind(key)
    .bind(read)
    .bind(library)
    .execute(conn)
    .await
    .map_err(text)?;
    Ok(())
}

/// Reports the objects under the store's libraries that no file, upload or open intent names, never their markers,
/// and resolves the orphans since gone or named.
async fn orphans(conn: &mut PgConnection, store: &str, blobs: &dyn BlobStore) -> Result<(), String> {
    let listed = blobs.list("libraries/").await.map_err(text)?;
    let listed: Vec<String> = listed.into_iter().filter(|key| !key.contains("/.photolib/")).collect();
    let mut orphans = vec![];
    for keys in listed.chunks(1000) {
        let named: HashSet<String> = sqlx::query_scalar(
            "SELECT key FROM asset_files WHERE storage = $1 AND key = ANY($2)
             UNION SELECT key FROM uploads WHERE store = $1 AND key = ANY($2)
             UNION SELECT key FROM file_intents WHERE store = $1 AND key = ANY($2) AND state IN ('planned', 'switched')",
        )
        .bind(store)
        .bind(keys)
        .fetch_all(&mut *conn)
        .await
        .map_err(text)?
        .into_iter()
        .collect();
        for key in keys.iter().filter(|key| !named.contains(*key)) {
            // A write rolled back since the listing leaves nothing behind.
            if blobs.head(key).await.map_err(text)?.is_some() {
                record(conn, (store, None, key), "orphan", "no file names it").await?;
                orphans.push(key.clone());
            }
        }
    }
    sqlx::query(
        "UPDATE integrity_findings SET resolved_at = now()
         WHERE store = $1 AND kind = 'orphan' AND resolved_at IS NULL AND NOT key = ANY($2)",
    )
    .bind(store)
    .bind(&orphans)
    .execute(conn)
    .await
    .map_err(text)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        os::unix::fs::{FileExt, MetadataExt, PermissionsExt},
        path::Path,
        time::Duration,
    };

    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_storage::{
        BlobStore, Hash,
        fs::FsStore,
        marker::{Candidate, Stores},
        s3::S3Store,
        testing,
    };
    use uuid::Uuid;

    use super::*;
    use crate::{
        config::{Store, StoreKind},
        library,
        secret::Secret,
    };

    const TIMEOUT: Duration = Duration::from_secs(30);

    /// A scrub of a filesystem store `fs`, which it reads, and of a fresh Garage prefix `s3`; returns it with the
    /// store's root and Garage driver, which tests damage objects through.
    async fn scrub(reads: Option<Reads>) -> (Scrub, tempfile::TempDir, S3Store) {
        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
        let root = tempfile::tempdir().unwrap();
        let s3 = testing::garage();
        let stores: [(&str, Arc<dyn BlobStore>); 2] = [
            ("fs", Arc::new(FsStore::open(root.path(), TIMEOUT).await.unwrap())),
            ("s3", Arc::new(S3Store::open(&s3, TIMEOUT).unwrap())),
        ];
        let candidates = (stores.into_iter())
            .map(|(name, store)| Candidate {
                name: name.into(),
                store,
                adopt: false,
            })
            .collect();
        let stores = Stores::check(&pool, Uuid::now_v7(), candidates).await;
        let journal = Arc::new(Journal::start(pool.clone(), stores).await.unwrap());
        let mut policy = BTreeMap::from([("fs".to_string(), Reads::Always)]);
        policy.extend(reads.map(|reads| ("s3".to_string(), reads)));
        let libraries = Arc::new(Libraries::new(TIMEOUT));
        let scrub = Scrub::new(pool, journal, policy, libraries);
        (scrub, root, S3Store::open(&s3, TIMEOUT).unwrap())
    }

    /// A library on `store` whose originals are `files`; returns their keys.
    async fn originals(scrub: &Scrub, store: &str, files: &[&[u8]]) -> Vec<String> {
        let (pool, journal) = (&scrub.pool, &scrub.journal);
        let owner = Uuid::now_v7();
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, $1::text, 'Ann')")
            .bind(owner)
            .execute(pool)
            .await
            .unwrap();
        let id = library::create(pool, journal, store, owner, "Photos").await.unwrap();
        let staging = tempfile::tempdir().unwrap();
        let mut keys = vec![];
        for (i, bytes) in files.iter().enumerate() {
            let (staged, hash) = testing::staged(staging.path(), bytes);
            let key = format!("{}/originals/IMG_{i}.jpg", library::root(id));
            let op = journal.put(store, &key, &staged, hash).await.unwrap();
            let mut tx = pool.begin().await.unwrap();
            sqlx::query(
                "WITH a AS (INSERT INTO assets (id, library_id, owner_id, original_filename, source, content_hash)
                   VALUES (photolib_uuidv7(), $1, $2, $3, 'upload', $5) RETURNING id)
                 INSERT INTO asset_files (id, asset_id, role, storage, key, size, content_hash)
                 SELECT photolib_uuidv7(), id, 'original', $4, $3, $6, $5 FROM a",
            )
            .bind(id)
            .bind(owner)
            .bind(&key)
            .bind(store)
            .bind(hash.0.to_vec())
            .bind(i64::try_from(bytes.len()).unwrap())
            .execute(&mut *tx)
            .await
            .unwrap();
            op.settle(&mut tx).await.unwrap();
            tx.commit().await.unwrap();
            keys.push(key);
        }
        keys
    }

    /// The findings, open ones as `(key, kind)` and how many are resolved.
    async fn findings(scrub: &Scrub) -> (Vec<(String, String)>, i64) {
        let open = "SELECT key, kind FROM integrity_findings WHERE resolved_at IS NULL ORDER BY key, kind";
        let resolved = "SELECT count(*) FROM integrity_findings WHERE resolved_at IS NOT NULL";
        (
            sqlx::query_as(open).fetch_all(&scrub.pool).await.unwrap(),
            sqlx::query_scalar(resolved).fetch_one(&scrub.pool).await.unwrap(),
        )
    }

    fn flip(path: &Path, at: u64) {
        let file = std::fs::OpenOptions::new().read(true).write(true).open(path).unwrap();
        let mut byte = [0];
        file.read_exact_at(&mut byte, at).unwrap();
        file.write_all_at(&[byte[0] ^ 0x20], at).unwrap();
    }

    #[test]
    fn the_data_directory_is_read_and_object_stores_are_rehashed_where_configured() {
        let mut config = crate::testing::config(&[], Path::new("/srv"));
        for (name, rehash) in [("b2", None), ("wasabi", Some(2))] {
            let store = Store {
                kind: StoreKind::S3,
                endpoint: "https://s3.example".into(),
                bucket: "photolib".into(),
                region: "eu".into(),
                prefix: String::new(),
                access_key_id: "id".into(),
                secret_access_key: Secret::new("secret".into()),
                timeout_secs: 120,
                rehash_gib_per_month: rehash,
            };
            config.stores.insert(name.into(), store);
        }
        let reads: Vec<_> = reads(&config)
            .into_iter()
            .map(|(name, reads)| format!("{name} {reads:?}"))
            .collect();
        assert_eq!(reads, ["local Always", "wasabi Monthly(2147483648)"]);
    }

    #[tokio::test]
    async fn bit_rot_on_a_filesystem_is_found_in_one_cycle_and_resolved_once_repaired() {
        let (scrub, root, _) = scrub(None).await;
        let keys = originals(&scrub, "fs", &[b"first photo", b"second photo", b"third photo"]).await;
        flip(&root.path().join(&keys[1]), 3);
        let done = scrub.pass("fs", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(
            done,
            Done {
                files: 3,
                read: 34,
                cycle_ended: true
            }
        );
        assert_eq!(findings(&scrub).await, (vec![(keys[1].clone(), "content".into())], 0));
        scrub.pass("fs", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(findings(&scrub).await.0.len(), 1, "a finding is reported once");
        flip(&root.path().join(&keys[1]), 3);
        scrub.pass("fs", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(findings(&scrub).await, (vec![], 1));
    }

    #[tokio::test]
    async fn on_garage_the_routine_cycle_finds_a_deleted_a_truncated_and_an_orphaned_object_with_heads_only() {
        let (scrub, _root, s3) = scrub(None).await;
        let photos: [&[u8]; 4] = [b"deleted", b"truncated", b"replaced", b"intact"];
        let keys = originals(&scrub, "s3", &photos).await;
        s3.delete(&keys[0]).await.unwrap();
        s3.forge(&keys[1], b"trunc".to_vec(), Hash::of(b"trunc")).await.unwrap();
        // Same size and recorded hash: only reading it tells.
        s3.forge(&keys[2], b"REPLACED".to_vec(), Hash::of(b"replaced"))
            .await
            .unwrap();
        let stray = keys[3].replace("IMG_3", "stray");
        s3.forge(&stray, b"stray".to_vec(), Hash::of(b"stray")).await.unwrap();
        let done = scrub.pass("s3", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!((done.files, done.read, done.cycle_ended), (4, 0, true));
        let found = |key: &String, kind: &str| (key.clone(), kind.to_string());
        let expected = vec![
            found(&keys[0], "missing"),
            found(&keys[1], "size"),
            found(&stray, "orphan"),
        ];
        assert_eq!(findings(&scrub).await, (expected, 0));
        s3.delete(&stray).await.unwrap();
        s3.forge(&keys[0], b"deleted".to_vec(), Hash::of(b"deleted"))
            .await
            .unwrap();
        scrub.pass("s3", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(
            findings(&scrub).await,
            (vec![found(&keys[1], "size")], 2),
            "what was put back is resolved"
        );
    }

    #[tokio::test]
    async fn a_full_rehash_finds_a_replaced_object_and_downloads_no_more_than_its_monthly_budget() {
        let (scrub, _root, s3) = scrub(Some(Reads::Monthly(2500))).await;
        let photos = [[1u8; 1000], [2; 1000], [3; 1000]];
        let keys = originals(&scrub, "s3", &photos.each_ref().map(|p| &p[..])).await;
        s3.forge(&keys[0], vec![9; 1000], Hash::of(&photos[0])).await.unwrap();
        s3.forge(&keys[2], vec![9; 1000], Hash::of(&photos[2])).await.unwrap();
        let routine = scrub.pass("s3", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(
            (routine.read, findings(&scrub).await.0.len()),
            (0, 0),
            "HEADs cannot tell"
        );
        let first = scrub.pass("s3", Pass::Rehash, u64::MAX).await.unwrap();
        assert_eq!((first.files, first.read, first.cycle_ended), (2, 2000, false));
        let found = |key: &String| (key.clone(), "content".to_string());
        assert_eq!(findings(&scrub).await, (vec![found(&keys[0])], 0));
        let spent = "SELECT egress_bytes FROM scrubs WHERE store = 's3'";
        assert_eq!(
            sqlx::query_scalar::<_, i64>(spent)
                .fetch_one(&scrub.pool)
                .await
                .unwrap(),
            2000
        );
        let again = scrub.pass("s3", Pass::Rehash, u64::MAX).await.unwrap();
        assert_eq!(again, Done::default(), "the month's budget is spent");
        sqlx::query("UPDATE scrubs SET egress_month = egress_month - interval '1 month'")
            .execute(&scrub.pool)
            .await
            .unwrap();
        let next = scrub.pass("s3", Pass::Rehash, u64::MAX).await.unwrap();
        assert_eq!((next.files, next.read, next.cycle_ended), (1, 1000, true));
        assert_eq!(findings(&scrub).await.0, vec![found(&keys[0]), found(&keys[2])]);
        assert_eq!(
            sqlx::query_scalar::<_, i64>(spent)
                .fetch_one(&scrub.pool)
                .await
                .unwrap(),
            1000
        );
    }

    /// A finding about a file that no asset holds any longer, deleted by its owner, has nothing left to repair: the
    /// end of the next cycle resolves it, so that its alert stops.
    #[tokio::test]
    async fn a_finding_whose_file_is_deleted_is_resolved_when_the_next_cycle_ends() {
        let (scrub, root, _) = scrub(None).await;
        let keys = originals(&scrub, "fs", &[b"first photo", b"second photo"]).await;
        flip(&root.path().join(&keys[1]), 3);
        scrub.pass("fs", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(findings(&scrub).await, (vec![(keys[1].clone(), "content".into())], 0));
        sqlx::query("DELETE FROM assets WHERE id = (SELECT asset_id FROM asset_files WHERE key = $1)")
            .bind(&keys[1])
            .execute(&scrub.pool)
            .await
            .unwrap();
        std::fs::remove_file(root.path().join(&keys[1])).unwrap();
        scrub.pass("fs", Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(findings(&scrub).await, (vec![], 1));
    }

    /// A run checks what the time since the last one allows of `scrub_days`, at least one file.
    #[tokio::test]
    async fn a_run_checks_each_store_at_the_pace_of_its_cycle() {
        let (scrub, root, s3) = scrub(None).await;
        let keys = originals(&scrub, "fs", &[&[1; 100], &[2; 100], &[3; 100], &[4; 100]]).await;
        let gone = originals(&scrub, "s3", &[b"gone"]).await;
        s3.delete(&gone[0]).await.unwrap();
        flip(&root.path().join(&keys[3]), 0);
        sqlx::query("UPDATE instance_settings SET scrub_days = 1")
            .execute(&scrub.pool)
            .await
            .unwrap();
        let run = async |hours_ago: i32| {
            sqlx::query("UPDATE scrubs SET ran_at = now() - make_interval(hours => $1)")
                .bind(hours_ago)
                .execute(&scrub.pool)
                .await
                .unwrap();
            for store in ["fs", "s3"] {
                scrub.scrub(store).await.unwrap();
            }
            let at = "SELECT f.key FROM scrubs s JOIN asset_files f ON f.id = s.checked_after WHERE s.store = 'fs'";
            sqlx::query_scalar::<_, String>(at)
                .fetch_optional(&scrub.pool)
                .await
                .unwrap()
        };
        assert_eq!(run(0).await.as_ref(), Some(&keys[0]), "the first run checks one file");
        assert_eq!(findings(&scrub).await.0, [(gone[0].clone(), "missing".into())]);
        // Six hours of a one-day cycle: a quarter of the 400 bytes, one file.
        assert_eq!(run(6).await.as_ref(), Some(&keys[1]));
        assert_eq!(run(18).await, None, "the rest of the day finishes the cycle");
        let mut expected = vec![(gone[0].clone(), "missing".into()), (keys[3].clone(), "content".into())];
        expected.sort();
        assert_eq!(findings(&scrub).await.0, expected);
        let ended = "SELECT count(*) FROM scrubs WHERE cycle_ended_at IS NOT NULL";
        assert_eq!(
            sqlx::query_scalar::<_, i64>(ended)
                .fetch_one(&scrub.pool)
                .await
                .unwrap(),
            2
        );
        let mut other = scrub.pool.acquire().await.unwrap();
        sqlx::query("SELECT pg_advisory_lock(hashtextextended('scrub fs', 0))")
            .execute(&mut *other)
            .await
            .unwrap();
        assert_eq!(run(6).await, None, "a run leaves a store another scrub holds");
    }

    /// An external library of Ann's at `root` whose files `names` are scanned, ingested and hashed as they are now.
    async fn external_library(scrub: &Scrub, root: &Path, names: &[&str]) -> Uuid {
        let (library, owner) = (Uuid::now_v7(), Uuid::now_v7());
        sqlx::query(
            "WITH u AS (INSERT INTO users (id, handle, display_name) VALUES ($2, $2::text, 'Ann') RETURNING id)
             INSERT INTO libraries (id, owner_id, name, kind, access, root_uri) SELECT $1, id, 'NAS', 'external', 'ro', $3
             FROM u",
        )
        .bind(library)
        .bind(owner)
        .bind(root.to_str().unwrap())
        .execute(&scrub.pool)
        .await
        .unwrap();
        for name in names {
            let bytes = std::fs::read(root.join(name)).unwrap();
            let stat = std::fs::metadata(root.join(name)).unwrap();
            let (dir, file) = name.rsplit_once('/').unwrap();
            sqlx::query(
                "WITH a AS (INSERT INTO assets (id, library_id, owner_id, source, content_hash)
                   VALUES (photolib_uuidv7(), $1, $2, 'scan', $5) RETURNING id),
                 f AS (INSERT INTO asset_files (id, asset_id, role, storage, key, size, content_hash)
                   SELECT photolib_uuidv7(), id, 'original', 'external', $3 || '/' || $4, $6, $5 FROM a)
                 INSERT INTO library_files (library_id, dir, name, dev, inode, size, mtime_ns, state, asset_id)
                 SELECT $1, $3, $4, $7, $8, $6, $9, 'ingested', id FROM a",
            )
            .bind(library)
            .bind(owner)
            .bind(dir)
            .bind(file)
            .bind(Hash::of(&bytes).0.to_vec())
            .bind(i64::try_from(bytes.len()).unwrap())
            .bind(stat.dev().cast_signed())
            .bind(stat.ino().cast_signed())
            .bind(stat.mtime() * 1_000_000_000 + stat.mtime_nsec())
            .execute(&scrub.pool)
            .await
            .unwrap();
        }
        library
    }

    /// Sets the modification time of `path` to `at`.
    fn touch(path: &Path, at: std::time::SystemTime) {
        std::fs::File::options()
            .write(true)
            .open(path)
            .unwrap()
            .set_modified(at)
            .unwrap();
    }

    /// External libraries are scrubbed as the store `external`: bytes that changed while the file did not (its size,
    /// modification time and inode) are bit-rot of that library's file, as is a file that cannot be read; a file
    /// written or gone since it was hashed is left to rescans, and one read as hashed again resolves its finding.
    #[tokio::test]
    async fn bit_rot_in_an_external_library_is_found_and_files_changed_on_purpose_are_left_alone() {
        let (scrub, _root, _) = scrub(None).await;
        let names = ["a/rot.jpg", "a/edited.jpg", "a/gone.jpg"];
        let roots = [tempfile::tempdir().unwrap(), tempfile::tempdir().unwrap()];
        let mut libraries = vec![];
        for root in &roots {
            std::fs::create_dir(root.path().join("a")).unwrap();
            for name in names {
                std::fs::write(root.path().join(name), format!("the photo {name}")).unwrap();
            }
            libraries.push(external_library(&scrub, root.path(), &names).await);
        }
        let (nas, usb) = (roots[0].path(), roots[1].path());
        let rot = nas.join("a/rot.jpg");
        let written = std::fs::metadata(&rot).unwrap().modified().unwrap();
        flip(&rot, 4);
        touch(&rot, written);
        let edited = nas.join("a/edited.jpg");
        flip(&edited, 4);
        touch(&edited, written + Duration::from_secs(1));
        std::fs::remove_file(nas.join("a/gone.jpg")).unwrap();
        let locked = usb.join("a/gone.jpg");
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o000)).unwrap();
        // Whoever may read anything (root) reads it anyway.
        let unreadable = std::fs::File::open(&locked).is_err();

        let done = scrub.pass(external::STORE, Pass::Check, u64::MAX).await.unwrap();
        assert_eq!((done.files, done.cycle_ended), (6, true));
        let open = "SELECT library_id, key, kind FROM integrity_findings WHERE resolved_at IS NULL ORDER BY key, 1";
        let found =
            async || -> Vec<(Uuid, String, String)> { sqlx::query_as(open).fetch_all(&scrub.pool).await.unwrap() };
        let mut expected = vec![(libraries[0], "a/rot.jpg".to_string(), "content".to_string())];
        if unreadable {
            expected.insert(0, (libraries[1], "a/gone.jpg".into(), "content".into()));
        }
        assert_eq!(found().await, expected);
        scrub.pass(external::STORE, Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(found().await, expected, "a finding is reported once");

        flip(&rot, 4);
        touch(&rot, written);
        std::fs::set_permissions(&locked, std::fs::Permissions::from_mode(0o644)).unwrap();
        scrub.pass(external::STORE, Pass::Check, u64::MAX).await.unwrap();
        assert_eq!(findings(&scrub).await, (vec![], i64::try_from(expected.len()).unwrap()));
    }
}
