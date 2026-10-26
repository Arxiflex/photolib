//! The setup and user services: the first administrator through the one-time setup token, then the accounts for
//! signed-in administrators (M2-01, ADR-0035).

use std::sync::Arc;

use axum::http::{HeaderMap, header::AUTHORIZATION};
use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_authz::{Principal, Role};
use photolib_proto::connect::photolib::api::v1::{SetupService, UserService};
use photolib_proto::proto::photolib::api::v1::{
    CreateFirstAdminRequest, CreateFirstAdminResponse, CreatePasswordSetupRequest, CreatePasswordSetupResponse,
    CreateUserRequest, CreateUserResponse, DeleteUserRequest, DeleteUserResponse, ListUsersRequest, ListUsersResponse,
    ResetSecondFactorsRequest, ResetSecondFactorsResponse, UpdateUserRequest, UpdateUserResponse, User, UserRole,
    UserStatus,
};
use subtle::ConstantTimeEq;
use uuid::Uuid;

use super::{ApiError, Sessions, authz::actor};
use crate::{
    accounts::{AccountError, Accounts},
    db::DbError,
    keys::{self, ApiKeys},
    secret::{Secret, random_hex},
};

/// The one-time token that creates the first administrator: 256 random bits, printed once in the log.
struct SetupToken(Secret<String>);

impl SetupToken {
    fn generate() -> SetupToken {
        SetupToken(Secret::new(random_hex()))
    }

    fn matches(&self, given: &str) -> bool {
        self.0.expose().as_bytes().ct_eq(given.as_bytes()).into()
    }
}

pub struct Users {
    pub(super) accounts: Accounts,
    pub(super) keys: ApiKeys,
    sessions: Arc<dyn Sessions>,
    setup: Option<SetupToken>,
    /// New webhooks may be created: the configuration's `webhooks`, unless `outbound: none` (ADR-0263).
    pub(super) webhooks: bool,
}

impl Users {
    /// The services of an API process. Without an administrator, it logs a new setup token.
    pub async fn start(accounts: Accounts, keys: ApiKeys, sessions: Arc<dyn Sessions>) -> Result<Users, DbError> {
        let setup = if accounts.has_admin().await? {
            None
        } else {
            let token = SetupToken::generate();
            tracing::warn!(
                setup_token = token.0.expose().as_str(),
                "no administrator exists: create the first one with this one-time setup token"
            );
            Some(token)
        };
        Ok(Users {
            accounts,
            keys,
            sessions,
            setup,
            webhooks: false,
        })
    }

    /// The services with webhooks `webhooks` (on or off).
    #[must_use]
    pub fn with_webhooks(self, webhooks: bool) -> Self {
        Self { webhooks, ..self }
    }

    /// Who signs a request: an active account, one of its API keys, or nobody; none for a session that must enrol a
    /// second factor first (ADR-0088).
    pub(crate) async fn principal(&self, headers: &HeaderMap) -> Result<Option<Principal>, ConnectError> {
        let bearer = headers.get(AUTHORIZATION).and_then(|value| value.to_str().ok());
        if let Some(secret) = bearer.and_then(|value| value.strip_prefix("Bearer "))
            && secret.starts_with(keys::PREFIX)
        {
            return Ok(Some(self.keys.principal(secret).await?));
        }
        match self.sessions.caller(headers).await.map_err(internal)? {
            Some(caller) if caller.must_enrol => Ok(None),
            Some(caller) => self.account(caller.user).await.map(Some),
            None => Ok(Some(Principal::Anonymous)),
        }
    }

    /// The account `id` while it may act: active, with its role.
    pub(crate) async fn account(&self, id: Uuid) -> Result<Principal, ConnectError> {
        let user = self.accounts.get(id).await.map_err(internal)?;
        Ok(match user {
            Some(user) if user.status == UserStatus::USER_STATUS_ACTIVE => {
                // An unknown role gets the fewest rights.
                let role = match user.role.as_known() {
                    Some(UserRole::USER_ROLE_ADMIN) => Role::Admin,
                    Some(UserRole::USER_ROLE_USER) => Role::User,
                    _ => Role::Viewer,
                };
                Principal::User(id, role)
            }
            _ => Principal::Anonymous,
        })
    }
}

