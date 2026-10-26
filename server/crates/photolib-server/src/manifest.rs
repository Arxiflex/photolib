//! Library manifests and recovery from storage (photolib-design docs/07 §8, docs/15 §6, ADR-0266). The daily
//! `manifest` job writes, for each standard managed library, `<root>/.photolib/manifests/<UTC time>.jsonl` in its
//! store: a header, then the rows of the library, its owner, assets, their files in the library, tags and albums, as
//! PostgreSQL's JSON of them. `photolibd recover --from-storage <store>` rebuilds a lost database from the newest
//! manifest of every library in a store.

use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    io::{BufRead, BufReader, BufWriter, Write},
    path::Path,
    time::Duration,
};

use futures::TryStreamExt;
use photolib_db::{dump, migrate::embedded};
use photolib_storage::{BlobStore, Hash, journal::Journal, marker};
use serde_json::{Value, json};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::{
    backup::fetch,
    config::Config,
    db::Database,
    instance,
    library::{self, text},
    pg::PgDatabase,
    storage, upgrade,
};

/// The job type.
pub const MANIFEST: &str = "manifest";
/// When it runs: daily, before the backup.
pub const CRON: &str = "0 2 * * *";
/// The manifests each library keeps.
const KEEP: usize = 3;
/// The newest format this release writes and reads.
const VERSION: u64 = 1;
const DIR: &str = ".photolib/manifests";

/// The rows of library `p.library` of `p.owner`, whose files lie under `p.root`, by table, in the order recovery
/// inserts them.
const TABLES: [(&str, &str); 10] = [
    ("users", "users t WHERE t.id = p.owner"),
    ("libraries", "libraries t WHERE t.id = p.library"),
    ("tags", "tags t WHERE t.owner_id = p.owner"),
    ("assets", "assets t WHERE t.library_id = p.library"),
    (
        "asset_files",
        "asset_files t JOIN assets a ON a.id = t.asset_id WHERE a.library_id = p.library AND starts_with(t.key, p.root)",
    ),
    (
        "asset_tags",
        "asset_tags t JOIN assets a ON a.id = t.asset_id WHERE a.library_id = p.library",
    ),
    (
        "asset_user_state",
        "asset_user_state t JOIN assets a ON a.id = t.asset_id WHERE a.library_id = p.library AND t.user_id = p.owner",
    ),
    ("album_folders", "album_folders t WHERE t.owner_id = p.owner"),
    ("albums", "albums t WHERE t.owner_id = p.owner"),
    (
        "album_items",
        "album_items t JOIN albums al ON al.id = t.album_id WHERE al.owner_id = p.owner",
    ),
];

/// Writes the manifest of `library` to `file`, from one snapshot of the database, and returns its hash.
async fn write(pool: &PgPool, library: Uuid, owner: Uuid, file: &Path) -> Result<Hash, String> {
    let mut snapshot = pool.begin().await.map_err(text)?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *snapshot)
        .await
        .map_err(text)?;
    let schema: i64 = sqlx::query_scalar("SELECT max(version) FROM schema_migrations")
        .fetch_one(&mut *snapshot)
        .await
        .map_err(text)?;
    let mut out = BufWriter::new(std::fs::File::create(file).map_err(text)?);
    let header = json!({ "manifest": VERSION, "schema": schema, "library": library });
    writeln!(out, "{header}").map_err(text)?;
    for (table, from) in TABLES {
        let sql = format!(
            "WITH p AS (SELECT $1::uuid AS library, $2::uuid AS owner, $3::text AS root)
             SELECT (to_jsonb(t) - 'txid')::text FROM p, {from}"
        );
        let root = format!("{}/", library::root(library));
        let query = sqlx::query_scalar::<_, String>(&sql)
            .bind(library)
            .bind(owner)
            .bind(root);
        let mut rows = query.fetch(&mut *snapshot);
        while let Some(row) = rows.try_next().await.map_err(text)? {
            writeln!(out, r#"{{"table":"{table}","row":{row}}}"#).map_err(text)?;
        }
    }
    out.into_inner().map_err(text)?.sync_all().map_err(text)?;
    Ok(Hash::of_file(file).map_err(text)?.0)
}

