//! The Connect API of photolibd.

use std::{collections::HashSet, path::PathBuf, sync::Arc};

use axum::{
    extract::{Request, State},
    middleware::{Next, from_fn, from_fn_with_state},
    response::Response,
};
use connectrpc::{ConnectRpcService, Limits, RequestContext, ServiceRequest, ServiceResult};
use photolib_proto::{
    connect::photolib::api::v1::{
        AdminServiceExt, ApiKeyServiceExt, AuthServiceExt, EventServiceExt, FaceServiceExt, KeyServiceExt,
        SearchServiceExt, ServerInfoService, ServerInfoServiceExt, SetupServiceExt, SyncServiceExt, UserServiceExt,
        WebhookServiceExt,
    },
    proto::photolib::api::v1::{AuthMethod, GetServerInfoRequest, GetServerInfoResponse, OidcProvider},
};

mod account_keys;
mod admin;
mod auth;
mod authz;
mod deprecation;
mod errors;
mod events;
mod faces;
mod keys;
mod oidc;
mod search;
mod sync;
mod users;
pub use admin::Admin;
pub use auth::{Auth, Caller, Sessions};
pub use authz::{ROUTES, Routes};
pub use deprecation::{DEPRECATIONS, Deprecation};
pub use errors::ApiError;
pub use sync::{Sync, hints};
pub use users::Users;

/// The version of `photolib.api.v1` this server implements.
pub const API_VERSION: &str = "1.0";
/// The oldest app this server serves; no app is released yet.
pub const MIN_CLIENT_VERSION: &str = "0.0.0";
/// The behaviours clients feature-detect (design 16 §5), as sorted lowercase dotted names. A capability stays for the
/// whole compatibility window once released; a changed behaviour gets a new name (`sync.stream.v2`).
pub const CAPABILITIES: &[&str] = &[
    // Errors are a Connect code plus a `photolib.api.v1.ErrorDetail`, never prose (F-13).
    "error.detail.v1",
    // `EventService` and `WebhookService`: ids-only events of standard libraries, signed webhooks (ADR-0263).
    "events.v1",
    // `FaceService`: the account's face consent, which alone starts any processing of faces, and the faces of an asset
    // (ADR-0389).
    "faces.v1",
    // `SearchService.SearchText`: the assets whose pictures hold a text OCR read (M5-08).
    "search.text.v1",
    // `GET /events`: Server-Sent Events naming the streams a change advanced (ADR-0225).
    "sync.hints.v1",
    // `SyncService.PushMutations`: outbox mutations applied once, merged by hybrid logical clock (ADR-0265).
    "sync.mutations.v1",
    // `SyncService`: streams with opaque cursors, snapshots handing over to the log, `RESET_REQUIRED` (ADR-0091).
    "sync.stream.v1",
    // `SyncService.EmptyTrash`, albums made on devices and per-surface hiding by field edit (ADR-0386).
    "sync.trash.v1",
    // `VersionEdit` mutations and `assets.current_version_id` as a field: edit recipes and the version history
    // (ADR-0391).
    "sync.versions.v1",
    // Resumable uploads on `/upload` (IETF draft-ietf-httpbis-resumable-upload-13, ADR-0061).
    "upload.rufh",
];

/// The procedure that answered a request, on its response: the route of the request metrics.
#[derive(Clone)]
pub struct Procedure(pub String);

/// Serves Connect services the way photolibd does: binary and JSON, identity, gzip and zstd, within `limits`. The
/// conformance server (`crates/photolib-conformance`) runs the official Connect suite through this function.
pub fn connect(services: connectrpc::Router, limits: Limits) -> ConnectRpcService {
    ConnectRpcService::new(services).with_limits(limits)
}

async fn tag_procedure(State(procedures): State<Arc<HashSet<String>>>, request: Request, next: Next) -> Response {
    let procedure = procedures.get(request.uri().path()).cloned();
    let mut response = next.run(request).await;
    if let Some(path) = procedure {
        response.extensions_mut().insert(Procedure(path));
    }
    response
}

struct ServerInfo {
    epoch: String,
    auth_methods: Vec<AuthMethod>,
    oidc_providers: Vec<OidcProvider>,
}

#[allow(refining_impl_trait)]
impl ServerInfoService for ServerInfo {
    async fn get_server_info(
        &self,
        _ctx: RequestContext,
        _request: ServiceRequest<'_, GetServerInfoRequest>,
    ) -> ServiceResult<GetServerInfoResponse> {
        Ok(GetServerInfoResponse {
            api_version: API_VERSION.into(),
            min_client_version: MIN_CLIENT_VERSION.into(),
            capabilities: CAPABILITIES.iter().map(|name| name.to_string()).collect(),
            epoch: self.epoch.clone(),
            auth_methods: self.auth_methods.iter().map(|&method| method.into()).collect(),
            oidc_providers: self.oidc_providers.clone(),
            ..Default::default()
        }
        .into())
    }
}