pub(super) fn internal(error: impl std::fmt::Display) -> ConnectError {
    tracing::error!(%error, "an account request failed");
    ApiError::new(ErrorCode::Internal, "server.internal").into()
}

impl From<AccountError> for ConnectError {
    fn from(error: AccountError) -> Self {
        match error {
            AccountError::Invalid(field) => {
                ApiError::new(ErrorCode::InvalidArgument, "field.invalid").param("field", field)
            }
            AccountError::Taken("email") => ApiError::new(ErrorCode::AlreadyExists, "user.email_taken"),
            AccountError::Taken(_) => ApiError::new(ErrorCode::AlreadyExists, "user.handle_taken"),
            AccountError::NotFound => ApiError::new(ErrorCode::NotFound, "user.not_found"),
            AccountError::LastAdmin => ApiError::new(ErrorCode::FailedPrecondition, "user.last_admin"),
            AccountError::SetupDone => ApiError::new(ErrorCode::FailedPrecondition, "setup.done"),
            AccountError::Db(error) => return internal(error),
        }
        .into()
    }
}

#[allow(refining_impl_trait)]
impl SetupService for Users {
    async fn create_first_admin(
        &self,
        _ctx: RequestContext,
        request: ServiceRequest<'_, CreateFirstAdminRequest>,
    ) -> ServiceResult<CreateFirstAdminResponse> {
        let request = request.to_owned_message();
        let Some(token) = &self.setup else {
            return Err(AccountError::SetupDone.into());
        };
        if !token.matches(&request.setup_token) {
            return Err(ApiError::new(ErrorCode::PermissionDenied, "setup.token_invalid").into());
        }
        let (user, setup) = self
            .accounts
            .create_first_admin(request.user.into_option().unwrap_or_default())
            .await?;
        Ok(CreateFirstAdminResponse {
            user: user.into(),
            password_setup: setup.into(),
            ..Default::default()
        }
        .into())
    }
}

#[allow(refining_impl_trait)]
impl UserService for Users {
    async fn list_users(
        &self,
        _ctx: RequestContext,
        _request: ServiceRequest<'_, ListUsersRequest>,
    ) -> ServiceResult<ListUsersResponse> {
        Ok(ListUsersResponse {
            users: self.accounts.list().await.map_err(internal)?,
            ..Default::default()
        }
        .into())
    }

