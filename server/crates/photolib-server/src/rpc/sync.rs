//! The sync service (design 05 §3–4, ADR-0091): the streams of an account, each a set of tables read through
//! `photolib_db::sync` and filtered by `photolib_authz`. A stream's opaque cursor holds the epoch and, per table, the
//! last `(txid, key)` read; an empty one starts with a snapshot, newest assets first, that hands over to the log at
//! the watermark it began at. `CheckHashes` tells a backup what the caller's libraries already hold (ADR-0092).

use std::{
    collections::BTreeMap,
    sync::{Arc, OnceLock},
};

use connectrpc::{ConnectError, ErrorCode, RequestContext, Response, ServiceRequest, ServiceResult, ServiceStream};
use futures::{SinkExt, channel::mpsc::Sender};
use photolib_authz::{Action, Kind, Principal, Resource, Stream, can, scope};
use photolib_db::sync::{self as capture, Change, Columns, Cursor, Read, Taken, Value};
use photolib_proto::{
    connect::photolib::api::v1::SyncService,
    proto::photolib::{
        api::v1::{
            CheckHashesRequest, CheckHashesResponse, Confirmation, EmptyTrashRequest, EmptyTrashResponse,
            GetTimelineSummaryRequest, GetTimelineSummaryResponse, PushMutationsRequest, PushMutationsResponse,
            SyncRequest, SyncResponse, TimelineDay,
        },
        sync::v1::{self as pb, __buffa::oneof::value::Kind as Of, Row, Rows, StreamCursor, StreamStatus, SyncBatch},
    },
};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Postgres, QueryBuilder};
use uuid::Uuid;

use super::{ApiError, authz::principal, users::internal};
use crate::dedup;

mod hints;
pub use hints::router as hints;
mod mutations;
mod versions;

/// Rows per page of a table, and assets per page of a snapshot.
const PAGE: i64 = 1000;
/// The streams one call may name.
const MAX_STREAMS: usize = 1000;
/// The most hashes one request may ask about.
const MAX_HASHES: usize = 1000;
/// The most mutations one request may push.
const MAX_MUTATIONS: usize = 500;

/// A table of a stream. `rows` and `tombstones` are SQL on the row `t` and on the tombstone's `scope`, with `$me` the
/// caller and `$of` the stream's id. `keep` drops the rows outside the caller's scope of a kind, `show` turns those
/// into deletions; each names the column with the id. `with` sends along, for every row sent, the rows of another
/// table of the stream whose column is one of this row's: `(table, its column, this column)`.
#[derive(Clone, Copy)]
struct Part {
    table: &'static str,
    rows: &'static str,
    tombstones: Option<&'static str>,
    keep: Option<(Kind, &'static str)>,
    show: Option<(Kind, &'static str)>,
    with: &'static [(&'static str, &'static str, &'static str)],
}

const fn part(table: &'static str, rows: &'static str, tombstones: &'static str) -> Part {
    Part {
        table,
        rows,
        tombstones: Some(tombstones),
        keep: None,
        show: None,
        with: &[],
    }
}

/// A table of the caller's own rows.
const fn mine(table: &'static str, rows: &'static str) -> Part {
    part(table, rows, "scope = $me")
}

/// A table of what hangs off an asset, found by its asset and seen with it.
const fn of_assets(table: &'static str, rows: &'static str, tombstones: &'static str) -> Part {
    Part {
        show: Some((Kind::Asset, "asset_id")),
        ..part(table, rows, tombstones)
    }
}

const FILES: &[(&str, &str, &str)] = &[
    ("asset_files", "asset_id", "id"),
    ("versions", "asset_id", "id"),
    ("asset_custom_values", "asset_id", "id"),
];
// What hangs off an asset belongs to the stream of its asset, looked up by key for each row, so that a page of changes
// never reads a whole library.
const IN_LIBRARY: &str = "(SELECT a.library_id FROM assets a WHERE a.id = t.asset_id) = $of";
const OF_LIBRARY: &str = "(SELECT a.library_id FROM assets a WHERE a.id = scope) = $of";
// Albums and partner shares carry photos and videos only, never other files (ADR-0066).
const IN_ALBUM: &str = "t.asset_id IN (SELECT i.asset_id FROM album_items i
    JOIN assets a ON a.id = i.asset_id AND a.media_kind IS NOT NULL WHERE i.album_id = $of)";
const OF_ALBUM: &str = "scope IN (SELECT asset_id FROM album_items WHERE album_id = $of)";
// A partner's stream holds the assets of the owner's own libraries only.
const OF_PARTNER: &str = "(SELECT l.owner_id FROM assets a JOIN libraries l ON l.id = a.library_id
    WHERE a.id = t.asset_id AND a.owner_id = $of AND a.media_kind IS NOT NULL) = $of";
const BY_PARTNER: &str = "(SELECT l.owner_id FROM assets a JOIN libraries l ON l.id = a.library_id
    WHERE a.id = scope AND a.owner_id = $of) = $of";
const MY_ALBUMS: &str = "t.album_id IN (SELECT id FROM albums WHERE owner_id = $me)";
const OF_MY_ALBUMS: &str = "scope IN (SELECT id FROM albums WHERE owner_id = $me)";

const ACCOUNT: &[Part] = &[
    mine("users", "t.id = $me"),
    mine("user_keys", "t.user_id = $me"),
    mine("devices", "t.user_id = $me"),
    mine("processing_grants", "t.user_id = $me"),
    mine("asset_user_state", "t.user_id = $me"),
    mine("album_user_state", "t.user_id = $me"),
    mine("library_user_state", "t.user_id = $me"),
];
/// Memberships and shares: a device opens the streams they give access to, from scratch.
const LIBRARIES: &[Part] = &[
    Part {
        keep: Some((Kind::Library, "id")),
        ..mine("libraries", "true")
    },
    mine("library_members", "t.user_id = $me"),
    mine("partner_shares", "t.partner_id = $me"),
];
const ALBUMS: &[Part] = &[
    mine("album_folders", "t.owner_id = $me"),
    Part {
        keep: Some((Kind::Album, "id")),
        ..mine("albums", "true")
    },
    mine("album_members", "t.user_id = $me"),
    part("links", MY_ALBUMS, OF_MY_ALBUMS),
    part("album_items", MY_ALBUMS, OF_MY_ALBUMS),
];
const ASSETS: &[Part] = &[
    Part {
        show: Some((Kind::Asset, "id")),
        with: FILES,
        ..part("assets", "t.library_id = $of", "scope = $of")
    },
    of_assets("asset_files", IN_LIBRARY, OF_LIBRARY),
    of_assets("versions", IN_LIBRARY, OF_LIBRARY),
    of_assets("asset_custom_values", IN_LIBRARY, OF_LIBRARY),
    part("custom_fields", "t.library_id = $of", "scope = $of"),
];
/// An album's items bring their assets, whose deletion is the item's; an item of a file that is no photo or video
/// stays out of the shared album.
const ALBUM_ITEMS: &[Part] = &[
    Part {
        with: &[("assets", "id", "asset_id")],
        ..part(
            "album_items",
            "t.album_id = $of
             AND (t.asset_id IS NULL OR (SELECT a.media_kind FROM assets a WHERE a.id = t.asset_id) IS NOT NULL)",
            "scope = $of",
        )
    },
    Part {
        tombstones: None,
        show: Some((Kind::Asset, "id")),
        with: FILES,
        ..part(
            "assets",
            "t.id IN (SELECT asset_id FROM album_items WHERE album_id = $of) AND t.media_kind IS NOT NULL",
            "",
        )
    },
    of_assets("asset_files", IN_ALBUM, OF_ALBUM),
    of_assets("versions", IN_ALBUM, OF_ALBUM),
    of_assets("asset_custom_values", IN_ALBUM, OF_ALBUM),
];
/// What the owner `$of` shares with the caller: the assets of the owner's libraries taken in the share's window, and
/// private libraries whole.
const PARTNER: &[Part] = &[
    Part {
        show: Some((Kind::Asset, "id")),
        with: FILES,
        ..part(
            "assets",
            "t.owner_id = $of AND t.media_kind IS NOT NULL AND t.library_id IN (SELECT id FROM libraries WHERE owner_id = $of)
             AND EXISTS (SELECT FROM partner_shares p WHERE p.owner_id = $of AND p.partner_id = $me
                 AND (p.taken_since IS NULL OR t.taken_utc >= p.taken_since
                     OR (SELECT privacy FROM libraries WHERE id = t.library_id) = 'private'))",
            "scope IN (SELECT id FROM libraries WHERE owner_id = $of)",
        )
    },
    of_assets("asset_files", OF_PARTNER, BY_PARTNER),
    of_assets("versions", OF_PARTNER, BY_PARTNER),
    of_assets("asset_custom_values", OF_PARTNER, BY_PARTNER),
];
const TAGS: &[Part] = &[mine("tags", "t.owner_id = $me")];
const PEOPLE: &[Part] = &[mine("persons", "t.owner_id = $me")];
const USER_PLACES: &[Part] = &[mine("user_places", "t.user_id = $me")];
const MEMORIES: &[Part] = &[mine("memories", "t.owner_id = $me")];
const FACES: &[Part] = &[of_assets("faces", IN_LIBRARY, OF_LIBRARY)];
const ML: &[Part] = &[
    of_assets("asset_embeddings", IN_LIBRARY, OF_LIBRARY),
    of_assets("asset_ocr", IN_LIBRARY, OF_LIBRARY),
    of_assets("asset_quality", IN_LIBRARY, OF_LIBRARY),
    of_assets("asset_ml_labels", IN_LIBRARY, OF_LIBRARY),
];

