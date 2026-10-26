//! Media delivery (photolib-design docs/08 §4.5, ADR-0022 point 5, ADR-0084): `/media/{asset}/{role}` on
//! photolibd's API as clients see it: who gets which bytes, the cache headers, ranges, and object stores.

use std::{sync::Arc, time::Duration};

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
use photolib_proto::proto::photolib::api::v1::{ApiKey, ApiKeyScope};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    keys::ApiKeys,
    media::Media,
    rpc::{Caller, Sessions, Users},
};
use photolib_storage::{
    Hash,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
    s3::S3Store,
    testing::garage,
};
use sqlx::PgPool;
use tower::ServiceExt;
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

/// Ann's photo on the store `local` and the same original in her bucket on `b2` (Garage); Bea, who sees neither.
struct Server {
    app: Router,
    media: Arc<Media>,
    pool: PgPool,
    ann: Uuid,
    bea: Uuid,
    photo: Uuid,
    remote: Uuid,
    original: Vec<u8>,
    thumb: Vec<u8>,
    _dir: tempfile::TempDir,
    _db: testpg::TestDb,
}

async fn server() -> Server {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let dir = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let local = FsStore::open(dir.path(), Duration::from_secs(30)).await.unwrap();
    let b2 = S3Store::open(&garage(), Duration::from_secs(30)).unwrap();
    let candidates = vec![
        Candidate {
            name: "local".into(),
            store: Arc::new(local),
            adopt: true,
        },
        Candidate {
            name: "b2".into(),
            store: Arc::new(b2),
            adopt: false,
        },
    ];
    let stores = Stores::check(&db.pool, Uuid::now_v7(), candidates).await;
    let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
    let (ann, bea) = (Uuid::now_v7(), Uuid::now_v7());
    let (library, bucket, photo, remote) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann'), ($2, 'bea', 'Bea')")
        .bind(ann)
        .bind(bea)
        .execute(&db.pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, root_uri, store)
         VALUES ($1, $3, 'Photos', 'managed', 'p', 'local'), ($2, $3, 'Bucket', 'managed', 'b', 'b2')",
    )
    .bind(library)
    .bind(bucket)
    .bind(ann)
    .execute(&db.pool)
    .await
    .unwrap();
    // 3 MiB that differ at every offset, so that ranges and chunks show.
    let original: Vec<u8> = (0..3u32 << 20).map(|i| (i ^ (i >> 8) ^ (i >> 16)) as u8).collect();
    let thumb = b"RIFF\x04\0\0\0WEBP".to_vec();
    for (asset, lib, store, files) in [
        (
            photo,
            library,
            "local",
            vec![
                ("original", &original, "image/jpeg", None),
                ("thumb_s", &thumb, "image/webp", None),
            ],
        ),
        (
            remote,
            bucket,
            "b2",
            vec![
                ("original", &original, "image/jpeg", None),
                ("motion_extracted", &original, "video/mp4", Some(1000)),
            ],
        ),
    ] {
        sqlx::query(
            "INSERT INTO assets (id, library_id, owner_id, source, media_kind) VALUES ($1, $2, $3, 'upload', 'image')",
        )
        .bind(asset)
        .bind(lib)
        .bind(ann)
        .execute(&db.pool)
        .await
        .unwrap();
        for (role, bytes, mime, offset) in files {
            let key = format!("libraries/{lib}/{asset}/{role}");
            let staged = dir.path().join("staged");
            std::fs::write(&staged, bytes).unwrap();
            let op = journal.put(store, &key, &staged, Hash::of(bytes)).await.unwrap();
            let mut tx = db.pool.begin().await.unwrap();
            op.switch(&mut tx).await.unwrap();
            let size = offset.map_or(bytes.len() as i64, |offset: i64| bytes.len() as i64 - offset - 1000);
            let spec = (role == "thumb_s").then(|| serde_json::json!({"spec_id": "s"}));
            sqlx::query(
                "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash, byte_offset,
                   render_spec) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
            )
            .bind(Uuid::now_v7())
            .bind(asset)
            .bind(role)
            .bind(store)
            .bind(&key)
            .bind(mime)
            .bind(size)
            .bind(Hash::of(bytes).0.to_vec())
            .bind(offset)
            .bind(spec)
            .execute(&mut *tx)
            .await
            .unwrap();
            tx.commit().await.unwrap();
            op.finish().await.unwrap();
        }
    }
    let users = Users::start(
        Accounts::new(db.pool.clone()),
        ApiKeys::new(db.pool.clone()),
        Arc::new(Bearer),
    );
    let media = Arc::new(Media::new(
        db.pool.clone(),
        journal,
        Arc::new(users.await.unwrap()),
        [7; 32],
    ));
    Server {
        app: photolib_server::media::router(media.clone()),
        media,
        pool: db.pool.clone(),
        ann,
        bea,
        photo,
        remote,
        original,
        thumb,
        _dir: dir,
        _db: db,
    }
}

