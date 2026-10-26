//! The S3 driver on OpenDAL (ADR-0022), within the core object API that Garage and other S3-compatible stores offer.
//! A put refuses an existing key, writes one PUT or a multipart upload with the BLAKE3 hash and size as object
//! metadata, and a HEAD verifies both. Listings and aborts are signed requests of our own (see `Raw`). Credentials
//! come only from the configuration: no environment, profile or instance metadata lookups.

use std::{
    fs::File,
    ops::Range,
    os::unix::fs::FileExt,
    path::Path,
    sync::Arc,
    time::{Duration, SystemTime},
};

use async_trait::async_trait;
use bytes::Bytes;
use futures::TryStreamExt;
use http::{
    Method, Request, Response,
    header::{CONTENT_LENGTH, DATE},
};
use http_body_util::{BodyExt, Full};
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{Client, connect::HttpConnector},
    rt::TokioExecutor,
};
use opendal::{
    Buffer, ErrorKind, HttpBody, HttpTransport, HttpTransporter, OperationContext, Operator, Writer,
    raw::percent_encode_path,
};
use percent_encoding::{AsciiSet, NON_ALPHANUMERIC, percent_decode_str, utf8_percent_encode};
use reqsign_aws_v4::{Credential, RequestSigner, StaticCredentialProvider};
use reqsign_core::{Context, Signer};
use serde::{Deserialize, Serialize};

use crate::{BlobStore, Error, Hash, Hook, Local, Meta, Result, Upload, check_key, pool::Pool};

/// Uploads above this size are multipart, in parts of this size (photolib-design docs/07 §6).
const PART: usize = 64 << 20;
const QUERY: &AsciiSet = &NON_ALPHANUMERIC.remove(b'-').remove(b'.').remove(b'_').remove(b'~');

#[derive(Clone, Serialize, Deserialize)]
pub struct S3Config {
    pub endpoint: String,
    pub bucket: String,
    pub region: String,
    /// Keys live under this prefix, e.g. `home/`.
    pub prefix: String,
    pub access_key_id: String,
    pub secret_access_key: String,
}

pub struct S3Store {
    op: Operator,
    raw: Arc<Raw>,
    pool: Pool,
    part: usize,
    hook: Option<Hook>,
}

impl S3Store {
    pub fn open(config: &S3Config, timeout: Duration) -> Result<S3Store> {
        let builder = opendal::services::S3::default()
            .endpoint(&config.endpoint)
            .bucket(&config.bucket)
            .region(&config.region)
            .root(&format!("/{}", config.prefix))
            .access_key_id(&config.access_key_id)
            .secret_access_key(&config.secret_access_key)
            .disable_config_load()
            .disable_ec2_metadata();
        let http = HttpTransporter::new(Https::new()?);
        let op = Operator::new(builder)
            .map_err(|e| Error::Other(format!("cannot configure the S3 store: {e}")))?
            .with_context(OperationContext::new().with_http_transport(http.clone()));
        let credentials = StaticCredentialProvider::new(&config.access_key_id, &config.secret_access_key);
        let raw = Raw {
            http,
            signer: Signer::new(Context::new(), credentials, RequestSigner::new("s3", &config.region)),
            bucket: format!("{}/{}", config.endpoint.trim_end_matches('/'), config.bucket),
            prefix: config.prefix.clone(),
        };
        Ok(S3Store {
            op,
            raw: Arc::new(raw),
            pool: Pool::new("s3", timeout)?,
            part: PART,
            hook: None,
        })
    }

    /// The store's clock, from the `Date` of a signed listing: a wrong credential fails it, and signatures fail when
    /// the clocks are more than 15 minutes apart.
    pub async fn clock(&self) -> Result<SystemTime> {
        let raw = self.raw.clone();
        let url = format!("{}?list-type=2&max-keys=1&prefix={}", raw.bucket, query(&raw.prefix));
        self.pool
            .run("read the store's clock", async move {
                let response = raw.call(Method::GET, url).await?;
                let (status, date) = (response.status(), response.headers().get(DATE).cloned());
                if !status.is_success() {
                    let body = response.into_body().to_bytes();
                    return Err(Error::Other(format!("{status} {}", String::from_utf8_lossy(&body))));
                }
                let date = date.as_ref().and_then(|date| date.to_str().ok()).unwrap_or_default();
                jiff::fmt::rfc2822::DateTimeParser::new()
                    .parse_timestamp(date)
                    .map(SystemTime::from)
                    .map_err(|e| Error::Other(format!("the store's Date header {date:?}: {e}")))
            })
            .await
    }