fn parts(stream: Stream) -> &'static [Part] {
    match stream {
        Stream::Account => ACCOUNT,
        Stream::Libraries => LIBRARIES,
        Stream::Albums => ALBUMS,
        Stream::Tags => TAGS,
        Stream::People => PEOPLE,
        Stream::UserPlaces => USER_PLACES,
        Stream::Memories => MEMORIES,
        Stream::Assets(_) => ASSETS,
        Stream::Faces(_) => FACES,
        Stream::Ml(_) => ML,
        Stream::AlbumItems(_) => ALBUM_ITEMS,
        Stream::Partner(_) => PARTNER,
    }
}

/// Every table of every stream, once.
fn tables() -> Vec<&'static str> {
    let streams = [
        ACCOUNT,
        LIBRARIES,
        ALBUMS,
        ASSETS,
        ALBUM_ITEMS,
        PARTNER,
        TAGS,
        PEOPLE,
        USER_PLACES,
        MEMORIES,
    ];
    let mut tables: Vec<_> = streams
        .into_iter()
        .chain([FACES, ML])
        .flatten()
        .map(|part| part.table)
        .collect();
    tables.sort();
    tables.dedup();
    tables
}

/// Columns no client receives: server paths and settings, storage locations, secrets, what is too big to sync, and
/// which type detection checked an asset.
fn hidden(table: &str) -> &'static [&'static str] {
    match table {
        "libraries" => &["root_uri", "scan_policy", "storage_template"],
        "assets" => &["raw_metadata", "sniff_version"],
        "asset_files" => &["storage", "key"],
        "links" => &["token_hash", "password_hash"],
        "devices" => &["secret_hash"],
        "faces" => &["embedding"],
        _ => &[],
    }
}

/// A stream by its name, and its id.
fn named(name: &str) -> Option<(Stream, Option<Uuid>)> {
    let Some((kind, id)) = name.split_once('/') else {
        let stream = match name {
            "account" => Stream::Account,
            "libraries" => Stream::Libraries,
            "albums" => Stream::Albums,
            "tags" => Stream::Tags,
            "people" => Stream::People,
            "user_places" => Stream::UserPlaces,
            "memories" => Stream::Memories,
            _ => return None,
        };
        return Some((stream, None));
    };
    let id: Uuid = id
        .parse()
        .ok()
        .filter(|id: &Uuid| id.to_string() == name[kind.len() + 1..])?;
    let stream = match kind {
        "assets" => Stream::Assets(id),
        "faces" => Stream::Faces(id),
        "ml" => Stream::Ml(id),
        "album_items" => Stream::AlbumItems(id),
        "partner" => Stream::Partner(id),
        _ => return None,
    };
    Some((stream, Some(id)))
}

/// What a stream's cursor holds.
#[derive(Default, Serialize, Deserialize)]
struct Position {
    epoch: String,
    /// Per table, the last `(txid, key)` read; a table missing here starts from scratch.
    tables: BTreeMap<String, (u64, String)>,
    /// While the newest-first snapshot of the stream's assets runs: the watermark it hands over at, and where it is.
    snapshot: Option<(u64, Option<Taken>)>,
}

/// The columns of every table of every stream.
type Tables = BTreeMap<&'static str, Arc<Columns>>;

#[derive(Clone)]
pub struct Sync {
    pool: PgPool,
    epoch: Arc<str>,
    columns: Arc<OnceLock<Arc<Tables>>>,
}

/// Who reads which stream.
#[derive(Clone, Copy)]
struct Reader {
    who: Principal,
    me: Uuid,
    of: Option<Uuid>,
}

type Batches = Sender<Result<SyncResponse, ConnectError>>;

impl Sync {
    pub fn new(pool: PgPool, epoch: String) -> Self {
        Sync {
            pool,
            epoch: epoch.into(),
            columns: Arc::default(),
        }
    }

    /// The columns of every table of every stream, read once.
    async fn columns(&self) -> sqlx::Result<Arc<Tables>> {
        if let Some(columns) = self.columns.get() {
            return Ok(columns.clone());
        }
        let mut all = BTreeMap::new();
        for table in tables() {
            let entity = capture::find(table).expect("a synced table");
            let columns = capture::columns(&self.pool, entity, hidden(table)).await?;
            all.insert(table, Arc::new(columns));
        }
        Ok(self.columns.get_or_init(|| Arc::new(all)).clone())
    }

    /// Sends the batches of one stream, ending with the one that has caught up.
    async fn stream(&self, who: Principal, me: Uuid, cursor: StreamCursor, out: &mut Batches) -> sqlx::Result<()> {
        let mut batch = SyncBatch {
            stream: cursor.stream.clone(),
            status: StreamStatus::STREAM_STATUS_OK.into(),
            caught_up: true,
            ..Default::default()
        };
        let Some((stream, of)) = named(&cursor.stream) else {
            batch.status = StreamStatus::STREAM_STATUS_FORBIDDEN.into();
            return send(out, batch).await;
        };
        if !can(&self.pool, who, Action::View, Resource::Stream(stream)).await? {
            batch.status = StreamStatus::STREAM_STATUS_FORBIDDEN.into();
            return send(out, batch).await;
        }
        let parts = parts(stream);
        let Some(mut at) = self.position(parts, &cursor.cursor).await? else {
            batch.status = StreamStatus::STREAM_STATUS_RESET_REQUIRED.into();
            return send(out, batch).await;
        };
        let reader = Reader { who, me, of };
        let columns = self.columns().await?;
        while let Some((watermark, after)) = at.snapshot.clone() {
            let read = reader.read(&parts[0], &columns[parts[0].table]);
            let (page, next) = capture::newest(&self.pool, &read, after.as_ref(), PAGE).await?;
            at.snapshot = next.map(|next| (watermark, Some(next)));
            if at.snapshot.is_none() {
                at.tables.insert("assets".into(), (watermark, String::new()));
            }
            let changes = self.with(reader, parts, parts[0], page, &columns).await?;
            let batch = self.batch(&cursor.stream, &at, changes, false);
            send(out, batch).await?;
        }
        let below = capture::watermark(&self.pool).await?.0;
        for part in parts.iter().copied() {
            let read = reader.read(&part, &columns[part.table]);
            loop {
                let (txid, key) = at.tables.get(part.table).cloned().unwrap_or_default();
                let page = capture::changes(&self.pool, &read, &Cursor { txid, key }, below, PAGE).await?;
                let Some(last) = page.last() else { break };
                let full = page.len() as i64 == PAGE;
                at.tables.insert(part.table.into(), (last.txid, last.key.clone()));
                let changes = self.with(reader, parts, part, page, &columns).await?;
                let batch = self.batch(&cursor.stream, &at, changes, false);
                send(out, batch).await?;
                if !full {
                    break;
                }
            }
        }
        let batch = self.batch(&cursor.stream, &at, vec![], true);
        send(out, batch).await
    }