/// photolibd's API for an instance in `epoch` (`instance::epoch`), with the setup, user, API key, key and sync services
/// when `users` is given, sign-in and the setup link's page when `auth` is (and the passkey relay when it offers
/// passkeys) and the admin console's when `admin` is.
pub fn api(epoch: String, users: Option<Arc<Users>>, auth: Option<Arc<Auth>>, admin: Option<Admin>) -> axum::Router {
    api_with(epoch, users, auth, admin, ROUTES, DEPRECATIONS, None)
}

/// `api` with the web app built in `web` (`web_root`) at `/` in place of the setup link's page.
pub fn api_serving(
    epoch: String,
    users: Option<Arc<Users>>,
    auth: Option<Arc<Auth>>,
    admin: Option<Admin>,
    web: Option<PathBuf>,
) -> axum::Router {
    api_with(epoch, users, auth, admin, ROUTES, DEPRECATIONS, web)
}

fn api_with(
    epoch: String,
    users: Option<Arc<Users>>,
    auth: Option<Arc<Auth>>,
    admin: Option<Admin>,
    routes: Routes,
    deprecations: &'static [Deprecation],
    web: Option<PathBuf>,
) -> axum::Router {
    let oidc_providers: Vec<OidcProvider> = auth
        .iter()
        .filter_map(|auth| auth.oidc.as_ref())
        .flat_map(|oidc| oidc.providers())
        .map(|(id, name)| OidcProvider {
            id: id.into(),
            name: name.into(),
            ..Default::default()
        })
        .collect();
    let opaque = auth.iter().map(|_| AuthMethod::AUTH_METHOD_OPAQUE);
    let passkey = auth
        .iter()
        .filter(|auth| auth.passkeys())
        .map(|_| AuthMethod::AUTH_METHOD_PASSKEY);
    let oidc = (!oidc_providers.is_empty()).then_some(AuthMethod::AUTH_METHOD_OIDC);
    let info = Arc::new(ServerInfo {
        epoch,
        auth_methods: opaque.chain(passkey).chain(oidc).collect(),
        oidc_providers,
    });
    let epoch = info.epoch.clone();
    let (passwords, relay) = (auth.is_some(), auth.as_ref().is_some_and(|auth| auth.passkeys()));
    let mut services = info.register(connectrpc::Router::new());
    if let Some(users) = &users {
        let sync = Sync::new(users.accounts.pool().clone(), epoch);
        services = SyncServiceExt::register(Arc::new(sync), services);
        services = SetupServiceExt::register(users.clone(), services);
        services = UserServiceExt::register(users.clone(), services);
        services = ApiKeyServiceExt::register(users.clone(), services);
        services = EventServiceExt::register(users.clone(), services);
        services = SearchServiceExt::register(users.clone(), services);
        services = WebhookServiceExt::register(users.clone(), services);
        services = FaceServiceExt::register(users.clone(), services);
        services = KeyServiceExt::register(users.clone(), services);
    }
    if let Some(auth) = auth {
        services = AuthServiceExt::register(auth, services);
    }
    let seen = admin.as_ref().and_then(Admin::seen);
    if let Some(admin) = admin {
        services = AdminServiceExt::register(Arc::new(admin), services);
    }
    let mut router = serve(services, routes, users, deprecations);
    if relay {
        router = router.merge(crate::relay::routes());
    }
    router = match web {
        Some(dir) => {
            let rest = router.clone();
            router.merge(crate::web::app(dir, rest))
        }
        None if passwords => router.merge(crate::relay::setup()),
        None => router,
    };
    match seen {
        Some(seen) => router.layer(from_fn_with_state(seen, crate::doctor::observe)),
        None => router,
    }
}

/// `services` behind photolibd's route rules, deprecation headers and error edge.
fn serve(
    services: connectrpc::Router,
    routes: Routes,
    users: Option<Arc<Users>>,
    deprecations: &'static [Deprecation],
) -> axum::Router {
    let authorize = authz::Authorize { routes, users };
    let procedures: Arc<HashSet<String>> = Arc::new(services.methods().map(|path| format!("/{path}")).collect());
    axum::Router::new()
        .fallback_service(connect(services, Limits::default()).with_interceptor(authorize))
        .layer(from_fn_with_state(procedures, tag_procedure))
        .layer(from_fn_with_state(deprecations, deprecation::headers))
        .layer(from_fn(errors::no_prose))
}

#[cfg(test)]
mod tests {
    use axum::{
        body::Body,
        http::{HeaderMap, Request},
    };
    use tower::ServiceExt;

    use uuid::Uuid;

    use super::*;
    use crate::{
        config::{Log, LogFormat},
        testing::Capture,
    };

    const GET_SERVER_INFO: &str = "/photolib.api.v1.ServerInfoService/GetServerInfo";

