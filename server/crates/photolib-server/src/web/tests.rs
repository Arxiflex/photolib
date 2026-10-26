use super::*;
use axum::{body::Body, http::Request};
use tower::ServiceExt;

async fn get(app: &Router, path: &str) -> (StatusCode, HeaderMap, String) {
    let request = Request::get(path).body(Body::empty()).unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let (status, headers) = (response.status(), response.headers().clone());
    let body = axum::body::to_bytes(response.into_body(), 1 << 20).await.unwrap();
    (status, headers, String::from_utf8_lossy(&body).into())
}

fn built() -> (tempfile::TempDir, Router) {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().join("web");
    std::fs::create_dir_all(root.join("canvaskit")).unwrap();
    std::fs::write(root.join("index.html"), r#"<script nonce="CSP_NONCE"></script>"#).unwrap();
    std::fs::write(root.join("main.dart.js"), "js").unwrap();
    std::fs::write(root.join("canvaskit/canvaskit.wasm"), "wasm").unwrap();
    std::fs::write(root.join("big.bin"), "0123456789").unwrap();
    std::fs::write(root.join("main.dart.js.br"), "brotli").unwrap();
    std::fs::write(root.join("main.dart.js.gz"), "gzip").unwrap();
    std::fs::write(root.join("only.css"), "css").unwrap();
    std::fs::write(root.join("only.css.gz"), "gz").unwrap();
    std::fs::write(dir.path().join("secret"), "secret").unwrap();
    let app = app(root, Router::new().fallback(|| async { "api" }));
    (dir, app)
}

fn nonce(csp: &str) -> &str {
    csp.split("'nonce-").nth(1).unwrap().split('\'').next().unwrap()
}

#[tokio::test]
async fn the_page_gets_a_fresh_nonce_that_its_policy_allows() {
    let (_dir, app) = built();
    let mut seen = Vec::new();
    for path in ["/", "/index.html", "/timeline/2026", "/"] {
        let (status, headers, html) = get(&app, path).await;
        assert!(status.is_success(), "{path}");
        let nonce = nonce(headers["content-security-policy"].to_str().unwrap()).to_string();
        assert_eq!(html, format!(r#"<script nonce="{nonce}"></script>"#), "{path}");
        assert_eq!(headers["cache-control"], "no-cache");
        seen.push(nonce);
    }
    seen.sort();
    seen.dedup();
    assert_eq!(seen.len(), 4, "a nonce per response");
}

#[tokio::test]
async fn the_policy_is_the_one_the_web_check_runs_the_app_under() {
    let (_dir, app) = built();
    let (_, headers, _) = get(&app, "/").await;
    let csp = headers["content-security-policy"].to_str().unwrap().to_string();
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tools/web_requests.py");
    let checked = std::fs::read_to_string(path).unwrap().replace("\"\n       \"", "");
    let expected = csp.replace(nonce(&csp), "{nonce}");
    assert!(checked.contains(&expected), "{expected}");
}

#[tokio::test]
async fn assets_are_served_by_type_and_nothing_outside_the_build_is() {
    let (_dir, app) = built();
    let (status, headers, body) = get(&app, "/main.dart.js").await;
    assert_eq!((status.as_u16(), body.as_str()), (200, "js"));
    assert_eq!(headers["content-type"], "text/javascript; charset=utf-8");
    assert_eq!(headers["x-content-type-options"], "nosniff");
    // A worker runs under the policy of its script, which photolibd's middleware would otherwise sandbox: no origin,
    // no Web Locks or OPFS, so the replica would not open.
    assert!(is_own(headers["content-security-policy"].to_str().unwrap()));
    let (_, headers, _) = get(&app, "/canvaskit/canvaskit.wasm").await;
    assert_eq!(headers["content-type"], "application/wasm");
    assert_eq!(get(&app, "/missing.js").await.0, 404);
    for path in [
        "/../secret",
        "/%2e%2e/secret",
        "/canvaskit/%2e%2e/%2e%2e/secret",
        "/canvaskit/..%2f..%2fsecret",
    ] {
        let (status, _, body) = get(&app, path).await;
        assert!(status.is_client_error() && !body.contains("secret"), "{path}: {status}");
    }
}

async fn send(app: &Router, path: &str, headers: &[(&str, &str)]) -> (StatusCode, HeaderMap, String) {
    let mut request = Request::get(path);
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    let response = app.clone().oneshot(request.body(Body::empty()).unwrap()).await.unwrap();
    let (status, headers) = (response.status(), response.headers().clone());
    let body = axum::body::to_bytes(response.into_body(), 1 << 20).await.unwrap();
    (status, headers, String::from_utf8_lossy(&body).into())
}

#[tokio::test]
async fn a_file_that_has_not_changed_is_answered_with_304() {
    let (_dir, app) = built();
    let (_, headers, _) = get(&app, "/main.dart.js").await;
    let etag = headers["etag"].to_str().unwrap().to_string();
    for given in [etag.clone(), format!("\"x\", {etag}"), "*".into()] {
        let (status, headers, body) = send(&app, "/main.dart.js", &[("if-none-match", &given)]).await;
        assert_eq!((status.as_u16(), body.as_str()), (304, ""), "{given}");
        assert_eq!(headers["etag"], etag.as_str());
    }
    let (status, _, body) = send(&app, "/main.dart.js", &[("if-none-match", "\"other\"")]).await;
    assert_eq!((status.as_u16(), body.as_str()), (200, "js"));
    // Another file, another tag.
    assert_ne!(get(&app, "/big.bin").await.1["etag"], etag.as_str());
}

#[tokio::test]
async fn a_precompressed_file_is_served_in_the_encoding_the_browser_accepts() {
    let (_dir, app) = built();
    for (accept, encoding, body) in [
        ("gzip, br", "br", "brotli"),
        ("gzip", "gzip", "gzip"),
        ("br;q=0, gzip", "gzip", "gzip"),
    ] {
        let (status, headers, text) = send(&app, "/main.dart.js", &[("accept-encoding", accept)]).await;
        assert_eq!((status.as_u16(), text.as_str()), (200, body), "{accept}");
        assert_eq!(headers["content-encoding"], encoding);
        assert_eq!(headers["content-type"], "text/javascript; charset=utf-8");
        assert_eq!(headers["vary"], "accept-encoding");
    }
    for accept in [None, Some("identity"), Some("deflate")] {
        let given: Vec<_> = accept.map(|a| ("accept-encoding", a)).into_iter().collect();
        let (_, headers, text) = send(&app, "/main.dart.js", &given).await;
        assert_eq!(text, "js");
        assert!(!headers.contains_key("content-encoding"));
        assert_eq!(headers["vary"], "accept-encoding");
    }
    // The tag tells the encodings apart; a file with only a .gz is plain for a browser that takes br alone.
    let tags: Vec<_> = futures::future::join_all(["br", "gzip", "identity"].map(|e| async move {
        let (_dir, app) = built();
        send(&app, "/main.dart.js", &[("accept-encoding", e)]).await.1["etag"].clone()
    }))
    .await;
    assert!(tags[0] != tags[1] && tags[1] != tags[2] && tags[0] != tags[2]);
    let (_, headers, text) = send(&app, "/only.css", &[("accept-encoding", "br")]).await;
    assert_eq!(
        (text.as_str(), headers.contains_key("content-encoding")),
        ("css", false)
    );
}

#[tokio::test]
async fn ranges_are_served_in_part_and_refused_beyond_the_file() {
    let (_dir, app) = built();
    let (status, headers, _) = get(&app, "/big.bin").await;
    assert_eq!(status.as_u16(), 200);
    assert_eq!(headers["accept-ranges"], "bytes");
    for (range, want, text) in [
        ("bytes=2-4", "bytes 2-4/10", "234"),
        ("bytes=7-", "bytes 7-9/10", "789"),
        ("bytes=-3", "bytes 7-9/10", "789"),
        ("bytes=8-99", "bytes 8-9/10", "89"),
        ("bytes=0-0", "bytes 0-0/10", "0"),
    ] {
        let (status, headers, body) = send(&app, "/big.bin", &[("range", range)]).await;
        assert_eq!((status.as_u16(), body.as_str()), (206, text), "{range}");
        assert_eq!(headers["content-range"], want);
        assert_eq!(headers["content-length"], text.len().to_string().as_str());
    }
    for range in ["bytes=10-", "bytes=5-2", "bytes=-0"] {
        let (status, headers, _) = send(&app, "/big.bin", &[("range", range)]).await;
        assert_eq!(status.as_u16(), 416, "{range}");
        assert_eq!(headers["content-range"], "bytes */10");
    }
    // What this does not serve in parts is served whole: several ranges, other units, a malformed one.
    for range in ["bytes=0-1,4-5", "items=0-1", "bytes=a-b"] {
        let (status, _, body) = send(&app, "/big.bin", &[("range", range)]).await;
        assert_eq!((status.as_u16(), body.as_str()), (200, "0123456789"), "{range}");
    }
}

#[tokio::test]
async fn what_is_not_a_get_goes_to_the_api() {
    let (_dir, app) = built();
    for path in ["/", "/x.Service/Call"] {
        let request = Request::post(path).body(Body::empty()).unwrap();
        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(
            axum::body::to_bytes(response.into_body(), 9).await.unwrap(),
            "api",
            "{path}"
        );
    }
}
