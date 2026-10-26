//! The schema upgrade at startup, maintenance mode after a failed one, the background data migrations, and the
//! `migrate`, `doctor schema` and `restore` commands.

use std::path::{Path, PathBuf};

use photolib_db::{
    data::{self, DataMigration},
    doctor,
    dump::{self, Dumps},
    migrate::{self, Migration, Outcome, Upgrade},
};
use sqlx::PgPool;
use tokio_util::sync::CancellationToken;

use crate::{config::Config, db::Database, mounts, pg::PgDatabase, run::prepare};

fn url(config: &Config) -> Result<&str, String> {
    let url = config.database.url.as_ref().ok_or("database.url is not set")?;
    Ok(url.expose())
}

pub(crate) fn backups(config: &Config) -> Result<PathBuf, String> {
    let data_dir = config.data_dir.as_ref().ok_or("data_dir is not set")?;
    Ok(data_dir.join("backups"))
}

/// Brings the schema to `migrations` before anything is served. `Ok(Some(reason))`: the upgrade failed and was
/// rolled back, and the process serves in maintenance mode. `Err`: the process must not start.
pub async fn startup(config: &Config, pool: &PgPool, migrations: &[Migration]) -> Result<Option<String>, String> {
    let registry = data::registry();
    let database = &config.database;
    let dumps = match database.pre_upgrade_dump {
        true => Some(Dumps {
            url: url(config)?.to_string(),
            bin_dir: database.bin_dir.clone(),
            dir: backups(config)?,
            keep: database.keep_dumps,
        }),
        false => None,
    };
    let up = Upgrade {
        migrations,
        data: &registry,
        dumps,
    };
    match migrate::upgrade(pool, &up).await {
        Ok(Outcome::Current(version)) => {
            tracing::info!(version, "the database schema is current");
            Ok(None)
        }
        Ok(Outcome::Upgraded { from, to, dump }) => {
            tracing::info!(from, to, ?dump, "the database schema was upgraded");
            Ok(None)
        }
        Err(migrate::Error::Refused(reason)) => Err(reason),
        Err(migrate::Error::Failed { error, dump }) => {
            let way_back = match dump {
                Some(dump) => format!(
                    "to go back to the previous release, stop photolibd, run `photolibd restore {}` and start that \
                     release",
                    dump.display()
                ),
                None => "no pre-upgrade dump was taken".into(),
            };
            let reason = format!(
                "maintenance: the upgrade failed and was rolled back, so the schema is unchanged: {error}. Fix the \
                 cause and restart photolibd; {way_back}"
            );
            tracing::error!(%reason, "maintenance mode");
            Ok(Some(reason))
        }
    }
}

/// `photolibd migrate`: what a start does to the database before it listens (the copy from the previous PostgreSQL
/// major, the instance check, the pre-upgrade dump and the migrations); the version the schema is at.
pub async fn migrate_only(config: &Config) -> Result<i64, String> {
    let pg = (PgDatabase::connect(url(config)?, 0).await)
        .map_err(|error| format!("cannot connect to the database: {error}"))?;
    from_previous_major(config, &pg).await?;
    prepare(config, Some(&pg), mounts::current_mountinfo().as_deref()).await?;
    let migrations = migrate::embedded();
    match startup(config, pg.pool(), &migrations).await? {
        Some(reason) => Err(reason),
        None => Ok(migrations.last().map_or(0, |m| m.version)),
    }
}

