//! The automatic dump before an upgrade, its retention, and the restore that undoes an upgrade.

use std::{
    fs,
    io::Write,
    os::unix::fs::{DirBuilderExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use percent_encoding::percent_decode_str;
use url::Url;

use crate::migrate::MIGRATE_LOCK;

/// Where and how to dump the database before an upgrade, and how many of those dumps to keep.
#[derive(Debug, Clone)]
pub struct Dumps {
    pub url: String,
    /// The directory with `pg_dump`, `pg_restore` and `psql`; `None` looks them up on `PATH`.
    pub bin_dir: Option<PathBuf>,
    pub dir: PathBuf,
    pub keep: usize,
}

impl Dumps {
    /// Writes `pre-<what>-<stamp>.dump`, such as `pre-0001-0002-…` before a schema upgrade, and removes the oldest
    /// dumps beyond `keep`.
    pub async fn take(&self, what: &str, stamp: &str) -> Result<PathBuf, String> {
        let path = self.dir.join(format!("pre-{what}-{stamp}.dump"));
        dump(&self.url, self.bin_dir.as_deref(), &path).await?;
        let mut dumps = list(&self.dir);
        while dumps.len() > self.keep.max(1) {
            let oldest = dumps.remove(0);
            fs::remove_file(&oldest).map_err(|error| format!("cannot remove {}: {error}", oldest.display()))?;
        }
        Ok(path)
    }
}

/// The database's time in UTC as dump names have it, `20261015T201042Z`.
pub async fn stamp(conn: &mut sqlx::PgConnection) -> sqlx::Result<String> {
    sqlx::query_scalar("SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYYMMDD\"T\"HH24MISS\"Z\"')")
        .fetch_one(conn)
        .await
}

/// Dumps the database at `url` into `path` (custom format), through a partial file renamed when complete. A dump
/// holds every row, password records included: only the owner may read it and its directory.
pub async fn dump(url: &str, bin_dir: Option<&Path>, path: &Path) -> Result<(), String> {
    let partial = path.with_extension("dump.partial");
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)
        .map_err(|error| format!("cannot create {}: {error}", dir.display()))?;
    let mut pg_dump = tool(bin_dir, "pg_dump", Some(url))?;
    pg_dump.arg("--format=custom").arg("--file").arg(&partial);
    run(pg_dump).await?;
    fs::set_permissions(&partial, fs::Permissions::from_mode(0o600))
        .and_then(|()| fs::rename(&partial, path))
        .map_err(|error| format!("cannot write {}: {error}", path.display()))
}

/// The pre-upgrade dumps in `dir`, oldest first.
fn list(dir: &Path) -> Vec<PathBuf> {
    let mut dumps: Vec<(String, PathBuf)> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            let name = path.file_name()?.to_str()?;
            let stamp = name.strip_prefix("pre-")?.strip_suffix(".dump")?.rsplit('-').next()?;
            Some((stamp.to_string(), path))
        })
        .collect();
    dumps.sort();
    dumps.into_iter().map(|(_, path)| path).collect()
}

/// The newest pre-upgrade dump in `dir`.
pub fn newest(dir: &Path) -> Option<PathBuf> {
    list(dir).pop()
}

/// Drops everything in the schema the dump restores into, in the restore's transaction, so that objects added
/// after the dump do not survive it.
const CLEAR: &str = "
DO $$DECLARE drop_it text; BEGIN
  FOR drop_it IN SELECT statement FROM (
    SELECT CASE relkind WHEN 'S' THEN 2 ELSE 1 END AS step, format('DROP %s IF EXISTS %I CASCADE', CASE relkind
      WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, relname)
    FROM pg_class WHERE relnamespace = current_schema()::regnamespace AND relkind IN ('r', 'p', 'v', 'm', 'S')
    UNION ALL SELECT 3, format('DROP ROUTINE IF EXISTS %s CASCADE', oid::regprocedure)
    FROM pg_proc WHERE pronamespace = current_schema()::regnamespace
    UNION ALL SELECT 4, format('DROP TYPE IF EXISTS %I CASCADE', typname)
    FROM pg_type WHERE typnamespace = current_schema()::regnamespace AND typtype IN ('e', 'd', 'r', 'm')
  ) AS objects(step, statement) ORDER BY step
  LOOP EXECUTE drop_it; END LOOP;
END$$";

