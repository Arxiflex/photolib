//! Model downloads for devices (photolib-design docs/09 §12.2): `GET /models/{name}/{file}` streams a file of a
//! registry model that devices run, as `photolibd models fetch` installed it, to any signed-in account or API key,
//! with HTTP ranges so that a broken download resumes. Anything else gets an empty 404, as media does: a file only
//! the server runs, or a bring-your-own model, never leaves it.

use std::{io::SeekFrom, path::PathBuf, sync::Arc};

use axum::{
    Router,
    body::Body,
    extract::{Path as UrlPath, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
    routing::get,
};
use photolib_authz::Principal;
use photolib_models::{REGISTRY, Target};
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio_util::io::ReaderStream;

use crate::{media, rpc::Users};

/// The model endpoint of one `api` process.
pub struct Models {
    root: PathBuf,
    users: Arc<Users>,
}

/// `GET /models/{name}/{file}`.
pub fn router(models: Arc<Models>) -> Router {
    Router::new()
        .route("/models/{name}/{file}", get(fetch))
        .with_state(models)
}

async fn fetch(
    State(models): State<Arc<Models>>,
    UrlPath((name, file)): UrlPath<(String, String)>,
    headers: HeaderMap,
) -> Response {
    media::private(models.fetch(&name, &file, &headers).await)
}

impl Models {
    /// Serves the models installed under `root`, `ml.models_dir`.
    pub fn new(root: PathBuf, users: Arc<Users>) -> Self {
        Self { root, users }
    }

    async fn fetch(&self, name: &str, file: &str, headers: &HeaderMap) -> Result<Response, StatusCode> {
        let who = self.users.principal(headers).await.map_err(internal)?;
        if !matches!(who, Some(Principal::User(..) | Principal::Key(..))) {
            return Err(StatusCode::NOT_FOUND);
        }
        // Only the registry's names, plain file names (`Model::problems`), reach the path.
        let model = REGISTRY.iter().find(|m| m.name() == name);
        let wanted = (model.into_iter().flat_map(|m| &m.files))
            .find(|f| f.name == file && f.targets.iter().any(|t| *t != Target::Server))
            .ok_or(StatusCode::NOT_FOUND)?;
        let path = self.root.join(name).join(&wanted.name);
        let mut opened = (tokio::fs::File::open(path).await).map_err(|_| StatusCode::NOT_FOUND)?;
        let size = opened.metadata().await.map_err(internal)?.len();
        // A file of another size is not the registry's: never one that a device could verify.
        if size != wanted.size {
            return Err(StatusCode::NOT_FOUND);
        }
        let (status, part, range) = match media::range(headers, size) {
            Err(()) => {
                let all = [(header::CONTENT_RANGE, format!("bytes */{size}"))];
                return Ok((StatusCode::RANGE_NOT_SATISFIABLE, all).into_response());
            }
            Ok(None) => (StatusCode::OK, 0..size, None),
            Ok(Some(part)) => {
                let range = format!("bytes {}-{}/{size}", part.start, part.end.saturating_sub(1));
                (
                    StatusCode::PARTIAL_CONTENT,
                    part,
                    Some([(header::CONTENT_RANGE, range)]),
                )
            }
        };
        opened.seek(SeekFrom::Start(part.start)).await.map_err(internal)?;
        let length = part.end.saturating_sub(part.start);
        let shown = [
            (header::ETAG, format!("\"{}\"", wanted.sha256)),
            (header::CACHE_CONTROL, "private".into()),
            (header::ACCEPT_RANGES, "bytes".into()),
            (header::CONTENT_TYPE, "application/octet-stream".into()),
            (header::CONTENT_LENGTH, length.to_string()),
        ];
        let body = Body::from_stream(ReaderStream::new(opened.take(length)));
        Ok((status, shown, range, body).into_response())
    }
}

fn internal(error: impl std::fmt::Display) -> StatusCode {
    tracing::error!(%error, "a model request failed");
    StatusCode::INTERNAL_SERVER_ERROR
}
