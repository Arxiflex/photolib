//! Mutations from devices' outboxes (design 05 §5, ADR-0265). Each applies at most once per account; a field keeps the
//! value of its latest edit by hybrid logical clock, an album keeps an asset by its latest add or removal, and a clock
//! more than five minutes ahead of the server's counts as five minutes ahead. The answer carries the rows the
//! mutations touched as they are now, which the device applies as it applies a sync batch.

use std::collections::{BTreeMap, BTreeSet};

use photolib_authz::{Action, Kind, Principal, Resource, can, scope};
use photolib_db::sync::{self as capture, Change, Read, Value};
use photolib_proto::proto::photolib::{
    api::v1::{ErrorDetail, MutationResult, PushMutationsResponse},
    sync::v1::{
        self as pb,
        __buffa::oneof::{mutation::Change as Edit, value::Kind as Of},
    },
};
use sha2::{Digest, Sha256};
use sqlx::{Postgres, QueryBuilder, Transaction, types::Json};
use uuid::Uuid;

use super::{Sync, groups, versions};

/// How far ahead of the server's clock a device's may run (design 05 §5).
const AHEAD_MS: i64 = 5 * 60_000;
const MAX_TEXT: usize = 10_000;
const MAX_KEY: usize = 1024;

const NOT_FOUND: &str = "mutation.not_found";
const FORBIDDEN: &str = "mutation.forbidden";
const INVALID: &str = "mutation.invalid";

type Tx<'a> = Transaction<'a, Postgres>;
/// The clock of each field's last edit, by field.
type Clocks = BTreeMap<String, String>;

/// A hybrid logical clock reading, ordered by time, counter, then device; stored as `<ms>-<counter>-<device>`.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Hlc {
    ms: i64,
    counter: u32,
    device: Uuid,
}

impl Hlc {
    /// A device's reading as the server counts it: one more than five minutes ahead of `now_ms` is at that bound with
    /// counter 0, where the device's next edits tie with it and, applied after it, win.
    fn of(hlc: &pb::Hlc, now_ms: i64) -> Option<Self> {
        let device = hlc.device_id.parse().ok()?;
        let bound = now_ms.saturating_add(AHEAD_MS);
        match hlc.physical_ms {
            ..0 => None,
            ms if ms > bound => Some(Self {
                ms: bound,
                counter: 0,
                device,
            }),
            ms => Some(Self {
                ms,
                counter: hlc.counter,
                device,
            }),
        }
    }

    fn parse(text: &str) -> Option<Self> {
        let (ms, rest) = text.split_once('-')?;
        let (counter, device) = rest.split_once('-')?;
        Some(Self {
            ms: ms.parse().ok()?,
            counter: counter.parse().ok()?,
            device: device.parse().ok()?,
        })
    }

    fn text(&self) -> String {
        format!("{:013}-{:010}-{}", self.ms, self.counter, self.device)
    }

    /// Whether an edit at this reading overrides one at `stored`; of two at one reading, from one device, the later.
    fn wins(&self, stored: Option<&str>) -> bool {
        stored.and_then(Self::parse).is_none_or(|stored| *self >= stored)
    }

    /// Takes `field` at this reading unless a later edit holds it in `clocks`; returns whether it did.
    fn take(&self, clocks: &mut Clocks, field: &str) -> bool {
        let wins = self.wins(clocks.get(field).map(String::as_str));
        if wins {
            clocks.insert(field.into(), self.text());
        }
        wins
    }
}

/// The id of `asset`'s item in `album`, the same on every device (`MemberEdit`).
fn item_id(album: Uuid, asset: Uuid) -> Uuid {
    let hash = Sha256::new()
        .chain_update(b"photolib.album_item")
        .chain_update(album.as_bytes())
        .chain_update(asset.as_bytes())
        .finalize();
    let bytes = hash.first_chunk().copied().unwrap_or_default();
    uuid::Builder::from_custom_bytes(bytes).into_uuid()
}

#[derive(Clone, Copy)]
enum Type {
    Text,
    Rating,
    Flag,
    Trash,
    /// A fractional index key.
    Key,
    /// The id of one of the asset's versions.
    Version,
}

/// What a device may set: the table, the field, its type and the action it takes on the row; `View` for one's own
/// state of an asset.
const FIELDS: &[(&str, &str, Type, Action)] = &[
    ("assets", "title", Type::Text, Action::Edit),
    ("assets", "description", Type::Text, Action::Edit),
    ("assets", "rating", Type::Rating, Action::Edit),
    ("assets", "color_label", Type::Text, Action::Edit),
    ("assets", "archived", Type::Flag, Action::Edit),
    ("assets", "trashed_at", Type::Trash, Action::Delete),
    ("assets", "current_version_id", Type::Version, Action::Edit),
    ("asset_user_state", "favorite", Type::Flag, Action::View),
    ("asset_user_state", "hidden_from_memories", Type::Flag, Action::View),
    ("album_user_state", "hide_from_timeline", Type::Flag, Action::View),
    ("album_user_state", "hide_from_memories", Type::Flag, Action::View),
    ("library_user_state", "hide_from_timeline", Type::Flag, Action::View),
    ("library_user_state", "hide_from_memories", Type::Flag, Action::View),
    ("album_items", "sort_key", Type::Key, Action::Edit),
    ("albums", "title", Type::Text, Action::Edit),
    ("albums", "description", Type::Text, Action::Edit),
];

/// A field's value as its column takes it.
#[derive(Clone, Debug, PartialEq)]
enum Bind {
    Text(Option<String>),
    Small(i16),
    Flag(bool),
    /// Milliseconds since the Unix epoch.
    Time(Option<i64>),
    Uuid(Uuid),
}

/// A mutation's change, checked.
#[derive(Debug, PartialEq)]
enum Checked {
    /// Fields of the row `id` of `table`; of `asset_user_state`, the caller's of the asset `id`.
    Fields {
        table: &'static str,
        id: Uuid,
        fields: Vec<(&'static str, Bind)>,
    },
    /// An asset added to an album, at `key` in its custom order, or removed from it.
    Member {
        album: Uuid,
        asset: Uuid,
        present: bool,
        key: Option<String>,
    },
    /// A version added to an asset's history.
    Version(versions::Add),
}

impl Checked {
    /// The table and key of the row it touches.
    fn row(&self) -> (&'static str, Uuid) {
        match self {
            Self::Fields { table, id, .. } => (table, *id),
            Self::Member { album, asset, .. } => ("album_items", item_id(*album, *asset)),
            Self::Version(add) => ("versions", add.version),
        }
    }
}

fn key(text: &str) -> bool {
    (1..=MAX_KEY).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_alphanumeric())
}

/// `change` at `hlc`, or `None` when it names what a device may not set or a value its field does not take.
fn check(change: &Edit, hlc: &Hlc) -> Option<Checked> {
    match change {
        Edit::Edit(edit) => {
            let (table, ..) = FIELDS.iter().find(|(table, ..)| *table == edit.entity)?;
            let mut fields = vec![];
            for (name, value) in &edit.fields {
                let &(_, field, kind, _) = FIELDS.iter().find(|(t, f, ..)| t == table && f == name)?;
                let bind = match (kind, &value.kind) {
                    (Type::Text, None) => Bind::Text(None),
                    (Type::Text, Some(Of::Text(text))) if text.chars().count() <= MAX_TEXT => {
                        Bind::Text(Some(text.clone()))
                    }
                    (Type::Rating, Some(Of::Integer(rating @ -1..=5))) => Bind::Small(i16::try_from(*rating).ok()?),
                    (Type::Flag, Some(Of::Boolean(flag))) => Bind::Flag(*flag),
                    (Type::Trash, None) => Bind::Time(None),
                    (Type::Trash, Some(_)) => Bind::Time(Some(hlc.ms)),
                    (Type::Key, Some(Of::Text(text))) if key(text) => Bind::Text(Some(text.clone())),
                    (Type::Version, Some(Of::Text(text))) => Bind::Uuid(text.parse().ok()?),
                    _ => return None,
                };
                fields.push((field, bind));
            }
            fields.sort_by_key(|(field, _)| *field);
            (!fields.is_empty()).then_some(Checked::Fields {
                table,
                id: edit.id.parse().ok()?,
                fields,
            })
        }
        Edit::Member(member) => {
            let key = Some(member.sort_key.clone()).filter(|key| !key.is_empty());
            if member.entity != "album_items" || key.as_deref().is_some_and(|key| !self::key(key)) {
                return None;
            }
            Some(Checked::Member {
                album: member.set_id.parse().ok()?,
                asset: member.element_id.parse().ok()?,
                present: member.present,
                key: key.filter(|_| member.present),
            })
        }
        Edit::Version(edit) => versions::check(edit, hlc.device).map(Checked::Version),
    }
}

/// The rejection a stored outcome names.
fn reason(stored: &str) -> &'static str {
    [NOT_FOUND, FORBIDDEN]
        .into_iter()
        .find(|reason| *reason == stored)
        .unwrap_or(INVALID)
}

const ALBUM_OF_ITEM: &str =
    "SELECT album_id FROM album_items WHERE id = $1 UNION ALL SELECT album_id FROM album_item_states WHERE id = $1";

impl Sync {
    /// Applies `mutations` from `me`'s device in order, at `now_ms` on the server's clock.
    pub(super) async fn push(
        &self,
        who: Principal,
        me: Uuid,
        mutations: Vec<pb::Mutation>,
        now_ms: i64,
    ) -> sqlx::Result<PushMutationsResponse> {
        let (mut results, mut touched) = (vec![], BTreeSet::new());
        for mutation in &mutations {
            let rejected = self.one(who, me, mutation, now_ms, &mut touched).await?;
            results.push(MutationResult {
                mutation_id: mutation.mutation_id.clone(),
                rejected: rejected
                    .map(|code| ErrorDetail {
                        code: code.into(),
                        ..Default::default()
                    })
                    .into(),
                ..Default::default()
            });
        }
        Ok(PushMutationsResponse {
            results,
            rows: self.touched(who, me, touched).await?,
            clock: pb::Hlc {
                physical_ms: now_ms,
                ..Default::default()
            }
            .into(),
            ..Default::default()
        })
    }