/// The `manifest` job: writes the manifest of every standard managed library whose store is online, in the job's
/// transaction `tx`, and leaves the newest [`KEEP`] of each.
pub async fn write_all(pool: &PgPool, journal: &Journal, scratch: &Path, tx: &mut PgConnection) -> Result<(), String> {
    let libraries: Vec<(Uuid, Uuid, String)> = sqlx::query_as(
        "SELECT id, owner_id, store FROM libraries WHERE kind = 'managed' AND privacy = 'standard' ORDER BY id",
    )
    .fetch_all(pool)
    .await
    .map_err(text)?;
    let stamp = dump::stamp(tx).await.map_err(text)?;
    for (library, owner, store) in libraries {
        let blobs = match journal.stores().get(&store) {
            Ok(blobs) => blobs,
            Err(error) => {
                tracing::warn!(%library, %error, "no manifest for a library whose store is offline");
                continue;
            }
        };
        let staged = tempfile::NamedTempFile::new_in(scratch).map_err(text)?;
        let hash = write(pool, library, owner, staged.path()).await?;
        let dir = format!("{}/{DIR}/", library::root(library));
        let key = format!("{dir}{stamp}.jsonl");
        let op = journal.put(&store, &key, staged.path(), hash).await.map_err(text)?;
        op.settle(tx).await.map_err(text)?;
        let manifests = blobs.list(&dir).await.map_err(text)?;
        for old in manifests.iter().rev().skip(KEEP) {
            journal
                .delete_after(tx, &store, old, Duration::ZERO)
                .await
                .map_err(text)?;
        }
    }
    Ok(())
}

/// What a recovery did: rows inserted and found in manifests by table, the files the manifests name that the store
/// lacks, and the originals in the store that no manifest names, which arrived after it.
#[derive(Debug, Default)]
pub struct Recovery {
    /// Each table, the rows inserted and the rows found.
    pub tables: Vec<(&'static str, u64, i64)>,
    /// Files the manifests name that the store lacks.
    pub missing: Vec<String>,
    /// Originals in the store that no manifest names.
    pub unrecorded: Vec<String>,
}

impl fmt::Display for Recovery {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (table, inserted, found) in &self.tables {
            writeln!(f, "{table}: {inserted} of {found} rows")?;
        }
        for (what, keys) in [
            ("missing from the store", &self.missing),
            ("in no manifest", &self.unrecorded),
        ] {
            if let Some(first) = keys.first() {
                writeln!(f, "{} files {what}, such as {first}", keys.len())?;
            }
        }
        Ok(())
    }
}

/// The instance of the database, else of the data directory, else of store `name`'s marker, which an empty database
/// and data directory take over; all that have one must agree.
async fn adopt(config: &Config, name: &str, db: &PgDatabase, data_dir: &Path) -> Result<Uuid, String> {
    let store = storage::open(config, name).await?;
    let in_db = db.instance_id().await.map_err(text)?;
    let on_disk = instance::read_marker(data_dir)?;
    let in_store = marker::instance(store.as_ref()).await.map_err(text)?;
    let claims: BTreeSet<Uuid> = [in_db, on_disk, in_store].into_iter().flatten().collect();
    let id = match claims.into_iter().collect::<Vec<_>>()[..] {
        [id] => id,
        [] => {
            return Err(format!(
                "store {name} has no instance marker: it holds no Photolib data"
            ));
        }
        _ => {
            return Err(format!(
                "the database, the data directory and store {name} belong to different instances"
            ));
        }
    };
    if in_db.is_none() {
        db.init_instance_id(id).await.map_err(text)?;
    }
    if on_disk.is_none() {
        instance::write_marker(data_dir, id).map_err(text)?;
    }
    Ok(id)
}

