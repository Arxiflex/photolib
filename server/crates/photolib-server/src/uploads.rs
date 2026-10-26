//! Resumable uploads (ADR-0061): the IETF resumable upload protocol (draft-ietf-httpbis-resumable-upload-13) on
//! `/upload`. Appends are staged in `<work_dir>/uploads/<id>` and fsynced and counted before they are acknowledged.
#![allow(
    clippy::result_large_err,
    reason = "a refusal is the response itself, built at most once per request"
)]

use std::{
    collections::HashMap,
    io,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    Router,
    body::Body,
    extract::{Path as UrlPath, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{head, post},
};
use base64::{Engine, engine::general_purpose::STANDARD};
use connectrpc::{ConnectError, ErrorCode};
use futures::StreamExt;
use photolib_authz::{Action, Capability, Principal, Resource, Role, can};
use photolib_models::{REGISTRY, Task};
use photolib_storage::{Hash, journal::Journal};
use sqlx::{PgConnection, PgPool, Row};
use tokio::io::{AsyncSeekExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    account_keys, dedup, ingest, library,
    library::template::numbered,
    rpc::{ApiError, Users},
};

/// The largest append clients are told to send: through Cloudflare's 100 MB request cap (design 16 §2).
const MAX_APPEND: u64 = 32 << 20;
/// An incomplete upload expires this long after its last append (design 05 §8).
const MAX_AGE_SECS: i64 = 24 * 3600;

const COMPLETE: &str = "upload-complete";
const OFFSET: &str = "upload-offset";
const LENGTH: &str = "upload-length";
const LIMIT: &str = "upload-limit";
const LIBRARY: &str = "photolib-library";
const HASH: &str = "photolib-hash";
const PATH: &str = "photolib-path";
const ML_MODEL: &str = "photolib-ml-model";
const ML_RUNTIME: &str = "photolib-ml-runtime";
const ML_VECTOR: &str = "photolib-ml-vector";

/// The upload endpoints of one `api` process.
pub struct Uploads {
    pool: PgPool,
    journal: Arc<Journal>,
    users: Arc<Users>,
    staging: PathBuf,
    disks: Disks,
    /// The store of the libraries made for uploads (`placement.libraries`).
    libraries: String,
    /// Held while a destination is looked for, so that uploads waiting to make one hold no database connection.
    destinations: tokio::sync::Mutex<()>,
    slots: Mutex<HashMap<Uuid, Arc<Slot>>>,
}

/// The size of a directory's filesystem and the space photolibd may still use there, in bytes.
pub type Space = dyn Fn(&Path) -> io::Result<(u64, u64)> + Send + Sync;

/// The filesystems uploads fill besides `work_dir`'s, and how full a filesystem is.
pub struct Disks {
    /// `data_dir`, the local store's directory.
    pub data_dir: PathBuf,
    /// `database.data_dir`, when set.
    pub database: Option<PathBuf>,
    /// `storage::space`, but in tests.
    pub space: Arc<Space>,
}

/// Serialises the requests to one upload: a new request stops the one in flight (draft §4.6), which keeps what it
/// received, and waits for it. Holds the hash of the bytes received so far.
#[derive(Default)]
struct Slot {
    hashed: tokio::sync::Mutex<Option<(u64, blake3::Hasher)>>,
    current: Mutex<CancellationToken>,
}

/// A vector a device computed for its upload (design 09 §3.2): the model's `id@revision` and the vector's bytes, half
/// floats.
type Handoff = (String, Vec<u8>);

/// What the database knows about an upload.
struct Upload {
    owner: Uuid,
    library: Uuid,
    length: u64,
    hash: Hash,
    received: u64,
    complete: bool,
    max_age: i64,
    floor: Floor,
}

/// The instance's free-disk floor, `min_free_disk_percent` and `min_free_disk_gb`, and the store of a library.
type Floor = (i32, i32, Option<String>);
const FLOOR: &str = "SELECT min_free_disk_percent, min_free_disk_gb, (SELECT store FROM libraries WHERE id = $1)
    FROM instance_settings";

type Answer = Result<Response, Response>;

pub fn router(uploads: Arc<Uploads>) -> Router {
    Router::new()
        .route("/upload", post(create).options(limits))
        .route("/upload/{id}", head(offset).patch(append).delete(cancel))
        .with_state(uploads)
}

async fn create(State(uploads): State<Arc<Uploads>>, request: Request) -> Answer {
    detach(async move { uploads.create(request).await }).await
}

/// What a client may discover before it creates an upload (draft §4.1.4).
async fn limits() -> Response {
    let limit = format!("max-append-size={MAX_APPEND}, max-age={MAX_AGE_SECS}");
    let limit = HeaderValue::try_from(limit).expect("a limit is ASCII");
    (StatusCode::NO_CONTENT, [(LIMIT, limit)]).into_response()
}

async fn offset(State(up): State<Arc<Uploads>>, UrlPath(id): UrlPath<Uuid>, h: HeaderMap) -> Answer {
    up.offset(id, &h).await
}

async fn append(State(up): State<Arc<Uploads>>, UrlPath(id): UrlPath<Uuid>, r: Request) -> Answer {
    detach(async move { up.append(id, r).await }).await
}

async fn cancel(State(up): State<Arc<Uploads>>, UrlPath(id): UrlPath<Uuid>, h: HeaderMap) -> Answer {
    detach(async move { up.cancel(id, &h).await }).await
}

/// Runs a request to its end even when its client goes away, which would drop it at any await: what arrived is
/// recorded, and a write to the store that started finishes rather than leaving the upload half complete.
async fn detach(request: impl Future<Output = Answer> + Send + 'static) -> Answer {
    tokio::spawn(request).await.unwrap_or_else(|error| Err(internal(error)))
}

/// How the content of a request ended.
enum Ended {
    Whole,
    /// The connection broke or the next request took over.
    Cut,
    /// It went past the upload's length; nothing past it was kept.
    TooLong,
}

impl Uploads {
    pub fn new(
        pool: PgPool,
        journal: Arc<Journal>,
        users: Arc<Users>,
        staging: &Path,
        disks: Disks,
        libraries: &str,
    ) -> io::Result<Uploads> {
        std::fs::create_dir_all(staging)?;
        Ok(Uploads {
            pool,
            journal,
            users,
            staging: staging.to_owned(),
            disks,
            libraries: libraries.into(),
            destinations: tokio::sync::Mutex::default(),
            slots: Mutex::default(),
        })
    }

    /// Expires abandoned uploads now and every `period` until `shutdown`.
    pub async fn expire_every(self: Arc<Self>, period: Duration, shutdown: CancellationToken) {
        loop {
            match self.expire().await {
                Ok(0) => {}
                Ok(expired) => tracing::info!(expired, "abandoned uploads expired"),
                Err(error) => tracing::warn!(%error, "abandoned uploads could not expire"),
            }
            tokio::select! {
                () = shutdown.cancelled() => return,
                () = tokio::time::sleep(period) => {}
            }
        }
    }

    /// Deletes the incomplete uploads whose time is up and staged bytes that belong to no upload; returns how many
    /// uploads expired.
    pub async fn expire(&self) -> Result<usize, sqlx::Error> {
        let expired: Vec<Uuid> =
            sqlx::query_scalar("DELETE FROM uploads WHERE completed_at IS NULL AND expires_at <= now() RETURNING id")
                .fetch_all(&self.pool)
                .await?;
        // An upload's row is written before its file, so a file without a row is left over.
        let staged: Vec<Uuid> = std::fs::read_dir(&self.staging)
            .map_err(sqlx::Error::Io)?
            .filter_map(|entry| entry.ok()?.file_name().to_str()?.parse().ok())
            .collect();
        let kept: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM uploads WHERE id = ANY($1)")
            .bind(&staged)
            .fetch_all(&self.pool)
            .await?;
        for id in staged.iter().filter(|id| !kept.contains(id)) {
            self.release(*id);
            if let Err(error) = std::fs::remove_file(self.staged(*id)) {
                tracing::warn!(%error, upload = %id, "cannot delete staged bytes");
            }
        }
        Ok(expired.len())
    }

    fn staged(&self, id: Uuid) -> PathBuf {
        self.staging.join(id.to_string())
    }

    async fn create(&self, request: Request) -> Answer {
        let headers = request.headers();
        let who = self.signed_in(headers).await?;
        let (Principal::User(owner, _) | Principal::Key(owner, ..)) = who else {
            return Err(internal("a signed-in principal is not a user"));
        };
        let complete = flag(headers, COMPLETE)?;
        let library = if headers.contains_key(LIBRARY) {
            parsed::<Uuid>(headers, LIBRARY)?
        } else {
            self.destination(who, owner).await?
        };
        let hash = parsed::<Hash>(headers, HASH)?;
        let length = match integer(headers, LENGTH)? {
            Some(length) => length,
            None if complete => integer(headers, header::CONTENT_LENGTH.as_str())?.ok_or_else(|| invalid(LENGTH))?,
            None => return Err(invalid(LENGTH)),
        };
        self.allow(who, Resource::Library(library)).await?;
        self.recoverable(owner, library).await?;
        let path = source_path(headers)?;
        let mut handoff = handoff(headers).unwrap_or_else(dropped);
        // A private library's devices hand off through its sealed metadata; the server keeps nothing of its files.
        if handoff.is_some() && self.private(library).await? {
            handoff = dropped("a private library");
        }
        let content = integer(headers, header::CONTENT_LENGTH.as_str())?;
        let id = Uuid::now_v7();
        self.reserve(id, owner, library, length, hash, path).await?;
        if let Some((model, vector)) = handoff {
            sqlx::query("UPDATE uploads SET embedding_model = $2, embedding = $3 WHERE id = $1")
                .bind(id)
                .bind(model)
                .bind(vector)
                .execute(&self.pool)
                .await
                .map_err(internal)?;
        }
        tokio::fs::File::create_new(self.staged(id)).await.map_err(internal)?;
        let answer = self.write(id, 0, complete, (None, content), request.into_body()).await;
        let (Ok(mut response) | Err(mut response)) = answer;
        if response.status() == StatusCode::NO_CONTENT {
            *response.status_mut() = StatusCode::CREATED;
        }
        let location = HeaderValue::try_from(format!("upload/{id}")).map_err(internal)?;
        response.headers_mut().insert(header::LOCATION, location);
        Ok(response)
    }

    /// Where `owner`'s uploads go without a library (design 07 §2): their upload target, else their first standard
    /// managed library, else one made now on `placement.libraries`, once however many uploads ask at a time (ADR-0226).
    async fn destination(&self, who: Principal, owner: Uuid) -> Result<Uuid, Response> {
        const FIND: &str = "SELECT id FROM libraries WHERE owner_id = $1 AND access = 'rw' AND privacy = 'standard' \
                            AND (is_upload_target OR kind = 'managed') ORDER BY is_upload_target DESC, id LIMIT 1";
        if let Principal::User(_, Role::Viewer) | Principal::Key(_, Role::Viewer, _) = who {
            return Err(refuse(ApiError::new(
                ErrorCode::PermissionDenied,
                "library.contribute_denied",
            )));
        }
        let find = async |conn: &mut PgConnection| {
            let found: Option<Uuid> = sqlx::query_scalar(FIND).bind(owner).fetch_optional(conn).await?;
            Ok::<_, sqlx::Error>(found)
        };
        if let Some(id) = find(&mut *self.pool.acquire().await.map_err(internal)?)
            .await
            .map_err(internal)?
        {
            return Ok(id);
        }
        let _one = self.destinations.lock().await;
        // Other API processes and the `library-create` job make theirs under the job's lock in the database.
        let mut tx = self.pool.begin().await.map_err(internal)?;
        sqlx::query("SELECT pg_advisory_xact_lock(hashtext($1))")
            .bind(library::CREATE)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        if let Some(id) = find(&mut tx).await.map_err(internal)? {
            return Ok(id);
        }
        let id = library::create(&self.pool, &self.journal, &self.libraries, owner, "Photos")
            .await
            .map_err(internal)?;
        tracing::info!(library = %id, owner = %owner, "a library was made for uploads");
        tx.commit().await.map_err(internal)?;
        Ok(id)
    }

    /// Records a new upload, its length counted against its owner's quota from now on.
    async fn reserve(
        &self,
        id: Uuid,
        owner: Uuid,
        library: Uuid,
        length: u64,
        hash: Hash,
        path: Option<String>,
    ) -> Result<(), Response> {
        let mut tx = self.pool.begin().await.map_err(internal)?;
        let floor = sqlx::query_as(FLOOR).bind(library).fetch_one(&mut *tx).await;
        self.room(&floor.map_err(internal)?)?;
        // Locks an owner with a quota, so that uploads created at once cannot exceed it together. Without one,
        // creations neither wait for each other nor add up the owner's files, which grow with every upload.
        let quota: Option<i64> =
            sqlx::query_scalar("SELECT quota_bytes FROM users WHERE id = $1 AND quota_bytes IS NOT NULL FOR UPDATE")
                .bind(owner)
                .fetch_optional(&mut *tx)
                .await
                .map_err(internal)?;
        if let Some(quota) = quota {
            let used: i64 = sqlx::query_scalar(
                "SELECT (SELECT coalesce(sum(file_size_total), 0) FROM assets WHERE owner_id = $1)::bigint \
                 + (SELECT coalesce(sum(length), 0) FROM uploads WHERE owner_id = $1)::bigint",
            )
            .bind(owner)
            .fetch_one(&mut *tx)
            .await
            .map_err(internal)?;
            if used.saturating_add(length as i64) > quota {
                let error = ApiError::new(ErrorCode::ResourceExhausted, "quota.exceeded");
                let mut response = connect(ConnectError::from(error).with_http_status(StatusCode::PAYLOAD_TOO_LARGE));
                let limit = format!("max-size={}", quota.saturating_sub(used).max(0));
                let limit = HeaderValue::try_from(limit).map_err(internal)?;
                response.headers_mut().insert(LIMIT, limit);
                return Err(response);
            }
        }
        sqlx::query(
            "INSERT INTO uploads (id, owner_id, library_id, length, hash, expires_at, path) \
             VALUES ($1, $2, $3, $4, $5, now() + make_interval(secs => $6), $7)",
        )
        .bind(id)
        .bind(owner)
        .bind(library)
        .bind(length as i64)
        .bind(hash.0.to_vec())
        .bind(MAX_AGE_SECS as f64)
        .bind(path)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        tx.commit().await.map_err(internal)
    }

    async fn offset(&self, id: Uuid, headers: &HeaderMap) -> Answer {
        self.admit(headers, Resource::Upload(id)).await?;
        let slot = self.slot(id);
        let _hashed = slot.take_over().await;
        let upload = self.upload(id).await?;
        let mut response = progress(StatusCode::NO_CONTENT, &upload);
        let headers = response.headers_mut();
        headers.insert(LENGTH, upload.length.into());
        headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
        Ok(response)
    }

    async fn append(&self, id: Uuid, request: Request) -> Answer {
        let headers = request.headers();
        self.admit(headers, Resource::Upload(id)).await?;
        if headers.get(header::CONTENT_TYPE).map(HeaderValue::as_bytes) != Some(b"application/partial-upload") {
            return Err(invalid("content-type"));
        }
        let offset = integer(headers, OFFSET)?.ok_or_else(|| invalid(OFFSET))?;
        let complete = flag(headers, COMPLETE)?;
        let length = integer(headers, LENGTH)?;
        let content = integer(headers, header::CONTENT_LENGTH.as_str())?;
        self.write(id, offset, complete, (length, content), request.into_body())
            .await
    }

    /// Appends `body` at `offset`, and completes the upload if asked to; `length` and `content` are the sizes the
    /// request announced.
    async fn write(
        &self,
        id: Uuid,
        offset: u64,
        complete: bool,
        (length, content): (Option<u64>, Option<u64>),
        body: Body,
    ) -> Answer {
        let slot = self.slot(id);
        let (mut hashed, token) = slot.take_over().await;
        let upload = self.upload(id).await?;
        if upload.complete {
            return match offset == upload.length {
                true => Ok(completed(id, &upload)),
                false => Err(mismatch(upload.length, true)),
            };
        }
        if offset != upload.received {
            return Err(mismatch(upload.received, false));
        }
        self.room(&upload.floor)?;
        let end = content.map(|content| offset + content);
        if length.is_some_and(|length| length != upload.length)
            || end.is_some_and(|end| end > upload.length || (complete && end != upload.length))
        {
            return Err(length_mismatch());
        }
        let (received, ended) = self.receive(id, &upload, body, &mut hashed, &token).await?;
        match ended {
            Ended::Cut => Err(mismatch(received, false)),
            Ended::TooLong => Err(length_mismatch()),
            Ended::Whole if complete && received != upload.length => Err(length_mismatch()),
            Ended::Whole if complete => {
                let (_, hasher) = hashed.as_ref().expect("receive leaves the hash");
                self.complete(id, &upload, hasher.finalize().into()).await
            }
            Ended::Whole => Ok(progress(StatusCode::NO_CONTENT, &Upload { received, ..upload })),
        }
    }

    /// Acknowledges an upload whose bytes have the announced hash once they are written to its library's store:
    /// fsynced on a filesystem, a verified PUT on an object store. The staged copy stays for ingest to read.
    async fn complete(&self, id: Uuid, upload: &Upload, hash: Hash) -> Answer {
        if hash != upload.hash {
            self.forget(id).await?;
            let error = ApiError::new(ErrorCode::InvalidArgument, "upload.hash_mismatch");
            let mut response = refuse(error.param("blake3", hash));
            let headers = response.headers_mut();
            headers.insert(COMPLETE, HeaderValue::from_static("?1"));
            return Err(response);
        }
        let (store, private, own): (String, bool, bool) =
            sqlx::query_as("SELECT store, privacy = 'private', owner_id = $2 FROM libraries WHERE id = $1")
                .bind(upload.library)
                .bind(upload.owner)
                .fetch_one(&self.pool)
                .await
                .map_err(internal)?;
        // Backed up into their own library, bytes that its owner's libraries hold already are linked, never stored
        // twice (ADR-0092), and put back for the files of theirs the scrub found damaged.
        if own && !private {
            let damaged = (dedup::damaged(&self.pool, upload.owner, &hash.0).await).map_err(internal)?;
            for (store, key) in &damaged {
                self.repair(id, store, key, hash).await?;
            }
            if !damaged.is_empty() || (dedup::held(&self.pool, upload.owner, &hash.0).await).map_err(internal)? {
                (dedup::hand_off(&self.pool, upload.owner, &hash.0, id).await).map_err(internal)?;
                self.forget(id).await?;
                return Ok(completed(id, upload));
            }
        }
        let key = format!("libraries/{}/uploads/{id}", upload.library);
        let staged = self.staged(id);
        let written = self.journal.put(&store, &key, &staged, hash).await;
        let written = written.map_err(unwritten)?;
        let mut tx = self.pool.begin().await.map_err(internal)?;
        written.switch(&mut tx).await.map_err(unwritten)?;
        sqlx::query("UPDATE uploads SET store = $2, key = $3, completed_at = now() WHERE id = $1")
            .bind(id)
            .bind(&store)
            .bind(&key)
            .execute(&mut *tx)
            .await
            .map_err(internal)?;
        // A private library's files are ciphertext the server never reads (photolib-design docs/03 §4.2).
        if !private {
            ingest::enqueue(&mut tx, &[id]).await.map_err(internal)?;
        }
        tx.commit().await.map_err(internal)?;
        if let Err(error) = written.finish().await {
            tracing::warn!(%error, "an upload's intent stays open until recovery closes it");
        }
        self.release(id);
        Ok(completed(id, upload))
    }

    /// Puts the bytes of upload `id`, which have `hash`, back for the damaged file `key` of `store`: at its key when
    /// the object is gone, else at the first free numbered key beside it, where its rows move as the purge deletes
    /// the damaged object. Its findings are resolved; a repair that another one beat leaves nothing behind.
    async fn repair(&self, id: Uuid, store: &str, key: &str, hash: Hash) -> Result<(), Response> {
        let (staged, mut n) = (self.staged(id), 1);
        let (fixed, op) = loop {
            let to = numbered(key, n);
            match self.journal.put(store, &to, &staged, hash).await {
                Err(photolib_storage::Error::Exists(_)) => n = n.saturating_add(1),
                put => break (to, put.map_err(unwritten)?),
            }
        };
        let mut tx = self.pool.begin().await.map_err(internal)?;
        if fixed != key {
            let moved = sqlx::query("UPDATE asset_files SET key = $3 WHERE storage = $1 AND key = $2")
                .bind(store)
                .bind(key)
                .bind(&fixed)
                .execute(&mut *tx)
                .await
                .map_err(internal)?;
            if moved.rows_affected() == 0 {
                drop(tx);
                return op.abandon().await.map_err(unwritten);
            }
            (self.journal.delete_after(&mut tx, store, key, Duration::ZERO).await).map_err(unwritten)?;
        }
        sqlx::query(
            "UPDATE integrity_findings SET resolved_at = now()
             WHERE store = $1 AND key = $2 AND library_id IS NULL AND resolved_at IS NULL",
        )
        .bind(store)
        .bind(key)
        .execute(&mut *tx)
        .await
        .map_err(internal)?;
        op.settle(&mut tx).await.map_err(unwritten)?;
        tx.commit().await.map_err(internal)
    }

    async fn cancel(&self, id: Uuid, headers: &HeaderMap) -> Answer {
        self.admit(headers, Resource::Upload(id)).await?;
        let slot = self.slot(id);
        let _hashed = slot.take_over().await;
        if self.upload(id).await?.complete {
            return Err(refuse(ApiError::new(ErrorCode::FailedPrecondition, "upload.complete")));
        }
        self.forget(id).await?;
        Ok(StatusCode::NO_CONTENT.into_response())
    }

    /// Deletes an upload that cannot complete, with its staged bytes.
    async fn forget(&self, id: Uuid) -> Result<(), Response> {
        sqlx::query("DELETE FROM uploads WHERE id = $1")
            .bind(id)
            .execute(&self.pool)
            .await
            .map_err(internal)?;
        self.release(id);
        match tokio::fs::remove_file(self.staged(id)).await {
            Err(error) if error.kind() != io::ErrorKind::NotFound => Err(internal(error)),
            _ => Ok(()),
        }
    }

    /// Writes `body` after the bytes received until it ends, breaks or the next request takes over, then fsyncs and
    /// records what arrived. Returns the new offset.
    async fn receive(
        &self,
        id: Uuid,
        upload: &Upload,
        body: Body,
        hashed: &mut Option<(u64, blake3::Hasher)>,
        token: &CancellationToken,
    ) -> Result<(u64, Ended), Response> {
        let path = self.staged(id);
        let mut hasher = match hashed.take() {
            Some((at, hasher)) if at == upload.received => hasher,
            _ => rehash(path.clone(), upload.received).await?,
        };
        let mut file = tokio::fs::OpenOptions::new()
            .write(true)
            .open(&path)
            .await
            .map_err(internal)?;
        // Bytes past the recorded offset were never acknowledged, and may not have reached the disk.
        file.set_len(upload.received).await.map_err(internal)?;
        file.seek(io::SeekFrom::Start(upload.received))
            .await
            .map_err(internal)?;
        let (mut received, mut stream) = (upload.received, body.into_data_stream());
        let ended = loop {
            let chunk = tokio::select! {
                biased;
                () = token.cancelled() => break Ended::Cut,
                chunk = stream.next() => chunk,
            };
            let bytes = match chunk {
                None => break Ended::Whole,
                Some(Err(_)) => break Ended::Cut,
                Some(Ok(bytes)) => bytes,
            };
            let room = (upload.length - received).min(bytes.len() as u64) as usize;
            file.write_all(&bytes[..room]).await.map_err(internal)?;
            hasher.update(&bytes[..room]);
            received += room as u64;
            if room < bytes.len() {
                break Ended::TooLong;
            }
        };
        file.flush().await.map_err(internal)?;
        file.sync_data().await.map_err(internal)?;
        let recorded = sqlx::query(
            "UPDATE uploads SET received = $2, expires_at = now() + make_interval(secs => $3) \
             WHERE id = $1 AND completed_at IS NULL",
        )
        .bind(id)
        .bind(received as i64)
        .bind(MAX_AGE_SECS as f64)
        .execute(&self.pool)
        .await
        .map_err(internal)?;
        if recorded.rows_affected() == 0 {
            return Err(refuse(ApiError::new(ErrorCode::NotFound, "upload.not_found")));
        }
        *hashed = Some((received, hasher));
        Ok((received, ended))
    }

    async fn private(&self, library: Uuid) -> Result<bool, Response> {
        sqlx::query_scalar("SELECT privacy = 'private' FROM libraries WHERE id = $1")
            .bind(library)
            .fetch_one(&self.pool)
            .await
            .map_err(internal)
    }

    /// Refuses bytes while a filesystem they fill has less free space than the instance's floor, the smaller of
    /// `min_free_disk_percent` of its size and `min_free_disk_gb` (ADR-0063): `work_dir`, `data_dir` for a library on
    /// the local store, and `database.data_dir`. Clients try again later.
    fn room(&self, (percent, gb, store): &Floor) -> Result<(), Response> {
        let local = (store.as_deref() == Some("local")).then_some(&self.disks.data_dir);
        let dirs = [
            ("work_dir", Some(&self.staging)),
            ("data_dir", local),
            ("database.data_dir", self.disks.database.as_ref()),
        ];
        for (name, dir) in dirs {
            let Some(dir) = dir else { continue };
            match (self.disks.space)(dir) {
                Ok((size, free)) if free < floor(size, *percent, *gb) => {
                    tracing::warn!(dir = name, free, "uploads pause: the disk is almost full");
                    return Err(refuse(
                        ApiError::new(ErrorCode::Unavailable, "disk.low").param("dir", name),
                    ));
                }
                Ok(_) => {}
                Err(error) => tracing::warn!(dir = name, %error, "free space unknown"),
            }
        }
        Ok(())
    }

    async fn admit(&self, headers: &HeaderMap, what: Resource) -> Result<(), Response> {
        self.allow(self.signed_in(headers).await?, what).await
    }

    /// Whether `who` may `Contribute` to `what`; an upload that is not theirs does not exist for them. A refusal names
    /// what the server's policy switched off, to whoever uploads into the library or appends to their own upload.
    async fn allow(&self, who: Principal, what: Resource) -> Result<(), Response> {
        if can(&self.pool, who, Action::Contribute, what).await.map_err(internal)? {
            return Ok(());
        }
        let account = match who {
            Principal::User(me, _) | Principal::Key(me, ..) => Some(me),
            _ => None,
        };
        let library = match what {
            Resource::Library(library) => Some(library),
            Resource::Upload(id) => {
                sqlx::query_scalar("SELECT library_id FROM uploads WHERE id = $1 AND owner_id = $2")
                    .bind(id)
                    .bind(account)
                    .fetch_optional(&self.pool)
                    .await
                    .map_err(internal)?
            }
            _ => None,
        };
        let off = match (account, library) {
            (Some(account), Some(library)) => self.switched_off(account, library).await?,
            _ => None,
        };
        Err(refuse(off.unwrap_or_else(|| match what {
            Resource::Upload(_) => ApiError::new(ErrorCode::NotFound, "upload.not_found"),
            _ => ApiError::new(ErrorCode::PermissionDenied, "library.contribute_denied"),
        })))
    }

    /// The refusal of the capability the server's policy switches off for uploads of `account` into `library`, if one
    /// is (ADR-0240).
    async fn switched_off(&self, account: Uuid, library: Uuid) -> Result<Option<ApiError>, Response> {
        let managed: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT FROM libraries WHERE id = $1 AND kind = 'managed')")
                .bind(library)
                .fetch_one(&self.pool)
                .await
                .map_err(internal)?;
        let policy = photolib_authz::policy(&self.pool, Some(account), Some(library)).await;
        let off = policy.map_err(internal)?.into_iter().find(|(capability, on, _)| {
            !on && (*capability == Capability::Uploads || (managed && *capability == Capability::ManagedLibraries))
        });
        Ok(off.map(|(capability, ..)| {
            ApiError::new(ErrorCode::PermissionDenied, "policy.disabled").param("capability", capability.name())
        }))
    }

    /// Refuses an upload into a private library from an account that could still lose its keys (design 06 §6).
    async fn recoverable(&self, owner: Uuid, library: Uuid) -> Result<(), Response> {
        let private: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT FROM libraries WHERE id = $1 AND privacy = 'private')")
                .bind(library)
                .fetch_one(&self.pool)
                .await
                .map_err(internal)?;
        if private && !account_keys::ready(&self.pool, owner).await.map_err(internal)? {
            return Err(refuse(ApiError::new(
                ErrorCode::FailedPrecondition,
                "keys.recovery_incomplete",
            )));
        }
        Ok(())
    }

    async fn signed_in(&self, headers: &HeaderMap) -> Result<Principal, Response> {
        match self.users.principal(headers).await.map_err(connect)? {
            None => Err(refuse(ApiError::new(
                ErrorCode::PermissionDenied,
                "second_factor.required",
            ))),
            Some(Principal::Anonymous) => Err(refuse(ApiError::new(ErrorCode::Unauthenticated, "session.required"))),
            Some(who) => Ok(who),
        }
    }

    async fn upload(&self, id: Uuid) -> Result<Upload, Response> {
        let row = sqlx::query(
            "SELECT u.owner_id, u.library_id, u.length, u.hash, u.received, u.completed_at IS NOT NULL AS complete, \
             greatest(0, ceil(extract(epoch FROM u.expires_at - now())))::bigint AS max_age, \
             s.min_free_disk_percent, s.min_free_disk_gb, l.store \
             FROM uploads u CROSS JOIN instance_settings s LEFT JOIN libraries l ON l.id = u.library_id \
             WHERE u.id = $1",
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(internal)?
        .ok_or_else(|| refuse(ApiError::new(ErrorCode::NotFound, "upload.not_found")))?;
        let hash: Vec<u8> = row.get("hash");
        Ok(Upload {
            owner: row.get("owner_id"),
            library: row.get("library_id"),
            length: row.get::<i64, _>("length") as u64,
            hash: Hash(hash.try_into().map_err(|_| internal("a malformed hash"))?),
            received: row.get::<i64, _>("received") as u64,
            complete: row.get("complete"),
            max_age: row.get("max_age"),
            floor: (
                row.get("min_free_disk_percent"),
                row.get("min_free_disk_gb"),
                row.get("store"),
            ),
        })
    }

    fn slot(&self, id: Uuid) -> Arc<Slot> {
        self.slots().entry(id).or_default().clone()
    }

    /// Forgets the slot of an upload that takes no more bytes.
    fn release(&self, id: Uuid) {
        self.slots().remove(&id);
    }

    fn slots(&self) -> std::sync::MutexGuard<'_, HashMap<Uuid, Arc<Slot>>> {
        self.slots.lock().expect("no thread panics holding the slots")
    }
}

