//! `FaceService` (ADR-0389): the account's face consent and the faces found in an asset. The consent is the account's
//! alone: its routes take the session, never an API key, so that a leaked key cannot start processing of faces.

use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_authz::{Action, Capability, Resource, Stream, can, policy};
use photolib_proto::{
    connect::photolib::api::v1::FaceService,
    proto::photolib::api::v1::{
        AssetFace, FaceConsentState, GetFaceConsentRequest, GetFaceConsentResponse, ListFacesRequest,
        ListFacesResponse, SetFaceConsentRequest, SetFaceConsentResponse,
    },
};
use uuid::Uuid;

use super::{
    ApiError, Users,
    authz::{actor, principal},
    users::internal,
};
use crate::{
    accounts::timestamp,
    faces::{self, ConsentError, NOTICE_VERSION},
};

fn invalid(field: &'static str) -> ConnectError {
    ApiError::new(ErrorCode::InvalidArgument, "field.invalid")
        .param("field", field)
        .into()
}

/// Where the account stands, with whether the server's policy allows faces for it.
async fn state(pool: &sqlx::PgPool, user: Uuid) -> Result<FaceConsentState, ConnectError> {
    let consent = faces::consent(pool, user).await.map_err(internal)?;
    let switches = policy(pool, Some(user), None).await.map_err(internal)?;
    let available = switches
        .iter()
        .find(|(capability, ..)| *capability == Capability::FaceRecognition)
        .is_none_or(|(_, on, _)| *on);
    Ok(FaceConsentState {
        notice_version: NOTICE_VERSION.unsigned_abs(),
        granted: consent.granted.is_some(),
        granted_version: consent.granted.map_or(0, |(version, _)| version.unsigned_abs()),
        granted_at: consent.granted.map(|(_, at)| timestamp(at)).into(),
        available,
        ..Default::default()
    })
}

#[allow(refining_impl_trait)]
impl FaceService for Users {
    async fn get_face_consent(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, GetFaceConsentRequest>,
    ) -> ServiceResult<GetFaceConsentResponse> {
        let state = state(self.accounts.pool(), actor(&ctx)?).await?;
        Ok(GetFaceConsentResponse {
            state: Some(state).into(),
            ..Default::default()
        }
        .into())
    }

    async fn set_face_consent(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, SetFaceConsentRequest>,
    ) -> ServiceResult<SetFaceConsentResponse> {
        let (pool, user) = (self.accounts.pool(), actor(&ctx)?);
        let request = request.to_owned_message();
        if request.granted {
            let version = i32::try_from(request.notice_version).unwrap_or(0);
            faces::grant(pool, user, version).await.map_err(|error| match error {
                ConsentError::Outdated => ApiError::new(ErrorCode::FailedPrecondition, "faces.notice_outdated")
                    .param("notice_version", NOTICE_VERSION.to_string())
                    .into(),
                ConsentError::Db(error) => internal(error),
            })?;
        } else {
            faces::withdraw(pool, user).await.map_err(internal)?;
        }
        Ok(SetFaceConsentResponse {
            state: Some(state(pool, user).await?).into(),
            ..Default::default()
        }
        .into())
    }

