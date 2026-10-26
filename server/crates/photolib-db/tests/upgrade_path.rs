//! The upgrade-path harness (design 15 §2.5): a fixture database of every schema version upgrades to the newest one.

use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::OnceLock,
    time::Instant,
};

use photolib_db::{
    data,
    doctor::drift,
    dump::Dumps,
    migrate::{Migration, Upgrade, embedded, upgrade},
    testpg,
};
use photolib_synthlib::{Config, Shape, generate};
use sqlx::PgPool;
use tokio::sync::Mutex;

/// What a URL or a share definition resolves to in the newest schema, given the id or link token as `$1`.
const RESOLVERS: &[(&str, &str)] = &[
    (
        "/albums/",
        "SELECT jsonb_build_object('owner', a.owner_id, 'kind', a.kind, 'privacy', a.privacy, 'title', a.title,
           'cover', a.cover_asset_id, 'tag', a.tag_id, 'source', a.source_library_id,
           'blocks', (SELECT jsonb_agg(jsonb_build_array(i.kind, i.asset_id, i.caption, i.body) ORDER BY i.sort_key, i.id)
                      FROM album_items i WHERE i.album_id = a.id))
         FROM albums a WHERE a.id = $1::uuid",
    ),
    (
        "/assets/",
        "SELECT jsonb_build_object('library', library_id, 'owner', owner_id, 'filename', original_filename,
           'hash', encode(content_hash, 'hex'), 'version', current_version_id, 'trashed', trashed_at IS NOT NULL,
           'locked', locked)
         FROM assets WHERE id = $1::uuid",
    ),
    (
        "/s/",
        "SELECT jsonb_build_object('album', album_id, 'download', allow_download, 'password', password_hash IS NOT NULL,
           'expires', expires_at, 'revoked', revoked_at)
         FROM links WHERE token_hash = sha256(convert_to($1, 'UTF8'))",
    ),
    (
        "shared with ",
        "SELECT jsonb_build_object(
           'albums', (SELECT jsonb_object_agg(album_id, role) FROM album_members WHERE user_id = $1::uuid),
           'libraries', (SELECT jsonb_object_agg(library_id, role) FROM library_members WHERE user_id = $1::uuid),
           'partners', (SELECT jsonb_object_agg(owner_id, taken_since) FROM partner_shares WHERE partner_id = $1::uuid))",
    ),
];

/// The URLs and share definitions of a fixture: a link's token is its id.
const URLS: &str = "SELECT '/albums/' || id FROM albums UNION ALL SELECT '/assets/' || id FROM assets
    UNION ALL SELECT '/s/' || id FROM links UNION ALL SELECT 'shared with ' || id FROM users ORDER BY 1";

/// One line per URL or share: what it resolves to.
async fn resolve<'a>(pool: &PgPool, keys: impl IntoIterator<Item = &'a str>) -> String {
    let mut lines = String::new();
    for key in keys {
        let (prefix, sql) = RESOLVERS
            .iter()
            .find(|(prefix, _)| key.starts_with(prefix))
            .unwrap_or_else(|| panic!("no resolver for {key}"));
        let resolved: Option<String> = sqlx::query_scalar(&format!("SELECT ({sql})::text"))
            .bind(&key[prefix.len()..])
            .fetch_one(pool)
            .await
            .unwrap();
        lines += &format!("{key}: {}\n", resolved.as_deref().unwrap_or("null"));
    }
    lines
}

/// The resolutions recorded when the fixture was made, the "before" of every upgrade from it. Missing ones are
/// recorded with PHOTOLIB_RECORD_FIXTURES=1, from the database the fixture just filled.
async fn recorded(m: &Migration, pool: &PgPool) -> Result<String, String> {
    let path = fixtures().join(format!("{m}.resolved"));
    if let Ok(recorded) = std::fs::read_to_string(&path) {
        return Ok(recorded);
    }
    if std::env::var_os("PHOTOLIB_RECORD_FIXTURES").is_none() {
        return Err(format!(
            "{m}: the fixture has no recorded resolutions: run PHOTOLIB_RECORD_FIXTURES=1 cargo test -p photolib-db \
             --test upgrade_path, review and commit {m}.resolved"
        ));
    }
    let keys: Vec<String> = sqlx::query_scalar(URLS).fetch_all(pool).await.unwrap();
    let resolved = resolve(pool, keys.iter().map(String::as_str)).await;
    std::fs::write(&path, &resolved).unwrap();
    Ok(resolved)
}