impl Slot {
    /// Stops the request in flight, waits until it has kept what it received, and returns the lock with a token
    /// that the next request cancels.
    async fn take_over(
        &self,
    ) -> (
        tokio::sync::MutexGuard<'_, Option<(u64, blake3::Hasher)>>,
        CancellationToken,
    ) {
        let token = CancellationToken::new();
        let previous = std::mem::replace(
            &mut *self.current.lock().expect("no thread panics holding a token"),
            token.clone(),
        );
        previous.cancel();
        (self.hashed.lock().await, token)
    }
}

/// The free space below which uploads pause on a filesystem of `size` bytes: `percent` of it, or `gb` GB if less.
fn floor(size: u64, percent: i32, gb: i32) -> u64 {
    let percent = u64::from(percent.cast_unsigned());
    (size / 100)
        .saturating_mul(percent)
        .min(u64::from(gb.cast_unsigned()).saturating_mul(1_000_000_000))
}

/// The protocol's answer while an upload is incomplete: its offset and limits.
fn progress(status: StatusCode, upload: &Upload) -> Response {
    let limit = format!(
        "max-size={}, max-append-size={MAX_APPEND}, max-age={}",
        upload.length, upload.max_age
    );
    let mut response = status.into_response();
    let headers = response.headers_mut();
    headers.insert(COMPLETE, HeaderValue::from_static(sf_bool(upload.complete)));
    let offset = if upload.complete {
        upload.length
    } else {
        upload.received
    };
    headers.insert(OFFSET, offset.into());
    headers.insert(LIMIT, HeaderValue::try_from(limit).expect("a limit is ASCII"));
    response
}

