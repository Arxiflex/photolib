///Shorthand for `OwnedView<GetKeysRequestView<'static>>`.
pub type OwnedGetKeysRequestView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::GetKeysRequestView<'static>,
>;
///Shorthand for `OwnedView<GetKeysResponseView<'static>>`.
pub type OwnedGetKeysResponseView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::GetKeysResponseView<'static>,
>;
///Shorthand for `OwnedView<CreateKeysRequestView<'static>>`.
pub type OwnedCreateKeysRequestView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::CreateKeysRequestView<'static>,
>;
///Shorthand for `OwnedView<CreateKeysResponseView<'static>>`.
pub type OwnedCreateKeysResponseView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::CreateKeysResponseView<'static>,
>;
///Shorthand for `OwnedView<PutUnlockPathRequestView<'static>>`.
pub type OwnedPutUnlockPathRequestView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathRequestView<'static>,
>;
///Shorthand for `OwnedView<PutUnlockPathResponseView<'static>>`.
pub type OwnedPutUnlockPathResponseView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathResponseView<'static>,
>;
///Shorthand for `OwnedView<VerifyRecoveryKitRequestView<'static>>`.
pub type OwnedVerifyRecoveryKitRequestView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitRequestView<'static>,
>;
///Shorthand for `OwnedView<VerifyRecoveryKitResponseView<'static>>`.
pub type OwnedVerifyRecoveryKitResponseView = ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitResponseView<
        'static,
    >,
>;
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::GetKeysResponse>
for crate::proto::photolib::api::v1::__buffa::view::GetKeysResponseView<'_> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self, codec)
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::GetKeysResponse>
for ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::GetKeysResponseView<'static>,
> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self.reborrow(), codec)
    }
    /// An `OwnedView` still holds the buffer it was decoded from, so
    /// its large fields can be handed to the response body by
    /// reference count instead of copied. The bare view impl above
    /// cannot do this: it has borrows but no buffer to name.
    fn encode_segments(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::connectrpc::EncodedBody, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body_segments(
            self.reborrow(),
            self.bytes(),
            codec,
        )
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::CreateKeysResponse>
for crate::proto::photolib::api::v1::__buffa::view::CreateKeysResponseView<'_> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self, codec)
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::CreateKeysResponse>
for ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::CreateKeysResponseView<'static>,
> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self.reborrow(), codec)
    }
    /// An `OwnedView` still holds the buffer it was decoded from, so
    /// its large fields can be handed to the response body by
    /// reference count instead of copied. The bare view impl above
    /// cannot do this: it has borrows but no buffer to name.
    fn encode_segments(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::connectrpc::EncodedBody, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body_segments(
            self.reborrow(),
            self.bytes(),
            codec,
        )
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::PutUnlockPathResponse>
for crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathResponseView<'_> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self, codec)
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::PutUnlockPathResponse>
for ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathResponseView<'static>,
> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self.reborrow(), codec)
    }
    /// An `OwnedView` still holds the buffer it was decoded from, so
    /// its large fields can be handed to the response body by
    /// reference count instead of copied. The bare view impl above
    /// cannot do this: it has borrows but no buffer to name.
    fn encode_segments(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::connectrpc::EncodedBody, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body_segments(
            self.reborrow(),
            self.bytes(),
            codec,
        )
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::VerifyRecoveryKitResponse>
for crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitResponseView<'_> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self, codec)
    }
}
impl ::connectrpc::Encodable<crate::proto::photolib::api::v1::VerifyRecoveryKitResponse>
for ::buffa::view::OwnedView<
    crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitResponseView<
        'static,
    >,
> {
    fn encode(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::buffa::bytes::Bytes, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body(self.reborrow(), codec)
    }
    /// An `OwnedView` still holds the buffer it was decoded from, so
    /// its large fields can be handed to the response body by
    /// reference count instead of copied. The bare view impl above
    /// cannot do this: it has borrows but no buffer to name.
    fn encode_segments(
        &self,
        codec: ::connectrpc::CodecFormat,
    ) -> ::std::result::Result<::connectrpc::EncodedBody, ::connectrpc::ConnectError> {
        ::connectrpc::__codegen::encode_view_body_segments(
            self.reborrow(),
            self.bytes(),
            codec,
        )
    }
}
/// Full service name for this service.
pub const KEY_SERVICE_SERVICE_NAME: &str = "photolib.api.v1.KeyService";
/// Static [`Spec`](::connectrpc::Spec) for the `GetKeys` RPC, as seen by the server; the generated client passes it with [`origin`](::connectrpc::Spec::origin) `Client` (compare across sides with [`Spec::same_method`](::connectrpc::Spec::same_method)).
pub const KEY_SERVICE_GET_KEYS_SPEC: ::connectrpc::Spec = ::connectrpc::Spec::server(
        "/photolib.api.v1.KeyService/GetKeys",
        ::connectrpc::StreamType::Unary,
    )
    .with_idempotency_level(::connectrpc::IdempotencyLevel::Unknown);
