//! Resumable uploads (ADR-0061) on photolibd's `/upload` endpoints: the protocol as clients see it on the wire,
//! durability before acknowledgement, quota, authorization, expiry, and a large upload through a proxy's request cap
//! with network losses on the way.

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    body::Body,
    http::{HeaderMap, Request, StatusCode},
    response::IntoResponse,
};
use buffa_types::google::protobuf::Timestamp;
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{Timing, Worker, reconcile::Profile};
use photolib_proto::proto::photolib::api::v1::{ApiKey, ApiKeyScope};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    ingest::{INGEST, Ingest},
    keys::ApiKeys,
    rpc::{Caller, Sessions, Users},
    uploads::{Disks, Uploads},
};
use photolib_storage::{
    BlobStore, Error, Hash, Hook, Meta,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
    s3::S3Store,
    testing::garage,
};
use sqlx::PgPool;
use tokio_util::sync::CancellationToken;
use tower::ServiceExt;
use uuid::Uuid;

const TIMEOUT: Duration = Duration::from_secs(30);
const TB: u64 = 1_000_000_000_000;

/// `Authorization: Bearer <user id>` signs a request as that user, and `Bearer enrol:<user id>` as that user on a session
/// that must enrol a second factor first.
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

/// photolibd's upload endpoints on a new instance with Ann, who owns `library` on the store `local` (a directory) and
/// `bucket` on `b2` (Garage). Both stores fail at the step `fail` names, and take half a second over `slow`. Every
/// filesystem has 1 TB, all of it free but what `free` says of a directory's.
struct Server {
    app: Router,
    uploads: Arc<Uploads>,
    journal: Arc<Journal>,
    pool: PgPool,
    ann: Uuid,
    library: Uuid,
    bucket: Uuid,
    staging: PathBuf,
    data: PathBuf,
    database: PathBuf,
    free: Arc<Mutex<HashMap<PathBuf, u64>>>,
    local: Arc<dyn BlobStore>,
    b2: Arc<dyn BlobStore>,
    fail: Arc<Mutex<Option<&'static str>>>,
    slow: Arc<Mutex<Option<&'static str>>>,
    _dirs: tempfile::TempDir,
    _db: testpg::TestDb,
}

async fn server() -> Server {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let dirs = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let (data, staging) = (dirs.path().join("data"), dirs.path().join("tmp/uploads"));
    let database = dirs.path().join("postgres");
    std::fs::create_dir(&data).unwrap();
    let (fail, slow) = (Arc::new(Mutex::new(None)), Arc::new(Mutex::new(None)));
    let (at, pause) = (fail.clone(), slow.clone());
    let hook: Hook = Arc::new(move |step| {
        if *pause.lock().unwrap() == Some(step) {
            std::thread::sleep(Duration::from_millis(500));
        }
        match *at.lock().unwrap() {
            Some(failing) if failing == step => Err(Error::Other(format!("{step} failed"))),
            _ => Ok(()),
        }
    });
    let fs = FsStore::open(&data, TIMEOUT).await.unwrap();
    let local: Arc<dyn BlobStore> = Arc::new(fs.with_hook(hook.clone()));
    let b2: Arc<dyn BlobStore> = Arc::new(S3Store::open(&garage(), TIMEOUT).unwrap().with_hook(hook));
    let candidates = [("local", &local, true), ("b2", &b2, false)].map(|(name, store, adopt)| Candidate {
        name: name.into(),
        store: store.clone(),
        adopt,
    });
    let stores = Stores::check(&db.pool, Uuid::now_v7(), candidates.into()).await;
    assert!(stores.offline.is_empty(), "{:?}", stores.offline);
    let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
    let (ann, library, bucket) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(ann)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, root_uri, store) \
         VALUES ($1, $3, 'Photos', 'managed', 'photos', 'local'), ($2, $3, 'Bucket', 'managed', 'bucket', 'b2')",
    )
    .bind(library)
    .bind(bucket)
    .bind(ann)
    .execute(&db.pool)
    .await
    .unwrap();
    let (accounts, keys) = (Accounts::new(db.pool.clone()), ApiKeys::new(db.pool.clone()));
    let users = Users::start(accounts, keys, Arc::new(Bearer)).await.unwrap();
    let (disks, free) = disks(&data, &database);
    // As few connections as photolibd's API has.
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(TIMEOUT)
        .connect(&db.url)
        .await
        .unwrap();
    let uploads = Uploads::new(pool, journal.clone(), Arc::new(users), &staging, disks, "local");
    let uploads = Arc::new(uploads.unwrap());
    Server {
        app: photolib_server::uploads::router(uploads.clone()),
        uploads,
        journal,
        pool: db.pool.clone(),
        ann,
        library,
        bucket,
        staging,
        data,
        database,
        free,
        local,
        b2,
        fail,
        slow,
        _dirs: dirs,
        _db: db,
    }
}

/// Filesystems of 1 TB, all of it free but what the map says of a directory's.
fn disks(data: &Path, database: &Path) -> (Disks, Arc<Mutex<HashMap<PathBuf, u64>>>) {
    let free = Arc::new(Mutex::new(HashMap::new()));
    let left = free.clone();
    let disks = Disks {
        data_dir: data.to_owned(),
        database: Some(database.to_owned()),
        space: Arc::new(move |dir: &Path| {
            let left = left.lock().unwrap().get(dir).copied();
            Ok((TB, left.unwrap_or(TB)))
        }),
    };
    (disks, free)
}

type Answer = (StatusCode, HeaderMap, Vec<u8>);

impl Server {
    async fn send(&self, request: Request<Body>) -> Answer {
        let response = self.app.clone().oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let body = axum::body::to_bytes(body, 1 << 20).await.unwrap();
        (parts.status, parts.headers, body.to_vec())
    }

    /// Creates an upload of `bytes` into the library as Ann and returns its path.
    async fn create(&self, bytes: &[u8]) -> String {
        self.create_in(self.library, bytes.len() as u64, Hash::of(bytes)).await
    }

    async fn create_in(&self, library: Uuid, length: u64, hash: Hash) -> String {
        let (status, headers, _) = self.send(creation(self.ann, library, length, hash)).await;
        assert_eq!(status, StatusCode::CREATED);
        format!("/{}", headers["location"].to_str().unwrap())
    }
}

/// `POST /upload` with `Upload-Complete: ?0` and no content, as `who`.
fn creation(who: Uuid, library: Uuid, length: u64, hash: Hash) -> Request<Body> {
    Request::post("/upload")
        .header("authorization", format!("Bearer {who}"))
        .header("upload-draft-interop-version", "10")
        .header("upload-complete", "?0")
        .header("upload-length", length.to_string())
        .header("photolib-library", library.to_string())
        .header("photolib-hash", hash.to_string())
        .body(Body::empty())
        .unwrap()
}

fn head(who: Uuid, path: &str) -> Request<Body> {
    Request::head(path)
        .header("authorization", format!("Bearer {who}"))
        .body(Body::empty())
        .unwrap()
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
    headers.get(name).map_or("", |value| value.to_str().unwrap())
}

/// `Upload-Complete` and `Upload-Offset`.
fn state(headers: &HeaderMap) -> [&str; 2] {
    ["upload-complete", "upload-offset"].map(|name| header(headers, name))
}

#[tokio::test]
async fn a_new_upload_has_a_location_its_limits_and_offset_zero() {
    let s = server().await;
    let (status, headers, _) = s.send(creation(s.ann, s.library, 11, Hash::of(b"hello world"))).await;
    assert_eq!(status, StatusCode::CREATED);
    let location = header(&headers, "location");
    let id: Uuid = location.strip_prefix("upload/").unwrap().parse().unwrap();
    assert_eq!(state(&headers), ["?0", "0"]);
    lives_a_day(&headers);
    assert!(s.staging.join(id.to_string()).exists());

    let (status, headers, _) = s.send(head(s.ann, &format!("/{location}"))).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let fields = ["upload-offset", "upload-complete", "upload-length", "cache-control"];
    assert_eq!(fields.map(|name| header(&headers, name)), ["0", "?0", "11", "no-store"]);
    lives_a_day(&headers);
}

/// `Upload-Limit` of a new 11-byte upload: a day to live, or a second less when the answer took that long.
fn lives_a_day(headers: &HeaderMap) {
    let limit = header(headers, "upload-limit");
    let ages = ["86400", "86399"].map(|age| format!("max-size=11, max-append-size=33554432, max-age={age}"));
    assert!(ages.iter().any(|expected| expected == limit), "{limit}");
}

fn patch(who: Uuid, path: &str, offset: u64, complete: bool, bytes: &[u8]) -> Request<Body> {
    Request::patch(path)
        .header("authorization", format!("Bearer {who}"))
        .header("content-type", "application/partial-upload")
        .header("upload-offset", offset.to_string())
        .header("upload-complete", if complete { "?1" } else { "?0" })
        .header("content-length", bytes.len().to_string())
        .body(Body::from(bytes.to_vec()))
        .unwrap()
}

