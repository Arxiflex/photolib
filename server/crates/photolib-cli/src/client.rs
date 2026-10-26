//! The client side of photolibd's resumable uploads (ADR-0061): IETF resumable uploads with photolib's fields.

use std::{
    collections::hash_map::RandomState,
    hash::BuildHasher,
    path::Path,
    sync::atomic::{AtomicU64, Ordering::Relaxed},
    time::Duration,
};

use base64::Engine;
use buffa::Message;
use bytes::Bytes;
use http::{Method, Request, Response, StatusCode};
use http_body_util::{BodyExt, Full};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{Client as Http, connect::HttpConnector},
    rt::TokioExecutor,
};
use photolib_proto::proto::photolib::api::v1::ErrorDetail;
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use url::Url;
use uuid::Uuid;

/// The largest append, as the apps send them: through Cloudflare's 100 MB request cap (design 16 §2). A proxy's 413
/// halves it, down to 64 KiB.
const APPEND: u64 = 8 << 20;
const MIN_APPEND: u64 = 64 << 10;
const RATE_LIMITED: &str = "api_key.rate_limited";

/// Why a request failed.
#[derive(Debug)]
pub enum Error {
    /// The network, a proxy or a timeout: the server may never have seen it.
    Unreachable(String),
    /// photolibd's answer: a Connect code and a reason code such as `quota.exceeded`.
    Server { code: String, reason: String },
    /// Reading the file or writing the journal.
    Local(String),
}

impl Error {
    /// Whether every further file would fail too: the server is gone, or refuses this key, library or quota.
    pub fn stops_run(&self) -> bool {
        match self {
            Error::Unreachable(_) => true,
            Error::Server { code, .. } => {
                ["unauthenticated", "permission_denied", "resource_exhausted"].contains(&code.as_str())
            }
            Error::Local(_) => false,
        }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Unreachable(why) => write!(f, "unreachable: {why}"),
            Error::Server { code, reason } => write!(f, "{code}: {reason}"),
            Error::Local(why) => write!(f, "{why}"),
        }
    }
}

pub struct Client {
    http: Http<HttpsConnector<HttpConnector>, Full<Bytes>>,
    /// The server's URL, ending in `/`.
    base: Url,
    token: String,
    library: Uuid,
    append: AtomicU64,
    /// The wait after the first failure in a row; the n-th waits n times as long. Beyond the key's rate, the unit of
    /// [`rate_wait`].
    backoff: Duration,
}

impl Client {
    pub fn new(server: &str, library: Uuid, token: String) -> Result<Client, String> {
        let mut base = Url::parse(server).map_err(|e| format!("--server {server}: {e}"))?;
        if !base.path().ends_with('/') {
            base.set_path(&format!("{}/", base.path()));
        }
        let provider = std::sync::Arc::new(rustls::crypto::ring::default_provider());
        let connector = hyper_rustls::HttpsConnectorBuilder::new()
            .with_provider_and_native_roots(provider)
            .map_err(|e| format!("cannot load the system's TLS roots: {e}"))?
            .https_or_http()
            .enable_http1()
            .build();
        Ok(Client {
            http: Http::builder(TokioExecutor::new()).build(connector),
            base,
            token,
            library,
            append: AtomicU64::new(APPEND),
            backoff: Duration::from_secs(1),
        })
    }

    /// Creates an upload of `length` bytes with this BLAKE3 hash; returns its path on the server, which stays valid
    /// when the server is reached at another address.
    pub async fn create(&self, length: u64, hash: &str) -> Result<String, Error> {
        let url = self.base.join("upload").expect("a relative path");
        let headers = [
            ("upload-complete", "?0".into()),
            ("upload-length", length.to_string()),
            ("photolib-library", self.library.to_string()),
            ("photolib-hash", hash.into()),
        ];
        let response = retry(self.backoff, async |_| {
            let response = self.send(Method::POST, &url, &headers, Bytes::new()).await?;
            match response.status() {
                StatusCode::CREATED => Ok(response),
                _ => Err(failure(response)),
            }
        });
        let response = response.await?;
        let location = response.headers().get(http::header::LOCATION);
        let location = location.and_then(|value| value.to_str().ok()).unwrap_or_default();
        let upload = url.join(location).map_err(|e| unreachable(location, e))?;
        match upload.as_str().strip_prefix(self.base.as_str()) {
            Some(path) if !location.is_empty() => Ok(path.into()),
            _ => Err(Error::Unreachable(format!("an upload at {upload}"))),
        }
    }

