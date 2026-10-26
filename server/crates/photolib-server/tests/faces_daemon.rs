//! Faces through the `photolibd` binary, as an operator and a user meet them (ADR-0389): the daemon runs every role on
//! a PostgreSQL cluster with ONNX Runtime and the face models, an account signs in and uploads a portrait, and
//! nothing is found until the account agrees to the notice through the API; then the face job, which the scheduler's
//! sweep queues, finds the face; withdrawing deletes it. Needs the models `tools/ml/fetch.py` pins.

use std::{
    io::{BufRead, BufReader},
    net::SocketAddr,
    path::Path,
    process::Stdio,
    time::Duration,
};

use photolib_ml::testing;
use photolib_spawn::{Group, Signal, command, output, tool};
use serde_json::{Value, json};
use uuid::Uuid;

const TOOL: Duration = Duration::from_secs(120);

struct Daemon {
    _child: Group,
    addr: SocketAddr,
    setup_token: String,
}

impl Daemon {
    fn start(dir: &Path, url: &str, runtime: &Path, models: &Path) -> Self {
        let data = dir.join("data");
        std::fs::create_dir(&data).unwrap();
        let config = dir.join("photolib.yaml");
        let yaml = format!(
            "config_version: 1\nroles: [api, scheduler, worker:cpu, worker:io, ml]\nlisten: 127.0.0.1:0\n\
             data_dir: {}\ndatabase:\n  url: \"{url}\"\nml:\n  runtime: {}\n  models_dir: {}\n  ocr: false\n",
            data.display(),
            runtime.display(),
            models.display()
        );
        std::fs::write(&config, &yaml).unwrap();
        let mut photolibd = command(env!("CARGO_BIN_EXE_photolibd"), Signal::SIGTERM);
        photolibd
            .arg("--config")
            .arg(&config)
            .env_clear()
            .stderr(Stdio::piped());
        let mut child = Group::start(photolibd, Signal::SIGTERM);
        let (mut setup_token, mut log) = (String::new(), String::new());
        let mut lines = BufReader::new(child.stderr.take().unwrap()).lines();
        for line in lines.by_ref() {
            let line = line.unwrap();
            log += &line;
            let line: Value = serde_json::from_str(&line).unwrap_or_default();
            if let Some(token) = line["fields"]["setup_token"].as_str() {
                setup_token = token.into();
            }
            if line["fields"]["message"] == "listening" {
                let addr: SocketAddr = line["fields"]["addr"].as_str().unwrap().parse().unwrap();
                std::thread::spawn(move || lines.for_each(drop));
                return Self {
                    _child: child,
                    addr,
                    setup_token,
                };
            }
        }
        let status = child.wait().unwrap();
        panic!("photolibd exited ({status}) before it listened: {log}");
    }

    fn url(&self, path: &str) -> String {
        format!("http://{}{path}", self.addr)
    }

    /// A Connect call in JSON that must succeed.
    fn rpc(&self, method: &str, bearer: Option<&str>, body: &Value) -> Value {
        let url = self.url(&format!("/photolib.api.v1.{method}"));
        let auth = bearer.map(|token| format!("authorization: Bearer {token}"));
        let body = body.to_string();
        let mut args = vec![
            "-s",
            "-H",
            "content-type: application/json",
            "--data-binary",
            &body,
            &url,
        ];
        if let Some(auth) = &auth {
            args.extend(["-H", auth]);
        }
        let reply = output(tool("curl").args(args), TOOL);
        let json: Value = serde_json::from_slice(&reply.stdout)
            .unwrap_or_else(|_| panic!("{method}: {}", String::from_utf8_lossy(&reply.stdout)));
        assert!(json["code"].is_null(), "{method}: {json}");
        json
    }