/// Static [`Spec`](::connectrpc::Spec) for the `CreateKeys` RPC, as seen by the server; the generated client passes it with [`origin`](::connectrpc::Spec::origin) `Client` (compare across sides with [`Spec::same_method`](::connectrpc::Spec::same_method)).
pub const KEY_SERVICE_CREATE_KEYS_SPEC: ::connectrpc::Spec = ::connectrpc::Spec::server(
        "/photolib.api.v1.KeyService/CreateKeys",
        ::connectrpc::StreamType::Unary,
    )
    .with_idempotency_level(::connectrpc::IdempotencyLevel::Unknown);
/// Static [`Spec`](::connectrpc::Spec) for the `PutUnlockPath` RPC, as seen by the server; the generated client passes it with [`origin`](::connectrpc::Spec::origin) `Client` (compare across sides with [`Spec::same_method`](::connectrpc::Spec::same_method)).
pub const KEY_SERVICE_PUT_UNLOCK_PATH_SPEC: ::connectrpc::Spec = ::connectrpc::Spec::server(
        "/photolib.api.v1.KeyService/PutUnlockPath",
        ::connectrpc::StreamType::Unary,
    )
    .with_idempotency_level(::connectrpc::IdempotencyLevel::Unknown);
/// Static [`Spec`](::connectrpc::Spec) for the `VerifyRecoveryKit` RPC, as seen by the server; the generated client passes it with [`origin`](::connectrpc::Spec::origin) `Client` (compare across sides with [`Spec::same_method`](::connectrpc::Spec::same_method)).
pub const KEY_SERVICE_VERIFY_RECOVERY_KIT_SPEC: ::connectrpc::Spec = ::connectrpc::Spec::server(
        "/photolib.api.v1.KeyService/VerifyRecoveryKit",
        ::connectrpc::StreamType::Unary,
    )
    .with_idempotency_level(::connectrpc::IdempotencyLevel::Unknown);