/// The code and reason of a Connect error body.
fn reason(body: &[u8]) -> (String, String) {
    let (code, detail) = detail(body);
    (code, detail.code)
}

/// The code of a Connect error body and its detail.
fn detail(body: &[u8]) -> (String, photolib_proto::proto::photolib::api::v1::ErrorDetail) {
    use base64::Engine;
    use buffa::Message;
    let json: serde_json::Value = serde_json::from_slice(body).unwrap();
    let detail = base64::engine::general_purpose::STANDARD_NO_PAD
        .decode(json["details"][0]["value"].as_str().unwrap())
        .unwrap();
    let detail = photolib_proto::proto::photolib::api::v1::ErrorDetail::decode_from_slice(&detail).unwrap();
    (json["code"].as_str().unwrap().into(), detail)
}

#[tokio::test]
async fn an_append_at_the_offset_is_acknowledged_and_one_elsewhere_gets_the_offset_back() {
    let s = server().await;
    let upload = s.create(b"hello world").await;
    let (status, headers, _) = s.send(patch(s.ann, &upload, 0, false, b"hello ")).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(state(&headers), ["?0", "6"]);
    let id = upload.rsplit('/').next().unwrap();
    assert_eq!(std::fs::read(s.staging.join(id)).unwrap(), b"hello ");

    for offset in [0, 3, 7] {
        let (status, headers, body) = s.send(patch(s.ann, &upload, offset, false, b"w")).await;
        assert_eq!(status, StatusCode::CONFLICT, "at {offset}");
        assert_eq!(state(&headers), ["?0", "6"]);
        assert_eq!(reason(&body), ("aborted".into(), "upload.offset_mismatch".into()));
    }
    let (status, _, body) = s.send(patch(s.ann, &upload, 6, false, b"world!")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "past the length");
    assert_eq!(
        reason(&body),
        ("invalid_argument".into(), "upload.length_mismatch".into())
    );
    let mut text = patch(s.ann, &upload, 6, false, b"w");
    text.headers_mut().insert("content-type", "text/plain".parse().unwrap());
    let (status, _, body) = s.send(text).await;
    assert_eq!(
        (status, reason(&body)),
        (
            StatusCode::BAD_REQUEST,
            ("invalid_argument".into(), "field.invalid".into())
        )
    );
    let (_, headers, _) = s.send(head(s.ann, &upload)).await;
    assert_eq!(header(&headers, "upload-offset"), "6", "nothing else was kept");
    assert_eq!(std::fs::read(s.staging.join(id)).unwrap(), b"hello ");
}

fn id(upload: &str) -> &str {
    upload.rsplit('/').next().unwrap()
}

#[tokio::test]
async fn the_last_append_is_acknowledged_once_its_bytes_have_their_hash_and_are_in_the_store() {
    let s = server().await;
    let upload = s.create(b"hello world").await;
    s.send(patch(s.ann, &upload, 0, false, b"hello ")).await;
    let (status, headers, body) = s.send(patch(s.ann, &upload, 6, true, b"world")).await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&body));
    assert_eq!(header(&headers, "upload-complete"), "?1");
    let hash = Hash::of(b"hello world");
    let acknowledged = serde_json::json!({ "uploadId": id(&upload), "length": 11, "blake3": hash.to_string() });
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
        acknowledged
    );
    let key = format!("libraries/{}/uploads/{}", s.library, id(&upload));
    let meta = Meta {
        size: 11,
        hash: Some(hash),
    };
    assert_eq!(s.local.head(&key).await.unwrap(), Some(meta));
    assert_eq!(s.local.get(&key, None).await.unwrap(), b"hello world");
    assert!(s.staging.join(id(&upload)).exists(), "kept until ingest has read it");

    let (status, headers, _) = s.send(head(s.ann, &upload)).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(state(&headers), ["?1", "11"]);
    // The client lost the acknowledgement: completing again gets it once more.
    let (status, headers, again) = s.send(patch(s.ann, &upload, 11, true, b"")).await;
    assert_eq!((status, header(&headers, "upload-complete")), (StatusCode::OK, "?1"));
    assert_eq!(again, body);
    let (status, headers, _) = s.send(patch(s.ann, &upload, 6, true, b"world")).await;
    assert_eq!((status, state(&headers)), (StatusCode::CONFLICT, ["?1", "11"]));
}