    /// Where `cursor` stands in a stream of `parts`, or `None` when the stream must start again: the cursor is
    /// unreadable or from another epoch, a deletion it has not seen was purged, or it is ahead of the database, which
    /// was then restored.
    async fn position(&self, parts: &'static [Part], cursor: &[u8]) -> sqlx::Result<Option<Position>> {
        if cursor.is_empty() {
            let watermark = capture::watermark(&self.pool).await?.0;
            return Ok(Some(Position::start(parts, &self.epoch, watermark)));
        }
        let Some(at) = serde_json::from_slice::<Position>(cursor)
            .ok()
            .filter(|at| *at.epoch == *self.epoch)
        else {
            return Ok(None);
        };
        let horizon = capture::horizon(&self.pool).await?;
        let ahead = capture::watermark(&self.pool).await?.1;
        Ok((!at.stale(horizon, ahead)).then_some(at))
    }

    /// `changes` of `part` and what goes with the rows it sends, recursively.
    async fn with(
        &self,
        reader: Reader,
        parts: &[Part],
        part: Part,
        changes: Vec<Change>,
        columns: &Tables,
    ) -> sqlx::Result<Vec<(&'static str, Vec<Change>)>> {
        let mut out = vec![];
        let mut queue = vec![(part, changes)];
        while let Some((part, changes)) = queue.pop() {
            let mut reads = vec![];
            for &(table, column, from) in part.with {
                let child = *parts
                    .iter()
                    .find(|part| part.table == table)
                    .expect("a part of the stream");
                let ids = ids(&changes, &columns[part.table], from);
                reads.push((child, reader.read(&child, &columns[table]), column, ids));
            }
            // On connections of their own, at once.
            let found = reads
                .iter()
                .map(|(_, read, column, ids)| capture::linked(&self.pool, read, column, ids));
            let found = futures::future::try_join_all(found).await?;
            queue.extend(reads.into_iter().map(|(child, ..)| child).zip(found));
            out.push((part.table, changes));
        }
        Ok(out)
    }

    /// A batch of `changes`, each table's upserts and deletions in a group of their own.
    fn batch(&self, stream: &str, at: &Position, changes: Vec<(&str, Vec<Change>)>, caught_up: bool) -> SyncBatch {
        let columns = self.columns.get().expect("columns are read before a batch");
        SyncBatch {
            stream: stream.into(),
            status: StreamStatus::STREAM_STATUS_OK.into(),
            changes: groups(columns, changes),
            cursor: serde_json::to_vec(at).expect("a position serialises"),
            caught_up,
            ..Default::default()
        }
    }
}

/// `changes` as rows, each table's upserts and deletions in a group of their own.
fn groups(columns: &Tables, changes: Vec<(&str, Vec<Change>)>) -> Vec<Rows> {
    let mut groups = vec![];
    for (table, changes) in changes {
        let entity = capture::find(table).expect("a synced table");
        let (deleted, upserted): (Vec<Change>, Vec<Change>) = changes.into_iter().partition(|change| change.deleted);
        let key = entity.key.iter().map(|column| column.to_string()).collect();
        let keys = deleted.into_iter().map(|change| {
            let key: serde_json::Value = serde_json::from_str(&change.key).unwrap_or_default();
            let text = |column: &&str| Value::Text(key[*column].as_str().unwrap_or_default().into());
            entity.key.iter().map(text).collect()
        });
        let rows = upserted.into_iter().map(|change| change.values);
        for (columns, rows, deleted) in [
            (columns[table].names.clone(), rows.collect::<Vec<_>>(), false),
            (key, keys.collect(), true),
        ] {
            if !rows.is_empty() {
                let rows = rows.into_iter().map(|values| Row {
                    values: values.into_iter().map(value).collect(),
                    ..Default::default()
                });
                groups.push(Rows {
                    entity: table.into(),
                    columns,
                    rows: rows.collect(),
                    deleted,
                    ..Default::default()
                });
            }
        }
    }
    groups
}

impl Reader {
    /// What this reader takes of `part`.
    fn read(&self, part: &Part, columns: &Arc<Columns>) -> Read {
        let (me, part) = (*self, *part);
        let rows = move |q: &mut QueryBuilder<'_, Postgres>| {
            me.push(q, part.rows);
            if let Some((kind, column)) = part.keep {
                q.push(format!(" AND t.{column} IN ("));
                scope(me.who, Action::View, kind, q);
                q.push(")");
            }
        };
        Read {
            entity: capture::find(part.table).expect("a synced table"),
            columns: columns.clone(),
            rows: Box::new(rows),
            tombstones: part
                .tombstones
                .map(|sql| -> capture::Push { Box::new(move |q| me.push(q, sql)) }),
            visible: part.show.map(|(kind, column)| -> (&str, capture::Push) {
                (column, Box::new(move |q| scope(me.who, Action::View, kind, q)))
            }),
        }
    }

    /// Pushes `sql` with `$me` and `$of` bound.
    fn push(&self, q: &mut QueryBuilder<'_, Postgres>, sql: &str) {
        let mut pieces = sql.split('$');
        q.push(pieces.next().unwrap_or_default());
        for piece in pieces {
            let (id, rest) = match piece.strip_prefix("me") {
                Some(rest) => (self.me, rest),
                None => (
                    self.of.expect("a stream with an id"),
                    piece.strip_prefix("of").expect("$me or $of"),
                ),
            };
            q.push_bind(id.to_string()).push("::uuid").push(rest);
        }
    }
}

impl Position {
    /// A stream from scratch at `watermark`: its assets from a snapshot, what goes with rows from the watermark, the
    /// rest from the start.
    fn start(parts: &[Part], epoch: &str, watermark: u64) -> Position {
        let mut at = Position {
            epoch: epoch.into(),
            ..Default::default()
        };
        for part in parts {
            for (table, ..) in part.with {
                at.tables.insert(table.to_string(), (watermark, String::new()));
            }
        }
        if parts[0].table == "assets" {
            at.snapshot = Some((watermark, None));
        }
        at
    }

    /// Whether a deletion this position has not read was purged at `horizon`, or it is past `ahead`, one past the
    /// newest transaction of the database, which no position read from it can be.
    fn stale(&self, horizon: Option<u64>, ahead: u64) -> bool {
        let snapshot = self.snapshot.iter().map(|(txid, _)| *txid);
        let mut read = self.tables.values().map(|(txid, _)| *txid).chain(snapshot);
        read.any(|txid| txid > 0 && (Some(txid) <= horizon || txid > ahead))
    }
}

/// The ids in the column `name` of `changes`.
fn ids(changes: &[Change], columns: &Columns, name: &str) -> Vec<String> {
    let id = |change: &Change| match change.get(columns, name) {
        Some(Value::Text(id)) => Some(id.clone()),
        _ => None,
    };
    changes.iter().filter_map(id).collect()
}

fn value(value: Value) -> pb::Value {
    pb::Value {
        kind: match value {
            Value::Null => None,
            Value::Text(text) => Some(Of::Text(text)),
            Value::Integer(integer) => Some(Of::Integer(integer)),
            Value::Real(real) => Some(Of::Real(real)),
            Value::Boolean(boolean) => Some(Of::Boolean(boolean)),
            Value::Blob(blob) => Some(Of::Blob(blob)),
        },
        ..Default::default()
    }
}

async fn send(out: &mut Batches, batch: SyncBatch) -> sqlx::Result<()> {
    let response = SyncResponse {
        batch: batch.into(),
        ..Default::default()
    };
    // Fails only once the client went away, which ends the call.
    out.send(Ok(response)).await.map_err(|_| sqlx::Error::PoolClosed)
}

#[allow(refining_impl_trait)]
impl SyncService for Sync {
    async fn sync(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, SyncRequest>,
    ) -> ServiceResult<ServiceStream<SyncResponse>> {
        let (who, me) = principal(&ctx)?;
        let streams = request.to_owned_message().streams;
        if streams.len() > MAX_STREAMS {
            let error = ApiError::new(ErrorCode::InvalidArgument, "field.invalid").param("field", "streams");
            return Err(error.into());
        }
        let (mut out, batches) = futures::channel::mpsc::channel(2);
        let sync = self.clone();
        tokio::spawn(async move {
            for cursor in streams {
                if let Err(error) = sync.stream(who, me, cursor, &mut out).await {
                    if !out.is_closed() {
                        let _ = out.send(Err(internal(error))).await;
                    }
                    return;
                }
            }
        });
        Ok(Response::new(Box::pin(batches)))
    }

