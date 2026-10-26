//! The PostgreSQL cluster photolibd runs itself (`database.cluster`), and where PostgreSQL's programs are, for it and
//! the tests' cluster.

use std::{
    fs::OpenOptions,
    io::ErrorKind,
    os::unix::{ffi::OsStrExt, process::CommandExt},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    time::{Duration, Instant},
};

use nix::{
    sys::signal::{Signal, kill},
    unistd::Pid,
};
use percent_encoding::{NON_ALPHANUMERIC, percent_encode};
use sqlx::{Connection, PgConnection};

/// postgres's output, in the cluster's directory.
const LOG: &str = "postgres.log";
const POLL: Duration = Duration::from_millis(20);

/// The directory of PostgreSQL's server programs: the one on `PATH` holding `postgres`, else Debian's and Ubuntu's
/// `/usr/lib/postgresql/<major>/bin` of `major` when installed, else of the newest.
pub fn programs(major: Option<u32>) -> Option<PathBuf> {
    let path = std::env::var_os("PATH").unwrap_or_default();
    if let Some(dir) = std::env::split_paths(&path).find(|dir| dir.join("postgres").is_file()) {
        return Some(dir);
    }
    let installed = std::fs::read_dir("/usr/lib/postgresql").ok()?.filter_map(|entry| {
        let version: u32 = entry.ok()?.file_name().to_str()?.parse().ok()?;
        let bin = PathBuf::from(format!("/usr/lib/postgresql/{version}/bin"));
        bin.join("postgres")
            .is_file()
            .then_some((Some(version) == major, version, bin))
    });
    installed.max().map(|(.., bin)| bin)
}

/// Waits until postmaster `pid` says in `<data>/postmaster.pid` that it is ready, as `pg_ctl -w` does, for at most a
/// minute of `elapsed` time; `exited` says whether it ended meanwhile. The error ends with the last lines of `log`.
pub fn wait_ready(
    data: &Path,
    pid: u32,
    log: &Path,
    mut exited: impl FnMut() -> bool,
    elapsed: impl Fn() -> Duration,
) -> Result<(), String> {
    let ready = || {
        let status = std::fs::read_to_string(data.join("postmaster.pid")).unwrap_or_default();
        let lines: Vec<&str> = status.lines().map(str::trim).collect();
        lines.first() == Some(&pid.to_string().as_str()) && lines.get(7) == Some(&"ready")
    };
    while !ready() {
        let ended = exited();
        if ended || elapsed() > Duration::from_secs(60) {
            let why = if ended {
                "exited"
            } else {
                "was not ready within a minute"
            };
            let log = std::fs::read_to_string(log).unwrap_or_default();
            let tail: Vec<&str> = log.lines().skip(log.lines().count().saturating_sub(20)).collect();
            return Err(format!("postgres {why}: {}", tail.join("\n")));
        }
        std::thread::sleep(POLL);
    }
    Ok(())
}

/// A cluster photolibd runs: on drop, a fast shutdown (SIGINT), then an immediate one (SIGQUIT) after the grace.
#[derive(Debug)]
pub struct Cluster {
    /// The URL of its database `photolib`, through the socket in its directory.
    pub url: String,
    /// The directory of the programs that run it.
    pub bin: PathBuf,
    /// None when another process runs it.
    postgres: Option<Child>,
    grace: Duration,
}

/// Starts the cluster in `dir` from the programs in `bin`, else those [`programs`] finds, made with `initdb` when it
/// has no `PG_VERSION`, with the database `photolib`; blocks while they start. Only its owner can connect: the socket
/// is in the cluster's 0700 directory, and TCP is off. A cluster another process runs already is used, never stopped.
pub async fn start(dir: &Path, bin: Option<&Path>, grace: Duration) -> Result<Cluster, String> {
    let version = dir.join("PG_VERSION");
    let made = match std::fs::read_to_string(&version) {
        Ok(text) => Some(
            text.trim()
                .parse::<u32>()
                .map_err(|_| format!("{} holds no version", version.display()))?,
        ),
        Err(error) if error.kind() == ErrorKind::NotFound => None,
        Err(error) => return Err(format!("cannot read {}: {error}", version.display())),
    };
    let bin = match bin {
        Some(bin) => bin.to_path_buf(),
        None => programs(made).ok_or(
            "no PostgreSQL server programs on PATH or in /usr/lib/postgresql: install PostgreSQL's server, or set \
             database.bin_dir",
        )?,
    };
    let major = major(&bin)?;
    if let Some(made) = made
        && made != major
    {
        return Err(format!(
            "the cluster at {} is PostgreSQL {made}, the programs in {} are {major}: install PostgreSQL {made}'s \
             programs (or set database.bin_dir), or upgrade the cluster with pg_upgrade",
            dir.display(),
            bin.display()
        ));
    }
    let host = percent_encode(dir.as_os_str().as_bytes(), NON_ALPHANUMERIC);
    let url = |database: &str| format!("postgres://photolib@localhost/{database}?host={host}");
    let failed = |error: sqlx::Error| format!("the database cluster at {} failed: {error}", dir.display());
    let mut cluster = Cluster {
        url: url("photolib"),
        bin,
        postgres: None,
        grace,
    };
    if PgConnection::connect(&url("postgres")).await.is_err() {
        if made.is_none() {
            run(Command::new(cluster.bin.join("initdb"))
                .args(["-U", "photolib", "-E", "UTF8", "--locale=C", "--auth-local=trust"])
                .args(["--auth-host=reject", "-D"])
                .arg(dir))?;
            tracing::info!(dir = %dir.display(), "the database cluster was created");
        }
        let postgres = cluster.postgres.insert(spawn(dir, &cluster.bin)?);
        let (pid, started) = (postgres.id(), Instant::now());
        let exited = || !matches!(postgres.try_wait(), Ok(None));
        wait_ready(dir, pid, &dir.join(LOG), exited, || started.elapsed())?;
        tracing::info!(dir = %dir.display(), "the database cluster started");
    }
    let mut admin = PgConnection::connect(&url("postgres")).await.map_err(failed)?;
    let exists = sqlx::query_scalar("SELECT EXISTS (SELECT FROM pg_database WHERE datname = 'photolib')");
    if !exists.fetch_one(&mut admin).await.map_err(failed)? {
        sqlx::raw_sql("CREATE DATABASE photolib")
            .execute(&mut admin)
            .await
            .map_err(failed)?;
    }
    Ok(cluster)
}

