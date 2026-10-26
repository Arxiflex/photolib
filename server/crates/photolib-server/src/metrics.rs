//! `/metrics` in the OpenMetrics text format, for the bearer of `metrics.token` (ADR-0046), beside `/diagnostics`.

use std::{
    fs,
    path::PathBuf,
    sync::{Arc, atomic::AtomicU64},
    time::UNIX_EPOCH,
};

use axum::{
    Router,
    extract::{Request, State},
    http::{StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::get,
};
use prometheus_client::{
    encoding::text::{encode_eof, encode_registry},
    metrics::{family::Family, gauge::Gauge, histogram::Histogram},
    registry::{Registry, Unit},
};
use subtle::ConstantTimeEq;

use crate::{
    db::{Database, DbStats},
    doctor::Doctor,
    http::DEPENDENCY_TIMEOUT,
    secret::Secret,
};

type Labels = Vec<(&'static str, String)>;

const LATENCY_BUCKETS: [f64; 11] = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0];

/// What a scrape reads when it runs.
#[derive(Default)]
pub struct Sources {
    pub db: Option<Arc<dyn Database>>,
    /// The directories whose filesystems `photolib_storage_*` report, by setting name.
    pub dirs: Vec<(&'static str, PathBuf)>,
    /// Where the database dumps are.
    pub backups: Option<PathBuf>,
    /// The sync watermark lag, in a process whose scheduler samples it (ADR-0053).
    pub sync_lag: Option<Gauge<f64, AtomicU64>>,
    /// The ML nodes' self-tests.
    pub ml: Option<Arc<crate::ml::Ml>>,
}

/// The metrics a process keeps from start to stop, and the sources of those read when scraped.
pub struct Metrics {
    registry: Registry,
    requests: Family<Labels, Histogram, fn() -> Histogram>,
    sources: Sources,
}

impl Default for Metrics {
    fn default() -> Self {
        Metrics::new(Sources::default())
    }
}

impl Metrics {
    pub fn new(sources: Sources) -> Self {
        let requests =
            Family::<Labels, Histogram, fn() -> Histogram>::new_with_constructor(|| Histogram::new(LATENCY_BUCKETS));
        let mut registry = Registry::default();
        registry.register_with_unit(
            "photolib_http_request_duration",
            "HTTP requests by route and status code",
            Unit::Seconds,
            requests.clone(),
        );
        if let Some(lag) = sources.sync_lag.clone() {
            registry.register_with_unit(
                "photolib_sync_watermark_lag",
                "How long changes that ended above the sync watermark have waited for it",
                Unit::Seconds,
                lag,
            );
        }
        Metrics {
            registry,
            requests,
            sources,
        }
    }

    pub fn observe_request(&self, route: &str, status: u16, seconds: f64) {
        self.requests
            .get_or_create(&vec![("route", route.to_string()), ("status", status.to_string())])
            .observe(seconds);
    }

    /// The kept metrics, then those read now: what is gone since the last scrape has no series.
    pub async fn render(&self) -> String {
        let mut now = Registry::default();
        let mut last_backup = None;
        if let Some(db) = &self.sources.db {
            let up = Gauge::<i64>::default();
            match tokio::time::timeout(DEPENDENCY_TIMEOUT, db.stats()).await {
                Ok(Ok(stats)) => {
                    up.set(1);
                    last_backup = stats.last_backup;
                    register_db(&mut now, stats);
                }
                Ok(Err(error)) => tracing::warn!(%error, "no database metrics"),
                Err(error) => tracing::warn!(%error, "no database metrics"),
            }
            now.register(
                "photolib_database_up",
                "Whether this scrape could read the database",
                up,
            );
        }
        self.register_dirs(&mut now, last_backup);
        if let Some(ml) = &self.sources.ml {
            ml.register(&mut now);
        }
        let mut text = String::new();
        encode_registry(&mut text, &self.registry)
            .and_then(|()| encode_registry(&mut text, &now))
            .and_then(|()| encode_eof(&mut text))
            .expect("writing to a String cannot fail");
        text
    }

    /// The filesystems, and the newest dump: in the data directory, or `stored` elsewhere (Unix time).
    fn register_dirs(&self, registry: &mut Registry, stored: Option<f64>) {
        let (size, free) = (Family::<Labels, Gauge>::default(), Family::<Labels, Gauge>::default());
        for (name, dir) in &self.sources.dirs {
            if let Ok((bytes, left)) = crate::storage::space(dir) {
                let labels = vec![("dir", name.to_string())];
                size.get_or_create(&labels).set(bytes as i64);
                free.get_or_create(&labels).set(left as i64);
            }
        }
        registry.register_with_unit(
            "photolib_storage_size",
            "Size of the filesystem of each directory",
            Unit::Bytes,
            size,
        );
        registry.register_with_unit(
            "photolib_storage_free",
            "Space photolibd may still use on the filesystem of each directory",
            Unit::Bytes,
            free,
        );
        let Some(backups) = &self.sources.backups else {
            return;
        };
        let newest = fs::read_dir(backups)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|entry| entry.path().extension().is_some_and(|ext| ext == "dump"))
            .filter_map(|entry| entry.metadata().ok()?.modified().ok())
            .max();
        let stamp = Gauge::<f64, AtomicU64>::default();
        let newest = newest.map(|time| time.duration_since(UNIX_EPOCH).unwrap_or_default().as_secs_f64());
        stamp.set(newest.into_iter().chain(stored).fold(0.0, f64::max));
        registry.register_with_unit(
            "photolib_backup_last_timestamp",
            "When the newest database dump was written, in Unix time; 0 without one",
            Unit::Seconds,
            stamp,
        );
    }
}

fn register_db(registry: &mut Registry, stats: DbStats) {
    let drill = Gauge::<f64, AtomicU64>::default();
    drill.set(stats.last_verified_restore.unwrap_or(0.0));
    registry.register_with_unit(
        "photolib_restore_drill_last_success_timestamp",
        "When the newest restore drill that passed ended, in Unix time; 0 without one",
        Unit::Seconds,
        drill,
    );
    let jobs = Family::<Labels, Gauge>::default();
    let ages = Family::<Labels, Gauge<f64, AtomicU64>>::default();
    for job in stats.jobs {
        let labels = vec![("type", job.kind), ("status", job.status)];
        jobs.get_or_create(&labels).set(job.count);
        ages.get_or_create(&labels).set(job.oldest_secs);
    }
    registry.register(
        "photolib_jobs",
        "Queued, running and dead jobs by type and status",
        jobs,
    );
    registry.register_with_unit(
        "photolib_jobs_oldest_age",
        "Age of the oldest job by type and status",
        Unit::Seconds,
        ages,
    );
    let findings = Family::<Labels, Gauge>::default();
    for (kind, count) in stats.findings {
        findings.get_or_create(&vec![("kind", kind)]).set(count);
    }
    registry.register(
        "photolib_integrity_findings",
        "Open integrity findings by kind",
        findings,
    );
    let scrubs = Family::<Labels, Gauge<f64, AtomicU64>>::default();
    for (store, ended) in stats.scrubs {
        scrubs.get_or_create(&vec![("store", store)]).set(ended);
    }
    registry.register_with_unit(
        "photolib_scrub_cycle_end_timestamp",
        "When each store's scrub last went through all its files, in Unix time",
        Unit::Seconds,
        scrubs,
    );
    let (silent, pending) = (Family::<Labels, Gauge>::default(), Family::<Labels, Gauge>::default());
    let seen = Family::<Labels, Gauge<f64, AtomicU64>>::default();
    for device in stats.devices {
        let labels = vec![
            ("device", device.id),
            ("name", escaped(&device.name)),
            ("user", escaped(&device.user)),
        ];
        silent.get_or_create(&labels).set(i64::from(device.silent));
        pending.get_or_create(&labels).set(device.pending);
        seen.get_or_create(&labels).set(device.last_seen);
    }
    registry.register(
        "photolib_device_backup_silent",
        "1 for a device that has not reported its backup for longer than backup_silent_hours",
        silent,
    );
    registry.register(
        "photolib_device_backup_pending",
        "Items a device had left to back up at its last report",
        pending,
    );
    registry.register_with_unit(
        "photolib_device_last_seen_timestamp",
        "A reporting device's last request, in Unix time; 0 without one",
        Unit::Seconds,
        seen,
    );
}

/// A label value people chose, escaped as the text format needs and prometheus_client does not do.
pub(crate) fn escaped(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Lets through only `Authorization: Bearer <metrics.token>`, compared in constant time.
pub(crate) async fn bearer(State(token): State<Secret<String>>, request: Request, next: Next) -> Response {
    let given =
        (request.headers().get(header::AUTHORIZATION)).and_then(|value| value.to_str().ok()?.strip_prefix("Bearer "));
    if !given.is_some_and(|given| token.expose().as_bytes().ct_eq(given.as_bytes()).into()) {
        return (StatusCode::UNAUTHORIZED, [(header::WWW_AUTHENTICATE, "Bearer")]).into_response();
    }
    next.run(request).await
}

async fn metrics(State(metrics): State<Arc<Metrics>>) -> Response {
    let kind = "application/openmetrics-text; version=1.0.0; charset=utf-8";
    ([(header::CONTENT_TYPE, kind)], metrics.render().await).into_response()
}

/// `/metrics` and the doctor's `/diagnostics` on the one listener, beside the API, for the bearer of
/// `metrics.token`; without a token there are none.
pub fn router(metrics: Arc<Metrics>, doctor: Arc<Doctor>, token: Option<Secret<String>>) -> Router {
    let Some(token) = token else {
        return Router::new();
    };
    Router::new()
        .route("/metrics", get(self::metrics))
        .with_state(metrics)
        .merge(
            Router::new()
                .route("/diagnostics", get(crate::doctor::diagnostics))
                .with_state(doctor),
        )
        .route_layer(middleware::from_fn_with_state(token, bearer))
}

#[cfg(test)]
mod tests {
    use axum::{body::Body, http::Request};
    use tokio_util::sync::CancellationToken;
    use tower::ServiceExt;
    use uuid::Uuid;

    use super::*;
    use crate::{
        db::{DeviceStats, JobStats},
        http::{self, Health},
        role::Role,
        rpc,
        secret::Secret,
        testing::FakeDb,
    };

    fn with_db(db: &Arc<FakeDb>) -> Metrics {
        let db: Arc<dyn Database> = db.clone();
        Metrics::new(Sources {
            db: Some(db),
            ..Sources::default()
        })
    }

    fn job(kind: &str, status: &str, count: i64, oldest_secs: f64) -> JobStats {
        JobStats {
            kind: kind.into(),
            status: status.into(),
            count,
            oldest_secs,
        }
    }

    #[tokio::test]
    async fn jobs_come_from_the_database_and_the_lag_from_the_scheduler_at_each_scrape() {
        let (db, lag) = (Arc::new(FakeDb::default()), Gauge::<f64, AtomicU64>::default());
        let metrics = Metrics::new(Sources {
            db: Some(db.clone()),
            sync_lag: Some(lag.clone()),
            ..Sources::default()
        });
        db.stats.lock().unwrap().jobs = vec![job("render", "queued", 3, 120.5), job("embed", "dead", 1, 7.0)];
        lag.set(42.25);
        let text = metrics.render().await;
        for line in [
            r#"photolib_jobs{type="render",status="queued"} 3"#,
            r#"photolib_jobs{type="embed",status="dead"} 1"#,
            r#"photolib_jobs_oldest_age_seconds{type="render",status="queued"} 120.5"#,
            "photolib_sync_watermark_lag_seconds 42.25",
        ] {
            assert!(text.contains(line), "{line} missing from {text}");
        }
        db.stats.lock().unwrap().jobs.clear();
        lag.set(0.0);
        let text = metrics.render().await;
        assert!(!text.contains("photolib_jobs{"), "series of jobs that are gone vanish");
        assert!(text.contains("photolib_sync_watermark_lag_seconds 0.0"), "{text}");
    }

    #[tokio::test]
    async fn findings_scrubs_and_device_backups_come_from_the_database() {
        let db = Arc::new(FakeDb::default());
        *db.stats.lock().unwrap() = DbStats {
            findings: vec![("content".into(), 2), ("orphan".into(), 0)],
            scrubs: vec![("local".into(), 1000.0)],
            devices: vec![DeviceStats {
                id: "d1".into(),
                name: "Ann's \"Pixel\"".into(),
                user: "ann".into(),
                last_seen: 2000.0,
                pending: 12,
                silent: true,
            }],
            ..DbStats::default()
        };
        let text = with_db(&db).render().await;
        let device = r#"{device="d1",name="Ann's \"Pixel\"",user="ann"}"#;
        for (series, expected) in [
            (r#"photolib_integrity_findings{kind="content"}"#.to_string(), 2.0),
            (r#"photolib_integrity_findings{kind="orphan"}"#.into(), 0.0),
            (
                r#"photolib_scrub_cycle_end_timestamp_seconds{store="local"}"#.into(),
                1000.0,
            ),
            (format!("photolib_device_backup_silent{device}"), 1.0),
            (format!("photolib_device_backup_pending{device}"), 12.0),
            (format!("photolib_device_last_seen_timestamp_seconds{device}"), 2000.0),
        ] {
            assert_eq!(value(&text, &series), Some(expected), "{series} in {text}");
        }
    }

    /// The value of the one sample whose name and labels are `series`.
    fn value(text: &str, series: &str) -> Option<f64> {
        text.lines()
            .find_map(|line| line.strip_prefix(series)?.strip_prefix(' ')?.parse().ok())
    }

    #[tokio::test]
    async fn storage_and_the_newest_dump_come_from_the_directories() {
        let dir = tempfile::tempdir().unwrap();
        let backups = dir.path().join("backups");
        let metrics = Metrics::new(Sources {
            dirs: vec![("data_dir", dir.path().into()), ("work_dir", dir.path().join("none"))],
            backups: Some(backups.clone()),
            ..Sources::default()
        });
        let text = metrics.render().await;
        let size = value(&text, r#"photolib_storage_size_bytes{dir="data_dir"}"#).unwrap();
        let free = value(&text, r#"photolib_storage_free_bytes{dir="data_dir"}"#).unwrap();
        assert!(size > 0.0 && (0.0..=size).contains(&free), "{text}");
        assert!(
            !text.contains("work_dir"),
            "a directory that does not exist has no series"
        );
        assert_eq!(
            value(&text, "photolib_backup_last_timestamp_seconds"),
            Some(0.0),
            "{text}"
        );

        std::fs::create_dir(&backups).unwrap();
        for (name, stamp) in [
            ("pre-0001-0002-a.dump", 1_700_000_000),
            ("pre-0002-0003-b.dump", 1_600_000_000),
            ("pre-0003-0004-c.dump.partial", 1_800_000_000),
        ] {
            let file = std::fs::File::create(backups.join(name)).unwrap();
            file.set_modified(std::time::UNIX_EPOCH + std::time::Duration::from_secs(stamp))
                .unwrap();
        }
        let text = metrics.render().await;
        assert_eq!(
            value(&text, "photolib_backup_last_timestamp_seconds"),
            Some(1_700_000_000.0),
            "{text}"
        );
        let db = Arc::new(FakeDb::default());
        *db.stats.lock().unwrap() = DbStats {
            last_backup: Some(1_750_000_000.0),
            last_verified_restore: Some(1_750_000_100.0),
            ..DbStats::default()
        };
        let metrics = Metrics::new(Sources {
            db: Some(db),
            backups: Some(backups),
            ..Sources::default()
        });
        let text = metrics.render().await;
        for (series, at) in [
            ("photolib_backup_last_timestamp_seconds", 1_750_000_000.0),
            ("photolib_restore_drill_last_success_timestamp_seconds", 1_750_000_100.0),
        ] {
            assert_eq!(
                value(&text, series),
                Some(at),
                "a backup in another store counts: {text}"
            );
        }
    }

    #[tokio::test]
    async fn every_metric_the_dashboards_and_alerts_query_is_exported() {
        let dir = tempfile::tempdir().unwrap();
        let db = Arc::new(FakeDb::default());
        *db.stats.lock().unwrap() = DbStats {
            jobs: vec![job("render", "dead", 1, 1.0)],
            findings: vec![("content".into(), 0)],
            scrubs: vec![("local".into(), 0.0)],
            devices: vec![DeviceStats {
                id: "d1".into(),
                name: "Pixel".into(),
                user: "ann".into(),
                last_seen: 0.0,
                pending: 0,
                silent: false,
            }],
            ..DbStats::default()
        };
        let db: Arc<dyn Database> = db;
        let ml = Arc::new(crate::ml::Ml::default());
        let failed = photolib_ml::Verdict::Failed {
            error: "no CUDA device".into(),
        };
        let file = photolib_ml::FileReport {
            name: "m@1/m.onnx".into(),
            backends: vec![(photolib_ml::Backend::Cuda, failed)],
            chosen: None,
            cost: photolib_ml::Cost::default(),
        };
        let report = crate::ml::Report {
            node: "gpu-box".into(),
            error: None,
            files: vec![file],
        };
        ml.record(report, None);
        let metrics = Metrics::new(Sources {
            db: Some(db),
            dirs: vec![("data_dir", dir.path().into())],
            backups: Some(dir.path().into()),
            sync_lag: Some(Gauge::default()),
            ml: Some(ml),
        });
        metrics.observe_request("/readyz", 200, 0.01);
        let text = metrics.render().await;
        let bundle = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../deploy/observability");
        for file in ["alerts.yml", "grafana/dashboards/photolib.json"] {
            let queries = fs::read_to_string(format!("{bundle}/{file}")).unwrap();
            let names = queries
                .split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
                .filter(|word| word.starts_with("photolib_"));
            for name in names {
                assert!(
                    text.lines()
                        .any(|line| line.strip_prefix(name).is_some_and(|rest| rest.starts_with(['{', ' ']))),
                    "{file} queries {name}, which photolibd does not export"
                );
            }
        }
    }

    #[tokio::test(start_paused = true)]
    async fn a_database_that_fails_or_hangs_costs_its_series_not_the_scrape_and_reads_as_down() {
        let db = Arc::new(FakeDb::default());
        let metrics = with_db(&db);
        metrics.observe_request("/readyz", 200, 0.01);
        assert_eq!(value(&metrics.render().await, "photolib_database_up"), Some(1.0));
        db.set_down(true);
        let text = metrics.render().await;
        assert!(text.contains("photolib_http_request_duration_seconds_count"), "{text}");
        assert!(!text.contains("photolib_jobs"), "{text}");
        assert_eq!(value(&text, "photolib_database_up"), Some(0.0), "{text}");
        db.set_down(false);
        db.hangs.store(true, std::sync::atomic::Ordering::SeqCst);
        let text = metrics.render().await;
        assert!(!text.contains("photolib_jobs"), "{text}");
        assert_eq!(value(&text, "photolib_database_up"), Some(0.0), "{text}");
        assert!(
            !Metrics::default().render().await.contains("photolib_database_up"),
            "a process without a database says nothing about one"
        );
    }

    #[tokio::test]
    async fn only_the_bearer_of_the_configured_token_gets_the_metrics_and_the_diagnostics() {
        let token = "test-token-test-token-test-token";
        let scrape = |app: Router, path: &'static str, authorization: Option<String>| async move {
            let mut request = Request::get(path);
            if let Some(value) = authorization {
                request = request.header("authorization", value);
            }
            let response = app.oneshot(request.body(Body::empty()).unwrap()).await.unwrap();
            (response.status().as_u16(), response.headers().clone())
        };
        let dir = tempfile::tempdir().unwrap();
        let doctor = Arc::new(Doctor {
            config: crate::testing::config(&[], dir.path()),
            pool: None,
            seen: None,
            tail: None,
            ml: None,
        });
        let app = router(Arc::default(), doctor.clone(), Some(Secret::new(token.into())));
        for path in ["/metrics", "/diagnostics"] {
            for authorization in [None, Some("Bearer wrong".into()), Some(token.into())] {
                let (status, headers) = scrape(app.clone(), path, authorization.clone()).await;
                assert_eq!(status, 401, "{path} {authorization:?}");
                assert_eq!(headers["www-authenticate"], "Bearer");
            }
            let (status, _) = scrape(app.clone(), path, Some(format!("Bearer {token}"))).await;
            assert_eq!(status, 200, "{path}");
        }
        let (_, headers) = scrape(app, "/metrics", Some(format!("Bearer {token}"))).await;
        assert!(
            headers["content-type"]
                .to_str()
                .unwrap()
                .starts_with("application/openmetrics-text")
        );
        let off = router(Arc::default(), doctor, None);
        for path in ["/metrics", "/diagnostics"] {
            assert_eq!(
                scrape(off.clone(), path, Some(format!("Bearer {token}"))).await.0,
                404,
                "without a token there is no {path}"
            );
        }
    }

    #[tokio::test]
    async fn requests_are_timed_by_route_pattern_or_procedure_and_other_paths_share_one_series() {
        let metrics = Arc::new(Metrics::default());
        let health = Arc::new(Health {
            roles: vec![Role::Ml],
            db: None,
            shutdown: CancellationToken::new(),
            maintenance: None,
        });
        let app = http::router(
            health,
            rpc::api(Uuid::now_v7().to_string(), None, None, None),
            metrics.clone(),
        );
        for (method, path) in [
            ("GET", "/readyz/ml"),
            ("GET", "/readyz/api"),
            ("POST", "/photolib.api.v1.ServerInfoService/GetServerInfo"),
            ("POST", "/photolib.api.v1.Nope/Nope"),
            ("GET", "/wp-login.php"),
        ] {
            let request = Request::builder()
                .method(method)
                .uri(path)
                .header("content-type", "application/json")
                .body(Body::from("{}"))
                .unwrap();
            app.clone().oneshot(request).await.unwrap();
        }
        let text = metrics.render().await;
        for series in [
            r#"_count{route="/readyz/{role}",status="200"} 1"#,
            r#"_count{route="/readyz/{role}",status="404"} 1"#,
            r#"_count{route="/photolib.api.v1.ServerInfoService/GetServerInfo",status="200"} 1"#,
            r#"_count{route="unmatched",status="404"} 2"#,
        ] {
            assert!(text.contains(series), "{series} missing from {text}");
        }
        assert!(!text.contains("Nope") && !text.contains("wp-login"), "{text}");
        assert!(text.ends_with("# EOF\n"), "{text}");
    }
}
