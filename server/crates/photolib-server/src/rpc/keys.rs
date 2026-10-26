//! The API key service (M2-06, ADR-0055): an account's own keys, which only the account signed in manages.

use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_proto::{
    connect::photolib::api::v1::ApiKeyService,
    proto::photolib::api::v1::{
        CreateApiKeyRequest, CreateApiKeyResponse, ListApiKeysRequest, ListApiKeysResponse, RevokeApiKeyRequest,
        RevokeApiKeyResponse,
    },
};

use super::{ApiError, Users, authz::actor, users::internal};
use crate::keys::KeyError;

impl From<KeyError> for ConnectError {
    fn from(error: KeyError) -> Self {
        match error {
            KeyError::Invalid(field) => {
                ApiError::new(ErrorCode::InvalidArgument, "field.invalid").param("field", field)
            }
            KeyError::NotFound => ApiError::new(ErrorCode::NotFound, "api_key.not_found"),
            KeyError::RateLimited => ApiError::new(ErrorCode::ResourceExhausted, "api_key.rate_limited"),
            KeyError::Db(error) => return internal(error),
        }
        .into()
    }
}

#[allow(refining_impl_trait)]
impl ApiKeyService for Users {
    async fn list_api_keys(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, ListApiKeysRequest>,
    ) -> ServiceResult<ListApiKeysResponse> {
        Ok(ListApiKeysResponse {
            api_keys: self.keys.list(actor(&ctx)?).await.map_err(internal)?,
            ..Default::default()
        }
        .into())
    }

    async fn create_api_key(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CreateApiKeyRequest>,
    ) -> ServiceResult<CreateApiKeyResponse> {
        let key = request.to_owned_message().api_key.into_option();
        let (key, secret) = self.keys.create(actor(&ctx)?, key.unwrap_or_default()).await?;
        Ok(CreateApiKeyResponse {
            api_key: key.into(),
            secret,
            ..Default::default()
        }
        .into())
    }

    async fn revoke_api_key(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, RevokeApiKeyRequest>,
    ) -> ServiceResult<RevokeApiKeyResponse> {
        let id = request.to_owned_message().api_key_id;
        Ok(RevokeApiKeyResponse {
            api_key: self.keys.revoke(actor(&ctx)?, &id).await?.into(),
            ..Default::default()
        }
        .into())
    }
}

#[cfg(test)]
pub(super) mod tests {
    use axum::http::StatusCode;
    use buffa_types::google::protobuf::Timestamp;
    use photolib_proto::proto::photolib::api::v1::{ApiKey, ApiKeyScope, User, UserRole};
    use serde_json::{Value, json};
    use sqlx::PgPool;

    use crate::{
        keys::ApiKeys,
        rpc::users::tests::{call, denied, person, with_admin},
    };

    /// The caller that `call` signs with `secret`: it sends a caller's id as its bearer token.
    fn bearer(secret: &str) -> User {
        User {
            user_id: secret.into(),
            ..Default::default()
        }
    }

    /// A caller signed with a new key of `owner`'s, which never expires.
    pub(in crate::rpc) async fn key(pool: &PgPool, owner: &User, scopes: &[ApiKeyScope]) -> User {
        let key = ApiKey {
            name: "key".into(),
            scopes: scopes.iter().map(|&scope| scope.into()).collect(),
            expires_at: Some(Timestamp {
                seconds: 1 << 35,
                ..Default::default()
            })
            .into(),
            ..Default::default()
        };
        let owner = owner.user_id.parse().unwrap();
        let (_, secret) = ApiKeys::new(pool.clone()).create(owner, key).await.unwrap();
        bearer(&secret)
    }

    /// A request to create `key`, with the defaults of a valid key for what it leaves out.
    fn create(key: Value) -> Value {
        let mut valid = json!({ "name": "cli", "scopes": ["API_KEY_SCOPE_VIEW"], "expiresAt": "2999-01-01T00:00:00Z" });
        valid.as_object_mut().unwrap().extend(key.as_object().unwrap().clone());
        json!({ "apiKey": valid })
    }