    /// Applies one mutation unless it was before; returns why it was rejected, if it was.
    async fn one(
        &self,
        who: Principal,
        me: Uuid,
        mutation: &pb::Mutation,
        now_ms: i64,
        touched: &mut BTreeSet<(&'static str, Uuid)>,
    ) -> sqlx::Result<Option<&'static str>> {
        let Ok(id) = mutation.mutation_id.parse::<Uuid>() else {
            return Ok(Some(INVALID));
        };
        let hlc = mutation.hlc.as_option().and_then(|hlc| Hlc::of(hlc, now_ms));
        let checked = (hlc.as_ref().zip(mutation.change.as_ref())).and_then(|(hlc, change)| check(change, hlc));
        touched.extend(checked.as_ref().map(Checked::row));
        if let Some(done) = self.outcome(me, id).await? {
            return Ok(done);
        }
        let (Some(checked), Some(hlc)) = (checked, hlc) else {
            return self.record(me, id, None, Some(INVALID)).await;
        };
        match self.allowed(who, &checked).await? {
            None if self.private(&checked).await? || self.unfit(&checked).await? => {
                self.record(me, id, None, Some(INVALID)).await
            }
            None => self.record(me, id, Some((&checked, &hlc)), None).await,
            refused => self.record(me, id, None, refused).await,
        }
    }

    /// The outcome of the mutation `id` of `me` if it was processed: why it was rejected, if it was.
    async fn outcome(&self, me: Uuid, id: Uuid) -> sqlx::Result<Option<Option<&'static str>>> {
        let done = "SELECT rejected FROM processed_mutations WHERE user_id = $1 AND mutation_id = $2";
        let done: Option<Option<String>> = sqlx::query_scalar(done)
            .bind(me)
            .bind(id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(done.map(|rejected| rejected.as_deref().map(reason)))
    }

    /// Records the mutation `id` as `rejected`, or applies its `change` in the same transaction; a call that recorded
    /// it first decides the outcome.
    async fn record(
        &self,
        me: Uuid,
        id: Uuid,
        change: Option<(&Checked, &Hlc)>,
        rejected: Option<&'static str>,
    ) -> sqlx::Result<Option<&'static str>> {
        let mut tx = self.pool.begin().await?;
        let record = "INSERT INTO processed_mutations (user_id, mutation_id, rejected) VALUES ($1, $2, $3)
                      ON CONFLICT DO NOTHING";
        let record = sqlx::query(record).bind(me).bind(id).bind(rejected);
        if record.execute(&mut *tx).await?.rows_affected() == 0 {
            drop(tx);
            return Ok(self.outcome(me, id).await?.flatten());
        }
        let mut rejected = rejected;
        if let Some((change, hlc)) = change
            && !apply(&mut tx, me, change, hlc).await?
        {
            rejected = Some(NOT_FOUND);
            sqlx::query("UPDATE processed_mutations SET rejected = $3 WHERE user_id = $1 AND mutation_id = $2")
                .bind(me)
                .bind(id)
                .bind(NOT_FOUND)
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(rejected)
    }

    /// `None` when `who` may make `change`, else whether what it changes is out of sight or only out of reach.
    async fn allowed(&self, who: Principal, change: &Checked) -> sqlx::Result<Option<&'static str>> {
        let (seen, needed) = match change {
            Checked::Fields { table, id, fields } => {
                let what = match *table {
                    "album_items" => {
                        let album = sqlx::query_scalar(ALBUM_OF_ITEM)
                            .bind(id)
                            .fetch_optional(&self.pool)
                            .await?;
                        let Some(album) = album else {
                            return Ok(Some(NOT_FOUND));
                        };
                        Resource::Album(album)
                    }
                    "album_user_state" => Resource::Album(*id),
                    "library_user_state" => Resource::Library(*id),
                    "albums" => {
                        // An id no album has yet is a new album of the caller's.
                        let held = sqlx::query_scalar("SELECT EXISTS (SELECT FROM albums WHERE id = $1)");
                        if !held.bind(id).fetch_one(&self.pool).await? {
                            return Ok(None);
                        }
                        Resource::Album(*id)
                    }
                    _ => Resource::Asset(*id),
                };
                let action = |name| FIELDS.iter().find(|(t, f, ..)| t == table && *f == name).map(|f| f.3);
                let mut needed: Vec<_> = fields
                    .iter()
                    .filter_map(|(name, _)| action(*name))
                    .map(|a| (a, what))
                    .collect();
                needed.dedup();
                (vec![what], needed)
            }
            Checked::Member {
                album,
                asset,
                present: true,
                ..
            } => (
                vec![Resource::Album(*album), Resource::Asset(*asset)],
                vec![(
                    Action::Contribute,
                    Resource::Item {
                        album: *album,
                        asset: *asset,
                    },
                )],
            ),
            Checked::Member { album, .. } => (
                vec![Resource::Album(*album)],
                vec![(Action::Edit, Resource::Album(*album))],
            ),
            Checked::Version(add) => (
                vec![Resource::Asset(add.asset)],
                vec![(Action::Edit, Resource::Asset(add.asset))],
            ),
        };
        for what in seen {
            if !can(&self.pool, who, Action::View, what).await? {
                return Ok(Some(NOT_FOUND));
            }
        }
        for (action, what) in needed {
            if !can(&self.pool, who, action, what).await? {
                return Ok(Some(FORBIDDEN));
            }
        }
        Ok(None)
    }

    /// Whether `change` would write in clear what a private library or album keeps encrypted (design 04 §9): an
    /// asset's fields but its trash, an item's place in the custom order.
    async fn private(&self, change: &Checked) -> sqlx::Result<bool> {
        let (sql, id) = match change {
            Checked::Fields {
                table: "assets",
                id,
                fields,
            } if fields.iter().any(|(f, _)| *f != "trashed_at") => (
                "SELECT l.privacy FROM assets a JOIN libraries l ON l.id = a.library_id WHERE a.id = $1".to_string(),
                id,
            ),
            Checked::Fields {
                table: "album_items",
                id,
                ..
            } => (format!("SELECT privacy FROM albums WHERE id IN ({ALBUM_OF_ITEM})"), id),
            Checked::Fields {
                table: "albums", id, ..
            } => ("SELECT privacy FROM albums WHERE id = $1".into(), id),
            Checked::Member {
                album, key: Some(_), ..
            } => ("SELECT privacy FROM albums WHERE id = $1".into(), album),
            Checked::Version(add) => (
                "SELECT l.privacy FROM assets a JOIN libraries l ON l.id = a.library_id WHERE a.id = $1".to_string(),
                &add.asset,
            ),
            _ => return Ok(false),
        };
        let privacy: Option<String> = sqlx::query_scalar(&sql).bind(id).fetch_optional(&self.pool).await?;
        Ok(privacy.as_deref() == Some("private"))
    }

    /// Whether the database says `change` is not one to make: a version of no picture, beyond the versions an asset
    /// keeps, with a parent that is not the asset's or an id another recipe has; a current version that is none of the
    /// asset's.
    async fn unfit(&self, change: &Checked) -> sqlx::Result<bool> {
        let mut conn = self.pool.acquire().await?;
        match change {
            Checked::Version(add) => versions::unfit(&mut conn, add).await,
            Checked::Fields {
                table: "assets",
                id,
                fields,
            } => {
                for (field, bind) in fields {
                    if let ("current_version_id", Bind::Uuid(version)) = (*field, bind)
                        && versions::foreign(&mut conn, *id, *version).await?
                    {
                        return Ok(true);
                    }
                }
                Ok(false)
            }
            _ => Ok(false),
        }
    }

    /// The rows `touched` names as they are now, those gone or out of `who`'s sight as deletions.
    async fn touched(
        &self,
        who: Principal,
        me: Uuid,
        touched: BTreeSet<(&'static str, Uuid)>,
    ) -> sqlx::Result<Vec<pb::Rows>> {
        let columns = self.columns().await?;
        let mut changes = vec![];
        for (table, key, column, kind) in [
            ("assets", "id", "id", Kind::Asset),
            ("versions", "id", "asset_id", Kind::Asset),
            ("asset_user_state", "asset_id", "asset_id", Kind::Asset),
            ("album_items", "id", "album_id", Kind::Album),
            ("albums", "id", "id", Kind::Album),
            ("album_user_state", "album_id", "album_id", Kind::Album),
            ("library_user_state", "library_id", "library_id", Kind::Library),
        ] {
            let ids: Vec<String> = (touched.iter())
                .filter(|(t, _)| *t == table)
                .map(|(_, id)| id.to_string())
                .collect();
            if ids.is_empty() {
                continue;
            }
            let (Some(entity), Some(table_columns)) = (capture::find(table), columns.get(table)) else {
                continue;
            };
            let read = Read {
                entity,
                columns: table_columns.clone(),
                rows: Box::new(move |q| {
                    match table {
                        "asset_user_state" | "album_user_state" | "library_user_state" => {
                            q.push("t.user_id = ").push_bind(me).push("::uuid")
                        }
                        _ => q.push("true"),
                    };
                }),
                tombstones: None,
                visible: Some((column, Box::new(move |q| scope(who, Action::View, kind, q)))),
            };
            let mut found = capture::current(&self.pool, &read, key, &ids).await?;
            let seen: BTreeSet<String> = (found.iter())
                .filter_map(|change| match change.get(&read.columns, key) {
                    Some(Value::Text(id)) => Some(id.clone()),
                    _ => None,
                })
                .collect();
            for id in ids.into_iter().filter(|id| !seen.contains(id)) {
                let key = match table {
                    "asset_user_state" | "album_user_state" | "library_user_state" => {
                        serde_json::json!({"user_id": me, column: id})
                    }
                    _ => serde_json::json!({ "id": id }),
                };
                found.push(Change {
                    txid: 0,
                    key: key.to_string(),
                    deleted: true,
                    values: vec![],
                });
            }
            changes.push((table, found));
        }
        Ok(groups(&columns, changes))
    }
}

