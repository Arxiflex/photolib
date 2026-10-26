//! The sync RPC on the wire (ADR-0091): batches compressed as the device accepts, and NFR-PERF-5 measured through the
//! whole Connect stack. A binary of its own, so that no other test shares the database cluster while it measures.

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use axum::http::HeaderMap;
use buffa::Message;
use connectrpc::compression::CompressionRegistry;
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_proto::proto::photolib::{
    api::v1::{SyncRequest, SyncResponse},
    sync::v1::{StreamCursor, SyncBatch},
};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    keys::ApiKeys,
    rpc::{self, Caller, Sessions, Users},
};
use tower::ServiceExt;
use uuid::Uuid;

/// Signs a request as the account whose id is its bearer token.
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

/// The API of a new instance where `ann` owns library `L` with `count` assets, a file each, taken a minute apart.
/// Analysed, as autovacuum keeps a library at rest, and below the watermark.
async fn api(count: u32) -> (axum::Router, testpg::TestDb, String) {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    sqlx::raw_sql(&format!(
        "INSERT INTO users (id, handle, display_name) VALUES (md5('ann')::uuid, 'ann', 'Ann');
         INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES (md5('L')::uuid, md5('ann')::uuid, 'L', 'managed', 'l');
         INSERT INTO assets (id, library_id, owner_id, source, taken_utc, original_filename, width, height, media_kind)
         SELECT md5(n::text)::uuid, md5('L')::uuid, md5('ann')::uuid, 'upload',
             '2020-01-01Z'::timestamptz + n * interval '1 minute', 'IMG_' || n || '.jpg', 4000, 3000, 'image'
         FROM generate_series(1, {count}) n;
         INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size)
         SELECT gen_random_uuid(), id, 'original', 'local', 'o/' || id, 'image/jpeg', 4000000 FROM assets;
         ANALYZE;"
    ))
    .execute(&db.pool)
    .await
    .unwrap();
    testpg::settle(&db.pool).await;
    let users = Users::start(
        Accounts::new(db.pool.clone()),
        ApiKeys::new(db.pool.clone()),
        Arc::new(Bearer),
    );
    let app = rpc::api(
        Uuid::now_v7().to_string(),
        Some(Arc::new(users.await.unwrap())),
        None,
        None,
    );
    let ann: String = sqlx::query_scalar("SELECT md5('ann')::uuid::text")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    (app, db, ann)
}

/// A binary sync of `streams` with their cursors as `bearer`, accepting `encoding`: the encoding the server chose, the
/// bytes it sent and the batches.
async fn sync(
    app: &axum::Router,
    bearer: &str,
    streams: &[(String, Vec<u8>)],
    encoding: &str,
) -> (String, usize, Vec<SyncBatch>) {
    let request = SyncRequest {
        streams: streams
            .iter()
            .map(|(stream, cursor)| StreamCursor {
                stream: stream.clone(),
                cursor: cursor.clone(),
                ..Default::default()
            })
            .collect(),
        ..Default::default()
    };
    let body = request.encode_to_vec();
    let mut envelope = vec![0];
    envelope.extend((body.len() as u32).to_be_bytes());
    envelope.extend(body);
    let request = axum::http::Request::post("/photolib.api.v1.SyncService/Sync")
        .header("content-type", "application/connect+proto")
        .header("connect-accept-encoding", encoding)
        .header("authorization", format!("Bearer {bearer}"))
        .body(axum::body::Body::from(envelope))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let used = response.headers().get("connect-content-encoding");
    let used = used
        .map(|value| value.to_str().unwrap().to_string())
        .unwrap_or_default();
    let body = axum::body::to_bytes(response.into_body(), 1 << 31).await.unwrap();
    let (registry, mut batches, mut rest) = (CompressionRegistry::default(), vec![], &body[..]);
    while let [flags, a, b, c, d, tail @ ..] = rest {
        let (message, tail) = tail.split_at(u32::from_be_bytes([*a, *b, *c, *d]) as usize);
        rest = tail;
        let message = bytes::Bytes::copy_from_slice(message);
        let message = match flags & 1 {
            1 => registry.decompress_with_limit(&used, message, 1 << 30).unwrap(),
            _ => message,
        };
        match flags & 2 {
            0 => batches.push(
                SyncResponse::decode_from_slice(&message)
                    .unwrap()
                    .batch
                    .into_option()
                    .unwrap(),
            ),
            _ => assert_eq!(&message[..], b"{}", "the stream ended without an error"),
        }
    }
    (used, body.len(), batches)
}

