//! The key service (M6-02, ADR-0255): the caller's own private-mode keys, which only the account signed in manages.

use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_proto::{
    connect::photolib::api::v1::KeyService,
    proto::photolib::api::v1::{
        CreateKeysRequest, CreateKeysResponse, GetKeysRequest, GetKeysResponse, PutUnlockPathRequest,
        PutUnlockPathResponse, VerifyRecoveryKitRequest, VerifyRecoveryKitResponse,
    },
};

use super::{ApiError, Users, authz::actor, users::internal};
use crate::account_keys::{self, KeyError};

impl From<KeyError> for ConnectError {
    fn from(error: KeyError) -> Self {
        match error {
            KeyError::Invalid(field) => {
                ApiError::new(ErrorCode::InvalidArgument, "field.invalid").param("field", field)
            }
            KeyError::Exist => ApiError::new(ErrorCode::AlreadyExists, "keys.exist"),
            KeyError::None => ApiError::new(ErrorCode::FailedPrecondition, "keys.none"),
            KeyError::NoPassword => ApiError::new(ErrorCode::FailedPrecondition, "keys.no_password"),
            KeyError::KitMismatch => ApiError::new(ErrorCode::FailedPrecondition, "keys.kit_mismatch"),
            KeyError::Db(error) => return internal(error),
        }
        .into()
    }
}

#[allow(refining_impl_trait)]
impl KeyService for Users {
    async fn get_keys(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, GetKeysRequest>,
    ) -> ServiceResult<GetKeysResponse> {
        let user = actor(&ctx)?;
        let mut conn = self.accounts.pool().acquire().await.map_err(internal)?;
        let password = sqlx::query_scalar("SELECT EXISTS (SELECT FROM password_records WHERE user_id = $1)")
            .bind(user)
            .fetch_one(&mut *conn)
            .await
            .map_err(internal)?;
        Ok(GetKeysResponse {
            keys: account_keys::get(&mut conn, user).await.map_err(internal)?.into(),
            password,
            user_id: user.to_string(),
            ..Default::default()
        }
        .into())
    }

    async fn create_keys(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CreateKeysRequest>,
    ) -> ServiceResult<CreateKeysResponse> {
        let keys = account_keys::create(self.accounts.pool(), actor(&ctx)?, request.to_owned_message()).await?;
        Ok(CreateKeysResponse {
            keys: keys.into(),
            ..Default::default()
        }
        .into())
    }

    async fn put_unlock_path(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, PutUnlockPathRequest>,
    ) -> ServiceResult<PutUnlockPathResponse> {
        let path = request.to_owned_message().path.into_option().unwrap_or_default();
        let keys = account_keys::put(self.accounts.pool(), actor(&ctx)?, &path).await?;
        Ok(PutUnlockPathResponse {
            keys: keys.into(),
            ..Default::default()
        }
        .into())
    }

    async fn verify_recovery_kit(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, VerifyRecoveryKitRequest>,
    ) -> ServiceResult<VerifyRecoveryKitResponse> {
        let kit = request.to_owned_message().kit_id;
        let keys = account_keys::verify(self.accounts.pool(), actor(&ctx)?, &kit).await?;
        Ok(VerifyRecoveryKitResponse {
            keys: keys.into(),
            ..Default::default()
        }
        .into())
    }
}

#[cfg(test)]
pub(in crate::rpc) mod tests {
    use axum::http::StatusCode;
    use base64::{Engine, engine::general_purpose::STANDARD};
    use photolib_kernel::{
        Keyring,
        proto::kernel::v1::{
            CallResponse, ImportKeyRequest, KeyPair, KeyResponse, Method, PublicKeyRequest, PublicKeyResponse,
            SignEntryRequest, SignEntryResponse, WrapContext, WrapKeyRequest, WrapKeyResponse, call_response,
        },
    };
    use photolib_proto::proto::photolib::api::v1::{User, UserRole};
    use prost::Message;
    use serde_json::{Value, json};
    use uuid::Uuid;

    use crate::rpc::users::tests::{Api, call, denied, person, with_admin};

