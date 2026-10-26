use std::{collections::BTreeMap, sync::Arc, time::Duration};

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, MatchedPath, Path, Request, State},
    http::{HeaderValue, StatusCode},
    middleware::{self, Next},
    response::Response,
    routing::get,
};
use serde::Serialize;
use serde_json::{Value, json};
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;
use tower::ServiceExt as _;
use tracing::Instrument;
use uuid::Uuid;

use crate::{db::Database, metrics::Metrics, role::Role, rpc::Procedure};

pub const REQUEST_ID_HEADER: &str = "x-request-id";
pub(crate) const DEPENDENCY_TIMEOUT: Duration = Duration::from_secs(2);

/// What the health endpoints report on: the roles of this process, their dependencies and the shutdown signal.
pub struct Health {
    pub roles: Vec<Role>,
    pub db: Option<Arc<dyn Database>>,
    pub shutdown: CancellationToken,
    /// Why the roles on the database cannot work: the schema upgrade failed and was rolled back.
    pub maintenance: Option<String>,
}

#[derive(Serialize)]
pub struct RoleStatus {
    pub ready: bool,
    pub checks: BTreeMap<&'static str, String>,
}

impl Health {
    async fn database(&self) -> String {
        let Some(db) = &self.db else {
            return "not configured".into();
        };
        match tokio::time::timeout(DEPENDENCY_TIMEOUT, db.ping()).await {
            Ok(Ok(())) => "ok".into(),
            Ok(Err(error)) => error.to_string(),
            Err(_) => format!("timed out after {}s", DEPENDENCY_TIMEOUT.as_secs()),
        }
    }

    async fn statuses(&self, only: Option<Role>) -> BTreeMap<String, RoleStatus> {
        let roles: Vec<Role> = self
            .roles
            .iter()
            .copied()
            .filter(|role| only.is_none_or(|only| only == *role))
            .collect();
        let database = if roles.iter().any(|role| role.needs_instance()) {
            self.database().await
        } else {
            String::new()
        };
        let draining = self.shutdown.is_cancelled();
        roles
            .into_iter()
            .map(|role| {
                let mut checks = BTreeMap::new();
                if role.needs_instance() {
                    checks.insert("database", database.clone());
                    if let Some(reason) = &self.maintenance {
                        checks.insert("schema", reason.clone());
                    }
                }
                if draining {
                    checks.insert("shutdown", "draining".to_string());
                }
                let ready = !draining
                    && !checks.contains_key("schema")
                    && checks.get("database").is_none_or(|check| check == "ok");
                (role.to_string(), RoleStatus { ready, checks })
            })
            .collect()
    }
}

fn status_code(ready: bool) -> StatusCode {
    if ready {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    }
}

async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

/// Takes a body as large as an upload append and drops it, for the apps' connection check to find a proxy that caps
/// requests below it (OPS-29).
async fn drained(_: axum::body::Bytes) -> StatusCode {
    StatusCode::NO_CONTENT
}

async fn readyz(State(health): State<Arc<Health>>) -> (StatusCode, Json<Value>) {
    let roles = health.statuses(None).await;
    let ready = roles.values().all(|role| role.ready);
    let mut body = json!({ "ready": ready, "roles": roles });
    if let Some(db) = &health.db
        && let Ok(Ok(upgrading)) = tokio::time::timeout(DEPENDENCY_TIMEOUT, db.upgrading()).await
        && !upgrading.is_empty()
    {
        body["upgrading"] = json!(upgrading);
    }
    (status_code(ready), Json(body))
}

async fn readyz_role(State(health): State<Arc<Health>>, Path(name): Path<String>) -> (StatusCode, Json<Value>) {
    let Some(role) = name.parse::<Role>().ok().filter(|role| health.roles.contains(role)) else {
        return (
            StatusCode::NOT_FOUND,
            Json(json!({ "error": format!("role {name} does not run in this process") })),
        );
    };
    let status = health.statuses(Some(role)).await.remove(&role.to_string());
    let ready = status.as_ref().is_some_and(|status| status.ready);
    (status_code(ready), Json(json!(status)))
}

