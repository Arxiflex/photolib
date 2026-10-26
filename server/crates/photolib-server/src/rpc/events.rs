//! The events API and webhooks (M9-04, ADR-0263): `EventService` pages the caller's events through `events::page`;
//! `WebhookService` manages the caller's webhooks, which only the account signed in creates, and only while the
//! configuration turns webhooks on.

use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_proto::{
    connect::photolib::api::v1::{EventService, WebhookService},
    proto::photolib::api::v1::{
        CreateWebhookRequest, CreateWebhookResponse, DeleteWebhookRequest, DeleteWebhookResponse, ListEventsRequest,
        ListEventsResponse, ListWebhooksRequest, ListWebhooksResponse,
    },
};

use super::{
    ApiError, Users,
    authz::{actor, principal},
    users::internal,
};
use crate::events::{self, Position, WebhookError};

fn invalid(field: &'static str) -> ConnectError {
    ApiError::new(ErrorCode::InvalidArgument, "field.invalid")
        .param("field", field)
        .into()
}

impl From<WebhookError> for ConnectError {
    fn from(error: WebhookError) -> Self {
        match error {
            WebhookError::Invalid(field) => invalid(field),
            WebhookError::NotFound => ApiError::new(ErrorCode::NotFound, "webhook.not_found").into(),
            WebhookError::Limit => ApiError::new(ErrorCode::ResourceExhausted, "webhook.limit").into(),
            WebhookError::Db(error) => internal(error),
        }
    }
}

#[allow(refining_impl_trait)]
impl EventService for Users {
    async fn list_events(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, ListEventsRequest>,
    ) -> ServiceResult<ListEventsResponse> {
        let (who, _) = principal(&ctx)?;
        let request = request.to_owned_message();
        let after = Position::parse(&request.after).ok_or_else(|| invalid("after"))?;
        let limit = match u16::try_from(request.page_size) {
            Ok(0) => 100,
            Ok(size @ 1..=1000) => size,
            _ => return Err(invalid("page_size")),
        };
        let pool = self.accounts.pool();
        let (events, next) = events::page(pool, who, after, limit).await.map_err(internal)?;
        Ok(ListEventsResponse {
            events,
            next_after: next.to_string(),
            ..Default::default()
        }
        .into())
    }
}

#[allow(refining_impl_trait)]
impl WebhookService for Users {
    async fn list_webhooks(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, ListWebhooksRequest>,
    ) -> ServiceResult<ListWebhooksResponse> {
        Ok(ListWebhooksResponse {
            webhooks: events::list(self.accounts.pool(), actor(&ctx)?)
                .await
                .map_err(internal)?,
            ..Default::default()
        }
        .into())
    }

    async fn create_webhook(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CreateWebhookRequest>,
    ) -> ServiceResult<CreateWebhookResponse> {
        if !self.webhooks {
            return Err(ApiError::new(ErrorCode::FailedPrecondition, "webhooks.disabled").into());
        }
        let url = request.to_owned_message().url;
        let (webhook, secret) = events::create(self.accounts.pool(), actor(&ctx)?, &url).await?;
        Ok(CreateWebhookResponse {
            webhook: webhook.into(),
            secret,
            ..Default::default()
        }
        .into())
    }