    #[tokio::test]
    async fn a_key_signs_as_its_account_within_its_scopes_until_it_is_revoked() {
        let (api, root) = with_admin().await;
        let as_root = |procedure: &'static str, body: Value| call(&api.app, procedure, Some(&root), body);
        let scopes = [
            "API_KEY_SCOPE_MANAGE_USERS",
            "API_KEY_SCOPE_VIEW",
            "API_KEY_SCOPE_MANAGE_USERS",
        ];
        let request = create(json!({ "name": " backup script ", "scopes": scopes }));
        let (status, created) = as_root("ApiKeyService/CreateApiKey", request).await;
        assert_eq!(status, StatusCode::OK, "{created}");
        let secret = created["secret"].as_str().unwrap();
        let hex = secret.strip_prefix("plk_").unwrap();
        assert!(hex.len() == 64 && hex.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')));
        let mut key = created["apiKey"].clone();
        let id = key["apiKeyId"].as_str().unwrap().to_string();
        assert!(key["createdAt"].as_str().unwrap().ends_with('Z'));
        for field in ["apiKeyId", "createdAt"] {
            key.as_object_mut().unwrap().remove(field);
        }
        assert_eq!(
            key,
            json!({
                "name": "backup script", "scopes": ["API_KEY_SCOPE_VIEW", "API_KEY_SCOPE_MANAGE_USERS"],
                "expiresAt": "2999-01-01T00:00:00Z", "requestsPerMinute": 600,
            })
        );
        let stored: bool = sqlx::query_scalar(
            "SELECT token_hash = sha256(convert_to($1, 'UTF8')) AND strpos(to_jsonb(k)::text, $2) = 0 FROM api_keys k",
        )
        .bind(secret)
        .bind(hex)
        .fetch_one(&api.pool)
        .await
        .unwrap();
        assert!(stored, "the server keeps only the secret's hash");

        let by_key = bearer(secret);
        let list_users = || call(&api.app, "UserService/ListUsers", Some(&by_key), json!({}));
        assert_eq!(list_users().await.0, StatusCode::OK);
        let (_, listed) = as_root("ApiKeyService/ListApiKeys", json!({})).await;
        let listed = &listed["apiKeys"];
        assert_eq!(listed.as_array().unwrap().len(), 1, "{listed}");
        assert!(listed[0]["lastUsedAt"].is_string(), "{listed}");
        assert!(listed[0].get("secret").is_none() && listed[0].get("revokedAt").is_none());

        let actor = root.user_id.parse().unwrap();
        let bob = person("bob", UserRole::USER_ROLE_USER);
        let bob = Some(api.accounts.create(actor, bob).await.unwrap());
        let revoke = json!({ "apiKeyId": id });
        assert_eq!(
            call(&api.app, "ApiKeyService/RevokeApiKey", bob.as_ref(), revoke.clone()).await,
            (StatusCode::NOT_FOUND, denied("not_found", "api_key.not_found")),
            "nobody else revokes it"
        );
        let (_, theirs) = call(&api.app, "ApiKeyService/ListApiKeys", bob.as_ref(), json!({})).await;
        assert_eq!(theirs, json!({}), "nor sees it");
        assert_eq!(list_users().await.0, StatusCode::OK, "it still signs");
        let (_, revoked) = as_root("ApiKeyService/RevokeApiKey", revoke.clone()).await;
        let revoked_at = &revoked["apiKey"]["revokedAt"];
        assert!(revoked_at.is_string(), "{revoked}");
        assert_eq!(
            list_users().await,
            (StatusCode::UNAUTHORIZED, denied("unauthenticated", "session.required"))
        );
        let (_, again) = as_root("ApiKeyService/RevokeApiKey", revoke).await;
        assert_eq!(
            &again["apiKey"]["revokedAt"], revoked_at,
            "a second revocation changes nothing"
        );

        let audited: Vec<(String, String, String)> = sqlx::query_as(
            "SELECT action, actor_user_id::text, target ->> 'api_key_id' FROM audit_events
             WHERE action LIKE 'api_key.%' ORDER BY id",
        )
        .fetch_all(&api.pool)
        .await
        .unwrap();
        let by_root = |action: &str| (action.to_string(), root.user_id.clone(), id.clone());
        assert_eq!(audited, [by_root("api_key.create"), by_root("api_key.revoke")]);
    }

    #[tokio::test]
    async fn a_key_of_an_account_that_cannot_sign_in_signs_nothing() {
        let (api, root) = with_admin().await;
        let ann = person("ann", UserRole::USER_ROLE_ADMIN);
        let ann = api.accounts.create(root.user_id.parse().unwrap(), ann).await.unwrap();
        let by_key = key(&api.pool, &ann, &[ApiKeyScope::API_KEY_SCOPE_MANAGE_USERS]).await;
        let list = || call(&api.app, "UserService/ListUsers", Some(&by_key), json!({}));
        assert_eq!(list().await.0, StatusCode::OK);
        sqlx::query("UPDATE users SET status = 'disabled' WHERE handle = 'ann'")
            .execute(&api.pool)
            .await
            .unwrap();
        assert_eq!(
            list().await,
            (StatusCode::UNAUTHORIZED, denied("unauthenticated", "session.required"))
        );
    }

    #[tokio::test]
    async fn a_key_is_refused_beyond_its_rate() {
        let (api, root) = with_admin().await;
        let request = create(json!({ "requestsPerMinute": 2 }));
        let (_, created) = call(&api.app, "ApiKeyService/CreateApiKey", Some(&root), request).await;
        let by_key = bearer(created["secret"].as_str().unwrap());
        let info = || call(&api.app, "ServerInfoService/GetServerInfo", Some(&by_key), json!({}));
        assert_eq!([info().await.0, info().await.0], [StatusCode::OK; 2]);
        assert_eq!(
            info().await,
            (
                StatusCode::TOO_MANY_REQUESTS,
                denied("resource_exhausted", "api_key.rate_limited")
            )
        );
    }

    #[tokio::test]
    async fn a_key_that_cannot_be_made_is_refused_with_its_field() {
        let (api, root) = with_admin().await;
        let invalid = |field: &str| {
            let mut error = denied("invalid_argument", "field.invalid");
            error["field"] = field.into();
            (StatusCode::BAD_REQUEST, error)
        };
        for (body, field) in [
            (json!({}), "name"),
            (create(json!({ "name": "  " })), "name"),
            (create(json!({ "name": "a\u{7}" })), "name"),
            (create(json!({ "name": "x".repeat(101) })), "name"),
            (create(json!({ "scopes": [] })), "scopes"),
            (create(json!({ "scopes": ["API_KEY_SCOPE_UNSPECIFIED"] })), "scopes"),
            (create(json!({ "expiresAt": null })), "expires_at"),
            (create(json!({ "expiresAt": "2020-01-01T00:00:00Z" })), "expires_at"),
            (create(json!({ "requestsPerMinute": 60001 })), "requests_per_minute"),
        ] {
            let answer = call(&api.app, "ApiKeyService/CreateApiKey", Some(&root), body.clone());
            assert_eq!(answer.await, invalid(field), "{body}");
        }
        let revoke = json!({ "apiKeyId": "x" });
        let answer = call(&api.app, "ApiKeyService/RevokeApiKey", Some(&root), revoke);
        assert_eq!(answer.await, invalid("api_key_id"));
        let request = create(json!({ "requestsPerMinute": 60000 }));
        let (_, at_most) = call(&api.app, "ApiKeyService/CreateApiKey", Some(&root), request).await;
        assert_eq!(at_most["apiKey"]["requestsPerMinute"], 60000, "{at_most}");
    }
}
