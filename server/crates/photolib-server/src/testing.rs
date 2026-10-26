use std::{
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use async_trait::async_trait;
use uuid::Uuid;

use crate::{
    config::{Config, Database as DatabaseConfig, Log, Traces},
    db::{Database, DbError, DbStats},
    jobs::JobQueue,
    role::Role,
    secret::Secret,
};

/// A valid configuration of these roles on `data_dir`, with a database that tests replace or never reach.
pub fn config(roles: &[Role], data_dir: &std::path::Path) -> Config {
    Config {
        config_version: 1,
        roles: roles.to_vec(),
        listen: "127.0.0.1:0".parse().unwrap(),
        base_path: "/".into(),
        web_root: None,
        trusted_proxies: vec!["127.0.0.1".parse().unwrap()],
        allow_insecure_http: false,
        discovery: false,
        data_dir: Some(data_dir.to_path_buf()),
        work_dir: None,
        allow_network_fs: false,
        database: DatabaseConfig {
            url: Some(Secret::new("postgres://x@db/x".into())),
            ..DatabaseConfig::default()
        },
        log: Log::default(),
        metrics: Default::default(),
        traces: Traces::default(),
        shutdown_grace_secs: 5,
        stores: Default::default(),
        placement: Default::default(),
        exiftool: vec![],
        ffmpeg_dir: None,
        tone_mapping: crate::tone::ToneMapping::default(),
        streaming: crate::config::Streaming::default(),
        oidc: Default::default(),
        external_roots: vec![],
        public_url: None,
        outbound: None,
        webhooks: false,
        ml: crate::config::Ml::default(),
        opaque_key_file: Some(data_dir.with_extension("opaque.key")),
        settings: crate::config::Pinned::default(),
    }
}

/// The configuration of an S3 store.
pub fn store(s3: &photolib_storage::s3::S3Config) -> crate::config::Store {
    crate::config::Store {
        kind: crate::config::StoreKind::S3,
        endpoint: s3.endpoint.clone(),
        bucket: s3.bucket.clone(),
        region: s3.region.clone(),
        prefix: s3.prefix.clone(),
        access_key_id: s3.access_key_id.clone(),
        secret_access_key: Secret::new(s3.secret_access_key.clone()),
        timeout_secs: 30,
        rehash_gib_per_month: None,
    }
}

pub fn assert_contains(message: &str, fragments: &[&str]) {
    for fragment in fragments {
        assert!(message.contains(fragment), "{fragment} missing from {message}");
    }
}

/// An in-memory database whose liveness and instance id the tests control.
#[derive(Default)]
pub struct FakeDb {
    pub id: Mutex<Option<Uuid>>,
    pub down: AtomicBool,
    pub lose_init_race: AtomicBool,
    pub hangs: AtomicBool,
    pub upgrading: Mutex<Vec<String>>,
    pub stats: Mutex<DbStats>,
    pub watermark: Mutex<(u64, u64)>,
    /// The retention of every purge, in order.
    pub purges: Mutex<Vec<Duration>>,
}

impl FakeDb {
    pub fn with_id(id: Uuid) -> Self {
        FakeDb {
            id: Mutex::new(Some(id)),
            ..FakeDb::default()
        }
    }

    pub fn set_down(&self, down: bool) {
        self.down.store(down, Ordering::SeqCst);
    }

    pub fn stored(&self) -> Option<Uuid> {
        *self.id.lock().unwrap()
    }

    fn check(&self) -> Result<(), DbError> {
        if self.down.load(Ordering::SeqCst) {
            Err("connection refused".into())
        } else {
            Ok(())
        }
    }
}

#[async_trait]
impl Database for FakeDb {
    async fn ping(&self) -> Result<(), DbError> {
        if self.hangs.load(Ordering::SeqCst) {
            std::future::pending::<()>().await;
        }
        self.check()
    }

    async fn instance_id(&self) -> Result<Option<Uuid>, DbError> {
        self.check()?;
        Ok(self.stored())
    }

    async fn init_instance_id(&self, id: Uuid) -> Result<bool, DbError> {
        self.check()?;
        let mut stored = self.id.lock().unwrap();
        if stored.is_some() || self.lose_init_race.load(Ordering::SeqCst) {
            return Ok(false);
        }
        *stored = Some(id);
        Ok(true)
    }

    async fn upgrading(&self) -> Result<Vec<String>, DbError> {
        self.check()?;
        Ok(self.upgrading.lock().unwrap().clone())
    }

    async fn stats(&self) -> Result<DbStats, DbError> {
        self.ping().await?;
        Ok(self.stats.lock().unwrap().clone())
    }

    async fn watermark(&self) -> Result<(u64, u64), DbError> {
        self.check()?;
        Ok(*self.watermark.lock().unwrap())
    }

    async fn purge_tombstones(&self, retention: Duration) -> Result<u64, DbError> {
        self.check()?;
        self.purges.lock().unwrap().push(retention);
        Ok(0)
    }

    async fn purge_mutations(&self, retention: Duration) -> Result<u64, DbError> {
        self.check()?;
        self.purges.lock().unwrap().push(retention);
        Ok(0)
    }
}

/// Sessions where `Authorization: Bearer <user id>` signs a request as that user, on no particular device.
pub struct BearerSessions;

#[async_trait]
impl crate::rpc::Sessions for BearerSessions {
    async fn caller(&self, headers: &axum::http::HeaderMap) -> Result<Option<crate::rpc::Caller>, DbError> {
        let bearer = headers
            .get("authorization")
            .and_then(|value| value.to_str().ok()?.strip_prefix("Bearer ")?.parse().ok());
        Ok(bearer.map(|user| crate::rpc::Caller {
            user,
            device: Uuid::nil(),
            session: Uuid::nil(),
            must_enrol: false,
        }))
    }
}

/// A job queue that records what happened to it, in order, in a log shared with the test.
pub struct FakeQueue {
    pub events: std::sync::Arc<Mutex<Vec<String>>>,
    pub fail: AtomicBool,
}

impl FakeQueue {
    pub fn new(events: &std::sync::Arc<Mutex<Vec<String>>>) -> Self {
        FakeQueue {
            events: events.clone(),
            fail: AtomicBool::new(false),
        }
    }
}

#[async_trait]
impl JobQueue for FakeQueue {
    async fn run(&self, role: Role, shutdown: tokio_util::sync::CancellationToken) {
        self.events.lock().unwrap().push(format!("run:{role}"));
        shutdown.cancelled().await;
    }

    async fn requeue_leased(&self, owner: &str) -> Result<u64, DbError> {
        if self.fail.load(Ordering::SeqCst) {
            return Err("queue unreachable".into());
        }
        self.events.lock().unwrap().push(format!("requeue:{owner}"));
        Ok(2)
    }
}

/// A GET over a raw TCP connection (no HTTP client in the dependencies); returns the status and the body.
pub async fn raw_get(addr: std::net::SocketAddr, path: &str) -> std::io::Result<(u16, String)> {
    raw(
        addr,
        format!("GET {path} HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n"),
    )
    .await
}

/// A POST of a JSON body, as a Connect client sends a unary call.
pub async fn raw_post_json(addr: std::net::SocketAddr, path: &str, body: &str) -> std::io::Result<(u16, String)> {
    let length = body.len();
    let head = format!("POST {path} HTTP/1.1\r\nHost: test\r\nConnection: close\r\n");
    let head = format!("{head}Content-Type: application/json\r\nContent-Length: {length}\r\n\r\n");
    raw(addr, format!("{head}{body}")).await
}

pub async fn raw(addr: std::net::SocketAddr, request: String) -> std::io::Result<(u16, String)> {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    let mut stream = tokio::net::TcpStream::connect(addr).await?;
    stream.write_all(request.as_bytes()).await?;
    let mut text = String::new();
    stream.read_to_string(&mut text).await?;
    let status = text
        .split_whitespace()
        .nth(1)
        .and_then(|code| code.parse().ok())
        .unwrap_or(0);
    let body = text.split_once("\r\n\r\n").map_or("", |(_, body)| body).to_string();
    Ok((status, body))
}

/// A unary Connect call in JSON with `Authorization: Bearer <bearer>`: the status, and the body or else the error's code,
/// reason and parameters.
pub async fn call(
    app: &axum::Router,
    procedure: &str,
    bearer: Option<&str>,
    body: serde_json::Value,
) -> (axum::http::StatusCode, serde_json::Value) {
    let (status, body) = post(app, procedure, bearer, "application/json", body.to_string()).await;
    let body: serde_json::Value = serde_json::from_slice(&body).unwrap();
    match status.is_success() {
        true => (status, body),
        false => (status, connect_error(&body)),
    }
}

/// A server-streaming Connect call in JSON: OK and the array of messages, or else the status a unary call would
/// have and the error, as `call` gives them.
pub async fn stream(
    app: &axum::Router,
    procedure: &str,
    bearer: Option<&str>,
    body: serde_json::Value,
) -> (axum::http::StatusCode, serde_json::Value) {
    use axum::http::StatusCode;

    let body = body.to_string();
    let mut envelope = vec![0];
    envelope.extend((body.len() as u32).to_be_bytes());
    envelope.extend(body.as_bytes());
    let (status, body) = post(app, procedure, bearer, "application/connect+json", envelope).await;
    assert_eq!(status, StatusCode::OK);
    let (mut messages, mut rest) = (vec![], &body[..]);
    while let [flags, a, b, c, d, tail @ ..] = rest {
        let (message, tail) = tail.split_at(u32::from_be_bytes([*a, *b, *c, *d]) as usize);
        let message: serde_json::Value = serde_json::from_slice(message).unwrap();
        rest = tail;
        if flags & 2 == 0 {
            messages.push(message);
        } else if let Some(failed) = message.get("error") {
            let status = match failed["code"].as_str() {
                Some("unauthenticated") => StatusCode::UNAUTHORIZED,
                Some("permission_denied") => StatusCode::FORBIDDEN,
                Some("invalid_argument") => StatusCode::BAD_REQUEST,
                _ => StatusCode::INTERNAL_SERVER_ERROR,
            };
            return (status, connect_error(failed));
        }
    }
    (StatusCode::OK, messages.into())
}

async fn post(
    app: &axum::Router,
    procedure: &str,
    bearer: Option<&str>,
    content_type: &str,
    body: impl Into<axum::body::Body>,
) -> (axum::http::StatusCode, bytes::Bytes) {
    use tower::ServiceExt;

    let mut request =
        axum::http::Request::post(format!("/photolib.api.v1.{procedure}")).header("content-type", content_type);
    if let Some(bearer) = bearer {
        request = request.header("authorization", format!("Bearer {bearer}"));
    }
    let response = app.clone().oneshot(request.body(body.into()).unwrap()).await.unwrap();
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), 1 << 30).await;
    (status, body.unwrap())
}

