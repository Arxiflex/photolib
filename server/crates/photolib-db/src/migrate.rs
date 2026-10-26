//! Forward-only schema migrations. Every migration of one upgrade runs in a single transaction under an advisory
//! lock, so that one process migrates and a failure leaves the schema as it was.

use std::{collections::BTreeMap, fmt, path::PathBuf, time::Instant};

use sha2::{Digest, Sha256};
use sqlx::{PgConnection, PgPool};

use crate::{
    data::{self, DataMigration},
    dump::Dumps,
};

/// Serialises migrators across processes ("photomig").
pub const MIGRATE_LOCK: i64 = 0x7068_6f74_6f6d_6967;

/// The framework's own tables. Never edit this: change them with a migration, like any other table.
pub(crate) const BOOTSTRAP: &str = "
CREATE TABLE IF NOT EXISTS schema_migrations (
    version bigint PRIMARY KEY,
    name text NOT NULL,
    checksum bytea NOT NULL,
    applied_at timestamptz NOT NULL DEFAULT now(),
    duration_ms bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS data_migrations (
    id text PRIMARY KEY,
    description text NOT NULL,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'done', 'failed')),
    cursor text,
    processed bigint NOT NULL DEFAULT 0,
    total bigint,
    error text,
    started_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz
);
CREATE TABLE IF NOT EXISTS quarantined_rows (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name text NOT NULL,
    data_migration text NOT NULL,
    data jsonb NOT NULL,
    quarantined_at timestamptz NOT NULL DEFAULT now()
);";

const FILES: &[(&str, &str)] = include!(concat!(env!("OUT_DIR"), "/migrations.rs"));

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Migration {
    pub version: i64,
    pub name: String,
    pub sql: String,
}

impl Migration {
    /// A migration from its file name, `NNNN_description.sql`, and its contents.
    pub fn new(file: &str, sql: &str) -> Result<Migration, String> {
        let parsed = file
            .strip_suffix(".sql")
            .and_then(|stem| stem.split_once('_'))
            .filter(|(number, name)| {
                number.len() == 4 && number.bytes().all(|b| b.is_ascii_digit()) && !name.is_empty()
            });
        let (number, name) = parsed.ok_or_else(|| format!("{file}: a migration is named NNNN_description.sql"))?;
        Ok(Migration {
            version: number.parse().unwrap_or_default(),
            name: name.into(),
            sql: sql.into(),
        })
    }

    pub fn checksum(&self) -> Vec<u8> {
        Sha256::digest(&self.sql).to_vec()
    }

    /// The data migration named by `-- photolib:prescan <id>`, which runs to the end right before this one.
    pub fn prescan(&self) -> Option<&str> {
        self.sql
            .lines()
            .find_map(|line| line.trim().strip_prefix("-- photolib:prescan "))
            .map(str::trim)
    }
}

impl fmt::Display for Migration {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:04}_{}", self.version, self.name)
    }
}

/// The migrations built into this binary, oldest first.
pub fn embedded() -> Vec<Migration> {
    FILES
        .iter()
        .map(|(file, sql)| Migration::new(file, sql).unwrap_or_else(|error| panic!("{error}")))
        .collect()
}

/// What to upgrade to and how.
pub struct Upgrade<'a> {
    pub migrations: &'a [Migration],
    /// The data migrations that migrations can name as their pre-scan.
    pub data: &'a [Box<dyn DataMigration>],
    /// Dump a database that already has a schema before upgrading it; `None` skips the dump.
    pub dumps: Option<Dumps>,
}

