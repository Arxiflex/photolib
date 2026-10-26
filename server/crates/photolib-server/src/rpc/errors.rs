//! Errors as codes and parameters, never prose (F-13).

use std::collections::BTreeMap;

use axum::{
    body::{Body, Bytes},
    extract::Request,
    http::{
        HeaderMap, StatusCode,
        header::{CONTENT_LENGTH, CONTENT_TYPE},
    },
    middleware::Next,
    response::{IntoResponse, Response},
};
use bytes::BytesMut;
use connectrpc::{ConnectError, ErrorCode, error::ErrorDetail as Detail};
use futures::StreamExt;
use photolib_proto::proto::photolib::api::v1::ErrorDetail;
use serde_json::Value;

/// The flag of the envelope that ends a Connect stream; it carries the error, always as JSON.
const END_STREAM: u8 = 0x02;
/// Connect error bodies are a few hundred bytes.
const MAX_ERROR_BODY: usize = 64 * 1024;

/// A failure a client can render in its user's language: a Connect code, a reason code such as `asset.not_found`
/// and named parameters, sent as a `photolib.api.v1.ErrorDetail`. There is no message to fill in.
#[derive(Debug)]
pub struct ApiError {
    code: ErrorCode,
    reason: &'static str,
    params: BTreeMap<&'static str, String>,
}

impl ApiError {
    /// `reason` is lowercase dotted words (`asset.not_found`); prose panics, when the code compiles if the error is a
    /// `const`.
    pub const fn new(code: ErrorCode, reason: &'static str) -> Self {
        assert!(
            is_reason(reason),
            "an error reason is a code such as `asset.not_found`, not prose"
        );
        ApiError {
            code,
            reason,
            params: BTreeMap::new(),
        }
    }

    pub fn param(mut self, name: &'static str, value: impl ToString) -> Self {
        self.params.insert(name, value.to_string());
        self
    }
}

const fn is_reason(reason: &str) -> bool {
    let bytes = reason.as_bytes();
    let (mut at, mut dots, mut segment) = (0, 0, 0);
    while at < bytes.len() {
        match bytes[at] {
            b'.' if segment > 0 => (dots, segment) = (dots + 1, 0),
            b'a'..=b'z' | b'0'..=b'9' | b'_' => segment += 1,
            _ => return false,
        }
        at += 1;
    }
    dots > 0 && segment > 0
}

impl From<ApiError> for ConnectError {
    #[allow(
        clippy::disallowed_methods,
        reason = "the one ConnectError photolibd builds, without a message"
    )]
    fn from(error: ApiError) -> Self {
        let detail = ErrorDetail {
            code: error.reason.into(),
            params: error
                .params
                .into_iter()
                .map(|(name, value)| (name.into(), value))
                .collect(),
            ..Default::default()
        };
        let mut connect =
            ConnectError::new(error.code, "").with_detail(Detail::from_message("photolib.api.v1.ErrorDetail", &detail));
        connect.message = None;
        connect
    }
}

