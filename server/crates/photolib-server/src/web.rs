//! The web app (M2-25, ADR-0385): a `flutter build web` directory, `web_root`, served at `/` under the policy that
//! `tools/web_requests.py` runs the app under. `index.html` gets a nonce of its own in each response; every other file
//! streams from disk with an `ETag`, a `.br` or `.gz` beside it for a browser that accepts one, and one byte `Range`.

use std::{
    fs::Metadata,
    io::SeekFrom,
    path::{Path as FsPath, PathBuf},
    sync::Arc,
    time::UNIX_EPOCH,
};

use axum::{
    Router,
    body::Body,
    extract::Path,
    http::{
        HeaderMap, HeaderValue, StatusCode,
        header::{
            ACCEPT_ENCODING, ACCEPT_RANGES, CACHE_CONTROL, CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_RANGE,
            CONTENT_SECURITY_POLICY, CONTENT_TYPE, ETAG, IF_NONE_MATCH, RANGE, REFERRER_POLICY, VARY,
            X_CONTENT_TYPE_OPTIONS,
        },
    },
    response::{IntoResponse, Response},
    routing::get,
};
use base64::Engine;
use tokio::io::{AsyncReadExt, AsyncSeekExt};

/// What the web app runs under, the same policy `tools/web_requests.py` checks it against: the `@` stands where the
/// response's nonce goes.
const POLICY: &str = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'nonce-@'; \
                      worker-src 'self' blob:; connect-src 'self' blob:; img-src 'self' blob: data:; \
                      media-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; \
                      require-trusted-types-for 'script'; trusted-types flutter-js default";

/// Whether `policy` is the web app's, with some nonce, which the response middleware leaves alone.
pub fn is_own(policy: &str) -> bool {
    let (head, tail) = POLICY.split_once('@').unwrap_or_default();
    policy
        .strip_prefix(head)
        .and_then(|rest| rest.strip_suffix(tail))
        .is_some_and(|nonce| {
            !nonce.is_empty()
                && nonce
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        })
}

/// A nonce and the web app's policy with it.
fn policy() -> Result<(String, HeaderValue), StatusCode> {
    let mut random = [0u8; 16];
    getrandom::fill(&mut random).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let nonce = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random);
    let header = value(&POLICY.replace('@', &nonce))?;
    Ok((nonce, header))
}