/// `photolibd recover --from-storage <store>`: rebuilds the libraries of `store` from their newest manifests, into
/// the database of `config`, empty or not: rows that exist stay. The restore counts into the epoch.
pub async fn from_storage(config: &Config, name: &str) -> Result<Recovery, String> {
    let data_dir = config.data_dir.as_ref().ok_or("data_dir is not set")?;
    let url = config.database.url.as_ref().ok_or("database.url is not set")?;
    let db = PgDatabase::connect(url.expose(), 0).await.map_err(text)?;
    let id = adopt(config, name, &db, data_dir).await?;
    if let Some(maintenance) = upgrade::startup(config, db.pool(), &embedded()).await? {
        return Err(maintenance);
    }
    let journal = storage::start(config, db.pool(), id).await?;
    let store = journal.stores().get(name).map_err(text)?;
    let keys = store.list("libraries/").await.map_err(text)?;
    let mut newest = BTreeMap::new();
    for key in &keys {
        if let Some((root, file)) = key.split_once(&format!("/{DIR}/"))
            && Path::new(file).extension().is_some_and(|ext| ext == "jsonl")
            && !file.contains('/')
        {
            newest.insert(root, key);
        }
    }
    let scratch = tempfile::tempdir().map_err(text)?;
    let mut tx = db.pool().begin().await.map_err(text)?;
    sqlx::query("CREATE TEMP TABLE recovered (kind text NOT NULL, row jsonb NOT NULL) ON COMMIT DROP")
        .execute(&mut *tx)
        .await
        .map_err(text)?;
    for key in newest.values() {
        stage(&mut tx, store.as_ref(), key, scratch.path()).await?;
    }
    let mut recovery = Recovery::default();
    for (table, _) in TABLES {
        recovery.tables.push(insert(&mut tx, table).await.map_err(text)?);
    }
    let files: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT f.id, f.key FROM asset_files f JOIN recovered r ON r.kind = 'asset_files' AND (r.row->>'id')::uuid = f.id
         WHERE f.storage = $1",
    )
    .bind(name)
    .fetch_all(&mut *tx)
    .await
    .map_err(text)?;
    let listed: BTreeSet<&String> = keys.iter().collect();
    let (missing, named): (Vec<_>, Vec<_>) = files.into_iter().partition(|(_, key)| !listed.contains(key));
    let named: BTreeSet<String> = named.into_iter().map(|(_, key)| key).collect();
    let ids: Vec<Uuid> = missing.iter().map(|(id, _)| *id).collect();
    sqlx::query("UPDATE asset_files SET state = 'missing' WHERE id = ANY($1)")
        .bind(&ids)
        .execute(&mut *tx)
        .await
        .map_err(text)?;
    recovery.missing = missing.into_iter().map(|(_, key)| key).collect();
    recovery.unrecorded = (keys.iter())
        .filter(|key| {
            let mut names = key.split('/');
            let root = names.next().zip(names.next()).map(|(a, b)| format!("{a}/{b}"));
            names.next() == Some("originals") && root.is_some_and(|root| newest.contains_key(root.as_str()))
        })
        .filter(|key| !named.contains(*key))
        .cloned()
        .collect();
    tx.commit().await.map_err(text)?;
    instance::count_restore(data_dir)?;
    Ok(recovery)
}

/// Stages the rows of the manifest `key` in `recovered`.
async fn stage(tx: &mut PgConnection, store: &dyn BlobStore, key: &str, scratch: &Path) -> Result<(), String> {
    let path = fetch(store, key, scratch).await?;
    let mut lines = BufReader::new(std::fs::File::open(path).map_err(text)?).lines();
    let header: Value = serde_json::from_str(&lines.next().ok_or("an empty manifest")?.map_err(text)?).map_err(text)?;
    let ours = embedded().last().map_or(0, |m| m.version);
    let (version, schema) = (
        header.get("manifest").and_then(Value::as_u64),
        header.get("schema").and_then(Value::as_i64),
    );
    if version.is_none_or(|v| v > VERSION) || schema.is_none_or(|s| s > ours) {
        return Err(format!(
            "{key} was written by a newer photolibd ({header}); recover with that release"
        ));
    }
    let mut batch: (Vec<String>, Vec<String>) = Default::default();
    loop {
        let line = lines.next().transpose().map_err(text)?;
        if let Some(line) = &line {
            let record: Value = serde_json::from_str(line).map_err(|e| format!("{key}: {e}"))?;
            let table = record.get("table").and_then(Value::as_str);
            batch.0.push(table.unwrap_or_default().to_string());
            batch.1.push(record.get("row").unwrap_or(&Value::Null).to_string());
        }
        if batch.0.len() == 1000 || (line.is_none() && !batch.0.is_empty()) {
            sqlx::query("INSERT INTO recovered SELECT * FROM unnest($1::text[], $2::text[]::jsonb[])")
                .bind(&batch.0)
                .bind(&batch.1)
                .execute(&mut *tx)
                .await
                .map_err(text)?;
            batch = Default::default();
        }
        if line.is_none() {
            return Ok(());
        }
    }
}

