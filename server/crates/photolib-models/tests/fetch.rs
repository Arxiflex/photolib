//! On-demand downloads: a model's files for one target, from its URLs in order, kept only when they match the pin.

use std::{
    fs,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Router,
    body::Body,
    http::{StatusCode, header::LOCATION},
    routing::get,
};
use common::{file, listing};
use photolib_models::{Model, Store, Target};
use serde_json::json;

mod common;

/// A mirror on loopback, counting requests: `/a` serves a.onnx, `/moved` redirects there, `/tampered` serves other
/// bytes, `/endless` never stops, and anything else is 404.
async fn mirror() -> (String, Arc<AtomicUsize>) {
    let requests = Arc::new(AtomicUsize::new(0));
    let counted = requests.clone();
    let app = Router::new()
        .route("/a", get(|| async { "weights a" }))
        .route("/b", get(|| async { "weights b" }))
        .route("/moved", get(|| async { (StatusCode::FOUND, [(LOCATION, "/a")]) }))
        .route("/tampered", get(|| async { "weights x" }))
        .route(
            "/endless",
            get(|| async {
                let chunk = || Ok::<_, std::io::Error>(bytes::Bytes::from(vec![0; 1 << 16]));
                Body::from_stream(futures::stream::repeat_with(chunk))
            }),
        )
        .layer(axum::middleware::from_fn(
            move |request: axum::extract::Request, next: axum::middleware::Next| {
                counted.fetch_add(1, Ordering::SeqCst);
                next.run(request)
            },
        ));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (base, requests)
}

fn model(a: &[&str], b: &[&str]) -> Model {
    serde_json::from_value(json!({
        "id": "m", "revision": "1", "task": "face_detection",
        "licence": {"spdx": "MIT", "source": "https://example.org/LICENSE"},
        "files": [file("a.onnx", b"weights a", "server", a), file("b.onnx", b"weights b", "web", b)]
    }))
    .unwrap()
}

#[tokio::test]
async fn the_files_a_target_runs_are_downloaded_through_redirects_verified_and_installed_once() {
    let (base, requests) = mirror().await;
    let dir = tempfile::tempdir().unwrap();
    let model = model(&[&format!("{base}/moved")], &[&format!("{base}/b")]);
    let store = Store::new(dir.path(), std::slice::from_ref(&model));
    store.fetch(&model, &[Target::Server]).await.unwrap();
    assert_eq!(listing(dir.path()), ["m@1/a.onnx", "m@1/manifest.json"]);
    assert_eq!(fs::read(dir.path().join("m@1/a.onnx")).unwrap(), b"weights a");
    let manifest = fs::read(dir.path().join("m@1/manifest.json")).unwrap();
    assert_eq!(serde_json::from_slice::<Model>(&manifest).unwrap(), model);
    assert_eq!(requests.load(Ordering::SeqCst), 2, "the redirect and the file");

    store.fetch(&model, &[Target::Server]).await.unwrap();
    assert_eq!(
        requests.load(Ordering::SeqCst),
        2,
        "an installed file is not downloaded again"
    );
    store.fetch(&model, &[Target::Web]).await.unwrap();
    assert_eq!(listing(dir.path()), ["m@1/a.onnx", "m@1/b.onnx", "m@1/manifest.json"]);
}

/// What `photolibd models fetch` installs: the files the server runs and those it serves to devices.
#[tokio::test]
async fn one_fetch_for_every_target_installs_the_files_devices_run_beside_the_servers() {
    let (base, _) = mirror().await;
    let dir = tempfile::tempdir().unwrap();
    let model = model(&[&format!("{base}/a")], &[&format!("{base}/b")]);
    let store = Store::new(dir.path(), std::slice::from_ref(&model));
    store.fetch(&model, &Target::ALL).await.unwrap();
    assert_eq!(listing(dir.path()), ["m@1/a.onnx", "m@1/b.onnx", "m@1/manifest.json"]);
    assert_eq!(fs::read(dir.path().join("m@1/b.onnx")).unwrap(), b"weights b");
}

#[tokio::test]
async fn a_download_that_differs_from_its_pin_falls_back_to_the_next_url_else_installs_nothing() {
    let (base, _) = mirror().await;
    let dir = tempfile::tempdir().unwrap();
    let urls = ["tampered", "missing", "endless"].map(|path| format!("{base}/{path}"));
    let failing = model(&urls.each_ref().map(String::as_str), &[]);
    let store = Store::new(dir.path(), std::slice::from_ref(&failing));
    let error = photolib_spawn::within(Duration::from_secs(10), store.fetch(&failing, &[Target::Server]))
        .await
        .expect("a download larger than its pin stops")
        .unwrap_err();
    for expected in [
        format!("{base}/tampered: does not match the SHA-256 and size of a.onnx"),
        format!("{base}/missing: HTTP 404"),
        format!("{base}/endless: does not match the SHA-256 and size of a.onnx"),
    ] {
        assert!(error.contains(&expected), "expected '{expected}' in '{error}'");
    }
    assert_eq!(listing(dir.path()), Vec::<String>::new());

    let fallback = model(&[&urls[0], &urls[1], &format!("{base}/a")], &[]);
    store.fetch(&fallback, &[Target::Server]).await.unwrap();
    assert_eq!(fs::read(dir.path().join("m@1/a.onnx")).unwrap(), b"weights a");
}

#[tokio::test]
async fn a_model_dated_2100_stays_installed_and_is_not_downloaded_again() {
    let (base, requests) = mirror().await;
    let dir = tempfile::tempdir().unwrap();
    let model = model(&[&format!("{base}/a")], &[]);
    let store = Store::new(dir.path(), std::slice::from_ref(&model));
    store.fetch(&model, &[Target::Server]).await.unwrap();
    let year_2100 = std::time::UNIX_EPOCH + Duration::from_secs(4_102_444_800);
    for file in listing(dir.path()) {
        let file = fs::File::options().write(true).open(dir.path().join(file));
        file.unwrap().set_modified(year_2100).unwrap();
    }
    store.fetch(&model, &[Target::Server]).await.unwrap();
    assert_eq!(requests.load(Ordering::SeqCst), 1);
    assert_eq!(listing(dir.path()), ["m@1/a.onnx", "m@1/manifest.json"]);
    assert_eq!(fs::read(dir.path().join("m@1/a.onnx")).unwrap(), b"weights a");
}
