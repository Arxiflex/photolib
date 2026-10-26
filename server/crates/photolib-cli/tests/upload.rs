//! `photolib upload` against photolibd's upload endpoints (ADR-0061) on a throwaway database.

use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
    process::Output,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering::SeqCst},
    },
    time::Duration,
};

use axum::http::HeaderMap;
use buffa_types::google::protobuf::Timestamp;
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_proto::proto::photolib::api::v1::{ApiKey, ApiKeyScope};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    keys::ApiKeys,
    rpc::{Caller, Sessions, Users},
    storage,
    uploads::{Disks, Uploads},
};
use photolib_spawn::Signal;
use photolib_storage::{
    BlobStore, Hash,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
};
use serde_json::json;
use sqlx::PgPool;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    process::Command,
};
use uuid::Uuid;

/// `Authorization: Bearer <user id>` signs a request as that user.
struct Bearer;

#[async_trait::async_trait]
impl Sessions for Bearer {
    async fn caller(&self, headers: &HeaderMap) -> Result<Option<Caller>, DbError> {
        let bearer = headers
            .get("authorization")
            .and_then(|value| value.to_str().ok()?.strip_prefix("Bearer ")?.parse().ok());
        Ok(bearer.map(|user| Caller {
            user,
            device: Uuid::nil(),
            session: Uuid::nil(),
            must_enrol: false,
        }))
    }
}

/// photolibd's upload endpoints on 127.0.0.1 behind a proxy that answers requests over `cap` bytes with its own
/// 413 page, with Ann, who owns `library`; and a scratch directory for the files to upload and the client's state.
struct Server {
    url: String,
    cap: Arc<AtomicU64>,
    seen: Seen,
    pool: PgPool,
    ann: Uuid,
    library: Uuid,
    dir: tempfile::TempDir,
    _db: testpg::TestDb,
}

async fn server() -> Server {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let data = dir.path().join("data");
    std::fs::create_dir(&data).unwrap();
    let local: Arc<dyn BlobStore> = Arc::new(FsStore::open(&data, Duration::from_secs(30)).await.unwrap());
    let candidate = Candidate {
        name: "local".into(),
        store: local,
        adopt: true,
    };
    let stores = Stores::check(&db.pool, Uuid::now_v7(), vec![candidate]).await;
    let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
    let (ann, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(ann)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES ($1, $2, 'Photos', 'managed', 'photos')",
    )
    .bind(library)
    .bind(ann)
    .execute(&db.pool)
    .await
    .unwrap();
    let (accounts, keys) = (Accounts::new(db.pool.clone()), ApiKeys::new(db.pool.clone()));
    let users = Users::start(accounts, keys, Arc::new(Bearer)).await.unwrap();
    let staging = dir.path().join("staging");
    let disks = Disks {
        data_dir: data,
        database: None,
        space: Arc::new(storage::space),
    };
    let uploads = Uploads::new(db.pool.clone(), journal, Arc::new(users), &staging, disks, "local").unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let cap = Arc::new(AtomicU64::new(u64::MAX));
    let seen = Seen::default();
    let app = photolib_server::uploads::router(Arc::new(uploads))
        .layer(axum::middleware::from_fn_with_state(cap.clone(), refuse_over))
        .layer(axum::middleware::from_fn_with_state(seen.clone(), record));
    tokio::spawn(async move { axum::serve(listener, app).await });
    Server {
        url,
        cap,
        seen,
        pool: db.pool.clone(),
        ann,
        library,
        dir,
        _db: db,
    }
}

/// The requests the server got: method, `Upload-Offset` and `Content-Length`.
type Seen = Arc<Mutex<Vec<(String, u64, u64)>>>;

async fn record(
    axum::extract::State(seen): axum::extract::State<Seen>,
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let headers = request.headers();
    let number = |name: &str| {
        let value = headers.get(name).and_then(|n| n.to_str().ok()?.parse().ok());
        value.unwrap_or(0)
    };
    let entry = (
        request.method().to_string(),
        number("upload-offset"),
        number("content-length"),
    );
    seen.lock().unwrap().push(entry);
    next.run(request).await
}