/// The hash of the first `length` bytes staged at `path`, read again after a restart.
async fn rehash(path: PathBuf, length: u64) -> Result<blake3::Hasher, Response> {
    let read = tokio::task::spawn_blocking(move || {
        let mut hasher = blake3::Hasher::new();
        let read = io::copy(&mut io::Read::take(std::fs::File::open(&path)?, length), &mut hasher)?;
        match read == length {
            true => Ok(hasher),
            false => Err(io::Error::other(format!("{} lost bytes", path.display()))),
        }
    });
    read.await.map_err(internal)?.map_err(internal)
}

/// 409: the upload is at `offset`.
fn mismatch(offset: u64, complete: bool) -> Response {
    let error = ApiError::new(ErrorCode::Aborted, "upload.offset_mismatch");
    let mut response = refuse(error.param("offset", offset));
    let headers = response.headers_mut();
    headers.insert(COMPLETE, HeaderValue::from_static(sf_bool(complete)));
    headers.insert(OFFSET, offset.into());
    response
}

/// The acknowledgement of a complete upload, sent again to a client that lost it.
fn completed(id: Uuid, upload: &Upload) -> Response {
    let body = serde_json::json!({
        "uploadId": id,
        "length": upload.length,
        "blake3": upload.hash.to_string(),
    });
    let mut response = axum::Json(body).into_response();
    let headers = response.headers_mut();
    headers.insert(COMPLETE, HeaderValue::from_static("?1"));
    response
}