/// Copies the database on the previous PostgreSQL major's cluster, `database.upgrade_from`, into the empty one of the
/// new cluster, before the instance check: the bundled PostgreSQL's major upgrade (ADR-0266). The dump it goes through
/// stays among the pre-upgrade dumps, and the previous cluster is left as it was, the way back. Nothing happens on a
/// first start, or once the new database is in use.
pub async fn from_previous_major(config: &Config, db: &dyn Database) -> Result<Option<PathBuf>, String> {
    let (Some(previous), Some(data_dir)) = (&config.database.upgrade_from, &config.data_dir) else {
        return Ok(None);
    };
    let unreadable = |error: sqlx::Error| format!("database.upgrade_from: cannot read the previous database: {error}");
    let used = db.instance_id().await.map_err(|error| error.to_string())?;
    let Some(ours) = crate::instance::read_marker(data_dir)?.filter(|_| used.is_none()) else {
        return Ok(None);
    };
    let old = PgPool::connect(previous.expose()).await.map_err(|error| {
        format!("database.upgrade_from: the previous cluster, which holds this instance's database until it is copied, is unreachable: {error}")
    })?;
    let theirs: Option<String> = sqlx::query_scalar(
        "SELECT CASE WHEN to_regclass('photolib_instance') IS NOT NULL THEN (SELECT instance_id::text FROM photolib_instance) END",
    )
    .fetch_one(&old)
    .await
    .map_err(unreadable)?;
    if theirs != Some(ours.to_string()) {
        return Err(format!(
            "database.upgrade_from holds {}, not instance {ours} of the data directory: another instance",
            theirs.as_deref().unwrap_or("no instance")
        ));
    }
    let new = PgPool::connect(url(config)?).await.map_err(|error| error.to_string())?;
    let major = async |pool: &PgPool| -> Result<i32, String> {
        let version: String = sqlx::query_scalar("SHOW server_version_num")
            .fetch_one(pool)
            .await
            .map_err(|error| error.to_string())?;
        Ok(version.parse::<i32>().unwrap_or_default() / 10_000)
    };
    let stamp = async { dump::stamp(&mut *new.acquire().await?).await };
    let stamp = stamp.await.map_err(|error: sqlx::Error| error.to_string())?;
    let dumps = Dumps {
        url: previous.expose().clone(),
        bin_dir: config.database.bin_dir.clone(),
        dir: backups(config)?,
        keep: config.database.keep_dumps,
    };
    let what = format!("pg{}-pg{}", major(&old).await?, major(&new).await?);
    let dump = dumps.take(&what, &stamp).await?;
    dump::restore(url(config)?, config.database.bin_dir.as_deref(), &dump).await?;
    tracing::info!(?dump, "the database of the previous PostgreSQL major was copied");
    Ok(Some(dump))
}

/// Runs the data migrations that are not done, one after another, until they finish or `shutdown`.
pub async fn run_data_migrations(pool: &PgPool, migrations: &[Box<dyn DataMigration>], shutdown: &CancellationToken) {
    for migration in migrations {
        match data::run(pool, migration.as_ref(), || shutdown.is_cancelled()).await {
            Ok(true) => tracing::info!(id = migration.id(), "data migration done"),
            Ok(false) => return,
            Err(error) => tracing::error!(%error, "data migration failed"),
        }
    }
}

/// `photolibd doctor schema`: what differs between the database and the schema its migrations build.
pub async fn doctor_schema(config: &Config) -> Result<Vec<String>, String> {
    let pool = PgPool::connect(url(config)?)
        .await
        .map_err(|error| format!("cannot connect to the database: {error}"))?;
    doctor::drift(&pool, &migrate::embedded())
        .await
        .map_err(|error| format!("cannot compare the schema: {error}"))
}