    async fn list_faces(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, ListFacesRequest>,
    ) -> ServiceResult<ListFacesResponse> {
        let (who, _) = principal(&ctx)?;
        let pool = self.accounts.pool();
        let asset: Uuid = request
            .to_owned_message()
            .asset_id
            .parse()
            .map_err(|_| invalid("asset_id"))?;
        let not_found = || ConnectError::from(ApiError::new(ErrorCode::NotFound, "asset.not_found"));
        if !can(pool, who, Action::View, Resource::Asset(asset))
            .await
            .map_err(internal)?
        {
            return Err(not_found());
        }
        let library: Uuid = sqlx::query_scalar("SELECT library_id FROM assets WHERE id = $1")
            .bind(asset)
            .fetch_optional(pool)
            .await
            .map_err(internal)?
            .ok_or_else(not_found)?;
        // With face recognition switched off for the library, there are no faces to show.
        let allowed = can(pool, who, Action::View, Resource::Stream(Stream::Faces(library))).await;
        if !allowed.map_err(internal)? {
            return Ok(ListFacesResponse::default().into());
        }
        let rows = faces::list(pool, asset).await.map_err(internal)?;
        Ok(ListFacesResponse {
            faces: rows
                .into_iter()
                .map(|face| AssetFace {
                    face_id: face.id.to_string(),
                    x: face.bbox[0],
                    y: face.bbox[1],
                    width: face.bbox[2],
                    height: face.bbox[3],
                    landmarks: face.landmarks,
                    score: face.score,
                    time_ms: face.time_ms.map(i32::unsigned_abs),
                    model_id: face.model_id,
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        }
        .into())
    }
}

#[cfg(test)]
mod tests {
    use axum::http::StatusCode;
    use photolib_proto::proto::photolib::api::v1::{ApiKeyScope, UserRole};
    use serde_json::{Value, json};
    use uuid::Uuid;

    use crate::rpc::{
        keys::tests::key,
        users::tests::{call, denied, person, with_admin},
    };

    async fn api() -> (
        super::super::users::tests::Api,
        photolib_proto::proto::photolib::api::v1::User,
    ) {
        with_admin().await
    }

    /// A face in `asset`, as the job would keep it.
    async fn face(pool: &sqlx::PgPool, asset: Uuid) -> Uuid {
        sqlx::query_scalar(
            "INSERT INTO faces (id, asset_id, bbox, landmarks, model_id, embedding, score, detector)
             VALUES (gen_random_uuid(), $1, '{0.25,0.125,0.5,0.375}', '{\"points\": [0.3,0.2,0.6,0.2,0.45,0.3,0.35,0.4,0.55,0.4]}',
                     'sface@2021dec', '\\x0102', 0.875, 'yunet@2026may') RETURNING id",
        )
        .bind(asset)
        .fetch_one(pool)
        .await
        .unwrap()
    }

    async fn count(pool: &sqlx::PgPool, sql: &str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(pool).await.unwrap()
    }

    fn state(granted: bool, version: u32) -> Value {
        let mut state = json!({ "noticeVersion": 1, "available": true });
        if granted {
            state["granted"] = true.into();
            state["grantedVersion"] = version.into();
        }
        state
    }

    #[tokio::test]
    async fn nobody_has_agreed_until_they_do_and_the_notice_version_must_be_the_current_one() {
        let (api, root) = api().await;
        let (status, got) = call(&api.app, "FaceService/GetFaceConsent", Some(&root), json!({})).await;
        assert_eq!(status, StatusCode::OK, "{got}");
        assert_eq!(got["state"], state(false, 0));
        let wrong = json!({ "granted": true, "noticeVersion": 7 });
        let (status, error) = call(&api.app, "FaceService/SetFaceConsent", Some(&root), wrong).await;
        assert_eq!(
            (status, error["reason"].clone()),
            (StatusCode::BAD_REQUEST, "faces.notice_outdated".into())
        );
        let none = json!({ "granted": true });
        let (status, _) = call(&api.app, "FaceService/SetFaceConsent", Some(&root), none).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "agreeing to no notice is no agreement");
        let (_, still) = call(&api.app, "FaceService/GetFaceConsent", Some(&root), json!({})).await;
        assert_eq!(still["state"], state(false, 0));

        let agree = json!({ "granted": true, "noticeVersion": 1 });
        let (status, agreed) = call(&api.app, "FaceService/SetFaceConsent", Some(&root), agree.clone()).await;
        assert_eq!(status, StatusCode::OK, "{agreed}");
        let mut expected = state(true, 1);
        expected["grantedAt"] = agreed["state"]["grantedAt"].clone();
        assert!(expected["grantedAt"].as_str().unwrap().ends_with('Z'), "{agreed}");
        assert_eq!(agreed["state"], expected);
        // Agreeing again changes nothing but is no error.
        let (status, _) = call(&api.app, "FaceService/SetFaceConsent", Some(&root), agree).await;
        assert_eq!(status, StatusCode::OK);
        let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM face_consents")
            .fetch_one(&api.pool)
            .await
            .unwrap();
        assert_eq!(rows, 1);
        let audited: Vec<(String, String)> = sqlx::query_as(
            "SELECT action, actor_user_id::text FROM audit_events WHERE action LIKE 'faces.%' ORDER BY id",
        )
        .fetch_all(&api.pool)
        .await
        .unwrap();
        assert_eq!(
            audited,
            [("faces.consent_grant".to_string(), root.user_id.clone())],
            "the second agreement is not logged again"
        );
    }

    #[tokio::test]
    async fn withdrawing_deletes_the_accounts_faces_scans_and_queued_jobs_and_nobody_elses() {
        let (api, root) = api().await;
        let me = root.user_id.parse().unwrap();
        let bob = api
            .accounts
            .create(me, person("bob", UserRole::USER_ROLE_USER))
            .await
            .unwrap();
        let bob_id: Uuid = bob.user_id.parse().unwrap();
        let mine = crate::events::tests::library(&api.pool, me, "standard").await;
        let bobs = crate::events::tests::library(&api.pool, bob_id, "standard").await;
        let (a, b) = (
            crate::events::tests::asset(&api.pool, mine).await,
            crate::events::tests::asset(&api.pool, bobs).await,
        );
        for user in [me, bob_id] {
            sqlx::query("INSERT INTO face_consents (user_id, notice_version) VALUES ($1, 1)")
                .bind(user)
                .execute(&api.pool)
                .await
                .unwrap();
        }
        for asset in [a, b] {
            face(&api.pool, asset).await;
            sqlx::query("INSERT INTO face_scans (asset_id, model_id, faces) VALUES ($1, 'sface@2021dec', 1)")
                .bind(asset)
                .execute(&api.pool)
                .await
                .unwrap();
            sqlx::query(
                "INSERT INTO jobs (id, type, payload, status, placement, idempotency_key)
                 VALUES (photolib_uuidv7(), 'faces', convert_to($2, 'UTF8'), CASE WHEN $1 = $4 THEN 'done' ELSE 'queued' END, 'server', $3)",
            )
            .bind(asset)
            .bind(format!("{{\"asset\": \"{asset}\"}}"))
            .bind(format!("faces:{asset}:sface@2021dec"))
            .bind(a)
            .execute(&api.pool)
            .await
            .unwrap();
        }
        let (status, left) = call(
            &api.app,
            "FaceService/SetFaceConsent",
            Some(&root),
            json!({ "granted": false }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{left}");
        assert_eq!(left["state"], state(false, 0));
        assert_eq!(
            count(&api.pool, "SELECT count(*) FROM faces").await,
            1,
            "only Bob's face is left"
        );
        assert_eq!(count(&api.pool, "SELECT count(*) FROM face_scans").await, 1);
        assert_eq!(
            count(
                &api.pool,
                "SELECT count(*) FROM jobs WHERE type = 'faces' AND status = 'queued'"
            )
            .await,
            1
        );
        assert_eq!(count(&api.pool, "SELECT count(*) FROM face_consents").await, 1);
        let left = count(&api.pool, &format!("SELECT count(*) FROM faces WHERE asset_id = '{b}'")).await;
        assert_eq!(left, 1);
        // Withdrawing again is no error, and is not logged twice.
        let (status, _) = call(
            &api.app,
            "FaceService/SetFaceConsent",
            Some(&root),
            json!({ "granted": false }),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        let audited: Vec<String> =
            sqlx::query_scalar("SELECT action FROM audit_events WHERE action LIKE 'faces.%' ORDER BY id")
                .fetch_all(&api.pool)
                .await
                .unwrap();
        assert_eq!(audited, ["faces.consent_withdraw"]);
    }

    #[tokio::test]
    async fn an_api_key_cannot_read_or_change_the_consent() {
        let (api, root) = api().await;
        let by_key = key(&api.pool, &root, &[ApiKeyScope::API_KEY_SCOPE_VIEW]).await;
        for (method, body) in [
            ("GetFaceConsent", json!({})),
            ("SetFaceConsent", json!({ "granted": true, "noticeVersion": 1 })),
        ] {
            let answer = call(&api.app, &format!("FaceService/{method}"), Some(&by_key), body).await;
            assert_eq!(
                answer,
                (
                    StatusCode::FORBIDDEN,
                    denied("permission_denied", "api_key.scope_missing")
                ),
                "{method}"
            );
        }
        let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM face_consents")
            .fetch_one(&api.pool)
            .await
            .unwrap();
        assert_eq!(rows, 0);
    }

    #[tokio::test]
    async fn the_faces_of_an_asset_are_listed_to_whoever_may_view_it_without_their_embeddings() {
        let (api, root) = api().await;
        let me = root.user_id.parse().unwrap();
        let bob = api
            .accounts
            .create(me, person("bob", UserRole::USER_ROLE_USER))
            .await
            .unwrap();
        let photos = crate::events::tests::library(&api.pool, me, "standard").await;
        let asset = crate::events::tests::asset(&api.pool, photos).await;
        let id = face(&api.pool, asset).await;
        let list = json!({ "assetId": asset.to_string() });
        let (status, got) = call(&api.app, "FaceService/ListFaces", Some(&root), list.clone()).await;
        assert_eq!(status, StatusCode::OK, "{got}");
        let expected = json!({ "faces": [{
            "faceId": id.to_string(), "x": 0.25, "y": 0.125, "width": 0.5, "height": 0.375,
            "landmarks": [0.3, 0.2, 0.6, 0.2, 0.45, 0.3, 0.35, 0.4, 0.55, 0.4], "score": 0.875, "modelId": "sface@2021dec"
        }] });
        assert_eq!(got, expected);
        assert!(!got.to_string().contains("embedding"));
        assert_eq!(
            call(&api.app, "FaceService/ListFaces", Some(&bob), list.clone()).await,
            (StatusCode::NOT_FOUND, denied("not_found", "asset.not_found")),
            "a stranger learns nothing of the asset"
        );
        sqlx::query("UPDATE faces SET time_ms = 1500 WHERE id = $1")
            .bind(id)
            .execute(&api.pool)
            .await
            .unwrap();
        let (_, video) = call(&api.app, "FaceService/ListFaces", Some(&root), list.clone()).await;
        assert_eq!(video["faces"][0]["timeMs"], 1500);
        // Switched off for the library, the faces are not shown.
        sqlx::query(
            "INSERT INTO policy_switches (capability, library_id, enabled) VALUES ('face_recognition', $1, false)",
        )
        .bind(photos)
        .execute(&api.pool)
        .await
        .unwrap();
        let (_, off) = call(&api.app, "FaceService/ListFaces", Some(&root), list).await;
        assert_eq!(off, json!({}));
        let bad = call(
            &api.app,
            "FaceService/ListFaces",
            Some(&root),
            json!({ "assetId": "x" }),
        )
        .await;
        assert_eq!(bad.0, StatusCode::BAD_REQUEST);
    }
}