#[tokio::test]
async fn bytes_without_the_announced_hash_are_refused_and_forgotten() {
    let s = server().await;
    let upload = s.create(b"hello world").await;
    let (status, headers, body) = s.send(patch(s.ann, &upload, 0, true, b"hello there")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(header(&headers, "upload-complete"), "?1", "resuming cannot help");
    assert_eq!(
        reason(&body),
        ("invalid_argument".into(), "upload.hash_mismatch".into())
    );
    assert_eq!(s.local.list("libraries/").await.unwrap(), Vec::<String>::new());
    assert!(!s.staging.join(id(&upload)).exists());
    assert_eq!(s.send(head(s.ann, &upload)).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn an_upload_is_acknowledged_only_after_a_durable_write_to_its_store() {
    let s = server().await;
    // The write's fsync on the filesystem, the end of the PUT on the object store; other bytes for each, as the same
    // bytes again would be linked to the first (ADR-0092).
    for (library, step, store, bytes) in [
        (s.library, "synced", &s.local, b"hello world"),
        (s.bucket, "closed", &s.b2, b"hello again"),
    ] {
        let upload = s.create_in(library, 11, Hash::of(bytes)).await;
        let key = format!("libraries/{library}/uploads/{}", id(&upload));
        *s.fail.lock().unwrap() = Some(step);
        let (status, headers, _) = s.send(patch(s.ann, &upload, 0, true, bytes)).await;
        assert!(status.is_server_error(), "{step}: {status}");
        assert_eq!(
            header(&headers, "upload-complete"),
            "?0",
            "{step}: the client may retry"
        );
        assert_eq!(store.head(&key).await.unwrap(), None, "{step}");
        let (_, headers, _) = s.send(head(s.ann, &upload)).await;
        assert_eq!(state(&headers), ["?0", "11"], "{step}");

        *s.fail.lock().unwrap() = None;
        let (status, headers, _) = s.send(patch(s.ann, &upload, 11, true, b"")).await;
        assert_eq!((status, header(&headers, "upload-complete")), (StatusCode::OK, "?1"));
        let meta = Meta {
            size: 11,
            hash: Some(Hash::of(bytes)),
        };
        assert_eq!(store.head(&key).await.unwrap(), Some(meta), "{step}: verified");
    }
}

/// A client that goes away while its upload is written to the store, as a killed `photolib upload` does, leaves it
/// complete rather than half written and refused from then on.
#[tokio::test(flavor = "multi_thread")]
async fn a_completion_finishes_when_its_client_goes_away() {
    let s = server().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let wire = Wire(listener.local_addr().unwrap());
    let app = s.app.clone();
    tokio::spawn(async move { axum::serve(listener, app).await });
    let upload = s.create(b"hello world").await;
    *s.slow.lock().unwrap() = Some("synced");
    let fields = [
        ("Content-Type", "application/partial-upload".into()),
        ("Upload-Offset", "0".into()),
        ("Upload-Complete", "?1".into()),
        ("Content-Length", "11".into()),
    ];
    let head_ = wire_head("PATCH", &upload, s.ann, &fields);
    let client = wire.start(head_, b"hello world", 11).await;
    // Once the server holds the bytes the client dies, as a process that dies resets its connections.
    let staged = s.staging.join(id(&upload));
    for _ in 0..3000 {
        if std::fs::metadata(&staged).is_ok_and(|file| file.len() == 11) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    client.set_zero_linger().unwrap();
    drop(client);
    tokio::time::sleep(Duration::from_millis(100)).await;
    let (_, headers, _) = s.send(head(s.ann, &upload)).await;
    assert_eq!(state(&headers), ["?1", "11"]);
}

#[tokio::test]
async fn content_sent_with_the_creation_is_appended_and_can_complete_the_upload_at_once() {
    let s = server().await;
    let mut partial = creation(s.ann, s.library, 11, Hash::of(b"hello world"));
    *partial.body_mut() = Body::from("hello");
    let (status, headers, _) = s.send(partial).await;
    assert_eq!((status, state(&headers)), (StatusCode::CREATED, ["?0", "5"]));
    let upload = format!("/{}", header(&headers, "location"));
    let (status, _, _) = s.send(patch(s.ann, &upload, 5, true, b" world")).await;
    assert_eq!(status, StatusCode::OK);

    // As iOS sends a file: everything in one request, the length from its Content-Length.
    let mut whole = creation(s.ann, s.library, 0, Hash::of(b"hello world"));
    let headers = whole.headers_mut();
    headers.remove("upload-length");
    headers.insert("upload-complete", "?1".parse().unwrap());
    headers.insert("content-length", "11".parse().unwrap());
    *whole.body_mut() = Body::from("hello world");
    let (status, headers, body) = s.send(whole).await;
    assert_eq!((status, header(&headers, "upload-complete")), (StatusCode::OK, "?1"));
    let id = header(&headers, "location").strip_prefix("upload/").unwrap();
    let body: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        (body["uploadId"].as_str(), &body["length"]),
        (Some(id), &serde_json::json!(11))
    );
}

/// Adds an account to the instance and returns its id.
async fn account(pool: &PgPool, handle: &str, role: &str) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO users (id, handle, display_name, role) VALUES ($1, $2, $2, $3)")
        .bind(id)
        .bind(handle)
        .bind(role)
        .execute(pool)
        .await
        .unwrap();
    id
}

#[tokio::test]
async fn only_contributors_create_uploads_and_only_the_uploader_sees_one() {
    let s = server().await;
    let (con, vic, ida, sam) = (
        account(&s.pool, "con", "user").await,
        account(&s.pool, "vic", "user").await,
        account(&s.pool, "ida", "viewer").await,
        account(&s.pool, "sam", "user").await,
    );
    // Ida's account is a viewer's, whatever her role in the library.
    sqlx::query(
        "INSERT INTO library_members (library_id, user_id, role) \
         VALUES ($1, $2, 'contributor'), ($1, $3, 'viewer'), ($1, $4, 'contributor')",
    )
    .bind(s.library)
    .bind(con)
    .bind(vic)
    .bind(ida)
    .execute(&s.pool)
    .await
    .unwrap();
    let hash = Hash::of(b"x");
    let mut anonymous = creation(s.ann, s.library, 1, hash);
    anonymous.headers_mut().remove("authorization");
    let (status, _, body) = s.send(anonymous).await;
    assert_eq!(
        (status, reason(&body)),
        (
            StatusCode::UNAUTHORIZED,
            ("unauthenticated".into(), "session.required".into())
        )
    );
    let mut enrolling = creation(con, s.library, 1, hash);
    let bearer = format!("Bearer enrol:{con}").parse().unwrap();
    enrolling.headers_mut().insert("authorization", bearer);
    let (status, _, body) = s.send(enrolling).await;
    assert_eq!(
        (status, reason(&body)),
        (
            StatusCode::FORBIDDEN,
            ("permission_denied".into(), "second_factor.required".into())
        ),
        "a session that must enrol a second factor uploads nothing"
    );
    for (who, library) in [
        (vic, s.library),
        (ida, s.library),
        (sam, s.library),
        (con, s.bucket),
        (con, Uuid::now_v7()),
    ] {
        let (status, _, body) = s.send(creation(who, library, 1, hash)).await;
        assert_eq!(
            (status, reason(&body)),
            (
                StatusCode::FORBIDDEN,
                ("permission_denied".into(), "library.contribute_denied".into())
            )
        );
    }
    let (status, headers, _) = s.send(creation(con, s.library, 1, hash)).await;
    assert_eq!(status, StatusCode::CREATED);
    let upload = format!("/{}", header(&headers, "location"));
    for who in [s.ann, sam] {
        assert_eq!(s.send(head(who, &upload)).await.0, StatusCode::NOT_FOUND);
        let (status, _, body) = s.send(patch(who, &upload, 0, true, b"x")).await;
        assert_eq!(
            (status, reason(&body)),
            (StatusCode::NOT_FOUND, ("not_found".into(), "upload.not_found".into()))
        );
    }
    // Con, demoted to a viewer before the upload completes, cannot complete it.
    sqlx::query("UPDATE library_members SET role = 'viewer' WHERE user_id = $1")
        .bind(con)
        .execute(&s.pool)
        .await
        .unwrap();
    assert_eq!(
        s.send(patch(con, &upload, 0, true, b"x")).await.0,
        StatusCode::NOT_FOUND
    );
}

/// Gives `who` private-mode keys with the unlock paths `kinds`, the recovery kit verified when `verified`: rows as
/// KeyService keeps them, whose wraps only clients open.
async fn keys(pool: &PgPool, who: Uuid, kinds: &[&str], verified: bool) {
    sqlx::query(
        "INSERT INTO account_keys (user_id, amk_id, signing_key, decryption_key, recovery_verified_at)
         VALUES ($1, $2, $3, $3, CASE WHEN $4 THEN now() END)
         ON CONFLICT (user_id) DO UPDATE SET recovery_verified_at = EXCLUDED.recovery_verified_at",
    )
    .bind(who)
    .bind(vec![0_u8; 16])
    .bind(vec![0_u8; 144])
    .bind(verified)
    .execute(pool)
    .await
    .unwrap();
    for kind in kinds {
        sqlx::query(
            "INSERT INTO unlock_paths (user_id, kind, wrap, params)
             VALUES ($1, $2, $3, CASE $2 WHEN 'password' THEN $4 END)",
        )
        .bind(who)
        .bind(kind)
        .bind(vec![0_u8; 144])
        .bind(vec![0_u8; 26])
        .execute(pool)
        .await
        .unwrap();
    }
}

/// No upload into a private library starts before its uploader, owner or not, has two ways into their keys and has
/// proved they hold the recovery kit (design 06 §6).
#[tokio::test]
async fn a_private_upload_waits_for_two_unlock_paths_and_a_verified_recovery_kit() {
    let s = server().await;
    let (private, con) = (Uuid::now_v7(), account(&s.pool, "con", "user").await);
    sqlx::query(
        "WITH library AS (INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri)
                          VALUES ($1, $2, 'V', 'managed', 'private', 'v'))
         INSERT INTO library_members (library_id, user_id, role) VALUES ($1, $3, 'contributor')",
    )
    .bind(private)
    .bind(s.ann)
    .bind(con)
    .execute(&s.pool)
    .await
    .unwrap();
    let server = &s;
    let attempt = |who: Uuid| async move {
        let (status, _, body) = server.send(creation(who, private, 1, Hash::of(b"x"))).await;
        (
            status,
            if status == StatusCode::CREATED {
                Default::default()
            } else {
                reason(&body)
            },
        )
    };
    let incomplete = (
        StatusCode::BAD_REQUEST,
        ("failed_precondition".into(), "keys.recovery_incomplete".into()),
    );
    assert_eq!(attempt(s.ann).await, incomplete, "no keys");
    keys(&s.pool, s.ann, &["recovery"], true).await;
    assert_eq!(attempt(s.ann).await, incomplete, "one unlock path");
    keys(&s.pool, s.ann, &["password"], false).await;
    assert_eq!(attempt(s.ann).await, incomplete, "an unverified recovery kit");
    keys(&s.pool, s.ann, &[], true).await;
    assert_eq!(attempt(s.ann).await.0, StatusCode::CREATED);
    assert_eq!(attempt(con).await, incomplete, "a contributor's own keys count");
    let uploads: i64 = sqlx::query_scalar("SELECT count(*) FROM uploads WHERE library_id = $1")
        .bind(private)
        .fetch_one(&s.pool)
        .await
        .unwrap();
    assert_eq!(uploads, 1, "a refused upload reserves nothing");
}

/// The library each upload of `who` without a library went to, and the libraries `who` owns.
async fn destinations(s: &Server, who: Uuid, uploads: usize) -> (Vec<Uuid>, Vec<(Uuid, String, String)>) {
    let requests = (0..uploads).map(|n| {
        let mut request = creation(who, Uuid::nil(), 1, Hash::of(&[n as u8]));
        request.headers_mut().remove("photolib-library");
        s.send(request)
    });
    for (status, _, body) in futures::future::join_all(requests).await {
        assert_eq!(status, StatusCode::CREATED, "{}", String::from_utf8_lossy(&body));
    }
    let went = sqlx::query_scalar("SELECT library_id FROM uploads WHERE owner_id = $1 ORDER BY id");
    let owned = sqlx::query_as("SELECT id, kind, store FROM libraries WHERE owner_id = $1 ORDER BY id");
    (
        went.bind(who).fetch_all(&s.pool).await.unwrap(),
        owned.bind(who).fetch_all(&s.pool).await.unwrap(),
    )
}

#[tokio::test]
async fn an_upload_without_a_library_goes_to_its_owners_destination_made_at_the_first() {
    let s = server().await;
    let (went, owned) = destinations(&s, s.ann, 2).await;
    assert_eq!(went, [s.library; 2], "her first managed library");

    let bob = account(&s.pool, "bob", "user").await;
    let (went, owned_by_bob) = destinations(&s, bob, 8).await;
    let [(library, kind, store)] = &owned_by_bob[..] else {
        panic!("one library for eight uploads at once: {owned_by_bob:?}")
    };
    assert_eq!((kind.as_str(), store.as_str()), ("managed", "local"));
    assert_eq!(went, [*library; 8]);
    let marker = format!("libraries/{library}/.photolib/library.json");
    assert!(s.local.head(&marker).await.unwrap().is_some(), "its marker");
    assert_eq!(owned.len(), 2, "Ann's libraries stay as they were");

    let ida = account(&s.pool, "ida", "viewer").await;
    let mut request = creation(ida, Uuid::nil(), 1, Hash::of(b"x"));
    request.headers_mut().remove("photolib-library");
    let (status, _, body) = s.send(request).await;
    assert_eq!(
        (status, reason(&body)),
        (
            StatusCode::FORBIDDEN,
            ("permission_denied".into(), "library.contribute_denied".into())
        ),
    );
    let none: i64 = sqlx::query_scalar("SELECT count(*) FROM libraries WHERE owner_id = $1")
        .bind(ida)
        .fetch_one(&s.pool)
        .await
        .unwrap();
    assert_eq!(none, 0, "a viewer gets no library");
}

#[tokio::test]
async fn an_api_key_creates_uploads_as_its_account_only_with_the_contribute_scope() {
    let s = server().await;
    let keys = ApiKeys::new(s.pool.clone());
    for (scope, expected) in [
        (ApiKeyScope::API_KEY_SCOPE_CONTRIBUTE, StatusCode::CREATED),
        (ApiKeyScope::API_KEY_SCOPE_VIEW, StatusCode::FORBIDDEN),
    ] {
        let key = ApiKey {
            name: "cli".into(),
            scopes: vec![scope.into()],
            expires_at: Some(Timestamp {
                seconds: 1 << 35,
                ..Default::default()
            })
            .into(),
            ..Default::default()
        };
        let (_, secret) = keys.create(s.ann, key).await.unwrap();
        let mut request = creation(s.ann, s.library, 1, Hash::of(b"x"));
        let bearer = format!("Bearer {secret}").parse().unwrap();
        request.headers_mut().insert("authorization", bearer);
        assert_eq!(s.send(request).await.0, expected, "{scope:?}");
    }
}

/// The server's policy refuses uploads with the capability it switches off as the reason, to sessions (the apps and the
/// web) and API keys (the CLI) alike (ADR-0240).
#[tokio::test]
async fn an_upload_the_policy_switches_off_is_refused_with_the_capability_as_the_reason() {
    let s = server().await;
    let key = ApiKey {
        name: "cli".into(),
        scopes: vec![ApiKeyScope::API_KEY_SCOPE_CONTRIBUTE.into()],
        expires_at: Some(Timestamp {
            seconds: 1 << 35,
            ..Default::default()
        })
        .into(),
        ..Default::default()
    };
    let (_, secret) = ApiKeys::new(s.pool.clone()).create(s.ann, key).await.unwrap();
    let hash = Hash::of(b"x");
    for (off, refused) in [
        ("uploads", Some("uploads")),
        ("managed_libraries", Some("managed_libraries")),
        ("nothing", None),
    ] {
        sqlx::query("DELETE FROM policy_switches")
            .execute(&s.pool)
            .await
            .unwrap();
        sqlx::query("INSERT INTO policy_switches (capability, enabled) SELECT $1, false WHERE $1 <> 'nothing'")
            .bind(off)
            .execute(&s.pool)
            .await
            .unwrap();
        let mut by_key = creation(s.ann, s.library, 1, hash);
        let bearer = format!("Bearer {secret}").parse().unwrap();
        by_key.headers_mut().insert("authorization", bearer);
        for request in [creation(s.ann, s.library, 1, hash), by_key] {
            let (status, _, body) = s.send(request).await;
            let Some(capability) = refused else {
                assert_eq!(status, StatusCode::CREATED);
                continue;
            };
            let (code, detail) = detail(&body);
            assert_eq!(
                (status, code.as_str(), detail.code.as_str()),
                (StatusCode::FORBIDDEN, "permission_denied", "policy.disabled"),
                "{off} off"
            );
            assert_eq!(detail.params.get("capability").map(String::as_str), Some(capability));
        }
    }
    // An upload under way when uploads are switched off says so at its next append.
    let upload = s.create(b"later").await;
    sqlx::query("INSERT INTO policy_switches (capability, enabled) VALUES ('uploads', false)")
        .execute(&s.pool)
        .await
        .unwrap();
    let (status, _, body) = s.send(patch(s.ann, &upload, 0, true, b"later")).await;
    let (code, detail) = detail(&body);
    assert_eq!(
        (status, code.as_str(), detail.code.as_str()),
        (StatusCode::FORBIDDEN, "permission_denied", "policy.disabled")
    );
}

#[tokio::test]
async fn an_upload_reserves_its_length_against_the_owners_quota() {
    let s = server().await;
    sqlx::query("UPDATE users SET quota_bytes = 15 WHERE id = $1")
        .bind(s.ann)
        .execute(&s.pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO assets (id, library_id, owner_id, source, file_size_total) VALUES ($1, $2, $3, 'upload', 3)",
    )
    .bind(Uuid::now_v7())
    .bind(s.library)
    .bind(s.ann)
    .execute(&s.pool)
    .await
    .unwrap();
    s.create(b"hello world").await;
    let (status, headers, body) = s.send(creation(s.ann, s.library, 2, Hash::of(b"!!"))).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(header(&headers, "upload-limit"), "max-size=1");
    assert_eq!(reason(&body), ("resource_exhausted".into(), "quota.exceeded".into()));
    assert_eq!(
        s.send(creation(s.ann, s.library, 1, Hash::of(b"!"))).await.0,
        StatusCode::CREATED
    );
}

#[tokio::test]
async fn uploads_pause_while_a_filesystem_they_fill_is_below_the_free_disk_floor() {
    let s = server().await;
    let set_free = |dir: &Path, bytes: u64| s.free.lock().unwrap().insert(dir.to_owned(), bytes);
    let hello = |library| creation(s.ann, library, 11, Hash::of(b"hello world"));
    let upload = s.create(b"hello world").await;
    // 5 % of 1 TB is 50 GB; the floor is the smaller 20 GB.
    for (dir, name) in [
        (&s.staging, "work_dir"),
        (&s.data, "data_dir"),
        (&s.database, "database.data_dir"),
    ] {
        set_free(dir, 20_000_000_000 - 1);
        for request in [hello(s.library), patch(s.ann, &upload, 0, false, b"hello ")] {
            let (status, _, body) = s.send(request).await;
            assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE, "{name}");
            let (code, detail) = detail(&body);
            assert_eq!(
                (code.as_str(), detail.code.as_str()),
                ("unavailable", "disk.low"),
                "{name}"
            );
            assert_eq!(detail.params["dir"], name);
        }
        set_free(dir, 20_000_000_000);
    }
    // The data directory holds no library on an object store.
    set_free(&s.data, 0);
    s.create_in(s.bucket, 11, Hash::of(b"hello world")).await;
    assert_eq!(s.send(hello(s.library)).await.0, StatusCode::SERVICE_UNAVAILABLE);
    set_free(&s.data, TB);
    // A floor of 1 % is 10 GB, less than 20 GB; 0 GB is none.
    sqlx::query("UPDATE instance_settings SET min_free_disk_percent = 1")
        .execute(&s.pool)
        .await
        .unwrap();
    set_free(&s.staging, 10_000_000_000);
    s.create(b"hello world").await;
    sqlx::query("UPDATE instance_settings SET min_free_disk_gb = 0")
        .execute(&s.pool)
        .await
        .unwrap();
    set_free(&s.staging, 0);
    let (status, headers, _) = s.send(patch(s.ann, &upload, 0, false, b"hello ")).await;
    assert_eq!(
        (status, state(&headers)),
        (StatusCode::NO_CONTENT, ["?0", "6"]),
        "the paused upload resumes"
    );
}

