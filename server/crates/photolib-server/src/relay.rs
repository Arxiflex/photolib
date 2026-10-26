//! photolibd's own pages, on its origin: the passkey relay (M2-05, ADR-0088), where an app runs a WebAuthn ceremony
//! in the system browser and gets the credential back on its own address, and the page a password setup link opens
//! (ADR-0243), which hands the link to the app.

use axum::{
    Router,
    http::header::{CONTENT_SECURITY_POLICY, CONTENT_TYPE, HeaderName, REFERRER_POLICY, X_CONTENT_TYPE_OPTIONS},
    routing::get,
};

/// The page runs its own script and style and nothing else, is framed nowhere and sends nothing but the app's
/// navigation.
pub const CSP: &str = "default-src 'none'; script-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'; \
                       frame-ancestors 'none'; require-trusted-types-for 'script'";

const PAGE: [(HeaderName, &str); 4] = [
    (CONTENT_TYPE, "text/html; charset=utf-8"),
    (CONTENT_SECURITY_POLICY, CSP),
    (REFERRER_POLICY, "no-referrer"),
    (X_CONTENT_TYPE_OPTIONS, "nosniff"),
];
const SCRIPT: [(HeaderName, &str); 2] = [
    (CONTENT_TYPE, "text/javascript; charset=utf-8"),
    (X_CONTENT_TYPE_OPTIONS, "nosniff"),
];
const STYLE: [(HeaderName, &str); 2] = [
    (CONTENT_TYPE, "text/css; charset=utf-8"),
    (X_CONTENT_TYPE_OPTIONS, "nosniff"),
];

fn page(path: &str, html: &'static str, script: &str, js: &'static str) -> Router {
    Router::new()
        .route(path, get(move || async move { (PAGE, html) }))
        .route(script, get(move || async move { (SCRIPT, js) }))
}

/// The passkey relay.
pub fn routes() -> Router {
    page(
        "/passkey",
        include_str!("relay/passkey.html"),
        "/passkey.js",
        include_str!("relay/passkey.js"),
    )
}

/// The page at photolibd's address, where a password setup link points, until the web app (M2-25) takes its place.
pub fn setup() -> Router {
    page(
        "/",
        include_str!("relay/setup.html"),
        "/setup.js",
        include_str!("relay/setup.js"),
    )
    .route("/setup.css", get(|| async { (STYLE, include_str!("relay/setup.css")) }))
}
