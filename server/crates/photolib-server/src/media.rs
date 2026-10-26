//! Media delivery (photolib-design docs/08 §4.5, ADR-0022 point 5, ADR-0084): `GET /media/{asset}/{role}` streams a
//! file of an asset from whichever store holds it, with HTTP ranges and private cache headers, to a session, an API
//! key or a signed URL, which `POST` on the same path makes. Anything else gets an empty 404, so no path is worth
//! guessing, and no URL ever points at a store. `GET /media/random/{role}` serves a random photo for frames and kiosks
//! (ADR-0263). Videos stream from `/media/{asset}/hls/` (`hls`), and a viewer's place in one is kept with
//! `PUT /media/{asset}/position`.

use std::{
    ops::Range,
    sync::Arc,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::{
    Json, Router,
    body::{Body, Bytes},
    extract::{Path as UrlPath, State},
    http::{HeaderMap, HeaderName, HeaderValue, StatusCode, Uri, header},
    response::{IntoResponse, Response},
    routing::{get, put},
};
use futures::{StreamExt, stream};
use hmac::{Hmac, Mac};
use photolib_authz::{Action, Kind, Principal, Resource, can, scope};
use photolib_storage::journal::Journal;
use sha2::Sha256;
use sqlx::{PgPool, QueryBuilder};
use uuid::Uuid;

use crate::{
    hls::{Hls, Video},
    rpc::Users,
};

/// How long a signed URL works, in seconds.
const TTL: u64 = 3600;
/// How much one read from a store returns while a file streams.
const CHUNK: u64 = 1 << 20;
/// The roles that showing an asset needs; its other files are downloads.
const RENDITIONS: [&str; 3] = ["thumb_s", "thumb_m", "preview"];

/// The media endpoints of one `api` process.
pub struct Media {
    pool: PgPool,
    journal: Arc<Journal>,
    users: Arc<Users>,
    /// Signs URLs; derived from the server key, so that every `api` process shares it.
    key: [u8; 32],
    hls: Option<Arc<Hls>>,
}

/// A file as it is served: `size` bytes of `key` from `offset`.
struct File {
    storage: String,
    key: String,
    mime: String,
    size: i64,
    offset: i64,
    hash: Vec<u8>,
}

/// How a file of an asset without a media kind goes out: as a download, never as something to show (ADR-0066).
const DOWNLOAD: &str = "application/octet-stream";

pub fn router(media: Arc<Media>) -> Router {
    Router::new()
        .route("/media/{asset}/{role}", get(fetch).post(sign))
        .route("/media/{asset}/hls/{file}", get(playlist))
        .route("/media/{asset}/hls/{rung}/{version}/{file}", get(segment))
        .route("/media/{asset}/position", put(position))
        .with_state(media)
}

async fn playlist(
    State(media): State<Arc<Media>>,
    UrlPath((asset, file)): UrlPath<(String, String)>,
    uri: Uri,
    headers: HeaderMap,
) -> Response {
    private(media.playlist(&asset, &file, &uri, &headers).await)
}

async fn segment(
    State(media): State<Arc<Media>>,
    UrlPath((asset, rung, version, file)): UrlPath<(String, String, String, String)>,
    uri: Uri,
    headers: HeaderMap,
) -> Response {
    let answer = media.segment(&asset, &rung, &version, &file, &uri, &headers).await;
    // Not made in time: the player asks again, never waits on a silent connection (docs/08 §5.4).
    let busy = answer.as_ref().err() == Some(&StatusCode::SERVICE_UNAVAILABLE);
    let mut response = private(answer);
    if busy {
        response.headers_mut().insert(header::RETRY_AFTER, HeaderValue::from(2));
    }
    response
}

async fn position(
    State(media): State<Arc<Media>>,
    UrlPath(asset): UrlPath<String>,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    private(media.position(&asset, &uri, &headers, &body).await)
}

async fn fetch(
    State(media): State<Arc<Media>>,
    UrlPath((asset, role)): UrlPath<(String, String)>,
    uri: Uri,
    headers: HeaderMap,
) -> Response {
    private(match asset.as_str() {
        "random" => media.random(&role, &headers).await,
        _ => media.fetch(&asset, &role, &uri, &headers).await,
    })
}

async fn sign(
    State(media): State<Arc<Media>>,
    UrlPath((asset, role)): UrlPath<(String, String)>,
    headers: HeaderMap,
) -> Response {
    private(media.sign(&asset, &role, &headers).await)
}

/// Only the client may keep a media response; a refusal says nothing and is kept by nobody.
pub(crate) fn private(answer: Result<Response, StatusCode>) -> Response {
    let mut response = answer.unwrap_or_else(|status| status.into_response());
    let headers = response.headers_mut();
    headers
        .entry(header::CACHE_CONTROL)
        .or_insert(HeaderValue::from_static("private, no-store"));
    response
}

impl Media {
    pub fn new(pool: PgPool, journal: Arc<Journal>, users: Arc<Users>, key: [u8; 32]) -> Media {
        Media {
            pool,
            journal,
            users,
            key,
            hls: None,
        }
    }

    /// Streams videos through `hls` too.
    #[must_use]
    pub fn with_hls(self, hls: Arc<Hls>) -> Self {
        Self { hls: Some(hls), ..self }
    }

    /// The URL of `role` of `asset` that `user` may fetch without a credential until `expires` (Unix seconds):
    /// the expiry, the user and 16 bytes of an HMAC over them, the asset and the role, in hex.
    pub fn url(&self, asset: Uuid, role: &str, user: Uuid, expires: u64) -> String {
        format!("/media/{asset}/{role}?t={}", self.token(asset, role, user, expires))
    }

    fn token(&self, asset: Uuid, role: &str, user: Uuid, expires: u64) -> String {
        let tag = self.mac(asset, role, user, expires).finalize().into_bytes();
        hex(&[&expires.to_be_bytes()[..], user.as_bytes(), &tag[..16]].concat())
    }

    fn mac(&self, asset: Uuid, role: &str, user: Uuid, expires: u64) -> Hmac<Sha256> {
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.key).expect("HMAC takes any key");
        // The role, the only part of variable length, goes last.
        for part in [
            &asset.as_bytes()[..],
            &expires.to_be_bytes(),
            user.as_bytes(),
            role.as_bytes(),
        ] {
            mac.update(part);
        }
        mac
    }

    /// The account of a signed URL that is this one's, unexpired and untouched.
    fn signer(&self, asset: Uuid, role: &str, token: &str) -> Option<Uuid> {
        let token: Vec<u8> = (0..token.len())
            .step_by(2)
            .map(|at| u8::from_str_radix(token.get(at..at + 2)?, 16).ok())
            .collect::<Option<_>>()?;
        let (expires, rest) = token.split_at_checked(8)?;
        let (user, tag) = rest.split_at_checked(16)?;
        let expires = u64::from_be_bytes(expires.try_into().ok()?);
        let user = Uuid::from_slice(user).ok()?;
        let mac = self.mac(asset, role, user, expires);
        (now() < expires && tag.len() == 16 && mac.verify_truncated_left(tag).is_ok()).then_some(user)
    }

    /// Who asks for `role` of `asset`: the signer of a signed URL for it, else the caller.
    async fn who(&self, asset: Uuid, role: &str, uri: &Uri, headers: &HeaderMap) -> Result<Principal, StatusCode> {
        Ok(match param(uri, "t") {
            Some(token) => match self.signer(asset, role, token) {
                Some(user) => self.users.account(user).await.map_err(internal)?,
                None => Principal::Anonymous,
            },
            // A session that must enrol a second factor sees no media (ADR-0088).
            None => (self.users.principal(headers).await.map_err(internal)?).unwrap_or(Principal::Anonymous),
        })
    }

    async fn fetch(&self, asset: &str, role: &str, uri: &Uri, headers: &HeaderMap) -> Result<Response, StatusCode> {
        let asset: Uuid = asset.parse().map_err(|_| StatusCode::NOT_FOUND)?;
        let who = self.who(asset, role, uri, headers).await?;
        let file = self.file(who, asset, role).await?;
        let (size, hash) = (file.size as u64, hex(&file.hash));
        let cache = match param(uri, "h") == Some(&hash) {
            true => "private, max-age=31536000, immutable",
            false => "private, no-cache",
        };
        let etag = format!("\"{hash}\"");
        let unchanged = headers.get(header::IF_NONE_MATCH).is_some_and(|tag| *tag == etag);
        let shown = [
            (header::ETAG, etag),
            (header::CACHE_CONTROL, cache.into()),
            (header::ACCEPT_RANGES, "bytes".into()),
            (header::CONTENT_TYPE, file.mime.clone()),
        ];
        let mut response = match range(headers, size) {
            _ if unchanged => (StatusCode::NOT_MODIFIED, shown).into_response(),
            Err(()) => {
                let all = [(header::CONTENT_RANGE, format!("bytes */{size}"))];
                (StatusCode::RANGE_NOT_SATISFIABLE, all).into_response()
            }
            Ok(None) => (StatusCode::OK, shown, self.body(&file, 0..size).await?).into_response(),
            Ok(Some(part)) => {
                let range = [(
                    header::CONTENT_RANGE,
                    format!("bytes {}-{}/{size}", part.start, part.end - 1),
                )];
                (StatusCode::PARTIAL_CONTENT, shown, range, self.body(&file, part).await?).into_response()
            }
        };
        if file.mime == DOWNLOAD {
            let attachment = HeaderValue::from_static("attachment");
            response.headers_mut().insert(header::CONTENT_DISPOSITION, attachment);
        }
        Ok(response)
    }

    /// `role` of a random photo the caller may view in a standard library, neither locked, archived nor trashed, named
    /// in `Photolib-Asset`; each request draws again, so nothing keeps the answer.
    async fn random(&self, role: &str, headers: &HeaderMap) -> Result<Response, StatusCode> {
        if !RENDITIONS.contains(&role) {
            return Err(StatusCode::NOT_FOUND);
        }
        let who = (self.users.principal(headers).await.map_err(internal)?).unwrap_or(Principal::Anonymous);
        let mut q = QueryBuilder::new("SELECT s.id FROM (");
        scope(who, Action::View, Kind::Asset, &mut q);
        q.push(
            ") s JOIN assets a ON a.id = s.id AND a.media_kind = 'image' AND NOT a.locked AND NOT a.archived
               AND a.trashed_at IS NULL
             JOIN libraries l ON l.id = a.library_id AND l.privacy = 'standard'
             WHERE EXISTS (SELECT FROM asset_files f WHERE f.asset_id = a.id AND f.state = 'present' AND f.role = ",
        );
        q.push_bind(role).push(") ORDER BY random() LIMIT 1");
        let asset: Option<Uuid> = q
            .build_query_scalar()
            .fetch_optional(&self.pool)
            .await
            .map_err(internal)?;
        let asset = asset.ok_or(StatusCode::NOT_FOUND)?;
        let file = self.file(who, asset, role).await?;
        let size = u64::try_from(file.size).map_err(internal)?;
        let shown = [
            (header::CONTENT_TYPE, file.mime.clone()),
            (header::CACHE_CONTROL, "private, no-store".into()),
            (HeaderName::from_static("photolib-asset"), asset.to_string()),
        ];
        Ok((StatusCode::OK, shown, self.body(&file, 0..size).await?).into_response())
    }

    async fn sign(&self, asset: &str, role: &str, headers: &HeaderMap) -> Result<Response, StatusCode> {
        let asset: Uuid = asset.parse().map_err(|_| StatusCode::NOT_FOUND)?;
        let who = (self.users.principal(headers).await.map_err(internal)?).unwrap_or(Principal::Anonymous);
        let (Principal::User(user, _) | Principal::Key(user, ..)) = who else {
            return Err(StatusCode::NOT_FOUND);
        };
        let expires = now() + TTL;
        let url = if role == "hls" {
            self.ladder(who, asset).await?;
            format!(
                "/media/{asset}/hls/master.m3u8?t={}",
                self.token(asset, role, user, expires)
            )
        } else {
            self.file(who, asset, role).await?;
            self.url(asset, role, user, expires)
        };
        Ok(Json(serde_json::json!({ "url": url, "expires_at": expires })).into_response())
    }

    /// The ladder and `asset`'s video, which `who` may view, and who that is.
    async fn ladder(&self, who: Principal, asset: Uuid) -> Result<(Arc<Hls>, Video, Uuid), StatusCode> {
        let hls = self.hls.clone().ok_or(StatusCode::NOT_FOUND)?;
        let (Principal::User(user, _) | Principal::Key(user, ..)) = who else {
            return Err(StatusCode::NOT_FOUND);
        };
        if !can(&self.pool, who, Action::View, Resource::Asset(asset))
            .await
            .map_err(internal)?
        {
            return Err(StatusCode::NOT_FOUND);
        }
        let video = hls.video(asset).await.map_err(internal)?.ok_or(StatusCode::NOT_FOUND)?;
        Ok((hls, video, user))
    }

    /// The ladder and the video of a request to `/media/{asset}/hls/` or its position.
    async fn streamed(
        &self,
        asset: &str,
        uri: &Uri,
        headers: &HeaderMap,
    ) -> Result<(Arc<Hls>, Video, Uuid), StatusCode> {
        let asset: Uuid = asset.parse().map_err(|_| StatusCode::NOT_FOUND)?;
        let who = self.who(asset, "hls", uri, headers).await?;
        self.ladder(who, asset).await
    }

    /// Where `user` stopped watching `video`, unless at its very start or within its last 5 s (docs/08 §5.8).
    async fn resume(&self, user: Uuid, video: &Video) -> Result<Option<f64>, StatusCode> {
        let ms: Option<Option<i64>> = sqlx::query_scalar(
            "SELECT playback_position_ms FROM asset_user_state WHERE user_id = $1 AND asset_id = $2",
        )
        .bind(user)
        .bind(video.asset)
        .fetch_optional(&self.pool)
        .await
        .map_err(internal)?;
        let seconds =
            (ms.flatten().and_then(|ms| u64::try_from(ms).ok())).map(|ms| Duration::from_millis(ms).as_secs_f64());
        Ok(seconds.filter(|s| *s >= 1.0 && *s < video.source.duration - 5.0))
    }

    /// The master playlist (`master.m3u8`, only the lowest rung with `saver=1`) or a rung's, whose URIs are signed
    /// for the viewer for at least three times the video's length.
    async fn playlist(&self, asset: &str, file: &str, uri: &Uri, headers: &HeaderMap) -> Result<Response, StatusCode> {
        let (hls, video, user) = self.streamed(asset, uri, headers).await?;
        let start = self.resume(user, &video).await?;
        let length = Duration::try_from_secs_f64(3.0 * video.source.duration).map_or(0, |d| d.as_secs());
        let expires = now().saturating_add(TTL.max(length));
        let query = format!("?t={}", self.token(video.asset, "hls", user, expires));
        let text = match file.strip_suffix(".m3u8") {
            Some("master") => {
                let (saver, hdr) = (param(uri, "saver") == Some("1"), param(uri, "hdr") == Some("1"));
                hls.master(&video, saver, hdr, start, &query).await
            }
            Some(rung) => hls.playlist(&video, rung, start, &query).await,
            None => None,
        };
        let mime = [(header::CONTENT_TYPE, "application/vnd.apple.mpegurl")];
        Ok((mime, text.ok_or(StatusCode::NOT_FOUND)?).into_response())
    }

    /// A rung's init segment (`init.mp4`) or segment (`<n>.m4s`), whose path changes with what it is made of.
    async fn segment(
        &self,
        asset: &str,
        rung: &str,
        version: &str,
        file: &str,
        uri: &Uri,
        headers: &HeaderMap,
    ) -> Result<Response, StatusCode> {
        let (hls, video, user) = self.streamed(asset, uri, headers).await?;
        let bytes = match file.strip_suffix(".m4s") {
            _ if file == "init.mp4" => {
                let start = self.resume(user, &video).await?.unwrap_or(0.0);
                Body::from(hls.init(&video, rung, version, start).await?)
            }
            Some(n) => {
                hls.segment(&video, rung, version, n.parse().map_err(|_| StatusCode::NOT_FOUND)?)
                    .await?
            }
            None => return Err(StatusCode::NOT_FOUND),
        };
        let kept = [
            (header::CONTENT_TYPE, "video/mp4"),
            (header::CACHE_CONTROL, "private, max-age=31536000, immutable"),
        ];
        Ok((kept, bytes).into_response())
    }

    /// Keeps where the viewer is in a video, `{"position_ms": <n>}`, which every device of theirs syncs.
    async fn position(&self, asset: &str, uri: &Uri, headers: &HeaderMap, body: &[u8]) -> Result<Response, StatusCode> {
        #[derive(serde::Deserialize)]
        struct Position {
            position_ms: u32,
        }
        let (_, video, user) = self.streamed(asset, uri, headers).await?;
        let Position { position_ms } = serde_json::from_slice(body).map_err(|_| StatusCode::BAD_REQUEST)?;
        sqlx::query(
            "INSERT INTO asset_user_state (user_id, asset_id, playback_position_ms) VALUES ($1, $2, $3)
             ON CONFLICT (user_id, asset_id) DO UPDATE SET playback_position_ms = EXCLUDED.playback_position_ms",
        )
        .bind(user)
        .bind(video.asset)
        .bind(i64::from(position_ms))
        .execute(&self.pool)
        .await
        .map_err(internal)?;
        Ok(StatusCode::NO_CONTENT.into_response())
    }

    /// The file of `role` of `asset`, if `who` may see it (renditions) or download it (anything else).
    async fn file(&self, who: Principal, asset: Uuid, role: &str) -> Result<File, StatusCode> {
        let action = if RENDITIONS.contains(&role) {
            Action::View
        } else {
            Action::Download
        };
        if !can(&self.pool, who, action, Resource::Asset(asset))
            .await
            .map_err(internal)?
        {
            return Err(StatusCode::NOT_FOUND);
        }
        let row: Option<(String, String, String, i64, i64, Vec<u8>)> = sqlx::query_as(
            "SELECT f.storage, f.key, CASE WHEN a.media_kind IS NOT NULL THEN coalesce(f.mime, $3) ELSE $3 END, f.size,
               coalesce(f.byte_offset, 0), f.content_hash
             FROM asset_files f JOIN assets a ON a.id = f.asset_id
             WHERE f.asset_id = $1 AND f.role = $2 AND f.state = 'present' AND f.size IS NOT NULL
               AND f.content_hash IS NOT NULL
               -- The export is of a version, and only the current one's goes out as the edited picture.
               AND (f.role <> 'edit_export' OR f.render_spec ->> 'version_id' = a.current_version_id::text)
             ORDER BY f.created_at DESC, f.id DESC LIMIT 1",
        )
        .bind(asset)
        .bind(role)
        .bind(DOWNLOAD)
        .fetch_optional(&self.pool)
        .await
        .map_err(internal)?;
        let (storage, key, mime, size, offset, hash) = row.ok_or(StatusCode::NOT_FOUND)?;
        Ok(File {
            storage,
            key,
            mime,
            size,
            offset,
            hash,
        })
    }

    /// `part` of `file`, read from its store in chunks. The first is read before the answer, so that a store that
    /// fails gets a 503 rather than a cut body.
    async fn body(&self, file: &File, part: Range<u64>) -> Result<impl IntoResponse, StatusCode> {
        let store = self
            .journal
            .stores()
            .get(&file.storage)
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?
            .clone();
        let (key, base, end) = (file.key.clone(), file.offset as u64, part.end);
        let length = HeaderValue::from(part.end - part.start);
        let read = move |at: u64| {
            let (store, key) = (store.clone(), key.clone());
            async move {
                let span = base + at..base + (at + CHUNK).min(end);
                store.get(&key, Some(span)).await.map(Bytes::from)
            }
        };
        if part.is_empty() {
            return Ok(([(header::CONTENT_LENGTH, length)], Body::empty()));
        }
        let first = read(part.start).await.map_err(|error| {
            tracing::warn!(%error, "a media file cannot be read");
            StatusCode::SERVICE_UNAVAILABLE
        })?;
        let rest = stream::unfold(part.start + CHUNK, move |at| {
            let read = read.clone();
            async move { (at < end).then_some((read(at).await, at + CHUNK)) }
        });
        Ok((
            [(header::CONTENT_LENGTH, length)],
            Body::from_stream(stream::once(async { Ok(first) }).chain(rest)),
        ))
    }
}

/// The single byte range a request asks for: none for the whole file (no `Range`, or not one byte range), an error
/// when it starts at or beyond the end.
pub(crate) fn range(headers: &HeaderMap, size: u64) -> Result<Option<Range<u64>>, ()> {
    let asked = headers.get(header::RANGE).and_then(|v| v.to_str().ok());
    let Some((from, to)) = asked.and_then(|v| v.strip_prefix("bytes=")?.split_once('-')) else {
        return Ok(None);
    };
    let part = match (from.trim().parse::<u64>(), to.trim().parse::<u64>()) {
        (Ok(from), Ok(to)) if from <= to => from..to.saturating_add(1).min(size),
        (Ok(from), Err(_)) if to.trim().is_empty() => from..size,
        (Err(_), Ok(suffix)) if from.trim().is_empty() => size.saturating_sub(suffix)..size,
        _ => return Ok(None),
    };
    if part.start >= size { Err(()) } else { Ok(Some(part)) }
}

fn param<'a>(uri: &'a Uri, name: &str) -> Option<&'a str> {
    (uri.query().unwrap_or_default().split('&')).find_map(|pair| pair.strip_prefix(name)?.strip_prefix('='))
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn internal(error: impl std::fmt::Display) -> StatusCode {
    tracing::error!(%error, "a media request failed");
    StatusCode::INTERNAL_SERVER_ERROR
}