#[tokio::test]
async fn options_announce_the_limits_of_new_uploads() {
    let s = server().await;
    let request = Request::options("/upload").body(Body::empty()).unwrap();
    let (status, headers, _) = s.send(request).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(
        header(&headers, "upload-limit"),
        "max-append-size=33554432, max-age=86400"
    );
}

fn delete(who: Uuid, path: &str) -> Request<Body> {
    Request::delete(path)
        .header("authorization", format!("Bearer {who}"))
        .body(Body::empty())
        .unwrap()
}

#[tokio::test]
async fn a_cancelled_upload_is_gone_with_its_staged_bytes_and_a_complete_one_stays() {
    let s = server().await;
    let upload = s.create(b"hello world").await;
    s.send(patch(s.ann, &upload, 0, false, b"hello")).await;
    assert_eq!(s.send(delete(s.ann, &upload)).await.0, StatusCode::NO_CONTENT);
    assert!(!s.staging.join(id(&upload)).exists());
    assert_eq!(s.send(head(s.ann, &upload)).await.0, StatusCode::NOT_FOUND);

    let complete = s.create(b"x").await;
    s.send(patch(s.ann, &complete, 0, true, b"x")).await;
    let (status, _, body) = s.send(delete(s.ann, &complete)).await;
    assert_eq!(
        (status, reason(&body)),
        (
            StatusCode::BAD_REQUEST,
            ("failed_precondition".into(), "upload.complete".into())
        )
    );
    assert_eq!(s.send(head(s.ann, &complete)).await.0, StatusCode::NO_CONTENT);
}