    /// Argon2id at 256 MiB and three passes, within the account policy.
    pub(in crate::rpc) const PARAMS: [u8; 26] = [
        1, 0, 4, 0, 0, 0, 0, 0, 3, 1, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    ];

    fn random(length: usize) -> Vec<u8> {
        let mut bytes = vec![0; length];
        getrandom::fill(&mut bytes).unwrap();
        bytes
    }

    fn kernel<R: Message + Default>(keyring: &mut Keyring, method: Method, request: &impl Message) -> R {
        let answer = keyring.call(method as u32, &request.encode_to_vec());
        match CallResponse::decode(answer.as_slice()).unwrap().result {
            Some(call_response::Result::Response(bytes)) => R::decode(bytes.as_slice()).unwrap(),
            other => panic!("{method:?}: {other:?}"),
        }
    }

    /// What a client makes when `user` turns private mode on: an AMK, the identity it wraps and the AMK wrapped under
    /// a password and a recovery kit, whose key ids are `kits`.
    pub(in crate::rpc) struct Enrolment {
        pub identity: Vec<u8>,
        pub signing_key: Vec<u8>,
        pub decryption_key: Vec<u8>,
        pub password: Vec<u8>,
        pub recovery: Vec<u8>,
        pub kit: Vec<u8>,
        keyring: Keyring,
        amk: u32,
        user: Uuid,
    }

    impl Enrolment {
        pub(in crate::rpc) fn new(user: Uuid) -> Self {
            let mut keyring = Keyring::default();
            let key = |keyring: &mut Keyring| {
                let request = ImportKeyRequest { secret: random(32) };
                kernel::<KeyResponse>(keyring, Method::ImportKey, &request)
            };
            let (amk, sign, decrypt) = (key(&mut keyring), key(&mut keyring), key(&mut keyring));
            let mut public = |key: u32, key_pair: KeyPair| {
                let request = PublicKeyRequest {
                    key,
                    key_pair: key_pair.into(),
                };
                kernel::<PublicKeyResponse>(&mut keyring, Method::PublicKey, &request).public_key
            };
            let body = [public(sign.key, KeyPair::Ed25519), public(decrypt.key, KeyPair::XWing)].concat();
            let genesis = SignEntryRequest {
                key: sign.key,
                log_type: 1,
                body_type: 1,
                log_id: user.as_bytes().to_vec(),
                body,
                ..Default::default()
            };
            let identity = kernel::<SignEntryResponse>(&mut keyring, Method::SignEntry, &genesis).entry;
            let mut enrolment = Self {
                identity,
                signing_key: vec![],
                decryption_key: vec![],
                password: vec![],
                recovery: vec![],
                kit: vec![],
                keyring,
                amk: amk.key,
                user,
            };
            enrolment.signing_key = enrolment.wrap(amk.key, sign.key, 8);
            enrolment.decryption_key = enrolment.wrap(amk.key, decrypt.key, 9);
            enrolment.password = enrolment.path();
            enrolment.recovery = enrolment.path();
            enrolment.kit = enrolment.recovery[8..24].to_vec();
            enrolment
        }

        fn wrap(&mut self, wrapping_key: u32, key: u32, wrapped_type: u32) -> Vec<u8> {
            let request = WrapKeyRequest {
                wrapping_key,
                key,
                wrapped_type,
                context: Some(WrapContext {
                    user_id: self.user.as_bytes().to_vec(),
                    ..Default::default()
                }),
                nonce: random(24),
            };
            kernel::<WrapKeyResponse>(&mut self.keyring, Method::WrapKey, &request).wrap
        }

        /// The AMK wrapped under a new key, as for a new password or recovery kit.
        pub(in crate::rpc) fn path(&mut self) -> Vec<u8> {
            let request = ImportKeyRequest { secret: random(32) };
            let kek = kernel::<KeyResponse>(&mut self.keyring, Method::ImportKey, &request).key;
            self.wrap(kek, self.amk, 1)
        }

        pub(in crate::rpc) fn request(&self) -> Value {
            json!({
                "identity": STANDARD.encode(&self.identity),
                "signingKey": STANDARD.encode(&self.signing_key),
                "decryptionKey": STANDARD.encode(&self.decryption_key),
                "paths": [password(&self.password), recovery(&self.recovery)],
            })
        }
    }