    pub fn with_hook(mut self, hook: Hook) -> Self {
        self.hook = Some(hook);
        self
    }

    /// Smaller parts, for tests (S3 allows 5 MiB).
    pub fn part_size(mut self, bytes: usize) -> Self {
        self.part = bytes;
        self
    }

    /// Writes `bytes` over `key` with `hash` as their recorded hash, as an object replaced behind the server's back
    /// would be found: for tests.
    #[cfg(any(test, feature = "testing"))]
    pub async fn forge(&self, key: &str, bytes: Vec<u8>, hash: Hash) -> Result<()> {
        let metadata = [
            ("blake3".to_string(), hash.to_string()),
            ("size".into(), bytes.len().to_string()),
        ];
        let write = self.op.write_with(key, bytes).user_metadata(metadata).await;
        write.map(drop).map_err(|e| s3_error(key, e))
    }

    fn step(&self) -> impl Fn(&str) -> Result<()> + Send + Sync + 'static {
        let hook = self.hook.clone();
        move |name| hook.as_ref().map_or(Ok(()), |hook| hook(name))
    }

    /// Sends a local file part by part through `w`, hashing what was sent.
    async fn upload(&self, key: &str, w: &mut Option<Writer>, file: Arc<File>) -> Result<Hash> {
        let mut hasher = blake3::Hasher::new();
        let mut offset = 0u64;
        loop {
            let (part, f) = (self.part, file.clone());
            let chunk = self
                .pool
                .blocking("read the staged file", move || read_at(&f, offset, part))
                .await?;
            if chunk.is_empty() {
                return Ok(Hash::from(hasher.finalize()));
            }
            hasher.update(&chunk);
            offset += chunk.len() as u64;
            let (mut writer, step, k) = (w.take().expect("a writer"), self.step(), key.to_owned());
            let (writer, written) = self
                .pool
                .run(&format!("upload {key:?}"), async move {
                    let written = writer.write(Bytes::from(chunk)).await.map_err(|e| s3_error(&k, e));
                    Ok((writer, written.and_then(|()| step("part"))))
                })
                .await?;
            *w = Some(writer);
            written?;
        }
    }

    async fn fetch(&self, key: &str, range: Range<u64>) -> Result<Vec<u8>> {
        let (op, k) = (self.op.clone(), key.to_owned());
        self.pool
            .run(&format!("get {key:?}"), async move {
                let read = op.read_with(&k).range(range).await;
                read.map(|buffer| buffer.to_vec()).map_err(|e| s3_error(&k, e))
            })
            .await
    }
}

fn read_at(file: &File, offset: u64, len: usize) -> Result<Vec<u8>> {
    let mut buf = vec![0; len];
    let mut n = 0;
    while n < len {
        match file.read_at(&mut buf[n..], offset + n as u64) {
            Ok(0) => break,
            Ok(read) => n += read,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(Error::Other(format!("cannot read a staged file: {e}"))),
        }
    }
    buf.truncate(n);
    Ok(buf)
}

/// OpenDAL trims whitespace off both ends of a path, which would store such a key under another name.
fn s3_key(key: &str) -> Result<()> {
    check_key(key)?;
    match key.trim() == key {
        true => Ok(()),
        false => Err(Error::InvalidKey(format!(
            "an object key cannot start or end with whitespace: {key:?}"
        ))),
    }
}

fn s3_error(key: &str, e: opendal::Error) -> Error {
    match e.kind() {
        ErrorKind::NotFound => Error::NotFound(key.into()),
        _ => Error::Other(format!("{key:?}: {e}")),
    }
}

fn verify(key: &str, meta: Option<Meta>, expected: Meta) -> Result<Meta> {
    match meta {
        Some(meta) if meta == expected => Ok(meta),
        found => Err(Error::Integrity(format!(
            "{key:?} is {found:?} after the write, expected {expected:?}"
        ))),
    }
}