/// Inserts the staged rows of `table` that are not there yet, with the columns they have, so that columns added since
/// the manifest take their defaults. A reference to a row that is neither there nor staged becomes NULL, or skips its
/// row where it cannot be NULL. Returns the table, the rows inserted and the rows staged.
async fn insert(tx: &mut PgConnection, table: &'static str) -> sqlx::Result<(&'static str, u64, i64)> {
    let columns: Vec<(String, bool, Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT a.attname::text, a.attnotnull, c.confrelid::regclass::text, fa.attname::text
         FROM pg_attribute a
         LEFT JOIN pg_constraint c ON c.conrelid = a.attrelid AND c.contype = 'f' AND c.conkey = ARRAY[a.attnum]
         LEFT JOIN pg_attribute fa ON fa.attrelid = c.confrelid AND fa.attnum = c.confkey[1]
         WHERE a.attrelid = $1::regclass AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attname::text IN (SELECT jsonb_object_keys(row) FROM recovered WHERE kind = $1)
         ORDER BY a.attnum",
    )
    .bind(table)
    .fetch_all(&mut *tx)
    .await?;
    let (mut names, mut values, mut required) = (vec![], vec![], vec!["r.kind = $1".to_string()]);
    for (name, not_null, target, key) in columns {
        let value = format!("p.{name}");
        let value = match (target, key) {
            (Some(target), Some(key)) => {
                let found = format!(
                    "(EXISTS (SELECT FROM {target} x WHERE x.{key} = p.{name}) OR EXISTS (SELECT FROM recovered s
                       WHERE s.kind = '{target}' AND '{target}' = $1 AND s.row->>'{key}' = p.{name}::text))"
                );
                if not_null {
                    required.push(found);
                    value
                } else {
                    format!("CASE WHEN {found} THEN {value} END")
                }
            }
            _ => value,
        };
        names.push(name);
        values.push(value);
    }
    let found: i64 = sqlx::query_scalar("SELECT count(*) FROM recovered WHERE kind = $1")
        .bind(table)
        .fetch_one(&mut *tx)
        .await?;
    if names.is_empty() {
        return Ok((table, 0, found));
    }
    let sql = format!(
        "INSERT INTO {table} ({}) SELECT {} FROM recovered r, jsonb_populate_record(NULL::{table}, r.row) p
         WHERE {} ON CONFLICT DO NOTHING",
        names.join(", "),
        values.join(", "),
        required.join(" AND ")
    );
    let inserted = sqlx::query(&sql).bind(table).execute(&mut *tx).await?.rows_affected();
    Ok((table, inserted, found))
}

#[cfg(test)]
mod tests {
    use photolib_db::testpg;
    use photolib_storage::testing::garage;

    use super::*;
    use crate::{role::Role, secret::Secret, testing};

    fn config(db: &testpg::TestDb, data_dir: &Path) -> Config {
        let mut config = testing::config(&[Role::Api], data_dir);
        config.database.url = Some(Secret::new(db.url.clone()));
        config.database.bin_dir = Some(testpg::bin_dir());
        config.stores.insert("b2".into(), testing::store(&garage()));
        config
    }