/// Replaces the schema and data with those of `dump`, in one transaction: on any error nothing changes. psql commits
/// only once pg_restore has written the whole dump, so a dump it cannot read changes nothing either.
pub async fn restore(url: &str, bin_dir: Option<&Path>, dump: &Path) -> Result<(), String> {
    if !dump.is_file() {
        return Err(format!("the dump {} does not exist", dump.display()));
    }
    let mut pg_restore = tool(bin_dir, "pg_restore", None)?;
    pg_restore
        .args(["--no-owner", "--no-privileges", "--file=-"])
        .arg(dump)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut psql = tool(bin_dir, "psql", Some(url))?;
    psql.args(["--no-psqlrc", "--quiet", "--set=ON_ERROR_STOP=1", "--file=-"])
        .env("PGOPTIONS", "-c client_min_messages=warning")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    tokio::task::spawn_blocking(move || {
        let mut consumer = psql.spawn().map_err(|error| cannot_start("psql", &error))?;
        let mut producer = pg_restore.spawn().map_err(|error| cannot_start("pg_restore", &error))?;
        let piped = "a pipe to pg_restore or psql is missing";
        let (mut sql, mut stdin) = (
            producer.stdout.take().ok_or(piped)?,
            consumer.stdin.take().ok_or(piped)?,
        );
        let (errors, messages) = (
            producer.stderr.take().ok_or(piped)?,
            consumer.stderr.take().ok_or(piped)?,
        );
        let read = |mut pipe: std::process::ChildStderr| {
            std::thread::spawn(move || {
                let mut text = String::new();
                std::io::Read::read_to_string(&mut pipe, &mut text)
                    .map(|_| text)
                    .unwrap_or_default()
            })
        };
        let (errors, messages) = (read(errors), read(messages));
        let copied = writeln!(stdin, "BEGIN; SELECT pg_advisory_xact_lock({MIGRATE_LOCK}); {CLEAR};")
            .and_then(|()| std::io::copy(&mut sql, &mut stdin));
        let produced = producer.wait().map_err(|error| error.to_string())?;
        let copied = copied.and_then(|_| {
            if produced.success() {
                writeln!(stdin, "COMMIT;")
            } else {
                Ok(())
            }
        });
        // Without COMMIT, psql ends at the end of its input and PostgreSQL rolls the transaction back.
        drop(stdin);
        let consumed = consumer.wait().map_err(|error| error.to_string())?;
        let failed = |name: &str, text: std::thread::JoinHandle<String>| {
            format!("{name} failed: {}", text.join().unwrap_or_default().trim())
        };
        // psql stops at an error, and pg_restore then fails to write: psql says why.
        match (consumed.success(), produced.success()) {
            (false, _) => Err(failed("psql", messages)),
            (_, false) => Err(failed("pg_restore", errors)),
            _ => copied.map_err(|error| format!("cannot pass the dump to psql: {error}")),
        }
    })
    .await
    .map_err(|error| error.to_string())?
}

/// A PostgreSQL client program; the password moves from the URL to `PGPASSWORD` so that it never shows in `ps`.
fn tool(bin_dir: Option<&Path>, name: &str, url: Option<&str>) -> Result<Command, String> {
    let mut command = Command::new(bin_dir.map_or_else(|| PathBuf::from(name), |dir| dir.join(name)));
    if let Some(url) = url {
        let mut url = Url::parse(url).map_err(|error| format!("the database URL is invalid: {error}"))?;
        if let Some(password) = url.password() {
            command.env("PGPASSWORD", percent_decode_str(password).decode_utf8_lossy().as_ref());
            let _ = url.set_password(None);
        }
        command.arg(format!("--dbname={url}"));
    }
    Ok(command)
}

fn cannot_start(name: &str, error: &std::io::Error) -> String {
    format!(
        "cannot run {name}: {error}; install the PostgreSQL client programs (pg_dump, pg_restore, psql) of the \
         server's major version or newer"
    )
}

async fn run(mut command: Command) -> Result<(), String> {
    let name = command
        .get_program()
        .to_string_lossy()
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_string();
    let output = tokio::task::spawn_blocking(move || command.output())
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| cannot_start(&name, &error))?;
    check(&name, &output)
}