async fn refuse_over(
    axum::extract::State(cap): axum::extract::State<Arc<AtomicU64>>,
    request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let length = request.headers().get("content-length");
    if length.and_then(|n| n.to_str().ok()?.parse::<u64>().ok()) > Some(cap.load(SeqCst)) {
        // As nginx's lingering close does, so that the client reads the answer.
        let _ = axum::body::to_bytes(request.into_body(), usize::MAX).await;
        let page = "<html><body><h1>413 Request Entity Too Large</h1></body></html>";
        let page = axum::response::Html(page);
        return axum::response::IntoResponse::into_response((axum::http::StatusCode::PAYLOAD_TOO_LARGE, page));
    }
    next.run(request).await
}

impl Server {
    /// `photolib upload` of `paths` as Ann, with the state under the scratch directory.
    fn upload(&self, paths: &[&Path]) -> Command {
        self.upload_via(&self.url, paths)
    }

    /// Runs `photolib upload` of `paths` with `args` to its end.
    async fn run(&self, paths: &[&Path], args: &[&str]) -> Output {
        self.upload(paths).args(args).output().await.unwrap()
    }

    fn upload_via(&self, url: &str, paths: &[&Path]) -> Command {
        let photolib = env!("CARGO_BIN_EXE_photolib");
        let mut command = Command::from(photolib_spawn::command(photolib, Signal::SIGKILL));
        command
            .arg("upload")
            .args(["--server", url])
            .args(["--library", &self.library.to_string()])
            .arg("--state")
            .arg(self.dir.path().join("state"))
            .args(paths)
            .env("PHOTOLIB_TOKEN", self.ann.to_string())
            .kill_on_drop(true);
        command
    }

    /// A folder `name` in the scratch directory with `files`, each holding its own path as bytes unless given.
    fn folder(&self, name: &str, files: &[&str]) -> PathBuf {
        let root = self.dir.path().join(name);
        std::fs::create_dir_all(&root).unwrap();
        for file in files {
            let path = root.join(file);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, file.as_bytes()).unwrap();
        }
        root
    }

    /// A folder `name` with `clip.mov`, `length` bytes that do not repeat within a MiB.
    fn video(&self, name: &str, length: usize) -> (PathBuf, Vec<u8>) {
        let root = self.folder(name, &[]);
        let video: Vec<u8> = (0..length).map(|i| (i * 7919 % 1021) as u8).collect();
        std::fs::write(root.join("clip.mov"), &video).unwrap();
        (root, video)
    }

    /// The bytes the server has kept of its one incomplete upload.
    async fn received(&self) -> i64 {
        let query = sqlx::query_scalar("SELECT received FROM uploads WHERE completed_at IS NULL");
        query.fetch_one(&self.pool).await.unwrap()
    }

    async fn complete(&self) -> i64 {
        let query = sqlx::query_scalar("SELECT count(*) FROM uploads WHERE completed_at IS NOT NULL");
        query.fetch_one(&self.pool).await.unwrap()
    }

    /// The hash, length and completeness of every upload into the library.
    async fn uploads(&self) -> Vec<(String, i64, bool)> {
        let rows: Vec<(Vec<u8>, i64, bool)> = sqlx::query_as(
            "SELECT hash, length, completed_at IS NOT NULL FROM uploads WHERE library_id = $1 ORDER BY 1, 2, 3",
        )
        .bind(self.library)
        .fetch_all(&self.pool)
        .await
        .unwrap();
        rows.into_iter()
            .map(|(hash, length, complete)| (Hash(hash.try_into().unwrap()).to_string(), length, complete))
            .collect()
    }
}