    async fn get_timeline_summary(
        &self,
        ctx: RequestContext,
        _request: ServiceRequest<'_, GetTimelineSummaryRequest>,
    ) -> ServiceResult<GetTimelineSummaryResponse> {
        let (who, me) = principal(&ctx)?;
        let reader = Reader { who, me, of: None };
        let mut q = QueryBuilder::new("");
        reader.push(
            &mut q,
            "SELECT t.library_id::text, coalesce(t.taken_local::date, (t.taken_utc AT TIME ZONE 'UTC')::date)::text,
                    count(*)
             FROM assets t JOIN libraries l ON l.id = t.library_id AND l.privacy = 'standard'
             WHERE t.media_kind IS NOT NULL AND NOT t.archived AND NOT t.locked AND t.trashed_at IS NULL AND NOT EXISTS (
                 SELECT FROM library_user_state h
                 WHERE h.user_id = $me AND h.library_id = t.library_id AND h.hide_from_timeline
             ) AND NOT EXISTS (
                 SELECT FROM asset_user_state h
                 WHERE h.user_id = $me AND h.asset_id = t.id AND h.album_hides_timeline
             ) AND ",
        );
        q.push("t.library_id IN (");
        scope(who, Action::View, Kind::Library, &mut q);
        q.push(") AND t.id IN (");
        scope(who, Action::View, Kind::Asset, &mut q);
        q.push(")");
        q.push(" GROUP BY 1, 2 ORDER BY 1, 2 DESC NULLS LAST");
        let rows: Vec<(String, Option<String>, i64)> =
            q.build_query_as().fetch_all(&self.pool).await.map_err(internal)?;
        Ok(GetTimelineSummaryResponse {
            days: rows
                .into_iter()
                .map(|(library_id, date, count)| TimelineDay {
                    library_id,
                    date: date.unwrap_or_default(),
                    count: count as u32,
                    ..Default::default()
                })
                .collect(),
            ..Default::default()
        }
        .into())
    }

    async fn check_hashes(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, CheckHashesRequest>,
    ) -> ServiceResult<CheckHashesResponse> {
        let hashes = request.to_owned_message().hashes;
        if hashes.len() > MAX_HASHES || hashes.iter().any(|hash| hash.len() != 32) {
            let error = ApiError::new(ErrorCode::InvalidArgument, "field.invalid");
            return Err(error.param("field", "hashes").into());
        }
        let (who, me) = principal(&ctx)?;
        let found = dedup::assets(&self.pool, who, me, &hashes).await;
        Ok(CheckHashesResponse {
            asset_ids: (found.map_err(internal)?.into_iter())
                .map(|asset| asset.map(|id| id.to_string()).unwrap_or_default())
                .collect(),
            ..Default::default()
        }
        .into())
    }

    async fn push_mutations(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, PushMutationsRequest>,
    ) -> ServiceResult<PushMutationsResponse> {
        let mutations = request.to_owned_message().mutations;
        if mutations.len() > MAX_MUTATIONS {
            let error = ApiError::new(ErrorCode::InvalidArgument, "field.invalid");
            return Err(error.param("field", "mutations").into());
        }
        let (who, me) = principal(&ctx)?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default();
        let now = i64::try_from(now.as_millis()).unwrap_or(i64::MAX);
        let answer = self.push(who, me, mutations, now).await;
        Ok(answer.map_err(internal)?.into())
    }

    async fn empty_trash(
        &self,
        ctx: RequestContext,
        request: ServiceRequest<'_, EmptyTrashRequest>,
    ) -> ServiceResult<EmptyTrashResponse> {
        let token = request.to_owned_message().confirm_token;
        let (who, me) = principal(&ctx)?;
        let answer = match crate::trash::empty(&self.pool, who, me, &token)
            .await
            .map_err(internal)?
        {
            Ok(queued) => EmptyTrashResponse {
                queued,
                ..Default::default()
            },
            Err(dry) => EmptyTrashResponse {
                held: Confirmation {
                    count: dry.count,
                    total: dry.total,
                    token: dry.token,
                    ..Default::default()
                }
                .into(),
                ..Default::default()
            },
        };
        Ok(answer.into())
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use futures::StreamExt;
    use photolib_authz::Role;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg::{self, TestDb},
    };

    use super::*;

    async fn migrated() -> TestDb {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db
    }

    async fn exec(pool: &PgPool, sql: &str) {
        sqlx::raw_sql(sql).execute(pool).await.unwrap();
    }

    /// The batches of `stream` after `cursor` as `who` reads them.
    async fn read(sync: &Sync, who: Principal, stream: &str, cursor: &[u8]) -> Vec<SyncBatch> {
        let me = match who {
            Principal::User(id, _) | Principal::Key(id, ..) => id,
            _ => Uuid::nil(),
        };
        let cursor = StreamCursor {
            stream: stream.into(),
            cursor: cursor.to_vec(),
            ..Default::default()
        };
        let (mut out, batches) = futures::channel::mpsc::channel(4);
        let send = async move { sync.stream(who, me, cursor, &mut out).await.unwrap() };
        let (_, batches) = tokio::join!(send, batches.collect::<Vec<_>>());
        let batches: Vec<SyncBatch> = batches
            .into_iter()
            .map(|response| response.unwrap().batch.into_option().unwrap())
            .collect();
        assert!(batches.last().unwrap().caught_up, "the last batch has caught up");
        assert_eq!(batches.iter().filter(|batch| batch.caught_up).count(), 1);
        batches
    }

    fn text(value: &pb::Value) -> String {
        match &value.kind {
            Some(Of::Text(text)) => text.clone(),
            Some(Of::Integer(integer)) => integer.to_string(),
            other => format!("{other:?}"),
        }
    }

    /// What a device holds after applying batches: rows by table and key, with their columns.
    #[derive(Default)]
    struct Replica(BTreeMap<(String, String), BTreeMap<String, pb::Value>>);

    impl Replica {
        fn apply(&mut self, batches: &[SyncBatch]) -> Vec<u8> {
            for rows in batches.iter().flat_map(|batch| &batch.changes) {
                let key = capture::find(&rows.entity).unwrap().key;
                for row in &rows.rows {
                    let values: BTreeMap<String, pb::Value> =
                        rows.columns.iter().cloned().zip(row.values.iter().cloned()).collect();
                    let id: Vec<String> = key.iter().map(|column| text(&values[*column])).collect();
                    let id = (rows.entity.clone(), id.join("/"));
                    match rows.deleted {
                        true => self.0.remove(&id),
                        false => self.0.insert(id, values),
                    };
                }
            }
            batches.last().unwrap().cursor.clone()
        }

        /// The keys of `entity` and the txid each was written by.
        fn of(&self, entity: &str) -> BTreeMap<String, String> {
            let rows = self.0.iter().filter(|((table, _), _)| table == entity);
            rows.map(|((_, key), values)| (key.clone(), text(&values["txid"])))
                .collect()
        }
    }

    /// What the database holds: the ids of a query's rows and their txids.
    async fn held(pool: &PgPool, sql: &str, library: &str) -> BTreeMap<String, String> {
        let rows: Vec<(String, String)> = sqlx::query_as(sql).bind(library).fetch_all(pool).await.unwrap();
        rows.into_iter().collect()
    }

    const ASSETS_OF: &str = "SELECT id::text, txid::text FROM assets WHERE library_id = $1::uuid";
    const FILES_OF: &str = "SELECT f.id::text, f.txid::text FROM asset_files f JOIN assets a ON a.id = f.asset_id
                            WHERE a.library_id = $1::uuid";

    /// An account `ann` with a library of `count` assets at 29.97 fps, one file each, taken a minute apart from 2020
    /// with every tenth undated.
    async fn library(count: u32) -> (TestDb, Principal, String) {
        let db = migrated().await;
        exec(
            &db.pool,
            &format!(
                "INSERT INTO users (id, handle, display_name) VALUES (md5('ann')::uuid, 'ann', 'Ann');
                 INSERT INTO libraries (id, owner_id, name, kind, root_uri)
                 VALUES (md5('L')::uuid, md5('ann')::uuid, 'L', 'managed', '/srv/l');
                 INSERT INTO assets (id, library_id, owner_id, source, taken_utc, original_filename, fps)
                 SELECT md5(n::text)::uuid, md5('L')::uuid, md5('ann')::uuid, 'upload',
                     CASE WHEN n % 10 <> 0 THEN '2020-01-01Z'::timestamptz + n * interval '1 minute' END,
                     'IMG_' || n || '.jpg', 29.97
                 FROM generate_series(1, {count}) n;
                 INSERT INTO asset_files (id, asset_id, role, storage, key)
                 SELECT gen_random_uuid(), id, 'original', 'local', 'o/' || id FROM assets;"
            ),
        )
        .await;
        testpg::settle(&db.pool).await;
        let (library, ann) = (id(&db.pool, "L").await, id(&db.pool, "ann").await);
        (db, Principal::User(ann, Role::User), library.to_string())
    }