    async fn call(deprecations: &'static [Deprecation]) -> HeaderMap {
        let request = Request::post(GET_SERVER_INFO)
            .header("content-type", "application/json")
            .header("user-agent", "photolib-app/1.4.2 (android)")
            .body(Body::from("{}"))
            .unwrap();
        let response = api_with(Uuid::now_v7().to_string(), None, None, None, ROUTES, deprecations, None)
            .oneshot(request)
            .await
            .unwrap();
        assert!(response.status().is_success());
        response.headers().clone()
    }

    #[tokio::test]
    async fn a_deprecated_procedure_answers_with_deprecation_and_sunset_and_logs_the_client() {
        let capture = Capture::default();
        let log = Log {
            format: LogFormat::Json,
            filter: "info".into(),
        };
        let _guards = capture.set_default(&log);
        let headers = call(&[Deprecation {
            procedure: GET_SERVER_INFO,
            deprecated_at: 1_798_761_600,
            sunset_at: 1_830_297_600,
        }])
        .await;
        assert_eq!(headers["deprecation"], "@1798761600");
        assert_eq!(headers["sunset"], "Sat, 01 Jan 2028 00:00:00 GMT");
        let log = capture.text();
        assert!(
            log.contains(GET_SERVER_INFO) && log.contains("photolib-app/1.4.2 (android)"),
            "{log}"
        );
    }

    #[tokio::test]
    async fn a_procedure_that_is_not_deprecated_has_neither_header() {
        let headers = call(&[]).await;
        assert!(headers.get("deprecation").is_none() && headers.get("sunset").is_none());
    }

    #[tokio::test]
    async fn photolibds_pages_and_what_they_load_are_served_beneath_any_base_path_where_they_are_on() {
        let pool = sqlx::PgPool::connect_lazy("postgres://nobody@localhost/none").unwrap();
        let auth = |passkeys: bool| {
            let auth = Auth::new(pool.clone(), opaque_ke::ServerSetup::new(&mut rand_core::OsRng));
            let rp = crate::webauthn::RelyingParty::from_url("https://photos.example.com");
            Some(Arc::new(auth.with_passkeys(rp.filter(|_| passkeys))))
        };
        let get = |app: axum::Router, path: String| async move {
            let request = Request::get(path).body(Body::empty()).unwrap();
            app.oneshot(request).await.unwrap()
        };
        // The passkey relay where passkeys are on, and the page a password setup link opens wherever passwords are.
        let off = |auth| api(Uuid::now_v7().to_string(), None, auth, None);
        assert!(
            get(off(auth(false)), "/passkey".into())
                .await
                .status()
                .is_client_error()
        );
        assert!(get(off(None), "/".into()).await.status().is_client_error());
        // The web app replaces the setup page at `/` and keeps the API's routes.
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("index.html"), "app").unwrap();
        let web = api_with(
            Uuid::now_v7().to_string(),
            None,
            auth(true),
            None,
            ROUTES,
            DEPRECATIONS,
            Some(dir.path().into()),
        );
        let (root, passkey) = (
            get(web.clone(), "/".into()).await,
            get(web.clone(), "/passkey".into()).await,
        );
        assert_eq!(axum::body::to_bytes(root.into_body(), 99).await.unwrap(), "app");
        assert_eq!(passkey.headers()["content-security-policy"], crate::relay::CSP);
        let info = "/photolib.api.v1.ServerInfoService/GetServerInfo";
        let call = Request::post(info)
            .header("content-type", "application/json")
            .body(Body::from("{}"))
            .unwrap();
        assert_eq!(web.oneshot(call).await.unwrap().status(), axum::http::StatusCode::OK);
        for base in ["/", "/photos"] {
            let app = || crate::http::under(base, api(Uuid::now_v7().to_string(), None, auth(true), None));
            let at = url::Url::parse("https://photos.example.com").unwrap();
            for page in ["passkey", ""] {
                let page = at.join(&format!("{}/{page}", base.trim_end_matches('/'))).unwrap();
                let response = get(app(), page.path().into()).await;
                assert!(response.status().is_success(), "{page}");
                assert_eq!(response.headers()["content-security-policy"], crate::relay::CSP);
                let body = axum::body::to_bytes(response.into_body(), 1 << 16).await;
                let html = String::from_utf8(body.unwrap().to_vec()).unwrap();
                // Every script and stylesheet it loads.
                for (attribute, kind) in [(r#"<script src=""#, "javascript"), (r#"stylesheet" href=""#, "css")] {
                    let Some(src) = html.split(attribute).nth(1) else {
                        continue;
                    };
                    let resource = page.join(&src[..src.find('"').unwrap()]).unwrap();
                    let response = get(app(), resource.path().into()).await;
                    assert!(response.status().is_success(), "{resource} from {page}");
                    assert_eq!(
                        response.headers()["content-type"],
                        format!("text/{kind}; charset=utf-8")
                    );
                }
            }
        }
    }
}