/// Gives every request a server-generated id (a client-supplied one is never trusted), puts it on the log span
/// and returns it in `x-request-id`; times it by route, a pattern rather than the path so that probing random paths
/// adds no series. Every response forbids sniffing, and all but photolibd's own pages forbid rendering as a page.
async fn request_id(State(metrics): State<Arc<Metrics>>, request: Request, next: Next) -> Response {
    let id = Uuid::now_v7();
    let (method, path) = (request.method().clone(), request.uri().path().to_string());
    let matched = request
        .extensions()
        .get::<MatchedPath>()
        .map(|route| route.as_str().to_string());
    let probe = ["/healthz", "/readyz", "/metrics"]
        .iter()
        .any(|prefix| path.starts_with(prefix));
    let span = tracing::info_span!("request", request_id = %id, %method, %path);
    let started = std::time::Instant::now();
    let mut response = next.run(request).instrument(span.clone()).await;
    let (status, elapsed_ms) = (response.status().as_u16(), started.elapsed().as_millis() as u64);
    span.in_scope(|| match probe {
        true => tracing::debug!(status, elapsed_ms, "request finished"),
        false => tracing::info!(status, elapsed_ms, "request finished"),
    });
    let route = matched.or_else(|| response.extensions().get::<Procedure>().map(|p| p.0.clone()));
    metrics.observe_request(
        route.as_deref().unwrap_or("unmatched"),
        status,
        started.elapsed().as_secs_f64(),
    );
    let headers = response.headers_mut();
    headers.insert(
        REQUEST_ID_HEADER,
        HeaderValue::from_str(&id.to_string()).expect("a uuid is a valid header value"),
    );
    // Responses carry what files say (names, EXIF, OCR text) as data: no browser may render one as a page but
    // photolibd's own pages (relay.rs).
    headers.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
    if headers
        .get("content-security-policy")
        .is_none_or(|policy| policy != crate::relay::CSP && !policy.to_str().is_ok_and(crate::web::is_own))
    {
        headers.insert(
            "content-security-policy",
            HeaderValue::from_static("default-src 'none'; frame-ancestors 'none'; sandbox"),
        );
    }
    response
}

/// The health endpoints next to `api`, the Connect API (empty when the process runs no `api` role).
pub fn router(health: Arc<Health>, api: Router, metrics: Arc<Metrics>) -> Router {
    Router::new()
        .route(
            "/healthz",
            get(healthz).post(drained).layer(DefaultBodyLimit::max(16 << 20)),
        )
        .route("/readyz", get(readyz))
        .route("/readyz/{role}", get(readyz_role))
        .with_state(health)
        .merge(api)
        .layer(middleware::from_fn_with_state(metrics, request_id))
}

/// `app` beneath `base_path` (`base_path` in the configuration); `/` leaves it at the root. `<base_path>/`, where
/// photolibd's links point, is the app's `/`.
pub fn under(base_path: &str, app: Router) -> Router {
    match base_path {
        "/" => app,
        base => Router::new()
            .route_service(
                &format!("{base}/"),
                app.clone().map_request(|mut request: Request| {
                    *request.uri_mut() = axum::http::Uri::from_static("/");
                    request
                }),
            )
            .nest(base, app),
    }
}