    pub(in crate::rpc) fn password(wrap: &[u8]) -> Value {
        json!({ "kind": "UNLOCK_KIND_PASSWORD", "wrap": STANDARD.encode(wrap), "params": STANDARD.encode(PARAMS) })
    }

    fn recovery(wrap: &[u8]) -> Value {
        json!({ "kind": "UNLOCK_KIND_RECOVERY", "wrap": STANDARD.encode(wrap) })
    }

    async fn with_password(pool: &sqlx::PgPool, user: &User) {
        sqlx::query(
            "INSERT INTO password_records (user_id, credential, record, ksf_params) VALUES ($1::uuid, '', '', '')",
        )
        .bind(&user.user_id)
        .execute(pool)
        .await
        .unwrap();
    }

    /// The paths of `keys` as (kind, whether its wrap is there).
    fn paths(keys: &Value) -> Vec<(&str, bool)> {
        let paths = keys["paths"].as_array().unwrap().iter();
        paths
            .map(|p| (p["kind"].as_str().unwrap(), p.get("wrap").is_some()))
            .collect()
    }

    /// Ann, a user with a password and the keys of `Enrolment`, as CreateKeys answered.
    async fn ann_with_keys(api: &Api, root: &User) -> (User, Enrolment, Value) {
        let ann = api
            .accounts
            .create(root.user_id.parse().unwrap(), person("ann", UserRole::USER_ROLE_USER));
        let ann = ann.await.unwrap();
        let keys = Enrolment::new(ann.user_id.parse().unwrap());
        let (status, got) = call(&api.app, "KeyService/GetKeys", Some(&ann), json!({})).await;
        assert_eq!(
            (status, got),
            (StatusCode::OK, json!({ "userId": ann.user_id })),
            "no keys and no password yet"
        );
        assert_eq!(
            call(&api.app, "KeyService/CreateKeys", Some(&ann), keys.request()).await,
            (
                StatusCode::BAD_REQUEST,
                denied("failed_precondition", "keys.no_password")
            ),
            "a password path needs the password"
        );
        with_password(&api.pool, &ann).await;
        let (status, created) = call(&api.app, "KeyService/CreateKeys", Some(&ann), keys.request()).await;
        assert_eq!(status, StatusCode::OK, "{created}");
        (ann, keys, created)
    }

    #[tokio::test]
    async fn an_account_keeps_its_keys_once_and_a_session_alone_gets_no_password_wrap() {
        let (api, root) = with_admin().await;
        let (ann, keys, created) = ann_with_keys(&api, &root).await;
        let (_, got) = call(&api.app, "KeyService/GetKeys", Some(&ann), json!({})).await;
        assert_eq!(
            got,
            json!({ "keys": created["keys"], "password": true, "userId": ann.user_id })
        );
        let got = &got["keys"];
        assert_eq!(
            paths(got),
            [("UNLOCK_KIND_PASSWORD", false), ("UNLOCK_KIND_RECOVERY", true)]
        );
        assert_eq!(
            STANDARD.decode(got["identity"].as_str().unwrap()).unwrap(),
            keys.identity
        );
        assert!(
            got.get("ready").is_none() && got.get("recoveryVerifiedAt").is_none(),
            "{got}"
        );
        assert_eq!(
            call(&api.app, "KeyService/CreateKeys", Some(&ann), keys.request()).await,
            (StatusCode::CONFLICT, denied("already_exists", "keys.exist"))
        );
    }