    fn admin_and_session(&self) -> String {
        use base64::{Engine, engine::general_purpose::STANDARD};
        use opaque_ke::{
            ClientLogin, ClientLoginFinishParameters, ClientRegistration, ClientRegistrationFinishParameters,
            CredentialResponse, Identifiers, RegistrationResponse,
        };
        use photolib_server::auth::{CONTEXT, Suite};

        let admin = json!({ "setupToken": self.setup_token, "user": { "handle": "root", "displayName": "Root" } });
        let created = self.rpc("SetupService/CreateFirstAdmin", None, &admin);
        let setup = created["passwordSetup"]["token"].as_str().unwrap();
        let start = ClientRegistration::<Suite>::start(&mut rand_core::OsRng, b"pw").unwrap();
        let request = json!({
            "registrationRequest": STANDARD.encode(start.message.serialize()),
            "passwordSetupToken": setup,
        });
        let started = self.rpc("AuthService/StartPasswordSetup", None, &request);
        let response = STANDARD
            .decode(started["registrationResponse"].as_str().unwrap())
            .unwrap();
        let response = RegistrationResponse::deserialize(&response).unwrap();
        let finish = start
            .state
            .finish(
                &mut rand_core::OsRng,
                b"pw",
                response,
                ClientRegistrationFinishParameters::default(),
            )
            .unwrap();
        let record = json!({
            "registrationRecord": STANDARD.encode(finish.message.serialize()),
            "ksfParams": STANDARD.encode([&[1, 0, 4, 0, 0, 0, 0, 0, 3, 1][..], &[5; 16]].concat()),
            "passwordSetupToken": setup,
            "registrationId": started["registrationId"],
        });
        self.rpc("AuthService/FinishPasswordSetup", None, &record);

        let start = ClientLogin::<Suite>::start(&mut rand_core::OsRng, b"pw").unwrap();
        let ke1 = STANDARD.encode(start.message.serialize());
        let started = self.rpc("AuthService/StartLogin", None, &json!({ "handle": "root", "ke1": ke1 }));
        let ke2 = STANDARD.decode(started["ke2"].as_str().unwrap()).unwrap();
        let parameters = ClientLoginFinishParameters::new(Some(CONTEXT), Identifiers::default(), None);
        let ke2 = CredentialResponse::deserialize(&ke2).unwrap();
        let finish = start
            .state
            .finish(&mut rand_core::OsRng, b"pw", ke2, parameters)
            .unwrap();
        let body = json!({
            "loginId": started["loginId"],
            "ke3": STANDARD.encode(finish.message.serialize()),
            "device": { "name": "CLI", "platform": "linux" },
        });
        let finished = self.rpc("AuthService/FinishLogin", None, &body);
        finished["session"]["token"].as_str().unwrap().into()
    }

    /// Uploads `bytes` into `library` as the apps do, in one piece.
    fn upload(&self, session: &str, library: Uuid, bytes: &[u8], dir: &Path) {
        let auth = format!("authorization: Bearer {session}");
        let (length, hash) = (bytes.len().to_string(), photolib_storage::Hash::of(bytes).to_string());
        let url = self.url("/upload");
        let created = output(
            tool("curl").args([
                "-s",
                "-i",
                "-X",
                "POST",
                "-H",
                &auth,
                "-H",
                "upload-complete: ?0",
                "-H",
                &format!("upload-length: {length}"),
                "-H",
                &format!("photolib-library: {library}"),
                "-H",
                &format!("photolib-hash: {hash}"),
                &url,
            ]),
            TOOL,
        );
        let text = String::from_utf8_lossy(&created.stdout).to_string();
        assert!(text.starts_with("HTTP/1.1 201"), "{text}");
        let location = text
            .lines()
            .find_map(|l| {
                l.to_lowercase()
                    .starts_with("location: ")
                    .then(|| l[10..].trim().to_string())
            })
            .unwrap();
        let location = format!("{}/{}", url.rsplit_once('/').unwrap().0, location);
        let file = dir.join("piece");
        std::fs::write(&file, bytes).unwrap();
        let reply = output(
            tool("curl").args([
                "-s",
                "-o",
                "/dev/null",
                "-w",
                "%{http_code}",
                "-X",
                "PATCH",
                "-H",
                &auth,
                "-H",
                "content-type: application/partial-upload",
                "-H",
                "upload-offset: 0",
                "-H",
                "upload-complete: ?1",
                "--data-binary",
                &format!("@{}", file.display()),
                &location,
            ]),
            TOOL,
        );
        let status = String::from_utf8_lossy(&reply.stdout).to_string();
        assert!(["200", "204"].contains(&status.as_str()), "upload: {status}");
    }
}