/// `server/migrations/fixtures`: `<migration>.sql` is the fixture library of that schema version.
fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../migrations/fixtures")
}

/// The tables without rows, but for the framework's own that only upgrades fill.
async fn empty_tables(pool: &PgPool) -> Vec<String> {
    sqlx::query_scalar(
        "SELECT relname::text FROM pg_class WHERE relnamespace = current_schema()::regnamespace AND relkind = 'r'
         AND relname NOT IN ('data_migrations', 'quarantined_rows')
         AND NOT (xpath('/row/e/text()', query_to_xml(format('SELECT EXISTS (SELECT FROM %I) AS e', relname),
                  false, true, '')))[1]::text::boolean
         ORDER BY 1",
    )
    .fetch_all(pool)
    .await
    .unwrap()
}

/// The rows of each foreign key that reference nothing, which only disabled triggers or NOT VALID allow.
async fn dangling(pool: &PgPool) -> BTreeMap<String, i64> {
    let counts: String = sqlx::query_scalar(
        "SELECT coalesce(string_agg(format('SELECT %L, count(*) FROM %s c WHERE %s AND NOT EXISTS (SELECT FROM %s p WHERE %s)',
           conrelid::regclass || '.' || conname, conrelid::regclass, present, confrelid::regclass, matches), ' UNION ALL '),
           'SELECT NULL, 0')
         FROM (SELECT con.conname, con.conrelid, con.confrelid,
                 string_agg(format('c.%I IS NOT NULL', ca.attname), ' AND ') AS present,
                 string_agg(format('p.%I = c.%I', pa.attname, ca.attname), ' AND ') AS matches
               FROM pg_constraint con, unnest(con.conkey, con.confkey) AS k (c, p), pg_attribute ca, pg_attribute pa
               WHERE con.contype = 'f' AND con.connamespace = current_schema()::regnamespace
                 AND ca.attrelid = con.conrelid AND ca.attnum = k.c AND pa.attrelid = con.confrelid AND pa.attnum = k.p
               GROUP BY con.oid, con.conname, con.conrelid, con.confrelid) AS fks",
    )
    .fetch_one(pool)
    .await
    .unwrap();
    sqlx::query_as(&format!("SELECT * FROM ({counts}) AS c (fk, n) WHERE n > 0"))
        .fetch_all(pool)
        .await
        .unwrap()
        .into_iter()
        .collect()
}

/// The line that ends a fixture's clean part; what follows is drift.
const DRIFT: &str = "-- photolib:drift";

/// What the harness loads into a database at the fixture's schema version.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Case {
    Clean,
    /// The clean part and the drift section: duplicate hashes, orphans, manual indexes and stray settings.
    Drifted,
    /// The clean part and a synthetic library of `PHOTOLIB_UPGRADE_ASSETS` assets (1000 by default), which the
    /// weekly run makes a million to catch slow migrations.
    Synthetic,
}

fn synthetic_assets() -> u64 {
    std::env::var("PHOTOLIB_UPGRADE_ASSETS").map_or(1000, |n| n.parse().expect("PHOTOLIB_UPGRADE_ASSETS: a number"))
}

/// The synthetic library's CSV tables, generated once per run.
fn synthetic() -> &'static Path {
    static DIR: OnceLock<PathBuf> = OnceLock::new();
    DIR.get_or_init(|| {
        let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("upgrade-path-synthetic");
        let _ = std::fs::remove_dir_all(&dir);
        let assets = synthetic_assets();
        generate(
            &Config {
                assets,
                seed: 20,
                shape: Shape::Library,
            },
            &dir,
        )
        .unwrap();
        dir
    })
}

