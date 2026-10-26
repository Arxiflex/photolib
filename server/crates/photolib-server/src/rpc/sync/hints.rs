//! Real-time hints (design 05 §9, design 16 §2, ADR-0225): `GET /events?streams=<name>,…` holds a Server-Sent Events
//! channel on which a device in the foreground learns which of the streams it follows advanced, so that it syncs. An
//! event's data is stream names, one a line, never what changed: the first names those the caller may read, which may
//! have advanced since its last sync, and each later one those a change advanced since, found as the watermark moves.

use std::{convert::Infallible, sync::Arc, time::Duration};

use axum::{
    extract::{RawQuery, State},
    http::{HeaderMap, HeaderValue},
    response::{
        IntoResponse, Response,
        sse::{Event, KeepAlive, Sse},
    },
    routing::get,
};
use connectrpc::{ConnectError, ErrorCode};
use futures::{StreamExt, stream};
use photolib_authz::{Action, Principal, Resource, can};
use photolib_db::sync::{self as capture, Cursor};
use tokio::time::{Interval, MissedTickBehavior};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use super::{MAX_STREAMS, Reader, Sync, named, parts};
use crate::{
    rpc::{ApiError, Users, users::internal},
    uploads::connect,
};

/// How often an open channel reads the watermark.
const TICK: Duration = Duration::from_millis(250);
/// How often a quiet channel sends a comment: within the apps' 30 s timeout and the idle limits of proxies.
const KEEP_ALIVE: Duration = Duration::from_secs(15);

struct Hints {
    sync: Sync,
    users: Arc<Users>,
    shutdown: CancellationToken,
}

/// An open channel: who follows which streams, and the watermark below which it has looked for changes.
struct Channel {
    hints: Arc<Hints>,
    who: Principal,
    me: Uuid,
    streams: Vec<String>,
    since: u64,
    ticks: Interval,
}

/// `GET /events` for the accounts of `users` in `epoch`; its channels end at `shutdown`.
pub fn router(epoch: String, users: Arc<Users>, shutdown: CancellationToken) -> axum::Router {
    let sync = Sync::new(users.accounts.pool().clone(), epoch);
    let hints = Hints { sync, users, shutdown };
    axum::Router::new()
        .route("/events", get(events))
        .with_state(Arc::new(hints))
}

async fn events(State(hints): State<Arc<Hints>>, RawQuery(query): RawQuery, headers: HeaderMap) -> Response {
    let opened = hints.open(&query.unwrap_or_default(), &headers).await;
    opened.unwrap_or_else(connect)
}

impl Hints {
    /// A channel for the caller of `headers` that follows the streams `query` names.
    async fn open(self: Arc<Self>, query: &str, headers: &HeaderMap) -> Result<Response, ConnectError> {
        let who = self.users.principal(headers).await?;
        let who = who.ok_or_else(|| ApiError::new(ErrorCode::PermissionDenied, "second_factor.required"))?;
        let (Principal::User(me, _) | Principal::Key(me, ..)) = who else {
            return Err(ApiError::new(ErrorCode::Unauthenticated, "session.required").into());
        };
        let streams: Vec<String> = url::form_urlencoded::parse(query.as_bytes())
            .filter(|(key, _)| key == "streams")
            .flat_map(|(_, names)| names.split(',').map(str::to_string).collect::<Vec<_>>())
            .filter(|name| !name.is_empty())
            .collect();
        if streams.len() > MAX_STREAMS {
            return Err(ApiError::new(ErrorCode::InvalidArgument, "field.invalid")
                .param("field", "streams")
                .into());
        }
        let since = capture::watermark(&self.sync.pool).await.map_err(internal)?.0;
        let streams = self.sync.readable(who, streams).await.map_err(internal)?;
        let first = Event::default().data(streams.join("\n"));
        let mut ticks = tokio::time::interval(TICK);
        ticks.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let channel = Channel {
            hints: self,
            who,
            me,
            streams,
            since,
            ticks,
        };
        let events = stream::once(async { first }).chain(stream::unfold(channel, Channel::next));
        let mut response = Sse::new(events.map(Ok::<_, Infallible>))
            .keep_alive(KeepAlive::new().interval(KEEP_ALIVE))
            .into_response();
        // Nginx passes events on as they come, whatever else its configuration buffers.
        (response.headers_mut()).insert("x-accel-buffering", HeaderValue::from_static("no"));
        Ok(response)
    }
}