    /// How many bytes of `upload` the server has, or None once it is complete.
    pub async fn offset(&self, upload: &str) -> Result<Option<u64>, Error> {
        let url = self.url(upload)?;
        let response = self.send(Method::HEAD, &url, &[], Bytes::new()).await?;
        let header = |name| response.headers().get(name).and_then(|v| v.to_str().ok());
        match (response.status(), header("upload-complete"), header("upload-offset")) {
            // A HEAD answer has no body to carry photolibd's error.
            (StatusCode::NOT_FOUND, _, _) => Err(Error::Server {
                code: "not_found".into(),
                reason: "upload.not_found".into(),
            }),
            (StatusCode::TOO_MANY_REQUESTS, _, _) => Err(Error::Server {
                code: "resource_exhausted".into(),
                reason: RATE_LIMITED.into(),
            }),
            (status, Some("?1"), _) if status.is_success() => Ok(None),
            (status, Some("?0"), Some(offset)) if status.is_success() => offset
                .parse()
                .map(Some)
                .map_err(|_| Error::Unreachable(format!("Upload-Offset: {offset}"))),
            _ => Err(failure(response)),
        }
    }

    /// Sends what the server lacks of `upload` from `file`, `length` bytes in all: from `offset` if known, else from
    /// where the server's copy ends. A lost connection, a proxy's page or a passing server error resumes from there,
    /// up to five times in a row without that offset moving, which the part of a failed append the server kept moves
    /// too (a slow uplink). Returns once the server has verified and stored every byte, and tells `progress` what it
    /// has before that.
    pub async fn upload(
        &self,
        upload: &str,
        file: &Path,
        mut offset: Option<u64>,
        length: u64,
        progress: &impl Fn(u64),
    ) -> Result<(), Error> {
        let mut file = tokio::fs::File::open(file).await.map_err(local)?;
        let url = self.url(upload)?;
        let mut at = 0;
        retry(self.backoff, async |failures| {
            let from = match offset.take() {
                Some(at) => at,
                None => match self.offset(upload).await? {
                    Some(at) => at,
                    None => return Ok(()),
                },
            };
            if from > at {
                *failures = 0;
            }
            at = from;
            loop {
                let size = self.append.load(Relaxed).min(length - at);
                let mut chunk = vec![0; size as usize];
                file.seek(std::io::SeekFrom::Start(at)).await.map_err(local)?;
                file.read_exact(&mut chunk).await.map_err(local)?;
                let last = at + size == length;
                let complete = if last { "?1" } else { "?0" };
                let headers = [
                    ("content-type", "application/partial-upload".into()),
                    ("upload-offset", at.to_string()),
                    ("upload-complete", complete.into()),
                ];
                let response = self.send(Method::PATCH, &url, &headers, chunk.into());
                let response = response.await?;
                if response.status() == StatusCode::PAYLOAD_TOO_LARGE && size > MIN_APPEND {
                    self.append.fetch_min(size / 2, Relaxed);
                    continue;
                }
                if !response.status().is_success() {
                    let error = failure(response);
                    if matches!(&error, Error::Server { reason, .. } if reason == RATE_LIMITED) {
                        // Refused before a byte was read: no HEAD, which would spend the key's next request.
                        offset = Some(at);
                    }
                    return Err(error);
                }
                if last {
                    return Ok(());
                }
                (at, *failures) = (at + size, 0);
                progress(at);
            }
        })
        .await
    }

    fn url(&self, upload: &str) -> Result<Url, Error> {
        self.base
            .join(upload)
            .map_err(|e| Error::Local(format!("{upload}: {e}")))
    }

    async fn send(
        &self,
        method: Method,
        url: &Url,
        headers: &[(&str, String)],
        body: Bytes,
    ) -> Result<Response<Bytes>, Error> {
        let mut request = Request::builder()
            .method(method)
            .uri(url.as_str())
            .header("upload-draft-interop-version", "10")
            .header("authorization", format!("Bearer {}", self.token));
        for (name, value) in headers {
            request = request.header(*name, value);
        }
        let request = request.body(Full::new(body)).map_err(|e| unreachable(url, e))?;
        let exchange = async {
            let (parts, body) = self.http.request(request).await?.into_parts();
            Ok::<_, hyper_util::client::legacy::Error>((parts, body))
        };
        let (parts, body) = tokio::time::timeout(Duration::from_secs(120), exchange)
            .await
            .map_err(|e| unreachable(url, e))?
            .map_err(|e| unreachable(url, e))?;
        let body = body.collect().await.map_err(|e| unreachable(url, e))?.to_bytes();
        Ok(Response::from_parts(parts, body))
    }
}

