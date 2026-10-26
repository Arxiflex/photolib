//! `SearchService` (M5-08): the assets whose pictures hold a text, through `search::text`.

use connectrpc::{ConnectError, ErrorCode, RequestContext, ServiceRequest, ServiceResult};
use photolib_proto::{
    connect::photolib::api::v1::SearchService,
    proto::photolib::api::v1::{GetTextRequest, GetTextResponse, SearchTextRequest, SearchTextResponse},
};

use super::{ApiError, Users, authz::principal, users::internal};
use crate::search;

fn invalid(field: &'static str) -> ConnectError {
    ApiError::new(ErrorCode::InvalidArgument, "field.invalid")
        .param("field", field)
        .into()
}

#[allow(refining_impl_trait)]
impl SearchService for Users {
    async fn search_text(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, SearchTextRequest>,
    ) -> ServiceResult<SearchTextResponse> {
        let (who, _) = principal(&ctx)?;
        let request = request.to_owned_message();
        let limit = match u16::try_from(request.page_size) {
            Ok(0) => 50,
            Ok(size @ 1..=200) => size,
            _ => return Err(invalid("page_size")),
        };
        let hits = search::text(self.accounts.pool(), who, &request.query, limit)
            .await
            .map_err(internal)?;
        Ok(SearchTextResponse {
            hits,
            ..Default::default()
        }
        .into())
    }

