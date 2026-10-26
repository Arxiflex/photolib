//! Model downloads (photolib-design docs/09 §12.2): `/models/{name}/{file}` on photolibd's API as devices see it: the
//! files of registry models that devices run, to any signed-in account or API key, resumable with ranges; anything
//! else an empty 404.

use std::{path::Path, sync::Arc};

use axum::{
    Router,
    body::Body,
    http::{HeaderMap, Request, StatusCode},
};
use buffa_types::google::protobuf::Timestamp;
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_models::REGISTRY;
use photolib_proto::proto::photolib::api::v1::{ApiKey, ApiKeyScope};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    keys::ApiKeys,
    models::Models,
    rpc::{Caller, Sessions, Users},
};
use sqlx::PgPool;
use tower::ServiceExt;
use uuid::Uuid;

/// `Authorization: Bearer <user id>` signs a request as that user, and `Bearer enrol:<user id>` as that user on a
/// session that must enrol a second factor first.
struct Bearer;

#[async_trait::async_trait]
impl Sessions for Bearer {
    async fn caller(&self, headers: &HeaderMap) -> Result<Option<Caller>, DbError> {
        let bearer = headers
            .get("authorization")
            .and_then(|value| value.to_str().ok()?.strip_prefix("Bearer "));
        Ok(bearer.and_then(|bearer| {
            let user = bearer.strip_prefix("enrol:");
            Some(Caller {
                user: user.unwrap_or(bearer).parse().ok()?,
                device: Uuid::nil(),
                session: Uuid::nil(),
                must_enrol: user.is_some(),
            })
        }))
    }
}

const YUNET: &str = "/models/yunet@2026may/face_detection_yunet_2026may.onnx";

/// A data directory's models: YuNet whole, SigLIP 2's server-only vision tower whole (sparse) beside a part of its
/// devices' one, nothing of SFace, and a bring-your-own model; and Ann, who signs in.
struct Server {
    app: Router,
    pool: PgPool,
    ann: Uuid,
    yunet: Vec<u8>,
    _dir: tempfile::TempDir,
    _db: testpg::TestDb,
}

fn size(name: &str, file: &str) -> u64 {
    let model = REGISTRY.iter().find(|m| m.name() == name).unwrap();
    model.files.iter().find(|f| f.name == file).unwrap().size
}

fn install(root: &Path, name: &str, file: &str, bytes: &[u8]) {
    std::fs::create_dir_all(root.join(name)).unwrap();
    std::fs::write(root.join(name).join(file), bytes).unwrap();
}

async fn server() -> Server {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let ann = Uuid::now_v7();
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(ann)
        .execute(&db.pool)
        .await
        .unwrap();
    let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let root = dir.path().join("models");
    let length = size("yunet@2026may", "face_detection_yunet_2026may.onnx");
    let yunet: Vec<u8> = (0..length).map(|i| (i ^ (i >> 8)) as u8).collect();
    install(&root, "yunet@2026may", "face_detection_yunet_2026may.onnx", &yunet);
    let siglip = "siglip2-b16-256@onnx-d1114256";
    install(&root, siglip, "vision_model.onnx", b"");
    let whole = std::fs::File::options()
        .write(true)
        .open(root.join(siglip).join("vision_model.onnx"));
    whole.unwrap().set_len(size(siglip, "vision_model.onnx")).unwrap();
    install(&root, siglip, "vision_model_fp16.onnx", b"the first bytes");
    install(&root, "byo@1", "w.onnx", b"weights");
    let users = Users::start(
        Accounts::new(db.pool.clone()),
        ApiKeys::new(db.pool.clone()),
        Arc::new(Bearer),
    );
    let models = Models::new(root, Arc::new(users.await.unwrap()));
    Server {
        app: photolib_server::models::router(Arc::new(models)),
        pool: db.pool.clone(),
        ann,
        yunet,
        _dir: dir,
        _db: db,
    }
}

type Answer = (StatusCode, HeaderMap, Vec<u8>);

impl Server {
    /// `GET path` with `headers`.
    async fn get(&self, path: &str, headers: &[(&str, String)]) -> Answer {
        let mut request = Request::get(path);
        for (name, value) in headers {
            request = request.header(*name, value);
        }
        let response = self
            .app
            .clone()
            .oneshot(request.body(Body::empty()).unwrap())
            .await
            .unwrap();
        let (parts, body) = response.into_parts();
        let body = axum::body::to_bytes(body, 1 << 20).await.unwrap();
        (parts.status, parts.headers, body.to_vec())
    }
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
    headers.get(name).map_or("", |value| value.to_str().unwrap())
}