pub fn local(error: std::io::Error) -> Error {
    Error::Local(error.to_string())
}

/// Runs `attempt` again after a lost connection, a proxy's page, a conflict or a passing server failure, up to five
/// times in a row without progress, which `attempt` reports by zeroing the count it gets; and, never counted as a
/// failure, while the API key is beyond its rate, which lets requests through again within a minute.
async fn retry<T>(backoff: Duration, mut attempt: impl AsyncFnMut(&mut u32) -> Result<T, Error>) -> Result<T, Error> {
    let (mut failures, mut limited) = (0, 0);
    loop {
        let wait = match attempt(&mut failures).await {
            Err(Error::Server { reason, .. }) if reason == RATE_LIMITED => {
                limited = u32::saturating_add(limited, 1);
                rate_wait(backoff, limited)
            }
            Err(error) if resumable(&error) && failures < 4 => {
                failures += 1;
                backoff.saturating_mul(failures)
            }
            done => return done,
        };
        tokio::time::sleep(wait).await;
    }
}

/// The wait after the n-th answer in a row that the API key is beyond its rate: `unit` doubling up to 60 of them, in
/// the upper half of that at random, so that the run's jobs come back apart (ADR-0065).
fn rate_wait(unit: Duration, n: u32) -> Duration {
    let step = unit.saturating_mul(2_u32.saturating_pow(n.saturating_sub(1)).min(60));
    let random = RandomState::new().hash_one(n) >> 32;
    step.mul_f64(0.5 + f64::from(u32::try_from(random).unwrap_or_default()) / f64::from(u32::MAX) / 2.0)
}

/// Whether an upload goes on after `error`: the network, a proxy, a conflict or a passing server failure.
fn resumable(error: &Error) -> bool {
    match error {
        Error::Unreachable(_) => true,
        Error::Server { code, .. } => ["aborted", "unavailable", "internal"].contains(&code.as_str()),
        Error::Local(_) => false,
    }
}

fn unreachable(what: impl std::fmt::Display, error: impl std::fmt::Display) -> Error {
    Error::Unreachable(format!("{what}: {error}"))
}

