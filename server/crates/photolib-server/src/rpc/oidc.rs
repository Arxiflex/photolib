//! Signing in with OpenID Connect providers (M2-04, ADR-0087): the identity a provider vouches for signs in to the
//! account it is linked to; the provider's policy may link it by verified email or create the account.

use std::time::Duration;

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use connectrpc::{ConnectError, ErrorCode, RequestContext};
use photolib_proto::proto::photolib::api::v1::{
    CompleteOidcRequest, CompleteOidcResponse, StartOidcRequest, StartOidcResponse, User, UserRole, UserStatus,
};
use url::Url;
use uuid::Uuid;

use super::{
    ApiError, Auth,
    auth::{checked, db, invalid, throttled},
};
use crate::{
    accounts::{AccountError, Accounts},
    auth::audit,
    config::OidcProvider,
    oidc::{self, Completed, Failure, Identity},
};

fn failure(failure: Failure) -> ConnectError {
    match failure {
        Failure::UnknownProvider => ApiError::new(ErrorCode::NotFound, "oidc.provider_unknown"),
        Failure::Unavailable => ApiError::new(ErrorCode::Unavailable, "oidc.unavailable"),
        Failure::Refused => ApiError::new(ErrorCode::PermissionDenied, "oidc.failed"),
        Failure::Claim(claim) => ApiError::new(ErrorCode::PermissionDenied, "oidc.claim_invalid").param("claim", claim),
        Failure::Busy => return throttled(Duration::from_secs(60)),
    }
    .into()
}

fn not_allowed() -> ConnectError {
    ApiError::new(ErrorCode::PermissionDenied, "oidc.not_allowed").into()
}

impl Auth {
    pub(super) async fn oidc_start(
        &self,
        ctx: &RequestContext,
        request: StartOidcRequest,
    ) -> Result<StartOidcResponse, ConnectError> {
        let oidc = self.oidc.as_ref().ok_or_else(|| failure(Failure::UnknownProvider))?;
        let redirect = &request.redirect_uri;
        if redirect.len() > 2048 || !Url::parse(redirect).is_ok_and(|url| url.fragment().is_none()) {
            return Err(invalid("redirect_uri"));
        }
        let challenge = &request.code_challenge;
        if !URL_SAFE_NO_PAD.decode(challenge).is_ok_and(|hash| hash.len() == 32) {
            return Err(invalid("code_challenge"));
        }
        let link = match request.link {
            true => Some(self.signed_in(ctx).await?.user),
            false => None,
        };
        let url = oidc.start(&request.provider, redirect, challenge, link).await;
        Ok(StartOidcResponse {
            authorization_url: url.map_err(failure)?,
            ..Default::default()
        })
    }

    pub(super) async fn oidc_complete(
        &self,
        request: CompleteOidcRequest,
    ) -> Result<CompleteOidcResponse, ConnectError> {
        let device = checked(request.device.into_option())?;
        let oidc = self.oidc.as_ref().ok_or_else(|| failure(Failure::Refused))?;
        let completed = oidc.complete(&request.state, &request.code, &request.code_verifier);
        let Completed {
            provider,
            identity,
            link,
        } = completed.await.map_err(failure)?;
        if let Some(user) = link {
            self.link(&provider.issuer, &identity.subject, user).await?;
            return Ok(CompleteOidcResponse::default());
        }
        let user = self.account(provider, &identity).await?;
        Ok(CompleteOidcResponse {
            session: self.open_session(user, &device, false).await?.into(),
            ..Default::default()
        })
    }