impl<'a> Upgrade<'a> {
    pub fn new(migrations: &'a [Migration]) -> Self {
        Upgrade {
            migrations,
            data: &[],
            dumps: None,
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    Current(i64),
    Upgraded { from: i64, to: i64, dump: Option<PathBuf> },
}

#[derive(Debug, PartialEq, Eq)]
pub enum Error {
    /// Nothing was changed, and photolibd must not start.
    Refused(String),
    /// The upgrade was rolled back: the schema is unchanged.
    Failed { error: String, dump: Option<PathBuf> },
}

/// Brings the database to the newest of `up.migrations`.
pub async fn upgrade(pool: &PgPool, up: &Upgrade<'_>) -> Result<Outcome, Error> {
    let refused = |error: sqlx::Error| Error::Refused(format!("the database cannot be migrated: {error}"));
    let mut tx = pool.begin().await.map_err(refused)?;
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(MIGRATE_LOCK)
        .execute(&mut *tx)
        .await
        .map_err(refused)?;
    sqlx::raw_sql(BOOTSTRAP).execute(&mut *tx).await.map_err(refused)?;
    let applied: Vec<(i64, String, Vec<u8>)> =
        sqlx::query_as("SELECT version, name, checksum FROM schema_migrations ORDER BY version")
            .fetch_all(&mut *tx)
            .await
            .map_err(refused)?;
    let from = applied.last().map_or(0, |(version, ..)| *version);
    let pending = plan(up.migrations, &applied).map_err(Error::Refused)?;
    let Some(to) = pending.last().map(|m| m.version) else {
        return Ok(Outcome::Current(from));
    };
    let dump = match &up.dumps {
        Some(dumps) if from > 0 => {
            let stamp = crate::dump::stamp(&mut tx).await.map_err(refused)?;
            Some(dumps.take(&format!("{from:04}-{to:04}"), &stamp).await.map_err(|error| {
                Error::Refused(format!(
                    "the dump before upgrading from version {from} to {to} failed, so nothing was changed: {error}"
                ))
            })?)
        }
        _ => None,
    };
    let failed = |error: String| Error::Failed {
        error,
        dump: dump.clone(),
    };
    apply(&mut tx, &pending, up.data).await.map_err(failed)?;
    tx.commit().await.map_err(|error| failed(error.to_string()))?;
    Ok(Outcome::Upgraded { from, to, dump })
}

/// The migrations still to apply, or why this binary must not touch the database.
fn plan<'m>(migrations: &'m [Migration], applied: &[(i64, String, Vec<u8>)]) -> Result<Vec<&'m Migration>, String> {
    let newest = migrations.last().map_or(0, |m| m.version);
    if let Some((version, name, _)) = applied.last().filter(|(version, ..)| *version > newest) {
        return Err(format!(
            "the database schema is at version {version} ({name}), newer than this photolibd knows (version \
             {newest}): photolibd was downgraded. Start the release that upgraded the database, or a newer one; \
             to go back to this release, restore the dump taken before that upgrade with `photolibd restore`"
        ));
    }
    for (version, name, checksum) in applied {
        match migrations.iter().find(|m| m.version == *version) {
            Some(m) if m.checksum() != *checksum => {
                return Err(format!(
                    "migration {m} was edited after it was applied to this database; released migrations are \
                     immutable. Start photolibd from an unmodified release, and add a new migration for the \
                     change"
                ));
            }
            Some(_) => {}
            None => {
                return Err(format!(
                    "the database has migration {version:04}_{name}, which this photolibd does not know: it \
                     came from a build that is not a release. Restore the dump taken before it was applied"
                ));
            }
        }
    }
    let newest_applied = applied.last().map_or(0, |(version, ..)| *version);
    let pending: Vec<&Migration> = migrations
        .iter()
        .filter(|m| !applied.iter().any(|(version, ..)| *version == m.version))
        .collect();
    if let Some(m) = pending.iter().find(|m| m.version < newest_applied) {
        return Err(format!(
            "migration {m} was never applied but is older than the newest applied one \
             ({newest_applied}): the database was migrated by a build that is not a release. Restore the dump \
             taken before that"
        ));
    }
    Ok(pending)
}

async fn apply(tx: &mut PgConnection, pending: &[&Migration], data: &[Box<dyn DataMigration>]) -> Result<(), String> {
    let before = invariants(tx).await.map_err(|error| error.to_string())?;
    for m in pending {
        let started = Instant::now();
        if let Some(id) = m.prescan() {
            let prescan = data.iter().find(|d| d.id() == id).ok_or_else(|| {
                format!("migration {m} names the pre-scan {id}, which is not a registered data migration")
            })?;
            data::finish(tx, prescan.as_ref())
                .await
                .map_err(|error| format!("the pre-scan of migration {m} failed: {error}"))?;
        }
        sqlx::raw_sql(&m.sql)
            .execute(&mut *tx)
            .await
            .map_err(|error| format!("migration {m} failed: {error}"))?;
        sqlx::query("INSERT INTO schema_migrations (version, name, checksum, duration_ms) VALUES ($1, $2, $3, $4)")
            .bind(m.version)
            .bind(&m.name)
            .bind(m.checksum())
            .bind(started.elapsed().as_millis() as i64)
            .execute(&mut *tx)
            .await
            .map_err(|error| error.to_string())?;
    }
    let after = invariants(tx).await.map_err(|error| error.to_string())?;
    match broken(&before, &after) {
        Some(invariant) => Err(format!("the upgrade broke an invariant: {invariant}")),
        None => Ok(()),
    }
}

/// What an upgrade must preserve: the rows of every table, which only a quarantine may move, and the database- and
/// role-level settings.
struct Invariants {
    rows: BTreeMap<String, i64>,
    quarantined: BTreeMap<String, i64>,
    settings: String,
}

