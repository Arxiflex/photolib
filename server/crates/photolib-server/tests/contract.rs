//! Contract tests: what a Connect client sees on the wire from photolibd's API. A change here breaks clients.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use buffa::Message;
use photolib_proto::proto::photolib::api::v1::GetServerInfoResponse;
use photolib_server::rpc;
use serde_json::json;
use tower::ServiceExt;
use uuid::Uuid;

const GET_SERVER_INFO: &str = "/photolib.api.v1.ServerInfoService/GetServerInfo";

async fn call(instance: Uuid, content_type: &str, body: &'static [u8]) -> (StatusCode, Vec<u8>) {
    call_api(rpc::api(instance.to_string(), None, None, None), content_type, body).await
}

async fn call_api(api: axum::Router, content_type: &str, body: &'static [u8]) -> (StatusCode, Vec<u8>) {
    let request = Request::post(GET_SERVER_INFO)
        .header("content-type", content_type)
        .body(Body::from(body))
        .unwrap();
    let response = api.oneshot(request).await.unwrap();
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), 1 << 20).await;
    (status, body.unwrap().to_vec())
}

#[tokio::test]
async fn server_info_in_json_names_the_versions_the_capabilities_and_the_epoch() {
    let instance = Uuid::now_v7();
    let (status, body) = call(instance, "application/json", b"{}").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
        json!({
            "apiVersion": "1.0",
            "minClientVersion": "0.0.0",
            "capabilities": ["error.detail.v1", "events.v1", "faces.v1", "search.text.v1", "sync.hints.v1", "sync.mutations.v1", "sync.stream.v1", "sync.trash.v1", "sync.versions.v1", "upload.rufh"],
            "epoch": instance.to_string(),
        })
    );
}

#[tokio::test]
async fn server_info_in_binary_carries_the_same_values() {
    let instance = Uuid::now_v7();
    let (status, body) = call(instance, "application/proto", b"").await;
    assert_eq!(status, StatusCode::OK);
    let info = GetServerInfoResponse::decode_from_slice(&body).unwrap();
    assert_eq!(
        (info.api_version, info.min_client_version, info.epoch),
        ("1.0".into(), "0.0.0".into(), instance.to_string())
    );
    assert_eq!(
        info.capabilities,
        [
            "error.detail.v1",
            "events.v1",
            "faces.v1",
            "search.text.v1",
            "sync.hints.v1",
            "sync.mutations.v1",
            "sync.stream.v1",
            "sync.trash.v1",
            "sync.versions.v1",
            "upload.rufh"
        ]
    );
    assert!(
        info.auth_methods.is_empty(),
        "a process without the account services offers no sign-in"
    );
}

#[tokio::test]
async fn server_info_names_opaque_when_passwords_sign_in() {
    let pool = sqlx::PgPool::connect_lazy("postgres://nobody@localhost/none").unwrap();
    let key = opaque_ke::ServerSetup::new(&mut rand_core::OsRng);
    let auth = std::sync::Arc::new(rpc::Auth::new(pool, key));
    let api = rpc::api(Uuid::now_v7().to_string(), None, Some(auth), None);
    let (status, body) = call_api(api, "application/json", b"{}").await;
    assert_eq!(status, StatusCode::OK);
    let info: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(info["authMethods"], json!(["AUTH_METHOD_OPAQUE"]));
}

#[tokio::test]
async fn errors_carry_a_code_and_no_prose_even_from_the_connect_layer() {
    for (content_type, body) in [
        ("application/json", &b"{\"bogus"[..]),
        ("application/proto", &b"\xff\xff\xff"[..]),
    ] {
        let (status, body) = call(Uuid::now_v7(), content_type, body).await;
        let error: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(status, StatusCode::BAD_REQUEST, "{error}");
        assert_eq!(error["code"], "invalid_argument", "{error}");
        assert!(error.get("message").is_none(), "{content_type}: {error}");
    }
}

#[test]
fn capabilities_are_sorted_unique_lowercase_dotted_names() {
    let valid = |name: &str| {
        name.contains('.')
            && name.split('.').all(|part| {
                part.starts_with(|c: char| c.is_ascii_lowercase() || c.is_ascii_digit())
                    && part
                        .chars()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
            })
    };
    assert!(
        rpc::CAPABILITIES.iter().all(|name| valid(name)),
        "{:?}",
        rpc::CAPABILITIES
    );
    assert!(
        rpc::CAPABILITIES.windows(2).all(|pair| pair[0] < pair[1]),
        "{:?}",
        rpc::CAPABILITIES
    );
    assert!(!valid("Sync.v2") && !valid("sync") && !valid("sync..v2") && !valid("sync stream.v2"));
}