    #[tokio::test]
    async fn a_snapshot_sends_the_newest_assets_first_with_their_files_and_hands_over_to_the_log() {
        let (db, ann, library) = library(2500).await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let stream = format!("assets/{library}");
        let first = read(&sync, ann, &stream, &[]).await;
        assert_eq!(first.len(), 4, "three pages of assets and the caught-up batch");
        let page = &first[0];
        let assets = page
            .changes
            .iter()
            .find(|rows| rows.entity == "assets" && !rows.deleted)
            .unwrap();
        let at = |name: &str| assets.columns.iter().position(|column| column == name).unwrap();
        let taken: Vec<Option<i64>> = assets
            .rows
            .iter()
            .map(|row| match row.values[at("taken_utc")].kind {
                Some(Of::Integer(taken)) => Some(taken),
                _ => None,
            })
            .collect();
        assert_eq!(taken.len(), 1000);
        assert!(taken.iter().all(Option::is_some), "the dated come first");
        assert!(taken.windows(2).all(|pair| pair[0] > pair[1]), "newest first");
        assert!(
            assets.rows.iter().all(|row| match row.values[at("fps")].kind {
                Some(Of::Real(fps)) => (fps - 29.97).abs() < 0.01,
                _ => false,
            }),
            "each asset with its frame rate"
        );
        let files = page.changes.iter().find(|rows| rows.entity == "asset_files").unwrap();
        assert_eq!(files.rows.len(), 1000, "each asset with its file");
        assert!(!files.columns.contains(&"key".to_string()) && !assets.columns.contains(&"raw_metadata".into()));

        // A device that stopped after the first page resumes once the library has changed under it: an asset it has,
        // one the snapshot has yet to send moved before its position, one deleted and one added.
        let mut replica = Replica::default();
        let cursor = replica.apply(&first[..1]);
        exec(
            &db.pool,
            "UPDATE assets SET title = 'sent' WHERE id = md5('2499')::uuid;
             UPDATE assets SET taken_utc = '2030-01-01Z' WHERE id = md5('1')::uuid;
             DELETE FROM assets WHERE id = md5('2')::uuid;
             INSERT INTO assets (id, library_id, owner_id, source) VALUES (md5('new')::uuid, md5('L')::uuid, md5('ann')::uuid, 'upload');
             INSERT INTO asset_files (id, asset_id, role, storage, key) VALUES (gen_random_uuid(), md5('new')::uuid, 'original', 'local', 'n')",
        )
        .await;
        testpg::settle(&db.pool).await;
        let cursor = replica.apply(&read(&sync, ann, &stream, &cursor).await);
        assert_eq!(replica.of("assets"), held(&db.pool, ASSETS_OF, &library).await);
        assert_eq!(replica.of("asset_files"), held(&db.pool, FILES_OF, &library).await);

        let again = read(&sync, ann, &stream, &cursor).await;
        assert!(
            again.iter().all(|batch| batch.changes.is_empty()),
            "nothing changed since"
        );
        exec(&db.pool, "UPDATE assets SET rating = 5 WHERE id = md5('7')::uuid").await;
        testpg::settle(&db.pool).await;
        let one = read(&sync, ann, &stream, &again[0].cursor).await;
        let sent: Vec<(&str, usize)> = one[0]
            .changes
            .iter()
            .map(|rows| (rows.entity.as_str(), rows.rows.len()))
            .collect();
        assert_eq!(
            sent,
            [("assets", 1), ("asset_files", 1)],
            "the change, with what goes with it"
        );
        replica.apply(&one);
        assert_eq!(replica.of("assets"), held(&db.pool, ASSETS_OF, &library).await);
    }

    /// The world of the authz matrix, with what its streams carry: a file and a face per asset; a device, tag, person,
    /// place and memory per account; a custom field of L1; vic's favourites, even of what vic cannot see.
    const WORLD: &str = concat!(
        include_str!("../../../photolib-authz/tests/world.sql"),
        "
        INSERT INTO asset_files (id, asset_id, role, storage, key)
        SELECT gen_random_uuid(), id, 'original', 'local', id::text FROM assets;
        INSERT INTO faces (id, asset_id, bbox, model_id) SELECT gen_random_uuid(), id, '{0,0,1,1}', 'm' FROM assets;
        INSERT INTO asset_embeddings (asset_id, model_id, embedding) SELECT id, 'm', '\\x00' FROM assets;
        INSERT INTO devices (id, user_id, name, platform) SELECT gen_random_uuid(), id, 'phone', 'android' FROM users;
        INSERT INTO tags (id, owner_id, name, path) SELECT gen_random_uuid(), id, 't', 't' FROM users;
        INSERT INTO persons (id, owner_id) SELECT gen_random_uuid(), id FROM users;
        INSERT INTO user_places (id, user_id, name, lat, lon, radius_m)
        SELECT gen_random_uuid(), id, 'home', 0, 0, 1 FROM users;
        INSERT INTO memories (id, owner_id, kind, title_template, date, asset_ids)
        SELECT gen_random_uuid(), id, 'year', 't', '2025-01-01', '{}' FROM users;
        INSERT INTO custom_fields (id, library_id, name, kind) VALUES (gen_random_uuid(), md5('L1')::uuid, 'f', 'text');
        INSERT INTO asset_user_state (user_id, asset_id, favorite) SELECT md5('vic')::uuid, id, true FROM assets;"
    );

    const PRINCIPALS: &[&str] = &[
        "ann", "vic", "con", "edi", "ida", "pat", "sam", "root", "anon", "k1", "g1", "ann/VS", "edi/E",
    ];
    const STREAMS: &[&str] = &[
        "account",
        "libraries",
        "albums",
        "tags",
        "people",
        "user_places",
        "memories",
        "assets/L1",
        "assets/L2",
        "faces/L1",
        "ml/L1",
        "album_items/A1",
        "album_items/A2",
        "partner/ann",
        "partner/con",
        "partner/sam",
    ];

    async fn id(pool: &PgPool, name: &str) -> Uuid {
        let id: String = sqlx::query_scalar("SELECT md5($1)::uuid::text")
            .bind(name)
            .fetch_one(pool)
            .await
            .unwrap();
        id.parse().unwrap()
    }

    async fn principal(pool: &PgPool, name: &str) -> Principal {
        if let Some((account, scopes)) = name.split_once('/') {
            let Principal::User(user, role) = Box::pin(principal(pool, account)).await else {
                unreachable!()
            };
            let scopes = [('V', Action::View), ('S', Action::Share), ('E', Action::Edit)]
                .into_iter()
                .filter(|(letter, _)| scopes.contains(*letter))
                .map(|(_, action)| action);
            return Principal::Key(user, role, scopes.collect());
        }
        let id = id(pool, name).await;
        match name {
            "anon" => Principal::Anonymous,
            "ida" => Principal::User(id, Role::Viewer),
            "root" => Principal::User(id, Role::Admin),
            _ if name.starts_with('k') => Principal::Link(id),
            _ if name.starts_with('g') => Principal::Grant(id),
            _ => Principal::User(id, Role::User),
        }
    }

    /// A stream of the world by name, its world names replaced by their ids.
    async fn stream_of(pool: &PgPool, name: &str) -> (String, Stream) {
        let name = match name.split_once('/') {
            Some((kind, world)) => format!("{kind}/{}", id(pool, world).await),
            None => name.into(),
        };
        let (stream, _) = named(&name).unwrap();
        (name, stream)
    }