fn rows(batches: &[SyncBatch], entity: &str) -> usize {
    let groups = batches.iter().flat_map(|batch| &batch.changes);
    groups
        .filter(|rows| rows.entity == entity && !rows.deleted)
        .map(|rows| rows.rows.len())
        .sum()
}

#[tokio::test(flavor = "multi_thread")]
async fn batches_are_compressed_with_zstd_or_gzip_as_the_device_accepts() {
    let (app, db, ann) = api(100).await;
    let pool = &db.pool;
    let library: String = sqlx::query_scalar("SELECT md5('L')::uuid::text")
        .fetch_one(pool)
        .await
        .unwrap();
    let streams = [("account".to_string(), vec![]), (format!("assets/{library}"), vec![])];
    let mut sent = vec![];
    for encoding in ["zstd", "gzip", "identity"] {
        let (used, _, batches) = sync(&app, &ann, &streams, encoding).await;
        sent.push((
            used,
            rows(&batches, "users"),
            rows(&batches, "assets"),
            rows(&batches, "asset_files"),
        ));
    }
    let expected = |encoding: &str| (encoding.to_string(), 1, 100, 100);
    assert_eq!(
        sent,
        [expected("zstd"), expected("gzip"), expected("")],
        "both streams in one call, compressed as the device accepts"
    );
}

/// The fastest of three runs of `run`: co-tenants of a loaded machine only ever add time (the fastest-sample method of
/// docs/dev/kernel-go-no-go.md).
async fn fastest<T, F: Future<Output = T>>(mut run: impl FnMut() -> F) -> (Duration, T) {
    let mut best = None;
    for _ in 0..3 {
        let started = Instant::now();
        let answer = run().await;
        let took = started.elapsed();
        if best.as_ref().is_none_or(|(fastest, _)| took < *fastest) {
            best = Some((took, answer));
        }
    }
    best.expect("a run")
}

/// NFR-PERF-5 on the server (`initial-sync-100k` in tools/perf/budgets.json): a 100k-asset library from scratch, then
/// one change, through the Connect stack in binary and zstd. Over a 1 Gbit/s LAN the bytes add about a tenth of a
/// second.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "a benchmark: tools/perf/run.sh runs it in a release build"]
async fn initial_sync_of_100k_assets_and_of_one_change() {
    let (app, db, ann) = api(100_000).await;
    let pool = &db.pool;
    let library: String = sqlx::query_scalar("SELECT md5('L')::uuid::text")
        .fetch_one(pool)
        .await
        .unwrap();
    let stream = format!("assets/{library}");
    let scratch = [(stream.clone(), vec![])];
    let (initial, (used, bytes, batches)) = fastest(|| sync(&app, &ann, &scratch, "zstd")).await;
    assert_eq!(used, "zstd");
    assert_eq!(
        (rows(&batches, "assets"), rows(&batches, "asset_files")),
        (100_000, 100_000)
    );
    sqlx::query("UPDATE assets SET rating = 5 WHERE id = md5('7')::uuid")
        .execute(pool)
        .await
        .unwrap();
    testpg::settle(pool).await;
    let after = [(stream, batches.last().unwrap().cursor.clone())];
    let (incremental, (_, _, one)) = fastest(|| sync(&app, &ann, &after, "zstd")).await;
    eprintln!("initial {initial:?} ({bytes} bytes), incremental {incremental:?}");
    assert_eq!((rows(&one, "assets"), rows(&one, "asset_files")), (1, 1));
    if let Ok(path) = std::env::var("PERF_RESULTS") {
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .unwrap();
        for (metric, value) in [
            ("standard", initial.as_secs_f64()),
            ("incremental", incremental.as_secs_f64() * 1e3),
        ] {
            let line = serde_json::json!({"budget": "initial-sync-100k", "metric": metric,
                "target": "server", "value": (value * 100.0).round() / 100.0});
            std::io::Write::write_all(&mut file, format!("{line}\n").as_bytes()).unwrap();
        }
    }
}
