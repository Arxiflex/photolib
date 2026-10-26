//! `photolibd doctor` (OPS-19, ADR-0063): checks an installation — configuration, PostgreSQL, filesystems, markers,
//! stores, proxy headers and client versions — and makes the diagnostics bundle for bug reports. The running server
//! answers it on `/diagnostics` beside `/metrics`, so the checks include what only it sees: the API's requests.

use std::{
    net::{Ipv4Addr, Ipv6Addr, SocketAddr},
    path::Path,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime},
};

use axum::{
    Json,
    extract::{Request, State},
    middleware::Next,
    response::Response,
};
use figment::providers::Format;
use photolib_storage::{BlobStore, fs::FsStore, marker};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sqlx::{PgPool, postgres::PgPoolOptions};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use uuid::Uuid;

use crate::{
    config::{CONFIG_VERSION, Config},
    instance,
    logging::Tail,
    mounts,
    proxy::Forwarding,
    rpc, storage,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Ok,
    Warn,
    Fail,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Check {
    pub name: String,
    pub status: Status,
    pub detail: String,
}

/// A check that fails if anything in `failures`, warns if anything in `warnings`, and else says `fine`.
pub(crate) fn verdict(name: impl Into<String>, fine: String, warnings: Vec<String>, failures: Vec<String>) -> Check {
    let (status, detail) = match (failures.is_empty(), warnings.is_empty()) {
        (false, _) => (Status::Fail, [failures, warnings].concat().join("; ")),
        (true, false) => (Status::Warn, warnings.join("; ")),
        (true, true) => (Status::Ok, fine),
    };
    Check {
        name: name.into(),
        status,
        detail,
    }
}

fn fail(name: impl Into<String>, why: impl Into<String>) -> Check {
    verdict(name, String::new(), vec![], vec![why.into()])
}

/// What the API saw of its requests, for the proxy check.
#[derive(Clone, Default)]
pub struct Seen(Arc<Mutex<Option<Forwarding>>>);

impl Seen {
    pub fn last(&self) -> Option<Forwarding> {
        self.0.lock().unwrap().clone()
    }
}

/// Records how each API request was forwarded, as `proxy::guard` found.
pub async fn observe(State(seen): State<Seen>, request: Request, next: Next) -> Response {
    if let Some(forwarding) = request.extensions().get::<Forwarding>() {
        *seen.0.lock().unwrap() = Some(forwarding.clone());
    }
    next.run(request).await
}

pub fn proxy(seen: Option<&Forwarding>) -> Check {
    let (mut warnings, fine) = (vec![], "requests arrive through a reverse proxy over HTTPS".to_string());
    match seen {
        None => warnings.push("no API request seen yet: use the app, then run doctor again".into()),
        Some(f) if !f.trusted && (f.forwarded_for || f.proto.is_some()) => {
            let peer = f.peer.map_or("an unknown address".into(), |peer| peer.to_string());
            warnings.push(format!(
                "requests from {peer} carry forwarded headers, but {peer} is not in trusted_proxies: they are ignored"
            ))
        }
        Some(f) if !f.forwarded_for && f.proto.is_none() => {
            if !f.peer.is_some_and(|peer| peer.is_loopback()) {
                warnings.push(format!(
                    "requests from {} reach photolibd directly over plain HTTP: put a TLS-terminating reverse proxy \
                     in front of it",
                    f.peer.map_or("the network".into(), |peer| peer.to_string())
                ));
            }
        }
        Some(f) if f.proto.as_deref() != Some("https") => warnings.push(format!(
            "the proxy forwards requests as {}: it must set X-Forwarded-Proto: https",
            f.proto
                .as_deref()
                .unwrap_or("an unknown protocol (no X-Forwarded-Proto)")
        )),
        Some(f) if !f.forwarded_for => {
            warnings.push("the proxy sets no X-Forwarded-For: clients' addresses are lost".into())
        }
        Some(_) => {}
    }
    let fine = match seen {
        Some(f) if !f.forwarded_for && f.proto.is_none() => "requests come from this machine".into(),
        _ => fine,
    };
    verdict("proxy", fine, warnings, vec![])
}

/// PostgreSQL's version and the settings that decide whether a crash or bit-rot goes unnoticed.
pub struct PgSettings {
    pub version_num: i32,
    pub data_checksums: String,
    pub fsync: String,
    pub full_page_writes: String,
    pub synchronous_commit: String,
}

pub fn postgres(s: &PgSettings) -> Check {
    let (mut warnings, mut failures) = (vec![], vec![]);
    if s.version_num < 160000 {
        failures.push(format!("PostgreSQL {} is older than 16", s.version_num / 10000));
    }
    if s.fsync != "on" {
        failures.push("fsync is off: a crash can corrupt the database".into());
    }
    if s.data_checksums != "on" {
        warnings.push(
            "data checksums are off, so corrupt pages go unnoticed: stop PostgreSQL and run pg_checksums --enable"
                .into(),
        );
    }
    if s.full_page_writes != "on" {
        warnings.push("full_page_writes is off: a crash can leave torn pages".into());
    }
    if s.synchronous_commit == "off" {
        warnings.push("synchronous_commit is off: a crash loses the last commits".into());
    }
    let fine = format!("PostgreSQL {}, data checksums on, fsync on", s.version_num / 10000);
    verdict("postgres", fine, warnings, failures)
}

/// The filesystem of a directory: network and FUSE filesystems cannot hold state, and barriers must stay on.
pub fn filesystem(name: &str, dir: &Path, mountinfo: Option<&str>, allow_network: bool) -> Check {
    let check = format!("filesystem {name}");
    let Some(mount) = mountinfo.and_then(|text| mounts::mount_of(text, dir)) else {
        let why = "the mount table is unreadable".to_string();
        return verdict(check, String::new(), vec![why], vec![]);
    };
    let found = format!("{} is on {} at {}", dir.display(), mount.fstype, mount.point.display());
    let (mut warnings, mut failures) = (vec![], vec![]);
    if mount.is_unsafe_for_state() {
        let why = format!("{found}: locking and fsync cannot be trusted there");
        match name == "data_dir" || allow_network {
            true => warnings.push(why),
            false => failures.push(why),
        }
    }
    let off = mount
        .options
        .split(',')
        .filter(|option| matches!(*option, "nobarrier" | "barrier=0" | "data=writeback"));
    for option in off {
        warnings.push(format!("{found}: {option} lets a power loss corrupt recent writes"));
    }
    verdict(check, found, warnings, failures)
}

/// Versions of the apps that synced in the last 30 days, against the oldest this server serves.
pub fn clients(versions: &[String]) -> Check {
    let parse = |v: &str| -> Option<Vec<u32>> { v.split('.').map(|n| n.parse().ok()).collect() };
    let oldest = parse(rpc::MIN_CLIENT_VERSION).unwrap_or_default();
    let too_old: Vec<&str> = versions
        .iter()
        .filter(|v| parse(v).is_none_or(|v| v < oldest))
        .map(String::as_str)
        .collect();
    let warnings = match too_old.is_empty() {
        true => vec![],
        false => vec![format!(
            "apps {} are older than {}, the oldest this server serves: update them",
            too_old.join(", "),
            rpc::MIN_CLIENT_VERSION
        )],
    };
    let fine = match versions.is_empty() {
        true => "no app synced in the last 30 days".into(),
        false => format!("apps {} are served", versions.join(", ")),
    };
    verdict("clients", fine, warnings, vec![])
}

/// Signed object-store requests fail beyond 15 minutes of skew (ADR-0022); a minute already distorts timestamps.
pub fn skew(store: &str, theirs: SystemTime, ours: SystemTime) -> Option<(bool, String)> {
    let (ahead, by) = match theirs.duration_since(ours) {
        Ok(by) => ("ahead of", by),
        Err(behind) => ("behind", behind.duration()),
    };
    (by > Duration::from_secs(60)).then(|| {
        let why = format!("the clock of {store} is {}s {ahead} this server's", by.as_secs());
        (by > Duration::from_secs(15 * 60), why)
    })
}

/// The installation `photolibd doctor` checks, and what the running server adds: its requests and its log.
pub struct Doctor {
    pub config: Config,
    pub pool: Option<PgPool>,
    pub seen: Option<Seen>,
    pub tail: Option<Tail>,
    /// The self-tests of the ML nodes this process knows.
    pub ml: Option<Arc<crate::ml::Ml>>,
}

impl Doctor {
    pub async fn checks(&self) -> Vec<Check> {
        let config = &self.config;
        let mountinfo = mounts::current_mountinfo();
        let fine = format!("valid, config_version {CONFIG_VERSION}");
        let mut checks = vec![verdict("config", fine, vec![], vec![])];
        let data_dir = config.data_dir.clone().map(|dir| ("data_dir", dir));
        for (name, dir) in data_dir.into_iter().chain(config.state_dirs()) {
            checks.push(filesystem(name, &dir, mountinfo.as_deref(), config.allow_network_fs));
        }
        checks.extend(self.ml.as_ref().map(|ml| ml.check(SystemTime::now())));
        if !config.roles.iter().any(|role| role.needs_instance()) {
            return checks;
        }
        let settings = match &self.pool {
            Some(pool) => pg_settings(pool).await.map_err(|error| error.to_string()),
            None => Err("database.url is not set".into()),
        };
        let (Some(pool), Ok(settings)) = (&self.pool, settings.as_ref()) else {
            checks.push(fail("postgres", settings.err().unwrap_or_default()));
            checks.push(self.proxy());
            return checks;
        };
        checks.push(postgres(settings));
        let drift = photolib_db::doctor::drift(pool, &photolib_db::migrate::embedded()).await;
        checks.push(match drift {
            Ok(drift) if drift.is_empty() => verdict("schema", "no drift".into(), vec![], vec![]),
            Ok(drift) => verdict("schema", String::new(), drift, vec![]),
            Err(error) => fail("schema", error.to_string()),
        });
        checks.push(self.instance_marker(pool).await);
        checks.extend(self.stores().await.into_iter().map(|(check, _)| check));
        let versions = sqlx::query_scalar(
            "SELECT DISTINCT app_version FROM devices WHERE app_version IS NOT NULL
               AND last_seen_at > now() - interval '30 days' ORDER BY 1",
        )
        .fetch_all(pool)
        .await;
        checks.push(match versions {
            Ok(versions) => clients(&versions),
            Err(error) => fail("clients", error.to_string()),
        });
        checks.push(self.proxy());
        checks
    }

    fn proxy(&self) -> Check {
        match &self.seen {
            Some(seen) => proxy(seen.last().as_ref()),
            None => {
                let why =
                    "only the running photolibd sees how requests arrive, and none answers on listen to metrics.token";
                verdict("proxy", String::new(), vec![why.into()], vec![])
            }
        }
    }

    async fn instance_marker(&self, pool: &PgPool) -> Check {
        let Some(data_dir) = &self.config.data_dir else {
            return fail("instance marker", "data_dir is not set");
        };
        let ids = (instance::read_marker(data_dir), instance_id(pool).await);
        let failure = match ids {
            (Ok(Some(disk)), Ok(Some(db))) if disk == db => {
                return verdict("instance marker", format!("instance {disk}"), vec![], vec![]);
            }
            (Ok(disk), Ok(db)) => format!(
                "the data directory says instance {disk:?} and the database {db:?}: they do not belong together"
            ),
            (Err(error), _) => error,
            (_, Err(error)) => error.to_string(),
        };
        fail("instance marker", failure)
    }

    /// Every store checked now — reachable, credentials and clock, marker — with its free space where known.
    pub async fn stores(&self) -> Vec<(Check, Option<u64>)> {
        let (Some(pool), Some(data_dir)) = (&self.pool, &self.config.data_dir) else {
            return vec![];
        };
        let instance = match instance_id(pool).await {
            Ok(Some(id)) => id,
            _ => Uuid::nil(),
        };
        let mut out = vec![];
        let local = FsStore::open(data_dir, storage::LOCAL_TIMEOUT).await;
        let free = storage::space(data_dir).ok().map(|(_, free)| free);
        let check = match local {
            Ok(store) => store_marker(pool, instance, "local", &store, vec![], vec![]).await,
            Err(error) => fail("store local", error.to_string()),
        };
        out.push((check, free));
        for (name, config) in &self.config.stores {
            let check = match storage::s3(config) {
                Ok(store) => match store.clock().await {
                    Ok(theirs) => {
                        let (warnings, failures) = match skew(name, theirs, SystemTime::now()) {
                            Some((true, why)) => (vec![], vec![why]),
                            Some((false, why)) => (vec![why], vec![]),
                            None => (vec![], vec![]),
                        };
                        store_marker(pool, instance, name, &store, warnings, failures).await
                    }
                    Err(error) => fail(
                        format!("store {name}"),
                        format!("unreachable or the credentials are wrong: {error}"),
                    ),
                },
                Err(error) => fail(format!("store {name}"), error),
            };
            out.push((check, None));
        }
        out
    }

    /// The bundle to attach to a bug report: versions, the configuration's differences from the defaults (secrets
    /// hidden), the checks and the log tail.
    pub fn bundle(&self, checks: &[Check]) -> Value {
        json!({
            "photolibd": env!("CARGO_PKG_VERSION"),
            "api_version": rpc::API_VERSION,
            "min_client_version": rpc::MIN_CLIENT_VERSION,
            "generated_at": httpdate::fmt_http_date(SystemTime::now()),
            "config": config_diff(&self.config),
            "checks": checks,
            "log": self.tail.as_ref().map(|tail| tail.lines(Tail::LINES)).unwrap_or_default(),
        })
    }
}

async fn instance_id(pool: &PgPool) -> sqlx::Result<Option<Uuid>> {
    sqlx::query_scalar("SELECT instance_id FROM photolib_instance")
        .fetch_optional(pool)
        .await
}

async fn pg_settings(pool: &PgPool) -> sqlx::Result<PgSettings> {
    let (version_num, data_checksums, fsync, full_page_writes, synchronous_commit) = sqlx::query_as(
        "SELECT current_setting('server_version_num')::int, current_setting('data_checksums'),
           current_setting('fsync'), current_setting('full_page_writes'), current_setting('synchronous_commit')",
    )
    .fetch_one(pool)
    .await?;
    Ok(PgSettings {
        version_num,
        data_checksums,
        fsync,
        full_page_writes,
        synchronous_commit,
    })
}

async fn store_marker(
    pool: &PgPool,
    instance: Uuid,
    name: &str,
    store: &dyn BlobStore,
    warnings: Vec<String>,
    mut failures: Vec<String>,
) -> Check {
    let fine = match marker::verify(pool, instance, name, store).await {
        Ok(id) => format!("online, store {id}"),
        Err(error) => {
            failures.push(error.to_string());
            String::new()
        }
    };
    verdict(format!("store {name}"), fine, warnings, failures)
}

/// The settings that differ from a configuration with nothing set, by dotted path; secrets read `[redacted]`.
pub fn config_diff(config: &Config) -> Value {
    let defaults = figment::Figment::from(serde_saphyr::figment::Yaml::string("config_version: 1"))
        .extract::<Config>()
        .map(|defaults| serde_json::to_value(defaults).unwrap_or_default())
        .unwrap_or_default();
    let mut diff = serde_json::Map::new();
    fn walk(path: String, value: &Value, default: &Value, diff: &mut serde_json::Map<String, Value>) {
        match (value, default) {
            (Value::Object(map), _) => {
                for (key, value) in map {
                    let path = if path.is_empty() {
                        key.clone()
                    } else {
                        format!("{path}.{key}")
                    };
                    walk(path, value, default.get(key).unwrap_or(&Value::Null), diff);
                }
            }
            _ if value != default => drop(diff.insert(path, value.clone())),
            _ => {}
        }
    }
    walk(
        String::new(),
        &serde_json::to_value(config).unwrap_or_default(),
        &defaults,
        &mut diff,
    );
    Value::Object(diff)
}

/// `/diagnostics` beside `/metrics`: the checks and the bundle, which `photolibd doctor` reads.
pub async fn diagnostics(State(doctor): State<Arc<Doctor>>) -> Json<Value> {
    let checks = doctor.checks().await;
    Json(json!({ "checks": checks, "bundle": doctor.bundle(&checks) }))
}

/// The running photolibd's answer on `/diagnostics`, if one answers on `listen` to `metrics.token`.
async fn fetch(config: &Config) -> Option<Value> {
    let token = config.metrics.token.as_ref()?;
    let mut addr = config.listen;
    if addr.ip().is_unspecified() {
        addr.set_ip(match addr {
            SocketAddr::V4(_) => Ipv4Addr::LOCALHOST.into(),
            SocketAddr::V6(_) => Ipv6Addr::LOCALHOST.into(),
        });
    }
    let base = config.base_path.trim_end_matches('/');
    let exchange = async {
        let mut stream = tokio::net::TcpStream::connect(addr).await.ok()?;
        let request = format!(
            "GET {base}/diagnostics HTTP/1.1\r\nHost: {addr}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n\r\n",
            token.expose()
        );
        stream.write_all(request.as_bytes()).await.ok()?;
        let mut text = String::new();
        stream.read_to_string(&mut text).await.ok()?;
        let (head, body) = text.split_once("\r\n\r\n")?;
        head.starts_with("HTTP/1.1 200")
            .then(|| serde_json::from_str(body).ok())?
    };
    tokio::time::timeout(Duration::from_secs(120), exchange).await.ok()?
}

/// `photolibd doctor`: the running photolibd's checks, or this process's own without what only a server sees;
/// prints them and writes the bundle to `bundle`. True when none failed.
pub async fn cli(config: Config, bundle: Option<&Path>) -> Result<bool, String> {
    let report = match fetch(&config).await {
        Some(report) => report,
        None => {
            let pool = config.database.url.as_ref().map(|url| {
                PgPoolOptions::new()
                    .acquire_timeout(Duration::from_secs(5))
                    .connect_lazy(url.expose())
            });
            let pool = pool.transpose().map_err(|error| format!("database.url: {error}"))?;
            let doctor = Doctor {
                config,
                pool,
                seen: None,
                tail: None,
                ml: None,
            };
            let checks = doctor.checks().await;
            json!({ "checks": checks, "bundle": doctor.bundle(&checks) })
        }
    };
    let checks: Vec<Check> = serde_json::from_value(report["checks"].clone())
        .map_err(|error| format!("photolibd answered /diagnostics with {error}"))?;
    for check in &checks {
        let status = format!("{:?}", check.status).to_lowercase();
        println!("{status:<4} {}: {}", check.name, check.detail);
    }
    if let Some(path) = bundle {
        let text = serde_json::to_string_pretty(&report["bundle"]).unwrap_or_default();
        std::fs::write(path, text).map_err(|error| format!("cannot write {}: {error}", path.display()))?;
    }
    Ok(checks.iter().all(|check| check.status != Status::Fail))
}

#[cfg(test)]
mod tests {

    use super::*;
    use crate::{role::Role, testing::config};

    fn settings(fsync: &str, checksums: &str, version_num: i32) -> PgSettings {
        PgSettings {
            version_num,
            data_checksums: checksums.into(),
            fsync: fsync.into(),
            full_page_writes: "on".into(),
            synchronous_commit: "on".into(),
        }
    }

    #[test]
    fn postgres_needs_16_and_fsync_and_should_have_data_checksums() {
        let ok = postgres(&settings("on", "on", 170004));
        assert_eq!(
            (ok.status, ok.detail.as_str()),
            (Status::Ok, "PostgreSQL 17, data checksums on, fsync on")
        );
        let off = postgres(&settings("on", "off", 180000));
        assert_eq!(off.status, Status::Warn);
        assert!(off.detail.contains("pg_checksums --enable"), "{}", off.detail);
        let old = postgres(&settings("off", "on", 150008));
        assert_eq!(old.status, Status::Fail);
        assert!(old.detail.contains("PostgreSQL 15 is older than 16") && old.detail.contains("fsync is off"));
    }

    const MOUNTS: &str = "\
22 1 8:1 / / rw,relatime - ext4 /dev/sda1 rw,errors=remount-ro
23 22 8:2 / /fast rw,relatime - ext4 /dev/sda2 rw,nobarrier,data=writeback
24 22 0:40 / /nas rw,relatime - nfs4 nas:/export rw,vers=4.2
";

    #[test]
    fn filesystems_must_keep_state_safe() {
        let check = |name, dir: &str, allow| filesystem(name, Path::new(dir), Some(MOUNTS), allow);
        let local = check("work_dir", "/srv/tmp", false);
        assert_eq!(
            (local.status, local.detail.as_str()),
            (Status::Ok, "/srv/tmp is on ext4 at /")
        );
        let fast = check("database.data_dir", "/fast/pg", false);
        assert_eq!(fast.status, Status::Warn);
        assert!(
            fast.detail.contains("nobarrier") && fast.detail.contains("data=writeback"),
            "{}",
            fast.detail
        );
        assert_eq!(check("work_dir", "/nas/tmp", false).status, Status::Fail);
        assert_eq!(
            check("work_dir", "/nas/tmp", true).status,
            Status::Warn,
            "allow_network_fs"
        );
        assert_eq!(
            check("data_dir", "/nas/photolib", false).status,
            Status::Warn,
            "libraries may be on a NAS"
        );
        assert_eq!(
            filesystem("data_dir", Path::new("/x"), None, false).status,
            Status::Warn
        );
    }

    /// The proxy check after a request from `peer`, which `trusted_proxies` lists unless it is in 198.51.100.0/24.
    fn seen(peer: &str, forwarded_for: bool, proto: Option<&str>) -> Check {
        proxy(Some(&Forwarding {
            peer: Some(peer.parse().unwrap()),
            trusted: !peer.starts_with("198.51.100."),
            forwarded_for,
            proto: proto.map(str::to_string),
            client: None,
        }))
    }

    #[test]
    fn the_proxy_must_forward_https_and_the_client_address() {
        assert_eq!(seen("172.18.0.2", true, Some("https")).status, Status::Ok);
        let http = seen("172.18.0.2", true, Some("http"));
        assert!(http.status == Status::Warn && http.detail.contains("X-Forwarded-Proto: https"));
        let no_for = seen("172.18.0.2", false, Some("https"));
        assert!(no_for.status == Status::Warn && no_for.detail.contains("X-Forwarded-For"));
        let direct = seen("198.51.100.7", false, None);
        assert!(
            direct.status == Status::Warn && direct.detail.contains("198.51.100.7"),
            "{}",
            direct.detail
        );
        let untrusted = seen("198.51.100.7", true, Some("https"));
        assert!(
            untrusted.status == Status::Warn
                && untrusted.detail.contains("198.51.100.7")
                && untrusted.detail.contains("trusted_proxies"),
            "{}",
            untrusted.detail
        );
        assert_eq!(seen("127.0.0.1", false, None).status, Status::Ok);
        assert_eq!(proxy(None).status, Status::Warn);
    }

    #[test]
    fn clients_older_than_the_oldest_served_version_are_named() {
        assert_eq!(clients(&[]).status, Status::Ok);
        assert_eq!(clients(&["0.1.0".into(), "1.2.3".into()]).status, Status::Ok);
        let odd = clients(&["1.0".into(), "beta".into()]);
        assert!(
            odd.status == Status::Warn && odd.detail.contains("beta"),
            "{}",
            odd.detail
        );
    }

    #[test]
    fn a_store_clock_a_minute_off_warns_and_fifteen_minutes_off_fails() {
        let now = SystemTime::now();
        let minutes = |m: u64| Duration::from_secs(m * 60);
        assert_eq!(skew("b2", now + Duration::from_secs(30), now), None);
        let (fails, why) = skew("b2", now - minutes(2), now).unwrap();
        assert!(!fails && why == "the clock of b2 is 120s behind this server's", "{why}");
        assert!(skew("b2", now + minutes(16), now).unwrap().0);
    }

    #[test]
    fn the_config_diff_names_what_differs_from_the_defaults_and_hides_secrets() {
        let dir = Path::new("/srv/photolib");
        let diff = config_diff(&config(&[Role::Api], dir));
        assert_eq!(diff["data_dir"], "/srv/photolib");
        assert_eq!(diff["roles"], json!(["api"]));
        assert_eq!(diff["database.url"], "[redacted]");
        assert!(diff.get("log.filter").is_none(), "a default is not listed: {diff}");
    }

    #[tokio::test]
    async fn stores_are_checked_for_their_credentials_and_marker() {
        let db = photolib_db::testpg::database().await;
        let pool = db.pool.clone();
        let migrations = photolib_db::migrate::embedded();
        let upgrade = photolib_db::migrate::Upgrade::new(&migrations);
        photolib_db::migrate::upgrade(&pool, &upgrade).await.unwrap();
        let data = tempfile::tempdir().unwrap();
        let mut config = config(&[Role::Api], data.path());
        let s3 = photolib_storage::testing::garage();
        config.stores.insert("b2".into(), crate::testing::store(&s3));
        let instance = Uuid::now_v7();
        sqlx::query("INSERT INTO photolib_instance (instance_id) VALUES ($1::uuid)")
            .bind(instance.to_string())
            .execute(&pool)
            .await
            .unwrap();
        storage::start(&config, &pool, instance).await.unwrap();
        let wrong = photolib_storage::s3::S3Config {
            secret_access_key: "wrong".into(),
            ..s3
        };
        config.stores.insert("wrong".into(), crate::testing::store(&wrong));
        let doctor = Doctor {
            config,
            pool: Some(pool),
            seen: None,
            tail: None,
            ml: None,
        };
        let stores = doctor.stores().await;
        let found: Vec<(&str, Status, bool)> = stores
            .iter()
            .map(|(c, free)| (c.name.as_str(), c.status, free.is_some()))
            .collect();
        assert_eq!(
            found,
            [
                ("store local", Status::Ok, true),
                ("store b2", Status::Ok, false),
                ("store wrong", Status::Fail, false)
            ]
        );
        assert!(
            stores[2].0.detail.contains("credentials are wrong"),
            "{}",
            stores[2].0.detail
        );
    }

    #[tokio::test]
    async fn a_remote_ml_node_checks_what_it_has_never_a_database_or_a_proxy() {
        let mut config = config(&[Role::Ml], Path::new("/unused"));
        (config.data_dir, config.database.url) = (None, None);
        let doctor = Doctor {
            config,
            pool: None,
            seen: None,
            tail: None,
            ml: Some(Arc::default()),
        };
        let checks = doctor.checks().await;
        let names: Vec<&str> = checks.iter().map(|check| check.name.as_str()).collect();
        assert_eq!(names, ["config", "ml"], "{checks:?}");
    }
}