    async fn get_text(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, GetTextRequest>,
    ) -> ServiceResult<GetTextResponse> {
        let (who, _) = principal(&ctx)?;
        let asset = (request.to_owned_message().asset_id.parse()).map_err(|_| invalid("asset_id"))?;
        match search::of(self.accounts.pool(), who, asset).await.map_err(internal)? {
            Some(text) => Ok(GetTextResponse {
                read: text.is_some(),
                regions: text.as_ref().map(|t| t.regions.clone()).unwrap_or_default(),
                text: text.map(|t| t.text).unwrap_or_default(),
                ..Default::default()
            }
            .into()),
            None => Err(ApiError::new(ErrorCode::NotFound, "asset.not_found").into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use axum::http::StatusCode;
    use photolib_proto::proto::photolib::api::v1::ApiKeyScope;
    use serde_json::{Value, json};
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::{
        events::tests::{asset, library},
        ocr::MODEL,
        rpc::{
            keys::tests::key,
            users::tests::{Api, app, call, denied, with_admin},
        },
        testing::BearerSessions,
    };

    const XSS: &str = "<img src=x onerror=alert(1)>";

    async fn read(pool: &PgPool, asset: Uuid, text: &str) {
        sqlx::query("INSERT INTO asset_ocr (asset_id, model_id, text) VALUES ($1, $2, $3)")
            .bind(asset)
            .bind(MODEL)
            .bind(text)
            .execute(pool)
            .await
            .unwrap();
    }

    /// The API with an administrator, who holds a key that views, a library of pictures and a stranger's.
    struct World {
        api: Api,
        app: axum::Router,
        key: photolib_proto::proto::photolib::api::v1::User,
        photos: Uuid,
        theirs: Uuid,
        owner: Uuid,
    }

    impl World {
        async fn new() -> Self {
            let (api, root) = with_admin().await;
            let keys = crate::keys::ApiKeys::new(api.pool.clone());
            let users = crate::rpc::Users::start(api.accounts.clone(), keys, std::sync::Arc::new(BearerSessions))
                .await
                .unwrap();
            let app = app(users, None, &api.pool, &api.data, &api.tail);
            let owner = root.user_id.parse().unwrap();
            let photos = library(&api.pool, owner, "standard").await;
            let stranger = Uuid::now_v7();
            sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'bob', 'Bob')")
                .bind(stranger)
                .execute(&api.pool)
                .await
                .unwrap();
            let theirs = library(&api.pool, stranger, "standard").await;
            let key = key(&api.pool, &root, &[ApiKeyScope::API_KEY_SCOPE_VIEW]).await;
            Self {
                api,
                app,
                key,
                photos,
                theirs,
                owner,
            }
        }

        /// A picture of `library` that OCR read as `text`.
        async fn picture(&self, library: Uuid, text: &str) -> Uuid {
            let id = asset(&self.api.pool, library).await;
            read(&self.api.pool, id, text).await;
            id
        }

        async fn call(&self, procedure: &str, body: Value) -> (StatusCode, Value) {
            call(&self.app, procedure, Some(&self.key), body).await
        }

        async fn find(&self, query: &str, size: u32) -> (StatusCode, Value) {
            self.call("SearchService/SearchText", json!({ "query": query, "pageSize": size }))
                .await
        }
    }

    #[tokio::test]
    async fn a_key_with_view_finds_the_text_of_pictures_it_may_view() {
        let world = World::new().await;
        let mut assets = vec![];
        for text in [
            "Lisboa Estação 2026",
            "Красная площадь, Москва",
            "東京駅 丸の内",
            XSS,
            "100% sure",
        ] {
            assets.push(world.picture(world.photos, text).await.to_string());
        }
        for (query, found) in [
            ("estação", 0),
            ("LISBOA", 0),
            ("красная", 1),
            ("МОСКВА", 1),
            ("東京", 2),
            ("丸の内", 2),
            ("onerror=alert(1)", 3),
            ("100%", 4),
        ] {
            let (status, answer) = world.find(query, 0).await;
            assert_eq!(status, StatusCode::OK, "{answer}");
            let hit = &answer["hits"];
            assert_eq!(hit.as_array().map(Vec::len), Some(1), "{query}: {answer}");
            assert_eq!(
                (hit[0]["assetId"].as_str(), hit[0]["libraryId"].as_str()),
                (Some(&*assets[found]), Some(&*world.photos.to_string()))
            );
        }
        let (_, answer) = world.find("<img", 0).await;
        assert_eq!(
            answer["hits"][0]["text"], XSS,
            "the payload comes back as the data it is"
        );
        let (_, answer) = world.find("o", 2).await;
        assert_eq!(
            answer["hits"].as_array().map(Vec::len),
            Some(2),
            "the page size bounds the hits"
        );
    }

    #[tokio::test]
    async fn nothing_else_is_a_hit_and_a_bad_request_is_refused() {
        let world = World::new().await;
        // Another account's picture, a private library's, one in the trash, and one with no text.
        world.picture(world.theirs, "Lisboa Estação 2026").await;
        let private = library(&world.api.pool, world.owner, "private").await;
        world.picture(private, "Lisboa Estação 2026").await;
        let trashed = world.picture(world.photos, "Lisboa trashed").await;
        sqlx::query("UPDATE assets SET trashed_at = now() WHERE id = $1")
            .bind(trashed)
            .execute(&world.api.pool)
            .await
            .unwrap();
        asset(&world.api.pool, world.photos).await;
        world.picture(world.photos, "100% sure").await;
        for query in ["Paris", "%%", "_", "", "  ", "trashed", "Lisboa"] {
            let (status, answer) = world.find(query, 0).await;
            assert_eq!(
                (status, answer.get("hits")),
                (StatusCode::OK, None),
                "{query}: {answer}"
            );
        }
        let (status, answer) = world.find("a", 201).await;
        assert_eq!(
            (status, &answer["field"]),
            (StatusCode::BAD_REQUEST, &json!("page_size"))
        );
        assert_eq!(
            call(&world.app, "SearchService/SearchText", None, json!({ "query": "a" })).await,
            (StatusCode::UNAUTHORIZED, denied("unauthenticated", "session.required")),
            "a request without a credential is refused before the handler"
        );
    }

    #[tokio::test]
    async fn the_text_of_one_picture_is_read_by_whoever_may_view_it() {
        let world = World::new().await;
        let text = "<script>alert(1)</script>\n東京駅";
        let read_one = world.picture(world.photos, text).await;
        let unread = asset(&world.api.pool, world.photos).await;
        let theirs = world.picture(world.theirs, "secret").await;
        let get = |asset: String| world.call("SearchService/GetText", json!({ "assetId": asset }));
        assert_eq!(
            get(read_one.to_string()).await,
            (StatusCode::OK, json!({ "text": text, "read": true }))
        );
        assert_eq!(
            get(unread.to_string()).await,
            (StatusCode::OK, json!({})),
            "not read yet"
        );
        let not_found = (StatusCode::NOT_FOUND, denied("not_found", "asset.not_found"));
        assert_eq!(
            get(theirs.to_string()).await,
            not_found,
            "another account's picture is not there"
        );
        assert_eq!(get(Uuid::now_v7().to_string()).await, not_found);
        let (status, answer) = get("x".into()).await;
        assert_eq!(
            (status, &answer["field"]),
            (StatusCode::BAD_REQUEST, &json!("asset_id"))
        );
    }

    #[tokio::test]
    async fn the_regions_of_a_pictures_text_are_those_of_its_current_version() {
        let world = World::new().await;
        let picture = world.picture(world.photos, "Lisboa\nRua").await;
        let get = || world.call("SearchService/GetText", json!({ "assetId": picture.to_string() }));
        let regions = json!([
            {"text": "Lisboa", "x": 0.1, "y": 0.2, "width": 0.5, "height": 0.25},
            {"text": "Rua", "x": 0.1, "y": 0.6, "width": 0.25, "height": 0.25}
        ]);
        sqlx::query("UPDATE asset_ocr SET regions = $2 WHERE asset_id = $1")
            .bind(picture)
            .bind(&regions)
            .execute(&world.api.pool)
            .await
            .unwrap();
        let (status, answer) = get().await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(answer["text"], "Lisboa\nRua");
        let got: Vec<(String, f64, f64)> = answer["regions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| {
                (
                    r["text"].as_str().unwrap().into(),
                    r["x"].as_f64().unwrap(),
                    r["height"].as_f64().unwrap(),
                )
            })
            .collect();
        assert_eq!(got.len(), 2);
        assert_eq!(
            (got[1].0.as_str(), got[1].1 > 0.09, got[1].2 > 0.24),
            ("Rua", true, true)
        );

        // An edit makes the text of the original stale: the picture reads as not read until it is read again.
        let (original, edit) = (Uuid::now_v7(), Uuid::now_v7());
        for (id, kind) in [(original, "original"), (edit, "edit")] {
            sqlx::query("INSERT INTO versions (id, asset_id, kind) VALUES ($1, $2, $3)")
                .bind(id)
                .bind(picture)
                .bind(kind)
                .execute(&world.api.pool)
                .await
                .unwrap();
        }
        let current = |version: Uuid| {
            sqlx::query("UPDATE assets SET current_version_id = $1 WHERE id = $2")
                .bind(version)
                .bind(picture)
        };
        current(original).execute(&world.api.pool).await.unwrap();
        assert_eq!(get().await.1["read"], true, "read as it came, and it is the original");
        current(edit).execute(&world.api.pool).await.unwrap();
        assert_eq!(get().await, (StatusCode::OK, json!({})), "read in another version");
        sqlx::query("UPDATE asset_ocr SET version_id = $1, text = 'Rua', regions = $2 WHERE asset_id = $3")
            .bind(edit)
            .bind(json!([{"text": "Rua", "x": 0.0, "y": 0.0, "width": 1.0, "height": 0.5}]))
            .bind(picture)
            .execute(&world.api.pool)
            .await
            .unwrap();
        let (_, answer) = get().await;
        assert_eq!(
            (&answer["text"], answer["regions"].as_array().map(Vec::len)),
            (&json!("Rua"), Some(1))
        );
    }
}