#[tokio::test]
async fn abandoned_uploads_expire_with_their_staged_bytes() {
    let s = server().await;
    let (abandoned, active, complete) = (
        s.create(b"hello world").await,
        s.create(b"hello world").await,
        s.create(b"x").await,
    );
    s.send(patch(s.ann, &abandoned, 0, false, b"hello")).await;
    s.send(patch(s.ann, &complete, 0, true, b"x")).await;
    sqlx::query("UPDATE uploads SET expires_at = now() WHERE id <> $1")
        .bind(Uuid::parse_str(id(&active)).unwrap())
        .execute(&s.pool)
        .await
        .unwrap();
    // A crash between deleting an upload and its staged bytes leaves them behind.
    let stray = s.staging.join(Uuid::now_v7().to_string());
    std::fs::write(&stray, b"left over").unwrap();

    assert_eq!(s.uploads.expire().await.unwrap(), 1);
    assert_eq!(s.send(head(s.ann, &abandoned)).await.0, StatusCode::NOT_FOUND);
    for kept in [&active, &complete] {
        assert_eq!(s.send(head(s.ann, kept)).await.0, StatusCode::NO_CONTENT);
        assert!(s.staging.join(id(kept)).exists());
    }
    assert!(!s.staging.join(id(&abandoned)).exists());
    assert!(!stray.exists());
}

#[tokio::test]
async fn an_incomplete_upload_lives_a_day_from_its_creation_and_again_from_each_append() {
    let s = server().await;
    let upload = s.create(b"hello world").await;
    let upload_id = Uuid::parse_str(id(&upload)).unwrap();
    let left = || async {
        sqlx::query_scalar::<_, f64>("SELECT extract(epoch FROM expires_at - now())::float8 FROM uploads WHERE id = $1")
            .bind(upload_id)
            .fetch_one(&s.pool)
            .await
            .unwrap()
    };
    let day = 86_390.0..=86_400.0;
    assert!(day.contains(&left().await), "{}", left().await);
    sqlx::query("UPDATE uploads SET expires_at = now() + interval '1 minute' WHERE id = $1")
        .bind(upload_id)
        .execute(&s.pool)
        .await
        .unwrap();
    s.send(patch(s.ann, &upload, 0, false, b"hello")).await;
    assert!(day.contains(&left().await), "{}", left().await);
}

/// A reverse proxy's cap on a request's size: Cloudflare's 100 MB on its Free and Pro plans.
const CAP: u64 = 100_000_000;
/// The client's appends, as the app sends them.
const APPEND: u64 = 8 << 20;

async fn cap(request: Request<Body>, next: axum::middleware::Next) -> axum::response::Response {
    let length = request.headers().get("content-length");
    if length.and_then(|n| n.to_str().ok()?.parse::<u64>().ok()) > Some(CAP) {
        let page = axum::response::Html("<html><body><h1>413 Request Entity Too Large</h1></body></html>");
        return (StatusCode::PAYLOAD_TOO_LARGE, page).into_response();
    }
    next.run(request).await
}

/// `length` bytes of a large video from `offset` on: a pseudo-random MiB, rotated differently in every MiB.
fn video(offset: u64, length: u64) -> Vec<u8> {
    const MIB: u64 = 1 << 20;
    static BLOCK: std::sync::OnceLock<Vec<u8>> = std::sync::OnceLock::new();
    let block = BLOCK.get_or_init(|| {
        let mut state = 0x9e37_79b9_7f4a_7c15_u64;
        let mib: Vec<u8> = (0..MIB)
            .map(|_| {
                state ^= state << 13;
                state ^= state >> 7;
                state ^= state << 17;
                state as u8
            })
            .collect();
        [mib.clone(), mib].concat()
    });
    let mut bytes = Vec::with_capacity(length as usize);
    let mut at = offset;
    while at < offset + length {
        let within = at % MIB;
        let start = (at / MIB * 7919 % MIB + within) as usize;
        let take = (MIB - within).min(offset + length - at) as usize;
        bytes.extend_from_slice(&block[start..start + take]);
        at += take as u64;
    }
    bytes
}

/// A client on raw TCP, so that it can lose its connection halfway through a request.
struct Wire(std::net::SocketAddr);

impl Wire {
    /// Sends `head`, then `body` up to `sent`; returns the connection.
    async fn start(&self, head: String, body: &[u8], sent: usize) -> tokio::net::TcpStream {
        use tokio::io::AsyncWriteExt;
        let mut stream = tokio::net::TcpStream::connect(self.0).await.unwrap();
        stream.write_all(head.as_bytes()).await.unwrap();
        stream.write_all(&body[..sent]).await.unwrap();
        stream
    }

    /// The status and headers of the answer to `head` and `body`.
    async fn send(&self, head: String, body: &[u8]) -> (u16, HeaderMap) {
        use tokio::io::AsyncReadExt;
        let mut stream = self.start(head, body, body.len()).await;
        let mut answer = Vec::new();
        stream.read_to_end(&mut answer).await.unwrap();
        let mut parsed = [httparse::EMPTY_HEADER; 32];
        let mut response = httparse::Response::new(&mut parsed);
        response.parse(&answer).unwrap();
        let mut headers = HeaderMap::new();
        for header in response.headers.iter() {
            headers.append(
                axum::http::HeaderName::from_bytes(header.name.as_bytes()).unwrap(),
                axum::http::HeaderValue::from_bytes(header.value).unwrap(),
            );
        }
        (response.code.unwrap(), headers)
    }
}

fn wire_head(method: &str, path: &str, who: Uuid, fields: &[(&str, String)]) -> String {
    let mut head = format!("{method} {path} HTTP/1.1\r\nHost: photos.example\r\nConnection: close\r\n");
    head += &format!("Authorization: Bearer {who}\r\nUpload-Draft-Interop-Version: 10\r\n");
    for (name, value) in fields {
        head += &format!("{name}: {value}\r\n");
    }
    head + "\r\n"
}