#[async_trait]
impl BlobStore for S3Store {
    async fn put(&self, key: &str, staged: &Path, hash: Hash) -> Result<Meta> {
        s3_key(key)?;
        if self.head(key).await?.is_some() {
            return Err(Error::Exists(key.into()));
        }
        let open = |e| Error::Other(format!("cannot read {}: {e}", staged.display()));
        let file = File::open(staged).map_err(open)?;
        let size = file.metadata().map_err(open)?.len();
        let metadata = [
            ("blake3".to_string(), hash.to_string()),
            ("size".into(), size.to_string()),
        ];
        let (op, k) = (self.op.clone(), key.to_owned());
        // No `chunk`: every write is one part, so the multipart upload starts with the second.
        let writer = self
            .pool
            .run(&format!("start {key:?}"), async move {
                let writer = op.writer_with(&k).user_metadata(metadata).await;
                writer.map_err(|e| s3_error(&k, e))
            })
            .await?;
        let mut w = Some(writer);
        let uploaded = match self.upload(key, &mut w, Arc::new(file)).await {
            Ok(actual) if actual != hash => Err(Error::Integrity(format!(
                "{key:?}: the staged file is {actual:?}, expected {hash:?}"
            ))),
            uploaded => uploaded,
        };
        // A timed-out part takes the writer with it; recovery aborts that upload.
        let Some(mut writer) = w else {
            return Err(uploaded
                .err()
                .unwrap_or_else(|| Error::Other("the upload was lost".into())));
        };
        let (k, step) = (key.to_owned(), self.step());
        match uploaded {
            Ok(_) => {
                self.pool
                    .run(&format!("complete {key:?}"), async move {
                        writer.close().await.map_err(|e| s3_error(&k, e))?;
                        step("closed")
                    })
                    .await?
            }
            Err(error) => {
                let abort = async move { writer.abort().await.map_err(|e| s3_error(&k, e)) };
                let _ = self.pool.run(&format!("abort {key:?}"), abort).await;
                return Err(error);
            }
        }
        let expected = Meta { size, hash: Some(hash) };
        let written = verify(key, self.head(key).await?, expected);
        if written.is_err() {
            self.delete(key).await?;
        }
        written
    }

    async fn get(&self, key: &str, range: Option<Range<u64>>) -> Result<Vec<u8>> {
        let size = self.head(key).await?.ok_or_else(|| Error::NotFound(key.into()))?.size;
        let range = range.unwrap_or(0..size);
        let range = range.start.min(size)..range.end.min(size);
        if range.is_empty() {
            return Ok(Vec::new());
        }
        self.fetch(key, range).await
    }

    async fn head(&self, key: &str) -> Result<Option<Meta>> {
        s3_key(key)?;
        let (op, k) = (self.op.clone(), key.to_owned());
        self.pool
            .run(&format!("head {key:?}"), async move {
                match op.stat(&k).await {
                    Ok(meta) => Ok(Some(Meta {
                        size: meta.content_length(),
                        hash: meta.user_metadata().and_then(|m| m.get("blake3")?.parse().ok()),
                    })),
                    Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
                    Err(e) => Err(s3_error(&k, e)),
                }
            })
            .await
    }

    async fn delete(&self, key: &str) -> Result<()> {
        s3_key(key)?;
        let (op, k) = (self.op.clone(), key.to_owned());
        self.pool
            .run(&format!("delete {key:?}"), async move {
                op.delete(&k).await.map_err(|e| s3_error(&k, e))
            })
            .await
    }

    async fn copy(&self, from: &str, to: &str) -> Result<Meta> {
        s3_key(to)?;
        let source = self.head(from).await?.ok_or_else(|| Error::NotFound(from.into()))?;
        if self.head(to).await?.is_some() {
            return Err(Error::Exists(to.into()));
        }
        let (op, f, t) = (self.op.clone(), from.to_owned(), to.to_owned());
        let copy = async move { op.copy(&f, &t).await.map(drop).map_err(|e| s3_error(&f, e)) };
        self.pool.run(&format!("copy {from:?}"), copy).await?;
        verify(to, self.head(to).await?, source)
    }

    async fn list(&self, prefix: &str) -> Result<Vec<String>> {
        let (raw, p) = (self.raw.clone(), prefix.to_owned());
        let list = async move { raw.list(&p).await };
        let mut keys = self.pool.run(&format!("list {prefix:?}"), list).await?;
        keys.sort();
        Ok(keys)
    }

    async fn uploads(&self, prefix: &str) -> Result<Vec<Upload>> {
        let (raw, p) = (self.raw.clone(), prefix.to_owned());
        self.pool
            .run(&format!("list the uploads of {prefix:?}"), async move {
                raw.uploads(&p).await
            })
            .await
    }

    async fn abort(&self, upload: &Upload) -> Result<()> {
        let (raw, u) = (self.raw.clone(), upload.clone());
        self.pool
            .run(&format!("abort {:?}", upload.key), async move { raw.abort(&u).await })
            .await
    }

