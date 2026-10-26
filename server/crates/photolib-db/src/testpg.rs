//! A throwaway PostgreSQL cluster for tests: one per test process, started on first use, stopped when the process
//! exits and then removed by a watchdog. Every test gets a database of its own.

use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        Mutex,
        atomic::{AtomicU32, Ordering},
    },
    time::Duration,
};

use photolib_spawn::{Group, Running, Signal, output, tool};
use sqlx::{Connection, PgConnection, PgPool};

use crate::cluster;

struct Cluster {
    socket: PathBuf,
    _postgres: Group,
}

/// One cluster per directory of PostgreSQL programs.
static CLUSTERS: Mutex<BTreeMap<PathBuf, &'static Cluster>> = Mutex::new(BTreeMap::new());
static NEXT: AtomicU32 = AtomicU32::new(0);

/// The directory holding `initdb`, `pg_ctl`, `pg_dump`, `pg_restore` and `psql`: `TEST_PG_BIN`, else where
/// [`cluster::programs`] finds them (GitHub's runners have Ubuntu's).
pub fn bin_dir() -> PathBuf {
    std::env::var_os("TEST_PG_BIN")
        .map(PathBuf::from)
        .or_else(|| cluster::programs(None))
        .expect(
            "the database tests need PostgreSQL 16 or newer: install its server and client programs (initdb, \
             pg_ctl, pg_dump, pg_restore, psql) or set TEST_PG_BIN to the directory that holds them",
        )
}

fn run(command: &mut Command) {
    let output = output(command, Duration::from_secs(120));
    assert!(
        output.status.success(),
        "{command:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

/// The programs of PostgreSQL `major`, which `tools/postgres.sh` fetches once (the major-upgrade test's).
pub fn bin_of(major: u32) -> PathBuf {
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../tools/postgres.sh");
    let output = output(
        tool("bash").arg(&script).arg(major.to_string()),
        Duration::from_secs(600),
    );
    assert!(
        output.status.success(),
        "{} {major} failed: {}",
        script.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    PathBuf::from(String::from_utf8(output.stdout).unwrap().trim())
}

fn start(bin: &Path) -> Cluster {
    let dir = tempfile::Builder::new()
        .prefix("photolib-pg-")
        .tempdir()
        .expect("a temporary directory")
        .keep();
    let data = dir.join("data");
    run(tool(bin.join("initdb"))
        .args([
            "-U",
            "postgres",
            "-A",
            "trust",
            "-E",
            "UTF8",
            "--no-sync",
            "--locale=C",
            "-D",
        ])
        .arg(&data));
    let log = std::fs::File::create(dir.join("log")).unwrap();
    // SIGQUIT: an immediate shutdown, which needs no client to leave.
    let mut postgres = photolib_spawn::command(bin.join("postgres"), Signal::SIGQUIT);
    postgres.arg("-D").arg(&data).arg("-k").arg(&dir);
    // wal_level=minimal: no standby snapshots, so an idle cluster writes no WAL at all (photolib-jobs' tests/idle.rs).
    for option in [
        "listen_addresses=",
        "fsync=off",
        "full_page_writes=off",
        "max_connections=200",
        "wal_level=minimal",
        "max_wal_senders=0",
    ] {
        postgres.args(["-c", option]);
    }
    postgres
        .stdin(Stdio::null())
        .stdout(log.try_clone().unwrap())
        .stderr(log);
    let mut postgres = Group::start(postgres, Signal::SIGQUIT);
    let (pid, started) = (postgres.id(), Running::start());
    let exited = || postgres.try_wait().unwrap().is_some();
    cluster::wait_ready(&data, pid, &dir.join("log"), exited, || started.elapsed())
        .unwrap_or_else(|error| panic!("{error}"));
    // The watchdog runs in the background of a shell that exits at once, so it outlives this call.
    let status = Command::new("sh")
        .args([
            "-c",
            "(while kill -0 \"$1\" || kill -0 \"$2\"; do sleep 1; done; rm -rf \"$0\") </dev/null >/dev/null 2>&1 &",
        ])
        .arg(&dir)
        .arg(std::process::id().to_string())
        .arg(postgres.id().to_string())
        .status();
    assert!(status.unwrap().success());
    Cluster {
        socket: dir,
        _postgres: postgres,
    }
}

/// A fresh, empty database on the shared cluster; the superuser `postgres` owns it.
pub struct TestDb {
    pub url: String,
    pub pool: PgPool,
}

pub async fn database() -> TestDb {
    database_on(&bin_dir()).await
}

/// A fresh, empty database on the cluster of the PostgreSQL programs in `bin`.
pub async fn database_on(bin: &Path) -> TestDb {
    let cluster = *(CLUSTERS.lock().unwrap_or_else(std::sync::PoisonError::into_inner))
        .entry(bin.to_path_buf())
        .or_insert_with(|| Box::leak(Box::new(start(bin))));
    let url = |name: &str| format!("postgres://postgres@localhost/{name}?host={}", cluster.socket.display());
    let name = format!("test_{}", NEXT.fetch_add(1, Ordering::SeqCst));
    let mut admin = PgConnection::connect(&url("postgres")).await.unwrap();
    sqlx::raw_sql(&format!("CREATE DATABASE {name}"))
        .execute(&mut admin)
        .await
        .unwrap();
    let url = url(&name);
    let pool = PgPool::connect(&url).await.unwrap();
    TestDb { url, pool }
}

/// Waits until every transaction that started before this call has ended, so that sync readers reach what it wrote:
/// tests share the cluster, and the transactions of the others hold the watermark back too.
pub async fn settle(pool: &PgPool) {
    let now: String = sqlx::query_scalar("SELECT pg_current_xact_id()::text")
        .fetch_one(pool)
        .await
        .unwrap();
    let started = Running::start();
    while crate::sync::watermark(pool).await.unwrap().0 <= now.parse::<u64>().unwrap() {
        assert!(started.elapsed().as_secs() < 30, "a transaction holds the watermark");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}