impl Channel {
    /// The next hint: the streams that the next change advanced. None once photolibd stops or the database fails, and
    /// the device opens a channel again.
    async fn next(mut self) -> Option<(Event, Self)> {
        loop {
            tokio::select! {
                _ = self.ticks.tick() => {}
                () = self.hints.shutdown.cancelled() => return None,
            }
            let sync = &self.hints.sync;
            let below = match capture::watermark(&sync.pool).await {
                Ok((below, _)) if below > self.since => below,
                Ok(_) => continue,
                Err(error) => {
                    tracing::warn!(%error, "a hints channel cannot read the watermark");
                    return None;
                }
            };
            match sync.advanced(self.who, self.me, &self.streams, self.since, below).await {
                Ok(advanced) if advanced.is_empty() => self.since = below,
                Ok(advanced) => {
                    self.since = below;
                    return Some((Event::default().data(advanced.join("\n")), self));
                }
                Err(error) => {
                    tracing::warn!(%error, "a hints channel cannot read the changes");
                    return None;
                }
            }
        }
    }
}

impl Sync {
    /// Those of `streams` that `who` may read.
    async fn readable(&self, who: Principal, streams: Vec<String>) -> sqlx::Result<Vec<String>> {
        let mut readable = vec![];
        for name in streams {
            if let Some((stream, _)) = named(&name)
                && can(&self.pool, who, Action::View, Resource::Stream(stream)).await?
            {
                readable.push(name);
            }
        }
        Ok(readable)
    }

    /// Those of `streams` that a change between the watermarks `since` and `below` advanced and `who` may read.
    async fn advanced(
        &self,
        who: Principal,
        me: Uuid,
        streams: &[String],
        since: u64,
        below: u64,
    ) -> sqlx::Result<Vec<String>> {
        let columns = self.columns().await?;
        let after = Cursor {
            txid: since,
            key: String::new(),
        };
        let mut advanced = vec![];
        for name in streams {
            let Some((stream, of)) = named(name) else { continue };
            let reader = Reader { who, me, of };
            for part in parts(stream) {
                let Some(columns) = columns.get(part.table) else {
                    continue;
                };
                let read = reader.read(part, columns);
                if !capture::changes(&self.pool, &read, &after, below, 1).await?.is_empty() {
                    if can(&self.pool, who, Action::View, Resource::Stream(stream)).await? {
                        advanced.push(name.clone());
                    }
                    break;
                }
            }
        }
        Ok(advanced)
    }
}

