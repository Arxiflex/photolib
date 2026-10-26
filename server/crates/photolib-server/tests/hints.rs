//! Real-time hints over a socket (ADR-0225): a change one device makes reaches another that follows hints, and that
//! device's sync, within 2 s. A binary of its own, as no other test's transaction may hold the watermark back meanwhile.

use std::{sync::Arc, time::Duration};

use axum::http::HeaderMap;
use bytes::Bytes;
use futures::StreamExt;
use http_body_util::{BodyExt, Empty};
use hyper_util::{client::legacy::Client, rt::TokioExecutor};
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_server::{
    accounts::Accounts,
    db::DbError,
    keys::ApiKeys,
    rpc::{self, Caller, Sessions, Users},
};
use photolib_spawn::{Running, within};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;
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

/// A Connect call in JSON as `bearer`, unary or (with `stream`) server-streaming: its messages.
async fn call(app: &axum::Router, procedure: &str, bearer: &str, body: &Value, stream: bool) -> Vec<Value> {
    let body = body.to_string().into_bytes();
    let (kind, body) = if stream {
        let length = u32::try_from(body.len()).unwrap().to_be_bytes();
        ("application/connect+json", [&[0][..], &length, &body].concat())
    } else {
        ("application/json", body)
    };
    let request = axum::http::Request::post(format!("/photolib.api.v1.{procedure}"))
        .header("content-type", kind)
        .header("authorization", format!("Bearer {bearer}"))
        .body(axum::body::Body::from(body))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    assert!(response.status().is_success(), "{procedure}: {}", response.status());
    let body = axum::body::to_bytes(response.into_body(), 1 << 20).await.unwrap();
    if !stream {
        return vec![serde_json::from_slice(&body).unwrap()];
    }
    let (mut messages, mut rest) = (vec![], &body[..]);
    while let [flags, a, b, c, d, tail @ ..] = rest {
        let (message, tail) = tail.split_at(u32::from_be_bytes([*a, *b, *c, *d]) as usize);
        if flags & 2 == 0 {
            messages.push(serde_json::from_slice(message).unwrap());
        }
        rest = tail;
    }
    messages
}

type Body = std::pin::Pin<Box<dyn futures::Stream<Item = Bytes> + Send>>;

/// The next event of a channel, keep-alive comments left out; none once it ended.
async fn event(body: &mut Body, text: &mut String) -> Option<String> {
    loop {
        if let Some(end) = text.find("\n\n") {
            let event: String = text.drain(..end + 2).collect();
            if !event.starts_with(':') {
                return Some(event);
            }
            continue;
        }
        text.push_str(std::str::from_utf8(&body.next().await?).unwrap());
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_change_on_one_device_reaches_another_that_follows_hints_within_2_s() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    sqlx::raw_sql(include_str!("../../photolib-authz/tests/world.sql"))
        .execute(&db.pool)
        .await
        .unwrap();
    testpg::settle(&db.pool).await;
    let (ann, root, l2): (String, String, String) =
        sqlx::query_as("SELECT md5('ann')::uuid::text, md5('root')::uuid::text, md5('L2')::uuid::text")
            .fetch_one(&db.pool)
            .await
            .unwrap();
    let (accounts, keys) = (Accounts::new(db.pool.clone()), ApiKeys::new(db.pool.clone()));
    let users = Arc::new(Users::start(accounts, keys, Arc::new(Bearer)).await.unwrap());
    let shutdown = CancellationToken::new();
    let app =
        rpc::api("e".into(), Some(users.clone()), None, None).merge(rpc::hints("e".into(), users, shutdown.clone()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let at = listener.local_addr().unwrap();
    tokio::spawn(axum::serve(listener, app.clone()).into_future());

    // Ann's phone follows her account, her library L2, and a library that does not exist.
    let l9 = Uuid::now_v7();
    let request = axum::http::Request::get(format!("http://{at}/events?streams=account,assets/{l2},assets/{l9}"))
        .header("authorization", format!("Bearer {ann}"))
        .body(Empty::<Bytes>::new())
        .unwrap();
    let response = Client::builder(TokioExecutor::new())
        .build_http()
        .request(request)
        .await
        .unwrap();
    assert_eq!(response.headers()["content-type"], "text/event-stream");
    let mut body: Body = Box::pin(response.into_body().into_data_stream().map(Result::unwrap));
    let mut text = String::new();
    let first = format!("data: account\ndata: assets/{l2}\n\n");
    assert_eq!(event(&mut body, &mut text).await.unwrap(), first, "what Ann may read");
    let sync = |cursor: Value| {
        let request = json!({ "streams": [{ "stream": "account", "cursor": cursor }] });
        let (app, ann) = (&app, &ann);
        async move { call(app, "SyncService/Sync", ann, &request, true).await }
    };
    let cursor = sync(json!("")).await.last().unwrap()["batch"]["cursor"].clone();

    // The administrator's console renames her.
    let renamed = Running::start();
    let rename = json!({ "user": { "userId": ann, "displayName": "Ann B" }, "updateMask": "displayName" });
    call(&app, "UserService/UpdateUser", &root, &rename, false).await;
    assert_eq!(event(&mut body, &mut text).await.unwrap(), "data: account\n\n");
    assert!(json!(sync(cursor).await).to_string().contains("Ann B"));
    let took = renamed.elapsed();
    println!("the rename reached the phone in {took:?}");
    assert!(
        took < Duration::from_secs(2),
        "the change took {took:?} to reach the phone"
    );

    shutdown.cancel();
    let ended = within(Duration::from_secs(5), event(&mut body, &mut text)).await;
    assert_eq!(ended.unwrap(), None, "the channel ends when photolibd stops");
}