/// The keys of private mode (design 06 §4 and §6, ADR-0255): an account's identity, its account master key (AMK)
/// wrapped once per unlock path, and its recovery kit. Clients make and wrap every key; the server keeps the wraps and
/// reads only their headers, so nothing it holds opens anything. It accepts no upload to a private library from an
/// account with fewer than two unlock paths or an unverified recovery kit (`keys.recovery_incomplete`).
///
/// # Implementing handlers
///
/// Implement methods with plain `async fn`; the returned future satisfies
/// the `Send` bound automatically.
///
/// **Unary and server-streaming requests** arrive as
/// [`ServiceRequest<'_, Req>`](::connectrpc::ServiceRequest): a zero-copy
/// view of the request plus its body, valid for the duration of the call.
/// Fields are read directly (`request.name` is a `&str` into the decoded
/// buffer) and the borrow may be held across `.await` points. Anything
/// that must outlive the call — `tokio::spawn`, channels, server state,
/// or data captured by a returned response stream — takes owned data:
/// call `request.to_owned_message()` (or copy the specific fields)
/// first.
///
/// **Client-streaming and bidi requests** arrive as
/// [`InboundStream<Req>`](::connectrpc::InboundStream) — a
/// `ServiceStream` of [`StreamMessage`](::connectrpc::StreamMessage)s.
/// Each item owns its decoded buffer and is `Send + 'static`, so items
/// can be buffered or moved into spawned tasks; read fields zero-copy
/// through the generated accessor methods (`item.name()`) or `.view()`,
/// convert with `.to_owned_message()`, or yield an item back unchanged —
/// `StreamMessage<M>` implements `Encodable<M>`.
///
/// Request types resolved through `extern_path` (e.g. well-known types
/// from another crate) use the same wrappers; the crate that owns the
/// type must be generated with buffa ≥ 0.9.0 and views enabled so the
/// backing `HasMessageView` impl exists.
///
/// The `impl Encodable<Out>` return bound accepts the owned `Out`, the
/// generated `OutView<'_>` / `OwnedOutView`,
/// [`MaybeBorrowed`](::connectrpc::MaybeBorrowed), or
/// [`PreEncoded`](::connectrpc::PreEncoded) for handlers that encode a
/// non-`'static` view internally and pass the bytes across the handler
/// boundary. View bodies are not emitted for output types mapped via
/// `extern_path` (the impl would be an orphan); return owned for
/// WKT/extern outputs.
///
/// Server-streaming and bidi-streaming methods return
/// `ServiceStream<impl Encodable<Out> + Send + use<Self>>`. The
/// `use<Self>` precise-capturing clause excludes `&self`'s lifetime and
/// the request's lifetime (unary methods use `use<'a, Self>` and may
/// borrow from `&self`), so stream items must be `'static` and cannot
/// borrow from the request. To stream view-encoded data, encode each
/// item inside the stream body and yield
/// [`PreEncoded`](::connectrpc::PreEncoded) — see its `# Streaming
/// example` doc.
#[allow(clippy::type_complexity)]
pub trait KeyService: Send + Sync + 'static {
    /// The caller's keys, and whether its account has a password. Only a password sign-in returns the password path's
    /// wrap (FinishLoginResponse.password_path), so that a session alone cannot test guesses at the password offline.
    ///
    /// `'a` lets the response body borrow from `&self` (e.g. server-resident state).
    ///
    /// `request` is borrowed from the request body and is valid for the
    /// duration of the call; message fields are read directly on it
    /// (zero-copy). The response cannot borrow from `request` — use
    /// `.to_owned_message()` (or copy the specific fields) for anything
    /// returned, stored, or moved into `tokio::spawn`.
    fn get_keys<'a>(
        &'a self,
        ctx: ::connectrpc::RequestContext,
        request: ::connectrpc::ServiceRequest<
            '_,
            crate::proto::photolib::api::v1::GetKeysRequest,
        >,
    ) -> impl ::std::future::Future<
        Output = ::connectrpc::ServiceResult<
            impl ::connectrpc::Encodable<
                crate::proto::photolib::api::v1::GetKeysResponse,
            > + Send + use<'a, Self>,
        >,
    > + Send;
    /// Creates the caller's keys, once (`keys.exist`). A password path needs the account's password (`keys.no_password`).
    ///
    /// `'a` lets the response body borrow from `&self` (e.g. server-resident state).
    ///
    /// `request` is borrowed from the request body and is valid for the
    /// duration of the call; message fields are read directly on it
    /// (zero-copy). The response cannot borrow from `request` — use
    /// `.to_owned_message()` (or copy the specific fields) for anything
    /// returned, stored, or moved into `tokio::spawn`.
    fn create_keys<'a>(
        &'a self,
        ctx: ::connectrpc::RequestContext,
        request: ::connectrpc::ServiceRequest<
            '_,
            crate::proto::photolib::api::v1::CreateKeysRequest,
        >,
    ) -> impl ::std::future::Future<
        Output = ::connectrpc::ServiceResult<
            impl ::connectrpc::Encodable<
                crate::proto::photolib::api::v1::CreateKeysResponse,
            > + Send + use<'a, Self>,
        >,
    > + Send;
    /// Adds an unlock path or replaces the one of its kind (`keys.none` before CreateKeys). A new recovery kit is
    /// unverified until VerifyRecoveryKit.
    ///
    /// `'a` lets the response body borrow from `&self` (e.g. server-resident state).
    ///
    /// `request` is borrowed from the request body and is valid for the
    /// duration of the call; message fields are read directly on it
    /// (zero-copy). The response cannot borrow from `request` — use
    /// `.to_owned_message()` (or copy the specific fields) for anything
    /// returned, stored, or moved into `tokio::spawn`.
    fn put_unlock_path<'a>(
        &'a self,
        ctx: ::connectrpc::RequestContext,
        request: ::connectrpc::ServiceRequest<
            '_,
            crate::proto::photolib::api::v1::PutUnlockPathRequest,
        >,
    ) -> impl ::std::future::Future<
        Output = ::connectrpc::ServiceResult<
            impl ::connectrpc::Encodable<
                crate::proto::photolib::api::v1::PutUnlockPathResponse,
            > + Send + use<'a, Self>,
        >,
    > + Send;
    /// Records that the person proved they hold the recovery kit: at setup by typing words of it again, in a drill by
    /// unlocking with it. `kit_id` names the kit (`keys.kit_mismatch` when it is not the current one).
    ///
    /// `'a` lets the response body borrow from `&self` (e.g. server-resident state).
    ///
    /// `request` is borrowed from the request body and is valid for the
    /// duration of the call; message fields are read directly on it
    /// (zero-copy). The response cannot borrow from `request` — use
    /// `.to_owned_message()` (or copy the specific fields) for anything
    /// returned, stored, or moved into `tokio::spawn`.
    fn verify_recovery_kit<'a>(
        &'a self,
        ctx: ::connectrpc::RequestContext,
        request: ::connectrpc::ServiceRequest<
            '_,
            crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
        >,
    ) -> impl ::std::future::Future<
        Output = ::connectrpc::ServiceResult<
            impl ::connectrpc::Encodable<
                crate::proto::photolib::api::v1::VerifyRecoveryKitResponse,
            > + Send + use<'a, Self>,
        >,
    > + Send;
}
/// Extension trait for registering a service implementation with a Router.
///
/// This trait is automatically implemented for all types that implement the service trait.
/// Prefer [`Router::add_service`](::connectrpc::Router::add_service) for
/// top-down registration; `register` remains available for compatibility
/// and cases where the service-first call shape is more convenient.
///
/// # Example
///
/// ```rust,ignore
/// use std::sync::Arc;
///
/// let service = Arc::new(MyServiceImpl);
/// let router = service.register(Router::new());
/// ```
pub trait KeyServiceExt: KeyService {
    /// Register this service implementation with a Router.
    ///
    /// Takes ownership of the `Arc<Self>` and returns a new Router with
    /// this service's methods registered.
    fn register(
        self: ::std::sync::Arc<Self>,
        router: ::connectrpc::Router,
    ) -> ::connectrpc::Router;
}
impl<S: KeyService> KeyServiceExt for S {
    fn register(
        self: ::std::sync::Arc<Self>,
        router: ::connectrpc::Router,
    ) -> ::connectrpc::Router {
        router
            .route_view(
                KEY_SERVICE_SERVICE_NAME,
                "GetKeys",
                {
                    let svc = ::std::sync::Arc::clone(&self);
                    ::connectrpc::view_handler_fn(move |
                        ctx,
                        req: ::buffa::view::OwnedView<
                            crate::proto::photolib::api::v1::__buffa::view::GetKeysRequestView<
                                'static,
                            >,
                        >,
                        format|
                    {
                        let svc = ::std::sync::Arc::clone(&svc);
                        async move {
                            let sreq = ::connectrpc::ServiceRequest::<
                                crate::proto::photolib::api::v1::GetKeysRequest,
                            >::from_parts(req.reborrow(), req.bytes());
                            svc.get_keys(ctx, sreq)
                                .await?
                                .encode::<
                                    crate::proto::photolib::api::v1::GetKeysResponse,
                                >(format)
                        }
                    })
                },
            )
            .with_spec(KEY_SERVICE_GET_KEYS_SPEC)
            .route_view(
                KEY_SERVICE_SERVICE_NAME,
                "CreateKeys",
                {
                    let svc = ::std::sync::Arc::clone(&self);
                    ::connectrpc::view_handler_fn(move |
                        ctx,
                        req: ::buffa::view::OwnedView<
                            crate::proto::photolib::api::v1::__buffa::view::CreateKeysRequestView<
                                'static,
                            >,
                        >,
                        format|
                    {
                        let svc = ::std::sync::Arc::clone(&svc);
                        async move {
                            let sreq = ::connectrpc::ServiceRequest::<
                                crate::proto::photolib::api::v1::CreateKeysRequest,
                            >::from_parts(req.reborrow(), req.bytes());
                            svc.create_keys(ctx, sreq)
                                .await?
                                .encode::<
                                    crate::proto::photolib::api::v1::CreateKeysResponse,
                                >(format)
                        }
                    })
                },
            )
            .with_spec(KEY_SERVICE_CREATE_KEYS_SPEC)
            .route_view(
                KEY_SERVICE_SERVICE_NAME,
                "PutUnlockPath",
                {
                    let svc = ::std::sync::Arc::clone(&self);
                    ::connectrpc::view_handler_fn(move |
                        ctx,
                        req: ::buffa::view::OwnedView<
                            crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathRequestView<
                                'static,
                            >,
                        >,
                        format|
                    {
                        let svc = ::std::sync::Arc::clone(&svc);
                        async move {
                            let sreq = ::connectrpc::ServiceRequest::<
                                crate::proto::photolib::api::v1::PutUnlockPathRequest,
                            >::from_parts(req.reborrow(), req.bytes());
                            svc.put_unlock_path(ctx, sreq)
                                .await?
                                .encode::<
                                    crate::proto::photolib::api::v1::PutUnlockPathResponse,
                                >(format)
                        }
                    })
                },
            )
            .with_spec(KEY_SERVICE_PUT_UNLOCK_PATH_SPEC)
            .route_view(
                KEY_SERVICE_SERVICE_NAME,
                "VerifyRecoveryKit",
                {
                    let svc = ::std::sync::Arc::clone(&self);
                    ::connectrpc::view_handler_fn(move |
                        ctx,
                        req: ::buffa::view::OwnedView<
                            crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitRequestView<
                                'static,
                            >,
                        >,
                        format|
                    {
                        let svc = ::std::sync::Arc::clone(&svc);
                        async move {
                            let sreq = ::connectrpc::ServiceRequest::<
                                crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
                            >::from_parts(req.reborrow(), req.bytes());
                            svc.verify_recovery_kit(ctx, sreq)
                                .await?
                                .encode::<
                                    crate::proto::photolib::api::v1::VerifyRecoveryKitResponse,
                                >(format)
                        }
                    })
                },
            )
            .with_spec(KEY_SERVICE_VERIFY_RECOVERY_KIT_SPEC)
    }
}
/// Type-inference marker used by [`Router::add_service`](::connectrpc::Router::add_service).
#[doc(hidden)]
pub struct KeyServiceRegisterMarker;
impl<S: KeyService> ::connectrpc::ServiceRegister<KeyServiceRegisterMarker>
for ::std::sync::Arc<S> {
    fn register_service(self, router: ::connectrpc::Router) -> ::connectrpc::Router {
        <S as KeyServiceExt>::register(self, router)
    }
}
/// Monomorphic dispatcher for `KeyService`.
///
/// Unlike `.register(Router)` which type-erases each method into an `Arc<dyn ErasedHandler>` stored in a `HashMap`, this struct dispatches via a compile-time `match` on method name: no vtable, no hash lookup.
///
/// # Example
///
/// ```rust,ignore
/// use connectrpc::ConnectRpcService;
///
/// let server = KeyServiceServer::new(MyImpl);
/// let service = ConnectRpcService::new(server);
/// // hand `service` to axum/hyper as a fallback_service
/// ```
pub struct KeyServiceServer<T> {
    inner: ::std::sync::Arc<T>,
}
impl<T: KeyService> KeyServiceServer<T> {
    /// Wrap a service implementation in a monomorphic dispatcher.
    pub fn new(service: T) -> Self {
        Self {
            inner: ::std::sync::Arc::new(service),
        }
    }
    /// Wrap an already-`Arc`'d service implementation.
    pub fn from_arc(inner: ::std::sync::Arc<T>) -> Self {
        Self { inner }
    }
}
impl<T> Clone for KeyServiceServer<T> {
    fn clone(&self) -> Self {
        Self {
            inner: ::std::sync::Arc::clone(&self.inner),
        }
    }
}
impl<T: KeyService> ::connectrpc::Dispatcher for KeyServiceServer<T> {
    #[inline]
    fn lookup(
        &self,
        path: &str,
    ) -> Option<::connectrpc::dispatcher::codegen::MethodDescriptor> {
        let method = path.strip_prefix("photolib.api.v1.KeyService/")?;
        match method {
            "GetKeys" => {
                Some(
                    ::connectrpc::dispatcher::codegen::MethodDescriptor::unary(false)
                        .with_spec(KEY_SERVICE_GET_KEYS_SPEC),
                )
            }
            "CreateKeys" => {
                Some(
                    ::connectrpc::dispatcher::codegen::MethodDescriptor::unary(false)
                        .with_spec(KEY_SERVICE_CREATE_KEYS_SPEC),
                )
            }
            "PutUnlockPath" => {
                Some(
                    ::connectrpc::dispatcher::codegen::MethodDescriptor::unary(false)
                        .with_spec(KEY_SERVICE_PUT_UNLOCK_PATH_SPEC),
                )
            }
            "VerifyRecoveryKit" => {
                Some(
                    ::connectrpc::dispatcher::codegen::MethodDescriptor::unary(false)
                        .with_spec(KEY_SERVICE_VERIFY_RECOVERY_KIT_SPEC),
                )
            }
            _ => None,
        }
    }
    fn call_unary(
        &self,
        path: &str,
        ctx: ::connectrpc::RequestContext,
        request: ::connectrpc::Payload,
        format: ::connectrpc::CodecFormat,
    ) -> ::connectrpc::dispatcher::codegen::UnaryResult {
        let Some(method) = path.strip_prefix("photolib.api.v1.KeyService/") else {
            return ::connectrpc::dispatcher::codegen::unimplemented_unary(path);
        };
        let _ = (&ctx, &request, &format);
        match method {
            "GetKeys" => {
                let svc = ::std::sync::Arc::clone(&self.inner);
                Box::pin(async move {
                    let body = ::connectrpc::dispatcher::codegen::request_proto_bytes::<
                        crate::proto::photolib::api::v1::GetKeysRequest,
                    >(request.encoded()?, format)?;
                    let req: crate::proto::photolib::api::v1::__buffa::view::GetKeysRequestView<
                        '_,
                    > = ::connectrpc::dispatcher::codegen::decode_borrowed_request_view(
                        &body,
                        ctx.decode_options(),
                    )?;
                    let req = ::connectrpc::ServiceRequest::<
                        crate::proto::photolib::api::v1::GetKeysRequest,
                    >::from_parts(&req, &body);
                    svc.get_keys(ctx, req)
                        .await?
                        .encode::<
                            crate::proto::photolib::api::v1::GetKeysResponse,
                        >(format)
                })
            }
            "CreateKeys" => {
                let svc = ::std::sync::Arc::clone(&self.inner);
                Box::pin(async move {
                    let body = ::connectrpc::dispatcher::codegen::request_proto_bytes::<
                        crate::proto::photolib::api::v1::CreateKeysRequest,
                    >(request.encoded()?, format)?;
                    let req: crate::proto::photolib::api::v1::__buffa::view::CreateKeysRequestView<
                        '_,
                    > = ::connectrpc::dispatcher::codegen::decode_borrowed_request_view(
                        &body,
                        ctx.decode_options(),
                    )?;
                    let req = ::connectrpc::ServiceRequest::<
                        crate::proto::photolib::api::v1::CreateKeysRequest,
                    >::from_parts(&req, &body);
                    svc.create_keys(ctx, req)
                        .await?
                        .encode::<
                            crate::proto::photolib::api::v1::CreateKeysResponse,
                        >(format)
                })
            }
            "PutUnlockPath" => {
                let svc = ::std::sync::Arc::clone(&self.inner);
                Box::pin(async move {
                    let body = ::connectrpc::dispatcher::codegen::request_proto_bytes::<
                        crate::proto::photolib::api::v1::PutUnlockPathRequest,
                    >(request.encoded()?, format)?;
                    let req: crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathRequestView<
                        '_,
                    > = ::connectrpc::dispatcher::codegen::decode_borrowed_request_view(
                        &body,
                        ctx.decode_options(),
                    )?;
                    let req = ::connectrpc::ServiceRequest::<
                        crate::proto::photolib::api::v1::PutUnlockPathRequest,
                    >::from_parts(&req, &body);
                    svc.put_unlock_path(ctx, req)
                        .await?
                        .encode::<
                            crate::proto::photolib::api::v1::PutUnlockPathResponse,
                        >(format)
                })
            }
            "VerifyRecoveryKit" => {
                let svc = ::std::sync::Arc::clone(&self.inner);
                Box::pin(async move {
                    let body = ::connectrpc::dispatcher::codegen::request_proto_bytes::<
                        crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
                    >(request.encoded()?, format)?;
                    let req: crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitRequestView<
                        '_,
                    > = ::connectrpc::dispatcher::codegen::decode_borrowed_request_view(
                        &body,
                        ctx.decode_options(),
                    )?;
                    let req = ::connectrpc::ServiceRequest::<
                        crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
                    >::from_parts(&req, &body);
                    svc.verify_recovery_kit(ctx, req)
                        .await?
                        .encode::<
                            crate::proto::photolib::api::v1::VerifyRecoveryKitResponse,
                        >(format)
                })
            }
            _ => ::connectrpc::dispatcher::codegen::unimplemented_unary(path),
        }
    }
    fn call_server_streaming(
        &self,
        path: &str,
        ctx: ::connectrpc::RequestContext,
        request: ::buffa::bytes::Bytes,
        format: ::connectrpc::CodecFormat,
    ) -> ::connectrpc::dispatcher::codegen::StreamingResult {
        let Some(method) = path.strip_prefix("photolib.api.v1.KeyService/") else {
            return ::connectrpc::dispatcher::codegen::unimplemented_streaming(path);
        };
        let _ = (&ctx, &request, &format);
        match method {
            _ => ::connectrpc::dispatcher::codegen::unimplemented_streaming(path),
        }
    }
    fn call_client_streaming(
        &self,
        path: &str,
        ctx: ::connectrpc::RequestContext,
        requests: ::connectrpc::dispatcher::codegen::RequestStream,
        format: ::connectrpc::CodecFormat,
    ) -> ::connectrpc::dispatcher::codegen::UnaryResult {
        let Some(method) = path.strip_prefix("photolib.api.v1.KeyService/") else {
            return ::connectrpc::dispatcher::codegen::unimplemented_unary(path);
        };
        let _ = (&ctx, &requests, &format);
        match method {
            _ => ::connectrpc::dispatcher::codegen::unimplemented_unary(path),
        }
    }
    fn call_bidi_streaming(
        &self,
        path: &str,
        ctx: ::connectrpc::RequestContext,
        requests: ::connectrpc::dispatcher::codegen::RequestStream,
        format: ::connectrpc::CodecFormat,
    ) -> ::connectrpc::dispatcher::codegen::StreamingResult {
        let Some(method) = path.strip_prefix("photolib.api.v1.KeyService/") else {
            return ::connectrpc::dispatcher::codegen::unimplemented_streaming(path);
        };
        let _ = (&ctx, &requests, &format);
        match method {
            _ => ::connectrpc::dispatcher::codegen::unimplemented_streaming(path),
        }
    }
}
/// Client for this service.
///
/// Generic over `T: ClientTransport`. For **gRPC** (HTTP/2), use
/// `Http2Connection` — it has honest `poll_ready` and composes with
/// `tower::balance` for multi-connection load balancing. For **Connect
/// over HTTP/1.1** (or unknown protocol), use `HttpClient`.
///
/// # Example (gRPC / HTTP/2)
///
/// ```rust,ignore
/// use connectrpc::client::{Http2Connection, ClientConfig};
/// use connectrpc::Protocol;
///
/// let uri: http::Uri = "http://localhost:8080".parse()?;
/// let conn = Http2Connection::connect_plaintext(uri.clone()).await?.shared(1024);
/// let config = ClientConfig::new(uri).with_protocol(Protocol::Grpc);
///
/// let client = KeyServiceClient::new(conn, config);
/// let response = client.get_keys(request).await?;
/// ```
///
/// # Example (Connect / HTTP/1.1 or ALPN)
///
/// ```rust,ignore
/// use connectrpc::client::{HttpClient, ClientConfig};
///
/// let http = HttpClient::plaintext();  // cleartext http:// only
/// let config = ClientConfig::new("http://localhost:8080".parse()?);
///
/// let client = KeyServiceClient::new(http, config);
/// let response = client.get_keys(request).await?;
/// ```
///
/// # Working with the response
///
/// Unary calls return [`UnaryResponse<OwnedView<FooView>>`](::connectrpc::client::UnaryResponse).
/// [`view()`](::connectrpc::client::UnaryResponse::view) borrows the response
/// message, so field access is zero-copy:
///
/// ```rust,ignore
/// let resp = client.get_keys(request).await?;
/// let name: &str = resp.view().name;  // borrow into the response buffer
/// ```
///
/// If you need the owned struct (e.g. to store or pass by value), use
/// [`into_owned()`](::connectrpc::client::UnaryResponse::into_owned):
///
/// ```rust,ignore
/// let owned = client.get_keys(request).await?.into_owned();
/// ```
///
/// [`into_view()`](::connectrpc::client::UnaryResponse::into_view) keeps the
/// zero-copy decoded body (an `OwnedView`) without copying; field access on it
/// goes through `.reborrow()`. Streaming responses yield one
/// [`StreamMessage`](::connectrpc::StreamMessage) per received message from
/// `.message().await` — read fields zero-copy through the generated accessor
/// methods (`msg.name()`) or `.view()`, or convert with `.to_owned_message()`.
#[cfg(feature = "client")]
#[derive(Clone)]
pub struct KeyServiceClient<T> {
    transport: T,
    config: ::connectrpc::client::ClientConfig,
}
#[cfg(feature = "client")]
impl<T> KeyServiceClient<T>
where
    T: ::connectrpc::client::ClientTransport,
    <T::ResponseBody as ::connectrpc::http_body::Body>::Error: ::std::fmt::Display,
{
    /// Create a new client with the given transport and configuration.
    pub fn new(transport: T, config: ::connectrpc::client::ClientConfig) -> Self {
        Self { transport, config }
    }
    /// Get the client configuration.
    pub fn config(&self) -> &::connectrpc::client::ClientConfig {
        &self.config
    }
    /// Get a mutable reference to the client configuration.
    pub fn config_mut(&mut self) -> &mut ::connectrpc::client::ClientConfig {
        &mut self.config
    }
    /// Call the GetKeys RPC. Sends a request to /photolib.api.v1.KeyService/GetKeys.
    pub async fn get_keys(
        &self,
        request: crate::proto::photolib::api::v1::GetKeysRequest,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::GetKeysResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        self.get_keys_with_options(request, ::connectrpc::client::CallOptions::default())
            .await
    }
    /// Call the GetKeys RPC with explicit per-call options. Options override [`ClientConfig`](::connectrpc::client::ClientConfig) defaults.
    pub async fn get_keys_with_options(
        &self,
        request: crate::proto::photolib::api::v1::GetKeysRequest,
        options: ::connectrpc::client::CallOptions,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::GetKeysResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        ::connectrpc::client::call_unary(
                &self.transport,
                &self.config,
                KEY_SERVICE_GET_KEYS_SPEC.with_origin(::connectrpc::SpecOrigin::Client),
                request,
                options,
            )
            .await
    }
    /// Call the CreateKeys RPC. Sends a request to /photolib.api.v1.KeyService/CreateKeys.
    pub async fn create_keys(
        &self,
        request: crate::proto::photolib::api::v1::CreateKeysRequest,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::CreateKeysResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        self.create_keys_with_options(
                request,
                ::connectrpc::client::CallOptions::default(),
            )
            .await
    }
    /// Call the CreateKeys RPC with explicit per-call options. Options override [`ClientConfig`](::connectrpc::client::ClientConfig) defaults.
    pub async fn create_keys_with_options(
        &self,
        request: crate::proto::photolib::api::v1::CreateKeysRequest,
        options: ::connectrpc::client::CallOptions,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::CreateKeysResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        ::connectrpc::client::call_unary(
                &self.transport,
                &self.config,
                KEY_SERVICE_CREATE_KEYS_SPEC
                    .with_origin(::connectrpc::SpecOrigin::Client),
                request,
                options,
            )
            .await
    }
    /// Call the PutUnlockPath RPC. Sends a request to /photolib.api.v1.KeyService/PutUnlockPath.
    pub async fn put_unlock_path(
        &self,
        request: crate::proto::photolib::api::v1::PutUnlockPathRequest,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        self.put_unlock_path_with_options(
                request,
                ::connectrpc::client::CallOptions::default(),
            )
            .await
    }
    /// Call the PutUnlockPath RPC with explicit per-call options. Options override [`ClientConfig`](::connectrpc::client::ClientConfig) defaults.
    pub async fn put_unlock_path_with_options(
        &self,
        request: crate::proto::photolib::api::v1::PutUnlockPathRequest,
        options: ::connectrpc::client::CallOptions,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::PutUnlockPathResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        ::connectrpc::client::call_unary(
                &self.transport,
                &self.config,
                KEY_SERVICE_PUT_UNLOCK_PATH_SPEC
                    .with_origin(::connectrpc::SpecOrigin::Client),
                request,
                options,
            )
            .await
    }
    /// Call the VerifyRecoveryKit RPC. Sends a request to /photolib.api.v1.KeyService/VerifyRecoveryKit.
    pub async fn verify_recovery_kit(
        &self,
        request: crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        self.verify_recovery_kit_with_options(
                request,
                ::connectrpc::client::CallOptions::default(),
            )
            .await
    }
    /// Call the VerifyRecoveryKit RPC with explicit per-call options. Options override [`ClientConfig`](::connectrpc::client::ClientConfig) defaults.
    pub async fn verify_recovery_kit_with_options(
        &self,
        request: crate::proto::photolib::api::v1::VerifyRecoveryKitRequest,
        options: ::connectrpc::client::CallOptions,
    ) -> Result<
        ::connectrpc::client::UnaryResponse<
            ::buffa::view::OwnedView<
                crate::proto::photolib::api::v1::__buffa::view::VerifyRecoveryKitResponseView<
                    'static,
                >,
            >,
        >,
        ::connectrpc::ConnectError,
    > {
        ::connectrpc::client::call_unary(
                &self.transport,
                &self.config,
                KEY_SERVICE_VERIFY_RECOVERY_KIT_SPEC
                    .with_origin(::connectrpc::SpecOrigin::Client),
                request,
                options,
            )
            .await
    }
}