type Answer = (StatusCode, HeaderMap, Vec<u8>);

impl Server {
    async fn send(&self, request: Request<Body>) -> Answer {
        let response = self.app.clone().oneshot(request).await.unwrap();
        let (parts, body) = response.into_parts();
        let body = axum::body::to_bytes(body, 64 << 20).await.unwrap();
        (parts.status, parts.headers, body.to_vec())
    }

    /// `GET path` with `headers`.
    async fn get(&self, path: &str, headers: &[(&str, String)]) -> Answer {
        let mut request = Request::get(path);
        for (name, value) in headers {
            request = request.header(*name, value);
        }
        self.send(request.body(Body::empty()).unwrap()).await
    }

    async fn sign(&self, path: &str, who: &str) -> Answer {
        let request = Request::post(path).header("authorization", format!("Bearer {who}"));
        self.send(request.body(Body::empty()).unwrap()).await
    }
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> &'a str {
    headers.get(name).map_or("", |value| value.to_str().unwrap())
}

fn bearer(who: impl std::fmt::Display) -> Vec<(&'static str, String)> {
    vec![("authorization", format!("Bearer {who}"))]
}

/// Nothing at all: an empty 404 that no cache keeps.
fn nothing((status, headers, body): Answer, what: &str) {
    assert_eq!(status, StatusCode::NOT_FOUND, "{what}");
    assert!(body.is_empty(), "{what}");
    assert_eq!(header(&headers, "cache-control"), "private, no-store", "{what}");
}

#[tokio::test]
async fn media_goes_only_to_sessions_api_keys_and_signed_urls_and_guessable_paths_return_nothing() {
    let s = server().await;
    let (thumb, original) = (
        format!("/media/{}/thumb_s", s.photo),
        format!("/media/{}/original", s.photo),
    );
    let (status, headers, body) = s.get(&thumb, &bearer(s.ann)).await;
    assert_eq!((status, body), (StatusCode::OK, s.thumb.clone()));
    let etag = format!("\"{}\"", Hash::of(&s.thumb));
    assert_eq!(
        ["content-type", "cache-control", "etag", "accept-ranges"].map(|name| header(&headers, name)),
        ["image/webp", "private, no-cache", etag.as_str(), "bytes"]
    );
    // Content-addressed by the hash clients sync, a rendition is cached for good, by the client only.
    let pinned = format!("{thumb}?h={}", Hash::of(&s.thumb));
    let (_, headers, _) = s.get(&pinned, &bearer(s.ann)).await;
    assert_eq!(
        header(&headers, "cache-control"),
        "private, max-age=31536000, immutable"
    );
    let (status, ..) = s.get(&thumb, &[bearer(s.ann).remove(0), ("if-none-match", etag)]).await;
    assert_eq!(status, StatusCode::NOT_MODIFIED);

    for (path, who) in [
        (&thumb, None),
        (&thumb, Some(s.bea)),
        (&original, Some(s.bea)),
        (&format!("/media/{}/thumb_s", Uuid::now_v7()), Some(s.ann)),
        (&format!("/media/{}/thumb_m", s.photo), Some(s.ann)),
        (&"/media/not-an-id/thumb_s".to_string(), Some(s.ann)),
        (&format!("{thumb}?t=00"), None),
        (&format!("{thumb}?t={}", "0".repeat(80)), None),
    ] {
        let headers = who.map(bearer).unwrap_or_default();
        nothing(s.get(path, &headers).await, &format!("{path} as {who:?}"));
    }

    // A key acts within its scopes: viewing is not downloading.
    let keys = ApiKeys::new(s.pool.clone());
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
    let (_, secret) = keys.create(s.ann, key).await.unwrap();
    assert_eq!(s.get(&thumb, &bearer(&secret)).await.0, StatusCode::OK);
    nothing(s.get(&original, &bearer(&secret)).await, "a view key's download");
    nothing(s.sign(&original, &secret).await, "a view key signing a download");

    // A signed URL, for players and <img>, points at the API and works without a header until it expires.
    let (status, _, body) = s.sign(&thumb, &s.ann.to_string()).await;
    assert_eq!(status, StatusCode::OK);
    let signed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let url = signed["url"].as_str().unwrap();
    assert!(url.starts_with(&format!("{thumb}?t=")), "{url}");
    let expires = signed["expires_at"].as_i64().unwrap();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    assert!((now + 3500..=now + 3600).contains(&expires), "{expires}");
    assert_eq!(s.get(url, &[]).await.2, s.thumb);
    let token = url.rsplit_once("t=").unwrap().1;
    nothing(
        s.get(&format!("{original}?t={token}"), &[]).await,
        "a token for another role",
    );
    nothing(
        s.get(&format!("/media/{}/thumb_s?t={token}", s.remote), &[]).await,
        "a token for another asset",
    );
    let mut forged = token.to_string();
    forged.replace_range(..1, if forged.starts_with('0') { "1" } else { "0" });
    nothing(s.get(&format!("{thumb}?t={forged}"), &[]).await, "a forged expiry");
    let expired = s.media.url(s.photo, "thumb_s", s.ann, now as u64 - 1);
    nothing(s.get(&expired, &[]).await, "an expired URL");
    nothing(s.sign(&thumb, &s.bea.to_string()).await, "Bea signing Ann's photo");
    sqlx::query("UPDATE users SET status = 'disabled' WHERE id = $1")
        .bind(s.ann)
        .execute(&s.pool)
        .await
        .unwrap();
    nothing(s.get(url, &[]).await, "a disabled account's URL");
}