/// Applies `change` at `hlc` in `tx`: each field and membership takes it unless a later edit holds it. Returns false
/// when what it changes is gone.
async fn apply(tx: &mut Tx<'_>, me: Uuid, change: &Checked, hlc: &Hlc) -> sqlx::Result<bool> {
    match change {
        Checked::Member {
            album,
            asset,
            present,
            key,
        } => member(tx, (*album, *asset), *present, key.as_deref(), hlc).await,
        Checked::Version(add) => versions::apply(tx, add).await,
        Checked::Fields { table, id, fields } => {
            if *table == "album_items"
                && let Some(mut state) = State::lock(tx, *id).await?
            {
                if let [("sort_key", Bind::Text(key))] = fields.as_slice()
                    && hlc.take(&mut state.clocks, "sort_key")
                {
                    state.key.clone_from(key);
                    state.save(tx).await?;
                }
                return Ok(true);
            }
            if *table == "albums" {
                sqlx::query("INSERT INTO albums (id, owner_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
                    .bind(id)
                    .bind(me)
                    .execute(&mut **tx)
                    .await?;
            }
            let held = set(tx, Row::of(table, me, *id), fields, hlc).await?;
            if held && *table == "assets" && fields.iter().any(|(field, _)| *field == "current_version_id") {
                versions::follow(tx, *id).await?;
            }
            Ok(held)
        }
    }
}

/// Adds the asset of `(album, asset)` to the album at `key`, or removes it, at `hlc`.
async fn member(
    tx: &mut Tx<'_>,
    (album, asset): (Uuid, Uuid),
    present: bool,
    key: Option<&str>,
    hlc: &Hlc,
) -> sqlx::Result<bool> {
    let item = item_id(album, asset);
    let made = "INSERT INTO album_item_states (id, album_id, asset_id, present)
                SELECT $1, a.id, s.id, false FROM albums a, assets s WHERE a.id = $2 AND s.id = $3
                ON CONFLICT DO NOTHING";
    sqlx::query(made)
        .bind(item)
        .bind(album)
        .bind(asset)
        .execute(&mut **tx)
        .await?;
    let Some(mut state) = State::lock(tx, item).await? else {
        return Ok(false);
    };
    if hlc.take(&mut state.clocks, "present") {
        state.present = present;
        if let Some(key) = key.filter(|_| hlc.take(&mut state.clocks, "sort_key")) {
            state.key = Some(key.into());
        }
        state.save(tx).await?;
    }
    Ok(true)
}

/// A row whose fields a device sets: its table and its key's columns and values.
struct Row {
    table: &'static str,
    key: Vec<(&'static str, Uuid)>,
}

impl Row {
    fn of(table: &'static str, me: Uuid, id: Uuid) -> Self {
        let key = match table {
            "asset_user_state" => vec![("user_id", me), ("asset_id", id)],
            "album_user_state" => vec![("user_id", me), ("album_id", id)],
            "library_user_state" => vec![("user_id", me), ("library_id", id)],
            _ => vec![("id", id)],
        };
        Self { table, key }
    }

    fn push_key(&self, q: &mut QueryBuilder<'_, Postgres>) {
        for (at, (column, id)) in self.key.iter().enumerate() {
            q.push(if at == 0 { " WHERE " } else { " AND " });
            q.push(format!("{column} = ")).push_bind(*id);
        }
    }
}

/// Sets each of `fields` of `row` that no later edit than `hlc` holds; false when the row is gone.
async fn set(tx: &mut Tx<'_>, row: Row, fields: &[(&'static str, Bind)], hlc: &Hlc) -> sqlx::Result<bool> {
    if let [(_, user), (column, id)] = row.key[..]
        && let Some(parent) = [
            ("asset_id", "assets"),
            ("album_id", "albums"),
            ("library_id", "libraries"),
        ]
        .iter()
        .find_map(|(c, parent)| (*c == column).then_some(*parent))
    {
        // The account's own state of a row it may see, made of its key alone.
        let insert = format!(
            "INSERT INTO {} (user_id, {column}) SELECT $1, id FROM {parent} WHERE id = $2 ON CONFLICT DO NOTHING",
            row.table
        );
        sqlx::query(&insert).bind(user).bind(id).execute(&mut **tx).await?;
    }
    let mut q = QueryBuilder::new(format!("SELECT field_hlc FROM {}", row.table));
    row.push_key(&mut q);
    let clocks: Option<Json<Clocks>> = q
        .push(" FOR UPDATE")
        .build_query_scalar()
        .fetch_optional(&mut **tx)
        .await?;
    let Some(Json(mut clocks)) = clocks else {
        return Ok(false);
    };
    let winners: Vec<_> = fields
        .iter()
        .filter(|(field, _)| hlc.take(&mut clocks, field))
        .collect();
    if winners.is_empty() {
        return Ok(true);
    }
    let mut q = QueryBuilder::new(format!("UPDATE {} SET ", row.table));
    for (field, bind) in winners {
        q.push(format!("{field} = "));
        match bind {
            Bind::Text(text) => q.push_bind(text.clone()).push("::text"),
            Bind::Small(small) => q.push_bind(*small),
            Bind::Flag(flag) => q.push_bind(*flag),
            Bind::Time(ms) => q
                .push("'epoch'::timestamptz + interval '1 millisecond' * ")
                .push_bind(*ms),
            Bind::Uuid(id) => q.push_bind(*id),
        };
        q.push(", ");
    }
    q.push("field_hlc = ").push_bind(Json(clocks));
    row.push_key(&mut q);
    q.build().execute(&mut **tx).await?;
    Ok(true)
}

/// An asset's item in an album as its mutations left it (`album_item_states`).
struct State {
    id: Uuid,
    present: bool,
    key: Option<String>,
    clocks: Clocks,
}

impl State {
    async fn lock(tx: &mut Tx<'_>, id: Uuid) -> sqlx::Result<Option<Self>> {
        let sql = "SELECT present, sort_key, field_hlc FROM album_item_states WHERE id = $1 FOR UPDATE";
        let state: Option<(bool, Option<String>, Json<Clocks>)> =
            sqlx::query_as(sql).bind(id).fetch_optional(&mut **tx).await?;
        Ok(state.map(|(present, key, Json(clocks))| Self {
            id,
            present,
            key,
            clocks,
        }))
    }

    /// Stores the state and makes album_items hold the item while it is present, unless another item of the album
    /// stands for its asset.
    async fn save(&self, tx: &mut Tx<'_>) -> sqlx::Result<()> {
        sqlx::query("UPDATE album_item_states SET present = $2, sort_key = $3, field_hlc = $4 WHERE id = $1")
            .bind(self.id)
            .bind(self.present)
            .bind(&self.key)
            .bind(Json(&self.clocks))
            .execute(&mut **tx)
            .await?;
        let held = if self.present {
            "INSERT INTO album_items (id, album_id, kind, asset_id, sort_key, field_hlc)
             SELECT s.id, s.album_id, 'asset', s.asset_id, s.sort_key, s.field_hlc - 'present'
             FROM album_item_states s WHERE s.id = $1 AND NOT EXISTS (
                 SELECT FROM album_items i WHERE i.album_id = s.album_id AND i.asset_id = s.asset_id AND i.id <> s.id)
             ON CONFLICT (id) DO UPDATE SET sort_key = excluded.sort_key, field_hlc = excluded.field_hlc"
        } else {
            "DELETE FROM album_items i USING album_item_states s
             WHERE s.id = $1 AND i.album_id = s.album_id AND i.asset_id = s.asset_id"
        };
        sqlx::query(held).bind(self.id).execute(&mut **tx).await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use photolib_authz::Role;
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg::{self, TestDb},
    };

    use super::*;

    const NOW: i64 = 1_767_225_600_000;
    const WORLD: &str = include_str!("../../../../photolib-authz/tests/world.sql");

    async fn world() -> (TestDb, Sync) {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        sqlx::raw_sql(WORLD).execute(&db.pool).await.unwrap();
        let sync = Sync::new(db.pool.clone(), "e".into());
        (db, sync)
    }

    async fn id(sync: &Sync, name: &str) -> Uuid {
        sqlx::query_scalar("SELECT md5($1)::uuid")
            .bind(name)
            .fetch_one(&sync.pool)
            .await
            .unwrap()
    }

    async fn user(sync: &Sync, name: &str) -> (Principal, Uuid) {
        let me = id(sync, name).await;
        (Principal::User(me, Role::User), me)
    }

    /// What `sql` reads, as text, `NULL` for none.
    async fn read(sync: &Sync, sql: &str) -> String {
        let sql = format!("SELECT coalesce(({sql})::text, 'NULL')");
        sqlx::query_scalar(&sql).fetch_one(&sync.pool).await.unwrap()
    }

    fn device(n: u128) -> Uuid {
        Uuid::from_u128(n)
    }

    fn hlc(ms: i64, counter: u32, device: Uuid) -> pb::Hlc {
        pb::Hlc {
            physical_ms: ms,
            counter,
            device_id: device.to_string(),
            ..Default::default()
        }
    }

    fn value(kind: Option<Of>) -> pb::Value {
        pb::Value {
            kind,
            ..Default::default()
        }
    }

    fn text(text: &str) -> pb::Value {
        value(Some(Of::Text(text.into())))
    }

    fn mutation(at: pb::Hlc, change: Edit) -> pb::Mutation {
        pb::Mutation {
            mutation_id: Uuid::now_v7().to_string(),
            hlc: at.into(),
            change: Some(change),
            ..Default::default()
        }
    }

    fn edit(at: pb::Hlc, entity: &str, id: Uuid, fields: &[(&str, pb::Value)]) -> pb::Mutation {
        let fields = fields.iter().map(|(field, value)| (field.to_string(), value.clone()));
        let edit = pb::FieldEdit {
            entity: entity.into(),
            id: id.to_string(),
            fields: fields.collect(),
            ..Default::default()
        };
        mutation(at, Edit::Edit(Box::new(edit)))
    }

    fn member(at: pb::Hlc, album: Uuid, asset: Uuid, present: bool, key: &str) -> pb::Mutation {
        let member = pb::MemberEdit {
            entity: "album_items".into(),
            set_id: album.to_string(),
            element_id: asset.to_string(),
            present,
            sort_key: key.into(),
            ..Default::default()
        };
        mutation(at, Edit::Member(Box::new(member)))
    }

    /// Pushes `mutations` as `who` at `now`: each one's rejection, "" when applied, and the answer.
    async fn push(
        sync: &Sync,
        (who, me): (Principal, Uuid),
        mutations: &[pb::Mutation],
        now: i64,
    ) -> (Vec<String>, PushMutationsResponse) {
        let answer = sync.push(who, me, mutations.to_vec(), now).await.unwrap();
        let ids: Vec<_> = answer.results.iter().map(|result| result.mutation_id.clone()).collect();
        let sent: Vec<_> = mutations.iter().map(|mutation| mutation.mutation_id.clone()).collect();
        assert_eq!(ids, sent, "a result per mutation, in their order");
        let rejected = answer.results.iter().map(|result| {
            (result.rejected.as_option())
                .map(|detail| detail.code.clone())
                .unwrap_or_default()
        });
        (rejected.collect(), answer)
    }

    /// The `column` of the row of `entity` whose `key` is `id` in `answer`: `deleted` for a deletion.
    fn echoed(answer: &PushMutationsResponse, entity: &str, key: &str, id: Uuid, column: &str) -> Option<String> {
        answer
            .rows
            .iter()
            .filter(|rows| rows.entity == entity)
            .find_map(|rows| {
                let at = |name: &str| rows.columns.iter().position(|column| column == name);
                let key = at(key)?;
                let row = rows.rows.iter().find(|row| match &row.values[key].kind {
                    Some(Of::Text(text)) => *text == id.to_string(),
                    _ => false,
                })?;
                if rows.deleted {
                    return Some("deleted".into());
                }
                Some(match &row.values[at(column)?].kind {
                    Some(Of::Text(text)) => text.clone(),
                    Some(Of::Integer(integer)) => integer.to_string(),
                    Some(Of::Boolean(flag)) => flag.to_string(),
                    None => "NULL".into(),
                    other => format!("{other:?}"),
                })
            })
    }