/// The upload of a large video (`PHOTOLIB_UPLOAD_BYTES`, 300 MB unless set; the weekly workflow sends 10 GB) in
/// appends that pass the proxy's cap, losing the connection twice on the way: once cut, once left hanging.
#[tokio::test(flavor = "multi_thread")]
async fn a_large_video_passes_a_100_mb_request_cap_and_resumes_after_network_loss() {
    let total: u64 = std::env::var("PHOTOLIB_UPLOAD_BYTES").map_or(300_000_000, |n| n.parse().unwrap());
    assert!(total > 4 * APPEND, "PHOTOLIB_UPLOAD_BYTES must exceed 32 MiB");
    let started = std::time::Instant::now();
    let mut hasher = blake3::Hasher::new();
    for offset in (0..total).step_by(APPEND as usize) {
        hasher.update(&video(offset, APPEND.min(total - offset)));
    }
    let hash = Hash::from(hasher.finalize());
    let s = server().await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let wire = Wire(listener.local_addr().unwrap());
    let app = s.app.clone().layer(axum::middleware::from_fn(cap));
    tokio::spawn(async move { axum::serve(listener, app).await });

    let fields = [
        ("Upload-Complete", "?0".into()),
        ("Upload-Length", total.to_string()),
        ("Photolib-Library", s.library.to_string()),
        ("Photolib-Hash", hash.to_string()),
        ("Content-Length", "0".into()),
    ];
    let (status, headers) = wire.send(wire_head("POST", "/upload", s.ann, &fields), b"").await;
    assert_eq!(status, 201);
    let upload = format!("/{}", header(&headers, "location"));
    let append = |offset: u64, length: u64| {
        let fields = [
            ("Content-Type", "application/partial-upload".into()),
            ("Upload-Offset", offset.to_string()),
            (
                "Upload-Complete",
                if offset + length == total { "?1" } else { "?0" }.into(),
            ),
            ("Content-Length", length.to_string()),
        ];
        wire_head("PATCH", &upload, s.ann, &fields)
    };
    let offset_now = || async {
        let (status, headers) = wire.send(wire_head("HEAD", &upload, s.ann, &[]), b"").await;
        assert_eq!(status, 204);
        header(&headers, "upload-offset").parse::<u64>().unwrap()
    };
    let received = || async {
        let query = sqlx::query_scalar::<_, i64>("SELECT received FROM uploads");
        query.fetch_one(&s.pool).await.unwrap() as u64
    };
    let staged = s.staging.join(id(&upload));
    let whole = 3 * CAP;
    let (status, _) = wire.send(append(0, whole), b"").await;
    assert_eq!(status, 413, "the proxy refuses a request over its cap");

    let (mut offset, mut requests, mut resumes, mut sent, mut hung) = (0, 0, 0, 0, vec![]);
    let acknowledged = loop {
        let length = APPEND.min(total - offset);
        let bytes = video(offset, length);
        let half = length / 2;
        requests += 1;
        match requests {
            // The network goes away halfway through an append: once the server sees the end of the connection, it keeps
            // what arrived.
            3 => {
                drop(wire.start(append(offset, length), &bytes, half as usize).await);
                let before = offset;
                while received().await == before {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
                (sent, resumes) = (sent + half, resumes + 1);
                offset = offset_now().await;
                assert_eq!(offset, before + half, "the cut append keeps what arrived");
            }
            // The connection hangs: once the server has what was sent, the client gives up on it and asks where to
            // go on.
            5 => {
                hung.push(wire.start(append(offset, length), &bytes, half as usize).await);
                let before = offset;
                while std::fs::metadata(&staged).unwrap().len() < before + half {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
                (sent, resumes) = (sent + half, resumes + 1);
                offset = offset_now().await;
                assert_eq!(offset, before + half, "the hung append keeps what arrived");
            }
            _ => {
                let (status, headers) = wire.send(append(offset, length), &bytes).await;
                sent += length;
                match status {
                    204 => offset += length,
                    _ => break (status, headers),
                }
            }
        }
    };
    let (status, headers) = acknowledged;
    assert_eq!((status, header(&headers, "upload-complete")), (200, "?1"));
    // Five requests to 32 MiB (two whole appends, the cut one, one more, the hung one), then the rest.
    let expected = 5 + (total - 4 * APPEND).div_ceil(APPEND);
    assert_eq!(
        (requests, resumes, sent),
        (expected, 2, total),
        "appends, resumes and bytes sent: none twice"
    );
    let key = format!("libraries/{}/uploads/{}", s.library, id(&upload));
    let meta = Meta {
        size: total,
        hash: Some(hash),
    };
    assert_eq!(s.local.head(&key).await.unwrap(), Some(meta));
    eprintln!("{total} bytes in {requests} requests: {:?}", started.elapsed());
}

/// A JPEG whose EXIF and XMP carry markup and script where text belongs.
fn hostile_jpeg() -> Vec<u8> {
    let tags: [(u16, &str); 4] = [
        (0x010e, "<script>alert('description')</script>"),
        (0x010f, "\"><img src=x onerror=alert('make')>"),
        (0x0110, "</title><svg onload=alert('model')>"),
        (0x013b, "javascript:alert('artist')"),
    ];
    let mut tiff = b"II*\0\x08\0\0\0".to_vec();
    tiff.extend((tags.len() as u16).to_le_bytes());
    let mut data = 8 + 2 + 12 * tags.len() + 4;
    let mut values = vec![];
    for (tag, text) in tags {
        let value = [text.as_bytes(), b"\0"].concat();
        tiff.extend(tag.to_le_bytes());
        tiff.extend(2u16.to_le_bytes());
        tiff.extend((value.len() as u32).to_le_bytes());
        tiff.extend((data as u32).to_le_bytes());
        data += value.len();
        values.extend(value);
    }
    tiff.extend([0; 4]);
    tiff.extend(values);
    let xmp = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title><rdf:Alt><rdf:li xml:lang="x-default">&lt;iframe src=javascript:alert('title')&gt;</rdf:li></rdf:Alt></dc:title></rdf:Description></rdf:RDF></x:xmpmeta>"#;
    let segment = |payload: Vec<u8>| {
        [
            vec![0xff, 0xe1],
            ((payload.len() + 2) as u16).to_be_bytes().to_vec(),
            payload,
        ]
        .concat()
    };
    [
        vec![0xff, 0xd8],
        segment([b"Exif\0\0".to_vec(), tiff].concat()),
        segment([b"http://ns.adobe.com/xap/1.0/\0".as_slice(), xmp.as_bytes()].concat()),
        vec![0xff, 0xd9],
    ]
    .concat()
}

/// ExifTool's -stay_open protocol, answering with the name it was given and a tag that holds a script.
const FAKE_EXIFTOOL: &str = r#"
while IFS= read -r line; do
    case $line in
        -execute) printf '[{"SourceFile":"%s","IFD0:ImageDescription":"<script>alert(1)</script>"}]\n{ready}\n' "$file";;
        *) file=$line;;
    esac
done
"#;

/// Runs ingest, with ExifTool's sandbox and FAKE_EXIFTOOL, until no ingest job is left.
async fn ingest(s: &Server) {
    let bin = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    std::fs::write(bin.path().join("exiftool"), FAKE_EXIFTOOL).unwrap();
    let exiftool = vec!["/bin/sh".into(), bin.path().join("exiftool")];
    let work = s.staging.parent().unwrap();
    let photolibd = env!("CARGO_BIN_EXE_photolibd").into();
    let ingest = Ingest::new(
        s.journal.clone(),
        work,
        photolibd,
        exiftool,
        Profile::default(),
        Arc::new(photolib_server::external::Libraries::new(TIMEOUT)),
    )
    .unwrap();
    let shutdown = CancellationToken::new();
    let worker = Worker::new(s.pool.clone(), "test", 1, Timing::default()).handle(INGEST, ingest);
    let running = tokio::spawn(worker.run(shutdown.clone()));
    let open = "SELECT count(*) FROM jobs WHERE type = 'ingest' AND status <> 'done'";
    while sqlx::query_scalar::<_, i64>(open).fetch_one(&s.pool).await.unwrap() > 0 {
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    shutdown.cancel();
    running.await.unwrap();
}

/// A complete upload is queued for ingest in the transaction that completes it, with the path its client gave; ingest
/// makes it an asset. Markup in its name, EXIF, XMP and ExifTool's dump is kept as the text it is, the name reaches
/// ExifTool not at all and the storage key only as the last name the template gives it, and an upload into a private
/// library is never queued.
#[tokio::test]
async fn a_complete_upload_becomes_an_asset_and_what_a_hostile_file_says_stays_text() {
    let s = server().await;
    let photo = hostile_jpeg();
    let mut created = creation(s.ann, s.library, photo.len() as u64, Hash::of(&photo));
    let named = "DCIM/%22%3E%3Cimg%20src%3Dx%20onerror%3Dalert(%27name%27)%3E.jpg";
    created.headers_mut().insert("photolib-path", named.parse().unwrap());
    let (status, headers, _) = s.send(created).await;
    assert_eq!(status, StatusCode::CREATED);
    let upload = format!("/{}", header(&headers, "location"));
    let queued = "SELECT convert_from(payload, 'UTF8')::jsonb FROM jobs WHERE type = 'ingest'";
    let jobs = || async {
        sqlx::query_scalar::<_, serde_json::Value>(queued)
            .fetch_all(&s.pool)
            .await
            .unwrap()
    };
    assert!(
        jobs().await.is_empty(),
        "nothing to ingest before the upload is complete"
    );
    let (status, _, _) = s.send(patch(s.ann, &upload, 0, true, &photo)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(jobs().await, [serde_json::json!({"uploads": [id(&upload)]})]);

    let private = Uuid::now_v7();
    sqlx::query("INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri) VALUES ($1, $2, 'V', 'managed', 'private', 'v')")
        .bind(private)
        .bind(s.ann)
        .execute(&s.pool)
        .await
        .unwrap();
    keys(&s.pool, s.ann, &["password", "recovery"], true).await;
    let sealed = s.create_in(private, 6, Hash::of(b"sealed")).await;
    assert_eq!(
        s.send(patch(s.ann, &sealed, 0, true, b"sealed")).await.0,
        StatusCode::OK
    );
    assert_eq!(
        jobs().await.len(),
        1,
        "the server never reads a private library's files"
    );

    ingest(&s).await;

    let (asset, key, dump, dated): (serde_json::Value, String, serde_json::Value, String) = sqlx::query_as(
        "SELECT json_build_object('name', original_filename, 'path', source_ref, 'description', description,
           'make', make, 'model', model, 'title', title, 'mime', f.mime), f.key, raw_metadata,
           to_char(coalesce(taken_local, taken_utc AT TIME ZONE 'UTC', a.created_at AT TIME ZONE 'UTC'), 'YYYY/YYYY-MM')
         FROM assets a JOIN asset_files f ON f.asset_id = a.id",
    )
    .fetch_one(&s.pool)
    .await
    .unwrap();
    let name = "\"><img src=x onerror=alert('name')>.jpg";
    assert_eq!(
        asset,
        serde_json::json!({
            "name": name,
            "path": format!("DCIM/{name}"),
            "description": "<script>alert('description')</script>",
            "make": "\"><img src=x onerror=alert('make')>",
            "model": "</title><svg onload=alert('model')>",
            "title": "<iframe src=javascript:alert('title')>",
            "mime": "image/jpeg",
        })
    );
    assert_eq!(key, format!("libraries/{}/originals/{dated}/{name}", s.library));
    assert_eq!(dump["IFD0:ImageDescription"], "<script>alert(1)</script>");
    let seen = dump["SourceFile"].as_str().unwrap();
    assert!(!seen.contains("img") && !seen.contains('>'), "ExifTool saw {seen}");
}

/// A file that is no photo or video is kept as an asset without a media kind, and no parser reads its bytes
/// (ADR-0066): ExifTool, which dumps every file it is given, never sees it; the kernel dates it by its name and folder
/// alone, and the template files it under that date, or the upload's when the name has none.
#[tokio::test]
async fn a_file_that_is_no_photo_or_video_is_kept_and_dated_by_its_name_alone() {
    let s = server().await;
    let (dated, undated) = ("Documents/DOC-20191120-WA0006.pdf", "Documents/notes.pdf");
    for (path, pdf) in [(dated, b"%PDF-1.7\n%%EOF\n"), (undated, b"%PDF-1.4\n%%EOF\n")] {
        let mut created = creation(s.ann, s.library, pdf.len() as u64, Hash::of(pdf));
        created.headers_mut().insert("photolib-path", path.parse().unwrap());
        let (status, headers, _) = s.send(created).await;
        assert_eq!(status, StatusCode::CREATED);
        let upload = format!("/{}", header(&headers, "location"));
        assert_eq!(s.send(patch(s.ann, &upload, 0, true, pdf)).await.0, StatusCode::OK);
    }
    ingest(&s).await;
    let rows: Vec<(serde_json::Value, String)> = sqlx::query_as(
        "SELECT json_build_object('kind', media_kind, 'dump', raw_metadata, 'taken', taken_local, 'source', time_source,
           'mime', f.mime, 'path', source_ref, 'key', f.key), to_char(a.created_at AT TIME ZONE 'UTC', 'YYYY/YYYY-MM')
         FROM assets a JOIN asset_files f ON f.asset_id = a.id ORDER BY source_ref",
    )
    .fetch_all(&s.pool)
    .await
    .unwrap();
    let originals = format!("libraries/{}/originals", s.library);
    let uploaded = &rows[1].1;
    assert_eq!(
        rows.iter().map(|row| &row.0).collect::<Vec<_>>(),
        [
            &serde_json::json!({"kind": null, "dump": null, "taken": "2019-11-20T00:00:00", "source": "filename:F25",
                "mime": "application/pdf", "path": dated,
                "key": format!("{originals}/2019/2019-11/DOC-20191120-WA0006.pdf")}),
            &serde_json::json!({"kind": null, "dump": null, "taken": null, "source": "unknown",
                "mime": "application/pdf", "path": undated, "key": format!("{originals}/{uploaded}/notes.pdf")}),
        ]
    );
}