/// synthlib's tables (tools/synthlib/README.md), copied into these staging tables.
const SYNTHETIC_CSV: &[(&str, &str)] = &[
    ("users", "id uuid, handle text, display_name text"),
    ("people", "id uuid, owner_id uuid, kind text, name text"),
    (
        "assets",
        "id uuid, owner_id uuid, folder text, original_filename text, media_kind text, panorama boolean, width int,
         height int, duration_ms bigint, file_size bigint, taken_local timestamp, tz_offset_min int, tz_name text,
         time_precision text, time_source text, time_confidence smallint, lat float8, lon float8, make text,
         model text, stack_id uuid, thumb text",
    ),
    ("stacks", "id uuid, owner_id uuid, kind text, cover_asset_id uuid"),
    ("albums", "id uuid, owner_id uuid, title text, cover_asset_id uuid"),
    ("album_items", "album_id uuid, asset_id uuid"),
    ("album_members", "album_id uuid, user_id uuid, role text"),
    (
        "faces",
        "id uuid, asset_id uuid, person_id uuid, x real, y real, w real, h real",
    ),
];

/// From the staging tables into the baseline's columns, which later migrations keep (expand and contract).
const SYNTHETIC_LOAD: &str = "
INSERT INTO users (id, handle, display_name) SELECT id, 'synthetic-' || handle, display_name FROM synthetic_users;
INSERT INTO libraries (id, owner_id, name, kind, root_uri, is_upload_target)
SELECT id, id, 'Synthetic', 'managed', 'managed:synthetic-' || handle, true FROM synthetic_users;
INSERT INTO stacks (id, owner_id, kind, origin) SELECT id, owner_id, kind, 'camera' FROM synthetic_stacks;
INSERT INTO assets (id, library_id, owner_id, original_filename, source, media_kind, facets, width, height,
                    duration_ms, file_size_total, taken_local, tz_offset_min, tz_name, taken_utc, time_source,
                    time_confidence, time_precision, lat, lon, make, model, stack_id)
SELECT id, owner_id, owner_id, original_filename, 'upload', media_kind,
       CASE WHEN panorama THEN '{panorama}'::text[] ELSE '{}' END, width, height, duration_ms, file_size,
       taken_local, tz_offset_min, tz_name, (taken_local - make_interval(mins => tz_offset_min)) AT TIME ZONE 'UTC',
       time_source, time_confidence,
       CASE time_precision WHEN 'millisecond' THEN 'ms' WHEN 'unspecified' THEN NULL ELSE time_precision END,
       lat, lon, make, model, stack_id
FROM synthetic_assets;
INSERT INTO asset_files (id, asset_id, role, storage, key, size)
SELECT gen_random_uuid(), id, 'original', 'managed', 'synthetic/' || original_filename, file_size
FROM synthetic_assets;
UPDATE stacks SET cover_asset_id = s.cover_asset_id FROM synthetic_stacks s WHERE stacks.id = s.id;
INSERT INTO persons (id, owner_id, kind, name) SELECT id, owner_id, kind, name FROM synthetic_people;
INSERT INTO faces (id, asset_id, bbox, model_id, person_id)
SELECT id, asset_id, ARRAY[x, y, w, h], 'synthlib', person_id FROM synthetic_faces;
INSERT INTO albums (id, owner_id, title, cover_asset_id) SELECT id, owner_id, title, cover_asset_id
FROM synthetic_albums;
INSERT INTO album_items (id, album_id, kind, asset_id, sort_key)
SELECT gen_random_uuid(), album_id, 'asset', asset_id, to_char(row_number() OVER (PARTITION BY album_id), 'FM00000000')
FROM synthetic_album_items;
INSERT INTO album_members (album_id, user_id, role) SELECT album_id, user_id, role FROM synthetic_album_members;";