    #[test]
    fn a_clock_orders_by_time_counter_then_device_and_counts_at_most_five_minutes_ahead() {
        let (one, two) = (device(1), device(2));
        let at = |ms, counter, device| Hlc::of(&hlc(ms, counter, device), NOW).unwrap();
        assert!(at(NOW, 0, two) < at(NOW, 1, one) && at(NOW, 1, one) < at(NOW + 1, 0, one));
        assert!(at(NOW, 0, one) < at(NOW, 0, two), "the device breaks a tie");
        assert_eq!(
            at(NOW + AHEAD_MS, 7, one),
            Hlc {
                ms: NOW + AHEAD_MS,
                counter: 7,
                device: one
            }
        );
        assert_eq!(
            at(NOW + AHEAD_MS + 1, 7, one),
            Hlc {
                ms: NOW + AHEAD_MS,
                counter: 0,
                device: one
            }
        );
        assert_eq!(Hlc::of(&hlc(-1, 0, one), NOW), None);
        assert_eq!(Hlc::of(&pb::Hlc::default(), NOW), None, "a reading names its device");

        let stored = at(NOW, 7, one).text();
        assert_eq!(stored, "1767225600000-0000000007-00000000-0000-0000-0000-000000000001");
        assert_eq!(Hlc::parse(&stored), Some(at(NOW, 7, one)));
        assert!(at(NOW, 7, one).wins(Some(&stored)), "the later of two at one reading");
        assert!(at(NOW, 8, one).wins(Some(&stored)) && !at(NOW, 6, one).wins(Some(&stored)));
        assert!(at(0, 0, one).wins(None) && at(0, 0, one).wins(Some("")));
    }

    #[test]
    fn an_assets_item_in_an_album_has_the_same_id_on_every_device() {
        let (album, asset) = (
            Uuid::parse_str("00000000-0000-7000-8000-000000000001").unwrap(),
            Uuid::parse_str("00000000-0000-7000-8000-000000000002").unwrap(),
        );
        assert_eq!(
            item_id(album, asset).to_string(),
            "5b1f6a53-e22f-8490-bfdc-e63a613abf90"
        );
        assert_ne!(item_id(asset, album), item_id(album, asset));
    }

    #[test]
    fn a_field_edit_names_only_what_devices_may_set_with_values_their_fields_take() {
        let (at, asset) = (at(NOW, device(1)), device(10));
        let fields = |entity: &str, fields: &[(&str, pb::Value)]| {
            let Some(Edit::Edit(edit)) = edit(hlc(NOW, 0, device(1)), entity, asset, fields).change else {
                unreachable!()
            };
            check(&Edit::Edit(edit), &at)
        };
        let rating = |rating| value(Some(Of::Integer(rating)));
        assert_eq!(
            fields(
                "assets",
                &[
                    ("title", value(None)),
                    ("rating", rating(-1)),
                    ("trashed_at", rating(1))
                ]
            ),
            Some(Checked::Fields {
                table: "assets",
                id: asset,
                fields: vec![
                    ("rating", Bind::Small(-1)),
                    ("title", Bind::Text(None)),
                    ("trashed_at", Bind::Time(Some(NOW)))
                ],
            }),
            "a trash takes the edit's time"
        );
        assert_eq!(
            fields("asset_user_state", &[("favorite", value(Some(Of::Boolean(true))))]),
            Some(Checked::Fields {
                table: "asset_user_state",
                id: asset,
                fields: vec![("favorite", Bind::Flag(true))]
            })
        );
        for refused in [
            fields("assets", &[]),
            fields("assets", &[("rating", rating(6))]),
            fields("assets", &[("rating", text("5"))]),
            fields("assets", &[("taken_utc", rating(0))]),
            fields("assets", &[("favorite", value(Some(Of::Boolean(true))))]),
            fields("libraries", &[("title", text("x"))]),
            fields("assets", &[("title", text(&"x".repeat(MAX_TEXT + 1)))]),
            fields("album_items", &[("sort_key", text("a-b"))]),
            fields("album_items", &[("sort_key", text(""))]),
            fields("album_items", &[("sort_key", value(None))]),
        ] {
            assert_eq!(refused, None);
        }
    }

    #[test]
    fn a_member_edit_names_an_asset_of_an_album_and_a_key_when_it_adds_it() {
        let (at, asset, album) = (at(NOW, device(1)), device(10), device(11));
        let member = |entity: &str, key: &str, present| {
            let Some(Edit::Member(mut member)) = member(hlc(NOW, 0, device(1)), album, asset, present, key).change
            else {
                unreachable!()
            };
            member.entity = entity.into();
            check(&Edit::Member(member), &at)
        };
        assert_eq!(
            member("album_items", "V", true),
            Some(Checked::Member {
                album,
                asset,
                present: true,
                key: Some("V".into())
            })
        );
        assert_eq!(
            member("album_items", "V", false),
            Some(Checked::Member {
                album,
                asset,
                present: false,
                key: None
            })
        );
        assert_eq!(member("asset_tags", "V", true), None);
        assert_eq!(member("album_items", "é", true), None);
    }

    #[tokio::test]
    async fn each_field_keeps_its_latest_edit_whatever_order_the_edits_arrive_in() {
        let (_db, sync) = world().await;
        let (ann, a1) = (user(&sync, "ann").await, id(&sync, "a1").await);
        let (one, two) = (device(1), device(2));
        let (rejected, answer) = push(
            &sync,
            ann,
            &[
                edit(
                    hlc(NOW, 0, one),
                    "assets",
                    a1,
                    &[("title", text("one")), ("archived", value(Some(Of::Boolean(true))))],
                ),
                edit(
                    hlc(NOW - 1000, 0, two),
                    "assets",
                    a1,
                    &[("title", text("two")), ("rating", value(Some(Of::Integer(4))))],
                ),
                edit(
                    hlc(NOW, 1, two),
                    "asset_user_state",
                    a1,
                    &[("favorite", value(Some(Of::Boolean(true))))],
                ),
                edit(
                    hlc(NOW - 5, 0, one),
                    "asset_user_state",
                    a1,
                    &[("favorite", value(Some(Of::Boolean(false))))],
                ),
            ],
            NOW,
        )
        .await;
        assert_eq!(
            rejected,
            ["", "", "", ""],
            "an edit that loses to a later one is still applied"
        );
        let row = |column| format!("SELECT {column} FROM assets WHERE id = md5('a1')::uuid");
        assert_eq!(read(&sync, &row("title")).await, "one");
        assert_eq!(read(&sync, &row("rating")).await, "4", "the older edit's other field");
        assert_eq!(read(&sync, &row("archived")).await, "true");
        assert_eq!(
            read(&sync, &row("field_hlc ->> 'title'")).await,
            Hlc::of(&hlc(NOW, 0, one), NOW).unwrap().text()
        );
        let favourite =
            "SELECT favorite FROM asset_user_state WHERE user_id = md5('ann')::uuid AND asset_id = md5('a1')::uuid";
        assert_eq!(read(&sync, favourite).await, "true");
        assert_eq!(echoed(&answer, "assets", "id", a1, "title").as_deref(), Some("one"));
        assert_eq!(echoed(&answer, "assets", "id", a1, "rating").as_deref(), Some("4"));
        assert_eq!(
            echoed(&answer, "asset_user_state", "asset_id", a1, "favorite").as_deref(),
            Some("true")
        );
        assert_eq!(
            answer.rows.iter().map(|rows| rows.rows.len()).sum::<usize>(),
            2,
            "each row once"
        );
        assert_eq!(answer.clock.physical_ms, NOW, "the answer carries the server's clock");

        let trash = edit(
            hlc(NOW + 1, 0, one),
            "assets",
            a1,
            &[("trashed_at", value(Some(Of::Integer(0))))],
        );
        let (rejected, answer) = push(&sync, ann, &[trash], NOW + 9).await;
        assert_eq!(rejected, [""]);
        assert_eq!(
            echoed(&answer, "assets", "id", a1, "trashed_at"),
            Some((NOW + 1).to_string()),
            "to the ms"
        );
        let restore = edit(hlc(NOW + 2, 0, two), "assets", a1, &[("trashed_at", value(None))]);
        push(&sync, ann, &[restore], NOW + 9).await;
        assert_eq!(read(&sync, &row("trashed_at")).await, "NULL");
    }

    #[tokio::test]
    async fn a_mutation_applies_once_and_keeps_its_outcome() {
        let (_db, sync) = world().await;
        let (ann, vic, a1) = (
            user(&sync, "ann").await,
            user(&sync, "vic").await,
            id(&sync, "a1").await,
        );
        let title = edit(hlc(NOW, 0, device(1)), "assets", a1, &[("title", text("once"))]);
        push(&sync, ann, std::slice::from_ref(&title), NOW).await;
        sqlx::query("UPDATE assets SET title = 'since', field_hlc = '{}' WHERE id = $1")
            .bind(a1)
            .execute(&sync.pool)
            .await
            .unwrap();
        let (rejected, answer) = push(&sync, ann, &[title.clone(), title], NOW).await;
        assert_eq!(rejected, ["", ""]);
        assert_eq!(
            echoed(&answer, "assets", "id", a1, "title").as_deref(),
            Some("since"),
            "not applied again"
        );

        let refused = edit(hlc(NOW, 0, device(2)), "assets", a1, &[("title", text("vic's"))]);
        let (rejected, _) = push(&sync, vic, std::slice::from_ref(&refused), NOW).await;
        assert_eq!(rejected, [FORBIDDEN]);
        sqlx::query("UPDATE library_members SET role = 'editor' WHERE user_id = $1")
            .bind(vic.1)
            .execute(&sync.pool)
            .await
            .unwrap();
        let (rejected, _) = push(&sync, vic, &[refused], NOW).await;
        assert_eq!(rejected, [FORBIDDEN], "a retry gets the first outcome");
        assert_eq!(
            read(&sync, "SELECT title FROM assets WHERE id = md5('a1')::uuid").await,
            "since"
        );
    }

    /// A recipe that crops to the part of the picture from `x` across.
    fn crop_recipe(x: f32) -> Vec<u8> {
        use photolib_kernel::proto::model::v1::{CropOperation, EditRecipe, Operation, operation::Kind as Step};
        use prost::Message;
        let crop = CropOperation {
            x,
            y: 0.0,
            width: 1.0 - x,
            height: 1.0,
        };
        EditRecipe {
            schema_version: 1,
            operations: vec![Operation {
                operation_id: "crop".into(),
                kind: Some(Step::Crop(crop)),
                ..Default::default()
            }],
            ..Default::default()
        }
        .encode_to_vec()
    }