    /// Why `who` may not see a row the stream sent, if it may not.
    async fn denied(pool: &PgPool, who: Principal, rows: &Rows, row: &Row) -> Option<String> {
        let me = match who {
            Principal::User(id, _) | Principal::Key(id, ..) => id.to_string(),
            _ => String::new(),
        };
        let value = |name: &str| {
            let at = rows.columns.iter().position(|column| column == name)?;
            Some(text(&row.values[at]))
        };
        let id = |name: &str| value(name).unwrap().parse::<Uuid>().unwrap();
        let (action, what) = match rows.entity.as_str() {
            "assets" => (Action::View, Resource::Asset(id("id"))),
            "libraries" => (Action::View, Resource::Library(id("id"))),
            "albums" => (Action::View, Resource::Album(id("id"))),
            "album_items" => (Action::View, Resource::Album(id("album_id"))),
            "links" => (Action::Share, Resource::Album(id("album_id"))),
            "custom_fields" => (Action::View, Resource::Library(id("library_id"))),
            "users" => return (value("id").unwrap() != me).then(|| format!("user {me}")),
            "partner_shares" => {
                return (value("partner_id").unwrap() != me).then(|| "share".into());
            }
            // The caller's own rows, such as what it keeps about an asset.
            entity if value("asset_id").is_none() || value("user_id").is_some() => {
                let owner = value("user_id").or_else(|| value("owner_id")).unwrap();
                return (owner != me).then(|| format!("{entity} of {owner}"));
            }
            _ => (Action::View, Resource::Asset(id("asset_id"))),
        };
        let allowed = can(pool, who, action, what).await.unwrap();
        (!allowed).then(|| format!("{} {:?}", rows.entity, what))
    }

    /// The assets of `stream` that `who` may see, by the policy: those of the library, or the photos and videos of the
    /// album's items or that the owner's share window holds.
    async fn expected(pool: &PgPool, who: Principal, stream: Stream) -> BTreeSet<String> {
        let (sql, of) = match stream {
            Stream::Assets(of) => ("SELECT id::text FROM assets WHERE library_id = $1::uuid", of),
            Stream::AlbumItems(of) => (
                "SELECT i.asset_id::text FROM album_items i JOIN assets a ON a.id = i.asset_id
                 WHERE i.album_id = $1::uuid AND a.media_kind IS NOT NULL",
                of,
            ),
            Stream::Partner(of) => (
                "SELECT a.id::text FROM assets a JOIN partner_shares p ON p.owner_id = a.owner_id
                 JOIN libraries l ON l.id = a.library_id AND l.owner_id = a.owner_id
                 WHERE a.owner_id = $1::uuid AND p.partner_id = $2::uuid AND a.media_kind IS NOT NULL
                     AND (p.taken_since IS NULL OR a.taken_utc >= p.taken_since OR l.privacy = 'private')",
                of,
            ),
            _ => return BTreeSet::new(),
        };
        let me = match who {
            Principal::User(id, _) | Principal::Key(id, ..) => id,
            _ => Uuid::nil(),
        };
        let ids: Vec<String> = sqlx::query_scalar(sql)
            .bind(of.to_string())
            .bind(me.to_string())
            .fetch_all(pool)
            .await
            .unwrap();
        let mut seen = BTreeSet::new();
        for asset in ids {
            if can(pool, who, Action::View, Resource::Asset(asset.parse().unwrap()))
                .await
                .unwrap()
            {
                seen.insert(asset);
            }
        }
        seen
    }

    /// Syncs every stream of the world as every principal, then again after changes, and compares what each holds
    /// with what the policy allows.
    #[tokio::test]
    async fn sync_never_returns_what_the_policy_denies() {
        let db = migrated().await;
        exec(&db.pool, WORLD).await;
        testpg::settle(&db.pool).await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let mut held = BTreeMap::new();
        let mut wrong = vec![];
        for round in 0..3 {
            if round == 1 {
                // a1 locked hides it from others, c1 trashed from all who may not delete it; vic leaves L1; pat's window
                // moves past everything but L3, which is private.
                exec(
                    &db.pool,
                    "UPDATE assets SET locked = true WHERE id = md5('a1')::uuid;
                     UPDATE assets SET trashed_at = now() WHERE id = md5('c1')::uuid;
                     DELETE FROM library_members WHERE user_id = md5('vic')::uuid;
                     UPDATE partner_shares SET taken_since = '2030-01-01' WHERE partner_id = md5('pat')::uuid",
                )
                .await;
                testpg::settle(&db.pool).await;
            }
            if round == 2 {
                // The server's policy switches off what sync shows of others and of faces and smart search (ADR-0240).
                exec(
                    &db.pool,
                    "INSERT INTO policy_switches (capability, enabled)
                     VALUES ('sharing', false), ('face_recognition', false), ('ml_search', false)",
                )
                .await;
            }
            for name in PRINCIPALS {
                let who = principal(&db.pool, name).await;
                for world in STREAMS {
                    let (stream, kind) = stream_of(&db.pool, world).await;
                    let (replica, cursor): &mut (Replica, Vec<u8>) = held.entry((name, world)).or_default();
                    if round == 1 && *name == "pat" && world.starts_with("partner/") {
                        // pat's share changed: a device opens the stream again from scratch (design 05 §3).
                        (*replica, *cursor) = Default::default();
                    }
                    let batches = read(&sync, who, &stream, cursor).await;
                    let open = can(&db.pool, who, Action::View, Resource::Stream(kind)).await.unwrap();
                    let status = batches[0].status.as_known().unwrap();
                    if status
                        != if open {
                            StreamStatus::STREAM_STATUS_OK
                        } else {
                            StreamStatus::STREAM_STATUS_FORBIDDEN
                        }
                    {
                        wrong.push(format!("{name} {world}: {status:?}"));
                    }
                    for rows in batches
                        .iter()
                        .flat_map(|batch| &batch.changes)
                        .filter(|rows| !rows.deleted)
                    {
                        for row in &rows.rows {
                            if let Some(why) = denied(&db.pool, who, rows, row).await {
                                wrong.push(format!("{name} {world} round {round}: {why}"));
                            }
                        }
                    }
                    if !open {
                        *replica = Replica::default();
                        continue;
                    }
                    *cursor = replica.apply(&batches);
                    let holds: BTreeSet<String> = replica.of("assets").into_keys().collect();
                    let allowed = expected(&db.pool, who, kind).await;
                    if holds != allowed {
                        wrong.push(format!(
                            "{name} {world} round {round}: holds {holds:?}, allowed {allowed:?}"
                        ));
                    }
                }
            }
        }
        let open: usize = held.values().filter(|(_, cursor)| !cursor.is_empty()).count();
        assert!(open > 60, "{open} streams were open");
        assert!(wrong.is_empty(), "{}", wrong.join("\n"));
    }

    /// What con put in Ann's L1 is no part of his share with sam: changes to its files, versions and values reach
    /// sam's device neither as rows nor as deletions.
    #[tokio::test]
    async fn a_partner_stream_reads_nothing_the_owner_put_in_another_library() {
        let db = migrated().await;
        exec(&db.pool, WORLD).await;
        testpg::settle(&db.pool).await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let (sam, (stream, _)) = (
            principal(&db.pool, "sam").await,
            stream_of(&db.pool, "partner/con").await,
        );
        let cursor = Replica::default().apply(&read(&sync, sam, &stream, &[]).await);
        exec(
            &db.pool,
            "UPDATE asset_files SET mime = 'image/jpeg' WHERE asset_id = md5('c1')::uuid;
             DELETE FROM asset_files WHERE asset_id = md5('c2')::uuid;
             INSERT INTO versions (id, asset_id, kind) VALUES (gen_random_uuid(), md5('c1')::uuid, 'edit');
             INSERT INTO asset_custom_values (asset_id, field_id, value) SELECT md5('c1')::uuid, id, '1' FROM custom_fields;",
        )
        .await;
        testpg::settle(&db.pool).await;
        let sent: Vec<(String, bool)> = (read(&sync, sam, &stream, &cursor).await.iter())
            .flat_map(|batch| &batch.changes)
            .map(|rows| (rows.entity.clone(), rows.deleted))
            .collect();
        assert_eq!(sent, []);
    }

    fn status(batches: &[SyncBatch]) -> StreamStatus {
        batches[0].status.as_known().unwrap()
    }