    /// Links the identity to `user`, unless another account has it.
    async fn link(&self, issuer: &str, subject: &str, user: Uuid) -> Result<(), ConnectError> {
        let mut tx = self.pool.begin().await.map_err(db)?;
        let (owner, new): (String, bool) = sqlx::query_as(
            "WITH new AS (
                INSERT INTO oidc_identities (issuer, subject, user_id) VALUES ($1, $2, $3::uuid)
                ON CONFLICT DO NOTHING RETURNING user_id
            )
            SELECT coalesce((TABLE new), (SELECT user_id FROM oidc_identities WHERE issuer = $1 AND subject = $2))::text,
                EXISTS (TABLE new)",
        )
        .bind(issuer)
        .bind(subject)
        .bind(user.to_string())
        .fetch_one(&mut *tx)
        .await
        .map_err(db)?;
        if owner != user.to_string() {
            return Err(ApiError::new(ErrorCode::AlreadyExists, "oidc.identity_taken").into());
        }
        if new {
            audit(&mut tx, user, "oidc.link", user, None).await.map_err(db)?;
        }
        tx.commit().await.map_err(db)
    }

    /// The active account `identity` signs in to under the provider's policy, its role set from the claims.
    async fn account(&self, provider: &OidcProvider, identity: &Identity) -> Result<Uuid, ConnectError> {
        let role = match &provider.roles {
            Some(mapping) => Some(oidc::role(mapping, &identity.roles).ok_or_else(not_allowed)?),
            None => None,
        };
        let issuer = &provider.issuer;
        let linked: Option<(String, i32)> = sqlx::query_as(
            "SELECT user_id::text, 0 FROM oidc_identities WHERE issuer = $1 AND subject = $2
             UNION ALL SELECT id::text, 1 FROM users WHERE $3 AND email = $4 AND status = 'active'
             ORDER BY 2 LIMIT 1",
        )
        .bind(issuer)
        .bind(&identity.subject)
        .bind(provider.link_by_email && identity.email.is_some())
        .bind(identity.email.as_deref().unwrap_or_default())
        .fetch_optional(&self.pool)
        .await
        .map_err(db)?;
        let accounts = Accounts::new(self.pool.clone());
        let id = match linked.and_then(|(id, _)| id.parse().ok()) {
            Some(id) => {
                self.link(issuer, &identity.subject, id).await?;
                id
            }
            None if provider.provision => {
                let user = new_user(identity, role.unwrap_or(UserRole::USER_ROLE_USER));
                accounts.provision(user, issuer, &identity.subject).await?
            }
            None => return Err(not_allowed()),
        };
        let user = accounts.get(id).await.map_err(db)?.ok_or_else(not_allowed)?;
        if user.status != UserStatus::USER_STATUS_ACTIVE {
            return Err(not_allowed());
        }
        if let Some(role) = role.filter(|role| user.role != *role) {
            let change = User {
                user_id: id.to_string(),
                role: role.into(),
                ..Default::default()
            };
            // The last administrator stays one until another exists.
            match accounts.update(id, change, &["role".into()]).await {
                Ok(_) | Err(AccountError::LastAdmin) => {}
                Err(error) => return Err(error.into()),
            }
        }
        Ok(id)
    }
}

