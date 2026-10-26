//! Test helpers for this and other crates: staged files and a throwaway Garage, one per test process, started on
//! first use, stopped when the process exits and then removed by a watchdog. `TEST_GARAGE` names its binary;
//! otherwise `tools/garage.sh` fetches the pinned release.

use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        OnceLock,
        atomic::{AtomicU32, Ordering},
    },
    time::Duration,
};

use photolib_spawn::{Group, Running, Signal, free_port, on_fresh_ports, output, port_taken, tool};

use crate::{Hash, s3::S3Config, s3::S3Store};

static NEXT: AtomicU32 = AtomicU32::new(0);

/// Writes `bytes` to a new file in `dir`, as an upload would be staged, and returns it with its hash.
pub fn staged(dir: &Path, bytes: &[u8]) -> (PathBuf, Hash) {
    let path = dir.join(format!("staged-{}", NEXT.fetch_add(1, Ordering::SeqCst)));
    std::fs::write(&path, bytes).unwrap();
    (path, Hash::of(bytes))
}

/// The Garage of this test process; each config it hands out has a prefix of its own.
pub fn garage() -> S3Config {
    static GARAGE: OnceLock<(S3Config, Group)> = OnceLock::new();
    let mut config = GARAGE.get_or_init(start).0.clone();
    config.prefix = format!("t{}-{}/", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst));
    config
}

/// A store on a fresh prefix of the test Garage, writing in 5 MiB parts.
pub fn garage_store(timeout: Duration) -> S3Store {
    S3Store::open(&garage(), timeout).unwrap().part_size(5 << 20)
}

fn binary() -> PathBuf {
    if let Some(path) = std::env::var_os("TEST_GARAGE") {
        return path.into();
    }
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../tools/garage.sh");
    // It fetches Garage when it is missing.
    let output = output(tool("bash").arg(&script), Duration::from_secs(600));
    assert!(
        output.status.success(),
        "the storage tests need Garage: {} failed: {}",
        script.display(),
        String::from_utf8_lossy(&output.stderr)
    );
    PathBuf::from(String::from_utf8(output.stdout).unwrap().trim())
}

fn random_hex(len: usize) -> String {
    let seed = format!("{:?}{}", std::time::SystemTime::now(), std::process::id());
    let hex = Hash::of(seed.as_bytes()).to_string() + &Hash::of(&[seed.as_bytes(), b"2"].concat()).to_string();
    hex[..len].to_string()
}

fn start() -> (S3Config, Group) {
    on_fresh_ports(try_start)
}

fn try_start() -> Result<(S3Config, Group), String> {
    let dir = tempfile::Builder::new()
        .prefix("photolib-garage-")
        .tempdir()
        .unwrap()
        .keep();
    let held = (free_port(), free_port());
    let (s3, rpc) = (held.0.number, held.1.number);
    let config = dir.join("garage.toml");
    std::fs::write(
        &config,
        format!(
            "metadata_dir = \"{dir}/meta\"\ndata_dir = \"{dir}/data\"\ndb_engine = \"sqlite\"\nreplication_factor = 1\n\
             rpc_bind_addr = \"127.0.0.1:{rpc}\"\nrpc_public_addr = \"127.0.0.1:{rpc}\"\nrpc_secret = \"{secret}\"\n\
             [s3_api]\ns3_region = \"garage\"\napi_bind_addr = \"127.0.0.1:{s3}\"\n",
            dir = dir.display(),
            secret = random_hex(64),
        ),
    )
    .unwrap();
    let s3_config = S3Config {
        endpoint: format!("http://127.0.0.1:{s3}"),
        bucket: "photolib-test".into(),
        region: "garage".into(),
        prefix: String::new(),
        access_key_id: format!("GK{}", random_hex(24)),
        secret_access_key: random_hex(64),
    };
    let log = std::fs::File::create(dir.join("log")).unwrap();
    let mut garage = photolib_spawn::command(binary(), Signal::SIGTERM);
    garage
        .arg("-c")
        .arg(&config)
        .args(["server", "--single-node", "--default-bucket"])
        .env("GARAGE_DEFAULT_ACCESS_KEY", &s3_config.access_key_id)
        .env("GARAGE_DEFAULT_SECRET_KEY", &s3_config.secret_access_key)
        .env("GARAGE_DEFAULT_BUCKET", &s3_config.bucket)
        .stdin(Stdio::null())
        .stdout(log.try_clone().unwrap())
        .stderr(log);
    let mut garage = Group::start(garage, Signal::SIGTERM);
    // The watchdog runs in the background of a shell that exits at once, so it outlives this call.
    let status = Command::new("sh")
        .args([
            "-c",
            "(while kill -0 \"$1\" || kill -0 \"$2\"; do sleep 1; done; rm -rf \"$0\") </dev/null >/dev/null 2>&1 &",
        ])
        .arg(&dir)
        .arg(std::process::id().to_string())
        .arg(garage.id().to_string())
        .status()
        .unwrap();
    assert!(status.success());
    // Not up while another process holds a port: Garage keeps running when it cannot bind the S3 API's.
    let started = Running::start();
    while !(garage.listens(s3)? && garage.listens(rpc)?) {
        let log = std::fs::read_to_string(dir.join("log")).unwrap_or_default();
        let exited = garage.try_wait().unwrap();
        if exited.is_some() || port_taken(&log) || started.elapsed() > Duration::from_secs(30) {
            return Err(format!("Garage did not listen ({exited:?}): {log}"));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Ok((s3_config, garage))
}