    #[tokio::test]
    async fn a_cursor_from_another_epoch_too_old_unreadable_or_ahead_of_the_database_must_start_again() {
        let (db, ann, library) = library(3).await;
        let stream = format!("assets/{library}");
        let sync = Sync::new(db.pool.clone(), "1.0".into());
        let mut replica = Replica::default();
        let cursor = replica.apply(&read(&sync, ann, &stream, &[]).await);
        assert_eq!(
            status(&read(&sync, ann, &stream, &cursor).await),
            StreamStatus::STREAM_STATUS_OK
        );
        let restored = Sync::new(db.pool.clone(), "1.1".into());
        let reset = read(&restored, ann, &stream, &cursor).await;
        assert_eq!(status(&reset), StreamStatus::STREAM_STATUS_RESET_REQUIRED);
        assert!(reset[0].changes.is_empty() && reset[0].cursor.is_empty());
        for garbage in [&b"{"[..], b"\xff", b"{}"] {
            assert_eq!(
                status(&read(&sync, ann, &stream, garbage).await),
                StreamStatus::STREAM_STATUS_RESET_REQUIRED
            );
        }
        let mut ahead: serde_json::Value = serde_json::from_slice(&cursor).unwrap();
        ahead["tables"]["assets"][0] = (u32::MAX as u64 * 1000).into();
        let ahead = serde_json::to_vec(&ahead).unwrap();
        assert_eq!(
            status(&read(&sync, ann, &stream, &ahead).await),
            StreamStatus::STREAM_STATUS_RESET_REQUIRED
        );

        // A deletion this cursor has not read was purged: it may hold a row that is gone.
        exec(&db.pool, "DELETE FROM assets WHERE id = md5('1')::uuid; UPDATE tombstones SET deleted_at = now() - interval '91 days'").await;
        testpg::settle(&db.pool).await;
        capture::purge_tombstones(&db.pool, std::time::Duration::from_secs(90 * 86_400))
            .await
            .unwrap();
        assert_eq!(
            status(&read(&sync, ann, &stream, &cursor).await),
            StreamStatus::STREAM_STATUS_RESET_REQUIRED
        );
        let fresh = read(&sync, ann, &stream, &[]).await;
        assert_eq!(
            status(&fresh),
            StreamStatus::STREAM_STATUS_OK,
            "from scratch, the horizon does not matter"
        );
        assert_eq!(
            status(&read(&sync, ann, &stream, &fresh.last().unwrap().cursor).await),
            StreamStatus::STREAM_STATUS_OK
        );
    }

    #[tokio::test]
    async fn an_unknown_or_foreign_stream_is_forbidden_and_the_others_sync() {
        let (db, ann, library) = library(1).await;
        exec(
            &db.pool,
            "INSERT INTO users (id, handle, display_name) VALUES (md5('eve')::uuid, 'eve', 'Eve')",
        )
        .await;
        testpg::settle(&db.pool).await;
        let eve = principal(&db.pool, "eve").await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let upper = format!("assets/{}", library.to_uppercase());
        for (who, stream) in [
            (ann, "nope".to_string()),
            (ann, "assets/x".into()),
            (ann, upper),
            (ann, format!("assets/{}", Uuid::nil())),
            (ann, format!("partner/{}", Uuid::nil())),
            (eve, format!("assets/{library}")),
        ] {
            let batches = read(&sync, who, &stream, &[]).await;
            assert_eq!(
                (stream.as_str(), status(&batches)),
                (stream.as_str(), StreamStatus::STREAM_STATUS_FORBIDDEN)
            );
            assert_eq!(batches.len(), 1);
            assert!(batches[0].changes.is_empty());
        }
        let account = read(&sync, eve, "account", &[]).await;
        let users: Vec<&Rows> = account.iter().flat_map(|batch| &batch.changes).collect();
        assert_eq!(users.len(), 1, "{users:?}");
        assert_eq!((users[0].entity.as_str(), users[0].rows.len()), ("users", 1));
    }

    #[tokio::test]
    async fn an_owners_devices_learn_which_library_is_their_upload_target() {
        let (db, ann, library) = library(1).await;
        exec(&db.pool, "UPDATE libraries SET is_upload_target = true").await;
        testpg::settle(&db.pool).await;
        let sync = Sync::new(db.pool.clone(), "e".into());
        let mut replica = Replica::default();
        replica.apply(&read(&sync, ann, "libraries", &[]).await);
        let row = &replica.0[&("libraries".to_string(), library)];
        assert_eq!(row["is_upload_target"].kind, Some(Of::Boolean(true)), "{row:?}");
    }

    #[tokio::test]
    async fn the_timeline_summary_leaves_out_what_an_album_the_account_hides_holds() {
        let (api, _root) = crate::rpc::users::tests::with_admin().await;
        exec(
            &api.pool,
            "INSERT INTO users (id, handle, display_name) SELECT md5(h)::uuid, h, h FROM unnest('{ann,vic}'::text[]) h;
             INSERT INTO libraries (id, owner_id, name, kind, root_uri)
             VALUES (md5('L1')::uuid, md5('ann')::uuid, 'L1', 'managed', 'L1');
             INSERT INTO library_members VALUES (md5('L1')::uuid, md5('vic')::uuid, 'viewer');
             INSERT INTO assets (id, library_id, owner_id, source, taken_local, media_kind)
             SELECT md5('x' || n)::uuid, md5('L1')::uuid, md5('ann')::uuid, 'upload', '2025-07-14 08:00', 'image'
             FROM generate_series(1, 3) n;
             INSERT INTO albums (id, owner_id, title) VALUES (md5('AH')::uuid, md5('ann')::uuid, 'Hidden');
             INSERT INTO album_items (id, album_id, kind, asset_id)
             VALUES (md5('i1')::uuid, md5('AH')::uuid, 'asset', md5('x1')::uuid);",
        )
        .await;
        let summary = |who: &'static str| {
            let (app, pool) = (api.app.clone(), api.pool.clone());
            async move {
                let bearer = id(&pool, who).await.to_string();
                let body = crate::testing::call(
                    &app,
                    "SyncService/GetTimelineSummary",
                    Some(&bearer),
                    serde_json::json!({}),
                )
                .await
                .1;
                body["days"][0]["count"].as_u64().unwrap_or(0)
            }
        };
        let hide = |sql: &'static str| exec(&api.pool, sql);
        assert_eq!(summary("ann").await, 3);
        hide("INSERT INTO album_user_state (user_id, album_id, hide_from_timeline) VALUES (md5('ann')::uuid, md5('AH')::uuid, true)").await;
        assert_eq!(summary("ann").await, 2, "the hidden album's asset leaves the timeline");
        assert_eq!(summary("vic").await, 3, "for the account that hid it only");
        hide("INSERT INTO album_items (id, album_id, kind, asset_id) VALUES (md5('i2')::uuid, md5('AH')::uuid, 'asset', md5('x2')::uuid)").await;
        assert_eq!(summary("ann").await, 1, "an asset added to it leaves too");
        hide("DELETE FROM album_items WHERE id = md5('i1')::uuid").await;
        assert_eq!(summary("ann").await, 2, "one taken out comes back");
        hide("DELETE FROM albums WHERE id = md5('AH')::uuid").await;
        assert_eq!(summary("ann").await, 3, "and all do when the album goes");
    }

    #[tokio::test]
    async fn the_timeline_summary_counts_what_the_timeline_shows_per_library_and_local_day() {
        let (api, root) = crate::rpc::users::tests::with_admin().await;
        exec(
            &api.pool,
            "INSERT INTO users (id, handle, display_name) SELECT md5(h)::uuid, h, h FROM unnest('{ann,vic}'::text[]) h;
             INSERT INTO libraries (id, owner_id, name, kind, root_uri, privacy)
             SELECT md5(name)::uuid, md5('ann')::uuid, name, 'managed', name, privacy
             FROM (VALUES ('L1', 'standard'), ('L2', 'private'), ('L3', 'standard')) AS l (name, privacy);
             INSERT INTO library_members VALUES (md5('L1')::uuid, md5('vic')::uuid, 'viewer');
             INSERT INTO library_user_state (user_id, library_id, hide_from_timeline) VALUES (md5('ann')::uuid, md5('L3')::uuid, true);
             INSERT INTO assets (id, library_id, owner_id, source, taken_local, taken_utc, archived, locked, trashed_at,
                 media_kind)
             SELECT gen_random_uuid(), md5(library)::uuid, md5('ann')::uuid, 'upload', local::timestamp, utc::timestamptz,
                 archived, locked, trashed::timestamptz, kind
             FROM (VALUES
                 ('L1', '2025-07-14 23:30', '2025-07-15 06:30Z', false, false, NULL, 'image'),
                 ('L1', '2025-07-14 08:00', '2025-07-14 06:00Z', false, false, NULL, 'video'),
                 ('L1', NULL, '2025-07-16 12:00Z', false, false, NULL, 'image'),
                 ('L1', '2024-01-01 10:00', '2024-01-01 10:00Z', false, false, NULL, 'image'),
                 ('L1', NULL, NULL, false, false, NULL, 'image'),
                 ('L1', '2024-01-01 11:00', '2024-01-01 11:00Z', true, false, NULL, 'image'),
                 ('L1', '2024-01-01 12:00', '2024-01-01 12:00Z', false, true, NULL, 'image'),
                 ('L1', '2024-01-01 13:00', '2024-01-01 13:00Z', false, false, '2025-01-01Z', 'image'),
                 ('L1', '2024-01-01 14:00', '2024-01-01 14:00Z', false, false, NULL, NULL),
                 ('L2', NULL, NULL, false, false, NULL, 'image'),
                 ('L3', '2024-01-01 10:00', '2024-01-01 10:00Z', false, false, NULL, 'image'))
             AS a (library, local, utc, archived, locked, trashed, kind)",
        )
        .await;
        let id = |name: &str| {
            let pool = api.pool.clone();
            let name = name.to_string();
            async move { id(&pool, &name).await.to_string() }
        };
        let (l1, ann, vic) = (id("L1").await, id("ann").await, id("vic").await);
        let summary = |bearer: String| {
            let app = api.app.clone();
            async move {
                let procedure = "SyncService/GetTimelineSummary";
                crate::testing::call(&app, procedure, Some(&bearer), serde_json::json!({})).await
            }
        };
        let (status, body) = summary(ann).await;
        assert_eq!(status, axum::http::StatusCode::OK, "{body}");
        let day = |date: &str, count: u32| serde_json::json!({ "libraryId": l1, "date": date, "count": count });
        let mut undated = day("", 1);
        undated.as_object_mut().unwrap().remove("date");
        let shown = serde_json::json!([
            day("2025-07-16", 1),
            day("2025-07-14", 2),
            day("2024-01-01", 1),
            undated
        ]);
        assert_eq!(
            body["days"], shown,
            "local days, newest first, undated last; neither archived, locked, trashed, private, hidden nor other files"
        );
        assert_eq!(summary(vic).await.1["days"], shown, "a member sees the same days");
        assert_eq!(
            summary(root.user_id.clone()).await.1,
            serde_json::json!({}),
            "nothing of others'"
        );
    }
}

