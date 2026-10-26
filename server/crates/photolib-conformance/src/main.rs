//! The server that the official Connect conformance suite (`tools/connect_conformance.sh`) tests: the conformance
//! service on photolibd's Connect stack (`rpc::connect` served by `http::serve`), for the subset that
//! `connect-conformance.yaml` declares. The suite checks that error messages round-trip, so unlike photolibd's own
//! services this one sends them.
#![allow(clippy::disallowed_methods)]

use std::{
    collections::BTreeMap,
    io::{Read, Write},
    sync::Arc,
    time::Duration,
};

use buffa::Message;
use buffa_types::google::protobuf::Any;
use connectrpc::{
    ConnectError, ErrorCode, Limits, RequestContext, Response, ServiceRequest, ServiceResult, ServiceStream,
    error::ErrorDetail,
};
use futures::StreamExt;
use http::{HeaderMap, HeaderName, HeaderValue};
use photolib_server::{http::serve, rpc};
use tokio_util::sync::CancellationToken;

mod proto {
    include!(concat!(env!("OUT_DIR"), "/_connectrpc.rs"));
}
use proto::connectrpc::conformance::v1::{
    self as v1, __buffa::oneof::unary_response_definition::Response as Answer, ConformancePayload, ConformanceService,
    ConformanceServiceExt, UnaryResponseDefinition, conformance_payload::RequestInfo,
};

const REQUEST_INFO: &str = "connectrpc.conformance.v1.ConformancePayload.RequestInfo";

fn request_info(ctx: &RequestContext, request: &[u8], type_url: &str) -> RequestInfo {
    let mut headers = BTreeMap::<String, Vec<String>>::new();
    for (name, value) in ctx.headers() {
        let value = value.to_str().unwrap_or_default().to_string();
        headers.entry(name.to_string()).or_default().push(value);
    }
    RequestInfo {
        request_headers: headers
            .into_iter()
            .map(|(name, value)| v1::Header {
                name,
                value,
                ..Default::default()
            })
            .collect(),
        timeout_ms: ctx
            .headers()
            .get("connect-timeout-ms")
            .and_then(|value| value.to_str().ok()?.parse().ok()),
        requests: vec![Any {
            type_url: type_url.into(),
            value: request.to_vec().into(),
            ..Default::default()
        }],
        ..Default::default()
    }
}

fn payload(data: Vec<u8>, info: Option<RequestInfo>) -> ConformancePayload {
    ConformancePayload {
        data,
        request_info: info.into(),
        ..Default::default()
    }
}

fn headers(list: &[v1::Header]) -> HeaderMap {
    let mut map = HeaderMap::new();
    for header in list {
        let Ok(name) = HeaderName::try_from(header.name.as_str()) else {
            continue;
        };
        for value in header.value.iter().filter_map(|v| HeaderValue::try_from(v).ok()) {
            map.append(name.clone(), value);
        }
    }
    map
}

fn error(definition: &v1::Error) -> ConnectError {
    let code = u32::try_from(definition.code.to_i32()).ok();
    ConnectError::new(
        code.and_then(ErrorCode::from_grpc_code).unwrap_or(ErrorCode::Unknown),
        definition.message.clone().unwrap_or_default(),
    )
}

/// Answers a unary call the way `definition` asks: after its delay, the echoed request and data, or its error.
async fn answer<T>(
    ctx: &RequestContext,
    request: &[u8],
    type_url: &str,
    definition: Option<&UnaryResponseDefinition>,
    wrap: impl FnOnce(ConformancePayload) -> T,
) -> ServiceResult<T> {
    let info = request_info(ctx, request, type_url);
    let Some(definition) = definition else {
        return Ok(Response::new(wrap(payload(Vec::new(), Some(info)))));
    };
    tokio::time::sleep(Duration::from_millis(definition.response_delay_ms.into())).await;
    let (headers, trailers) = (
        headers(&definition.response_headers),
        headers(&definition.response_trailers),
    );
    let data = match &definition.response {
        Some(Answer::Error(definition)) => {
            return Err(error(definition)
                .with_detail(ErrorDetail::from_message(REQUEST_INFO, &info))
                .with_headers(headers)
                .with_trailers(trailers));
        }
        Some(Answer::ResponseData(data)) => data.clone(),
        None => Vec::new(),
    };
    let mut response = Response::new(wrap(payload(data, Some(info))));
    (response.headers, response.trailers) = (headers, trailers);
    Ok(response)
}

struct Conformance;

#[allow(refining_impl_trait)]
impl ConformanceService for Conformance {
    async fn unary(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, v1::UnaryRequest>,
    ) -> ServiceResult<v1::UnaryResponse> {
        let owned = request.to_owned_message();
        let definition = owned.response_definition.as_option();
        answer(
            &ctx,
            request.bytes(),
            v1::UnaryRequest::TYPE_URL,
            definition,
            |payload| v1::UnaryResponse {
                payload: payload.into(),
                ..Default::default()
            },
        )
        .await
    }