/// A Connect error body as `{"code", "reason", <params>}`.
pub fn connect_error(body: &serde_json::Value) -> serde_json::Value {
    use base64::Engine;
    use buffa::Message;
    use photolib_proto::proto::photolib::api::v1::ErrorDetail;

    let detail = base64::engine::general_purpose::STANDARD_NO_PAD
        .decode(body["details"][0]["value"].as_str().unwrap())
        .unwrap();
    let detail = ErrorDetail::decode_from_slice(&detail).unwrap();
    let mut error = serde_json::json!({ "code": body["code"], "reason": detail.code });
    for (name, value) in detail.params {
        error[name] = value.into();
    }
    error
}

/// Plays back fixed bytes as randomness.
pub struct Replay(pub Vec<u8>);

impl rand_core::RngCore for Replay {
    fn next_u32(&mut self) -> u32 {
        unreachable!()
    }

    fn next_u64(&mut self) -> u64 {
        unreachable!()
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        dest.copy_from_slice(&self.0[..dest.len()]);
        self.0.drain(..dest.len());
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand_core::Error> {
        self.fill_bytes(dest);
        Ok(())
    }
}

impl rand_core::CryptoRng for Replay {}

/// A log writer that keeps everything written to it, for tests that read the log.
#[derive(Clone, Default)]
pub struct Capture(std::sync::Arc<Mutex<Vec<u8>>>);

impl std::io::Write for Capture {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(bytes);
        Ok(bytes.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for Capture {
    type Writer = Capture;

    fn make_writer(&'a self) -> Capture {
        self.clone()
    }
}

impl Capture {
    /// Captures this thread's logs, filtered by `log`, until the guards drop. While a single dispatcher is
    /// live, tracing caches whether a callsite is enabled from the default of the thread that reaches it first,
    /// so another test's thread could switch off a shared one (the request span) here; a second live dispatcher
    /// makes tracing ask every live one instead.
    pub fn set_default(&self, log: &Log) -> (tracing::Dispatch, tracing::subscriber::DefaultGuard) {
        (
            tracing::Dispatch::new(tracing::subscriber::NoSubscriber::default()),
            tracing::subscriber::set_default(crate::logging::subscriber(log, self.clone(), None)),
        )
    }

    pub fn text(&self) -> String {
        String::from_utf8(self.0.lock().unwrap().clone()).unwrap()
    }
}

/// Signs ID tokens as an identity provider does, with a new key: RSA from `openssl`, ECDSA P-256 or Ed25519.
pub struct Signer {
    pub alg: &'static str,
    pub kid: String,
    key: SignerKey,
}

enum SignerKey {
    Rsa(ring::signature::RsaKeyPair),
    Ec(ring::signature::EcdsaKeyPair),
    Ed(ring::signature::Ed25519KeyPair),
}

impl Signer {
    /// `alg` is RS256 or PS256.
    pub fn rsa(alg: &'static str) -> Signer {
        let der = photolib_spawn::output(
            photolib_spawn::tool("openssl")
                .args(["genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048"])
                .args(["-outform", "DER"]),
            std::time::Duration::from_secs(120),
        );
        let key = ring::signature::RsaKeyPair::from_der(&der.stdout).unwrap();
        Signer::with(alg, SignerKey::Rsa(key))
    }

    pub fn es256() -> Signer {
        use ring::signature::{ECDSA_P256_SHA256_FIXED_SIGNING as P256, EcdsaKeyPair};
        let rng = ring::rand::SystemRandom::new();
        let pkcs8 = EcdsaKeyPair::generate_pkcs8(&P256, &rng).unwrap();
        let key = EcdsaKeyPair::from_pkcs8(&P256, pkcs8.as_ref(), &rng).unwrap();
        Signer::with("ES256", SignerKey::Ec(key))
    }

    pub fn eddsa() -> Signer {
        use ring::signature::Ed25519KeyPair;
        let pkcs8 = Ed25519KeyPair::generate_pkcs8(&ring::rand::SystemRandom::new()).unwrap();
        let key = Ed25519KeyPair::from_pkcs8(pkcs8.as_ref()).unwrap();
        Signer::with("EdDSA", SignerKey::Ed(key))
    }

    fn with(alg: &'static str, key: SignerKey) -> Signer {
        Signer {
            alg,
            kid: crate::auth::new_token()[..8].into(),
            key,
        }
    }

    /// The public key as a JWK.
    pub fn jwk(&self) -> serde_json::Value {
        use ring::signature::KeyPair;
        let b64 = |bytes: &[u8]| base64::Engine::encode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, bytes);
        let mut jwk = match &self.key {
            SignerKey::Rsa(key) => {
                let public = ring::rsa::PublicKeyComponents::<Vec<u8>>::from(key.public());
                serde_json::json!({ "kty": "RSA", "n": b64(&public.n), "e": b64(&public.e) })
            }
            SignerKey::Ec(key) => {
                let point = key.public_key().as_ref();
                serde_json::json!({ "kty": "EC", "crv": "P-256", "x": b64(&point[1..33]), "y": b64(&point[33..]) })
            }
            SignerKey::Ed(key) => {
                serde_json::json!({ "kty": "OKP", "crv": "Ed25519", "x": b64(key.public_key().as_ref()) })
            }
        };
        jwk["kid"] = self.kid.clone().into();
        jwk["alg"] = self.alg.into();
        jwk["use"] = "sig".into();
        jwk
    }

    /// A JWT of `claims` with the header `{alg, kid, typ}`.
    pub fn sign(&self, claims: &serde_json::Value) -> String {
        let header = serde_json::json!({ "alg": self.alg, "kid": self.kid, "typ": "JWT" });
        self.sign_with(&header, claims)
    }

    pub fn sign_with(&self, header: &serde_json::Value, claims: &serde_json::Value) -> String {
        use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD as B64};
        let input = format!("{}.{}", B64.encode(header.to_string()), B64.encode(claims.to_string()));
        let rng = ring::rand::SystemRandom::new();
        let signature = match &self.key {
            SignerKey::Rsa(key) => {
                let mut signature = vec![0; key.public().modulus_len()];
                let padding: &dyn ring::signature::RsaEncoding = match self.alg {
                    "PS256" => &ring::signature::RSA_PSS_SHA256,
                    _ => &ring::signature::RSA_PKCS1_SHA256,
                };
                key.sign(padding, &rng, input.as_bytes(), &mut signature).unwrap();
                signature
            }
            SignerKey::Ec(key) => key.sign(&rng, input.as_bytes()).unwrap().as_ref().to_vec(),
            SignerKey::Ed(key) => key.sign(input.as_bytes()).as_ref().to_vec(),
        };
        format!("{input}.{}", B64.encode(signature))
    }
}

/// An OpenID Connect provider on a loopback port that answers as Keycloak, Authentik, Authelia or Google do: discovery,
/// keys, a token endpoint that checks the client and PKCE as they do, and userinfo. `authorize` is the browser.
pub struct Idp {
    pub issuer: String,
    state: std::sync::Arc<Mutex<IdpState>>,
}

struct IdpState {
    issuer: String,
    client_id: String,
    secret: Option<String>,
    signer: Signer,
    /// Claims only userinfo returns, as Authelia's ID tokens carry none by default.
    userinfo_only: Vec<String>,
    /// Codes and access tokens issued: the redirect URI and challenge of a code, then the person's claims.
    codes: std::collections::HashMap<String, (String, String, serde_json::Value)>,
    tokens: std::collections::HashMap<String, serde_json::Value>,
    /// The paths requested, in order.
    seen: Vec<String>,
    /// Replaces the next answer of a path.
    next: std::collections::HashMap<String, (u16, String)>,
}

impl Idp {
    /// Serves an issuer at `path` (e.g. `/realms/home`), signing with `signer`, for a client with `secret`, or a public
    /// client without.
    pub async fn start(path: &str, signer: Signer, secret: Option<&str>, userinfo_only: &[&str]) -> Idp {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let issuer = format!("http://{}", listener.local_addr().unwrap()) + path;
        let state = std::sync::Arc::new(Mutex::new(IdpState {
            issuer: issuer.clone(),
            client_id: "photolib".into(),
            secret: secret.map(String::from),
            signer,
            userinfo_only: userinfo_only.iter().map(|claim| claim.to_string()).collect(),
            codes: Default::default(),
            tokens: Default::default(),
            seen: vec![],
            next: Default::default(),
        }));
        let app = axum::Router::new().fallback(idp_answer).with_state(state.clone());
        tokio::spawn(async move { axum::serve(listener, app).await });
        Idp { issuer, state }
    }

