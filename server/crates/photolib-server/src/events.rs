//! Events and webhooks (M9-04, ADR-0263). A trigger on `assets` records what happens to each asset as ids only;
//! `page` is the one read path of the events API and of webhook deliveries: the events of the assets an account may
//! view and has not locked, and the deletions in the libraries it may view, of standard libraries only, in commit
//! order below the sync watermark. The `events` job, queued every minute, purges what is a week old and POSTs each
//! webhook its owner's events, signed as Standard Webhooks sign them.

use std::{
    future::Future,
    io,
    net::{IpAddr, SocketAddr},
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use async_trait::async_trait;
use axum::http::{Request, header::CONTENT_TYPE};
use base64::{Engine, engine::general_purpose::STANDARD};
use bytes::Bytes;
use http_body_util::Full;
use hyper_rustls::HttpsConnector;
use hyper_util::{
    client::legacy::{
        Client,
        connect::{HttpConnector, dns::Name},
    },
    rt::TokioExecutor,
};
use photolib_authz::{Action, Kind, Principal, scope};
use photolib_db::sync::watermark;
use photolib_jobs::{Handler, Job};
use photolib_proto::proto::photolib::api::v1::{Event, EventType, Webhook};
use rand_core::{OsRng, RngCore};
use ring::hmac;
use sqlx::{PgConnection, PgPool, QueryBuilder};
use url::{Host, Url};
use uuid::Uuid;

use crate::{accounts::timestamp, keys::role_named};

/// The job type: the scheduler queues it every minute.
pub const EVENTS: &str = "events";
/// How long a receiver may take to answer a delivery.
const TIMEOUT: Duration = Duration::from_secs(10);
/// The events a delivery run reads at once.
const BATCH: u16 = 100;

/// The webhooks an account may have.
const MAX_WEBHOOKS: i64 = 10;
const WEBHOOK: &str = "id::text, url, (extract(EPOCH FROM created_at) * 1e6)::bigint,
    (extract(EPOCH FROM delivered_at) * 1e6)::bigint, (extract(EPOCH FROM failing_since) * 1e6)::bigint,
    coalesce(last_status, 0)";
type Row = (String, String, i64, Option<i64>, Option<i64>, i32);

/// The event types as `events.type` names them.
const TYPES: [(&str, EventType); 4] = [
    ("asset.created", EventType::EVENT_TYPE_ASSET_CREATED),
    ("asset.trashed", EventType::EVENT_TYPE_ASSET_TRASHED),
    ("asset.restored", EventType::EVENT_TYPE_ASSET_RESTORED),
    ("asset.deleted", EventType::EVENT_TYPE_ASSET_DELETED),
];

/// Where a reader stands: after the event `id` of the transaction `txid`, in `(txid, id)` order.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Position {
    txid: u64,
    id: i64,
}

impl Position {
    /// The position an `event_id` or a `next_after` names; empty is the start.
    pub fn parse(text: &str) -> Option<Self> {
        if text.is_empty() {
            return Some(Self::default());
        }
        let (txid, id) = text.split_once('.')?;
        Some(Self {
            txid: txid.parse().ok()?,
            id: id.parse().ok()?,
        })
    }
}

impl std::fmt::Display for Position {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}.{}", self.txid, self.id)
    }
}