#[tokio::test]
async fn media_on_an_object_store_streams_through_the_api_with_ranges_and_the_same_headers() {
    let s = server().await;
    let size = s.original.len();
    let paths = [
        format!("/media/{}/original", s.photo),
        format!("/media/{}/original", s.remote),
    ];
    let mut answers = vec![];
    for path in &paths {
        let (status, headers, body) = s.get(path, &bearer(s.ann)).await;
        assert_eq!((status, body.len()), (StatusCode::OK, size), "{path}");
        assert!(body == s.original, "{path}");
        assert_eq!(header(&headers, "content-length"), size.to_string());
        let mut answer = vec![headers];
        for (range, from, to) in [
            ("bytes=1048570-1048585", 1048570, 1048585),
            ("bytes=-10", size - 10, size - 1),
            (&format!("bytes={}-", size - 8), size - 8, size - 1),
            (&format!("bytes=5-{}", size * 2), 5, size - 1),
        ] {
            let (status, headers, body) = s
                .get(path, &[bearer(s.ann).remove(0), ("range", range.to_string())])
                .await;
            assert_eq!(status, StatusCode::PARTIAL_CONTENT, "{path} {range}");
            assert_eq!(
                header(&headers, "content-range"),
                format!("bytes {from}-{to}/{size}"),
                "{path} {range}"
            );
            assert!(body == s.original[from..=to], "{path} {range}");
            answer.push(headers);
        }
        let (status, headers, body) = s
            .get(path, &[bearer(s.ann).remove(0), ("range", format!("bytes={size}-"))])
            .await;
        assert_eq!((status, body.len()), (StatusCode::RANGE_NOT_SATISFIABLE, 0));
        assert_eq!(header(&headers, "content-range"), format!("bytes */{size}"));
        answers.push(answer);
    }
    let shown = |answer: &Vec<HeaderMap>| -> Vec<Vec<(String, String)>> {
        answer
            .iter()
            .map(|headers| {
                headers
                    .iter()
                    .map(|(n, v)| (n.to_string(), v.to_str().unwrap().into()))
                    .collect()
            })
            .collect()
    };
    assert_eq!(
        shown(&answers[0]),
        shown(&answers[1]),
        "a bucket's media looks exactly like a directory's"
    );
    assert!(answers.concat().iter().all(|h| h.get("location").is_none()));
    // A motion photo's video is a range of its original, served as a file of its own.
    let (status, headers, body) = s
        .get(&format!("/media/{}/motion_extracted", s.remote), &bearer(s.ann))
        .await;
    assert_eq!(
        (status, header(&headers, "content-type")),
        (StatusCode::OK, "video/mp4")
    );
    assert!(body == s.original[1000..size - 1000]);
}

/// A file that is no photo or video goes out only as a download, whatever type it says it is (ADR-0066): never as
/// something a browser shows, by URL or signed URL. A photo keeps its type.
#[tokio::test]
async fn a_file_that_is_no_photo_or_video_goes_out_only_as_a_download() {
    let s = server().await;
    let original = format!("/media/{}/original", s.photo);
    let (_, headers, _) = s.get(&original, &bearer(s.ann)).await;
    let shown =
        |headers: &HeaderMap| ["content-type", "content-disposition"].map(|name| header(headers, name).to_owned());
    assert_eq!(shown(&headers), ["image/jpeg", ""]);
    sqlx::query("UPDATE assets SET media_kind = NULL WHERE id = $1")
        .bind(s.photo)
        .execute(&s.pool)
        .await
        .unwrap();
    sqlx::query("UPDATE asset_files SET mime = 'image/svg+xml' WHERE asset_id = $1")
        .bind(s.photo)
        .execute(&s.pool)
        .await
        .unwrap();
    let (_, _, body) = s.sign(&original, &s.ann.to_string()).await;
    let signed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    for (path, headers) in [
        (original.as_str(), bearer(s.ann)),
        (signed["url"].as_str().unwrap(), vec![]),
    ] {
        let (status, got, body) = s.get(path, &headers).await;
        assert_eq!((status, body.len()), (StatusCode::OK, s.original.len()), "{path}");
        assert_eq!(shown(&got), ["application/octet-stream", "attachment"], "{path}");
    }
}