fn check(name: &str, output: &std::process::Output) -> Result<(), String> {
    match output.status.success() {
        true => Ok(()),
        false => Err(format!(
            "{name} failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        migrate::{
            Error, Outcome, Upgrade,
            tests::{T1, set},
            upgrade,
        },
        testpg,
    };

    const T2: (&str, &str) = ("0002_u.sql", "CREATE TABLE u (y int); INSERT INTO t VALUES (7);");

    async fn rows(pool: &sqlx::PgPool, sql: &str) -> Vec<String> {
        sqlx::query_scalar(sql).fetch_all(pool).await.unwrap()
    }

    #[tokio::test]
    async fn an_upgrade_is_preceded_by_a_dump_that_restores_the_old_schema_and_data() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let dumps = Dumps {
            url: db.url.clone(),
            bin_dir: Some(testpg::bin_dir()),
            dir: dir.path().join("backups"),
            keep: 3,
        };
        let v1 = set(&[T1]);
        let fresh = upgrade(
            &db.pool,
            &Upgrade {
                dumps: Some(dumps.clone()),
                ..Upgrade::new(&v1)
            },
        )
        .await;
        assert_eq!(
            fresh,
            Ok(Outcome::Upgraded {
                from: 0,
                to: 1,
                dump: None
            }),
            "an empty database is not dumped"
        );
        sqlx::query("INSERT INTO t VALUES (1), (2)")
            .execute(&db.pool)
            .await
            .unwrap();

        let v2 = set(&[T1, T2]);
        let Ok(Outcome::Upgraded {
            from: 1,
            to: 2,
            dump: Some(dump),
        }) = upgrade(
            &db.pool,
            &Upgrade {
                dumps: Some(dumps.clone()),
                ..Upgrade::new(&v2)
            },
        )
        .await
        else {
            panic!("the upgrade of a used database was not dumped");
        };
        let name = dump.file_name().unwrap().to_str().unwrap().to_string();
        assert!(name.starts_with("pre-0001-0002-") && name.ends_with("Z.dump"), "{name}");
        assert_eq!(dump.parent(), Some(dumps.dir.as_path()));
        let mode = |path: &Path| fs::metadata(path).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            (mode(&dumps.dir), mode(&dump)),
            (0o700, 0o600),
            "only the owner reads the data"
        );

        restore(&db.url, dumps.bin_dir.as_deref(), &dump).await.unwrap();
        let tables = "SELECT tablename::text FROM pg_tables WHERE schemaname = 'public' ORDER BY 1";
        assert_eq!(
            rows(&db.pool, tables).await,
            ["data_migrations", "quarantined_rows", "schema_migrations", "t"]
        );
        assert_eq!(rows(&db.pool, "SELECT x::text FROM t ORDER BY x").await, ["1", "2"]);
        assert_eq!(upgrade(&db.pool, &Upgrade::new(&v1)).await, Ok(Outcome::Current(1)));
        let missing = restore(&db.url, dumps.bin_dir.as_deref(), &dir.path().join("nope.dump")).await;
        assert!(missing.unwrap_err().contains("nope.dump"));
    }

    async fn used(db: &testpg::TestDb) {
        upgrade(&db.pool, &Upgrade::new(&set(&[T1]))).await.unwrap();
    }

    fn dumps(db: &testpg::TestDb, dir: &Path) -> Dumps {
        Dumps {
            url: db.url.clone(),
            bin_dir: Some(testpg::bin_dir()),
            dir: dir.to_path_buf(),
            keep: 2,
        }
    }

    #[tokio::test]
    async fn only_the_newest_dumps_are_kept() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let dumps = dumps(&db, dir.path());
        used(&db).await;
        for old in [
            "pre-0000-0001-20200101T000000Z.dump",
            "pre-0000-0001-20210101T000000Z.dump",
            "notes.txt",
        ] {
            fs::write(dir.path().join(old), "").unwrap();
        }
        let v2 = set(&[T1, T2]);
        let up = Upgrade {
            dumps: Some(dumps),
            ..Upgrade::new(&v2)
        };
        let Ok(Outcome::Upgraded { dump: Some(new), .. }) = upgrade(&db.pool, &up).await else {
            panic!("no dump");
        };
        let mut left: Vec<_> = fs::read_dir(dir.path())
            .unwrap()
            .map(|entry| entry.unwrap().file_name().into_string().unwrap())
            .collect();
        left.sort();
        let new = new.file_name().unwrap().to_str().unwrap().to_string();
        assert_eq!(left, ["notes.txt", "pre-0000-0001-20210101T000000Z.dump", new.as_str()]);
        assert_eq!(newest(dir.path()), Some(dir.path().join(&new)));
    }

    #[tokio::test]
    async fn a_failing_dump_stops_the_upgrade_before_it_changes_anything() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let mut dumps = dumps(&db, dir.path());
        used(&db).await;
        dumps.bin_dir = Some(dir.path().join("no-such-bin"));
        let v2 = set(&[T1, T2]);
        let up = Upgrade {
            dumps: Some(dumps),
            ..Upgrade::new(&v2)
        };
        match upgrade(&db.pool, &up).await {
            Err(Error::Refused(message)) => assert!(
                message.contains("pg_dump") && message.contains("nothing was changed"),
                "{message}"
            ),
            other => panic!("expected a refusal, got {other:?}"),
        }
        assert_eq!(
            upgrade(&db.pool, &Upgrade::new(&set(&[T1]))).await,
            Ok(Outcome::Current(1))
        );
    }

    #[tokio::test]
    async fn a_dump_that_cannot_be_read_restores_nothing() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        used(&db).await;
        sqlx::query("INSERT INTO t VALUES (1)").execute(&db.pool).await.unwrap();
        let broken = dir.path().join("broken.dump");
        fs::write(&broken, b"PGDMP but not really").unwrap();
        let error = restore(&db.url, Some(&testpg::bin_dir()), &broken).await.unwrap_err();
        assert!(error.contains("pg_restore"), "{error}");
        assert_eq!(
            rows(&db.pool, "SELECT x::text FROM t").await,
            ["1"],
            "the database is unchanged"
        );
    }

    #[tokio::test]
    async fn a_failed_upgrade_names_the_dump_that_undoes_it() {
        let db = testpg::database().await;
        let dir = tempfile::tempdir().unwrap();
        let dumps = dumps(&db, dir.path());
        used(&db).await;
        let broken = set(&[T1, ("0002_broken.sql", "SELECT 1/0;")]);
        let up = Upgrade {
            dumps: Some(dumps),
            ..Upgrade::new(&broken)
        };
        match upgrade(&db.pool, &up).await {
            Err(Error::Failed { dump: Some(dump), .. }) => assert!(dump.is_file()),
            other => panic!("expected a failed upgrade with a dump, got {other:?}"),
        }
    }
}