/// Serves `app` until `shutdown`, then lets in-flight requests finish for up to `grace`; connections still open
/// after that are cut when the process exits.
pub async fn serve(
    listener: TcpListener,
    app: Router,
    shutdown: CancellationToken,
    grace: Duration,
) -> std::io::Result<()> {
    let app = app.into_make_service_with_connect_info::<std::net::SocketAddr>();
    let server = axum::serve(listener, app).with_graceful_shutdown(shutdown.clone().cancelled_owned());
    let deadline = async {
        shutdown.cancelled().await;
        tokio::time::sleep(grace).await;
    };
    tokio::select! {
        result = server => result,
        () = deadline => {
            tracing::warn!(grace_secs = grace.as_secs(), "the grace period ended; closing the connections that are still open");
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::Ordering;

    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;
    use uuid::Uuid;

    use super::*;
    use crate::{role::WorkerClass, testing::FakeDb};

    fn health(roles: &[Role], db: &Arc<FakeDb>) -> Arc<Health> {
        let db: Arc<dyn Database> = db.clone();
        Arc::new(Health {
            roles: roles.to_vec(),
            db: Some(db),
            shutdown: CancellationToken::new(),
            maintenance: None,
        })
    }

    fn without_db(roles: &[Role]) -> Arc<Health> {
        Arc::new(Health {
            roles: roles.to_vec(),
            db: None,
            shutdown: CancellationToken::new(),
            maintenance: None,
        })
    }

    async fn get(health: &Arc<Health>, path: &str) -> (StatusCode, serde_json::Value, axum::http::HeaderMap) {
        let response = router(health.clone(), Router::new(), Default::default())
            .oneshot(Request::get(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        let (parts, body) = response.into_parts();
        let bytes = axum::body::to_bytes(body, 1 << 20).await.unwrap();
        (
            parts.status,
            serde_json::from_slice(&bytes).unwrap_or_default(),
            parts.headers,
        )
    }

    const ALL: [Role; 3] = [Role::Api, Role::Scheduler, Role::Worker(WorkerClass::Cpu)];

    #[tokio::test]
    async fn under_a_base_path_every_endpoint_moves_beneath_it() {
        let api = Router::new()
            .route("/", axum::routing::get(|| async { "root" }))
            .fallback(|uri: axum::http::Uri| async move { uri.path().to_string() });
        let app = router(without_db(&[Role::Ml]), api, Default::default());
        let send = |app: &Router, path: &str| {
            let request = Request::get(path).body(Body::empty()).unwrap();
            let response = app.clone().oneshot(request);
            async move {
                let response = response.await.unwrap();
                let status = response.status();
                let body = axum::body::to_bytes(response.into_body(), 1 << 20).await.unwrap();
                (status, String::from_utf8(body.to_vec()).unwrap())
            }
        };
        let photos = under("/photos", app.clone());
        assert_eq!(send(&photos, "/photos/healthz").await.0, StatusCode::OK);
        let call = "/photolib.api.v1.ServerInfoService/GetServerInfo";
        assert_eq!(
            send(&photos, &format!("/photos{call}")).await,
            (StatusCode::OK, call.into())
        );
        // Where photolibd's links point, such as a password setup link.
        assert_eq!(send(&photos, "/photos/").await, (StatusCode::OK, "root".into()));
        for outside in ["/healthz", call, "/photosx/healthz", "/other/photos/healthz"] {
            assert_eq!(send(&photos, outside).await.0, StatusCode::NOT_FOUND, "{outside}");
        }
        let root = under("/", app);
        assert_eq!(send(&root, "/healthz").await.0, StatusCode::OK);
        assert_eq!(send(&root, call).await.1, call);
    }

    #[tokio::test]
    async fn after_a_failed_upgrade_the_roles_on_the_database_are_in_maintenance() {
        let db: Arc<dyn Database> = Arc::new(FakeDb::default());
        let health = Arc::new(Health {
            roles: vec![Role::Api, Role::Ml],
            db: Some(db),
            shutdown: CancellationToken::new(),
            maintenance: Some("maintenance: run `photolibd restore /x.dump`".into()),
        });
        let (status, body, _) = get(&health, "/readyz").await;
        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE, "{body}");
        assert_eq!(body["roles"]["api"]["ready"], false);
        assert_eq!(
            body["roles"]["api"]["checks"]["schema"],
            "maintenance: run `photolibd restore /x.dump`"
        );
        assert_eq!(body["roles"]["ml"]["ready"], true, "ml needs no database");
    }

    #[tokio::test]
    async fn unfinished_data_migrations_show_as_upgrading_without_hurting_readiness() {
        let db = Arc::new(FakeDb::default());
        let health = health(&ALL, &db);
        let (_, body, _) = get(&health, "/readyz").await;
        assert_eq!(body.get("upgrading"), None, "{body}");
        *db.upgrading.lock().unwrap() = vec!["backfill: running, 40 of 100".into()];
        let (status, body, _) = get(&health, "/readyz").await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["upgrading"], json!(["backfill: running, 40 of 100"]));
    }

    #[tokio::test]
    async fn liveness_needs_no_dependency() {
        let db = Arc::new(FakeDb::default());
        db.set_down(true);
        let (status, body, _) = get(&health(&ALL, &db), "/healthz").await;
        assert_eq!((status, body["status"].as_str()), (StatusCode::OK, Some("ok")));
    }

    #[tokio::test]
    async fn a_post_to_healthz_drains_an_upload_append_for_the_apps_proxy_check() {
        let app = router(without_db(&ALL), Router::new(), Arc::default());
        let post = |bytes: usize| {
            let request = Request::post("/healthz").body(Body::from(vec![0u8; bytes])).unwrap();
            app.clone().oneshot(request)
        };
        assert_eq!(post(8 << 20).await.unwrap().status(), StatusCode::NO_CONTENT);
        assert_eq!(
            post((16 << 20) + 1).await.unwrap().status(),
            StatusCode::PAYLOAD_TOO_LARGE
        );
    }

    #[tokio::test]
    async fn every_role_is_ready_while_the_database_answers() {
        let db = Arc::new(FakeDb::default());
        let health = health(&ALL, &db);
        let (status, body, _) = get(&health, "/readyz").await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(body["ready"], true);
        for role in ["api", "scheduler", "worker:cpu"] {
            assert_eq!(body["roles"][role]["ready"], true, "{role}: {body}");
            assert_eq!(body["roles"][role]["checks"]["database"], "ok");
            assert_eq!(get(&health, &format!("/readyz/{role}")).await.0, StatusCode::OK);
        }
    }

    #[tokio::test]
    async fn killing_the_database_flips_readiness_and_restoring_it_flips_it_back() {
        let db = Arc::new(FakeDb::default());
        let health = health(&ALL, &db);
        db.set_down(true);
        let (status, body, _) = get(&health, "/readyz").await;
        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(body["ready"], false);
        assert_eq!(body["roles"]["api"]["checks"]["database"], "connection refused");
        assert_eq!(
            get(&health, "/readyz/scheduler").await.0,
            StatusCode::SERVICE_UNAVAILABLE
        );
        db.set_down(false);
        assert_eq!(get(&health, "/readyz").await.0, StatusCode::OK);
    }

    #[tokio::test(start_paused = true)]
    async fn a_database_that_hangs_makes_the_role_not_ready_within_the_timeout() {
        let db = Arc::new(FakeDb::default());
        db.hangs.store(true, Ordering::SeqCst);
        let (status, body, _) = get(&health(&ALL, &db), "/readyz/api").await;
        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert!(
            body["checks"]["database"].as_str().unwrap().contains("timed out"),
            "{body}"
        );
    }

    #[tokio::test]
    async fn only_the_roles_running_in_this_process_are_reported() {
        let db = Arc::new(FakeDb::default());
        let health = health(&[Role::Worker(WorkerClass::Gpu)], &db);
        let (_, body, _) = get(&health, "/readyz").await;
        assert_eq!(
            body["roles"].as_object().unwrap().keys().collect::<Vec<_>>(),
            ["worker:gpu"]
        );
        assert_eq!(get(&health, "/readyz/api").await.0, StatusCode::NOT_FOUND);
        assert_eq!(get(&health, "/readyz/bogus").await.0, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn the_ml_role_depends_on_no_database() {
        let db = Arc::new(FakeDb::default());
        db.set_down(true);
        let health = health(&[Role::Ml], &db);
        let (status, body, _) = get(&health, "/readyz/ml").await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert!(body["checks"].as_object().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_database_role_without_a_database_is_not_ready() {
        let health = without_db(&[Role::Api]);
        assert_eq!(get(&health, "/readyz/api").await.0, StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn shutting_down_makes_every_role_not_ready_but_the_process_alive() {
        let db = Arc::new(FakeDb::default());
        let ml = without_db(&[Role::Ml]);
        let health = health(&ALL, &db);
        health.shutdown.cancel();
        ml.shutdown.cancel();
        for health in [&health, &ml] {
            let (status, body, _) = get(health, "/readyz").await;
            assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE, "{body}");
            assert_eq!(get(health, "/healthz").await.0, StatusCode::OK);
        }
        let (_, body, _) = get(&ml, "/readyz/ml").await;
        assert_eq!(body["checks"]["shutdown"], "draining");
    }

    #[tokio::test]
    async fn every_response_carries_a_server_generated_request_id() {
        let db = Arc::new(FakeDb::default());
        let health = health(&ALL, &db);
        let ids: Vec<String> = {
            let mut ids = Vec::new();
            for path in ["/healthz", "/readyz", "/nope"] {
                let (_, _, headers) = get(&health, path).await;
                ids.push(headers[REQUEST_ID_HEADER].to_str().unwrap().to_string());
            }
            ids
        };
        for id in &ids {
            assert!(Uuid::parse_str(id).is_ok(), "{id}");
        }
        assert_eq!(ids.iter().collect::<std::collections::HashSet<_>>().len(), 3);
        let spoofed = router(health.clone(), Router::new(), Default::default())
            .oneshot(
                Request::get("/healthz")
                    .header(REQUEST_ID_HEADER, "client-chosen")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_ne!(spoofed.headers()[REQUEST_ID_HEADER], "client-chosen");
    }

    /// Whatever a response carries, such as text a file's metadata or name put there, no browser renders it as a page
    /// or runs it: every response forbids sniffing, scripts, frames and embedding.
    #[tokio::test]
    async fn no_response_can_be_rendered_as_a_page() {
        let html = "<script>alert(document.cookie)</script>";
        let api = Router::new().route(
            "/markup",
            axum::routing::get(move || async move { ([("content-type", "text/html")], html) }),
        );
        let app = router(without_db(&[Role::Api]), api, Default::default());
        for path in ["/healthz", "/markup", "/nowhere"] {
            let response = app
                .clone()
                .oneshot(Request::get(path).body(Body::empty()).unwrap())
                .await
                .unwrap();
            let headers = response.headers();
            assert_eq!(headers["x-content-type-options"], "nosniff", "{path}");
            assert_eq!(
                headers["content-security-policy"], "default-src 'none'; frame-ancestors 'none'; sandbox",
                "{path}"
            );
        }
    }

    /// photolibd's own pages run their own script, under their own policy, behind the same middleware as in
    /// production; any other policy a handler sets is replaced.
    #[tokio::test]
    async fn only_photolibds_own_pages_keep_their_policy() {
        let pages = crate::relay::routes().route(
            "/weak",
            axum::routing::get(|| async { ([("content-security-policy", "script-src *")], "<script></script>") }),
        );
        let app = router(without_db(&[Role::Api]), pages, Arc::default());
        for (path, policy) in [
            ("/passkey", crate::relay::CSP),
            ("/weak", "default-src 'none'; frame-ancestors 'none'; sandbox"),
        ] {
            let response = app
                .clone()
                .oneshot(Request::get(path).body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.headers()["content-security-policy"], policy, "{path}");
        }
    }

    /// The web app keeps the policy with its nonce through the middleware, and nothing else gets to claim it.
    #[tokio::test]
    async fn the_web_app_keeps_its_policy_and_no_look_alike_does() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("index.html"), "<script nonce=\"CSP_NONCE\"></script>").unwrap();
        let sandbox = "default-src 'none'; frame-ancestors 'none'; sandbox";
        let app = crate::web::app(dir.path().into(), Router::new()).route(
            "/weak",
            axum::routing::get(|| async {
                (
                    [(
                        "content-security-policy",
                        "default-src 'self'; style-src 'self' 'nonce-x'; script-src *",
                    )],
                    "",
                )
            }),
        );
        let app = router(without_db(&[Role::Api]), app, Arc::default());
        let get = |path| app.clone().oneshot(Request::get(path).body(Body::empty()).unwrap());
        let page = get("/").await.unwrap();
        let policy = page.headers()["content-security-policy"].to_str().unwrap().to_string();
        assert!(
            policy.contains("'wasm-unsafe-eval'") && policy.contains("'nonce-"),
            "{policy}"
        );
        assert_eq!(
            get("/weak").await.unwrap().headers()["content-security-policy"],
            sandbox
        );
    }

    async fn start(
        grace_ms: u64,
    ) -> (
        std::net::SocketAddr,
        CancellationToken,
        tokio::task::JoinHandle<std::io::Result<()>>,
    ) {
        async fn slow(State(millis): State<u64>) -> &'static str {
            tokio::time::sleep(Duration::from_millis(millis)).await;
            "done"
        }
        let app = Router::new()
            .route("/slow", axum::routing::get(slow))
            .with_state(300u64)
            .route(
                "/stuck",
                axum::routing::get(|| async { std::future::pending::<&str>().await }),
            );
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let shutdown = CancellationToken::new();
        let server = tokio::spawn(serve(listener, app, shutdown.clone(), Duration::from_millis(grace_ms)));
        (addr, shutdown, server)
    }

    #[tokio::test]
    async fn a_request_in_flight_when_shutdown_starts_is_answered_before_the_server_stops() {
        let (addr, shutdown, server) = start(5_000).await;
        let request = tokio::spawn(crate::testing::raw_get(addr, "/slow"));
        tokio::time::sleep(Duration::from_millis(100)).await;
        shutdown.cancel();
        assert_eq!(request.await.unwrap().unwrap(), (200, "done".to_string()));
        server.await.unwrap().unwrap();
        assert!(
            crate::testing::raw_get(addr, "/slow").await.is_err(),
            "a stopped server accepts nothing"
        );
    }

    #[tokio::test]
    async fn a_request_that_outlives_the_grace_does_not_hold_shutdown_forever() {
        let (addr, shutdown, server) = start(200).await;
        let request = tokio::spawn(crate::testing::raw_get(addr, "/stuck"));
        tokio::time::sleep(Duration::from_millis(100)).await;
        shutdown.cancel();
        photolib_spawn::within(Duration::from_secs(3), server)
            .await
            .expect("the server stops after the grace")
            .unwrap()
            .unwrap();
        assert!(!request.is_finished(), "the stuck request never got an answer");
        request.abort();
    }
}