/// The account a provider's claims make: a handle from the username or the email, at most 57 characters so that a
/// suffix fits, the name cut to fit, the verified email.
fn new_user(identity: &Identity, role: UserRole) -> User {
    let base = identity.username.as_deref().or(identity.email.as_deref());
    let base = base.unwrap_or_default().split('@').next().unwrap_or_default();
    let handle: String = (base.to_lowercase().chars())
        .filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || "._-".contains(*c))
        .skip_while(|c| "._-".contains(*c))
        .take(57)
        .collect();
    let handle = if handle.is_empty() { "user".into() } else { handle };
    let name = identity.name.as_deref().unwrap_or_default().trim();
    User {
        display_name: if name.is_empty() {
            handle.clone()
        } else {
            name.chars().take(100).collect()
        },
        handle,
        email: identity.email.clone().unwrap_or_default(),
        role: role.into(),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeMap, sync::Arc};

    use axum::http::StatusCode;
    use opaque_ke::ServerSetup;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use photolib_proto::proto::photolib::api::v1::{User, UserRole, UserStatus};
    use rand_core::OsRng;
    use serde_json::{Value, json};
    use sqlx::PgPool;
    use uuid::Uuid;

    use super::*;
    use crate::{
        accounts::Accounts,
        auth::{new_token, token_hash},
        config::{OidcProvider, RoleClaim},
        keys::ApiKeys,
        oidc::{Oidc, challenge},
        rpc::Users,
        testing::{Idp, Signer, call},
    };

    const REDIRECT: &str = "app.photolib:/oidc";
    /// RFC 7636, appendix B.
    const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";

    struct Server {
        app: axum::Router,
        accounts: Accounts,
        pool: PgPool,
        root: Uuid,
    }

    /// An instance with the administrator root and these providers.
    async fn server(providers: &[(&str, OidcProvider)]) -> Server {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let accounts = Accounts::new(db.pool.clone());
        let root = User {
            handle: "root".into(),
            display_name: "Root".into(),
            ..Default::default()
        };
        let (root, _) = accounts.create_first_admin(root).await.unwrap();
        let providers: BTreeMap<String, OidcProvider> = providers
            .iter()
            .map(|(id, provider)| (id.to_string(), provider.clone()))
            .collect();
        let auth = Auth::new(db.pool.clone(), ServerSetup::new(&mut OsRng));
        let auth = Arc::new(auth.with_oidc(Oidc::new(&providers).unwrap()));
        let keys = ApiKeys::new(db.pool.clone());
        let users = Users::start(accounts.clone(), keys, auth.clone()).await.unwrap();
        Server {
            app: super::super::api(Uuid::now_v7().to_string(), Some(Arc::new(users)), Some(auth), None),
            accounts,
            pool: db.pool,
            root: root.user_id.parse().unwrap(),
        }
    }

    impl Server {
        /// A session token of `user`, as a sign-in would give.
        async fn session(&self, user: Uuid) -> String {
            let token = new_token();
            sqlx::query(
                "WITH device AS (
                    INSERT INTO devices (id, user_id, name, platform) VALUES (gen_random_uuid(), $1::uuid, 'laptop', 'linux')
                    RETURNING id
                )
                INSERT INTO sessions (id, device_id, token_hash, expires_at)
                SELECT gen_random_uuid(), id, $2, now() + interval '1 hour' FROM device",
            )
            .bind(user.to_string())
            .bind(token_hash(&token))
            .execute(&self.pool)
            .await
            .unwrap();
            token
        }

        async fn user(&self, handle: &str) -> Option<User> {
            self.accounts
                .list()
                .await
                .unwrap()
                .into_iter()
                .find(|user| user.handle == handle)
        }

        async fn audited(&self, action: &str) -> i64 {
            sqlx::query_scalar("SELECT count(*) FROM audit_events WHERE action = $1")
                .bind(action)
                .fetch_one(&self.pool)
                .await
                .unwrap()
        }
    }

    fn phone() -> Value {
        json!({ "name": "Ann's Pixel", "platform": "android", "appVersion": "0.4.0" })
    }

    /// Signs in at `provider` through `idp` as `claims`, or links them to the account of `bearer`: the answer.
    async fn flow(
        server: &Server,
        idp: &Idp,
        provider: &str,
        claims: Value,
        bearer: Option<&str>,
    ) -> (StatusCode, Value) {
        let start = json!({
            "provider": provider, "redirectUri": REDIRECT, "codeChallenge": challenge(VERIFIER),
            "link": bearer.is_some(),
        });
        let (status, started) = call(&server.app, "AuthService/StartOidc", bearer, start).await;
        if !status.is_success() {
            return (status, started);
        }
        let (state, code) = idp.authorize(started["authorizationUrl"].as_str().unwrap(), claims);
        let body = json!({ "state": state, "code": code, "codeVerifier": VERIFIER, "device": phone() });
        call(&server.app, "AuthService/CompleteOidc", bearer, body).await
    }

    /// Signs in: the session, or the error.
    async fn sign_in(server: &Server, idp: &Idp, provider: &str, claims: Value) -> Result<Value, Value> {
        let (status, answer) = flow(server, idp, provider, claims, None).await;
        status.is_success().then(|| answer["session"].clone()).ok_or(answer)
    }

    fn refused(reason: &str) -> Value {
        json!({ "code": "permission_denied", "reason": reason })
    }

    fn groups(claim: &str, admin: &[&str], user: &[&str], viewer: &[&str]) -> Option<RoleClaim> {
        let values = |values: &[&str]| values.iter().map(|value| value.to_string()).collect();
        Some(RoleClaim {
            claim: claim.into(),
            admin: values(admin),
            user: values(user),
            viewer: values(viewer),
        })
    }

    /// A Keycloak realm whose groups mapper sends full group paths.
    async fn keycloak() -> (Idp, OidcProvider) {
        let idp = Idp::start("/realms/home", Signer::rsa("RS256"), Some("kc-secret"), &[]).await;
        let mut provider = idp.provider();
        provider.roles = groups("groups", &["/photolib-admins"], &["/family"], &[]);
        (idp, provider)
    }

    fn ann() -> Value {
        json!({
            "sub": "5f0c3a5e-7a1b-4c1e-9a55-0e2f1d3c4b5a", "typ": "ID", "sid": "8d1f", "acr": "1",
            "session_state": "8d1f", "at_hash": "x4lQ", "email": "ann@example.org", "email_verified": true,
            "name": "Ann Lee", "given_name": "Ann", "family_name": "Lee", "preferred_username": "ann",
            "groups": ["/family"],
        })
    }

    #[tokio::test]
    async fn each_kind_of_provider_signs_a_new_person_in_to_an_account_it_creates() {
        let (keycloak, keycloak_config) = keycloak().await;
        // Authentik's issuer ends with a slash; its default mappings send groups by name.
        let authentik = Idp::start("/application/o/photolib/", Signer::rsa("RS256"), Some("ak-secret"), &[]).await;
        let mut authentik_config = authentik.provider();
        authentik_config.roles = groups("groups", &["authentik Admins"], &[], &["Guests"]);
        // Authelia's ID tokens carry no profile claims: they come from userinfo. A public client, with PKCE only.
        let profile = ["email", "email_verified", "name", "preferred_username", "groups"];
        let authelia = Idp::start("", Signer::rsa("RS256"), None, &profile).await;
        let mut authelia_config = authelia.provider();
        authelia_config.roles = groups("groups", &[], &[], &["family"]);
        // Google, a cloud provider: no groups and no username, a picture.
        let google = Idp::start("", Signer::rsa("RS256"), Some("g-secret"), &[]).await;
        let server = server(&[
            ("keycloak", keycloak_config),
            ("authentik", authentik_config),
            ("authelia", authelia_config),
            ("google", google.provider()),
        ])
        .await;
        let people = [
            (
                &keycloak,
                "keycloak",
                ann(),
                ("ann", "Ann Lee", "ann@example.org", UserRole::USER_ROLE_USER),
            ),
            (
                &authentik,
                "authentik",
                json!({
                    "sub": "a3f0c7d2e9b14f6a8c5d7e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b", "email": "Bob@Example.org",
                    "email_verified": true, "name": "Bob", "given_name": "Bob", "preferred_username": "bob",
                    "nickname": "bob", "groups": ["authentik Admins", "Guests"], "amr": ["pwd"],
                }),
                ("bob", "Bob", "bob@example.org", UserRole::USER_ROLE_ADMIN),
            ),
            (
                &authelia,
                "authelia",
                json!({
                    "sub": "0b8a6c1e-5d4f-4a3b-9c2d-1e0f9a8b7c6d", "amr": ["pwd", "kba"], "auth_time": 1_800_000_000,
                    "email": "cy@example.org", "email_verified": true, "name": "Cy", "preferred_username": "cy",
                    "groups": ["family"],
                }),
                ("cy", "Cy", "cy@example.org", UserRole::USER_ROLE_VIEWER),
            ),
            (
                &google,
                "google",
                json!({
                    "sub": "104857600000000000002", "email": "dee.lee@gmail.com", "email_verified": true,
                    "name": "Dee Lee", "given_name": "Dee", "family_name": "Lee", "at_hash": "HK6E",
                    "picture": "https://photos.example/a/ACg8ocJ=s96-c",
                }),
                ("dee.lee", "Dee Lee", "dee.lee@gmail.com", UserRole::USER_ROLE_USER),
            ),
        ];
        for (idp, provider, claims, (handle, name, email, role)) in people {
            let session = sign_in(&server, idp, provider, claims).await.unwrap();
            let user = server.user(handle).await.expect(handle);
            assert_eq!(
                (&user.display_name[..], &user.email[..], user.role, user.status),
                (name, email, role.into(), UserStatus::USER_STATUS_ACTIVE.into()),
                "{provider}"
            );
            assert_eq!(session["userId"], user.user_id, "{provider}");
            let devices = call(
                &server.app,
                "AuthService/ListDevices",
                session["token"].as_str(),
                json!({}),
            )
            .await;
            assert_eq!(
                devices.1["devices"][0]["name"], "Ann's Pixel",
                "{provider}: a device session"
            );
        }
        assert_eq!(server.audited("oidc.link").await, 4);
        assert_eq!(server.audited("session.create").await, 4);
    }

    #[tokio::test]
    async fn an_identity_signs_in_to_its_account_again_and_its_role_follows_the_claims() {
        let (idp, provider) = keycloak().await;
        let server = server(&[("keycloak", provider)]).await;
        let first = sign_in(&server, &idp, "keycloak", ann()).await.unwrap();
        let mut again = ann();
        again["preferred_username"] = "annie".into();
        again["groups"] = json!(["/family", "/photolib-admins"]);
        let second = sign_in(&server, &idp, "keycloak", again.clone()).await.unwrap();
        assert_eq!(second["userId"], first["userId"]);
        assert_ne!(
            second["deviceId"], first["deviceId"],
            "a client that names no device gets a new one"
        );
        let ann = server.user("ann").await.unwrap();
        assert_eq!(
            ann.role,
            UserRole::USER_ROLE_ADMIN,
            "the handle stays, the role follows"
        );
        assert!(server.user("annie").await.is_none());
        again["groups"] = json!(["/friends"]);
        assert_eq!(
            sign_in(&server, &idp, "keycloak", again.clone()).await,
            Err(refused("oidc.not_allowed"))
        );
        assert_eq!(server.user("ann").await.unwrap().role, UserRole::USER_ROLE_ADMIN);
        let disable = User {
            user_id: ann.user_id.clone(),
            status: UserStatus::USER_STATUS_DISABLED.into(),
            ..Default::default()
        };
        server
            .accounts
            .update(server.root, disable, &["status".into()])
            .await
            .unwrap();
        again["groups"] = json!(["/family"]);
        assert_eq!(
            sign_in(&server, &idp, "keycloak", again).await,
            Err(refused("oidc.not_allowed"))
        );
        assert_eq!(
            server.accounts.list().await.unwrap().len(),
            2,
            "nobody else was created"
        );
    }

    /// The provider's browser session may live on a stolen device (ADR-0242).
    #[tokio::test]
    async fn an_oidc_sign_in_is_no_proof_for_a_step_up() {
        let (idp, provider) = keycloak().await;
        let server = server(&[("keycloak", provider)]).await;
        let session = sign_in(&server, &idp, "keycloak", ann()).await.unwrap();
        sqlx::query("INSERT INTO totp_secrets (user_id, secret, last_step) VALUES ($1::uuid, '\\x00', 0)")
            .bind(session["userId"].as_str())
            .execute(&server.pool)
            .await
            .unwrap();
        let bearer = session["token"].as_str();
        assert_eq!(
            call(&server.app, "AuthService/DeleteTotp", bearer, json!({})).await,
            (StatusCode::FORBIDDEN, refused("step_up.required"))
        );
    }

    #[tokio::test]
    async fn without_provisioning_only_linked_identities_and_with_email_linking_verified_emails_sign_in() {
        let (idp, mut strict) = keycloak().await;
        strict.provision = false;
        let mut by_email = strict.clone();
        by_email.link_by_email = true;
        let server = server(&[("strict", strict), ("email", by_email)]).await;
        let person = User {
            handle: "annlee".into(),
            display_name: "Ann".into(),
            email: "ANN@example.org".into(),
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        };
        let account = server.accounts.create(server.root, person).await.unwrap();
        assert_eq!(
            sign_in(&server, &idp, "strict", ann()).await,
            Err(refused("oidc.not_allowed"))
        );
        let mut unverified = ann();
        unverified["email_verified"] = false.into();
        assert_eq!(
            sign_in(&server, &idp, "email", unverified).await,
            Err(refused("oidc.not_allowed"))
        );
        let mut stranger = ann();
        stranger["sub"] = "someone else".into();
        stranger["email"] = "bob@example.org".into();
        assert_eq!(
            sign_in(&server, &idp, "email", stranger).await,
            Err(refused("oidc.not_allowed"))
        );
        let linked = sign_in(&server, &idp, "email", ann()).await.unwrap();
        assert_eq!(linked["userId"], account.user_id);
        let mut moved = ann();
        moved["email"] = "ann@elsewhere.example".into();
        let session = sign_in(&server, &idp, "strict", moved).await.unwrap();
        assert_eq!(
            session["userId"], account.user_id,
            "the identity is its issuer and subject, not its email"
        );
        assert_eq!(server.accounts.list().await.unwrap().len(), 2);
    }

    #[tokio::test]
    async fn a_signed_in_account_links_identities_that_no_other_account_has() {
        let (idp, mut provider) = keycloak().await;
        provider.provision = false;
        let server = server(&[("keycloak", provider)]).await;
        let root = server.session(server.root).await;
        let linked = flow(&server, &idp, "keycloak", ann(), Some(&root)).await;
        assert_eq!(linked, (StatusCode::OK, json!({})));
        let again = flow(&server, &idp, "keycloak", ann(), Some(&root)).await;
        assert_eq!(again, (StatusCode::OK, json!({})), "linking twice changes nothing");
        let session = sign_in(&server, &idp, "keycloak", ann()).await.unwrap();
        assert_eq!(session["userId"], server.root.to_string());
        let person = User {
            handle: "bob".into(),
            display_name: "Bob".into(),
            role: UserRole::USER_ROLE_USER.into(),
            ..Default::default()
        };
        let bob = server.accounts.create(server.root, person).await.unwrap();
        let bob = server.session(bob.user_id.parse().unwrap()).await;
        let taken = flow(&server, &idp, "keycloak", ann(), Some(&bob)).await;
        assert_eq!(
            taken,
            (
                StatusCode::CONFLICT,
                json!({ "code": "already_exists", "reason": "oidc.identity_taken" })
            )
        );
        let body = json!({ "provider": "keycloak", "redirectUri": REDIRECT, "codeChallenge": challenge(VERIFIER), "link": true });
        let anonymous = call(&server.app, "AuthService/StartOidc", None, body).await;
        assert_eq!(
            anonymous,
            (
                StatusCode::UNAUTHORIZED,
                json!({ "code": "unauthenticated", "reason": "session.required" })
            )
        );
        assert_eq!(server.audited("oidc.link").await, 1);
    }

    #[tokio::test]
    async fn a_malformed_claim_fails_one_sign_in_and_never_the_api() {
        let (idp, provider) = keycloak().await;
        let server = server(&[("keycloak", provider)]).await;
        let picture = format!("{}/ann.png", idp.issuer);
        let long = "x".repeat(300);
        for (claim, value) in [
            ("sub", json!(["5f0c"])),
            ("email", json!({ "address": "ann@example.org" })),
            ("email_verified", json!("yes")),
            ("name", json!(long)),
            ("preferred_username", json!(["ann"])),
            ("picture", json!("data:image/svg+xml;base64,PHN2Zz48c2NyaXB0Pg==")),
            ("groups", json!({ "/family": true })),
        ] {
            let mut claims = ann();
            claims[claim] = value;
            let failed = json!({ "code": "permission_denied", "reason": "oidc.claim_invalid", "claim": claim });
            assert_eq!(sign_in(&server, &idp, "keycloak", claims).await, Err(failed));
        }
        for (path, status, body, reason) in [
            ("/token", 200, "x".repeat(70_000), "oidc.unavailable"),
            ("/token", 200, "[1, 2".into(), "oidc.unavailable"),
            ("/token", 400, r#"{"error":"invalid_grant"}"#.into(), "oidc.failed"),
            ("/token", 200, r#"{"access_token":"x"}"#.into(), "oidc.failed"),
            (
                "/jwks",
                200,
                json!({ "keys": [Signer::es256().jwk()] }).to_string(),
                "oidc.failed",
            ),
            (
                "/userinfo",
                200,
                json!({ "sub": "someone else" }).to_string(),
                "oidc.failed",
            ),
            (
                "/userinfo",
                200,
                json!({ "sub": ann()["sub"], "name": [] }).to_string(),
                "oidc.claim_invalid",
            ),
            ("/userinfo", 500, "{}".into(), "oidc.unavailable"),
        ] {
            idp.answer_next(&format!("/realms/home{path}"), status, body);
            let error = sign_in(&server, &idp, "keycloak", ann()).await.unwrap_err();
            assert_eq!(error["reason"], reason, "{path} {status}");
        }
        assert_eq!(
            server.accounts.list().await.unwrap().len(),
            1,
            "no failed sign-in made an account"
        );
        let info = call(&server.app, "ServerInfoService/GetServerInfo", None, json!({})).await;
        assert_eq!(info.0, StatusCode::OK);
        let mut claims = ann();
        claims["picture"] = picture.clone().into();
        assert!(
            sign_in(&server, &idp, "keycloak", claims).await.is_err(),
            "an http:// picture"
        );
        let mut claims = ann();
        claims["picture"] = picture.replace("http:", "https:").into();
        assert!(
            sign_in(&server, &idp, "keycloak", claims).await.is_ok(),
            "the API still signs people in"
        );
        assert!(
            !idp.seen().iter().any(|path| path.ends_with(".png")),
            "a picture is never fetched"
        );
    }

    #[tokio::test]
    async fn a_flow_is_single_use_bound_to_its_verifier_and_needs_its_provider() {
        let (idp, provider) = keycloak().await;
        let mut gone = provider.clone();
        gone.issuer = "http://127.0.0.1:9/realms/home".into();
        let mut impostor = provider.clone();
        impostor.issuer = format!("{}/", provider.issuer);
        let server = server(&[("keycloak", provider), ("gone", gone), ("impostor", impostor)]).await;
        let start = |provider: &str, redirect: &str, challenge: &str| {
            let body = json!({ "provider": provider, "redirectUri": redirect, "codeChallenge": challenge });
            call(&server.app, "AuthService/StartOidc", None, body)
        };
        let good = challenge(VERIFIER);
        let invalid = |field: &str| {
            (
                StatusCode::BAD_REQUEST,
                json!({ "code": "invalid_argument", "reason": "field.invalid", "field": field }),
            )
        };
        for redirect in [
            "",
            "/oidc",
            "app.photolib:/oidc#x",
            &format!("https://photos.example/{}", "x".repeat(2048)),
        ] {
            assert_eq!(
                start("keycloak", redirect, &good).await,
                invalid("redirect_uri"),
                "{redirect}"
            );
        }
        for challenge in ["", "short", &good.replace('-', "+"), &format!("{good}A")] {
            assert_eq!(
                start("keycloak", REDIRECT, challenge).await,
                invalid("code_challenge"),
                "{challenge}"
            );
        }
        assert_eq!(
            start("nobody", REDIRECT, &good).await,
            (
                StatusCode::NOT_FOUND,
                json!({ "code": "not_found", "reason": "oidc.provider_unknown" })
            )
        );
        let unavailable = (
            StatusCode::SERVICE_UNAVAILABLE,
            json!({ "code": "unavailable", "reason": "oidc.unavailable" }),
        );
        assert_eq!(start("gone", REDIRECT, &good).await, unavailable);
        assert_eq!(
            start("impostor", REDIRECT, &good).await,
            unavailable,
            "discovery names another issuer"
        );
        let (_, started) = start("keycloak", REDIRECT, &good).await;
        let (state, code) = idp.authorize(started["authorizationUrl"].as_str().unwrap(), ann());
        let complete = |verifier: &str, device: Value| {
            let body = json!({ "state": state, "code": code, "codeVerifier": verifier, "device": device });
            call(&server.app, "AuthService/CompleteOidc", None, body)
        };
        assert_eq!(
            complete(VERIFIER, json!({ "name": "", "platform": "android" })).await,
            invalid("device.name")
        );
        let failed = (StatusCode::FORBIDDEN, refused("oidc.failed"));
        assert_eq!(
            complete(&VERIFIER.replace('d', "e"), phone()).await,
            failed,
            "another verifier"
        );
        assert_eq!(complete(VERIFIER, phone()).await, failed, "the flow is used up");
        let body = json!({ "state": "unknown", "code": code, "codeVerifier": VERIFIER, "device": phone() });
        assert_eq!(call(&server.app, "AuthService/CompleteOidc", None, body).await, failed);
        assert_eq!(server.accounts.list().await.unwrap().len(), 1);
        let info = call(&server.app, "ServerInfoService/GetServerInfo", None, json!({}))
            .await
            .1;
        assert_eq!(info["authMethods"], json!(["AUTH_METHOD_OPAQUE", "AUTH_METHOD_OIDC"]));
        assert_eq!(
            info["oidcProviders"],
            json!([
                { "id": "gone", "name": "Test IdP" },
                { "id": "impostor", "name": "Test IdP" },
                { "id": "keycloak", "name": "Test IdP" },
            ])
        );
    }

    /// Signs in at a real provider, with `tools/oidc/signin.py` as the browser: `TEST_OIDC_ISSUER`,
    /// `TEST_OIDC_CLIENT_ID`, `TEST_OIDC_CLIENT_SECRET` (unset for a public client), `TEST_OIDC_SCOPES` and
    /// `TEST_OIDC_BROWSER`, a command that signs in at the URL it is given and prints where the provider redirects. With
    /// `TEST_OIDC_USER_GROUP`, only that value of the `groups` claim may sign in.
    #[tokio::test]
    #[ignore = "needs a provider in TEST_OIDC_ISSUER"]
    async fn a_real_provider_signs_a_person_in() {
        let env = |name: &str| std::env::var(name).ok();
        let scopes = env("TEST_OIDC_SCOPES").unwrap_or("openid profile email".into());
        let provider = OidcProvider {
            name: "Real".into(),
            issuer: env("TEST_OIDC_ISSUER").unwrap(),
            client_id: env("TEST_OIDC_CLIENT_ID").unwrap(),
            client_secret: env("TEST_OIDC_CLIENT_SECRET").map(crate::secret::Secret::new),
            scopes: scopes.split(' ').map(String::from).collect(),
            provision: true,
            link_by_email: false,
            roles: env("TEST_OIDC_USER_GROUP").and_then(|group| groups("groups", &[], &[&group], &[])),
        };
        let server = server(&[("real", provider)]).await;
        let start = json!({ "provider": "real", "redirectUri": REDIRECT, "codeChallenge": challenge(VERIFIER) });
        let (status, started) = call(&server.app, "AuthService/StartOidc", None, start).await;
        assert_eq!(status, StatusCode::OK, "{started}");
        let browser = photolib_spawn::output(
            photolib_spawn::tool("sh")
                .args(["-c", &format!("{} \"$1\"", env("TEST_OIDC_BROWSER").unwrap()), "sh"])
                .arg(started["authorizationUrl"].as_str().unwrap()),
            std::time::Duration::from_secs(300),
        );
        let redirected = String::from_utf8(browser.stdout).unwrap();
        assert!(
            redirected.starts_with(REDIRECT),
            "{redirected}{}",
            String::from_utf8_lossy(&browser.stderr)
        );
        let query: BTreeMap<String, String> = Url::parse(redirected.trim())
            .unwrap()
            .query_pairs()
            .into_owned()
            .collect();
        let body =
            json!({ "state": query["state"], "code": query["code"], "codeVerifier": VERIFIER, "device": phone() });
        let (status, completed) = call(&server.app, "AuthService/CompleteOidc", None, body).await;
        assert_eq!(status, StatusCode::OK, "{completed}");
        let user = server
            .accounts
            .get(completed["session"]["userId"].as_str().unwrap().parse().unwrap());
        let user = user.await.unwrap().unwrap();
        eprintln!(
            "signed in as {} ({}, {}, {:?})",
            user.handle, user.display_name, user.email, user.role
        );
        assert!(!user.handle.is_empty() && user.status == UserStatus::USER_STATUS_ACTIVE);
    }
}
