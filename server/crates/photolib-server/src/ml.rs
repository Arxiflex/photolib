//! The `ml` role (ADR-0245, design 09 §3.2). At start it self-tests every installed model on each backend of the ONNX
//! Runtime library `ml.runtime` and keeps what passed in a `Pool` under `ml.memory_mb`; each backend it disables is
//! an administrator's warning: in the log, in `photolib_ml_backend_disabled` and in the doctor's `ml` check. A remote
//! node (`ml.server`) reports the same to the API every 5 minutes, presenting `ml.token`, which the API asks for.

use std::{
    collections::BTreeMap,
    path::Path,
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime},
};

use axum::{Json, Router, extract::State, http::StatusCode, middleware, routing::post};
use bytes::Bytes;
use http_body_util::Full;
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use photolib_ml::{FileReport, Ort, Pool, Runtime, Verdict};
use photolib_models::{REGISTRY, Store};
use prometheus_client::{
    metrics::{family::Family, gauge::Gauge},
    registry::Registry,
};
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

pub use crate::ocr::Models;
use crate::{
    config::Config,
    doctor::{Check, verdict},
    metrics::escaped,
    secret::Secret,
};

/// Where remote nodes report, on the API's listener.
pub const REPORT: &str = "/ml/v1/report";
/// How often a remote node reports; the API warns of one silent for three times as long.
const EVERY: Duration = Duration::from_mins(5);
const TIMEOUT: Duration = Duration::from_secs(10);

/// A node's self-test.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Report {
    /// Its host name
    pub node: String,
    /// Why ONNX Runtime did not load, if it did not
    pub error: Option<String>,
    /// Each installed file's self-test
    pub files: Vec<FileReport>,
}

/// The self-tests of the ML nodes this process knows: itself, and the remote nodes that report to its API, with when
/// they last did.
#[derive(Default)]
pub struct Ml {
    reports: Mutex<BTreeMap<String, (Report, Option<SystemTime>)>>,
}

/// The backends a self-test disabled for a file, and why.
fn disabled(file: &FileReport) -> impl Iterator<Item = (String, String)> + '_ {
    file.backends.iter().filter_map(|(backend, verdict)| {
        let why = match verdict {
            Verdict::Passed { .. } => return None,
            Verdict::Wrong { cosine } => format!("its outputs differ from the golden ones (cosine {cosine:.4})"),
            Verdict::Failed { error } => format!("it failed: {error}"),
        };
        Some((backend.to_string(), why))
    })
}

fn log(report: &Report) {
    let node = &report.node;
    if let Some(error) = &report.error {
        tracing::warn!(node, error, "ONNX Runtime did not load: no model runs");
    }
    for file in &report.files {
        let name = &file.name;
        match file.chosen {
            Some(backend) => tracing::info!(node, file = name, %backend, "an ML model passed its self-test"),
            None if file.backends.is_empty() => tracing::warn!(node, file = name, "an ML model has no golden input"),
            None => tracing::error!(node, file = name, "no backend reproduces an ML model's golden outputs"),
        }
        for (backend, why) in disabled(file) {
            tracing::warn!(node, file = name, backend, why, "an ML backend is disabled for a model");
        }
    }
}

impl Ml {
    /// Keeps `report`, logging it when it changed; `seen` is when a remote node sent it, `None` for this process.
    pub fn record(&self, report: Report, seen: Option<SystemTime>) {
        let Ok(mut reports) = self.reports.lock() else { return };
        if reports.get(&report.node).is_none_or(|(known, _)| *known != report) {
            log(&report);
        }
        reports.insert(report.node.clone(), (report, seen));
    }

    /// The doctor's `ml` check at `now`.
    pub fn check(&self, now: SystemTime) -> Check {
        let reports = self.reports.lock().map(|reports| reports.clone()).unwrap_or_default();
        let (mut running, mut warnings, mut failures) = (vec![], vec![], vec![]);
        if reports.is_empty() {
            warnings.push("no self-test has finished yet".into());
        }
        for (node, (report, seen)) in &reports {
            let silent = seen
                .and_then(|seen| now.duration_since(seen).ok())
                .filter(|silent| *silent > EVERY.saturating_mul(3));
            if let Some(silent) = silent {
                warnings.push(format!("{node} has not reported for {} minutes", silent.as_secs() / 60));
            }
            failures.extend(report.error.iter().map(|error| format!("{node}: {error}")));
            for file in &report.files {
                match file.chosen {
                    Some(backend) => running.push(format!("{node}: {} on {backend}", file.name)),
                    None if file.backends.is_empty() => {
                        warnings.push(format!("{node}: {} has no golden input and does not run", file.name));
                    }
                    None => failures.push(format!(
                        "{node}: no backend reproduces the golden outputs of {}",
                        file.name
                    )),
                }
                for (backend, why) in disabled(file) {
                    warnings.push(format!("{node}: {backend} is disabled for {}: {why}", file.name));
                }
            }
        }
        let fine = if running.is_empty() {
            "no models installed; `photolibd models fetch` installs them".into()
        } else {
            running.join("; ")
        };
        verdict("ml", fine, warnings, failures)
    }