    async fn delete_webhook(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, DeleteWebhookRequest>,
    ) -> ServiceResult<DeleteWebhookResponse> {
        let id = request.to_owned_message().webhook_id;
        events::delete(self.accounts.pool(), actor(&ctx)?, &id).await?;
        Ok(DeleteWebhookResponse::default().into())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::http::StatusCode;
    use base64::{Engine, engine::general_purpose::STANDARD};
    use photolib_proto::proto::photolib::api::v1::{ApiKeyScope, UserRole};
    use serde_json::{Value, json};

    use crate::{
        keys::ApiKeys,
        rpc::{
            Users,
            keys::tests::key,
            users::tests::{app, call, denied, person, with_admin},
        },
        testing::BearerSessions,
    };

    /// The API with webhooks on, as an administrator signed in.
    async fn api() -> (
        super::super::users::tests::Api,
        axum::Router,
        photolib_proto::proto::photolib::api::v1::User,
    ) {
        let (api, root) = with_admin().await;
        let keys = ApiKeys::new(api.pool.clone());
        let users = Users::start(api.accounts.clone(), keys, Arc::new(BearerSessions))
            .await
            .unwrap();
        let app = app(users.with_webhooks(true), None, &api.pool, &api.data, &api.tail);
        (api, app, root)
    }

    fn invalid(field: &str) -> (StatusCode, Value) {
        let mut error = denied("invalid_argument", "field.invalid");
        error["field"] = field.into();
        (StatusCode::BAD_REQUEST, error)
    }

    #[tokio::test]
    async fn an_account_registers_lists_and_deletes_its_own_webhooks_and_each_change_is_audited() {
        let (api, app, root) = api().await;
        let url = "http://homeassistant.test:8123/api/webhook/photolib-0a1b2c";
        let create = json!({ "url": url });
        let (status, created) = call(&app, "WebhookService/CreateWebhook", Some(&root), create.clone()).await;
        assert_eq!(status, StatusCode::OK, "{created}");
        let secret = created["secret"].as_str().unwrap();
        let key = STANDARD.decode(secret.strip_prefix("whsec_").unwrap()).unwrap();
        assert_eq!(key.len(), 32);
        let webhook = &created["webhook"];
        assert_eq!(webhook["url"], url);
        assert!(
            webhook["createdAt"].is_string() && webhook.get("deliveredAt").is_none(),
            "{webhook}"
        );
        let id = webhook["webhookId"].as_str().unwrap().to_string();
        let (_, listed) = call(&app, "WebhookService/ListWebhooks", Some(&root), json!({})).await;
        assert_eq!(listed, json!({ "webhooks": [webhook] }), "the secret is shown once");

        let actor = root.user_id.parse().unwrap();
        let bob = Some(
            api.accounts
                .create(actor, person("bob", UserRole::USER_ROLE_USER))
                .await
                .unwrap(),
        );
        let delete = json!({ "webhookId": id });
        assert_eq!(
            call(&app, "WebhookService/DeleteWebhook", bob.as_ref(), delete.clone()).await,
            (StatusCode::NOT_FOUND, denied("not_found", "webhook.not_found")),
            "nobody else deletes it"
        );
        let (_, theirs) = call(&app, "WebhookService/ListWebhooks", bob.as_ref(), json!({})).await;
        assert_eq!(theirs, json!({}), "nor sees it");
        let (status, _) = call(&app, "WebhookService/DeleteWebhook", Some(&root), delete.clone()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(
            call(&app, "WebhookService/DeleteWebhook", Some(&root), delete).await,
            (StatusCode::NOT_FOUND, denied("not_found", "webhook.not_found"))
        );
        let audited: Vec<(String, String, String, bool)> = sqlx::query_as(
            "SELECT action, actor_user_id::text, target ->> 'webhook_id', strpos(to_jsonb(e)::text, 'homeassistant') = 0
             FROM audit_events e WHERE action LIKE 'webhook.%' ORDER BY id",
        )
        .fetch_all(&api.pool)
        .await
        .unwrap();
        let by_root = |action: &str| (action.to_string(), root.user_id.clone(), id.clone(), true);
        assert_eq!(
            audited,
            [by_root("webhook.create"), by_root("webhook.delete")],
            "never the URL"
        );

        for _ in 0..10 {
            let (status, _) = call(&app, "WebhookService/CreateWebhook", bob.as_ref(), create.clone()).await;
            assert_eq!(status, StatusCode::OK);
        }
        assert_eq!(
            call(&app, "WebhookService/CreateWebhook", bob.as_ref(), create).await,
            (
                StatusCode::TOO_MANY_REQUESTS,
                denied("resource_exhausted", "webhook.limit")
            )
        );
    }

    #[tokio::test]
    async fn a_webhook_is_refused_where_it_could_reach_this_machine_or_while_webhooks_are_off() {
        let (api, app, root) = api().await;
        let long = format!("https://example.org/{}", "a".repeat(2000));
        let refused = [
            "",
            "homeassistant.test:8123",
            "ftp://example.org/hook",
            "file:///etc/passwd",
            &long,
        ];
        let hosts = [
            "127.0.0.1:8123",
            "127.1.2.3",
            "0.0.0.0:2283",
            "0.1.2.3",
            "[::1]",
            "[::]",
            "[::ffff:127.0.0.1]",
            "169.254.169.254",
            "[fe80::1]",
            "255.255.255.255",
            "224.0.0.1",
            "[ff02::1]",
        ];
        let at = hosts.map(|host| format!("http://{host}/"));
        for url in refused.into_iter().chain(at.iter().map(String::as_str)) {
            let request = json!({ "url": url });
            let answer = call(&app, "WebhookService/CreateWebhook", Some(&root), request).await;
            assert_eq!(answer, invalid("url"), "{url}");
        }
        for host in ["192.168.1.20:8123", "[fd00::20]", "hooks.example.org"] {
            let request = json!({ "url": format!("https://{host}/") });
            let (status, _) = call(&app, "WebhookService/CreateWebhook", Some(&root), request).await;
            assert_eq!(status, StatusCode::OK, "{host}: a LAN or public address");
        }
        let request = json!({ "webhookId": "x" });
        let answer = call(&app, "WebhookService/DeleteWebhook", Some(&root), request).await;
        assert_eq!(answer, invalid("webhook_id"));
        let request = json!({ "url": "https://hooks.example.org/" });
        assert_eq!(
            call(&api.app, "WebhookService/CreateWebhook", Some(&root), request).await,
            (
                StatusCode::BAD_REQUEST,
                denied("failed_precondition", "webhooks.disabled")
            ),
            "off by default"
        );
        let (_, listed) = call(&api.app, "WebhookService/ListWebhooks", Some(&root), json!({})).await;
        assert_eq!(
            listed["webhooks"].as_array().unwrap().len(),
            3,
            "listed while off, to delete them"
        );
    }

    #[tokio::test]
    async fn a_key_with_view_pages_through_the_events_of_its_account() {
        let (api, app, root) = api().await;
        let owner = root.user_id.parse().unwrap();
        let photos = crate::events::tests::library(&api.pool, owner, "standard").await;
        let first = crate::events::tests::asset(&api.pool, photos).await;
        let second = crate::events::tests::asset(&api.pool, photos).await;
        photolib_db::testpg::settle(&api.pool).await;
        let by_key = key(&api.pool, &root, &[ApiKeyScope::API_KEY_SCOPE_VIEW]).await;
        let list = |body: Value| call(&app, "EventService/ListEvents", Some(&by_key), body);
        let (status, page) = list(json!({ "pageSize": 1 })).await;
        assert_eq!(status, StatusCode::OK, "{page}");
        let event = &page["events"][0];
        assert_eq!(page["events"].as_array().unwrap().len(), 1);
        assert_eq!(page["nextAfter"], event["eventId"]);
        assert!(event["recordedAt"].as_str().unwrap().ends_with('Z'), "{event}");
        let mut event = event.clone();
        event
            .as_object_mut()
            .unwrap()
            .retain(|name, _| !["eventId", "recordedAt"].contains(&name.as_str()));
        let created = |asset: uuid::Uuid| json!({ "type": "EVENT_TYPE_ASSET_CREATED", "libraryId": photos.to_string(), "assetId": asset.to_string() });
        assert_eq!(event, created(first));
        let (_, rest) = list(json!({ "after": page["nextAfter"] })).await;
        assert_eq!(rest["events"][0]["assetId"], second.to_string());
        assert_eq!(rest["events"].as_array().unwrap().len(), 1, "{rest}");
        let (_, end) = list(json!({ "after": rest["nextAfter"] })).await;
        assert_eq!(end.get("events"), None, "{end}");
        assert_eq!(list(json!({ "after": "x" })).await, invalid("after"));
        assert_eq!(list(json!({ "pageSize": 1001 })).await, invalid("page_size"));
    }
}