async fn eventually<F, Fut>(what: &str, seconds: u64, mut check: F)
where
    F: FnMut() -> Fut,
    Fut: Future<Output = bool>,
{
    for _ in 0..seconds {
        if check().await {
            return;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    panic!("not within {seconds} s: {what}");
}

#[tokio::test(flavor = "multi_thread")]
async fn photolibd_finds_faces_only_after_the_account_agreed_and_forgets_them_on_withdrawal() {
    let (runtime, models, _) = testing::onnx();
    let db = photolib_db::testpg::database().await;
    let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let server = Daemon::start(dir.path(), &db.url, &runtime, models.path());
    let session = server.admin_and_session();
    let library = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, root_uri, store) \
         SELECT $1, id, 'Photos', 'managed', 'photos', 'local' FROM users WHERE handle = 'root'",
    )
    .bind(library)
    .execute(&db.pool)
    .await
    .unwrap();
    let portrait = std::fs::read(testing::photo("face-photo-armstrong-a")).unwrap();
    server.upload(&session, library, &portrait, dir.path());

    // The picture is ingested and rendered, and the sweep has run: with no consent, no job, scan or face exists.
    let count = |sql: &'static str| {
        let pool = db.pool.clone();
        async move { sqlx::query_scalar::<_, i64>(sql).fetch_one(&pool).await.unwrap() }
    };
    eventually("the picture's renditions and a sweep", 240, || async {
        count("SELECT count(*) FROM jobs WHERE type = 'faces-sweep' AND status = 'done'").await > 0
            && count("SELECT count(*) FROM jobs WHERE type = 'render' AND status = 'done'").await > 0
    })
    .await;
    for sql in [
        "SELECT count(*) FROM jobs WHERE type = 'faces'",
        "SELECT count(*) FROM face_scans",
        "SELECT count(*) FROM faces",
    ] {
        assert_eq!(count(sql).await, 0, "{sql}");
    }
    let state = server.rpc("FaceService/GetFaceConsent", Some(&session), &json!({}));
    assert_eq!(state["state"]["granted"], Value::Null, "{state}");

    // Agreeing starts it.
    let agreed = server.rpc(
        "FaceService/SetFaceConsent",
        Some(&session),
        &json!({ "granted": true, "noticeVersion": photolib_server::faces::NOTICE_VERSION }),
    );
    assert_eq!(agreed["state"]["granted"], true, "{agreed}");
    eventually("the face job", 300, || async {
        count("SELECT count(*) FROM faces").await > 0 && count("SELECT count(*) FROM face_scans").await > 0
    })
    .await;
    let asset: Uuid = sqlx::query_scalar("SELECT id FROM assets")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    let listed = server.rpc(
        "FaceService/ListFaces",
        Some(&session),
        &json!({ "assetId": asset.to_string() }),
    );
    let faces = listed["faces"].as_array().unwrap();
    assert_eq!(faces.len(), 1, "{listed}");
    assert!(faces[0]["score"].as_f64().unwrap() > 0.6, "{listed}");
    assert!(
        faces[0].get("embedding").is_none(),
        "an embedding never leaves the server: {listed}"
    );

    // Withdrawing deletes it.
    server.rpc(
        "FaceService/SetFaceConsent",
        Some(&session),
        &json!({ "granted": false, "noticeVersion": 1 }),
    );
    for sql in ["SELECT count(*) FROM faces", "SELECT count(*) FROM face_scans"] {
        assert_eq!(count(sql).await, 0, "{sql}");
    }
}