fn value(text: &str) -> Result<HeaderValue, StatusCode> {
    HeaderValue::from_str(text).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

/// The app in `dir`, at `/`. A path that names no file and has no extension is a route of the app and gets
/// `index.html`; whatever is not a GET goes on to `rest`, the API, which the app's paths would answer with 405.
pub fn app(dir: PathBuf, rest: Router) -> Router {
    let dir = Arc::new(dir);
    let serve = move |path: Option<Path<String>>, request: HeaderMap| {
        let dir = dir.clone();
        async move {
            let path = path.map_or_else(String::new, |Path(path)| path);
            respond(&dir, &path, &request)
                .await
                .unwrap_or_else(IntoResponse::into_response)
        }
    };
    Router::new()
        .route("/", get(serve.clone()).fallback_service(rest.clone()))
        .route("/{*path}", get(serve).fallback_service(rest))
}

async fn respond(dir: &FsPath, path: &str, request: &HeaderMap) -> Result<Response, StatusCode> {
    let mut file = dir.to_path_buf();
    for part in path.split('/').filter(|part| !part.is_empty()) {
        if part == ".." || part == "." || part.contains(['\\', '\0']) {
            return Err(StatusCode::NOT_FOUND);
        }
        file.push(part);
    }
    let name = path.rsplit('/').next().unwrap_or_default();
    if name.is_empty() || name == "index.html" || !name.contains('.') {
        return page(&dir.join("index.html")).await;
    }
    asset(&file, name, request).await
}

async fn page(index: &FsPath) -> Result<Response, StatusCode> {
    let bytes = tokio::fs::read(index).await.map_err(|_| StatusCode::NOT_FOUND)?;
    let (nonce, policy) = policy()?;
    let html = String::from_utf8_lossy(&bytes).replace("CSP_NONCE", &nonce);
    let headers = [
        (CONTENT_TYPE, HeaderValue::from_static("text/html; charset=utf-8")),
        (CONTENT_SECURITY_POLICY, policy),
        (REFERRER_POLICY, HeaderValue::from_static("no-referrer")),
        (X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff")),
        (CACHE_CONTROL, HeaderValue::from_static("no-cache")),
    ];
    Ok((headers, html).into_response())
}

fn content_type(name: &str) -> &'static str {
    match name.rsplit('.').next().unwrap_or_default() {
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "wasm" => "application/wasm",
        "json" | "map" => "application/json",
        "webmanifest" => "application/manifest+json",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "svg" => "image/svg+xml",
        "ico" => "image/x-icon",
        "woff2" => "font/woff2",
        "woff" => "font/woff",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        "txt" => "text/plain; charset=utf-8",
        _ => "application/octet-stream",
    }
}

/// The encodings a request accepts (`Accept-Encoding` with a quality above 0).
fn accepted(request: &HeaderMap) -> Vec<String> {
    let header = request.get(ACCEPT_ENCODING).and_then(|value| value.to_str().ok());
    header
        .unwrap_or_default()
        .split(',')
        .filter_map(|item| {
            let (name, params) = item.split_once(';').unwrap_or((item, ""));
            let refused = params
                .trim()
                .strip_prefix("q=")
                .is_some_and(|q| q.trim().parse::<f32>() == Ok(0.0));
            (!refused).then(|| name.trim().to_ascii_lowercase())
        })
        .collect()
}

/// What a request's `Range` asks of a file of `len` bytes.
#[derive(Debug, PartialEq)]
enum Wanted {
    /// The whole file: no range, several, another unit or a malformed one.
    Whole,
    /// The bytes from the first to the last, both included.
    Part(u64, u64),
    /// A range beyond the file.
    Refused,
}

fn wanted(request: &HeaderMap, len: u64) -> Wanted {
    let spec = request
        .get(RANGE)
        .and_then(|value| value.to_str().ok())
        .and_then(|spec| spec.strip_prefix("bytes="));
    let Some((from, to)) = spec
        .filter(|spec| !spec.contains(','))
        .and_then(|spec| spec.split_once('-'))
    else {
        return Wanted::Whole;
    };
    let (from, to) = (from.trim(), to.trim());
    let end = len.saturating_sub(1);
    let span = match (from.parse::<u64>(), to.parse::<u64>()) {
        (Err(_), Ok(n)) if from.is_empty() => (n > 0).then_some((len.saturating_sub(n), end)),
        (Ok(a), Ok(b)) => (a <= b).then_some((a, b.min(end))),
        (Ok(a), Err(_)) if to.is_empty() => Some((a, end)),
        _ => return Wanted::Whole,
    };
    match span {
        Some((a, b)) if a < len => Wanted::Part(a, b),
        _ => Wanted::Refused,
    }
}

/// The file to send, with its encoding: a `.br` or `.gz` beside `file` that the request accepts, else `file`.
async fn choose(file: &FsPath, request: &HeaderMap) -> Option<(&'static str, PathBuf, Metadata)> {
    let accepts = accepted(request);
    for (encoding, suffix) in [("br", ".br"), ("gzip", ".gz")] {
        if accepts.iter().any(|accepted| accepted == encoding) {
            let mut path = file.as_os_str().to_owned();
            path.push(suffix);
            if let Ok(meta) = tokio::fs::metadata(&path).await
                && meta.is_file()
            {
                return Some((encoding, PathBuf::from(path), meta));
            }
        }
    }
    let meta = tokio::fs::metadata(file).await.ok()?;
    meta.is_file().then(|| ("identity", file.to_path_buf(), meta))
}

/// A tag that changes with the file and its encoding.
fn tag(meta: &Metadata, encoding: &str) -> String {
    let modified = meta.modified().ok().and_then(|at| at.duration_since(UNIX_EPOCH).ok());
    format!(
        "\"{:x}-{:x}-{encoding}\"",
        meta.len(),
        modified.map_or(0, |at| at.as_nanos())
    )
}

fn unchanged(request: &HeaderMap, tag: &str) -> bool {
    let given = request.get(IF_NONE_MATCH).and_then(|value| value.to_str().ok());
    given.is_some_and(|tags| {
        tags.split(',')
            .map(str::trim)
            .any(|t| t == "*" || t.strip_prefix("W/").unwrap_or(t) == tag)
    })
}

/// A file of the build, streamed.
async fn asset(file: &FsPath, name: &str, request: &HeaderMap) -> Result<Response, StatusCode> {
    let (encoding, path, meta) = choose(file, request).await.ok_or(StatusCode::NOT_FOUND)?;
    let tag = tag(&meta, encoding);
    let mut headers = HeaderMap::new();
    headers.insert(ETAG, value(&tag)?);
    headers.insert(VARY, HeaderValue::from_static("accept-encoding"));
    headers.insert(CACHE_CONTROL, HeaderValue::from_static("no-cache"));
    headers.insert(X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    headers.insert(ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    // A worker runs under the policy of its script, never the sandbox of photolibd's other responses.
    headers.insert(CONTENT_SECURITY_POLICY, policy()?.1);
    if unchanged(request, &tag) {
        return Ok((StatusCode::NOT_MODIFIED, headers).into_response());
    }
    headers.insert(CONTENT_TYPE, HeaderValue::from_static(content_type(name)));
    if encoding != "identity" {
        headers.insert(CONTENT_ENCODING, HeaderValue::from_static(encoding));
    }
    let len = meta.len();
    let (status, first, length) = match wanted(request, len) {
        Wanted::Whole => (StatusCode::OK, 0, len),
        Wanted::Part(first, last) => {
            headers.insert(CONTENT_RANGE, value(&format!("bytes {first}-{last}/{len}"))?);
            (
                StatusCode::PARTIAL_CONTENT,
                first,
                last.saturating_sub(first).saturating_add(1),
            )
        }
        Wanted::Refused => {
            headers.insert(CONTENT_RANGE, value(&format!("bytes */{len}"))?);
            return Ok((StatusCode::RANGE_NOT_SATISFIABLE, headers).into_response());
        }
    };
    headers.insert(CONTENT_LENGTH, HeaderValue::from(length));
    let mut open = tokio::fs::File::open(&path).await.map_err(|_| StatusCode::NOT_FOUND)?;
    open.seek(SeekFrom::Start(first))
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let body = Body::from_stream(tokio_util::io::ReaderStream::new(open.take(length)));
    Ok((status, headers, body).into_response())
}

#[cfg(test)]
mod tests;