/// What uploading these contents once each leaves on the server, as `Server::uploads` lists it.
fn uploaded(contents: impl IntoIterator<Item = impl AsRef<[u8]>>) -> Vec<(String, i64, bool)> {
    let mut uploads: Vec<_> = contents
        .into_iter()
        .map(|c| (Hash::of(c.as_ref()).to_string(), c.as_ref().len() as i64, true))
        .collect();
    uploads.sort();
    uploads
}

fn succeeded(output: &Output) {
    assert!(
        output.status.success(),
        "{:?}\n{}\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[tokio::test]
async fn uploads_every_photo_and_video_of_a_folder() {
    let s = server().await;
    let files = ["a.jpg", "2024/b.heic", "2024/trip/c.mp4"];
    let root = s.folder("photos", &files);
    std::fs::write(root.join("empty.png"), "").unwrap();
    let output = s.run(&[&root], &[]).await;
    succeeded(&output);
    assert_eq!(s.uploads().await, uploaded(files.into_iter().chain([""])));
}

/// The rules of the apps' folder sources: photos and videos only, without what `.photolibignore` and the defaults
/// (NAS thumbnails, trash folders) exclude.
#[tokio::test]
async fn skips_what_a_folder_source_would_skip() {
    let s = server().await;
    let root = s.folder(
        "photos",
        &[
            "a.jpg",
            "Raw/c.DNG",
            "notes.txt",
            "@eaDir/a.jpg/SYNOPHOTO_THUMB_XL.jpg",
            "private/b.jpg",
            "2024/.thumbnails/d.jpg",
        ],
    );
    std::fs::write(root.join(".photolibignore"), "private/\n").unwrap();
    succeeded(&s.run(&[&root], &[]).await);
    assert_eq!(s.uploads().await, uploaded(["a.jpg", "Raw/c.DNG"]));
}

/// As in the apps' folder sources, a name of the root that is, in another case, the same file (here a hard link)
/// shows a case-insensitive volume, where ignore rules match names in any case.
#[cfg(unix)]
#[tokio::test]
async fn ignore_rules_match_names_in_any_case_where_the_volume_does() {
    let s = server().await;
    let root = s.folder("photos", &["a.jpg", "2024/drafts/b.jpg"]);
    std::fs::write(root.join("2024/.photolibignore"), "DRAFTS/\n").unwrap();
    let planned = async || events(&s.run(&[&root], &["--dry-run", "--json"]).await)[0].clone();
    assert_eq!(planned().await, json!({"event": "plan", "files": 2, "bytes": 22}));
    std::fs::hard_link(root.join("a.jpg"), root.join("A.JPG")).unwrap();
    assert_eq!(planned().await, json!({"event": "plan", "files": 2, "bytes": 10}));
}

/// The JSON lines a run printed.
fn events(output: &Output) -> Vec<serde_json::Value> {
    std::str::from_utf8(&output.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}

#[tokio::test]
async fn a_dry_run_lists_what_a_run_would_upload_and_sends_nothing() {
    let s = server().await;
    let root = s.folder("photos", &["a.jpg", "b.jpg"]);
    let dry = s.run(&[&root], &["--dry-run"]).await;
    succeeded(&dry);
    let stdout = String::from_utf8_lossy(&dry.stdout);
    assert!(stdout.contains("a.jpg") && stdout.contains("b.jpg"), "{stdout}");
    assert_eq!(s.uploads().await, []);

    std::fs::write(root.join("c.jpg"), "c").unwrap();
    succeeded(&s.run(&[&root.join("a.jpg")], &[]).await);
    let dry = s.run(&[&root], &["--dry-run", "--json"]).await;
    succeeded(&dry);
    let events = events(&dry);
    let new: Vec<_> = events.iter().filter(|e| e["status"] == "new").collect();
    assert_eq!(new.len(), 2, "{events:?}");
    assert_eq!(
        events.last().unwrap(),
        &json!({"event": "summary", "uploaded": 0, "duplicates": 0, "skipped": 1, "failed": 0, "new": 2})
    );
    assert_eq!(s.uploads().await, uploaded(["a.jpg"]));
}

#[tokio::test]
async fn json_lines_report_the_plan_each_file_progress_and_a_summary() {
    let s = server().await;
    let root = s.folder("photos", &["a.jpg", "b.jpg", "x/b.jpg"]);
    std::fs::write(root.join("x/b.jpg"), "b.jpg").unwrap();
    let video = std::fs::read(s.video("photos", 20 << 20).0.join("clip.mov")).unwrap();
    let run = s.run(&[&root], &["--json", "--jobs", "1"]).await;
    succeeded(&run);
    let lines = events(&run);
    let size = video.len() as u64;
    assert_eq!(lines[0], json!({"event": "plan", "files": 4, "bytes": 15 + size}));
    let path = |name: &str| root.canonicalize().unwrap().join(name).display().to_string();
    let file = |name: &str, content: &[u8], status: &str| {
        json!({"event": "file", "path": path(name), "size": content.len(),
            "status": status, "blake3": Hash::of(content).to_string()})
    };
    let progress = |sent: u64| json!({"event": "progress", "path": path("clip.mov"), "sent": sent, "size": size});
    assert_eq!(
        lines[1..],
        [
            file("a.jpg", b"a.jpg", "uploaded"),
            file("b.jpg", b"b.jpg", "uploaded"),
            progress(8 << 20),
            progress(16 << 20),
            file("clip.mov", &video, "uploaded"),
            file("x/b.jpg", b"b.jpg", "duplicate"),
            json!({"event": "summary", "uploaded": 3, "duplicates": 1, "skipped": 0, "failed": 0}),
        ]
    );

    let again = s.run(&[&root], &["--json"]).await;
    assert_eq!(
        events(&again),
        [
            json!({"event": "plan", "files": 0, "bytes": 0}),
            json!({"event": "summary", "uploaded": 0, "duplicates": 0, "skipped": 4, "failed": 0}),
        ]
    );
}

/// A refusal that every further file would get too stops the run: a full quota, or an API key the server does not
/// know.
#[tokio::test]
async fn a_full_quota_or_an_unknown_key_stops_the_run() {
    let s = server().await;
    let files = ["a.jpg", "b.jpg", "c.jpg", "d.jpg"];
    let root = s.folder("photos", &files);
    sqlx::query("UPDATE users SET quota_bytes = 12")
        .execute(&s.pool)
        .await
        .unwrap();
    let full = s.run(&[&root], &["--json", "--jobs", "1"]).await;
    assert!(!full.status.success());
    let statuses: Vec<_> = events(&full).into_iter().map(|e| e["status"].clone()).collect();
    assert_eq!(
        statuses,
        [
            json!(null),
            json!("uploaded"),
            json!("uploaded"),
            json!("failed"),
            json!(null)
        ]
    );
    let stderr = String::from_utf8_lossy(&full.stderr);
    assert!(stderr.contains("quota.exceeded"), "{stderr}");

    sqlx::query("UPDATE users SET quota_bytes = NULL")
        .execute(&s.pool)
        .await
        .unwrap();
    let mut stranger = s.upload(&[&root]);
    stranger.env("PHOTOLIB_TOKEN", Uuid::now_v7().to_string());
    let refused = stranger.args(["--json", "--jobs", "1"]).output().await.unwrap();
    assert!(!refused.status.success());
    let failed = events(&refused).iter().filter(|e| e["status"] == "failed").count();
    assert_eq!(failed, 1);
    let stderr = String::from_utf8_lossy(&refused.stderr);
    assert!(stderr.contains("session.required"), "{stderr}");
}

/// A server whose policy switches uploads off refuses the first file; the run stops there and says why (ADR-0240).
#[tokio::test]
async fn uploads_the_servers_policy_switches_off_stop_the_run_with_the_reason() {
    let s = server().await;
    let root = s.folder("photos", &["a.jpg", "b.jpg", "c.jpg"]);
    sqlx::query("INSERT INTO policy_switches (capability, enabled) VALUES ('uploads', false)")
        .execute(&s.pool)
        .await
        .unwrap();
    let refused = s.run(&[&root], &["--json", "--jobs", "1"]).await;
    assert!(!refused.status.success());
    let failed = events(&refused).iter().filter(|e| e["status"] == "failed").count();
    assert_eq!((failed, s.complete().await), (1, 0));
    let stderr = String::from_utf8_lossy(&refused.stderr);
    assert!(stderr.contains("permission_denied: policy.disabled"), "{stderr}");
}

/// A run signs in with an API key that may contribute; beyond the key's rate, it waits rather than stopping.
#[tokio::test]
async fn an_api_key_s_rate_slows_the_run_down_without_stopping_it() {
    let s = server().await;
    let key = ApiKey {
        name: "cli".into(),
        scopes: vec![ApiKeyScope::API_KEY_SCOPE_CONTRIBUTE.into()],
        expires_at: Some(Timestamp {
            seconds: 1 << 35,
            ..Default::default()
        })
        .into(),
        requests_per_minute: 60,
        ..Default::default()
    };
    let keys = ApiKeys::new(s.pool.clone());
    let (_, secret) = keys.create(s.ann, key).await.unwrap();
    // A creation and an append each: a minute's worth of requests and four more.
    let files: Vec<_> = (0..32).map(|i| format!("{i}.jpg")).collect();
    let root = s.folder("photos", &files.iter().map(String::as_str).collect::<Vec<_>>());
    let mut run = s.upload(&[&root]);
    succeeded(&run.env("PHOTOLIB_TOKEN", secret).output().await.unwrap());
    assert_eq!(s.uploads().await, uploaded(&files));
}

#[tokio::test]
async fn a_second_run_uploads_only_what_changed() {
    let s = server().await;
    let files = ["a.jpg", "b.jpg", "c.jpg"];
    let root = s.folder("photos", &files);
    succeeded(&s.run(&[&root], &[]).await);
    let again = s.run(&[&root], &[]).await;
    succeeded(&again);
    assert_eq!(s.uploads().await, uploaded(files), "{again:?}");

    std::fs::write(root.join("b.jpg"), "b, edited").unwrap();
    succeeded(&s.run(&[&root], &[]).await);
    assert_eq!(s.uploads().await, uploaded(files.into_iter().chain(["b, edited"])));
}

#[tokio::test]
async fn the_same_photo_in_several_places_is_uploaded_once() {
    let s = server().await;
    let root = s.folder("photos", &["a.jpg", "b.jpg"]);
    let copies = s.folder("copies", &[]);
    for copy in ["a.jpg", "a copy.jpg", "x/a.jpg"] {
        std::fs::create_dir_all(copies.join("x")).unwrap();
        std::fs::copy(root.join("a.jpg"), copies.join(copy)).unwrap();
    }
    succeeded(&s.run(&[&root, &copies], &[]).await);
    succeeded(&s.run(&[&root, &copies], &[]).await);
    assert_eq!(s.uploads().await, uploaded(["a.jpg", "b.jpg"]));
}

/// The client's appends.
const APPEND: u64 = 8 << 20;

/// nginx refuses requests over 1 MiB unless told otherwise.
#[tokio::test]
async fn appends_shrink_to_pass_a_proxy_s_request_cap() {
    let s = server().await;
    s.cap.store(1 << 20, SeqCst);
    let (root, video) = s.video("videos", 3 << 20);
    succeeded(&s.run(&[&root], &[]).await);
    assert_eq!(s.uploads().await, uploaded([&video]));
}

/// A TCP proxy in front of the server that counts the bytes clients send. Once `stall` of them have passed, it
/// swallows the rest as a network that went away does, until the client gives up; once `cut` have, it closes that
/// connection, once.
struct Proxy {
    url: String,
    forwarded: Arc<AtomicU64>,
    stall: Arc<AtomicU64>,
    cut: Arc<AtomicU64>,
    accepting: tokio::task::JoinHandle<()>,
}

async fn proxy(server: &str) -> Proxy {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let to = server.strip_prefix("http://").unwrap().to_owned();
    let never = || Arc::new(AtomicU64::new(u64::MAX));
    let (forwarded, stall, cut) = (Arc::new(AtomicU64::new(0)), never(), never());
    let (count, limit, cut_at) = (forwarded.clone(), stall.clone(), cut.clone());
    let accepting = tokio::spawn(async move {
        loop {
            let (client, _) = listener.accept().await.unwrap();
            let server = TcpStream::connect(&to).await.unwrap();
            let (count, limit, cut_at) = (count.clone(), limit.clone(), cut_at.clone());
            tokio::spawn(async move {
                let (mut client_in, mut client_out) = client.into_split();
                let (mut server_in, mut server_out) = server.into_split();
                let back = tokio::spawn(async move { tokio::io::copy(&mut server_in, &mut client_out).await });
                let mut buffer = vec![0; 64 << 10];
                while let Ok(n @ 1..) = client_in.read(&mut buffer).await {
                    let room = limit.load(SeqCst).saturating_sub(count.load(SeqCst));
                    let pass = n.min(room as usize);
                    if pass > 0 && server_out.write_all(&buffer[..pass]).await.is_err() {
                        break;
                    }
                    if count.fetch_add(pass as u64, SeqCst) + pass as u64 >= cut_at.load(SeqCst) {
                        cut_at.store(u64::MAX, SeqCst);
                        break;
                    }
                }
                back.abort();
            });
        }
    });
    Proxy {
        url,
        forwarded,
        stall,
        cut,
        accepting,
    }
}

impl Server {
    /// A folder `name` with one video of `length` bytes, which a run of `photolib upload` killed halfway through left
    /// on the server in part, as `proxy` saw it.
    async fn interrupted(&self, name: &str, length: usize) -> (PathBuf, Vec<u8>, Proxy) {
        let (root, video) = self.video(name, length);
        let p = proxy(&self.url).await;
        p.stall.store(length as u64 / 2, SeqCst);
        let mut run = self.upload_via(&p.url, &[&root]).spawn().unwrap();
        while p.forwarded.load(SeqCst) < length as u64 / 2 {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        run.kill().await.unwrap();
        // Once the server sees the end of the connection, it keeps what reached it of the append the kill cut short.
        let whole = (length as u64 / 2) / APPEND * APPEND;
        while self.received().await as u64 <= whole {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        (root, video, p)
    }
}

/// The second run reaches the server at another address, as a laptop does from home and from the office.
#[tokio::test]
async fn a_killed_run_resumes_the_upload_where_the_server_has_it() {
    let s = server().await;
    let (root, video, p) = s.interrupted("videos", 40 << 20).await;
    p.accepting.abort();
    let kept = s.received().await as u64;
    s.seen.lock().unwrap().clear();
    let elsewhere = proxy(&s.url).await;
    succeeded(&s.upload_via(&elsewhere.url, &[&root]).output().await.unwrap());
    assert_eq!(s.uploads().await, uploaded([&video]));
    // One resume, from where the server's copy ends, with no byte sent again.
    let rest = (kept..40 << 20).step_by(APPEND as usize);
    let appends = rest.map(|at| ("PATCH".into(), at, APPEND.min((40 << 20) - at)));
    let expected: Vec<_> = [("HEAD".into(), 0, 0)].into_iter().chain(appends).collect();
    assert_eq!(*s.seen.lock().unwrap(), expected);
}

#[tokio::test]
async fn an_upload_the_server_forgot_starts_over() {
    let s = server().await;
    let (root, video, _) = s.interrupted("videos", 20 << 20).await;
    // As a day without appends does.
    sqlx::query("DELETE FROM uploads").execute(&s.pool).await.unwrap();
    succeeded(&s.run(&[&root], &[]).await);
    assert_eq!(s.uploads().await, uploaded([&video]));
}

#[tokio::test]
async fn a_file_that_changed_during_its_upload_is_uploaded_as_it_is_now() {
    let s = server().await;
    let (root, mut video, _) = s.interrupted("videos", 20 << 20).await;
    // An editor that keeps the size and modification time.
    let file = std::fs::File::options()
        .write(true)
        .open(root.join("clip.mov"))
        .unwrap();
    let modified = file.metadata().unwrap().modified().unwrap();
    let last = video.len() - 1;
    video[0] ^= 1;
    video[last] ^= 1;
    std::fs::write(root.join("clip.mov"), &video).unwrap();
    file.set_modified(modified).unwrap();
    succeeded(&s.run(&[&root], &[]).await);
    assert_eq!(s.uploads().await, uploaded([&video]));
}

/// The connection breaks once while the upload is created, and once in its third append.
#[tokio::test]
async fn a_lost_connection_resumes_in_the_same_run() {
    let s = server().await;
    let (root, video) = s.video("videos", 20 << 20);
    let p = proxy(&s.url).await;
    p.cut.store(100, SeqCst);
    let first = s.upload_via(&p.url, &[&root]).output();
    let cut_again = async {
        while p.cut.load(SeqCst) != u64::MAX {
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        p.cut.store(p.forwarded.load(SeqCst) + (12 << 20), SeqCst);
    };
    let (output, ()) = tokio::join!(first, cut_again);
    succeeded(&output.unwrap());
    assert_eq!(s.uploads().await, uploaded([&video]));
    let sent = p.forwarded.load(SeqCst);
    assert!(sent < 25 << 20, "{sent} bytes sent");
}

/// 100,000 photos (`PHOTOLIB_CLI_FILES` changes how many), 32 at a time: a run killed a third of the way, a second
/// that completes them and a third that finds nothing to do. Every photo ends up uploaded exactly once.
#[tokio::test(flavor = "multi_thread")]
async fn uploads_100k_files_resumably_and_idempotently() {
    let count: usize = std::env::var("PHOTOLIB_CLI_FILES").map_or(100_000, |n| n.parse().unwrap());
    let s = server().await;
    let root = s.dir.path().join("card");
    let names: Vec<String> = (0..count).map(|i| format!("{:03}/IMG_{i:06}.jpg", i / 1000)).collect();
    for dir in names.iter().map(|name| &name[..3]).collect::<BTreeSet<_>>() {
        std::fs::create_dir_all(root.join(dir)).unwrap();
    }
    for name in &names {
        std::fs::write(root.join(name), name).unwrap();
    }
    let jobs = ["--jobs", "32"];
    let started = std::time::Instant::now();
    let mut run = s.upload(&[&root]);
    let mut run = run.args(jobs).stdout(std::process::Stdio::null()).spawn().unwrap();
    while s.complete().await < count as i64 / 3 {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    run.kill().await.unwrap();
    let killed = s.complete().await;

    succeeded(&s.run(&[&root], &jobs).await);
    let complete: Vec<_> = s.uploads().await.into_iter().filter(|u| u.2).collect();
    assert_eq!(complete, uploaded(&names));
    let orphans = s.uploads().await.len() - count;
    // A creation the killed run never heard back about expires in a day.
    assert!(orphans <= 32, "{orphans} uploads left incomplete");

    let again = std::time::Instant::now();
    succeeded(&s.run(&[&root], &jobs).await);
    assert_eq!(s.uploads().await.len(), count + orphans);
    eprintln!(
        "{count} files: {killed} before the kill, all in {:?}; a run with nothing to do took {:?}",
        again - started,
        again.elapsed()
    );
}