fn bearer(who: impl std::fmt::Display) -> (&'static str, String) {
    ("authorization", format!("Bearer {who}"))
}

/// A device downloads a model file whole, and after a broken download only what it lacks.
#[tokio::test]
async fn a_signed_in_device_downloads_a_model_file_whole_or_from_where_it_broke_off() {
    let s = server().await;
    let size = s.yunet.len();
    let (status, headers, body) = s.get(YUNET, &[bearer(s.ann)]).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, s.yunet);
    let sha256 = &REGISTRY.iter().find(|m| m.id == "yunet").unwrap().files[0].sha256;
    assert_eq!(
        [
            "content-length",
            "accept-ranges",
            "etag",
            "cache-control",
            "content-type"
        ]
        .map(|name| header(&headers, name)),
        [
            size.to_string().as_str(),
            "bytes",
            &format!("\"{sha256}\""),
            "private",
            "application/octet-stream"
        ]
    );
    for (range, from, to) in [
        ("bytes=100000-", 100_000, size - 1),
        ("bytes=10-19", 10, 19),
        (&format!("bytes=5-{}", size * 2), 5, size - 1),
    ] {
        let (status, headers, body) = s.get(YUNET, &[bearer(s.ann), ("range", range.into())]).await;
        assert_eq!(status, StatusCode::PARTIAL_CONTENT, "{range}");
        assert_eq!(
            [header(&headers, "content-range"), header(&headers, "content-length")],
            [format!("bytes {from}-{to}/{size}"), (to + 1 - from).to_string()],
            "{range}"
        );
        assert!(body == s.yunet[from..=to], "{range}");
    }
    let (status, headers, body) = s
        .get(YUNET, &[bearer(s.ann), ("range", format!("bytes={size}-"))])
        .await;
    assert_eq!((status, body.len()), (StatusCode::RANGE_NOT_SATISFIABLE, 0));
    assert_eq!(header(&headers, "content-range"), format!("bytes */{size}"));

    // An API key of any scope downloads models too.
    let key = ApiKey {
        name: "frame".into(),
        scopes: vec![ApiKeyScope::API_KEY_SCOPE_VIEW.into()],
        expires_at: Some(Timestamp {
            seconds: 1 << 35,
            ..Default::default()
        })
        .into(),
        ..Default::default()
    };
    let (_, secret) = ApiKeys::new(s.pool.clone()).create(s.ann, key).await.unwrap();
    let (status, _, body) = s.get(YUNET, &[bearer(secret)]).await;
    assert_eq!((status, body), (StatusCode::OK, s.yunet));
}

/// Nobody signed in, a model or file not in the registry, a file only the server runs, one not installed whole, a
/// bring-your-own model and a name that is no plain file name all get an empty 404 that no cache keeps.
#[tokio::test]
async fn anything_but_a_device_file_of_an_installed_registry_model_is_an_empty_404() {
    let s = server().await;
    let siglip = "/models/siglip2-b16-256@onnx-d1114256";
    for (path, who) in [
        (YUNET, None),
        (YUNET, Some(format!("enrol:{}", s.ann))),
        (
            "/models/yunet@2025/face_detection_yunet_2026may.onnx",
            Some(s.ann.to_string()),
        ),
        ("/models/yunet@2026may/manifest.json", Some(s.ann.to_string())),
        (&format!("{siglip}/vision_model.onnx"), Some(s.ann.to_string())),
        (&format!("{siglip}/vision_model_fp16.onnx"), Some(s.ann.to_string())),
        (
            "/models/sface@2021dec/face_recognition_sface_2021dec.onnx",
            Some(s.ann.to_string()),
        ),
        ("/models/byo@1/w.onnx", Some(s.ann.to_string())),
        (
            "/models/yunet@2026may/..%2Fyunet@2026may%2Fface_detection_yunet_2026may.onnx",
            Some(s.ann.to_string()),
        ),
        (
            "/models/..%2Fmodels%2Fyunet@2026may/face_detection_yunet_2026may.onnx",
            Some(s.ann.to_string()),
        ),
        (&format!("{YUNET}%00"), Some(s.ann.to_string())),
    ] {
        let headers: Vec<_> = who.iter().map(bearer).collect();
        let (status, got, body) = s.get(path, &headers).await;
        assert_eq!((status, body.len()), (StatusCode::NOT_FOUND, 0), "{path} as {who:?}");
        assert_eq!(header(&got, "cache-control"), "private, no-store", "{path} as {who:?}");
    }
}