/// The bytes could not be written to the store; the client may complete the upload again.
fn unwritten(error: photolib_storage::Error) -> Response {
    tracing::error!(%error, "a complete upload could not be written to its store");
    let mut response = refuse(match error {
        photolib_storage::Error::Offline(_) | photolib_storage::Error::Timeout(_) => {
            ApiError::new(ErrorCode::Unavailable, "store.unavailable")
        }
        _ => ApiError::new(ErrorCode::Internal, "server.internal"),
    });
    let headers = response.headers_mut();
    headers.insert(COMPLETE, HeaderValue::from_static("?0"));
    response
}

fn length_mismatch() -> Response {
    refuse(ApiError::new(ErrorCode::InvalidArgument, "upload.length_mismatch"))
}

fn sf_bool(value: bool) -> &'static str {
    if value { "?1" } else { "?0" }
}

/// A Structured Field Boolean header.
fn flag(headers: &HeaderMap, name: &'static str) -> Result<bool, Response> {
    match headers.get(name).map(HeaderValue::as_bytes) {
        Some(b"?1") => Ok(true),
        Some(b"?0") => Ok(false),
        _ => Err(invalid(name)),
    }
}

/// A non-negative Structured Field Integer header, if present.
fn integer(headers: &HeaderMap, name: &'static str) -> Result<Option<u64>, Response> {
    let Some(value) = headers.get(name) else {
        return Ok(None);
    };
    let text = value.to_str().map_err(|_| invalid(name))?;
    if text.is_empty() || text.len() > 15 || !text.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid(name));
    }
    text.parse().map(Some).map_err(|_| invalid(name))
}