#[cfg(test)]
mod hashes {
    use axum::http::StatusCode;
    use base64::{Engine, engine::general_purpose::STANDARD};
    use photolib_proto::proto::photolib::api::v1::{User, UserRole};
    use serde_json::{Value, json};
    use sqlx::PgPool;
    use uuid::Uuid;

    use crate::rpc::users::tests::{call, person, with_admin};

    /// An asset of `owner` in `library`, with files of these roles and hashes.
    async fn asset(pool: &PgPool, owner: &User, library: Uuid, files: &[(&str, u8)]) -> String {
        let id = Uuid::now_v7();
        sqlx::query("INSERT INTO assets (id, library_id, owner_id, source) VALUES ($1, $2, $3::uuid, 'scan')")
            .bind(id)
            .bind(library)
            .bind(&owner.user_id)
            .execute(pool)
            .await
            .unwrap();
        for (role, byte) in files {
            sqlx::query(
                "INSERT INTO asset_files (id, asset_id, role, storage, key, content_hash) VALUES ($1, $2, $3, 'nas', $3, $4)",
            )
            .bind(Uuid::now_v7())
            .bind(id)
            .bind(role)
            .bind(vec![*byte; 32])
            .execute(pool)
            .await
            .unwrap();
        }
        id.to_string()
    }

    async fn library(pool: &PgPool, owner: &User, kind: &str) -> Uuid {
        let id = Uuid::now_v7();
        sqlx::query("INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES ($1, $2::uuid, 'L', $3, 'l')")
            .bind(id)
            .bind(&owner.user_id)
            .bind(kind)
            .execute(pool)
            .await
            .unwrap();
        id
    }

    /// A request for hashes made of 32 times each byte.
    fn hashes(bytes: &[u8]) -> Value {
        let hashes: Vec<String> = bytes.iter().map(|&b| STANDARD.encode([b; 32])).collect();
        json!({ "hashes": hashes })
    }

    /// Each hash finds the asset of the caller's own libraries that holds it as an original or partner file, present,
    /// not in the trash and not found damaged by the scrub, so that a device sends it again: an external library's
    /// too, the earliest of several, never another account's.
    #[tokio::test]
    async fn a_hash_finds_the_asset_of_the_callers_own_libraries_that_holds_it() {
        let (api, root) = with_admin().await;
        let actor = root.user_id.parse().unwrap();
        let mut people = vec![];
        for handle in ["ann", "bob", "cat"] {
            let user = person(handle, UserRole::USER_ROLE_USER);
            people.push(api.accounts.create(actor, user).await.unwrap());
        }
        let [ann, bob, cat] = &people[..] else { unreachable!() };
        let pool = &api.pool;
        let (nas, photos) = (
            library(pool, ann, "external").await,
            library(pool, ann, "managed").await,
        );
        let roles = [("original", 1), ("original_alt", 2), ("live_motion", 3)];
        let photo = asset(pool, ann, nas, &roles).await;
        let other = [("motion_extracted", 4), ("thumb_s", 5)];
        asset(pool, ann, nas, &other).await;
        asset(pool, ann, photos, &[("original", 1)]).await;
        let trashed = asset(pool, ann, photos, &[("original", 6)]).await;
        let missing = asset(pool, ann, photos, &[("original", 7)]).await;
        let offline = library(pool, ann, "external").await;
        asset(pool, ann, offline, &[("original", 8)]).await;
        let damaged = asset(pool, ann, photos, &[("original", 9)]).await;
        sqlx::raw_sql(&format!(
            "UPDATE assets SET trashed_at = now() WHERE id = '{trashed}';
             UPDATE asset_files SET state = 'missing' WHERE asset_id = '{missing}';
             UPDATE libraries SET state = 'offline' WHERE id = '{offline}';
             UPDATE asset_files SET key = 'rotten.jpg' WHERE asset_id = '{damaged}';
             INSERT INTO integrity_findings (id, store, key, kind, detail)
             VALUES (photolib_uuidv7(), 'nas', 'rotten.jpg', 'content', '')"
        ))
        .execute(pool)
        .await
        .unwrap();
        let his = library(pool, bob, "managed").await;
        let bobs = asset(pool, bob, his, &[("original", 1)]).await;

        let asked = hashes(&[1, 2, 3, 1, 4, 5, 6, 7, 8, 9]);
        let check = |who| call(&api.app, "SyncService/CheckHashes", Some(who), asked.clone());
        let found = [&photo, &photo, &photo, &photo, "", "", "", "", "", ""];
        assert_eq!(check(ann).await, (StatusCode::OK, json!({ "assetIds": found })));
        let found = [&bobs, "", "", &bobs, "", "", "", "", "", ""];
        assert_eq!(check(bob).await, (StatusCode::OK, json!({ "assetIds": found })));
        assert_eq!(
            check(cat).await,
            (StatusCode::OK, json!({ "assetIds": vec![""; 10] })),
            "nobody learns what another account holds"
        );
    }

    #[tokio::test]
    async fn malformed_hashes_and_more_than_a_thousand_are_refused() {
        let (api, root) = with_admin().await;
        let invalid = (
            StatusCode::BAD_REQUEST,
            json!({ "code": "invalid_argument", "reason": "field.invalid", "field": "hashes" }),
        );
        let short = json!({ "hashes": [STANDARD.encode([1; 31])] });
        for body in [short, hashes(&[0; 1001])] {
            let answer = call(&api.app, "SyncService/CheckHashes", Some(&root), body).await;
            assert_eq!(answer, invalid);
        }
        let answer = call(&api.app, "SyncService/CheckHashes", Some(&root), hashes(&[0; 1000])).await;
        assert_eq!(answer, (StatusCode::OK, json!({ "assetIds": vec![""; 1000] })));
    }
}