    /// `photolib_ml_backend_disabled`, for each backend a node disabled for a file.
    pub fn register(&self, registry: &mut Registry) {
        let family = Family::<Vec<(&'static str, String)>, Gauge>::default();
        for (node, (report, _)) in self.reports.lock().iter().flat_map(|reports| reports.iter()) {
            for file in &report.files {
                for (backend, _) in disabled(file) {
                    let labels = vec![
                        ("node", escaped(node)),
                        ("file", escaped(&file.name)),
                        ("backend", backend),
                    ];
                    family.get_or_create(&labels).set(1);
                }
            }
        }
        registry.register(
            "photolib_ml_backend_disabled",
            "1 for each ML backend whose self-test failed for a model file on a node",
            family,
        );
    }
}

/// Self-tests the models installed in `dir`, on the runtime that `runtime` loads only if there are any, and pools
/// the files that passed under `memory` resident bytes.
pub fn test_models(
    dir: Option<&Path>,
    runtime: impl FnOnce() -> Result<&'static dyn Runtime, String>,
    memory: u64,
) -> (Report, Option<Pool<'static>>) {
    let host = std::fs::read_to_string("/proc/sys/kernel/hostname").unwrap_or_default();
    let mut report = Report {
        node: Some(host.trim())
            .filter(|host| !host.is_empty())
            .unwrap_or("photolibd")
            .into(),
        error: None,
        files: vec![],
    };
    let Some(dir) = dir else { return (report, None) };
    let models = Store::new(dir, &REGISTRY).installed();
    if models.is_empty() {
        return (report, None);
    }
    match runtime() {
        Ok(runtime) => {
            report.files = photolib_ml::self_test(runtime, dir, &models);
            let pool = Pool::new(runtime, dir, &report.files, memory, photolib_ml::rss);
            (report, Some(pool))
        }
        Err(error) => {
            report.error = Some(error);
            (report, None)
        }
    }
}

/// Runs the role: its self-test, then sharing the pool as `models`, unloading idle models and, on a remote node,
/// reporting to the API.
pub fn start(config: &Config, ml: Arc<Ml>, models: Models, shutdown: CancellationToken) {
    let (dir, library) = (config.models_dir(), config.ml.runtime.clone());
    let memory = config.ml.memory_mb.saturating_mul(1_000_000);
    let api = config.ml.server.clone().zip(config.ml.token.clone());
    tokio::spawn(async move {
        let ort = move || Ort::load(&library).map(|ort| ort as &'static dyn Runtime);
        let tested = tokio::task::spawn_blocking(move || test_models(dir.as_deref(), ort, memory)).await;
        let Ok((report, pool)) = tested else { return };
        ml.record(report.clone(), None);
        if let Some((server, token)) = api {
            tokio::spawn(report_every(server, token, report, shutdown.clone()));
        }
        let Some(pool) = pool else { return };
        // The jobs that run models (`ocr`, `faces`) find the pool here once its self-test is done.
        let Ok(()) = models.set(pool).map_err(drop) else { return };
        while !shutdown.is_cancelled() {
            tokio::select! {
                () = tokio::time::sleep(Duration::from_mins(1)) => {
                    models.get().iter().for_each(|pool| pool.unload_idle(Instant::now()));
                }
                () = shutdown.cancelled() => {}
            }
        }
    });
}

/// Sends `report` to the API at `server`.
async fn send(server: &str, token: &Secret<String>, report: &Report) -> Result<(), String> {
    let tls = Arc::new(rustls::crypto::ring::default_provider());
    let connector = hyper_rustls::HttpsConnectorBuilder::new()
        .with_provider_and_native_roots(tls)
        .map_err(|error| format!("cannot load the system's TLS roots: {error}"))?
        .https_or_http()
        .enable_http1()
        .build();
    let body = serde_json::to_vec(report).map_err(|e| e.to_string())?;
    let request = axum::http::Request::post(format!("{}{REPORT}", server.trim_end_matches('/')))
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {}", token.expose()))
        .header(axum::http::header::CONTENT_TYPE, "application/json")
        .body(Full::new(Bytes::from(body)))
        .map_err(|e| e.to_string())?;
    let client = Client::builder(TokioExecutor::new()).build::<_, Full<Bytes>>(connector);
    let response = tokio::time::timeout(TIMEOUT, client.request(request)).await;
    match response.map_err(|_| format!("no answer within {TIMEOUT:?}"))? {
        Ok(response) if response.status() == StatusCode::NO_CONTENT => Ok(()),
        Ok(response) => Err(format!("HTTP {}", response.status())),
        Err(error) => Err(error.to_string()),
    }
}

/// Reports to the API every `EVERY` until `shutdown`, logging when that starts and stops failing.
async fn report_every(server: String, token: Secret<String>, report: Report, shutdown: CancellationToken) {
    let mut failing = false;
    while !shutdown.is_cancelled() {
        let sent = send(&server, &token, &report).await;
        match &sent {
            Ok(()) if failing => tracing::info!(server, "the API takes this ML node's reports again"),
            Err(error) if !failing => tracing::warn!(server, error, "cannot report to the API"),
            _ => {}
        }
        failing = sent.is_err();
        tokio::select! {
            () = tokio::time::sleep(EVERY) => {}
            () = shutdown.cancelled() => {}
        }
    }
}

async fn receive(State(ml): State<Arc<Ml>>, Json(report): Json<Report>) -> StatusCode {
    ml.record(report, Some(SystemTime::now()));
    StatusCode::NO_CONTENT
}

/// `REPORT`, for the bearer of `token`.
pub fn router(ml: Arc<Ml>, token: Secret<String>) -> Router {
    Router::new()
        .route(REPORT, post(receive))
        .with_state(ml)
        .route_layer(middleware::from_fn_with_state(token, crate::metrics::bearer))
}

#[cfg(test)]
mod tests {
    use axum::{body::Body, http::Request};
    use photolib_ml::{
        Backend,
        testing::{Fake, GOLDEN, installed},
    };
    use tower::ServiceExt;

    use super::*;
    use crate::{
        config::{Log, LogFormat},
        doctor::Status,
        testing::Capture,
    };

    const TOKEN: &str = "node-token-node-token-node-token";

    fn runtime(outputs: fn(Backend) -> Result<Vec<f32>, String>) -> &'static dyn Runtime {
        Box::leak(Box::new(Fake {
            backends: vec![Backend::OpenVino, Backend::Cpu],
            outputs,
        }))
    }

    /// A node's self-test of `installed`'s model on a fake OpenVINO and CPU.
    fn tested(outputs: fn(Backend) -> Result<Vec<f32>, String>) -> (Report, Option<Pool<'static>>) {
        let (dir, _) = installed(true);
        let tested = test_models(Some(dir.path()), || Ok(runtime(outputs)), 1 << 30);
        (
            Report {
                node: "gpu-box".into(),
                ..tested.0
            },
            tested.1,
        )
    }

    fn metrics(ml: &Ml) -> String {
        let mut registry = Registry::default();
        ml.register(&mut registry);
        let mut text = String::new();
        prometheus_client::encoding::text::encode(&mut text, &registry).unwrap();
        text
    }

    #[test]
    fn a_backend_with_wrong_outputs_is_disabled_at_startup_with_an_admin_warning() {
        let capture = Capture::default();
        let guards = capture.set_default(&Log {
            format: LogFormat::Json,
            filter: "info".into(),
        });
        let (report, pool) = tested(|backend| match backend {
            Backend::OpenVino => Ok(GOLDEN.iter().map(|v| -v).collect()),
            _ => Ok(GOLDEN.to_vec()),
        });
        let ml = Ml::default();
        ml.record(report.clone(), None);
        ml.record(report, None);
        drop(guards);
        let check = ml.check(SystemTime::now());
        assert_eq!(check.status, Status::Warn, "{check:?}");
        assert!(
            check.detail.contains(
                "gpu-box: openvino is disabled for m@1/m.onnx: its outputs differ from the golden ones (cosine -1.0000)"
            ),
            "{check:?}"
        );
        assert!(
            metrics(&ml)
                .contains(r#"photolib_ml_backend_disabled{node="gpu-box",file="m@1/m.onnx",backend="openvino"} 1"#),
            "{}",
            metrics(&ml)
        );
        let quoted = Report {
            node: r#"box "1""#.into(),
            ..tested(|_| Err("no GPU".into())).0
        };
        ml.record(quoted, None);
        let escaped = r#"photolib_ml_backend_disabled{node="box \"1\"",file="m@1/m.onnx",backend="cpu"} 1"#;
        assert!(metrics(&ml).contains(escaped), "{}", metrics(&ml));
        let log = capture.text();
        assert_eq!(
            log.matches("an ML backend is disabled for a model").count(),
            1,
            "logged once: {log}"
        );
        assert!(log.contains(r#""backend":"openvino""#), "{log}");
        assert!(log.contains("an ML model passed its self-test"), "{log}");
        let pool = pool.unwrap();
        assert_eq!(
            pool.run("m@1/m.onnx", &[vec![]]).unwrap()[0][0].1,
            GOLDEN,
            "the CPU runs it"
        );
    }

    #[test]
    fn without_models_onnx_runtime_is_never_loaded_and_ml_is_fine() {
        let empty = tempfile::tempdir().unwrap();
        for dir in [None, Some(empty.path())] {
            let (report, pool) = test_models(dir, || panic!("ONNX Runtime loaded"), 1 << 30);
            assert!(report.files.is_empty() && report.error.is_none() && pool.is_none());
            let ml = Ml::default();
            assert_eq!(
                ml.check(SystemTime::now()).status,
                Status::Warn,
                "the self-test is running"
            );
            ml.record(report, None);
            let check = ml.check(SystemTime::now());
            assert_eq!(check.status, Status::Ok, "{check:?}");
            assert!(check.detail.contains("photolibd models fetch"), "{check:?}");
        }
    }

    #[test]
    fn installed_models_that_cannot_run_fail_the_check() {
        let (dir, _) = installed(true);
        let (report, pool) = test_models(Some(dir.path()), || Err("no libonnxruntime.so".into()), 1 << 30);
        assert!(pool.is_none());
        let (drifted, _) = tested(|_| Ok(GOLDEN.iter().map(|v| v + 0.06).collect()));
        let ml = Ml::default();
        ml.record(report, None);
        ml.record(drifted, None);
        let check = ml.check(SystemTime::now());
        assert_eq!(check.status, Status::Fail, "{check:?}");
        assert!(check.detail.contains(": no libonnxruntime.so"), "{check:?}");
        assert!(
            check
                .detail
                .contains("gpu-box: no backend reproduces the golden outputs of m@1/m.onnx"),
            "{check:?}"
        );
        let (dir, _) = installed(false);
        let (unchecked, _) = test_models(Some(dir.path()), || Ok(runtime(|_| Ok(vec![]))), 1 << 30);
        let ml = Ml::default();
        ml.record(unchecked, None);
        assert!(
            ml.check(SystemTime::now())
                .detail
                .contains("m@1/m.onnx has no golden input and does not run")
        );
    }

    #[test]
    fn a_node_report_dated_2100_is_current_until_the_node_falls_silent() {
        let at = SystemTime::UNIX_EPOCH + Duration::from_hours(1_139_568);
        let (report, _) = tested(|_| Ok(GOLDEN.to_vec()));
        let ml = Ml::default();
        ml.record(report, Some(at));
        assert_eq!(ml.check(at + 3 * EVERY).status, Status::Ok);
        let check = ml.check(at + 3 * EVERY + Duration::from_mins(1));
        assert_eq!(check.status, Status::Warn);
        assert!(
            check.detail.contains("gpu-box has not reported for 16 minutes"),
            "{check:?}"
        );
    }

    #[tokio::test]
    async fn the_api_takes_reports_only_from_the_bearer_of_the_token() {
        let ml = Arc::new(Ml::default());
        let app = router(ml.clone(), Secret::new(TOKEN.into()));
        let (report, _) = tested(|_| Ok(GOLDEN.to_vec()));
        let body = serde_json::to_string(&report).unwrap();

        for (auth, status) in [(None, 401), (Some("Bearer wrong"), 401), (Some(TOKEN), 204)] {
            let mut request = Request::post(REPORT).header("content-type", "application/json");
            if let Some(auth) = auth {
                request = request.header(
                    "authorization",
                    if auth == TOKEN {
                        format!("Bearer {auth}")
                    } else {
                        auth.into()
                    },
                );
            }
            let response = app
                .clone()
                .oneshot(request.body(Body::from(body.clone())).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), status, "{auth:?}");
            let reported = ml
                .check(SystemTime::now())
                .detail
                .contains("gpu-box: m@1/m.onnx on openvino");
            assert_eq!(reported, status == 204, "{auth:?}");
        }
    }

    #[tokio::test]
    async fn a_remote_node_reports_its_self_test_to_the_api_with_its_token() {
        let ml = Arc::new(Ml::default());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let server = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(axum::serve(listener, router(ml.clone(), Secret::new(TOKEN.into()))).into_future());
        let (report, _) = tested(|_| Ok(GOLDEN.to_vec()));
        let wrong = send(&server, &Secret::new("x".repeat(32)), &report).await;
        assert_eq!(wrong, Err("HTTP 401 Unauthorized".into()));
        send(&format!("{server}/"), &Secret::new(TOKEN.into()), &report)
            .await
            .unwrap();
        assert!(
            ml.check(SystemTime::now())
                .detail
                .contains("gpu-box: m@1/m.onnx on openvino")
        );
    }
}