/// The file's path below its source's root, as percent-encoded UTF-8: names separated by "/", none of them empty,
/// "." or "..", and no backslash, control character or bidirectional override, which could disguise a name.
fn source_path(headers: &HeaderMap) -> Result<Option<String>, Response> {
    let Some(value) = headers.get(PATH) else {
        return Ok(None);
    };
    let mut bytes = value.to_str().map_err(|_| invalid(PATH))?.bytes();
    let mut decoded = vec![];
    while let Some(byte) = bytes.next() {
        decoded.push(match byte {
            b'%' => {
                let hex = [bytes.next(), bytes.next()].map(|d| d.and_then(|d| (d as char).to_digit(16)));
                let [Some(high), Some(low)] = hex else {
                    return Err(invalid(PATH));
                };
                (high * 16 + low) as u8
            }
            byte => byte,
        });
    }
    let path = String::from_utf8(decoded).map_err(|_| invalid(PATH))?;
    let disguised =
        |c: char| c == '\\' || c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}');
    let fine = (1..=1024).contains(&path.len())
        && path.split('/').all(|name| !["", ".", ".."].contains(&name))
        && !path.chars().any(disguised);
    fine.then_some(Some(path)).ok_or_else(|| invalid(PATH))
}

/// The vector a creation hands off, if every check passes (design 09 §3.2): the active model, a self-tested runtime,
/// as many finite half floats as the model's dimension and a norm above 0; else why it is dropped.
fn handoff(headers: &HeaderMap) -> Result<Option<Handoff>, &'static str> {
    let [model, runtime, vector] = [ML_MODEL, ML_RUNTIME, ML_VECTOR].map(|name| headers.get(name));
    let (Some(model), Some(runtime), Some(vector)) = (model, runtime, vector) else {
        return match model.or(runtime).or(vector) {
            None => Ok(None),
            Some(_) => Err("a header is missing"),
        };
    };
    // No library has an active model of its own yet (design 09 §12.3): the registry's first is everyone's.
    let active = REGISTRY.iter().find(|m| m.task == Task::ImageTextEmbedding);
    let active = active
        .filter(|m| m.name().as_bytes() == model.as_bytes())
        .ok_or("not the active model")?;
    if !runtime.to_str().is_ok_and(self_tested) {
        return Err("not onnxruntime <x.y.z> <provider> <precision>");
    }
    let bytes = STANDARD.decode(vector.as_bytes()).map_err(|_| "not base64")?;
    let (halves, odd) = bytes.as_chunks::<2>();
    let dim = active.dim.and_then(|dim| usize::try_from(dim).ok());
    if Some(halves.len()) != dim || !odd.is_empty() {
        return Err("not as many values as the model's dimension");
    }
    let halves = halves.iter().map(|half| u16::from_le_bytes(*half));
    // An exponent of all ones is an infinity or a NaN; anything but ±0 makes the norm positive.
    if halves.clone().any(|half| half & 0x7c00 == 0x7c00) {
        return Err("not finite");
    }
    if halves.clone().all(|half| matches!(half, 0 | 0x8000)) {
        return Err("a norm of 0");
    }
    Ok(Some((active.name(), bytes)))
}