#[cfg(test)]
mod tests {
    use photolib_authz::Role;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg::{self, TestDb},
    };
    use serde_json::json;
    use sqlx::PgPool;
    use tower::ServiceExt;

    use super::*;
    use crate::{
        accounts::Accounts,
        keys::ApiKeys,
        testing::{BearerSessions, connect_error},
    };

    /// The world of the authz matrix (Ann owns L1, L2 and A1, which shows b1 of L2; vic is a member of L1 and A1).
    async fn world() -> TestDb {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        exec(&db.pool, include_str!("../../../../photolib-authz/tests/world.sql")).await;
        db
    }

    async fn exec(pool: &PgPool, sql: &str) {
        sqlx::raw_sql(sql).execute(pool).await.unwrap();
        testpg::settle(pool).await;
    }

    async fn id(pool: &PgPool, name: &str) -> Uuid {
        let id: String = sqlx::query_scalar("SELECT md5($1)::uuid::text")
            .bind(name)
            .fetch_one(pool)
            .await
            .unwrap();
        id.parse().unwrap()
    }

    /// Stream names with world names (`assets/L2`) as their ids.
    async fn streams(pool: &PgPool, names: &[&str]) -> Vec<String> {
        let mut streams = vec![];
        for name in names {
            streams.push(match name.split_once('/') {
                Some((kind, world)) => format!("{kind}/{}", id(pool, world).await),
                None => (*name).into(),
            });
        }
        streams
    }

    #[tokio::test]
    async fn a_change_dated_2100_advances_the_streams_that_carry_it_for_those_who_may_read_them() {
        let db = world().await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let names = [
            "account",
            "tags",
            "assets/L1",
            "assets/L2",
            "album_items/A1",
            "assets/b1",
            "nonsense",
        ];
        let followed = streams(&db.pool, &names).await;
        let since = capture::watermark(&db.pool).await.unwrap().0;
        exec(
            &db.pool,
            "UPDATE assets SET taken_utc = '2100-01-01Z' WHERE id = md5('b1')::uuid;
             UPDATE users SET display_name = 'Ann B' WHERE id = md5('ann')::uuid",
        )
        .await;
        let below = capture::watermark(&db.pool).await.unwrap().0;
        let (ann, vic) = (id(&db.pool, "ann").await, id(&db.pool, "vic").await);
        let advanced = |who, me, since| {
            let (sync, followed) = (&sync, &followed);
            async move { sync.advanced(who, me, followed, since, below).await.unwrap() }
        };
        let ann_advanced = advanced(Principal::User(ann, Role::User), ann, since).await;
        assert_eq!(
            ann_advanced,
            streams(&db.pool, &["account", "assets/L2", "album_items/A1"]).await
        );
        let vic_advanced = advanced(Principal::User(vic, Role::User), vic, since).await;
        assert_eq!(
            vic_advanced,
            streams(&db.pool, &["album_items/A1"]).await,
            "vic may not read L2"
        );
        assert!(
            advanced(Principal::User(ann, Role::User), ann, below).await.is_empty(),
            "nothing since"
        );
    }

    /// The API of the world with its hints, whose channels end at `shutdown`.
    async fn api(db: &TestDb, shutdown: &CancellationToken) -> axum::Router {
        let (accounts, keys) = (Accounts::new(db.pool.clone()), ApiKeys::new(db.pool.clone()));
        let users = Arc::new(Users::start(accounts, keys, Arc::new(BearerSessions)).await.unwrap());
        let api = crate::rpc::api("e".into(), Some(users.clone()), None, None);
        api.merge(router("e".into(), users, shutdown.clone()))
    }

    #[tokio::test]
    async fn a_channel_needs_a_signed_in_account_and_at_most_1000_streams() {
        let db = world().await;
        let app = api(&db, &CancellationToken::new()).await;
        let ann = id(&db.pool, "ann").await.to_string();
        let refusal = |bearer: Option<&str>, streams: String| {
            let mut request = axum::http::Request::get(format!("/events?streams={streams}"));
            if let Some(bearer) = bearer {
                request = request.header("authorization", format!("Bearer {bearer}"));
            }
            let app = app.clone();
            async move {
                let response = app
                    .oneshot(request.body(axum::body::Body::empty()).unwrap())
                    .await
                    .unwrap();
                let status = response.status();
                let body = axum::body::to_bytes(response.into_body(), 1 << 16).await.unwrap();
                (status.as_u16(), connect_error(&serde_json::from_slice(&body).unwrap()))
            }
        };
        assert_eq!(
            refusal(None, "account".into()).await,
            (401, json!({ "code": "unauthenticated", "reason": "session.required" }))
        );
        let many = vec!["tags"; 1001].join(",");
        assert_eq!(
            refusal(Some(&ann), many).await,
            (
                400,
                json!({ "code": "invalid_argument", "reason": "field.invalid", "field": "streams" })
            )
        );
    }
}