fn content_type(headers: &HeaderMap) -> &str {
    headers
        .get(CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
}

/// Refuses gRPC and gRPC-Web, which put prose in `grpc-message`, and strips the developer message from every Connect
/// error, including those the connectrpc crate writes itself for a malformed request.
pub async fn no_prose(request: Request, next: Next) -> Response {
    if content_type(request.headers()).starts_with("application/grpc") {
        return StatusCode::UNSUPPORTED_MEDIA_TYPE.into_response();
    }
    let response = next.run(request).await;
    let kind = content_type(response.headers());
    if kind.starts_with("application/connect+") {
        response.map(strip_end_stream)
    } else if kind == "application/json" && !response.status().is_success() {
        let (mut parts, body) = response.into_parts();
        let json = axum::body::to_bytes(body, MAX_ERROR_BODY).await.unwrap_or_default();
        parts.headers.remove(CONTENT_LENGTH);
        Response::from_parts(parts, Body::from(without_message(json, |value| Some(value))))
    } else {
        response
    }
}

/// `json` without the `message` of the error object that `error` selects; anything else passes unchanged.
fn without_message(json: Bytes, error: fn(&mut Value) -> Option<&mut Value>) -> Bytes {
    let Ok(mut value) = serde_json::from_slice::<Value>(&json) else {
        return json;
    };
    let removed = error(&mut value)
        .and_then(Value::as_object_mut)
        .and_then(|object| object.remove("message"));
    match removed {
        Some(_) => serde_json::to_vec(&value).map_or(json, Bytes::from),
        None => json,
    }
}

/// Passes the envelopes of a Connect stream through as they complete, the last one without its error message.
fn strip_end_stream(body: Body) -> Body {
    let mut pending = BytesMut::new();
    Body::from_stream(body.into_data_stream().map(move |chunk| {
        pending.extend_from_slice(&chunk?);
        let mut ready = BytesMut::new();
        while let Some(length) = pending
            .get(1..5)
            .map(|length| 5 + u32::from_be_bytes(length.try_into().unwrap()) as usize)
            .filter(|length| pending.len() >= *length)
        {
            let envelope = pending.split_to(length).freeze();
            if envelope[0] & END_STREAM == 0 {
                ready.extend_from_slice(&envelope);
                continue;
            }
            let end = without_message(envelope.slice(5..), |value| value.get_mut("error"));
            ready.extend_from_slice(&[envelope[0]]);
            ready.extend_from_slice(&(end.len() as u32).to_be_bytes());
            ready.extend_from_slice(&end);
        }
        Ok::<_, axum::Error>(ready.freeze())
    }))
}

#[cfg(test)]
mod tests {
    use axum::{Router, middleware, routing::post};
    use tower::ServiceExt;

    use super::*;

    #[test]
    fn an_api_error_reaches_the_client_as_a_code_and_an_error_detail_without_a_message() {
        let error = ConnectError::from(ApiError::new(ErrorCode::NotFound, "asset.not_found").param("asset_id", 42));
        assert_eq!((error.code, error.message), (ErrorCode::NotFound, None));
        let expected = ErrorDetail {
            code: "asset.not_found".into(),
            params: [("asset_id".to_string(), "42".to_string())].into_iter().collect(),
            ..Default::default()
        };
        let detail = Detail::from_message("photolib.api.v1.ErrorDetail", &expected);
        assert_eq!(error.details.len(), 1);
        assert_eq!(
            (&error.details[0].type_url, &error.details[0].value),
            (&detail.type_url, &detail.value)
        );
    }

    #[test]
    #[should_panic(expected = "not prose")]
    fn a_reason_that_is_prose_is_refused() {
        let _ = ApiError::new(ErrorCode::Internal, "Something went wrong");
    }

    const PROSE: &str = "the asset 42 does not exist";

    /// Sends a POST through `no_prose` to an inner handler that answers `status`, `content_type` and `chunks`.
    async fn through_no_prose(
        request_type: &'static str,
        status: StatusCode,
        content_type: &'static str,
        chunks: Vec<Vec<u8>>,
    ) -> (StatusCode, Vec<u8>) {
        let inner = move || async move {
            let stream = futures::stream::iter(chunks.into_iter().map(Ok::<_, std::io::Error>));
            (status, [(CONTENT_TYPE, content_type)], Body::from_stream(stream))
        };
        let app = Router::new()
            .route("/svc/Method", post(inner))
            .layer(middleware::from_fn(no_prose));
        let request = axum::http::Request::post("/svc/Method")
            .header(CONTENT_TYPE, request_type)
            .body(Body::empty())
            .unwrap();
        let response = app.oneshot(request).await.unwrap();
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), 1 << 20).await.unwrap();
        (status, body.to_vec())
    }

    fn json(bytes: &[u8]) -> serde_json::Value {
        serde_json::from_slice(bytes).unwrap()
    }

    #[tokio::test]
    async fn a_unary_error_loses_its_message_and_keeps_its_code_and_details() {
        let body = serde_json::json!({
            "code": "not_found", "message": PROSE, "details": [{"type": "photolib.api.v1.ErrorDetail", "value": "CgE"}]
        });
        let (status, bytes) = through_no_prose(
            "application/json",
            StatusCode::NOT_FOUND,
            "application/json",
            vec![body.to_string().into_bytes()],
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert_eq!(
            json(&bytes),
            serde_json::json!({"code": "not_found", "details": [{"type": "photolib.api.v1.ErrorDetail", "value": "CgE"}]})
        );
    }

    fn envelope(flags: u8, payload: &[u8]) -> Vec<u8> {
        let mut bytes = vec![flags];
        bytes.extend((payload.len() as u32).to_be_bytes());
        bytes.extend(payload);
        bytes
    }

    #[tokio::test]
    async fn a_stream_keeps_its_messages_and_its_end_loses_the_message_even_split_across_chunks() {
        let message = envelope(0, br#"{"epoch":"x"}"#);
        let end = serde_json::json!({"error": {"code": "internal", "message": PROSE}, "metadata": {"a": ["b"]}});
        let wire = [message.clone(), envelope(2, end.to_string().as_bytes())].concat();
        let chunks = vec![
            wire[..3].to_vec(),
            wire[3..message.len() + 7].to_vec(),
            wire[message.len() + 7..].to_vec(),
        ];
        let (status, bytes) = through_no_prose(
            "application/connect+json",
            StatusCode::OK,
            "application/connect+json",
            chunks,
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(bytes[..message.len()], message[..]);
        let rest = &bytes[message.len()..];
        assert_eq!(rest[0], 2);
        assert_eq!(
            u32::from_be_bytes(rest[1..5].try_into().unwrap()) as usize,
            rest.len() - 5
        );
        assert_eq!(
            json(&rest[5..]),
            serde_json::json!({"error": {"code": "internal"}, "metadata": {"a": ["b"]}})
        );
    }

    #[tokio::test]
    async fn successful_responses_pass_unchanged() {
        let body = br#"{"message":"a field that happens to be called message"}"#.to_vec();
        let (status, bytes) = through_no_prose(
            "application/json",
            StatusCode::OK,
            "application/json",
            vec![body.clone()],
        )
        .await;
        assert_eq!((status, bytes), (StatusCode::OK, body));
    }

    #[tokio::test]
    async fn grpc_and_grpc_web_are_refused_because_they_carry_prose_in_trailers() {
        for request_type in [
            "application/grpc",
            "application/grpc+proto",
            "application/grpc-web+proto",
        ] {
            let (status, bytes) =
                through_no_prose(request_type, StatusCode::OK, "application/grpc", vec![b"x".to_vec()]).await;
            assert_eq!(
                (status, bytes),
                (StatusCode::UNSUPPORTED_MEDIA_TYPE, Vec::new()),
                "{request_type}"
            );
        }
    }
}