    /// photolibd's configuration of this provider.
    pub fn provider(&self) -> crate::config::OidcProvider {
        let state = self.state.lock().unwrap();
        crate::config::OidcProvider {
            name: "Test IdP".into(),
            issuer: self.issuer.clone(),
            client_id: state.client_id.clone(),
            client_secret: state.secret.clone().map(Secret::new),
            scopes: vec!["openid".into(), "profile".into(), "email".into(), "groups".into()],
            provision: true,
            link_by_email: false,
            roles: None,
        }
    }

    /// The person signs in at `url` as `claims`; returns the `state` and `code` the browser brings to the redirect URI.
    pub fn authorize(&self, url: &str, claims: serde_json::Value) -> (String, String) {
        let url = url::Url::parse(url).unwrap();
        let query: std::collections::HashMap<String, String> = url.query_pairs().into_owned().collect();
        let mut state = self.state.lock().unwrap();
        assert!(
            url.as_str()
                .starts_with(&format!("{}/authorize?", state.issuer.trim_end_matches('/'))),
            "{url}"
        );
        assert_eq!(
            (
                &query["response_type"][..],
                &query["client_id"],
                &query["code_challenge_method"][..]
            ),
            ("code", &state.client_id, "S256")
        );
        assert!(query["scope"].split(' ').any(|scope| scope == "openid"), "{url}");
        let mut claims = claims;
        claims["nonce"] = query["nonce"].clone().into();
        let code = crate::auth::new_token();
        let grant = (query["redirect_uri"].clone(), query["code_challenge"].clone(), claims);
        state.codes.insert(code.clone(), grant);
        (query["state"].clone(), code)
    }