/// `photolibd restore [DUMP]`: replaces the database with a dump, by default the newest pre-upgrade dump, and counts
/// the restore into the instance's epoch.
pub async fn restore(config: &Config, dump: Option<&Path>) -> Result<PathBuf, String> {
    let dump = match dump {
        Some(dump) => dump.to_path_buf(),
        None => {
            let dir = backups(config)?;
            dump::newest(&dir).ok_or_else(|| format!("there is no pre-upgrade dump in {}", dir.display()))?
        }
    };
    dump::restore(url(config)?, config.database.bin_dir.as_deref(), &dump).await?;
    if let Some(data_dir) = &config.data_dir {
        crate::instance::count_restore(data_dir)?;
    }
    Ok(dump)
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        data::{DataMigration, Quarantine},
        migrate::{Migration, embedded},
        testpg,
    };

    use super::*;
    use crate::{role::Role, secret::Secret, testing};

    fn config(db: &testpg::TestDb, data_dir: &Path) -> Config {
        let mut config = testing::config(&[Role::Api], data_dir);
        config.database.url = Some(Secret::new(db.url.clone()));
        config.database.bin_dir = Some(testpg::bin_dir());
        config
    }

    #[tokio::test]
    async fn a_failed_upgrade_leaves_the_schema_and_serves_maintenance_with_the_way_back() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let config = config(&db, dir.path());
        let current = embedded();
        assert_eq!(startup(&config, &db.pool, &current).await, Ok(None));
        let mut broken = embedded();
        broken.push(Migration::new("9999_broken.sql", "SELECT 1/0;").unwrap());

        let reason = startup(&config, &db.pool, &broken).await.unwrap().unwrap();
        let dump = photolib_db::dump::newest(&dir.path().join("backups")).unwrap();
        for words in [
            "rolled back",
            "division by zero",
            &format!("photolibd restore {}", dump.display()),
        ] {
            assert!(reason.contains(words), "{words:?} missing from: {reason}");
        }
        assert_eq!(startup(&config, &db.pool, &current).await, Ok(None));

        let id = uuid::Uuid::now_v7();
        crate::instance::write_marker(dir.path(), id).unwrap();
        assert_eq!(restore(&config, None).await, Ok(dump));
        assert_eq!(doctor_schema(&config).await, Ok(Vec::new()));
        let epoch = crate::instance::epoch(dir.path());
        assert_eq!(epoch, Ok(Some(format!("{id}.1"))), "devices see the restore");
    }

    /// The major of the PostgreSQL that the compose bundle runs.
    fn bundled_major() -> u32 {
        let compose = include_str!("../../../../deploy/compose/compose.yaml");
        let image = compose
            .split("image: postgres:")
            .nth(1)
            .expect("the bundle's PostgreSQL");
        image.split('.').next().unwrap().parse().unwrap()
    }

    async fn major(pool: &PgPool) -> i32 {
        let version: String = sqlx::query_scalar("SHOW server_version_num")
            .fetch_one(pool)
            .await
            .unwrap();
        version.parse::<i32>().unwrap() / 10_000
    }

    #[tokio::test]
    async fn the_bundled_postgresql_starts_with_the_database_of_the_previous_major() {
        let bundled = bundled_major();
        let (old_bin, new_bin) = (testpg::bin_of(bundled - 1), testpg::bin_of(bundled));
        let (old, new) = (testpg::database_on(&old_bin).await, testpg::database_on(&new_bin).await);
        let dir = tempfile::tempdir().unwrap();
        let mut config = config(&old, dir.path());
        config.database.bin_dir = Some(new_bin.clone());
        let on_old = PgDatabase::connect(&old.url, 0).await.unwrap();
        let id = crate::instance::verify(dir.path(), &on_old).await.unwrap();
        startup(&config, &old.pool, &embedded()).await.unwrap();
        sqlx::query("INSERT INTO users (id, handle, display_name) VALUES (gen_random_uuid(), 'ann', 'Ann')")
            .execute(&old.pool)
            .await
            .unwrap();

        config.database.url = Some(Secret::new(new.url.clone()));
        config.database.upgrade_from = Some(Secret::new(old.url.clone()));
        let on_new = PgDatabase::connect(&new.url, 0).await.unwrap();
        let dump = from_previous_major(&config, &on_new).await.unwrap().expect("a copy");
        let name = dump.file_name().unwrap().to_str().unwrap().to_string();
        let prefix = format!("pre-pg{}-pg{bundled}-", bundled - 1);
        assert!(name.starts_with(&prefix), "{name}");
        assert_eq!(dump::newest(&dir.path().join("backups")), Some(dump));
        assert_eq!(crate::instance::verify(dir.path(), &on_new).await, Ok(id));
        assert_eq!(startup(&config, &new.pool, &embedded()).await, Ok(None));
        assert_eq!(major(&new.pool).await, i32::try_from(bundled).unwrap());
        let handles: Vec<String> = sqlx::query_scalar("SELECT handle FROM users")
            .fetch_all(&new.pool)
            .await
            .unwrap();
        assert_eq!(handles, ["ann"]);
        assert_eq!(doctor_schema(&config).await, Ok(Vec::new()));
        assert_eq!(
            from_previous_major(&config, &on_new).await,
            Ok(None),
            "a database in use is never replaced"
        );
    }

    #[tokio::test]
    async fn a_previous_major_that_is_unreachable_or_another_instance_stops_a_used_instance_only() {
        let (db, other) = (testpg::database().await, testpg::database().await);
        let dir = tempfile::tempdir().unwrap();
        let mut config = config(&db, dir.path());
        let on_db = PgDatabase::connect(&db.url, 0).await.unwrap();
        config.database.upgrade_from = Some(Secret::new(format!("{}_gone", other.url)));
        assert_eq!(from_previous_major(&config, &on_db).await, Ok(None), "a first start");

        crate::instance::write_marker(dir.path(), uuid::Uuid::now_v7()).unwrap();
        let unreachable = from_previous_major(&config, &on_db).await.unwrap_err();
        assert!(unreachable.contains("database.upgrade_from"), "{unreachable}");
        let on_other = PgDatabase::connect(&other.url, 0).await.unwrap();
        crate::instance::verify(tempfile::tempdir().unwrap().path(), &on_other)
            .await
            .unwrap();
        config.database.upgrade_from = Some(Secret::new(other.url.clone()));
        let stranger = from_previous_major(&config, &on_db).await.unwrap_err();
        assert!(stranger.contains("another instance"), "{stranger}");
    }

    #[tokio::test]
    async fn a_refused_upgrade_stops_startup() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let config = config(&db, dir.path());
        let mut newer = embedded();
        newer.push(Migration::new("9999_newer.sql", "CREATE TABLE newer (x int);").unwrap());
        startup(&config, &db.pool, &newer).await.unwrap();
        let refused = startup(&config, &db.pool, &embedded()).await.unwrap_err();
        assert!(refused.contains("downgraded"), "{refused}");
    }

    #[tokio::test]
    async fn the_doctor_and_the_restore_say_what_is_wrong() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let config = config(&db, dir.path());
        startup(&config, &db.pool, &embedded()).await.unwrap();
        sqlx::query("ALTER TABLE users ADD COLUMN nickname text")
            .execute(&db.pool)
            .await
            .unwrap();
        assert_eq!(
            doctor_schema(&config).await,
            Ok(vec!["unexpected: column users.nickname text".to_string()])
        );
        let none = restore(&config, None).await.unwrap_err();
        assert!(
            none.contains("no pre-upgrade dump") && none.contains("backups"),
            "{none}"
        );
    }

    #[tokio::test]
    async fn pending_data_migrations_run_in_the_background() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        startup(&config(&db, dir.path()), &db.pool, &embedded()).await.unwrap();
        sqlx::query("INSERT INTO ml_labels VALUES ('cat', '{}'), ('dog', 'null')")
            .execute(&db.pool)
            .await
            .unwrap();
        let migrations: Vec<Box<dyn DataMigration>> = vec![Box::new(Quarantine {
            id: "labels_without_names",
            description: "labels whose names are JSON null",
            table: "ml_labels",
            violating: "names = 'null'",
        })];
        run_data_migrations(&db.pool, &migrations, &CancellationToken::new()).await;
        let left: Vec<String> = sqlx::query_scalar("SELECT id FROM ml_labels")
            .fetch_all(&db.pool)
            .await
            .unwrap();
        assert_eq!(left, ["cat"]);
    }
}