    fn version(at: pb::Hlc, asset: Uuid, id: Uuid, parent: Option<Uuid>, recipe: Vec<u8>) -> pb::Mutation {
        let edit = pb::VersionEdit {
            asset_id: asset.to_string(),
            version_id: id.to_string(),
            parent_id: parent.map(|p| p.to_string()).unwrap_or_default(),
            label: "Crop".into(),
            recipe,
            ..Default::default()
        };
        mutation(at, Edit::Version(Box::new(edit)))
    }

    fn current(at: pb::Hlc, asset: Uuid, version: Uuid) -> pb::Mutation {
        edit(
            at,
            "assets",
            asset,
            &[("current_version_id", text(&version.to_string()))],
        )
    }

    #[tokio::test]
    async fn a_version_is_added_once_and_a_revert_is_one_field_edit_that_changes_no_version() {
        let (_db, sync) = world().await;
        let (ann, a1) = (user(&sync, "ann").await, id(&sync, "a1").await);
        let (one, two) = (Uuid::now_v7(), Uuid::now_v7());
        let dev = device(7);
        let sql = |v: Uuid| format!("SELECT recipe_hash IS NOT NULL AND kind = 'edit' FROM versions WHERE id = '{v}'");
        let (rejected, answer) = push(
            &sync,
            ann,
            &[
                version(hlc(NOW, 0, dev), a1, one, None, crop_recipe(0.25)),
                current(hlc(NOW, 1, dev), a1, one),
            ],
            NOW,
        )
        .await;
        assert_eq!(rejected, ["", ""]);
        assert_eq!(read(&sync, &sql(one)).await, "true");
        assert_eq!(echoed(&answer, "versions", "id", one, "kind").as_deref(), Some("edit"));
        assert_eq!(echoed(&answer, "versions", "id", one, "label").as_deref(), Some("Crop"));
        assert_eq!(
            echoed(&answer, "assets", "id", a1, "current_version_id"),
            Some(one.to_string())
        );
        // The same version again, from another outbox entry, changes nothing; another recipe under its id is refused.
        let (rejected, _) = push(
            &sync,
            ann,
            &[
                version(hlc(NOW + 1, 0, dev), a1, one, None, crop_recipe(0.25)),
                version(hlc(NOW + 1, 1, dev), a1, one, None, crop_recipe(0.5)),
            ],
            NOW,
        )
        .await;
        assert_eq!(rejected, ["", INVALID]);
        // A second version, then a revert to the first by a later edit; the second stays what it was.
        let before = read(&sync, &format!("SELECT recipe FROM versions WHERE id = '{two}'")).await;
        push(
            &sync,
            ann,
            &[
                version(hlc(NOW + 2, 0, dev), a1, two, Some(one), crop_recipe(0.5)),
                current(hlc(NOW + 2, 1, dev), a1, two),
            ],
            NOW + 2,
        )
        .await;
        let held = |v: Uuid| format!("SELECT encode(recipe, 'hex') FROM versions WHERE id = '{v}'");
        let second = read(&sync, &held(two)).await;
        assert_ne!(second, before);
        let (rejected, answer) = push(&sync, ann, &[current(hlc(NOW + 3, 0, dev), a1, one)], NOW + 3).await;
        assert_eq!(rejected, [""]);
        let now = |what: &str| format!("SELECT {what} FROM assets WHERE id = md5('a1')::uuid");
        assert_eq!(read(&sync, &now("current_version_id")).await, one.to_string());
        assert_eq!(
            echoed(&answer, "assets", "id", a1, "current_version_id"),
            Some(one.to_string())
        );
        assert_eq!(read(&sync, &held(two)).await, second, "a revert changes no version");
        assert_eq!(
            read(&sync, "SELECT count(*) FROM versions WHERE asset_id = md5('a1')::uuid").await,
            "2"
        );
        // An older edit than the revert is ignored whatever the order it arrives in.
        push(&sync, ann, &[current(hlc(NOW + 2, 5, dev), a1, two)], NOW + 4).await;
        assert_eq!(read(&sync, &now("current_version_id")).await, one.to_string());
        // The parent of the second is the first.
        assert_eq!(
            read(&sync, &format!("SELECT parent_id FROM versions WHERE id = '{two}'")).await,
            one.to_string()
        );
    }

    #[tokio::test]
    async fn a_version_is_refused_for_what_may_not_be_edited_or_is_not_a_recipe() {
        let (_db, sync) = world().await;
        let (ann, vic, sam) = (
            user(&sync, "ann").await,
            user(&sync, "vic").await,
            user(&sync, "sam").await,
        );
        let (a1, b1, p1, o1) = (
            id(&sync, "a1").await,
            id(&sync, "b1").await,
            id(&sync, "p1").await,
            id(&sync, "o1").await,
        );
        let dev = device(8);
        let recipe = crop_recipe(0.25);
        let add = |asset, who: (Principal, Uuid), n: u32, recipe: Vec<u8>, parent| {
            let m = version(hlc(NOW, n, dev), asset, Uuid::now_v7(), parent, recipe);
            (who, m)
        };
        let cases = [
            (add(a1, vic, 0, recipe.clone(), None), FORBIDDEN, "a viewer"),
            (add(a1, sam, 1, recipe.clone(), None), NOT_FOUND, "out of sight"),
            (
                add(p1, ann, 2, recipe.clone(), None),
                INVALID,
                "a private library keeps recipes on devices",
            ),
            (add(o1, ann, 3, recipe.clone(), None), INVALID, "no photo"),
            (add(a1, ann, 4, vec![], None), INVALID, "no recipe"),
            (add(a1, ann, 5, vec![0xff, 0xff], None), INVALID, "garbage"),
            (
                add(a1, ann, 6, crop_recipe(1.5), None),
                INVALID,
                "a crop outside the picture",
            ),
            (
                add(a1, ann, 7, recipe.clone(), Some(Uuid::now_v7())),
                INVALID,
                "an unknown parent",
            ),
            (
                add(b1, ann, 8, recipe.clone(), Some(Uuid::nil())),
                INVALID,
                "a parent of no asset",
            ),
        ];
        for ((who, m), rejected, why) in cases {
            let (got, _) = push(&sync, who, &[m], NOW).await;
            assert_eq!(got, [rejected], "{why}");
        }
        assert_eq!(read(&sync, "SELECT count(*) FROM versions").await, "0");
        // A label of any length and an id that is no UUID.
        let mut long = version(hlc(NOW, 9, dev), a1, Uuid::now_v7(), None, recipe.clone());
        if let Some(Edit::Version(v)) = long.change.as_mut() {
            v.label = "x".repeat(201);
        }
        let mut named = version(hlc(NOW, 10, dev), a1, Uuid::now_v7(), None, recipe.clone());
        if let Some(Edit::Version(v)) = named.change.as_mut() {
            v.version_id = "not-a-uuid".into();
        }
        let (got, _) = push(&sync, ann, &[long, named], NOW).await;
        assert_eq!(got, [INVALID, INVALID]);
        // A parent that is another asset's version.
        let other = Uuid::now_v7();
        push(
            &sync,
            ann,
            &[version(hlc(NOW, 11, dev), b1, other, None, recipe.clone())],
            NOW,
        )
        .await;
        let (got, _) = push(
            &sync,
            ann,
            &[version(hlc(NOW, 12, dev), a1, Uuid::now_v7(), Some(other), recipe)],
            NOW,
        )
        .await;
        assert_eq!(got, [INVALID]);
    }

    #[tokio::test]
    async fn the_current_version_is_one_of_the_assets_own() {
        let (_db, sync) = world().await;
        let (ann, a1, b1) = (user(&sync, "ann").await, id(&sync, "a1").await, id(&sync, "b1").await);
        let (mine, theirs) = (Uuid::now_v7(), Uuid::now_v7());
        let dev = device(9);
        push(
            &sync,
            ann,
            &[
                version(hlc(NOW, 0, dev), a1, mine, None, crop_recipe(0.1)),
                version(hlc(NOW, 1, dev), b1, theirs, None, crop_recipe(0.1)),
            ],
            NOW,
        )
        .await;
        let wrong = current(hlc(NOW, 2, dev), a1, theirs);
        let missing = current(hlc(NOW, 3, dev), a1, Uuid::now_v7());
        let none = edit(hlc(NOW, 4, dev), "assets", a1, &[("current_version_id", value(None))]);
        let garbage = edit(hlc(NOW, 5, dev), "assets", a1, &[("current_version_id", text("x"))]);
        let (got, _) = push(&sync, ann, &[wrong, missing, none, garbage], NOW).await;
        assert_eq!(got, [INVALID, INVALID, INVALID, INVALID]);
        assert_eq!(
            read(
                &sync,
                "SELECT current_version_id FROM assets WHERE id = md5('a1')::uuid"
            )
            .await,
            "NULL"
        );
        let (got, _) = push(&sync, ann, &[current(hlc(NOW, 6, dev), a1, mine)], NOW).await;
        assert_eq!(got, [""]);
    }

    /// The `bbox` and `cropped` of the face `name`, as text.
    async fn face(sync: &Sync, name: &str) -> String {
        let sql = format!(
            "SELECT (SELECT string_agg(round(b::numeric, 3)::text, ' ') FROM unnest(bbox) b) || ' ' || cropped::text
             FROM faces WHERE id = md5('{name}')::uuid"
        );
        read(sync, &sql).await
    }