    /// Ann's library on `store`: two photos with titles and descriptions, a rendition outside the library, a tag tree
    /// on them, and an album in a folder with both photos around a text block.
    const FIXTURE: &str = "
        INSERT INTO assets (id, library_id, owner_id, source, media_kind, original_filename, title, description,
            taken_local, rating, content_hash)
        VALUES ('01900000-0000-7000-8000-00000000000a', $2, $1, 'upload', 'image', 'a.jpg', 'Harbour', 'Boats at dawn',
            '2024-05-01 06:00', 4, '\\x0a'),
          ('01900000-0000-7000-8000-00000000000b', $2, $1, 'upload', 'image', 'b.jpg', 'Market', 'Fish, mostly', NULL, 0,
            '\\x0b');
        INSERT INTO asset_files (id, asset_id, role, storage, key, size, content_hash, mime) VALUES
          ('01900000-0000-7000-8000-0000000000fa', '01900000-0000-7000-8000-00000000000a', 'original', $3,
            'libraries/' || $2 || '/originals/2024/2024-05/a.jpg', 1, '\\x0a', 'image/jpeg'),
          ('01900000-0000-7000-8000-0000000000fb', '01900000-0000-7000-8000-00000000000b', 'original', $3,
            'libraries/' || $2 || '/originals/2024/2024-05/b.jpg', 1, '\\x0b', 'image/jpeg'),
          ('01900000-0000-7000-8000-0000000000fc', '01900000-0000-7000-8000-00000000000a', 'thumb_s', 'local',
            'derived/' || $2 || '/a.webp', 1, NULL, 'image/webp');
        INSERT INTO tags (id, owner_id, parent_id, name, path) VALUES
          ('01900000-0000-7000-8000-000000000071', $1, NULL, 'Places', 'Places'),
          ('01900000-0000-7000-8000-000000000072', $1, '01900000-0000-7000-8000-000000000071', 'Lisbon', 'Places|Lisbon');
        INSERT INTO asset_tags (asset_id, tag_id) VALUES
          ('01900000-0000-7000-8000-00000000000a', '01900000-0000-7000-8000-000000000072'),
          ('01900000-0000-7000-8000-00000000000b', '01900000-0000-7000-8000-000000000072');
        INSERT INTO asset_user_state (user_id, asset_id, favorite) VALUES ($1, '01900000-0000-7000-8000-00000000000a', true);
        INSERT INTO album_folders (id, owner_id, name, sort_key) VALUES ('01900000-0000-7000-8000-0000000000af', $1, 'Trips', 'a');
        INSERT INTO albums (id, owner_id, folder_id, title, description, cover_asset_id, sort_mode) VALUES
          ('01900000-0000-7000-8000-0000000000a1', $1, '01900000-0000-7000-8000-0000000000af', 'Lisbon 2024',
            'A week by the river', '01900000-0000-7000-8000-00000000000b', 'custom');
        INSERT INTO album_items (id, album_id, kind, asset_id, body, sort_key) VALUES
          ('01900000-0000-7000-8000-0000000000b1', '01900000-0000-7000-8000-0000000000a1', 'asset',
            '01900000-0000-7000-8000-00000000000a', NULL, 'a'),
          ('01900000-0000-7000-8000-0000000000b2', '01900000-0000-7000-8000-0000000000a1', 'text', NULL,
            'Then the rain came.', 'b'),
          ('01900000-0000-7000-8000-0000000000b3', '01900000-0000-7000-8000-0000000000a1', 'asset',
            '01900000-0000-7000-8000-00000000000b', NULL, 'c');";

    async fn rows(pool: &PgPool, table: &str) -> Vec<Value> {
        let sql = format!(
            "SELECT to_jsonb(t) - 'txid' FROM {table} t
             WHERE coalesce(to_jsonb(t)->>'key', 'libraries/') LIKE 'libraries/%' ORDER BY 1::text"
        );
        sqlx::query_scalar(&sql).fetch_all(pool).await.unwrap()
    }