async fn invariants(conn: &mut PgConnection) -> sqlx::Result<Invariants> {
    let rows = sqlx::query_as(
        "SELECT relname::text, (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM %I.%I',
         current_schema(), relname), false, true, '')))[1]::text::bigint
         FROM pg_class WHERE relnamespace = current_schema()::regnamespace AND relkind IN ('r', 'p')",
    )
    .fetch_all(&mut *conn)
    .await?;
    let quarantined = sqlx::query_as("SELECT table_name, count(*) FROM quarantined_rows GROUP BY 1")
        .fetch_all(&mut *conn)
        .await?;
    let settings = sqlx::query_scalar(
        "SELECT coalesce(string_agg(format('%s/%s/%s', setdatabase, setrole, setconfig), ';'
         ORDER BY setdatabase, setrole), '') FROM pg_db_role_setting",
    )
    .fetch_one(conn)
    .await?;
    Ok(Invariants {
        rows: rows.into_iter().collect(),
        quarantined: quarantined.into_iter().collect(),
        settings,
    })
}

fn broken(before: &Invariants, after: &Invariants) -> Option<String> {
    if before.settings != after.settings {
        return Some(
            "it changed database- or role-level settings (ALTER DATABASE or ALTER ROLE ... SET), which migrations \
             may not do"
                .into(),
        );
    }
    let quarantined = |at: &Invariants, table: &str| at.quarantined.get(table).copied().unwrap_or(0);
    before.rows.iter().find_map(|(table, &was)| {
        let now = *after.rows.get(table)?;
        let moved = quarantined(after, table) - quarantined(before, table);
        (now + moved < was).then(|| {
            format!(
                "table {table} lost {} rows ({was} before, {now} after, {moved} quarantined); only data migrations \
                 may remove rows",
                was - now - moved
            )
        })
    })
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::{data::Quarantine, testpg};

    #[tokio::test]
    async fn a_fresh_database_gets_every_migration_once() {
        let db = testpg::database().await;
        let migrations = embedded();
        let newest = migrations.last().unwrap().version;
        let up = Upgrade::new(&migrations);
        assert_eq!(
            upgrade(&db.pool, &up).await.unwrap(),
            Outcome::Upgraded {
                from: 0,
                to: newest,
                dump: None
            }
        );
        assert_eq!(upgrade(&db.pool, &up).await.unwrap(), Outcome::Current(newest));
        let recorded: Vec<i64> = sqlx::query_scalar("SELECT version FROM schema_migrations ORDER BY version")
            .fetch_all(&db.pool)
            .await
            .unwrap();
        assert_eq!(recorded, migrations.iter().map(|m| m.version).collect::<Vec<_>>());
    }

    pub(crate) fn set(files: &[(&str, &str)]) -> Vec<Migration> {
        files
            .iter()
            .map(|(file, sql)| Migration::new(file, sql).unwrap())
            .collect()
    }

    pub(crate) const T1: (&str, &str) = ("0001_t.sql", "CREATE TABLE t (x int);");
    const T2: (&str, &str) = ("0002_u.sql", "CREATE TABLE u (y int);");

    async fn migrated(files: &[(&str, &str)]) -> PgPool {
        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&set(files))).await.unwrap();
        pool
    }

    #[tokio::test]
    async fn incompatible_migration_histories_are_refused() {
        const T3: (&str, &str) = ("0003_v.sql", "CREATE TABLE v (z int);");
        let edited = ("0001_t.sql", "CREATE TABLE t (x bigint);");
        for (before, after, expected) in [
            (
                &[T1, T2][..],
                &[T1][..],
                &[
                    "version 2 (u)",
                    "newer than this photolibd",
                    "downgraded",
                    "photolibd restore",
                ][..],
            ),
            (&[T1, T2], &[edited, T2], &["0001_t", "edited", "immutable"]),
            (&[T1, T2], &[T1, T3], &["0002_u", "does not know"]),
            (&[T1, T3], &[T1, T2, T3], &["0002_u", "older than"]),
        ] {
            let pool = migrated(before).await;
            let message = match upgrade(&pool, &Upgrade::new(&set(after))).await {
                Err(Error::Refused(message)) => message,
                other => panic!("expected a refusal, got {other:?}"),
            };
            for words in expected {
                assert!(message.contains(words), "{words:?} missing from: {message}");
            }
        }
    }

    async fn tables(pool: &PgPool) -> Vec<String> {
        sqlx::query_scalar("SELECT tablename::text FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")
            .fetch_all(pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn a_failing_migration_rolls_back_the_whole_upgrade() {
        let pool = migrated(&[T1]).await;
        let before = tables(&pool).await;
        let broken = ("0003_broken.sql", "ALTER TABLE t ADD COLUMN y int; SELECT 1/0;");
        match upgrade(&pool, &Upgrade::new(&set(&[T1, T2, broken]))).await {
            Err(Error::Failed { error, dump: None }) => {
                assert!(
                    error.contains("0003_broken") && error.contains("division by zero"),
                    "{error}"
                )
            }
            other => panic!("expected a failed upgrade, got {other:?}"),
        }
        assert_eq!(tables(&pool).await, before, "0002 was rolled back too");
        let columns: i64 = sqlx::query_scalar("SELECT count(*) FROM information_schema.columns WHERE table_name = 't'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(columns, 1, "the column 0003 added was rolled back");
        assert_eq!(
            upgrade(&pool, &Upgrade::new(&set(&[T1]))).await,
            Ok(Outcome::Current(1))
        );
    }

    #[tokio::test]
    async fn concurrent_starts_migrate_once() {
        let db = testpg::database().await;
        let migrations = set(&[T1, T2]);
        let up = Upgrade::new(&migrations);
        let (a, b, c, d) = tokio::join!(
            upgrade(&db.pool, &up),
            upgrade(&db.pool, &up),
            upgrade(&db.pool, &up),
            upgrade(&db.pool, &up)
        );
        let results = [a, b, c, d];
        let upgraded = results
            .iter()
            .filter(|result| matches!(result, Ok(Outcome::Upgraded { .. })))
            .count();
        assert_eq!(upgraded, 1, "{results:?}");
        assert!(
            results
                .iter()
                .all(|result| matches!(result, Ok(Outcome::Upgraded { .. } | Outcome::Current(2)))),
            "{results:?}"
        );
    }

    #[tokio::test]
    async fn a_constraint_migration_first_quarantines_the_rows_that_violate_it() {
        let people = (
            "0001_people.sql",
            "CREATE TABLE people (id int PRIMARY KEY, email text);",
        );
        let pool = migrated(&[people]).await;
        sqlx::query("INSERT INTO people VALUES (1, 'a'), (2, NULL), (3, 'b'), (4, NULL)")
            .execute(&pool)
            .await
            .unwrap();
        let not_null = (
            "0002_email_required.sql",
            "-- photolib:prescan people_without_email\nALTER TABLE people ALTER COLUMN email SET NOT NULL;",
        );
        let migrations = set(&[people, not_null]);
        let unregistered = upgrade(&pool, &Upgrade::new(&migrations)).await;
        assert!(
            matches!(&unregistered, Err(Error::Failed { error, .. }) if error.contains("people_without_email")),
            "{unregistered:?}"
        );

        let data: Vec<Box<dyn DataMigration>> = vec![Box::new(Quarantine {
            id: "people_without_email",
            description: "people without an email address",
            table: "people",
            violating: "email IS NULL",
        })];
        let up = Upgrade {
            data: &data,
            ..Upgrade::new(&migrations)
        };
        assert!(matches!(upgrade(&pool, &up).await, Ok(Outcome::Upgraded { to: 2, .. })));
        let ids: Vec<i32> = sqlx::query_scalar("SELECT id FROM people ORDER BY id")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(ids, [1, 3]);
        let quarantined: Vec<(String, String, String)> =
            sqlx::query_as("SELECT table_name, data_migration, data->>'id' FROM quarantined_rows ORDER BY 3")
                .fetch_all(&pool)
                .await
                .unwrap();
        let expected = |id: &str| ("people".to_string(), "people_without_email".to_string(), id.to_string());
        assert_eq!(quarantined, [expected("2"), expected("4")]);
        let status: String = sqlx::query_scalar("SELECT status FROM data_migrations WHERE id = 'people_without_email'")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!(status, "done");
    }

    #[tokio::test]
    async fn an_upgrade_that_breaks_an_invariant_is_rolled_back() {
        let pool = migrated(&[T1]).await;
        sqlx::query("INSERT INTO t VALUES (1), (2), (3)")
            .execute(&pool)
            .await
            .unwrap();
        let alter_database = "DO $$BEGIN EXECUTE format('ALTER DATABASE %I SET work_mem = ''8MB''', \
                              current_database()); END$$;";
        let breakers = [
            ("0002_purge.sql", "DELETE FROM t WHERE x > 1;", "table t lost 2 rows"),
            (
                "0002_role.sql",
                "ALTER ROLE CURRENT_USER SET work_mem = '8MB';",
                "role-level settings",
            ),
            ("0002_database.sql", alter_database, "database- or role-level settings"),
        ];
        for (file, sql, words) in breakers {
            match upgrade(&pool, &Upgrade::new(&set(&[T1, (file, sql)]))).await {
                Err(Error::Failed { error, .. }) => {
                    assert!(error.contains(words), "{words:?} missing from: {error}")
                }
                other => panic!("{file}: expected a failed upgrade, got {other:?}"),
            }
        }
        let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM t")
            .fetch_one(&pool)
            .await
            .unwrap();
        let settings: i64 = sqlx::query_scalar("SELECT count(*) FROM pg_db_role_setting")
            .fetch_one(&pool)
            .await
            .unwrap();
        assert_eq!((rows, settings), (3, 0));
    }
}