#[tokio::test]
async fn a_random_photo_is_a_rendition_the_caller_may_view_shown_in_a_standard_library_and_never_cached() {
    let s = server().await;
    for _ in 0..3 {
        let (status, headers, body) = s.get("/media/random/thumb_s", &bearer(s.ann)).await;
        assert_eq!(
            (status, body),
            (StatusCode::OK, s.thumb.clone()),
            "the one photo with a thumbnail"
        );
        assert_eq!(
            ["content-type", "cache-control", "photolib-asset"].map(|name| header(&headers, name)),
            ["image/webp", "private, no-store", s.photo.to_string().as_str()]
        );
    }
    nothing(
        s.get("/media/random/thumb_s", &bearer(s.bea)).await,
        "Bea may view none",
    );
    nothing(s.get("/media/random/thumb_s", &[]).await, "nobody signed in");
    nothing(s.get("/media/random/original", &bearer(s.ann)).await, "an original");
    for hidden in [
        "UPDATE assets SET locked = true WHERE id = $1",
        "UPDATE assets SET archived = true WHERE id = $1",
        "UPDATE assets SET trashed_at = now() WHERE id = $1",
        "UPDATE libraries SET privacy = 'private' WHERE id = (SELECT library_id FROM assets WHERE id = $1)",
    ] {
        let mut tx = s.pool.begin().await.unwrap();
        sqlx::query(hidden).bind(s.photo).execute(&mut *tx).await.unwrap();
        let answer = s.get("/media/random/thumb_s", &bearer(s.ann)).await;
        assert_eq!(answer.0, StatusCode::OK, "{hidden}: shown until it commits");
        tx.commit().await.unwrap();
        nothing(s.get("/media/random/thumb_s", &bearer(s.ann)).await, hidden);
        let undo = hidden
            .replace("= true", "= false")
            .replace("now()", "NULL")
            .replace("'private'", "'standard'");
        sqlx::query(&undo).bind(s.photo).execute(&s.pool).await.unwrap();
    }
}

/// The edited version of a photo is served as `edit_export` only while the version it was made for is the current one:
/// a revert, or a newer edit not yet exported, never hands out an older picture as the edited one.
#[tokio::test]
async fn the_export_of_a_version_goes_out_only_while_that_version_is_current() {
    let s = server().await;
    let (edit, other) = (Uuid::now_v7(), Uuid::now_v7());
    for id in [edit, other] {
        sqlx::query("INSERT INTO versions (id, asset_id, kind) VALUES ($1, $2, 'edit')")
            .bind(id)
            .bind(s.photo)
            .execute(&s.pool)
            .await
            .unwrap();
    }
    // The export is the original's bytes, which are in the store.
    sqlx::query(
        "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash, render_spec)
         SELECT $2, asset_id, 'edit_export', storage, key, 'image/jpeg', size, content_hash,
                jsonb_build_object('spec_id', 'x', 'version_id', $1::text)
         FROM asset_files WHERE asset_id = $3 AND role = 'original'",
    )
    .bind(edit)
    .bind(Uuid::now_v7())
    .bind(s.photo)
    .execute(&s.pool)
    .await
    .unwrap();
    let path = format!("/media/{}/edit_export", s.photo);
    let current = |version: Option<Uuid>| {
        sqlx::query("UPDATE assets SET current_version_id = $1 WHERE id = $2")
            .bind(version)
            .bind(s.photo)
            .execute(&s.pool)
    };
    current(Some(edit)).await.unwrap();
    let (status, headers, body) = s.get(&path, &bearer(s.ann)).await;
    assert_eq!(
        (status, body.len(), header(&headers, "content-type")),
        (StatusCode::OK, s.original.len(), "image/jpeg")
    );
    nothing(s.get(&path, &bearer(s.bea)).await, "another account");
    current(Some(other)).await.unwrap();
    nothing(s.get(&path, &bearer(s.ann)).await, "the export is of another version");
    current(None).await.unwrap();
    nothing(s.get(&path, &bearer(s.ann)).await, "no version is current");
}
