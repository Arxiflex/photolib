//! Deprecation and Sunset headers on deprecated procedures (RFC 9745, RFC 8594), logged with the calling client.

use std::time::{Duration, UNIX_EPOCH};

use axum::{
    extract::{Request, State},
    http::{HeaderValue, header::USER_AGENT},
    middleware::Next,
    response::Response,
};

/// A procedure clients should stop calling: deprecated since `deprecated_at`, removed at `sunset_at` (Unix seconds).
pub struct Deprecation {
    pub procedure: &'static str,
    pub deprecated_at: u64,
    pub sunset_at: u64,
}

/// The deprecated procedures; one is removed no earlier than the compatibility window (design 16 §5) after its
/// deprecation.
pub const DEPRECATIONS: &[Deprecation] = &[];

pub async fn headers(State(table): State<&'static [Deprecation]>, request: Request, next: Next) -> Response {
    let path = request.uri().path();
    let Some(deprecation) = table.iter().find(|entry| entry.procedure == path) else {
        return next.run(request).await;
    };
    let client = request.headers().get(USER_AGENT).and_then(|agent| agent.to_str().ok());
    tracing::info!(procedure = path, client, "a client called a deprecated procedure");
    let mut response = next.run(request).await;
    let sunset = httpdate::fmt_http_date(UNIX_EPOCH + Duration::from_secs(deprecation.sunset_at));
    for (name, value) in [
        ("deprecation", format!("@{}", deprecation.deprecated_at)),
        ("sunset", sunset),
    ] {
        let value = HeaderValue::try_from(value).expect("a date is a valid header value");
        response.headers_mut().insert(name, value);
    }
    response
}