    async fn local(&self, key: &str, hash: Hash, scratch: &Path) -> Result<Local> {
        let size = self.head(key).await?.ok_or_else(|| Error::NotFound(key.into()))?.size;
        let path = scratch.join(key.rsplit('/').next().unwrap_or(key));
        let scratch_error = |e: std::io::Error| Error::Other(format!("cannot write {}: {e}", path.display()));
        let file = Arc::new(File::create_new(&path).map_err(scratch_error)?);
        let mut hasher = blake3::Hasher::new();
        let mut copied = Ok(());
        let mut offset = 0;
        while offset < size && copied.is_ok() {
            let end = size.min(offset + self.part as u64);
            copied = match self.fetch(key, offset..end).await {
                Ok(chunk) => {
                    hasher.update(&chunk);
                    let (f, at) = (file.clone(), offset);
                    offset += chunk.len() as u64;
                    let write = move || {
                        f.write_all_at(&chunk, at)
                            .map_err(|e| Error::Other(format!("scratch: {e}")))
                    };
                    self.pool.blocking("write a scratch copy", write).await
                }
                Err(e) => Err(e),
            };
        }
        let actual = Hash::from(hasher.finalize());
        let checked = copied.and_then(|()| match actual == hash {
            true => file.sync_all().map_err(scratch_error),
            false => Err(Error::Integrity(format!(
                "{key:?} reads as {actual:?}, expected {hash:?}"
            ))),
        });
        match checked {
            Ok(()) => Ok(Local::Copy(path)),
            Err(error) => {
                let _ = std::fs::remove_file(&path);
                Err(error)
            }
        }
    }
}