    async fn create_user(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CreateUserRequest>,
    ) -> ServiceResult<CreateUserResponse> {
        let actor = actor(&ctx)?;
        let user = request.to_owned_message().user.into_option().unwrap_or_default();
        Ok(CreateUserResponse {
            user: self.accounts.create(actor, user).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn update_user(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, UpdateUserRequest>,
    ) -> ServiceResult<UpdateUserResponse> {
        let actor = actor(&ctx)?;
        let request = request.to_owned_message();
        let user = request.user.into_option().unwrap_or_default();
        let mask = request.update_mask.into_option().unwrap_or_default().paths;
        if mask.iter().any(|field| field == "status") && user.status == UserStatus::USER_STATUS_DELETED {
            return Err(AccountError::Invalid("status").into());
        }
        Ok(UpdateUserResponse {
            user: self.accounts.update(actor, user, &mask).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn delete_user(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, DeleteUserRequest>,
    ) -> ServiceResult<DeleteUserResponse> {
        let actor = actor(&ctx)?;
        let deleted = User {
            user_id: request.to_owned_message().user_id,
            status: UserStatus::USER_STATUS_DELETED.into(),
            ..Default::default()
        };
        Ok(DeleteUserResponse {
            user: self.accounts.update(actor, deleted, &["status".into()]).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn create_password_setup(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CreatePasswordSetupRequest>,
    ) -> ServiceResult<CreatePasswordSetupResponse> {
        let actor = actor(&ctx)?;
        let user = request.to_owned_message().user_id;
        Ok(CreatePasswordSetupResponse {
            password_setup: self.accounts.password_setup(actor, &user).await?.into(),
            ..Default::default()
        }
        .into())
    }

    async fn reset_second_factors(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, ResetSecondFactorsRequest>,
    ) -> ServiceResult<ResetSecondFactorsResponse> {
        let user = request.to_owned_message().user_id;
        let reset = self.accounts.reset_second_factors(actor(&ctx)?, &user);
        reset.await?;
        Ok(ResetSecondFactorsResponse::default().into())
    }
}

#[cfg(test)]
pub(super) mod tests {
    use axum::http::StatusCode;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use serde_json::{Value, json};
    use uuid::Uuid;

    use super::*;
    use crate::{
        config::{Log, LogFormat},
        doctor::{Doctor, Seen},
        logging::Tail,
        role::Role,
        rpc::Admin,
        testing::{BearerSessions, Capture, config},
    };

    pub(in crate::rpc) struct Api {
        pub app: axum::Router,
        pub accounts: Accounts,
        pub pool: sqlx::PgPool,
        /// The data directory, and the log tail that the admin console reads.
        pub data: Arc<tempfile::TempDir>,
        pub tail: Tail,
    }

    /// The API on `pool` with these user services, `auth`, and the admin console's on the data directory.
    pub(in crate::rpc) fn app(
        users: Users,
        auth: Option<Arc<super::super::Auth>>,
        pool: &sqlx::PgPool,
        data: &tempfile::TempDir,
        tail: &Tail,
    ) -> axum::Router {
        let doctor = Doctor {
            config: config(&[Role::Api], data.path()),
            pool: Some(pool.clone()),
            seen: Some(Seen::default()),
            tail: Some(tail.clone()),
            ml: None,
        };
        let admin = Admin::new(pool.clone(), Arc::new(doctor));
        super::super::api(Uuid::now_v7().to_string(), Some(Arc::new(users)), auth, Some(admin))
    }

    /// The API of a new instance; also returns the setup token it logged.
    async fn api() -> (Api, String) {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let accounts = Accounts::new(db.pool.clone());
        let capture = Capture::default();
        let log = Log {
            format: LogFormat::Json,
            filter: "info".into(),
        };
        let users = {
            let _guards = capture.set_default(&log);
            // On a loaded machine sqlx warns of a slow statement among the records, as here.
            tracing::warn!(target: "sqlx::query", elapsed_secs = 1.2, "slow statement");
            let keys = ApiKeys::new(db.pool.clone());
            Users::start(accounts.clone(), keys, Arc::new(BearerSessions))
                .await
                .unwrap()
        };
        let line = (capture.text().lines())
            .map(|line| serde_json::from_str::<Value>(line).unwrap())
            .find(|line| line["fields"]["setup_token"].is_string())
            .unwrap();
        assert_eq!(line["level"], "WARN");
        let token = line["fields"]["setup_token"].as_str().unwrap().to_string();
        assert_eq!(&token, users.setup.as_ref().unwrap().0.expose());
        let (data, tail) = (Arc::new(tempfile::tempdir().unwrap()), Tail::default());
        let app = app(users, None, &db.pool, &data, &tail);
        (
            Api {
                app,
                accounts,
                pool: db.pool,
                data,
                tail,
            },
            token,
        )
    }

    /// A unary call in JSON as `caller`: the status, and the body or else the error's code and reason.
    pub(in crate::rpc) async fn call(
        app: &axum::Router,
        procedure: &str,
        caller: Option<&User>,
        body: Value,
    ) -> (StatusCode, Value) {
        let bearer = caller.map(|caller| caller.user_id.as_str());
        crate::testing::call(app, procedure, bearer, body).await
    }

    /// A server-streaming call in JSON as `caller`, as `crate::testing::stream` answers it.
    pub(in crate::rpc) async fn stream(
        app: &axum::Router,
        procedure: &str,
        caller: Option<&User>,
        body: Value,
    ) -> (StatusCode, Value) {
        let bearer = caller.map(|caller| caller.user_id.as_str());
        crate::testing::stream(app, procedure, bearer, body).await
    }

    pub(in crate::rpc) fn denied(code: &str, reason: &str) -> Value {
        json!({ "code": code, "reason": reason })
    }

    #[tokio::test]
    async fn the_first_admin_is_created_only_with_the_setup_token_and_only_once() {
        let (api, token) = api().await;
        let root = json!({ "handle": "root", "displayName": "Root", "email": "root@example.org", "locale": "en" });
        for wrong in [
            String::new(),
            "0".repeat(64),
            token.to_uppercase(),
            format!("{token}0"),
            token[1..].into(),
        ] {
            let (status, error) = call(
                &api.app,
                "SetupService/CreateFirstAdmin",
                None,
                json!({ "setupToken": wrong, "user": root }),
            )
            .await;
            assert_eq!(
                (status, error),
                (
                    StatusCode::FORBIDDEN,
                    denied("permission_denied", "setup.token_invalid")
                ),
                "{wrong}"
            );
        }
        assert_eq!(
            api.accounts.list().await.unwrap(),
            [],
            "no account exists before the setup"
        );
        let request = json!({ "setupToken": token, "user": root });
        let (status, body) = call(&api.app, "SetupService/CreateFirstAdmin", None, request).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        let password = body["passwordSetup"]["token"].as_str().unwrap();
        assert!(password.len() == 64 && password != token, "{body}");
        assert!(body["passwordSetup"]["expiresAt"].is_string(), "{body}");
        assert_eq!(
            stable(&body["user"]),
            json!({
                "handle": "root", "displayName": "Root", "email": "root@example.org", "locale": "en",
                "role": "USER_ROLE_ADMIN", "status": "USER_STATUS_ACTIVE",
            })
        );
        let again = json!({ "setupToken": token, "user": { "handle": "eve", "displayName": "Eve" } });
        assert_eq!(
            call(&api.app, "SetupService/CreateFirstAdmin", None, again).await,
            (StatusCode::BAD_REQUEST, denied("failed_precondition", "setup.done"))
        );
        assert_eq!(api.accounts.list().await.unwrap().len(), 1);
    }

    /// `user` without the values the server makes up.
    fn stable(user: &Value) -> Value {
        let mut user = user.clone();
        for field in ["userId", "createdAt"] {
            user.as_object_mut().unwrap().remove(field);
        }
        user
    }

    /// The API of a process that starts on the same database.
    async fn restart(api: Api, sessions: Arc<dyn Sessions>) -> (Api, bool) {
        let keys = ApiKeys::new(api.pool.clone());
        let users = Users::start(api.accounts.clone(), keys, sessions).await.unwrap();
        let setup = users.setup.is_some();
        let app = app(users, None, &api.pool, &api.data, &api.tail);
        (Api { app, ..api }, setup)
    }

    #[tokio::test]
    async fn a_process_started_with_an_administrator_has_no_setup_token() {
        let (api, root) = with_admin().await;
        let key = opaque_ke::ServerSetup::new(&mut rand_core::OsRng);
        let sessions = Arc::new(super::super::Auth::new(api.pool.clone(), key));
        let (fresh, setup) = restart(api, sessions).await;
        assert!(!setup);
        let request = json!({ "setupToken": "", "user": { "handle": "eve", "displayName": "Eve" } });
        assert_eq!(
            call(&fresh.app, "SetupService/CreateFirstAdmin", None, request).await,
            (StatusCode::BAD_REQUEST, denied("failed_precondition", "setup.done"))
        );
        assert_eq!(
            call(&fresh.app, "UserService/ListUsers", Some(&root), json!({})).await,
            (StatusCode::UNAUTHORIZED, denied("unauthenticated", "session.required")),
            "an account id is no session token"
        );
    }

    pub(in crate::rpc) fn person(handle: &str, role: UserRole) -> User {
        User {
            handle: handle.into(),
            display_name: handle.into(),
            role: role.into(),
            ..Default::default()
        }
    }

    pub(in crate::rpc) async fn with_admin() -> (Api, User) {
        let (api, _) = api().await;
        let root = User {
            email: "root@example.org".into(),
            ..person("root", UserRole::USER_ROLE_ADMIN)
        };
        let root = api.accounts.create_first_admin(root).await.unwrap().0;
        (api, root)
    }

    #[tokio::test]
    async fn an_admin_manages_accounts_and_every_change_is_audited_as_theirs() {
        let (api, root) = with_admin().await;
        let admin = Some(&root);
        let create =
            json!({ "user": { "handle": "kid", "displayName": "Kid", "role": "USER_ROLE_VIEWER", "quotaBytes": "0" } });
        let (status, created) = call(&api.app, "UserService/CreateUser", admin, create).await;
        assert_eq!(status, StatusCode::OK, "{created}");
        let kid = created["user"]["userId"].as_str().unwrap().to_string();
        assert!(created["user"]["createdAt"].as_str().unwrap().ends_with('Z'));
        assert_eq!(
            stable(&created["user"]),
            json!({ "handle": "kid", "displayName": "Kid", "role": "USER_ROLE_VIEWER", "status": "USER_STATUS_ACTIVE", "quotaBytes": "0" })
        );
        let rename = json!({
            "user": { "userId": kid, "displayName": "Kiddo", "status": "USER_STATUS_DISABLED", "locale": "fr" },
            "updateMask": "displayName,status"
        });
        let (_, renamed) = call(&api.app, "UserService/UpdateUser", admin, rename).await;
        assert_eq!(
            (
                &renamed["user"]["displayName"],
                &renamed["user"]["status"],
                renamed["user"].get("locale")
            ),
            (&json!("Kiddo"), &json!("USER_STATUS_DISABLED"), None),
            "{renamed}"
        );
        let (_, deleted) = call(&api.app, "UserService/DeleteUser", admin, json!({ "userId": kid })).await;
        assert_eq!(deleted["user"]["status"], "USER_STATUS_DELETED", "{deleted}");
        assert!(deleted["user"]["purgeAt"].is_string(), "{deleted}");
        let restore = json!({ "user": { "userId": kid, "status": "USER_STATUS_ACTIVE" }, "updateMask": "status" });
        let (_, restored) = call(&api.app, "UserService/UpdateUser", admin, restore).await;
        assert_eq!(
            (&restored["user"]["status"], restored["user"].get("purgeAt")),
            (&json!("USER_STATUS_ACTIVE"), None)
        );
        let (_, listed) = call(&api.app, "UserService/ListUsers", admin, json!({})).await;
        let handles: Vec<&Value> = listed["users"]
            .as_array()
            .unwrap()
            .iter()
            .map(|user| &user["handle"])
            .collect();
        assert_eq!(handles, [&json!("kid"), &json!("root")]);
        let audited: Vec<(String, Option<String>, String)> = sqlx::query_as(
            "SELECT action, actor_user_id::text, target ->> 'user_id' FROM audit_events ORDER BY id OFFSET 2",
        )
        .fetch_all(&api.pool)
        .await
        .unwrap();
        let by_root = |action: &str| (action.to_string(), Some(root.user_id.clone()), kid.clone());
        assert_eq!(
            audited,
            [
                by_root("user.create"),
                by_root("user.update"),
                by_root("user.update"),
                by_root("user.update")
            ]
        );
    }

    #[tokio::test]
    async fn account_errors_reach_the_client_as_codes_and_parameters() {
        let (api, root) = with_admin().await;
        let invalid = |field: &str| {
            let mut error = denied("invalid_argument", "field.invalid");
            error["field"] = field.into();
            (StatusCode::BAD_REQUEST, error)
        };
        let user = |handle: &str, extra: Value| {
            let mut user = json!({ "handle": handle, "displayName": "Ann", "role": "USER_ROLE_USER" });
            user.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
            json!({ "user": user })
        };
        let update = |fields: Value, mask: &str| {
            let mut user = json!({ "userId": root.user_id });
            user.as_object_mut()
                .unwrap()
                .extend(fields.as_object().unwrap().clone());
            json!({ "user": user, "updateMask": mask })
        };
        for (procedure, body, expected) in [
            (
                "CreateUser",
                user("root", json!({})),
                (StatusCode::CONFLICT, denied("already_exists", "user.handle_taken")),
            ),
            (
                "CreateUser",
                user("ann", json!({ "email": "ROOT@example.org" })),
                (StatusCode::CONFLICT, denied("already_exists", "user.email_taken")),
            ),
            ("CreateUser", user("Ann", json!({})), invalid("handle")),
            (
                "CreateUser",
                user("ann", json!({ "role": "USER_ROLE_UNSPECIFIED" })),
                invalid("role"),
            ),
            (
                "UpdateUser",
                update(json!({ "status": "USER_STATUS_DELETED" }), "status"),
                invalid("status"),
            ),
            (
                "UpdateUser",
                update(json!({ "handle": "x" }), "handle"),
                invalid("update_mask"),
            ),
            ("UpdateUser", update(json!({}), ""), invalid("update_mask")),
            (
                "UpdateUser",
                json!({ "user": { "userId": Uuid::now_v7() }, "updateMask": "locale" }),
                (StatusCode::NOT_FOUND, denied("not_found", "user.not_found")),
            ),
            (
                "DeleteUser",
                json!({ "userId": root.user_id }),
                (
                    StatusCode::BAD_REQUEST,
                    denied("failed_precondition", "user.last_admin"),
                ),
            ),
        ] {
            let result = call(&api.app, &format!("UserService/{procedure}"), Some(&root), body.clone()).await;
            assert_eq!(result, expected, "{body}");
        }
        assert_eq!(api.accounts.list().await.unwrap(), [root]);
    }

    #[tokio::test]
    async fn an_admin_makes_a_password_setup_token_that_replaces_the_earlier_one() {
        let (api, root) = with_admin().await;
        let actor = root.user_id.parse().unwrap();
        let kid = api
            .accounts
            .create(actor, person("kid", UserRole::USER_ROLE_USER))
            .await
            .unwrap();
        let request = json!({ "userId": kid.user_id });
        let mut tokens = Vec::new();
        for _ in 0..2 {
            let (status, body) = call(
                &api.app,
                "UserService/CreatePasswordSetup",
                Some(&root),
                request.clone(),
            )
            .await;
            assert_eq!(status, StatusCode::OK, "{body}");
            assert!(body["passwordSetup"]["expiresAt"].is_string(), "{body}");
            tokens.push(body["passwordSetup"]["token"].as_str().unwrap().to_string());
        }
        assert_ne!(tokens[0], tokens[1]);
        let stored: Vec<(Vec<u8>, bool)> = sqlx::query_as(
            "SELECT token_hash, expires_at BETWEEN now() + interval '7 days' - interval '1 minute' AND now() + interval '7 days'
             FROM password_setups WHERE user_id = $1::uuid",
        )
        .bind(&kid.user_id)
        .fetch_all(&api.pool)
        .await
        .unwrap();
        assert_eq!(stored, [(crate::auth::token_hash(&tokens[1]), true)]);
        let audited: Vec<(String, String)> = sqlx::query_as(
            "SELECT actor_user_id::text, target ->> 'user_id' FROM audit_events WHERE action = 'password_setup.create' ORDER BY id OFFSET 1",
        )
        .fetch_all(&api.pool)
        .await
        .unwrap();
        assert_eq!(
            audited,
            [
                (root.user_id.clone(), kid.user_id.clone()),
                (root.user_id.clone(), kid.user_id.clone())
            ]
        );
        for user_id in [Uuid::now_v7().to_string(), "x".into()] {
            assert_eq!(
                call(
                    &api.app,
                    "UserService/CreatePasswordSetup",
                    Some(&root),
                    json!({ "userId": user_id })
                )
                .await,
                (StatusCode::NOT_FOUND, denied("not_found", "user.not_found"))
            );
        }
    }
}