    #[tokio::test]
    async fn only_the_current_recovery_kit_verifies_and_a_drill_falls_due_six_months_later() {
        let (api, root) = with_admin().await;
        let (ann, mut keys, _) = ann_with_keys(&api, &root).await;
        let verify = |kit: &[u8]| {
            let body = json!({ "kitId": STANDARD.encode(kit) });
            call(&api.app, "KeyService/VerifyRecoveryKit", Some(&ann), body)
        };
        let mismatch = (
            StatusCode::BAD_REQUEST,
            denied("failed_precondition", "keys.kit_mismatch"),
        );
        assert_eq!(verify(&[0; 16]).await, mismatch);
        let (_, verified) = verify(&keys.kit).await;
        let verified = &verified["keys"];
        assert_eq!(verified["ready"], true, "{verified}");
        let due: String = sqlx::query_scalar(
            "SELECT to_char((recovery_verified_at + interval '6 months') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS')
             FROM account_keys",
        )
        .fetch_one(&api.pool)
        .await
        .unwrap();
        assert!(verified["drillDueAt"].as_str().unwrap().starts_with(&due), "{verified}");
        let kit = keys.path();
        let body = json!({ "path": recovery(&kit) });
        let (_, put) = call(&api.app, "KeyService/PutUnlockPath", Some(&ann), body).await;
        assert!(put["keys"].get("ready").is_none(), "a new kit is unverified: {put}");
        assert_eq!(verify(&keys.kit).await, mismatch, "the old kit verifies nothing");
        assert_eq!(verify(&kit[8..24]).await.1["keys"]["ready"], true);
        let audited: Vec<String> =
            sqlx::query_scalar("SELECT action FROM audit_events WHERE action LIKE 'keys.%' ORDER BY id")
                .fetch_all(&api.pool)
                .await
                .unwrap();
        let expected = [
            "keys.create",
            "keys.recovery_verified",
            "keys.unlock_path",
            "keys.recovery_verified",
        ];
        assert_eq!(audited, expected);
    }

    #[tokio::test]
    async fn keys_are_refused_unless_their_headers_say_they_are_the_callers_under_one_master_key() {
        let (api, root) = with_admin().await;
        with_password(&api.pool, &root).await;
        let mut keys = Enrolment::new(root.user_id.parse().unwrap());
        let other = Enrolment::new(Uuid::now_v7());
        let encoded = |bytes: &[u8]| json!(STANDARD.encode(bytes));
        let (identity, signing, foreign) = (
            encoded(&other.identity),
            encoded(&other.signing_key),
            password(&other.password),
        );
        let (truncated, weak, params) = (encoded(&keys.password[..143]), encoded(&[1; 26]), encoded(&PARAMS));
        let cases: [(&str, &str, &str, Value); 10] = [
            ("another account's identity", "/identity", "identity", identity),
            (
                "a decryption key as the signing key",
                "/signingKey",
                "signing_key",
                encoded(&keys.decryption_key),
            ),
            (
                "a signing key as the decryption key",
                "/decryptionKey",
                "decryption_key",
                encoded(&keys.signing_key),
            ),
            ("keys under two AMKs", "/signingKey", "decryption_key", signing),
            ("a path of another AMK", "/paths/0", "path.wrap", foreign),
            ("two recovery kits", "/paths/0", "paths", recovery(&keys.password)),
            (
                "a recovery kit with parameters",
                "/paths/1/params",
                "path.params",
                params,
            ),
            ("weak parameters", "/paths/0/params", "path.params", weak),
            (
                "no kind",
                "/paths/1/kind",
                "path.kind",
                json!("UNLOCK_KIND_UNSPECIFIED"),
            ),
            ("a truncated wrap", "/paths/0/wrap", "path.wrap", truncated),
        ];
        for (what, pointer, field, value) in cases {
            let mut request = keys.request();
            let (parent, key) = pointer.rsplit_once('/').unwrap();
            let parent = request.pointer_mut(parent).unwrap();
            match key.parse::<usize>() {
                Ok(index) => parent[index] = value,
                Err(_) => parent[key] = value,
            }
            let mut expected = denied("invalid_argument", "field.invalid");
            expected["field"] = field.into();
            let got = call(&api.app, "KeyService/CreateKeys", Some(&root), request).await;
            assert_eq!(got, (StatusCode::BAD_REQUEST, expected), "{what}");
        }
        let kept: i64 = sqlx::query_scalar("SELECT count(*) FROM account_keys")
            .fetch_one(&api.pool)
            .await
            .unwrap();
        assert_eq!(kept, 0, "nothing refused is kept");
        let path = json!({ "path": password(&keys.path()) });
        assert_eq!(
            call(&api.app, "KeyService/PutUnlockPath", Some(&root), path).await,
            (StatusCode::BAD_REQUEST, denied("failed_precondition", "keys.none"))
        );
    }
}
