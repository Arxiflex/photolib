//! Passkeys in a real browser (ADR-0088): Chrome registers one through the relay page and signs in with it, as apps do
//! through the system browser. Needs node and Chrome; the `web` part of tools/check.sh runs it.

use std::{process::Command, sync::Arc};

use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_proto::proto::photolib::api::v1::User;
use photolib_server::{accounts::Accounts, auth::token_hash, http, rpc, webauthn::RelyingParty};
use uuid::Uuid;

#[tokio::test]
#[ignore = "needs node and Chrome: the web part of tools/check.sh runs it"]
async fn chrome_adds_a_passkey_through_the_relay_and_signs_in_with_it() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let ann = User {
        handle: "ann".into(),
        display_name: "Ann".into(),
        ..Default::default()
    };
    let (ann, _) = Accounts::new(db.pool.clone()).create_first_admin(ann).await.unwrap();
    sqlx::query(
        "WITH device AS (
            INSERT INTO devices (id, user_id, name, platform) VALUES (gen_random_uuid(), $1::uuid, 'laptop', 'linux')
            RETURNING id
        )
        INSERT INTO sessions (id, device_id, token_hash, expires_at)
        SELECT gen_random_uuid(), id, $2, now() + interval '1 hour' FROM device",
    )
    .bind(&ann.user_id)
    .bind(token_hash("laptop"))
    .execute(&db.pool)
    .await
    .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    // http://localhost is a secure context, where WebAuthn runs without TLS.
    let origin = format!("http://localhost:{}", listener.local_addr().unwrap().port());
    let key = opaque_ke::ServerSetup::new(&mut rand_core::OsRng);
    let auth = rpc::Auth::new(db.pool.clone(), key).with_passkeys(RelyingParty::from_url(&origin));
    // Beneath a base path, as behind a proxy that serves other applications too.
    let api = http::under(
        "/photos",
        rpc::api(Uuid::now_v7().to_string(), None, Some(Arc::new(auth)), None),
    );
    tokio::spawn(async move { axum::serve(listener, api).await });

    let output = drive(&format!("{origin}/photos")).await;
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(
        output.status.success(),
        "{stdout}{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let signed_in: serde_json::Value = serde_json::from_str(stdout.trim()).unwrap();
    let token = signed_in["session"].as_str().unwrap();
    let (user, passkey): (String, String) = sqlx::query_as(
        "SELECT d.user_id::text, (SELECT name FROM passkeys WHERE last_used_at IS NOT NULL)
         FROM sessions s JOIN devices d ON d.id = s.device_id WHERE s.token_hash = $1",
    )
    .bind(token_hash(token))
    .fetch_one(&db.pool)
    .await
    .unwrap();
    assert_eq!((user, passkey), (ann.user_id, "Chrome".into()));
}

/// The driver fails on an error in the relay page's console, here one a stand-in page logs on purpose.
#[tokio::test]
#[ignore = "needs node and Chrome: the web part of tools/check.sh runs it"]
async fn the_driver_fails_on_an_error_the_page_logs() {
    const PAGE: &str = "<!doctype html><button id=go hidden></button><script>console.error('on', 'purpose')</script>";
    let relay = axum::Router::new().route("/passkey", axum::routing::get(|| async { axum::response::Html(PAGE) }));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let origin = format!("http://localhost:{}", listener.local_addr().unwrap().port());
    tokio::spawn(async move { axum::serve(listener, relay).await });
    let output = drive(&origin).await;
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !output.status.success() && stderr.contains("the relay page logged: console.error: on purpose"),
        "{stderr}"
    );
}

/// Runs passkeys.mjs against the server at `url`, as the session `laptop`.
async fn drive(url: &str) -> std::process::Output {
    let script = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/passkeys.mjs");
    let mut node = Command::new("node");
    node.args([script, url, "laptop"]);
    tokio::task::spawn_blocking(move || node.output())
        .await
        .unwrap()
        .unwrap()
}