/// Up to `limit` events after `after` that `who` may see, oldest first, and where to read on: past the last one, or,
/// on a short page, past every event below the watermark.
pub async fn page(pool: &PgPool, who: Principal, after: Position, limit: u16) -> sqlx::Result<(Vec<Event>, Position)> {
    let below = watermark(pool).await?.0;
    let mut q = QueryBuilder::new(
        "SELECT e.txid::text, e.id, e.type, (extract(EPOCH FROM e.at) * 1e6)::bigint, e.library_id::text,
           e.asset_id::text
         FROM events e JOIN libraries l ON l.id = e.library_id AND l.privacy = 'standard'
         WHERE (e.txid, e.id) > (",
    );
    q.push_bind(after.txid.to_string()).push("::xid8, ").push_bind(after.id);
    q.push(") AND e.txid < ").push_bind(below.to_string()).push("::xid8");
    q.push(" AND (EXISTS (SELECT FROM (");
    scope(who, Action::View, Kind::Asset, &mut q);
    q.push(") s JOIN assets a ON a.id = s.id AND NOT a.locked WHERE s.id = e.asset_id)");
    q.push(" OR e.type = 'asset.deleted' AND EXISTS (SELECT FROM (");
    scope(who, Action::View, Kind::Library, &mut q);
    q.push(") s WHERE s.id = e.library_id)) ORDER BY e.txid, e.id LIMIT ")
        .push_bind(i64::from(limit));
    let rows: Vec<(String, i64, String, i64, String, String)> = q.build_query_as().fetch_all(pool).await?;
    let full = rows.len() == usize::from(limit);
    let mut next = after.max(Position { txid: below, id: 0 });
    let mut events = Vec::with_capacity(rows.len());
    for (txid, id, kind, micros, library_id, asset_id) in rows {
        let txid = txid.parse().map_err(|error| sqlx::Error::Decode(Box::new(error)))?;
        let kind = TYPES.iter().find(|(name, _)| *name == kind).map(|&(_, kind)| kind);
        let at = Position { txid, id };
        events.push(Event {
            event_id: at.to_string(),
            r#type: kind.unwrap_or_default().into(),
            recorded_at: timestamp(micros).into(),
            library_id,
            asset_id,
            ..Default::default()
        });
        if full {
            next = at;
        }
    }
    Ok((events, next))
}

/// Why a webhook cannot be created or deleted.
#[derive(Debug)]
pub enum WebhookError {
    /// The named field has a value a webhook cannot take.
    Invalid(&'static str),
    /// The account has no such webhook.
    NotFound,
    /// The account has as many webhooks as it may.
    Limit,
    /// The database failed.
    Db(sqlx::Error),
}

impl From<sqlx::Error> for WebhookError {
    fn from(error: sqlx::Error) -> Self {
        Self::Db(error)
    }
}

/// Registers a webhook of `owner` at `url`; returns it and its secret.
pub async fn create(pool: &PgPool, owner: Uuid, url: &str) -> Result<(Webhook, String), WebhookError> {
    let url = target(url).ok_or(WebhookError::Invalid("url"))?;
    let mut secret = [0; 32];
    OsRng.fill_bytes(&mut secret);
    let mut tx = pool.begin().await?;
    let row: Option<Row> = sqlx::query_as(&format!(
        "INSERT INTO webhooks (id, owner_id, url, secret) SELECT $1, $2, $3, $4
         WHERE (SELECT count(*) FROM webhooks WHERE owner_id = $2) < $5 RETURNING {WEBHOOK}"
    ))
    .bind(Uuid::now_v7())
    .bind(owner)
    .bind(url.as_str())
    .bind(&secret[..])
    .bind(MAX_WEBHOOKS)
    .fetch_optional(&mut *tx)
    .await?;
    let row = row.ok_or(WebhookError::Limit)?;
    audit(&mut tx, owner, "webhook.create", &row.0).await?;
    tx.commit().await?;
    Ok((webhook(row), format!("whsec_{}", STANDARD.encode(secret))))
}

/// The webhooks of `owner`, oldest first.
pub async fn list(pool: &PgPool, owner: Uuid) -> sqlx::Result<Vec<Webhook>> {
    let sql = format!("SELECT {WEBHOOK} FROM webhooks WHERE owner_id = $1 ORDER BY id");
    let rows: Vec<Row> = sqlx::query_as(&sql).bind(owner).fetch_all(pool).await?;
    Ok(rows.into_iter().map(webhook).collect())
}

/// Deletes the webhook `id` of `owner`.
pub async fn delete(pool: &PgPool, owner: Uuid, id: &str) -> Result<(), WebhookError> {
    let id: Uuid = id.parse().map_err(|_| WebhookError::Invalid("webhook_id"))?;
    let mut tx = pool.begin().await?;
    let deleted = sqlx::query("DELETE FROM webhooks WHERE id = $1 AND owner_id = $2")
        .bind(id)
        .bind(owner)
        .execute(&mut *tx)
        .await?;
    if deleted.rows_affected() == 0 {
        return Err(WebhookError::NotFound);
    }
    audit(&mut tx, owner, "webhook.delete", &id.to_string()).await?;
    Ok(tx.commit().await?)
}

/// Names the webhook, never its URL, which may hold the receiver's token.
async fn audit(tx: &mut PgConnection, owner: Uuid, action: &str, id: &str) -> sqlx::Result<()> {
    sqlx::query("SELECT audit_append($1, $2, jsonb_build_object('webhook_id', $3::text), NULL)")
        .bind(owner)
        .bind(action)
        .bind(id)
        .execute(tx)
        .await
        .map(drop)
}

fn webhook((webhook_id, url, created_at, delivered_at, failing_since, last_status): Row) -> Webhook {
    Webhook {
        webhook_id,
        url,
        created_at: timestamp(created_at).into(),
        delivered_at: delivered_at.map(timestamp).into(),
        failing_since: failing_since.map(timestamp).into(),
        last_status: u32::try_from(last_status).unwrap_or_default(),
        ..Default::default()
    }
}

/// `url` if a webhook may POST to it: http or https, at most 2000 characters, at a host name or an address that is
/// `reachable`.
fn target(url: &str) -> Option<Url> {
    let url = Url::parse(url).ok().filter(|_| url.len() <= 2000)?;
    let allowed = match url.host()? {
        Host::Domain(_) => true,
        Host::Ipv4(ip) => reachable(ip.into()),
        Host::Ipv6(ip) => reachable(ip.into()),
    };
    (allowed && matches!(url.scheme(), "http" | "https")).then_some(url)
}

/// Whether a webhook may connect to `ip`: a LAN or public address, never one of this machine's (loopback, `0.0.0.0/8`,
/// also as `::1`, `::` and other IPv4-compatible or mapped IPv6), a link-local one (where cloud metadata services
/// answer), broadcast or multicast.
fn reachable(ip: IpAddr) -> bool {
    let v4 = match ip {
        IpAddr::V4(v4) => v4,
        IpAddr::V6(v6) => match v6.to_ipv4() {
            Some(v4) => v4,
            None => return !(v6.is_multicast() || v6.is_unicast_link_local()),
        },
    };
    !(v4.is_loopback() || v4.octets()[0] == 0 || v4.is_link_local() || v4.is_broadcast() || v4.is_multicast())
}

type Http = Client<HttpsConnector<HttpConnector<Guarded>>, Full<Bytes>>;
/// A webhook to deliver to: its id, owner, the owner's role, URL, secret and the position it was delivered up to.
type Hook = (Uuid, Uuid, String, String, Vec<u8>, String, i64);

/// The `events` job: purges the events a week old and, where webhooks are on, POSTs each webhook of an active
/// account the events its owner may read, one at a time and in order, until one fails; the next run tries it again.
pub struct Deliveries {
    pool: PgPool,
    /// None while webhooks are off.
    http: Option<Http>,
}

impl Deliveries {
    /// The job of a worker; `on` is whether webhooks are.
    pub fn new(pool: PgPool, on: bool) -> Result<Self, String> {
        Self::guarded(pool, on, reachable)
    }

    /// Connects only to the addresses `allows` lets through.
    fn guarded(pool: PgPool, on: bool, allows: fn(IpAddr) -> bool) -> Result<Self, String> {
        let http = on.then(|| {
            let mut connector = HttpConnector::new_with_resolver(Guarded(allows));
            connector.enforce_http(false);
            let tls = Arc::new(rustls::crypto::ring::default_provider());
            let connector = hyper_rustls::HttpsConnectorBuilder::new()
                .with_provider_and_native_roots(tls)
                .map_err(|error| format!("cannot load the system's TLS roots: {error}"))?
                .https_or_http()
                .enable_http1()
                .wrap_connector(connector);
            Ok::<_, String>(Client::builder(TokioExecutor::new()).build(connector))
        });
        Ok(Self {
            pool,
            http: http.transpose()?,
        })
    }

    /// Purges, then delivers unless another run holds `lock`'s lock, which takes no transaction id and so holds back
    /// no watermark.
    async fn tick(&self, lock: &mut PgConnection) -> sqlx::Result<()> {
        sqlx::query("DELETE FROM events WHERE at < now() - interval '7 days'")
            .execute(&self.pool)
            .await?;
        let Some(http) = &self.http else {
            return Ok(());
        };
        let free: bool = sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtextextended('webhooks', 0))")
            .fetch_one(lock)
            .await?;
        if !free {
            return Ok(());
        }
        let hooks: Vec<Hook> = sqlx::query_as(
            "SELECT w.id, w.owner_id, u.role, w.url, w.secret, w.after_txid::text, w.after_id
             FROM webhooks w JOIN users u ON u.id = w.owner_id AND u.status = 'active' ORDER BY w.id",
        )
        .fetch_all(&self.pool)
        .await?;
        for (id, owner, role, url, secret, txid, after_id) in hooks {
            let who = Principal::User(owner, role_named(&role));
            let txid = txid.parse().map_err(|error| sqlx::Error::Decode(Box::new(error)))?;
            let mut after = Position { txid, id: after_id };
            loop {
                let (events, next) = page(&self.pool, who, after, BATCH).await?;
                let (mut sent, mut failed) = (false, None);
                for event in &events {
                    if let Err(status) = post(http, &url, &secret, event).await {
                        failed = Some(status);
                        break;
                    }
                    after = Position::parse(&event.event_id).unwrap_or(after);
                    sent = true;
                }
                if failed.is_none() {
                    after = next;
                }
                sqlx::query(
                    "UPDATE webhooks SET after_txid = $2::xid8, after_id = $3,
                       delivered_at = CASE WHEN $4 THEN now() ELSE delivered_at END,
                       failing_since = CASE WHEN $5::int IS NOT NULL THEN coalesce(failing_since, now()) END,
                       last_status = $5
                     WHERE id = $1",
                )
                .bind(id)
                .bind(after.txid.to_string())
                .bind(after.id)
                .bind(sent)
                .bind(failed.map(i32::from))
                .execute(&self.pool)
                .await?;
                if failed.is_some() || events.len() < usize::from(BATCH) {
                    break;
                }
            }
        }
        Ok(())
    }
}

#[async_trait]
impl Handler for Deliveries {
    async fn run(&self, _job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        self.tick(tx).await.map_err(|error| error.to_string())
    }
}

/// POSTs `event` to `url`, signed with `secret`; a failure is the status that came, 0 for none.
async fn post(http: &Http, url: &str, secret: &[u8], event: &Event) -> Result<(), u16> {
    let url = target(url).ok_or(0u16)?;
    let body = serde_json::to_vec(event).map_err(|_| 0u16)?;
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let request = Request::post(url.as_str())
        .header(CONTENT_TYPE, "application/json")
        .header("webhook-id", &event.event_id)
        .header("webhook-timestamp", now)
        .header("webhook-signature", sign(secret, &event.event_id, now, &body))
        .body(Full::new(Bytes::from(body)))
        .map_err(|_| 0u16)?;
    match tokio::time::timeout(TIMEOUT, http.request(request)).await {
        Ok(Ok(response)) if response.status().is_success() => Ok(()),
        Ok(Ok(response)) => Err(response.status().as_u16()),
        _ => Err(0),
    }
}

/// The `webhook-signature` of Standard Webhooks: `v1,` and the base64 of the HMAC-SHA256 of `id.timestamp.body`.
fn sign(secret: &[u8], id: &str, timestamp: u64, body: &[u8]) -> String {
    let mut mac = hmac::Context::with_key(&hmac::Key::new(hmac::HMAC_SHA256, secret));
    mac.update(format!("{id}.{timestamp}.").as_bytes());
    mac.update(body);
    format!("v1,{}", STANDARD.encode(mac.sign()))
}

/// Resolves a receiver's name to the addresses a webhook may reach, so that the one connected to is one checked.
#[derive(Clone)]
struct Guarded(fn(IpAddr) -> bool);

impl tower_service::Service<Name> for Guarded {
    type Response = std::vec::IntoIter<SocketAddr>;
    type Error = io::Error;
    type Future = Pin<Box<dyn Future<Output = io::Result<Self::Response>> + Send>>;

    fn poll_ready(&mut self, _: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn call(&mut self, name: Name) -> Self::Future {
        let allows = self.0;
        Box::pin(async move {
            let found = tokio::net::lookup_host((name.as_str(), 0)).await?;
            let allowed: Vec<SocketAddr> = found.filter(|address| allows(address.ip())).collect();
            if allowed.is_empty() {
                Err(io::Error::other("no address a webhook may reach"))
            } else {
                Ok(allowed.into_iter())
            }
        })
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex},
    };

    use axum::http::{HeaderMap, StatusCode};
    use photolib_authz::Role;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };
    use serde_json::Value;
    use uuid::Uuid;

    use super::*;

    type Got = Arc<Mutex<Vec<(HeaderMap, Bytes)>>>;

    /// A receiver on localhost that keeps what each delivery sends and answers it with the next of `statuses`, then
    /// 204; returns its URL and what it got.
    async fn receiver(statuses: &[u16]) -> (String, Got) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://localhost:{}/hook", listener.local_addr().unwrap().port());
        let (got, statuses): (Got, _) = (Got::default(), Arc::new(Mutex::new(VecDeque::from(statuses.to_vec()))));
        let kept = got.clone();
        let hook = move |headers: HeaderMap, body: Bytes| async move {
            kept.lock().unwrap().push((headers, body));
            StatusCode::from_u16(statuses.lock().unwrap().pop_front().unwrap_or(204)).unwrap()
        };
        let app = axum::Router::new().route("/hook", axum::routing::post(hook));
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        (url, got)
    }

    /// One run of the `events` job once what was written has committed, with webhooks on and loopback allowed.
    async fn deliver(pool: &PgPool) {
        testpg::settle(pool).await;
        let deliveries = Deliveries::guarded(pool.clone(), true, |_| true).unwrap();
        deliveries.tick(&mut pool.begin().await.unwrap()).await.unwrap();
    }

    /// The events that `got` received, by their ids.
    fn ids(got: &Got) -> Vec<String> {
        let got = got.lock().unwrap();
        let body = |body: &Bytes| {
            serde_json::from_slice::<Value>(body).unwrap()["eventId"]
                .as_str()
                .unwrap()
                .into()
        };
        got.iter().map(|(_, sent)| body(sent)).collect()
    }

    /// When a webhook last delivered, since when it fails and with what.
    async fn state(pool: &PgPool) -> (bool, bool, Option<i32>) {
        let sql = "SELECT delivered_at IS NOT NULL, failing_since IS NOT NULL, last_status FROM webhooks";
        sqlx::query_as(sql).fetch_one(pool).await.unwrap()
    }

    pub(crate) async fn database() -> PgPool {
        let pool = testpg::database().await.pool;
        upgrade(&pool, &Upgrade::new(&embedded())).await.unwrap();
        pool
    }

    pub(crate) async fn exec(pool: &PgPool, sql: &str, binds: &[Uuid]) {
        let query = binds.iter().fold(sqlx::query(sql), sqlx::query::Query::bind);
        query.execute(pool).await.unwrap();
    }

    pub(crate) async fn user(pool: &PgPool, role: &str) -> Uuid {
        let id = Uuid::now_v7();
        let sql = "INSERT INTO users (id, handle, display_name, role) VALUES ($1, $1::text, 'U', $2)";
        sqlx::query(sql).bind(id).bind(role).execute(pool).await.unwrap();
        id
    }

    pub(crate) async fn library(pool: &PgPool, owner: Uuid, privacy: &str) -> Uuid {
        let id = Uuid::now_v7();
        sqlx::query(
            "INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri) VALUES ($1, $2, 'L', 'managed', $3, '')",
        )
        .bind(id)
        .bind(owner)
        .bind(privacy)
        .execute(pool)
        .await
        .unwrap();
        id
    }

    /// An asset of `library`'s owner named `IMG_<its id>.jpg`, taken in Lisbon.
    pub(crate) async fn asset(pool: &PgPool, library: Uuid) -> Uuid {
        let id = Uuid::now_v7();
        exec(
            pool,
            "INSERT INTO assets (id, library_id, owner_id, original_filename, source, media_kind, lat, lon)
             SELECT $1, id, owner_id, 'IMG_' || $1::text || '.jpg', 'upload', 'image', 38.71, -9.14
             FROM libraries WHERE id = $2",
            &[id, library],
        )
        .await;
        id
    }

    /// Every event `who` reads, a page of `limit` at a time, as (type, asset).
    async fn read(pool: &PgPool, who: Principal, limit: u16) -> Vec<(EventType, Uuid)> {
        testpg::settle(pool).await;
        let (mut after, mut all) = (Position::default(), vec![]);
        loop {
            let (events, next) = page(pool, who, after, limit).await.unwrap();
            assert!(next > after, "{next} moves on from {after}");
            let done = events.len() < usize::from(limit);
            all.extend(
                events
                    .iter()
                    .map(|e| (e.r#type.as_known().unwrap(), e.asset_id.parse().unwrap())),
            );
            after = next;
            if done {
                return all;
            }
        }
    }

    #[tokio::test]
    async fn an_account_reads_what_happens_to_what_it_may_view_in_standard_libraries_only() {
        use EventType::*;
        let pool = database().await;
        let (ann, bob, cyd) = (
            user(&pool, "user").await,
            user(&pool, "user").await,
            user(&pool, "user").await,
        );
        let (photos, private) = (
            library(&pool, ann, "standard").await,
            library(&pool, ann, "private").await,
        );
        exec(
            &pool,
            "INSERT INTO library_members VALUES ($1, $2, 'viewer')",
            &[photos, bob],
        )
        .await;
        let (shown, locked, gone) = (
            asset(&pool, photos).await,
            asset(&pool, photos).await,
            asset(&pool, photos).await,
        );
        let sealed = asset(&pool, private).await;
        exec(&pool, "UPDATE assets SET locked = true WHERE id = $1", &[locked]).await;
        exec(
            &pool,
            "UPDATE assets SET trashed_at = now() WHERE id IN ($1, $2)",
            &[shown, sealed],
        )
        .await;
        exec(&pool, "UPDATE assets SET rating = 5 WHERE id = $1", &[shown]).await;
        exec(&pool, "UPDATE assets SET trashed_at = NULL WHERE id = $1", &[shown]).await;
        exec(&pool, "DELETE FROM assets WHERE id IN ($1, $2)", &[gone, sealed]).await;

        let as_ann = read(&pool, Principal::User(ann, Role::User), 2).await;
        let expected = [
            (EVENT_TYPE_ASSET_CREATED, shown),
            (EVENT_TYPE_ASSET_TRASHED, shown),
            (EVENT_TYPE_ASSET_RESTORED, shown),
            (EVENT_TYPE_ASSET_DELETED, gone),
        ];
        assert_eq!(
            as_ann, expected,
            "nothing of the private library, the rating or what she locked"
        );
        let as_bob = read(&pool, Principal::User(bob, Role::User), 100).await;
        let expected = [
            (EVENT_TYPE_ASSET_CREATED, shown),
            (EVENT_TYPE_ASSET_TRASHED, shown),
            (EVENT_TYPE_ASSET_RESTORED, shown),
            (EVENT_TYPE_ASSET_DELETED, gone),
        ];
        assert_eq!(
            as_bob, expected,
            "a member sees neither the locked asset nor the deleted one's creation"
        );
        assert_eq!(read(&pool, Principal::User(cyd, Role::User), 100).await, []);
        assert_eq!(read(&pool, Principal::Anonymous, 100).await, []);
    }

    #[tokio::test]
    async fn a_cursor_never_skips_an_event_whose_transaction_ends_later() {
        let pool = database().await;
        let ann = user(&pool, "user").await;
        let photos = library(&pool, ann, "standard").await;
        let who = Principal::User(ann, Role::User);
        let mut open = pool.begin().await.unwrap();
        let first = Uuid::now_v7();
        sqlx::query("INSERT INTO assets (id, library_id, owner_id, source) VALUES ($1, $2, $3, 'upload')")
            .bind(first)
            .bind(photos)
            .bind(ann)
            .execute(&mut *open)
            .await
            .unwrap();
        let second = asset(&pool, photos).await;
        let (events, after) = page(&pool, who, Position::default(), 10).await.unwrap();
        assert!(
            events.is_empty(),
            "the later transaction waits for the earlier one: {events:?}"
        );
        open.commit().await.unwrap();
        testpg::settle(&pool).await;
        let (events, _) = page(&pool, who, after, 10).await.unwrap();
        let assets: Vec<String> = events.into_iter().map(|e| e.asset_id).collect();
        assert_eq!(assets, [first.to_string(), second.to_string()]);
    }

    #[test]
    fn a_signature_matches_the_standard_webhooks_reference() {
        let vector = STANDARD.decode("MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw").unwrap();
        let body = br#"{"test": 2432232314}"#;
        assert_eq!(
            sign(&vector, "msg_p5jXN8AQM9LWM0D4loKWxJek", 1_614_265_330, body),
            "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="
        );
    }

    #[tokio::test]
    async fn a_delivery_is_signed_and_carries_ids_only_and_nothing_of_a_private_library() {
        let pool = database().await;
        let ann = user(&pool, "user").await;
        let (photos, private) = (
            library(&pool, ann, "standard").await,
            library(&pool, ann, "private").await,
        );
        let (url, got) = receiver(&[]).await;
        let (_, secret) = create(&pool, ann, &url).await.unwrap();
        let shown = asset(&pool, photos).await;
        let sealed = asset(&pool, private).await;
        exec(
            &pool,
            "UPDATE assets SET trashed_at = now(), meta_core = '\\x5345414c4544' WHERE id = $1",
            &[sealed],
        )
        .await;
        exec(&pool, "DELETE FROM assets WHERE id = $1", &[sealed]).await;
        deliver(&pool).await;

        let got = got.lock().unwrap().clone();
        assert_eq!(
            got.len(),
            1,
            "the standard library's one event, none of the private one's three"
        );
        let (headers, body) = &got[0];
        let event: Value = serde_json::from_slice(body).unwrap();
        let mut fields: Vec<&str> = event.as_object().unwrap().keys().map(String::as_str).collect();
        fields.sort_unstable();
        assert_eq!(fields, ["assetId", "eventId", "libraryId", "recordedAt", "type"]);
        assert_eq!(event["type"], "EVENT_TYPE_ASSET_CREATED");
        assert_eq!(
            (&event["assetId"], &event["libraryId"]),
            (&shown.to_string().into(), &photos.to_string().into())
        );
        let text = String::from_utf8_lossy(body);
        for leak in [
            sealed.to_string(),
            private.to_string(),
            "IMG_".into(),
            "38.71".into(),
            "SEALED".into(),
        ] {
            assert!(!text.contains(&leak), "{leak} in {text}");
        }
        assert_eq!(headers[CONTENT_TYPE], "application/json");
        assert_eq!(headers["webhook-id"], event["eventId"].as_str().unwrap());
        let sent: u64 = headers["webhook-timestamp"].to_str().unwrap().parse().unwrap();
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
        assert!(now.abs_diff(sent) < 60, "{sent} is now");
        let key = STANDARD.decode(secret.strip_prefix("whsec_").unwrap()).unwrap();
        let signed = sign(&key, event["eventId"].as_str().unwrap(), sent, body);
        assert_eq!(
            headers["webhook-signature"],
            signed.as_str(),
            "under the secret shown at creation"
        );
        assert_eq!(state(&pool).await, (true, false, None));
    }

    #[tokio::test]
    async fn a_receiver_that_fails_gets_the_same_events_again_in_order_and_nothing_reaches_this_machine() {
        let pool = database().await;
        let ann = user(&pool, "user").await;
        let photos = library(&pool, ann, "standard").await;
        let (url, got) = receiver(&[503]).await;
        create(&pool, ann, &url).await.unwrap();
        asset(&pool, photos).await;
        asset(&pool, photos).await;
        deliver(&pool).await;
        let first = ids(&got);
        assert_eq!(first.len(), 1, "the first refused, the second waits");
        assert_eq!(state(&pool).await, (false, true, Some(503)));
        deliver(&pool).await;
        let all = ids(&got);
        assert_eq!(
            (all.len(), &all[..2]),
            (3, &[first[0].clone(), first[0].clone()][..]),
            "{all:?}"
        );
        assert!(Position::parse(&all[1]) < Position::parse(&all[2]), "in order: {all:?}");
        assert_eq!(state(&pool).await, (true, false, None));
        deliver(&pool).await;
        assert_eq!(ids(&got).len(), 3, "nothing twice once delivered");

        asset(&pool, photos).await;
        testpg::settle(&pool).await;
        let guarded = Deliveries::new(pool.clone(), true).unwrap();
        guarded.tick(&mut pool.begin().await.unwrap()).await.unwrap();
        assert_eq!(
            ids(&got).len(),
            3,
            "localhost resolves to no address a webhook may reach"
        );
        assert_eq!(state(&pool).await, (true, true, Some(0)));
    }

    #[tokio::test]
    async fn an_event_dated_2100_is_delivered_and_kept_while_week_old_ones_are_purged() {
        let pool = database().await;
        let ann = user(&pool, "user").await;
        let photos = library(&pool, ann, "standard").await;
        let (url, got) = receiver(&[]).await;
        create(&pool, ann, &url).await.unwrap();
        let (old, future) = (asset(&pool, photos).await, asset(&pool, photos).await);
        exec(
            &pool,
            "UPDATE events SET at = now() - interval '8 days' WHERE asset_id = $1",
            &[old],
        )
        .await;
        exec(
            &pool,
            "UPDATE events SET at = '2100-01-01' WHERE asset_id = $1",
            &[future],
        )
        .await;
        testpg::settle(&pool).await;
        let off = Deliveries::new(pool.clone(), false).unwrap();
        let mut held = pool.begin().await.unwrap();
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended('webhooks', 0))")
            .execute(&mut *held)
            .await
            .unwrap();
        let on = Deliveries::guarded(pool.clone(), true, |_| true).unwrap();
        on.tick(&mut pool.begin().await.unwrap()).await.unwrap();
        off.tick(&mut pool.begin().await.unwrap()).await.unwrap();
        assert!(
            ids(&got).is_empty(),
            "off, or while another run delivers, nothing goes out"
        );
        let kept: Vec<Uuid> = sqlx::query_scalar("SELECT asset_id FROM events")
            .fetch_all(&pool)
            .await
            .unwrap();
        assert_eq!(kept, [future], "the week-old event is purged, the one of 2100 kept");
        held.commit().await.unwrap();
        deliver(&pool).await;
        let got = got.lock().unwrap();
        let event: Value = serde_json::from_slice(&got[0].1).unwrap();
        assert_eq!(
            (got.len(), &event["recordedAt"]),
            (1, &Value::from("2100-01-01T00:00:00Z"))
        );
    }
}