/// What an answer that is not a success means: photolibd's Connect error, or a proxy's page.
fn failure(response: Response<Bytes>) -> Error {
    let json = response
        .headers()
        .get(http::header::CONTENT_TYPE)
        .is_some_and(|value| value.as_bytes().starts_with(b"application/json"));
    let error: Option<serde_json::Value> = json.then(|| serde_json::from_slice(response.body()).ok()).flatten();
    let Some(code) = error.as_ref().and_then(|e| e["code"].as_str()) else {
        return Error::Unreachable(format!("HTTP {}", response.status()));
    };
    let reason = error.as_ref().and_then(|e| {
        let value = e["details"][0]["value"].as_str()?;
        let bytes = base64::engine::general_purpose::STANDARD_NO_PAD
            .decode(value.trim_end_matches('='))
            .ok()?;
        Some(ErrorDetail::decode_from_slice(&bytes).ok()?.code)
    });
    Error::Server {
        code: code.into(),
        reason: reason.unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A HEAD answer has no body to say why: photolibd's 429 there is the API key's rate.
    #[tokio::test]
    async fn a_head_beyond_the_key_s_rate_is_rate_limited() {
        let busy = axum::routing::head(|| async { StatusCode::TOO_MANY_REQUESTS });
        let app = axum::Router::new().route("/upload/1", busy);
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await });
        let client = Client::new(&url, Uuid::nil(), "plk_".into()).unwrap();
        let error = client.offset("upload/1").await.unwrap_err();
        assert_eq!(error.to_string(), "resource_exhausted: api_key.rate_limited");
    }

    /// Beyond the key's rate the waits double from a second to a minute, each in the upper half of its step at
    /// random, and never count as failures.
    #[tokio::test(start_paused = true)]
    async fn beyond_the_key_s_rate_the_waits_double_up_to_a_minute() {
        let mut times = vec![];
        retry(Duration::from_secs(1), async |_| {
            times.push(tokio::time::Instant::now());
            match times.len() {
                ..10 => Err(Error::Server {
                    code: "resource_exhausted".into(),
                    reason: RATE_LIMITED.into(),
                }),
                _ => Ok(()),
            }
        })
        .await
        .unwrap();
        let waits: Vec<f64> = times.windows(2).map(|w| (w[1] - w[0]).as_secs_f64()).collect();
        let steps = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 60.0, 60.0, 60.0];
        assert_eq!(waits.len(), steps.len());
        for (wait, step) in waits.iter().zip(steps) {
            assert!((step / 2.0..=step).contains(wait), "waits {waits:?}, steps {steps:?}");
        }
    }

    #[test]
    fn jobs_beyond_the_key_s_rate_come_back_apart() {
        let waits: std::collections::HashSet<_> = (0..20).map(|_| rate_wait(Duration::from_secs(1), 7)).collect();
        assert!(waits.len() > 10, "{waits:?}");
    }

    /// photolibd behind a proxy that buffers requests, as nginx does, and whose connection to photolibd breaks `keep`
    /// bytes into each of the next `cuts` appends: photolibd keeps those, the proxy answers 502. `appends` are offsets.
    struct Upstream {
        kept: Vec<u8>,
        length: usize,
        cuts: usize,
        keep: usize,
        appends: Vec<usize>,
    }

    type Shared = std::sync::Arc<std::sync::Mutex<Upstream>>;

    async fn head(axum::extract::State(up): axum::extract::State<Shared>) -> impl axum::response::IntoResponse {
        let up = up.lock().unwrap();
        let complete = if up.kept.len() == up.length { "?1" } else { "?0" };
        let offset = up.kept.len().to_string();
        (
            StatusCode::NO_CONTENT,
            [("upload-offset", offset), ("upload-complete", complete.into())],
        )
    }

    async fn append(
        axum::extract::State(up): axum::extract::State<Shared>,
        headers: http::HeaderMap,
        body: axum::body::Body,
    ) -> StatusCode {
        let at = headers["upload-offset"].to_str().unwrap().parse().unwrap();
        let cut = {
            let mut up = up.lock().unwrap();
            up.appends.push(at);
            (up.cuts > 0).then(|| {
                up.cuts -= 1;
                up.keep
            })
        };
        let got = axum::body::to_bytes(body, usize::MAX).await.unwrap();
        up.lock().unwrap().kept.extend(&got[..cut.unwrap_or(got.len())]);
        if cut.is_some() {
            StatusCode::BAD_GATEWAY
        } else {
            StatusCode::NO_CONTENT
        }
    }

    /// Uploads a MiB through an [`Upstream`], retrying at once; returns the result, the upstream and the bytes.
    async fn upload_through(cuts: usize, keep: usize) -> (Result<(), Error>, Shared, Vec<u8>) {
        let bytes: Vec<u8> = (0..1 << 20).map(|i: usize| (i / 4096) as u8).collect();
        let file = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(file.path(), &bytes).unwrap();
        let (kept, length, appends) = (Vec::new(), bytes.len(), Vec::new());
        let upstream = Shared::new(
            Upstream {
                kept,
                length,
                cuts,
                keep,
                appends,
            }
            .into(),
        );
        let route = axum::routing::head(head).patch(append);
        let app = axum::Router::new()
            .route("/upload/1", route)
            .with_state(upstream.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await });
        let client = Client::new(&url, Uuid::nil(), "plk_".into()).unwrap();
        let client = Client {
            backoff: Duration::ZERO,
            ..client
        };
        let sent = client
            .upload("upload/1", file.path(), None, length as u64, &|_| {})
            .await;
        (sent, upstream, bytes)
    }

    /// On a slow uplink every append fails part-way at its deadline, which `send` reports as it does a broken
    /// connection or a proxy's page: what the server kept of each is progress.
    #[tokio::test]
    async fn what_a_failed_append_left_on_the_server_is_progress() {
        let (sent, upstream, bytes) = upload_through(6, 64 << 10).await;
        sent.unwrap();
        let up = upstream.lock().unwrap();
        assert_eq!(up.appends, (0..=6).map(|cut| cut * (64 << 10)).collect::<Vec<_>>());
        assert!(up.kept == bytes, "the server's copy differs");
    }

    #[tokio::test]
    async fn an_append_that_failed_before_the_server_kept_a_byte_is_no_progress() {
        let (sent, upstream, _) = upload_through(6, 0).await;
        assert_eq!(sent.unwrap_err().to_string(), "unreachable: HTTP 502 Bad Gateway");
        assert_eq!(
            upstream.lock().unwrap().appends,
            [0; 5],
            "five tries in a row, no sixth"
        );
    }
}