/// `onnxruntime <x.y.z> <provider> <precision>`: the `rt_flags` of a self-tested runtime (design 09 §12.3).
fn self_tested(runtime: &str) -> bool {
    let number = |part: &str| !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit());
    let words: Vec<&str> = runtime.split(' ').collect();
    let [name, version, provider, precision] = words.as_slice() else {
        return false;
    };
    let version: Vec<&str> = version.split('.').collect();
    *name == "onnxruntime"
        && version.len() == 3
        && version.into_iter().all(number)
        && !provider.is_empty()
        && provider.bytes().all(|b| b.is_ascii_alphanumeric())
        && ["fp32", "fp16", "int8"].contains(precision)
}

fn dropped(reason: &str) -> Option<Handoff> {
    tracing::info!(reason, "a device's vector is dropped; its upload goes on");
    None
}

fn parsed<T: std::str::FromStr>(headers: &HeaderMap, name: &'static str) -> Result<T, Response> {
    let value = headers.get(name).and_then(|value| value.to_str().ok());
    value.and_then(|value| value.parse().ok()).ok_or_else(|| invalid(name))
}

fn invalid(field: &'static str) -> Response {
    refuse(ApiError::new(ErrorCode::InvalidArgument, "field.invalid").param("field", field))
}

fn internal(error: impl std::fmt::Display) -> Response {
    tracing::error!(%error, "an upload request failed");
    refuse(ApiError::new(ErrorCode::Internal, "server.internal"))
}

/// An error as photolibd's Connect errors are, so that clients read its code and reason the same way.
fn refuse(error: ApiError) -> Response {
    connect(error.into())
}

pub(crate) fn connect(error: ConnectError) -> Response {
    let mut response = (error.http_status(), error.to_json()).into_response();
    response
        .headers_mut()
        .insert(header::CONTENT_TYPE, HeaderValue::from_static("application/json"));
    response
}