    #[tokio::test]
    #[allow(clippy::too_many_lines)] // one story: a crop, a turn on it, a revert, each with what the faces must be
    async fn faces_follow_the_current_version_and_come_back_with_a_revert() {
        let (_db, sync) = world().await;
        let (ann, a1) = (user(&sync, "ann").await, id(&sync, "a1").await);
        let (original, crop, turned) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
        let dev = device(11);
        sqlx::query("INSERT INTO versions (id, asset_id, kind) VALUES ($1, $2, 'original')")
            .bind(original)
            .bind(a1)
            .execute(&sync.pool)
            .await
            .unwrap();
        sqlx::query("UPDATE assets SET current_version_id = $1 WHERE id = $2")
            .bind(original)
            .bind(a1)
            .execute(&sync.pool)
            .await
            .unwrap();
        // Right of the middle, left of it, cutting the crop's edge (a quarter in), and three quarters in.
        sqlx::query(
            "INSERT INTO faces (id, asset_id, bbox, model_id) VALUES
             (md5('fa')::uuid, $1, '{0.6,0.2,0.2,0.2}', 'm'), (md5('fb')::uuid, $1, '{0.1,0.2,0.2,0.2}', 'm'),
             (md5('fc')::uuid, $1, '{0.35,0.2,0.2,0.2}', 'm'), (md5('fd')::uuid, $1, '{0.45,0.2,0.2,0.2}', 'm')",
        )
        .bind(a1)
        .execute(&sync.pool)
        .await
        .unwrap();
        // The right half of the picture.
        let half = |n, recipe| (n, recipe);
        let (_, right) = half(0, crop_recipe(0.5));
        let (rejected, _) = push(
            &sync,
            ann,
            &[
                version(hlc(NOW, 0, dev), a1, crop, Some(original), right),
                current(hlc(NOW, 1, dev), a1, crop),
            ],
            NOW,
        )
        .await;
        assert_eq!(rejected, ["", ""]);
        assert_eq!(
            face(&sync, "fa").await,
            "0.200 0.200 0.400 0.200 false",
            "in the crop's fractions"
        );
        assert_eq!(
            face(&sync, "fb").await,
            "0.100 0.200 0.200 0.200 true",
            "cut out: its last box, kept"
        );
        assert_eq!(
            face(&sync, "fc").await,
            "0.000 0.200 0.100 0.200 true",
            "a quarter of it is left"
        );
        assert_eq!(
            face(&sync, "fd").await,
            "0.000 0.200 0.300 0.200 false",
            "three quarters are left"
        );
        assert_eq!(
            read(&sync, "SELECT count(*) FROM faces WHERE version_basis = (SELECT current_version_id FROM assets WHERE id = md5('a1')::uuid)")
                .await,
            "5",
            "the four and the world's own face"
        );
        // A turn on top of the crop moves the boxes again, from where they were in the original.
        let turn = {
            use photolib_kernel::proto::model::v1::{EditRecipe, Operation, TurnOperation, operation::Kind as Step};
            use prost::Message;
            let mut recipe = EditRecipe::decode(crop_recipe(0.5).as_slice()).unwrap();
            recipe.operations.push(Operation {
                operation_id: "turn".into(),
                kind: Some(Step::Turn(TurnOperation { quarter_turns: 1 })),
                ..Default::default()
            });
            recipe.encode_to_vec()
        };
        push(
            &sync,
            ann,
            &[
                version(hlc(NOW + 1, 0, dev), a1, turned, Some(crop), turn),
                current(hlc(NOW + 1, 1, dev), a1, turned),
            ],
            NOW + 1,
        )
        .await;
        // The crop is 0.5 wide and 1 high; turned a quarter clockwise it is 1 wide and 0.5 high, and fa (0.2, 0.2)
        // of the crop's frame, 0.4 × 0.2, is at x 1 - (0.2 + 0.2) = 0.6, y 0.2 (its x), 0.2 wide and 0.4 high.
        assert_eq!(face(&sync, "fa").await, "0.600 0.200 0.200 0.400 false");
        assert_eq!(face(&sync, "fb").await, "0.100 0.200 0.200 0.200 true");
        // A revert to the original puts every face back where it was, the cut out ones included.
        push(&sync, ann, &[current(hlc(NOW + 2, 0, dev), a1, original)], NOW + 2).await;
        for (name, want) in [
            ("fa", "0.600 0.200 0.200 0.200 false"),
            ("fb", "0.100 0.200 0.200 0.200 false"),
            ("fc", "0.350 0.200 0.200 0.200 false"),
            ("fd", "0.450 0.200 0.200 0.200 false"),
        ] {
            assert_eq!(face(&sync, name).await, want, "{name} after the revert");
        }
        // Three changes of version queued one follow-up job each, whatever order they came in.
        assert_eq!(
            read(&sync, "SELECT count(*) FROM jobs WHERE type = 'follow'").await,
            "3"
        );
        push(&sync, ann, &[current(hlc(NOW + 3, 0, dev), a1, original)], NOW + 3).await;
        assert_eq!(
            read(&sync, "SELECT count(*) FROM jobs WHERE type = 'follow'").await,
            "3"
        );
    }

    #[tokio::test]
    async fn an_asset_keeps_at_most_five_hundred_versions() {
        let (_db, sync) = world().await;
        let (ann, a1) = (user(&sync, "ann").await, id(&sync, "a1").await);
        sqlx::query(
            "INSERT INTO versions (id, asset_id, kind) SELECT gen_random_uuid(), md5('a1')::uuid, 'edit'
             FROM generate_series(1, 500)",
        )
        .execute(&sync.pool)
        .await
        .unwrap();
        let add = version(hlc(NOW, 0, device(3)), a1, Uuid::now_v7(), None, crop_recipe(0.5));
        let (got, _) = push(&sync, ann, &[add], NOW).await;
        assert_eq!(got, [INVALID]);
    }

    #[tokio::test]
    async fn a_clock_more_than_five_minutes_ahead_counts_as_five_minutes_ahead() {
        let (_db, sync) = world().await;
        let (ann, a1) = (user(&sync, "ann").await, id(&sync, "a1").await);
        let (ahead, right) = (device(1), device(2));
        let year = 365 * 86_400_000;
        push(
            &sync,
            ann,
            &[edit(
                hlc(NOW + year, 0, ahead),
                "assets",
                a1,
                &[("title", text("future"))],
            )],
            NOW,
        )
        .await;
        let title = "SELECT title FROM assets WHERE id = md5('a1')::uuid";
        let later = edit(
            hlc(NOW + AHEAD_MS + 1, 0, right),
            "assets",
            a1,
            &[("title", text("later"))],
        );
        let (_, answer) = push(&sync, ann, &[later], NOW + 10 * 60_000).await;
        assert_eq!(
            read(&sync, title).await,
            "later",
            "the wrong clock does not win for ever"
        );
        assert_eq!(answer.clock.physical_ms, NOW + 10 * 60_000);
        let again = edit(hlc(NOW + year, 0, ahead), "assets", a1, &[("title", text("again"))]);
        push(&sync, ann, &[again], NOW + 10 * 60_000).await;
        assert_eq!(
            read(&sync, title).await,
            "again",
            "five minutes ahead of the server's clock then"
        );
    }

    #[tokio::test]
    async fn an_album_keeps_an_asset_by_its_latest_add_or_removal_and_its_place_by_its_latest_move() {
        let (_db, sync) = world().await;
        let ann = user(&sync, "ann").await;
        let (a1, a2, b2) = (id(&sync, "A1").await, id(&sync, "A2").await, id(&sync, "b2").await);
        let (one, two) = (device(1), device(2));
        let item = item_id(a1, b2);
        let state = "SELECT string_agg(id::text || ' ' || coalesce(sort_key, '-'), ',') FROM album_items
                     WHERE album_id = md5('A1')::uuid AND asset_id = md5('b2')::uuid";
        let expect = |key: &str| {
            if key.is_empty() {
                "NULL".to_string()
            } else {
                format!("{item} {key}")
            }
        };
        for (mutation, held) in [
            (member(hlc(NOW, 0, one), a1, b2, true, "V"), "V"),
            (member(hlc(NOW - 10, 0, two), a1, b2, false, ""), "V"),
            (member(hlc(NOW + 10, 0, two), a1, b2, false, ""), ""),
            (member(hlc(NOW + 5, 0, one), a1, b2, true, "U"), ""),
            (
                edit(hlc(NOW + 15, 0, one), "album_items", item, &[("sort_key", text("M"))]),
                "",
            ),
            (member(hlc(NOW + 12, 0, one), a1, b2, true, "W"), "M"),
            (member(hlc(NOW + 30, 0, two), a1, b2, true, "X"), "X"),
            (member(hlc(NOW + 25, 0, one), a1, b2, true, "Y"), "X"),
            (
                edit(hlc(NOW + 20, 0, one), "album_items", item, &[("sort_key", text("Z"))]),
                "X",
            ),
            (
                edit(hlc(NOW + 40, 0, one), "album_items", item, &[("sort_key", text("Z"))]),
                "Z",
            ),
            (
                edit(hlc(NOW + 45, 0, one), "album_items", item, &[("sort_key", text("P"))]),
                "P",
            ),
            (member(hlc(NOW + 35, 0, two), a1, b2, false, ""), ""),
            (member(hlc(NOW + 38, 0, two), a1, b2, true, "Q"), "P"),
        ] {
            let (rejected, _) = push(&sync, ann, &[mutation], NOW).await;
            assert_eq!(
                (rejected, read(&sync, state).await),
                (vec![String::new()], expect(held))
            );
        }
        let (_, answer) = push(&sync, ann, &[member(hlc(NOW + 50, 0, one), a1, b2, false, "")], NOW).await;
        assert_eq!(
            echoed(&answer, "album_items", "id", item, "id").as_deref(),
            Some("deleted")
        );
        let (_, answer) = push(&sync, ann, &[member(hlc(NOW + 60, 0, one), a2, b2, true, "V")], NOW).await;
        assert_eq!(
            echoed(&answer, "album_items", "id", item_id(a2, b2), "id").as_deref(),
            Some("deleted")
        );
        assert_eq!(
            read(
                &sync,
                "SELECT count(*) FROM album_items WHERE album_id = md5('A2')::uuid"
            )
            .await,
            "1",
            "an item the album held before stands for the asset"
        );

        let removed = member(hlc(NOW, 0, one), a1, id(&sync, "a1").await, false, "");
        push(&sync, ann, &[removed], NOW).await;
        assert_eq!(
            read(
                &sync,
                "SELECT count(*) FROM album_items WHERE album_id = md5('A1')::uuid AND asset_id = md5('a1')::uuid"
            )
            .await,
            "0",
            "whatever its item's id"
        );
    }

    #[tokio::test]
    async fn an_album_a_device_made_offline_keeps_its_id_title_and_contents_whatever_arrives_again() {
        let (_db, sync) = world().await;
        let (ann, vic) = (user(&sync, "ann").await, user(&sync, "vic").await);
        let (a1, b2) = (id(&sync, "a1").await, id(&sync, "b2").await);
        let (one, two) = (device(1), device(2));
        let album = Uuid::from_u128(0x0190_0000_0000_7000_8000_0000_0000_0001);
        let made = edit(
            hlc(NOW, 0, one),
            "albums",
            album,
            &[("title", text("Trip")), ("description", text("Lisbon"))],
        );
        let batch = [
            made.clone(),
            member(hlc(NOW + 1, 0, one), album, a1, true, "M"),
            member(hlc(NOW + 2, 0, one), album, b2, true, "N"),
            edit(hlc(NOW - 5, 0, two), "albums", album, &[("title", text("Older"))]),
        ];
        let (rejected, answer) = push(&sync, ann, &batch, NOW).await;
        assert_eq!(rejected, ["", "", "", ""]);
        assert_eq!(echoed(&answer, "albums", "id", album, "title").as_deref(), Some("Trip"));
        let state = format!(
            "SELECT owner_id = md5('ann')::uuid AND title = 'Trip' AND description = 'Lisbon' AND
             (SELECT count(*) FROM album_items WHERE album_id = '{album}') = 2 FROM albums WHERE id = '{album}'"
        );
        assert_eq!(read(&sync, &state).await, "true");
        let (again, _) = push(&sync, ann, &batch, NOW).await;
        assert_eq!(
            again,
            ["", "", "", ""],
            "a mutation that came before is not applied twice"
        );
        assert_eq!(read(&sync, &state).await, "true");

        let (taken, _) = push(
            &sync,
            vic,
            &[edit(hlc(NOW + 9, 0, one), "albums", album, &[("title", text("Mine"))])],
            NOW,
        )
        .await;
        assert_eq!(taken, [NOT_FOUND], "another account's album id is not its to take");
        assert_eq!(read(&sync, &state).await, "true");
        let bad = edit(
            hlc(NOW, 1, one),
            "albums",
            Uuid::now_v7(),
            &[("cover_asset_id", text("x"))],
        );
        assert_eq!(push(&sync, ann, &[bad], NOW).await.0, [INVALID]);
    }