    /// Writes the manifest of a fixture library on `store`, loses the database (and on an object store the data
    /// directory too), and recovers it from `store`.
    async fn recovers(store: &str) {
        let (db, lost) = (testpg::database().await, testpg::database().await);
        let data = tempfile::tempdir().unwrap();
        let mut config = config(&db, data.path());
        let pg = PgDatabase::connect(&db.url, 0).await.unwrap();
        let id = instance::verify(data.path(), &pg).await.unwrap();
        upgrade::startup(&config, &db.pool, &embedded()).await.unwrap();
        let journal = storage::start(&config, &db.pool, id).await.unwrap();
        let ann = Uuid::now_v7();
        sqlx::query("INSERT INTO users (id, handle, display_name, email) VALUES ($1, 'ann', 'Ann', 'ann@example.com')")
            .bind(ann)
            .execute(&db.pool)
            .await
            .unwrap();
        let photos = library::create(&db.pool, &journal, store, ann, "Photos").await.unwrap();
        let fixture = (FIXTURE.replace("$1", &format!("'{ann}'")))
            .replace("$2", &format!("'{photos}'"))
            .replace("$3", &format!("'{store}'"));
        sqlx::raw_sql(&fixture).execute(&db.pool).await.unwrap();
        let blobs = journal.stores().get(store).unwrap().clone();
        for name in ["a", "b", "c"] {
            let key = format!("libraries/{photos}/originals/2024/2024-05/{name}.jpg");
            let op = journal.put_bytes(store, &key, name.as_bytes()).await.unwrap();
            op.settle(&mut db.pool.acquire().await.unwrap()).await.unwrap();
        }
        let scratch = tempfile::tempdir().unwrap();
        for _ in 0..=KEEP {
            let mut tx = db.pool.begin().await.unwrap();
            write_all(&db.pool, &journal, scratch.path(), &mut tx).await.unwrap();
            tx.commit().await.unwrap();
            tokio::time::sleep(Duration::from_millis(1100)).await;
        }
        assert_eq!(journal.purge().await.unwrap(), 1, "the oldest manifest goes");
        let manifests = blobs.list(&format!("libraries/{photos}/{DIR}/")).await.unwrap();
        assert_eq!(manifests.len(), KEEP);
        blobs
            .delete(&format!("libraries/{photos}/originals/2024/2024-05/b.jpg"))
            .await
            .unwrap();
        drop(journal);

        config.database.url = Some(Secret::new(lost.url.clone()));
        let fresh = tempfile::tempdir().unwrap();
        if store != "local" {
            config.data_dir = Some(fresh.path().to_path_buf());
        }
        let recovery = from_storage(&config, store).await.unwrap();
        let b = format!("libraries/{photos}/originals/2024/2024-05/b.jpg");
        let c = format!("libraries/{photos}/originals/2024/2024-05/c.jpg");
        assert_eq!(
            (recovery.missing.clone(), recovery.unrecorded.clone()),
            (vec![b.clone()], vec![c])
        );
        let report = recovery.to_string();
        assert!(
            report.contains("assets: 2 of 2 rows\n") && report.contains("album_items: 3 of 3 rows\n"),
            "{report}"
        );
        sqlx::query("UPDATE asset_files SET state = 'missing' WHERE key = $1")
            .bind(&b)
            .execute(&db.pool)
            .await
            .unwrap();
        for (table, _) in TABLES {
            assert_eq!(rows(&lost.pool, table).await, rows(&db.pool, table).await, "{table}");
        }
        let data_dir = config.data_dir.as_ref().unwrap();
        assert_eq!(
            instance::epoch(data_dir),
            Ok(Some(format!("{id}.1"))),
            "devices see the recovery"
        );
        let again = from_storage(&config, store).await.unwrap();
        assert!(again.tables.iter().all(|(_, inserted, _)| *inserted == 0), "{again}");
    }

    #[tokio::test]
    async fn recovery_rebuilds_a_library_with_albums_tags_and_descriptions_from_the_filesystem() {
        recovers("local").await;
    }

    #[tokio::test]
    async fn recovery_rebuilds_a_library_with_albums_tags_and_descriptions_from_an_object_store() {
        recovers("b2").await;
    }

    #[tokio::test]
    async fn recovery_refuses_a_store_of_another_instance_or_none() {
        let (db, other) = (testpg::database().await, testpg::database().await);
        let data = tempfile::tempdir().unwrap();
        let empty = config(&other, data.path());
        assert!(
            from_storage(&empty, "b2")
                .await
                .unwrap_err()
                .contains("no instance marker")
        );
        let pg = PgDatabase::connect(&db.url, 0).await.unwrap();
        instance::verify(tempfile::tempdir().unwrap().path(), &pg)
            .await
            .unwrap();
        instance::write_marker(data.path(), Uuid::now_v7()).unwrap();
        assert!(
            from_storage(&config(&db, data.path()), "local")
                .await
                .unwrap_err()
                .contains("different instances")
        );
    }
}