async fn load_synthetic(pool: &PgPool, dir: &Path) {
    let mut tx = pool.begin().await.unwrap();
    for (table, columns) in SYNTHETIC_CSV {
        sqlx::raw_sql(&format!(
            "CREATE TEMP TABLE synthetic_{table} ({columns}) ON COMMIT DROP"
        ))
        .execute(&mut *tx)
        .await
        .unwrap();
        let mut copy = tx
            .copy_in_raw(&format!("COPY synthetic_{table} FROM STDIN (FORMAT csv, HEADER true)"))
            .await
            .unwrap();
        copy.send(std::fs::read(dir.join(format!("{table}.csv"))).unwrap())
            .await
            .unwrap();
        copy.finish().await.unwrap();
    }
    sqlx::raw_sql(SYNTHETIC_LOAD).execute(&mut *tx).await.unwrap();
    tx.commit().await.unwrap();
}

/// The drifted fixtures change database and role settings, which every upgrade on the cluster checks.
static ONE_AT_A_TIME: Mutex<()> = Mutex::const_new(());

/// What the loaded fixture lacks to be a test of `case`.
async fn lacking(pool: &PgPool, case: Case, dangling: &BTreeMap<String, i64>, drift: &[String]) -> Vec<String> {
    let holds = |sql: String| async move { sqlx::query_scalar::<_, bool>(&sql).fetch_one(pool).await.unwrap() };
    let wanted = match case {
        Case::Synthetic => vec![(
            "the synthetic library".into(),
            holds(format!(
                "SELECT count(*) = {} FROM assets JOIN users u ON u.id = owner_id WHERE u.handle LIKE 'synthetic-%'",
                synthetic_assets()
            ))
            .await,
        )],
        Case::Clean => {
            let empty = empty_tables(pool).await;
            vec![
                (format!("rows in {}", empty.join(", ")), empty.is_empty()),
                ("intact references".into(), dangling.is_empty()),
                ("the schema of its migrations".into(), drift.is_empty()),
            ]
        }
        Case::Drifted => vec![
            (
                "duplicate hashes".into(),
                holds(
                    "SELECT EXISTS (SELECT FROM assets WHERE content_hash IS NOT NULL
                     GROUP BY library_id, content_hash HAVING count(*) > 1)"
                        .into(),
                )
                .await,
            ),
            ("orphans".into(), !dangling.is_empty()),
            (
                "manual indexes".into(),
                drift.iter().any(|line| line.starts_with("unexpected: index")),
            ),
            (
                "stray settings".into(),
                holds(
                    "SELECT EXISTS (SELECT FROM pg_db_role_setting
                     WHERE setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database()))"
                        .into(),
                )
                .await,
            ),
        ],
    };
    wanted
        .into_iter()
        .filter(|(_, present)| !present)
        .map(|(what, _)| what)
        .collect()
}