    #[tokio::test]
    async fn hiding_an_album_or_a_library_is_the_accounts_own_and_reaches_the_assets_it_holds() {
        let (_db, sync) = world().await;
        let (ann, vic) = (user(&sync, "ann").await, user(&sync, "vic").await);
        let (a1, one) = (id(&sync, "A1").await, device(1));
        let yes = || value(Some(Of::Boolean(true)));
        let hidden = |column: &str| {
            format!(
                "SELECT count(*) FROM asset_user_state WHERE user_id = md5('ann')::uuid AND {column}
                 AND asset_id IN (SELECT asset_id FROM album_items WHERE album_id = md5('A1')::uuid)"
            )
        };
        let hide = edit(
            hlc(NOW, 0, one),
            "album_user_state",
            a1,
            &[("hide_from_timeline", yes())],
        );
        let (rejected, answer) = push(&sync, ann, &[hide], NOW).await;
        assert_eq!(rejected, [""]);
        assert_eq!(
            echoed(&answer, "album_user_state", "album_id", a1, "hide_from_timeline").as_deref(),
            Some("true")
        );
        let held = read(
            &sync,
            "SELECT count(*) FROM album_items WHERE album_id = md5('A1')::uuid",
        )
        .await;
        assert_eq!(
            read(&sync, &hidden("album_hides_timeline")).await,
            held,
            "every asset of the album"
        );
        assert_eq!(
            read(&sync, &hidden("album_hides_memories")).await,
            "0",
            "only what was hidden"
        );

        let (taken, _) = push(
            &sync,
            vic,
            &[member(hlc(NOW, 1, one), a1, id(&sync, "a1").await, false, "")],
            NOW,
        )
        .await;
        assert_eq!(taken, [FORBIDDEN], "vic may only view A1");
        let (out, _) = push(
            &sync,
            ann,
            &[member(hlc(NOW + 1, 0, one), a1, id(&sync, "a1").await, false, "")],
            NOW,
        )
        .await;
        assert_eq!(out, [""]);
        let still = read(
            &sync,
            "SELECT album_hides_timeline FROM asset_user_state WHERE asset_id = md5('a1')::uuid",
        )
        .await;
        assert_eq!(still, "false", "an asset taken out of the album shows again");

        let unhide = edit(
            hlc(NOW + 2, 0, one),
            "album_user_state",
            a1,
            &[("hide_from_timeline", value(Some(Of::Boolean(false))))],
        );
        push(&sync, ann, &[unhide], NOW).await;
        assert_eq!(read(&sync, &hidden("album_hides_timeline")).await, "0");
    }

    #[tokio::test]
    async fn hiding_a_library_is_the_accounts_own_and_needs_a_library_in_its_sight() {
        let (_db, sync) = world().await;
        let (ann, vic) = (user(&sync, "ann").await, user(&sync, "vic").await);
        let (l1, one) = (id(&sync, "L1").await, device(1));
        let yes = || value(Some(Of::Boolean(true)));
        let library = edit(
            hlc(NOW + 3, 0, one),
            "library_user_state",
            l1,
            &[("hide_from_memories", yes())],
        );
        assert_eq!(push(&sync, ann, std::slice::from_ref(&library), NOW).await.0, [""]);
        let state = "SELECT hide_from_memories FROM library_user_state WHERE library_id = md5('L1')::uuid
                     AND user_id = md5('ann')::uuid";
        assert_eq!(read(&sync, state).await, "true");
        let unseen = edit(
            hlc(NOW + 4, 0, one),
            "library_user_state",
            id(&sync, "L3").await,
            &[("hide_from_timeline", yes())],
        );
        assert_eq!(
            push(&sync, vic, &[unseen], NOW).await.0,
            [NOT_FOUND],
            "a library out of sight"
        );
    }

    #[tokio::test]
    async fn a_device_that_missed_the_emptying_cannot_bring_back_what_was_deleted() {
        let (_db, sync) = world().await;
        let ann = user(&sync, "ann").await;
        let (a1, b2) = (id(&sync, "A1").await, id(&sync, "b2").await);
        let one = device(1);
        let trash = value(Some(Of::Integer(1)));
        let (rejected, _) = push(
            &sync,
            ann,
            &[edit(hlc(NOW, 0, one), "assets", b2, &[("trashed_at", trash)])],
            NOW,
        )
        .await;
        assert_eq!(rejected, [""]);
        sqlx::query("DELETE FROM assets WHERE id = md5('b2')::uuid")
            .execute(&sync.pool)
            .await
            .unwrap();

        let stale = [
            edit(hlc(NOW + 1, 0, one), "assets", b2, &[("trashed_at", value(None))]),
            edit(
                hlc(NOW + 2, 0, one),
                "asset_user_state",
                b2,
                &[("favorite", value(Some(Of::Boolean(true))))],
            ),
            member(hlc(NOW + 3, 0, one), a1, b2, true, "M"),
        ];
        let (rejected, answer) = push(&sync, ann, &stale, NOW).await;
        assert_eq!(rejected, [NOT_FOUND; 3]);
        assert_eq!(
            echoed(&answer, "assets", "id", b2, "id").as_deref(),
            Some("deleted"),
            "the device is told"
        );
        for table in ["assets", "asset_user_state", "album_item_states", "album_items"] {
            let column = if table == "assets" { "id" } else { "asset_id" };
            let sql = format!("SELECT count(*) FROM {table} WHERE {column} = md5('b2')::uuid");
            assert_eq!(read(&sync, &sql).await, "0", "{table}");
        }
    }

    #[tokio::test]
    async fn what_a_user_may_only_see_or_not_at_all_is_refused_for_good_and_answered_with_what_the_server_holds() {
        let (_db, sync) = world().await;
        let at = hlc(NOW, 0, device(1));
        let (vic, pat) = (user(&sync, "vic").await, user(&sync, "pat").await);
        let [a1, b1, album] = [id(&sync, "a1").await, id(&sync, "b1").await, id(&sync, "A1").await];
        let flag = value(Some(Of::Boolean(true)));
        let (rejected, answer) = push(
            &sync,
            vic,
            &[
                edit(at.clone(), "assets", a1, &[("title", text("vic's"))]),
                edit(at.clone(), "asset_user_state", a1, &[("favorite", flag.clone())]),
                member(at.clone(), album, a1, false, ""),
            ],
            NOW,
        )
        .await;
        assert_eq!(
            rejected,
            [FORBIDDEN, "", FORBIDDEN],
            "a viewer keeps only their own state of what they see"
        );
        assert_eq!(echoed(&answer, "assets", "id", a1, "title").as_deref(), Some("NULL"));
        assert_eq!(
            echoed(&answer, "asset_user_state", "asset_id", a1, "favorite").as_deref(),
            Some("true")
        );

        let (rejected, answer) = push(
            &sync,
            pat,
            &[
                edit(at.clone(), "assets", b1, &[("title", text("pat's"))]),
                edit(at.clone(), "asset_user_state", b1, &[("favorite", flag.clone())]),
                edit(at.clone(), "assets", device(99), &[("title", text("gone"))]),
                edit(at.clone(), "asset_user_state", a1, &[("favorite", flag)]),
            ],
            NOW,
        )
        .await;
        assert_eq!(
            rejected,
            [NOT_FOUND, NOT_FOUND, NOT_FOUND, ""],
            "what pat's share starts after is out of sight"
        );
        assert_eq!(echoed(&answer, "assets", "id", b1, "id").as_deref(), Some("deleted"));
        assert_eq!(
            echoed(&answer, "assets", "id", device(99), "id").as_deref(),
            Some("deleted")
        );
        assert_eq!(
            read(
                &sync,
                "SELECT count(*) FROM asset_user_state WHERE asset_id = md5('b1')::uuid"
            )
            .await,
            "0"
        );
    }

    #[tokio::test]
    async fn what_no_device_may_send_is_invalid_a_private_librarys_fields_in_clear_too_and_each_outcome_is_kept() {
        let (_db, sync) = world().await;
        let at = hlc(NOW, 0, device(1));
        let (ann, edi) = (user(&sync, "ann").await, user(&sync, "edi").await);
        let [a1, p1, album] = [id(&sync, "a1").await, id(&sync, "p1").await, id(&sync, "A1").await];
        let (rejected, _) = push(
            &sync,
            ann,
            &[
                edit(at.clone(), "assets", a1, &[("rating", value(Some(Of::Integer(9))))]),
                edit(at.clone(), "assets", p1, &[("title", text("in clear"))]),
                edit(at.clone(), "assets", p1, &[("trashed_at", value(Some(Of::Integer(0))))]),
                member(at.clone(), id(&sync, "A2").await, id(&sync, "o1").await, true, "V"),
                pb::Mutation {
                    mutation_id: "not a uuid".into(),
                    ..edit(at.clone(), "assets", a1, &[("title", text("x"))])
                },
                pb::Mutation {
                    hlc: None.into(),
                    ..edit(at.clone(), "assets", a1, &[("title", text("x"))])
                },
            ],
            NOW,
        )
        .await;
        assert_eq!(
            rejected,
            [INVALID, INVALID, "", FORBIDDEN, INVALID, INVALID],
            "a private library's titles stay encrypted, its trash does not"
        );
        assert_eq!(
            read(&sync, "SELECT title FROM assets WHERE id = md5('p1')::uuid").await,
            "NULL"
        );
        let (rejected, _) = push(&sync, edi, &[member(at, album, a1, false, "")], NOW).await;
        assert_eq!(rejected, [""], "an editor removes from the album");
        let stored = "SELECT string_agg(coalesce(rejected, '-'), ',' ORDER BY rejected) FROM processed_mutations";
        assert_eq!(
            read(&sync, stored).await,
            "mutation.forbidden,mutation.invalid,mutation.invalid,mutation.invalid,-,-",
            "every outcome is kept, but of what has no id"
        );
    }