/// A client's path names a file below its source's root: nothing that climbs out of it, starts at the root, hides
/// in control or bidirectional characters, or is not UTF-8.
#[tokio::test]
async fn a_path_that_could_escape_or_disguise_a_name_is_refused() {
    let s = server().await;
    let long = "a".repeat(1025);
    for path in [
        "../etc/passwd",
        "DCIM/../../x.jpg",
        "/etc/passwd",
        "DCIM//x.jpg",
        "./x.jpg",
        "DCIM/.",
        "C:%5CWindows%5Cx.jpg",
        "x%00.jpg",
        "x%0A.jpg",
        "photo%E2%80%AEgpj.exe",
        "%FF.jpg",
        "%2E%2E/x.jpg",
        "",
        &long,
    ] {
        let mut created = creation(s.ann, s.library, 1, Hash::of(b"x"));
        created.headers_mut().insert("photolib-path", path.parse().unwrap());
        let (status, _, body) = s.send(created).await;
        assert_eq!(
            (status, reason(&body)),
            (
                StatusCode::BAD_REQUEST,
                ("invalid_argument".into(), "field.invalid".into())
            ),
            "{path}"
        );
    }
}

/// Sends `bytes` into `library` as `who` in one request, as iOS does; returns the status and the upload's id.
async fn back_up(s: &Server, who: Uuid, library: Uuid, bytes: &[u8]) -> (StatusCode, String) {
    let mut whole = creation(who, library, bytes.len() as u64, Hash::of(bytes));
    whole.headers_mut().insert("upload-complete", "?1".parse().unwrap());
    *whole.body_mut() = Body::from(bytes.to_vec());
    let (status, headers, _) = s.send(whole).await;
    (status, id(header(&headers, "location")).into())
}

/// Backing up a file that its owner's libraries already hold, in an external library or in an upload that ingest has
/// yet to record, is acknowledged without a copy: nothing is written or queued, and the upload is gone. Another
/// account's identical file, and a file sent into a library that someone else owns, are stored as usual.
#[tokio::test]
async fn a_file_its_owner_already_holds_is_linked_instead_of_stored() {
    let s = server().await;
    let (photo, nas, bob, family) = (b"on the NAS", Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    let ann = s.ann;
    sqlx::raw_sql(&format!(
        "INSERT INTO libraries (id, owner_id, name, kind, access, root_uri) VALUES ('{nas}', '{ann}', 'NAS', 'external', 'ro', '/nas');
         INSERT INTO assets (id, library_id, owner_id, source) VALUES ('{nas}', '{nas}', '{ann}', 'scan');
         INSERT INTO asset_files (id, asset_id, role, storage, key, content_hash)
         VALUES ('{nas}', '{nas}', 'original', 'nas', 'IMG_1.jpg', '\\x{}');
         INSERT INTO users (id, handle, display_name) VALUES ('{bob}', 'bob', 'Bob');
         INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES ('{family}', '{bob}', 'Family', 'managed', 'family');
         INSERT INTO library_members (library_id, user_id, role) VALUES ('{family}', '{ann}', 'contributor')",
        Hash::of(photo)
    ))
    .execute(&s.pool)
    .await
    .unwrap();

    let upload = s.create(photo).await;
    let (status, headers, body) = s.send(patch(s.ann, &upload, 0, true, photo)).await;
    assert_eq!((status, header(&headers, "upload-complete")), (StatusCode::OK, "?1"));
    let acknowledged =
        serde_json::json!({ "uploadId": id(&upload), "length": photo.len(), "blake3": Hash::of(photo).to_string() });
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
        acknowledged
    );
    assert!(!s.staging.join(id(&upload)).exists());
    let mut stored = vec![];
    for (who, library, bytes, kept) in [
        (s.ann, s.library, &b"new"[..], true),
        (s.ann, s.library, b"new", false),
        (bob, family, photo, true),
        (s.ann, family, photo, true),
    ] {
        let (status, upload) = back_up(&s, who, library, bytes).await;
        assert_eq!(status, StatusCode::OK);
        if kept {
            stored.push(format!("libraries/{library}/uploads/{upload}"));
        }
    }
    stored.sort();
    assert_eq!(s.local.list("libraries/").await.unwrap(), stored);
    let pool = &s.pool;
    let count = |sql: &'static str| async move { sqlx::query_scalar::<_, i64>(sql).fetch_one(pool).await.unwrap() };
    assert_eq!(count("SELECT count(*) FROM uploads").await, 3);
    assert_eq!(count("SELECT count(*) FROM jobs WHERE type = 'ingest'").await, 3);
}

/// A file the scrub found damaged is no longer held (ADR-0234): backing its bytes up again, into any of its owner's
/// libraries, puts them back for that file instead of linking to it. A file that is gone is written again at its key;
/// one whose object holds other bytes gets a numbered key beside it, and the purge deletes the damaged object. Its
/// findings are resolved, and nothing is left to ingest.
#[tokio::test]
async fn a_backup_of_a_damaged_files_bytes_puts_it_back() {
    let s = server().await;
    let (gone, rotten) = (&b"a photo that went missing"[..], &b"a photo that rotted"[..]);
    let at = |name: &str| format!("libraries/{}/originals/2024/{name}.jpg", s.library);
    let data = s.staging.parent().unwrap().parent().unwrap().join("data");
    std::fs::create_dir_all(data.join(at("x")).parent().unwrap()).unwrap();
    std::fs::write(data.join(at("rotten")), b"a photo that ROTTED").unwrap();
    for (name, bytes, kind) in [("gone", gone, "missing"), ("rotten", rotten, "content")] {
        sqlx::query(
            "WITH a AS (INSERT INTO assets (id, library_id, owner_id, source, content_hash)
               VALUES (photolib_uuidv7(), $1, $2, 'upload', $4) RETURNING id),
             f AS (INSERT INTO asset_files (id, asset_id, role, storage, key, size, content_hash)
               SELECT photolib_uuidv7(), id, 'original', 'local', $3, $5, $4 FROM a)
             INSERT INTO integrity_findings (id, store, key, kind, detail) VALUES (photolib_uuidv7(), 'local', $3, $6, '')",
        )
        .bind(s.library)
        .bind(s.ann)
        .bind(at(name))
        .bind(Hash::of(bytes).0.to_vec())
        .bind(i64::try_from(bytes.len()).unwrap())
        .bind(kind)
        .execute(&s.pool)
        .await
        .unwrap();
    }

    for (library, bytes) in [(s.library, gone), (s.bucket, rotten)] {
        assert_eq!(back_up(&s, s.ann, library, bytes).await.0, StatusCode::OK);
    }
    s.journal.purge().await.unwrap();
    let repaired = [(at("gone"), gone), (at("rotten (2)"), rotten)];
    let keys: Vec<String> = sqlx::query_scalar("SELECT key FROM asset_files ORDER BY key")
        .fetch_all(&s.pool)
        .await
        .unwrap();
    assert_eq!(keys, repaired.clone().map(|(key, _)| key));
    assert_eq!(s.local.list("libraries/").await.unwrap(), keys);
    for (key, bytes) in repaired {
        assert_eq!(std::fs::read(data.join(key)).unwrap(), bytes);
    }
    assert_eq!(s.b2.list("libraries/").await.unwrap(), Vec::<String>::new());
    let pool = &s.pool;
    let count = |sql: &'static str| async move { sqlx::query_scalar::<_, i64>(sql).fetch_one(pool).await.unwrap() };
    let open = "SELECT count(*) FROM integrity_findings WHERE resolved_at IS NULL";
    assert_eq!(count(open).await, 0);
    assert_eq!(count("SELECT count(*) FROM uploads").await, 0);
    assert_eq!(count("SELECT count(*) FROM jobs WHERE type = 'ingest'").await, 0);
    assert_eq!(std::fs::read_dir(&s.staging).unwrap().count(), 0);
}