    /// Answers the next request for `path` with `status` and `body`.
    pub fn answer_next(&self, path: &str, status: u16, body: impl Into<String>) {
        self.state
            .lock()
            .unwrap()
            .next
            .insert(path.into(), (status, body.into()));
    }

    pub fn seen(&self) -> Vec<String> {
        self.state.lock().unwrap().seen.clone()
    }
}

async fn idp_answer(
    axum::extract::State(state): axum::extract::State<std::sync::Arc<Mutex<IdpState>>>,
    request: axum::extract::Request,
) -> axum::response::Response {
    use axum::{http::StatusCode, response::IntoResponse};
    use base64::{Engine, engine::general_purpose::STANDARD};
    use serde_json::{Value, json};
    let path = request.uri().path().to_string();
    let bearer = request
        .headers()
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .map(String::from);
    let body = axum::body::to_bytes(request.into_body(), 1 << 20).await.unwrap();
    let form: std::collections::HashMap<String, String> = url::form_urlencoded::parse(&body).into_owned().collect();
    let mut state = state.lock().unwrap();
    state.seen.push(path.clone());
    if let Some((status, body)) = state.next.remove(&path) {
        return (StatusCode::from_u16(status).unwrap(), body).into_response();
    }
    let base = state.issuer.trim_end_matches('/').to_string();
    let error = |error: &str| (StatusCode::BAD_REQUEST, axum::Json(json!({ "error": error }))).into_response();
    let answer = match path.strip_prefix(url::Url::parse(&state.issuer).unwrap().path().trim_end_matches('/')) {
        Some("/.well-known/openid-configuration") => json!({
            "issuer": state.issuer,
            "authorization_endpoint": format!("{base}/authorize"),
            "token_endpoint": format!("{base}/token"),
            "userinfo_endpoint": format!("{base}/userinfo"),
            "jwks_uri": format!("{base}/jwks"),
            "response_types_supported": ["code"],
            "code_challenge_methods_supported": ["S256"],
        }),
        Some("/jwks") => json!({ "keys": [state.signer.jwk()] }),
        Some("/token") => {
            let client = match &state.secret {
                Some(secret) => {
                    let basic = format!("{}:{secret}", state.client_id);
                    bearer == Some(format!("Basic {}", STANDARD.encode(basic)))
                }
                None => form.get("client_id") == Some(&state.client_id),
            };
            if !client {
                return (
                    StatusCode::UNAUTHORIZED,
                    axum::Json(json!({ "error": "invalid_client" })),
                )
                    .into_response();
            }
            let Some((redirect_uri, challenge, claims)) = state.codes.remove(&form["code"]) else {
                return error("invalid_grant");
            };
            let verifier = form.get("code_verifier").map(String::as_str).unwrap_or_default();
            if form["grant_type"] != "authorization_code"
                || form["redirect_uri"] != redirect_uri
                || crate::oidc::challenge(verifier) != challenge
            {
                return error("invalid_grant");
            }
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs();
            let mut id_token = json!({
                "iss": state.issuer, "aud": state.client_id, "azp": state.client_id, "iat": now, "exp": now + 300,
            });
            for (claim, value) in claims.as_object().unwrap() {
                if !state.userinfo_only.contains(claim) {
                    id_token[claim] = value.clone();
                }
            }
            let access = crate::auth::new_token();
            state.tokens.insert(access.clone(), claims);
            json!({
                "access_token": access, "token_type": "Bearer", "expires_in": 300,
                "id_token": state.signer.sign(&id_token),
            })
        }
        Some("/userinfo") => {
            let token = bearer.as_deref().and_then(|bearer| bearer.strip_prefix("Bearer "));
            match token.and_then(|token| state.tokens.get(token)) {
                Some(Value::Object(claims)) => {
                    let mut claims = claims.clone();
                    claims.remove("nonce");
                    Value::Object(claims)
                }
                _ => return StatusCode::UNAUTHORIZED.into_response(),
            }
        }
        _ => return StatusCode::NOT_FOUND.into_response(),
    };
    axum::Json(answer).into_response()
}