    /// splitmix64, so that a failing case runs again from its seed.
    struct Random(u64);

    impl Random {
        fn below(&mut self, n: usize) -> usize {
            self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
            let mut z = self.0;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
            ((z ^ (z >> 31)) % n as u64) as usize
        }

        fn int(&mut self, n: usize) -> i64 {
            i64::try_from(self.below(n)).unwrap()
        }
    }

    /// What one device's user did offline, at one reading of its clock: on asset `n`, or asset `n` of album `m`.
    #[derive(Clone, Debug)]
    enum Op {
        Title(usize, Option<&'static str>),
        Rating(usize, i64),
        Trash(usize, bool),
        Favourite(usize, bool),
        Member(usize, usize, bool, &'static str),
        Move(usize, usize, &'static str),
    }

    const KEYS: [&str; 5] = ["V", "Vk", "W", "a", "b"];

    /// The items both devices saw before they went offline.
    const SEEN: [(usize, usize); 2] = [(0, 0), (1, 1)];

    fn at(ms: i64, device: Uuid) -> Hlc {
        Hlc { ms, counter: 0, device }
    }

    /// A device's edits made offline, each in order of its clock, which starts `skew` ms off the server's.
    fn offline(random: &mut Random, device: Uuid, skew: i64) -> Vec<(Hlc, Op)> {
        let (mut at, mut added, mut ops) = (at(NOW + skew, device), SEEN.to_vec(), vec![]);
        for _ in 0..=random.below(16) {
            match random.int(3) {
                0 => at.counter += 1,
                step => (at.ms, at.counter) = (at.ms + step, 0),
            }
            let (asset, album) = (random.below(4), random.below(2));
            // Fewer items than assets, so that the devices' adds, moves and removals meet.
            let item = random.below(2);
            let op = match random.below(8) {
                0 => Op::Title(asset, [None, Some("x"), Some("y")][random.below(3)]),
                1 => Op::Rating(asset, random.int(7) - 1),
                2 => Op::Trash(asset, random.below(2) == 0),
                3 => Op::Favourite(asset, random.below(2) == 0),
                // A device moves only what it added itself or saw before going offline, never what it has not seen.
                4 | 5 => {
                    let (album, asset) = added[random.below(added.len())];
                    Op::Move(album, asset, KEYS[random.below(KEYS.len())])
                }
                _ => {
                    let present = random.below(3) > 0;
                    if present {
                        added.push((album, item));
                    }
                    Op::Member(album, item, present, KEYS[random.below(KEYS.len())])
                }
            };
            ops.push((at.clone(), op));
        }
        ops
    }

    /// Assets by title, rating and trash time; favourites; items' keys.
    type Outcome = (
        BTreeMap<usize, (Option<String>, i64, Option<i64>)>,
        BTreeSet<usize>,
        BTreeMap<(usize, usize), String>,
    );

    /// The state the rules give `ops`, in any order: each field's value and each item's presence from its latest
    /// edit, an item's place from its latest add or move.
    fn expected(ops: &[(Hlc, Op)]) -> Outcome {
        let mut latest: BTreeMap<String, (&Hlc, &Op)> = BTreeMap::new();
        for (at, op) in ops {
            let mut field = |name: String| {
                if latest.get(&name).is_none_or(|(held, _)| *held <= at) {
                    latest.insert(name, (at, op));
                }
            };
            match op {
                Op::Title(asset, _) => field(format!("title {asset}")),
                Op::Rating(asset, _) => field(format!("rating {asset}")),
                Op::Trash(asset, _) => field(format!("trash {asset}")),
                Op::Favourite(asset, _) => field(format!("favourite {asset}")),
                Op::Member(album, asset, present, _) => {
                    field(format!("member {album} {asset}"));
                    if *present {
                        field(format!("key {album} {asset}"));
                    }
                }
                Op::Move(album, asset, _) => field(format!("key {album} {asset}")),
            }
        }
        let mut outcome = Outcome::default();
        for asset in 0..4 {
            let at = |name: &str| latest.get(&format!("{name} {asset}")).copied();
            let title = match at("title") {
                Some((_, Op::Title(_, title))) => title.map(String::from),
                _ => None,
            };
            let rating = match at("rating") {
                Some((_, Op::Rating(_, rating))) => *rating,
                _ => 0,
            };
            let trashed = match at("trash") {
                Some((at, Op::Trash(_, true))) => Some(at.ms),
                _ => None,
            };
            outcome.0.insert(asset, (title, rating, trashed));
            if let Some((_, Op::Favourite(_, true))) = at("favourite") {
                outcome.1.insert(asset);
            }
            for album in 0..2 {
                if let Some((_, Op::Member(.., true, _))) = at(&format!("member {album}"))
                    && let Some((_, Op::Member(.., key) | Op::Move(.., key))) = at(&format!("key {album}"))
                {
                    outcome.2.insert((album, asset), key.to_string());
                }
            }
        }
        outcome
    }

    /// Ann's assets a1, a3, b1, b2 and albums A1, A2 of the world, which `Op`s name by position.
    struct Things {
        assets: Vec<Uuid>,
        albums: Vec<Uuid>,
    }

    impl Things {
        fn mutation(&self, (at, op): &(Hlc, Op)) -> pb::Mutation {
            let at = hlc(at.ms, at.counter, at.device);
            let (asset, field) = match op {
                Op::Member(album, asset, present, key) => {
                    return member(at, self.albums[*album], self.assets[*asset], *present, key);
                }
                Op::Move(album, asset, key) => {
                    let item = item_id(self.albums[*album], self.assets[*asset]);
                    return edit(at, "album_items", item, &[("sort_key", text(key))]);
                }
                Op::Title(asset, title) => (asset, ("title", value(title.map(|t| Of::Text(t.into()))))),
                Op::Rating(asset, rating) => (asset, ("rating", value(Some(Of::Integer(*rating))))),
                Op::Trash(asset, trash) => (asset, ("trashed_at", value(trash.then_some(Of::Integer(0))))),
                Op::Favourite(asset, favourite) => {
                    let flag = ("favorite", value(Some(Of::Boolean(*favourite))));
                    return edit(at, "asset_user_state", self.assets[*asset], &[flag]);
                }
            };
            edit(at, "assets", self.assets[*asset], &[field])
        }

        /// What the server holds, as `expected` gives it.
        async fn held(&self, sync: &Sync) -> Outcome {
            let position = |all: &[Uuid], id: Uuid| all.iter().position(|one| *one == id).unwrap();
            let mut held = Outcome::default();
            let rows: Vec<(Uuid, Option<String>, i16, Option<i64>)> = sqlx::query_as(
                "SELECT id, title, rating, (extract(epoch FROM trashed_at) * 1000)::int8 FROM assets WHERE id = ANY($1)",
            )
            .bind(&self.assets)
            .fetch_all(&sync.pool)
            .await
            .unwrap();
            for (asset, title, rating, trashed) in rows {
                held.0
                    .insert(position(&self.assets, asset), (title, rating.into(), trashed));
            }
            let favourites = "SELECT asset_id FROM asset_user_state WHERE favorite";
            for asset in sqlx::query_scalar(favourites).fetch_all(&sync.pool).await.unwrap() {
                held.1.insert(position(&self.assets, asset));
            }
            let items: Vec<(Uuid, Uuid, Uuid, Option<String>)> =
                sqlx::query_as("SELECT id, album_id, asset_id, sort_key FROM album_items")
                    .fetch_all(&sync.pool)
                    .await
                    .unwrap();
            for (item, album, asset, key) in items {
                assert_eq!(item, item_id(album, asset));
                let item = (position(&self.albums, album), position(&self.assets, asset));
                held.2.insert(item, key.unwrap_or_default());
            }
            held
        }
    }

    /// The two devices' mutations as the server gets them, each device's in order: the first's first (`order` 0),
    /// the second's (1) or the two interleaved at random; some sent again, as a lost answer makes a device do.
    fn arriving(random: &mut Random, sent: &[Vec<pb::Mutation>; 2], order: usize) -> Vec<pb::Mutation> {
        let (mut next, mut arriving) = ([0, 0], vec![]);
        while next[0] < sent[0].len() || next[1] < sent[1].len() {
            let first = match order {
                0 => true,
                1 => next[1] == sent[1].len(),
                _ => next[1] == sent[1].len() || random.below(2) == 0,
            };
            let from = usize::from(!first || next[0] == sent[0].len());
            arriving.push(sent[from][next[from]].clone());
            if random.below(5) > 0 {
                next[from] += 1;
            }
        }
        arriving
    }

    #[tokio::test]
    async fn two_devices_editing_offline_converge_whatever_order_their_mutations_arrive_in() {
        let (_db, sync) = world().await;
        let ann = user(&sync, "ann").await;
        let mut things = Things {
            assets: vec![],
            albums: vec![],
        };
        for name in ["a1", "a3", "b1", "b2"] {
            things.assets.push(id(&sync, name).await);
        }
        for name in ["A1", "A2"] {
            things.albums.push(id(&sync, name).await);
        }
        let reset = "UPDATE assets SET title = NULL, rating = 0, trashed_at = NULL, field_hlc = '{}';
                     DELETE FROM asset_user_state; DELETE FROM album_items; DELETE FROM album_item_states;
                     DELETE FROM processed_mutations;";
        for seed in 0..40 {
            let mut random = Random(seed);
            let seen: Vec<_> = (SEEN.iter())
                .map(|&(album, asset)| (at(NOW - 1000, device(3)), Op::Member(album, asset, true, "a")))
                .collect();
            let skew = [random.int(40), random.int(40)];
            let mut ops = offline(&mut random, device(1), skew[0]);
            let two = offline(&mut random, device(2), skew[1]);
            let sent = [
                ops.iter().map(|op| things.mutation(op)).collect::<Vec<_>>(),
                two.iter().map(|op| things.mutation(op)).collect(),
            ];
            let seen_sent: Vec<_> = seen.iter().map(|op| things.mutation(op)).collect();
            ops.extend(two);
            ops.extend(seen);
            let want = expected(&ops);
            for order in 0..3 {
                sqlx::raw_sql(reset).execute(&sync.pool).await.unwrap();
                push(&sync, ann, &seen_sent, NOW + 60_000).await;
                let size = random.below(4) + 1;
                for batch in arriving(&mut random, &sent, order).chunks(size) {
                    let (rejected, _) = push(&sync, ann, batch, NOW + 60_000).await;
                    assert!(rejected.iter().all(String::is_empty), "seed {seed}: {rejected:?}");
                }
                assert_eq!(things.held(&sync).await, want, "seed {seed}, order {order}: {ops:?}");
            }
        }
    }
}