/// The model whose vectors devices hand off at upload (design 09 §3.2), and a self-tested runtime that ran it.
const ACTIVE: &str = "siglip2-b16-256@onnx-d1114256";
const RUNTIME: &str = "onnxruntime 1.31.0 CPU fp16";

/// `n` half floats, the i-th `half(i)`, as their little-endian bytes.
fn halves(n: usize, half: impl Fn(usize) -> u16) -> Vec<u8> {
    (0..n).flat_map(|i| half(i).to_le_bytes()).collect()
}

/// A device's vector of SigLIP 2: 768 finite half floats, none of them 0.
fn siglip(sign: u16) -> Vec<u8> {
    halves(768, |i| sign | 0x3c00 | (i as u16 & 0x3ff))
}

/// The hand-off headers of a vector.
fn handoff(model: &str, runtime: &str, vector: &[u8]) -> Vec<(&'static str, String)> {
    use base64::Engine;
    vec![
        ("photolib-ml-model", model.into()),
        ("photolib-ml-runtime", runtime.into()),
        (
            "photolib-ml-vector",
            base64::engine::general_purpose::STANDARD.encode(vector),
        ),
    ]
}

/// Sends `bytes` into `library` as Ann in one request with the hand-off `headers`; returns the status.
async fn hand_off(s: &Server, library: Uuid, bytes: &[u8], headers: &[(&'static str, String)]) -> StatusCode {
    let mut whole = creation(s.ann, library, bytes.len() as u64, Hash::of(bytes));
    whole.headers_mut().insert("upload-complete", "?1".parse().unwrap());
    for (name, value) in headers {
        whole.headers_mut().insert(*name, value.parse().unwrap());
    }
    *whole.body_mut() = Body::from(bytes.to_vec());
    s.send(whole).await.0
}

async fn embeddings(pool: &PgPool) -> Vec<(Uuid, String, Vec<u8>)> {
    sqlx::query_as("SELECT asset_id, model_id, embedding FROM asset_embeddings ORDER BY asset_id")
        .fetch_all(pool)
        .await
        .unwrap()
}

/// A vector a device computed with the active model on a self-tested runtime comes with its upload (design 09 §3.2)
/// and is kept for its asset as the device sent it. The first vector an asset gets stays: a backup of the same bytes
/// with another one, which dedup links to the asset, changes nothing, while an asset without one takes it.
#[tokio::test]
async fn a_vector_a_device_computed_with_the_active_model_is_kept_for_its_asset_and_the_first_one_stays() {
    let s = server().await;
    let (vector, other) = (siglip(0), siglip(0x8000));
    let photo = hostile_jpeg();
    let status = hand_off(&s, s.library, &photo, &handoff(ACTIVE, RUNTIME, &vector)).await;
    assert_eq!(status, StatusCode::OK);
    ingest(&s).await;
    let asset: Uuid = sqlx::query_scalar("SELECT id FROM assets")
        .fetch_one(&s.pool)
        .await
        .unwrap();
    assert_eq!(embeddings(&s.pool).await, [(asset, ACTIVE.into(), vector.clone())]);

    let status = hand_off(&s, s.library, &photo, &handoff(ACTIVE, RUNTIME, &other)).await;
    assert_eq!(status, StatusCode::OK);
    let (held, unindexed) = (b"an asset no device indexed", Uuid::now_v7());
    sqlx::raw_sql(&format!(
        "INSERT INTO assets (id, library_id, owner_id, source) VALUES ('{unindexed}', '{}', '{}', 'upload');
         INSERT INTO asset_files (id, asset_id, role, storage, key, content_hash)
         VALUES ('{unindexed}', '{unindexed}', 'original', 'local', 'held.jpg', '\\x{}')",
        s.library,
        s.ann,
        Hash::of(held)
    ))
    .execute(&s.pool)
    .await
    .unwrap();
    let status = hand_off(&s, s.library, held, &handoff(ACTIVE, RUNTIME, &other)).await;
    assert_eq!(status, StatusCode::OK);
    let ingests: i64 = sqlx::query_scalar("SELECT count(*) FROM jobs WHERE type = 'ingest'")
        .fetch_one(&s.pool)
        .await
        .unwrap();
    assert_eq!(ingests, 1, "dedup linked both backups");
    assert_eq!(
        embeddings(&s.pool).await,
        [(asset, ACTIVE.into(), vector), (unindexed, ACTIVE.into(), other)]
    );
}

/// Hand-offs that fail a check, each with what is wrong with it.
fn refused() -> Vec<(&'static str, Vec<(&'static str, String)>)> {
    let good = siglip(0);
    let with = |at: usize, half: u16| {
        let mut vector = good.clone();
        vector[2 * at..2 * at + 2].copy_from_slice(&half.to_le_bytes());
        handoff(ACTIVE, RUNTIME, &vector)
    };
    let without = |header: &str| -> Vec<_> {
        let all = handoff(ACTIVE, RUNTIME, &good).into_iter();
        all.filter(|(name, _)| *name != header).collect()
    };
    let runtime = |runtime: &str| handoff(ACTIVE, runtime, &good);
    let mut garbled = handoff(ACTIVE, RUNTIME, &good);
    garbled[2].1 = "not base64!".into();
    vec![
        (
            "another model",
            handoff("sface@2021dec", RUNTIME, &halves(128, |_| 0x3c00)),
        ),
        ("another revision", handoff("siglip2-b16-256@onnx-0", RUNTIME, &good)),
        ("another runtime", runtime("tflite 2.16.1 CPU fp16")),
        ("a version of two numbers", runtime("onnxruntime 1.31 CPU fp16")),
        ("a version that is no number", runtime("onnxruntime 1.31.x CPU fp16")),
        ("a provider of other characters", runtime("onnxruntime 1.31.0 C_P fp16")),
        ("an unknown precision", runtime("onnxruntime 1.31.0 CPU fp8")),
        ("a word too many", runtime("onnxruntime 1.31.0 CPU fp16 x")),
        ("two spaces", runtime("onnxruntime  1.31.0 CPU fp16")),
        ("767 values", handoff(ACTIVE, RUNTIME, &good[..1534])),
        (
            "769 values",
            handoff(ACTIVE, RUNTIME, &[&good[..], &[0, 0x3c]].concat()),
        ),
        ("an odd byte", handoff(ACTIVE, RUNTIME, &good[..1535])),
        ("no base64", garbled),
        ("a NaN", with(5, 0x7e00)),
        ("an infinity", with(767, 0xfc00)),
        (
            "zeros",
            handoff(ACTIVE, RUNTIME, &halves(768, |i| (i as u16 & 1) << 15)),
        ),
        ("no model", without("photolib-ml-model")),
        ("no runtime", without("photolib-ml-runtime")),
        ("no vector", without("photolib-ml-vector")),
    ]
}

/// A hand-off that fails a check is dropped and its upload goes on: another model or revision, a runtime that is not
/// `onnxruntime <x.y.z> <provider> <precision>`, a vector of another length, not finite or of norm 0, a missing
/// header, or a private library, whose devices hand off through sealed metadata instead.
#[tokio::test]
async fn a_hand_off_that_fails_a_check_stores_nothing_and_its_upload_completes() {
    let s = server().await;
    let private = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri)
         VALUES ($1, $2, 'V', 'managed', 'private', 'v')",
    )
    .bind(private)
    .bind(s.ann)
    .execute(&s.pool)
    .await
    .unwrap();
    keys(&s.pool, s.ann, &["password", "recovery"], true).await;
    let cases = refused().into_iter().map(|(case, headers)| (case, s.library, headers));
    let cases: Vec<_> = cases
        .chain([("a private library", private, handoff(ACTIVE, RUNTIME, &siglip(0)))])
        .collect();
    for (i, (case, library, headers)) in cases.iter().enumerate() {
        let bytes = format!("upload {i}");
        let status = hand_off(&s, *library, bytes.as_bytes(), headers).await;
        assert_eq!(status, StatusCode::OK, "{case}");
    }
    ingest(&s).await;
    let pool = &s.pool;
    let count = |sql: &'static str| async move { sqlx::query_scalar::<_, i64>(sql).fetch_one(pool).await.unwrap() };
    let standard = i64::try_from(cases.len()).unwrap() - 1;
    assert_eq!(count("SELECT count(*) FROM assets").await, standard);
    assert_eq!(embeddings(&s.pool).await, []);
    assert_eq!(
        count("SELECT count(*) FROM uploads WHERE embedding IS NOT NULL").await,
        0
    );
}