/// The major version of the programs in `bin`, from `postgres (PostgreSQL) 17.2 (Debian 17.2-1)`.
fn major(bin: &Path) -> Result<u32, String> {
    let said = run(Command::new(bin.join("postgres")).arg("--version"))?;
    let version = said.split_whitespace().nth(2).unwrap_or_default();
    let digits: String = version.chars().take_while(char::is_ascii_digit).collect();
    digits
        .parse()
        .map_err(|_| format!("{} --version said {said}", bin.join("postgres").display()))
}

/// What `command` printed, or why it failed.
fn run(command: &mut Command) -> Result<String, String> {
    let output = (command.output()).map_err(|error| format!("cannot run {command:?}: {error}"))?;
    if !output.status.success() {
        let said = String::from_utf8_lossy(&output.stderr);
        return Err(format!("{command:?} failed: {}", said.trim()));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn spawn(dir: &Path, bin: &Path) -> Result<Child, String> {
    let path = dir.join(LOG);
    let log = OpenOptions::new().create(true).append(true).open(&path);
    let log = log.map_err(|error| format!("cannot open {}: {error}", path.display()))?;
    let out = log
        .try_clone()
        .map_err(|error| format!("cannot open {}: {error}", path.display()))?;
    Command::new(bin.join("postgres"))
        .arg("-D")
        .arg(dir)
        .args(["-c", "listen_addresses=", "-c", "unix_socket_permissions=0700", "-k"])
        .arg(dir)
        .stdin(Stdio::null())
        .stdout(out)
        .stderr(log)
        // Not in photolibd's group: a terminal's Ctrl-C stops photolibd, which stops postgres once it has drained.
        .process_group(0)
        .spawn()
        .map_err(|error| format!("cannot run {}: {error}", bin.join("postgres").display()))
}

impl Drop for Cluster {
    fn drop(&mut self) {
        let Some(postgres) = &mut self.postgres else {
            return;
        };
        let pid = Pid::from_raw(postgres.id().cast_signed());
        kill(pid, Signal::SIGINT).ok();
        let started = Instant::now();
        while matches!(postgres.try_wait(), Ok(None)) {
            if started.elapsed() > self.grace {
                kill(pid, Signal::SIGQUIT).ok();
                postgres.wait().ok();
            }
            std::thread::sleep(POLL);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;

    use super::*;
    use crate::testpg;

    const GRACE: Duration = Duration::from_secs(10);

    #[tokio::test]
    async fn a_new_cluster_is_made_started_and_stopped_and_starts_again_with_its_data() {
        let scratch = tempfile::tempdir().unwrap();
        let (dir, bin) = (scratch.path().join("state/cluster"), testpg::bin_dir());
        let cluster = start(&dir, Some(&bin), GRACE).await.unwrap();
        let mut db = PgConnection::connect(&cluster.url).await.unwrap();
        sqlx::raw_sql("CREATE TABLE kept (x int)")
            .execute(&mut db)
            .await
            .unwrap();
        let mode = std::fs::metadata(&dir).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o700, "only its owner reaches the socket");
        drop(start(&dir, Some(&bin), GRACE).await.unwrap());
        PgConnection::connect(&cluster.url)
            .await
            .expect("a cluster another process runs is used, never stopped");
        drop(cluster);
        assert!(!dir.join("postmaster.pid").exists(), "postgres stopped");

        let again = start(&dir, Some(&bin), GRACE).await.unwrap();
        let mut db = PgConnection::connect(&again.url).await.unwrap();
        sqlx::raw_sql("SELECT x FROM kept").execute(&mut db).await.unwrap();
    }

    #[tokio::test]
    async fn a_cluster_of_another_major_is_refused_with_the_ways_out() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("PG_VERSION"), "9\n").unwrap();
        let bin = testpg::bin_dir();
        let refused = start(dir.path(), Some(&bin), GRACE).await.unwrap_err();
        let both = format!(
            "the cluster at {} is PostgreSQL 9, the programs in {} are ",
            dir.path().display(),
            bin.display()
        );
        assert!(
            refused.starts_with(&both) && refused.contains("pg_upgrade"),
            "{refused}"
        );
    }
}