/// What is wrong with upgrading the fixture of `migrations[version]` to the newest of `migrations`.
async fn upgrade_from(migrations: &[Migration], version: usize, case: Case) -> Vec<String> {
    let m = &migrations[version];
    let Ok(sql) = std::fs::read_to_string(fixtures().join(format!("{m}.sql"))) else {
        return vec![format!(
            "schema version {m} has no upgrade fixture: add server/migrations/fixtures/{m}.sql (docs/dev/migrations.md)"
        )];
    };
    let Some((clean, drifted)) = sql.split_once(DRIFT) else {
        return vec![format!("{m}: the fixture has no {DRIFT:?} section")];
    };
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&migrations[..=version])).await.unwrap();
    sqlx::raw_sql(clean).execute(&db.pool).await.unwrap();
    let before = match recorded(m, &db.pool).await {
        Ok(before) => before,
        Err(problem) => return vec![problem],
    };
    match case {
        Case::Clean => {}
        Case::Drifted => {
            sqlx::raw_sql(drifted).execute(&db.pool).await.unwrap();
        }
        Case::Synthetic => load_synthetic(&db.pool, synthetic()).await,
    }
    // New connections, which take up the stray settings.
    let pool = PgPool::connect(&db.url).await.unwrap();
    let dangling_before = dangling(&pool).await;
    let drift_before = drift(&pool, migrations).await.unwrap();
    let lacks = lacking(&pool, case, &dangling_before, &drift_before).await;
    if !lacks.is_empty() {
        return vec![format!("{m} ({case:?}): the fixture lacks {}", lacks.join(", "))];
    }
    let dumps = tempfile::tempdir().unwrap();
    let data = data::registry();
    let up = Upgrade {
        migrations,
        data: &data,
        dumps: Some(Dumps {
            url: db.url.clone(),
            bin_dir: Some(testpg::bin_dir()),
            dir: dumps.path().into(),
            keep: 1,
        }),
    };
    let started = Instant::now();
    if let Err(error) = upgrade(&pool, &up).await {
        return vec![format!("{m} ({case:?}): the upgrade failed: {error:?}")];
    }
    eprintln!("{m} ({case:?}): upgraded in {:?}", started.elapsed());
    for d in &data {
        if let Err(error) = data::run(&pool, d.as_ref(), || false).await {
            return vec![format!("{m} ({case:?}): data migration {} failed: {error}", d.id())];
        }
    }
    let after = resolve(
        &pool,
        before
            .lines()
            .filter_map(|line| line.split_once(": ").map(|(key, _)| key)),
    )
    .await;
    let resolved = before
        .lines()
        .zip(after.lines())
        .filter(|(was, is)| was != is)
        .map(|(was, is)| format!("{m} ({case:?}): resolved as {was}, now as {is}"));
    let dangling = dangling(&pool)
        .await
        .into_iter()
        .filter(|(fk, n)| *n > dangling_before.get(fk).copied().unwrap_or(0))
        .map(|(fk, n)| format!("{m} ({case:?}): {n} rows of {fk} reference nothing"));
    let drift = drift(&pool, migrations)
        .await
        .unwrap()
        .into_iter()
        .filter(|line| !drift_before.contains(line))
        .map(|line| format!("{m} ({case:?}): the upgraded schema differs from a fresh one: {line}"));
    resolved.chain(dangling).chain(drift).collect()
}

#[tokio::test]
async fn every_schema_version_upgrades_to_the_newest() {
    let _cluster = ONE_AT_A_TIME.lock().await;
    let migrations = embedded();
    let mut problems = Vec::new();
    for version in 0..migrations.len() {
        for case in [Case::Clean, Case::Drifted, Case::Synthetic] {
            problems.extend(upgrade_from(&migrations, version, case).await);
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

/// Passes the migrator's own checks, yet demotes an editor, points a file at no asset and builds an index only where
/// there are rows.
const HOSTILE: &str = "
UPDATE album_members SET role = 'viewer' WHERE role = 'editor';
ALTER TABLE asset_files DROP CONSTRAINT asset_files_asset_id_fkey;
UPDATE asset_files SET asset_id = gen_random_uuid() WHERE role = 'sidecar';
ALTER TABLE asset_files ADD CONSTRAINT asset_files_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets (id)
    ON DELETE CASCADE NOT VALID;
DO $$BEGIN IF EXISTS (SELECT FROM assets) THEN CREATE INDEX hostile ON assets (title); END IF; END$$;";

#[tokio::test]
async fn the_harness_tells_a_hostile_migration_from_a_benign_one() {
    let _cluster = ONE_AT_A_TIME.lock().await;
    let with = |file, sql| {
        let mut migrations = embedded();
        migrations.push(Migration::new(file, sql).unwrap());
        migrations
    };
    let benign = with(
        "9999_benign.sql",
        "ALTER TABLE assets ADD COLUMN benign text; CREATE TABLE benign (id uuid PRIMARY KEY);",
    );
    for case in [Case::Clean, Case::Drifted] {
        let problems = upgrade_from(&benign, benign.len() - 2, case).await;
        assert_eq!(problems, Vec::<String>::new());
    }

    let hostile = with("9999_hostile.sql", HOSTILE);
    let problems = upgrade_from(&hostile, hostile.len() - 2, Case::Clean).await;
    for words in [
        "shared with 00000001-0000-7000-8000-000000000002",
        "asset_files_asset_id_fkey",
        "INDEX hostile",
    ] {
        assert!(
            problems.iter().any(|p| p.contains(words)),
            "{words:?} missing from: {problems:#?}"
        );
    }
    assert_eq!(problems.len(), 3, "{problems:#?}");
}