/// The signed requests OpenDAL does not make: listing with `encoding-type=url`, as XML cannot carry every
/// character a key may hold (a carriage return comes back as a line feed), and listing and aborting multipart uploads.
struct Raw {
    http: HttpTransporter,
    signer: Signer<Credential>,
    bucket: String,
    prefix: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct ListObjects {
    #[serde(default)]
    contents: Vec<Entry>,
    #[serde(default)]
    is_truncated: bool,
    next_continuation_token: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct ListUploads {
    #[serde(default)]
    upload: Vec<Entry>,
    #[serde(default)]
    is_truncated: bool,
    next_key_marker: Option<String>,
    next_upload_id_marker: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct Entry {
    key: String,
    upload_id: Option<String>,
    initiated: Option<String>,
}

fn query(value: &str) -> String {
    utf8_percent_encode(value, QUERY).to_string()
}

impl Raw {
    async fn send(&self, method: Method, url: String) -> Result<(http::StatusCode, String)> {
        let response = self.call(method, url).await?;
        Ok((
            response.status(),
            String::from_utf8_lossy(&response.into_body().to_bytes()).into_owned(),
        ))
    }

    async fn call(&self, method: Method, url: String) -> Result<Response<Buffer>> {
        let fail = |e: &dyn std::fmt::Display| Error::Other(format!("{method} {url}: {e}"));
        let (mut parts, body) = Request::builder()
            .method(method.clone())
            .uri(&url)
            .body(Buffer::new())
            .map_err(|e| fail(&e))?
            .into_parts();
        self.signer.sign(&mut parts, None).await.map_err(|e| fail(&e))?;
        self.http
            .send(Request::from_parts(parts, body))
            .await
            .map_err(|e| fail(&e))
    }

    /// One page of a listing of keys under `prefix`, which are URL-encoded in the response.
    async fn page<T: serde::de::DeserializeOwned>(&self, what: &str, prefix: &str, more: &str) -> Result<T> {
        let prefix = query(&format!("{}{prefix}", self.prefix));
        let url = format!("{}?{what}&encoding-type=url&prefix={prefix}{more}", self.bucket);
        let fail = |e: &dyn std::fmt::Display| Error::Other(format!("listing {prefix}: {e}"));
        let (status, text) = self.send(Method::GET, url).await?;
        if !status.is_success() {
            return Err(fail(&format!("{status} {text}")));
        }
        quick_xml::de::from_str(&text).map_err(|e| fail(&e))
    }

    /// A key from a URL-encoded listing, without the store's prefix. Servers encode `+` itself, so a `+` is a space.
    fn key(&self, encoded: &str) -> Result<String> {
        let spaced = encoded.replace('+', " ");
        let key = percent_decode_str(&spaced)
            .decode_utf8()
            .map_err(|e| Error::Other(format!("a listed key is not UTF-8: {e}")))?;
        Ok(key.strip_prefix(&self.prefix).unwrap_or(&key).to_string())
    }

    async fn list(&self, prefix: &str) -> Result<Vec<String>> {
        let mut keys = Vec::new();
        let mut more = String::new();
        loop {
            let page: ListObjects = self.page("list-type=2", prefix, &more).await?;
            for entry in page.contents {
                keys.push(self.key(&entry.key)?);
            }
            match (page.is_truncated, page.next_continuation_token) {
                (true, Some(token)) => more = format!("&continuation-token={}", query(&token)),
                _ => return Ok(keys),
            }
        }
    }

    async fn uploads(&self, prefix: &str) -> Result<Vec<Upload>> {
        let mut uploads = Vec::new();
        let mut more = String::new();
        loop {
            let page: ListUploads = self.page("uploads", prefix, &more).await?;
            for entry in page.upload {
                let started = entry.initiated.unwrap_or_default().parse::<jiff::Timestamp>();
                uploads.push(Upload {
                    key: self.key(&entry.key)?,
                    id: entry.upload_id.unwrap_or_default(),
                    started: started
                        .map_err(|e| Error::Other(format!("an upload's start: {e}")))?
                        .into(),
                });
            }
            match (page.is_truncated, page.next_key_marker, page.next_upload_id_marker) {
                (true, Some(key), Some(id)) => {
                    more = format!(
                        "&key-marker={}&upload-id-marker={}",
                        query(&self.key(&key)?),
                        query(&id)
                    );
                }
                _ => return Ok(uploads),
            }
        }
    }

    async fn abort(&self, upload: &Upload) -> Result<()> {
        let path = percent_encode_path(&format!("{}{}", self.prefix, upload.key));
        let id = utf8_percent_encode(&upload.id, QUERY);
        let (status, text) = self
            .send(Method::DELETE, format!("{}/{path}?uploadId={id}", self.bucket))
            .await?;
        match status.as_u16() {
            200..=299 | 404 => Ok(()),
            _ => Err(Error::Other(format!(
                "aborting the upload of {:?}: {status} {text}",
                upload.key
            ))),
        }
    }
}

/// HTTPS on rustls with the system's roots: OpenDAL's own transport would bring reqwest's TLS stack.
struct Https(Client<HttpsConnector<HttpConnector>, Full<Bytes>>);

/// Pauses before each try again of a request the store answered as busy or failing for a moment (429 or 5xx), as
/// Garage does when its database is locked under load. Every request is whole in memory, so it can be sent again.
const RETRIES: [Duration; 3] = [
    Duration::from_millis(100),
    Duration::from_millis(400),
    Duration::from_millis(1600),
];

impl Https {
    fn new() -> Result<Https> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let connector = hyper_rustls::HttpsConnectorBuilder::new()
            .with_provider_and_native_roots(provider)
            .map_err(|e| Error::Other(format!("cannot load the system's TLS roots: {e}")))?
            .https_or_http()
            .enable_http1()
            .build();
        Ok(Https(Client::builder(TokioExecutor::new()).build(connector)))
    }

    async fn send(&self, req: Request<Buffer>) -> opendal::Result<Response<HttpBody>> {
        let head = req.method() == Method::HEAD;
        let request = self.0.request(req.map(|body| Full::new(body.to_bytes())));
        let (parts, body) = request
            .await
            .map_err(|e| transport_error("S3 request failed", e))?
            .into_parts();
        let size = parts
            .headers
            .get(CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok()?.parse().ok());
        let stream = body
            .into_data_stream()
            .map_ok(Buffer::from)
            .map_err(|e| transport_error("reading an S3 response failed", e));
        Ok(Response::from_parts(
            parts,
            HttpBody::new(stream, size.filter(|_| !head)),
        ))
    }
}

fn transport_error(what: &'static str, e: impl std::error::Error + Send + Sync + 'static) -> opendal::Error {
    opendal::Error::new(ErrorKind::Unexpected, what)
        .set_temporary()
        .set_source(e)
}

impl HttpTransport for Https {
    async fn fetch(&self, req: Request<Buffer>) -> opendal::Result<Response<HttpBody>> {
        let mut pauses = RETRIES.iter();
        loop {
            let response = self.send(req.clone()).await?;
            match (response.status().as_u16(), pauses.next()) {
                (429 | 500 | 502 | 503 | 504, Some(pause)) => tokio::time::sleep(*pause).await,
                _ => return Ok(response),
            }
        }
    }
}