    async fn idempotent_unary(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, v1::IdempotentUnaryRequest>,
    ) -> ServiceResult<v1::IdempotentUnaryResponse> {
        let owned = request.to_owned_message();
        let definition = owned.response_definition.as_option();
        answer(
            &ctx,
            request.bytes(),
            v1::IdempotentUnaryRequest::TYPE_URL,
            definition,
            |payload| v1::IdempotentUnaryResponse {
                payload: payload.into(),
                ..Default::default()
            },
        )
        .await
    }

    async fn server_stream(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, v1::ServerStreamRequest>,
    ) -> ServiceResult<ServiceStream<v1::ServerStreamResponse>> {
        let info = request_info(&ctx, request.bytes(), v1::ServerStreamRequest::TYPE_URL);
        let Some(definition) = request.to_owned_message().response_definition.into_option() else {
            return Ok(Response::new(Box::pin(futures::stream::empty())));
        };
        let (headers, trailers) = (
            headers(&definition.response_headers),
            headers(&definition.response_trailers),
        );
        let failure = definition.error.as_option().map(error);
        if definition.response_data.is_empty()
            && let Some(failure) = failure
        {
            return Err(failure
                .with_detail(ErrorDetail::from_message(REQUEST_INFO, &info))
                .with_headers(headers)
                .with_trailers(trailers));
        }
        let delay = Duration::from_millis(definition.response_delay_ms.into());
        let mut info = Some(info);
        let messages = futures::stream::iter(definition.response_data).then(move |data| {
            let payload = payload(data, info.take());
            async move {
                tokio::time::sleep(delay).await;
                Ok(v1::ServerStreamResponse {
                    payload: payload.into(),
                    ..Default::default()
                })
            }
        });
        let mut response =
            Response::new(Box::pin(messages.chain(futures::stream::iter(failure.map(Err)))) as ServiceStream<_>);
        (response.headers, response.trailers) = (headers, trailers);
        Ok(response)
    }

    async fn client_stream(
        &self,
        _ctx: RequestContext,
        _requests: connectrpc::InboundStream<v1::ClientStreamRequest>,
    ) -> ServiceResult<v1::ClientStreamResponse> {
        Err(ConnectError::unimplemented("outside photolib's Connect subset"))
    }

    async fn bidi_stream(
        &self,
        _ctx: RequestContext,
        _requests: connectrpc::InboundStream<v1::BidiStreamRequest>,
    ) -> ServiceResult<ServiceStream<v1::BidiStreamResponse>> {
        Err(ConnectError::unimplemented("outside photolib's Connect subset"))
    }

    async fn unimplemented(
        &self,
        _ctx: RequestContext,
        _request: ServiceRequest<'_, v1::UnimplementedRequest>,
    ) -> ServiceResult<v1::UnimplementedResponse> {
        Err(ConnectError::unimplemented("ConformanceService.Unimplemented"))
    }
}

/// The runner's framing on stdin and stdout: a big-endian u32 length, then the message.
fn read_message<M: Message>() -> std::io::Result<M> {
    let mut stdin = std::io::stdin().lock();
    let mut length = [0; 4];
    stdin.read_exact(&mut length)?;
    let mut bytes = vec![0; u32::from_be_bytes(length) as usize];
    stdin.read_exact(&mut bytes)?;
    M::decode_from_slice(&bytes).map_err(std::io::Error::other)
}

fn write_message(message: &impl Message) -> std::io::Result<()> {
    let bytes = message.encode_to_vec();
    let mut stdout = std::io::stdout().lock();
    stdout.write_all(&(bytes.len() as u32).to_be_bytes())?;
    stdout.write_all(&bytes)?;
    stdout.flush()
}

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let mut registry = buffa::type_registry::TypeRegistry::new();
    buffa_types::register_wkt_types(&mut registry);
    v1::__buffa::register_types(&mut registry);
    buffa::type_registry::set_type_registry(registry);

    let config: v1::ServerCompatRequest = read_message()?;
    let limits = match config.message_receive_limit {
        0 => Limits::default(),
        limit => Limits::default().with_max_message_size(limit as usize),
    };
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    write_message(&v1::ServerCompatResponse {
        host: "127.0.0.1".into(),
        port: listener.local_addr()?.port().into(),
        ..Default::default()
    })?;
    let services = Arc::new(Conformance).register(connectrpc::Router::new());
    let app = axum::Router::new().fallback_service(rpc::connect(services, limits));
    serve(listener, app, CancellationToken::new(), Duration::ZERO).await
}
