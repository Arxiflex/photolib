//! The reading side of change capture (migration 0007, ADR-0053): every synced table stamps its rows with the
//! `txid` of the transaction that last wrote them and leaves a tombstone per deleted key. Readers return changes in
//! `(txid, key)` order and only below the watermark, so a long transaction delays them but never makes them skip a row.

use std::{collections::HashSet, sync::Arc, time::Duration};

use sqlx::{PgExecutor, PgPool, Postgres, QueryBuilder, Row, postgres::PgRow};

/// A synced table: the column its stream filters by (`None` for vocabularies every client gets) and its key.
#[derive(Debug, PartialEq, Eq)]
pub struct Entity {
    pub table: &'static str,
    pub scope: Option<&'static str>,
    pub key: &'static [&'static str],
}

const fn entity(table: &'static str, scope: &'static str, key: &'static [&'static str]) -> Entity {
    Entity {
        table,
        scope: if scope.is_empty() { None } else { Some(scope) },
        key,
    }
}

/// Every synced table, as the arguments of its `sync_capture` trigger name it.
#[rustfmt::skip]
pub const ENTITIES: &[Entity] = &[
    entity("users", "id", &["id"]),
    entity("user_keys", "user_id", &["user_id"]),
    entity("devices", "user_id", &["id"]),
    entity("processing_grants", "user_id", &["id"]),
    entity("user_places", "user_id", &["id"]),
    entity("asset_user_state", "user_id", &["user_id", "asset_id"]),
    entity("album_user_state", "user_id", &["user_id", "album_id"]),
    entity("library_user_state", "user_id", &["user_id", "library_id"]),
    entity("libraries", "owner_id", &["id"]),
    entity("library_members", "user_id", &["library_id", "user_id"]),
    entity("custom_fields", "library_id", &["id"]),
    entity("assets", "library_id", &["id"]),
    entity("stacks", "owner_id", &["id"]),
    entity("asset_files", "asset_id", &["id"]),
    entity("versions", "asset_id", &["id"]),
    entity("asset_custom_values", "asset_id", &["asset_id", "field_id"]),
    entity("asset_embeddings", "asset_id", &["asset_id", "model_id"]),
    entity("asset_ocr", "asset_id", &["asset_id", "model_id"]),
    entity("asset_quality", "asset_id", &["asset_id", "model_id"]),
    entity("asset_ml_labels", "asset_id", &["asset_id", "label_id", "model_id"]),
    entity("asset_tags", "asset_id", &["asset_id", "tag_id"]),
    entity("faces", "asset_id", &["id"]),
    entity("album_folders", "owner_id", &["id"]),
    entity("albums", "owner_id", &["id"]),
    entity("album_members", "user_id", &["album_id", "user_id"]),
    entity("links", "album_id", &["id"]),
    entity("album_items", "album_id", &["id"]),
    entity("partner_shares", "partner_id", &["owner_id", "partner_id"]),
    entity("tags", "owner_id", &["id"]),
    entity("persons", "owner_id", &["id"]),
    entity("face_constraints", "face_id", &["id"]),
    entity("memories", "owner_id", &["id"]),
    entity("places", "", &["id"]),
    entity("ml_labels", "", &["id"]),
];

/// The synced table named `table`.
pub fn find(table: &str) -> Option<&'static Entity> {
    ENTITIES.iter().find(|entity| entity.table == table)
}

/// Where a reader stands in one entity's changes: the last `(txid, key)` it read. The default is the start.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Cursor {
    pub txid: u64,
    pub key: String,
}

/// A column as clients receive it: uuids, text, dates, JSON and arrays (as JSON) are text, times are milliseconds since
/// the Unix epoch.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Text(String),
    Integer(i64),
    Real(f64),
    Boolean(bool),
    Blob(Vec<u8>),
}

#[derive(Clone, Copy, Debug)]
enum Type {
    Text,
    Integer,
    Real,
    Boolean,
    Blob,
}

/// The columns of an entity that clients receive and the SQL that reads them from the row `t`. They come from the
/// catalogue, so that a migration's new column syncs without code.
#[derive(Clone, Debug)]
pub struct Columns {
    pub names: Vec<String>,
    types: Vec<Type>,
    select: String,
}

/// The columns of `entity` but `hidden`, in table order.
pub async fn columns(db: &PgPool, entity: &Entity, hidden: &[&str]) -> sqlx::Result<Columns> {
    let all: Vec<(String, String)> = sqlx::query_as(
        "SELECT attname::text, format_type(atttypid, NULL) FROM pg_attribute
         WHERE attrelid = $1::regclass AND attnum > 0 AND NOT attisdropped ORDER BY attnum",
    )
    .bind(entity.table)
    .fetch_all(db)
    .await?;
    let (mut names, mut types, mut select) = (vec![], vec![], vec![]);
    for (name, sql_type) in all.into_iter().filter(|(name, _)| !hidden.contains(&name.as_str())) {
        let (kind, sql) = match sql_type.as_str() {
            "smallint" | "integer" | "bigint" => (Type::Integer, format!("t.{name}::int8")),
            "xid8" => (Type::Integer, format!("t.{name}::text::int8")),
            "timestamp with time zone" => (
                Type::Integer,
                format!("floor(extract(epoch FROM t.{name}) * 1000)::int8"),
            ),
            "real" | "double precision" => (Type::Real, format!("t.{name}::float8")),
            "boolean" => (Type::Boolean, format!("t.{name}")),
            "bytea" => (Type::Blob, format!("t.{name}")),
            "timestamp without time zone" => (Type::Text, format!("replace(t.{name}::text, ' ', 'T')")),
            array if array.ends_with("[]") => (Type::Text, format!("array_to_json(t.{name})::text")),
            _ => (Type::Text, format!("t.{name}::text")),
        };
        select.push(format!("{sql} AS \"{name}\""));
        names.push(name);
        types.push(kind);
    }
    Ok(Columns {
        names,
        types,
        select: select.join(", "),
    })
}

impl Columns {
    fn values(&self, row: &PgRow, from: usize) -> sqlx::Result<Vec<Value>> {
        let mut values = Vec::with_capacity(self.types.len());
        for (at, kind) in self.types.iter().enumerate() {
            let at = from + at;
            let value = match kind {
                Type::Text => row.try_get::<Option<String>, _>(at)?.map(Value::Text),
                Type::Integer => row.try_get::<Option<i64>, _>(at)?.map(Value::Integer),
                Type::Real => row.try_get::<Option<f64>, _>(at)?.map(Value::Real),
                Type::Boolean => row.try_get::<Option<bool>, _>(at)?.map(Value::Boolean),
                Type::Blob => row.try_get::<Option<Vec<u8>>, _>(at)?.map(Value::Blob),
            };
            values.push(value.unwrap_or(Value::Null));
        }
        Ok(values)
    }
}

/// Pushes SQL into a reader's query: a predicate on the row `t` or the tombstone's `scope`, or a query of ids.
pub type Push = Box<dyn Fn(&mut QueryBuilder<'_, Postgres>) + Send + Sync>;

/// What a reader takes of an entity: the rows that `rows` keeps and the tombstones that `tombstones` keeps (none
/// without it). With `visible`, a row whose id in that column is not among the ids its query gives reads as deleted.
pub struct Read {
    pub entity: &'static Entity,
    pub columns: Arc<Columns>,
    pub rows: Push,
    pub tombstones: Option<Push>,
    pub visible: Option<(&'static str, Push)>,
}

/// A row written or deleted (`deleted`) by transaction `txid`; `key` is its key columns as a JSON object and `values`
/// its columns, which a deletion has none of.
#[derive(Clone, Debug, PartialEq)]
pub struct Change {
    pub txid: u64,
    pub key: String,
    pub deleted: bool,
    pub values: Vec<Value>,
}

impl Change {
    pub fn cursor(&self) -> Cursor {
        Cursor {
            txid: self.txid,
            key: self.key.clone(),
        }
    }

    /// The value of the column `name`.
    pub fn get(&self, columns: &Columns, name: &str) -> Option<&Value> {
        let at = columns.names.iter().position(|column| column == name)?;
        self.values.get(at)
    }

    fn read(row: &PgRow, columns: &Columns, from: usize) -> sqlx::Result<Change> {
        let deleted = row.try_get(2)?;
        Ok(Change {
            txid: xid(row.try_get(0)?)?,
            key: row.try_get(1)?,
            deleted,
            values: if deleted { vec![] } else { columns.values(row, from)? },
        })
    }
}

fn xid(text: String) -> sqlx::Result<u64> {
    text.parse().map_err(|error| sqlx::Error::Decode(Box::new(error)))
}

/// Pushes `jsonb_build_object('k', t.k, …)` of the key of `entity`.
fn push_key(q: &mut QueryBuilder<'_, Postgres>, entity: &Entity) {
    let key: Vec<String> = entity
        .key
        .iter()
        .map(|column| format!("'{column}', t.{column}"))
        .collect();
    q.push(format!("jsonb_build_object({})", key.join(", ")));
}

/// Marks the rows of `changes` that `read` does not see as deleted. The ids of a page are asked at once: the access
/// paths then look them up by key, where a check of each row would start its query for each.
async fn hide(db: &PgPool, read: &Read, changes: &mut [Change]) -> sqlx::Result<()> {
    let Some((column, visible)) = &read.visible else {
        return Ok(());
    };
    let id = |change: &Change| match change.get(&read.columns, column) {
        Some(Value::Text(id)) => Some(id.clone()),
        _ => None,
    };
    let ids: Vec<String> = changes.iter().filter_map(id).collect();
    if ids.is_empty() {
        return Ok(());
    }
    let mut q: QueryBuilder<'static, Postgres> = QueryBuilder::new("SELECT s.id::text FROM (");
    visible(&mut q);
    q.push(") s WHERE s.id = ANY(").push_bind(ids).push("::uuid[])");
    let seen: HashSet<String> = q.build_query_scalar().fetch_all(db).await?.into_iter().collect();
    for change in changes {
        if !change.deleted && !id(change).is_some_and(|id| seen.contains(&id)) {
            change.deleted = true;
            change.values.clear();
        }
    }
    Ok(())
}

/// Up to `limit` changes that `read` takes after `after` and below the watermark `below`, oldest first. Only the page
/// is read in full: its rows are found again by `ctid`, in the same snapshot.
pub async fn changes(db: &PgPool, read: &Read, after: &Cursor, below: u64, limit: i64) -> sqlx::Result<Vec<Change>> {
    let table = read.entity.table;
    let mut q: QueryBuilder<'static, Postgres> = QueryBuilder::new(format!(
        "SELECT c.txid::text, c.key::text, c.deleted, {} FROM (SELECT * FROM (SELECT t.txid, ",
        read.columns.select
    ));
    push_key(&mut q, read.entity);
    q.push(" AS key, false AS deleted, t.ctid AS row FROM ")
        .push(table)
        .push(" t WHERE t.txid >= ");
    q.push_bind(after.txid.to_string()).push("::xid8 AND t.txid < ");
    q.push_bind(below.to_string()).push("::xid8 AND (");
    (read.rows)(&mut q);
    q.push(")");
    if let Some(tombstones) = &read.tombstones {
        q.push(" UNION ALL SELECT txid, key, true, NULL::tid FROM tombstones WHERE entity = ")
            .push_bind(table);
        q.push(" AND txid >= ")
            .push_bind(after.txid.to_string())
            .push("::xid8 AND txid < ");
        q.push_bind(below.to_string()).push("::xid8 AND (");
        tombstones(&mut q);
        q.push(")");
    }
    q.push(") u WHERE (u.txid, u.key::text COLLATE \"C\") > (")
        .push_bind(after.txid.to_string());
    q.push("::xid8, ").push_bind(after.key.clone());
    q.push(") ORDER BY u.txid, u.key::text COLLATE \"C\" LIMIT ")
        .push_bind(limit);
    q.push(format!(
        ") c LEFT JOIN {table} t ON t.ctid = c.row ORDER BY c.txid, c.key::text COLLATE \"C\""
    ));
    let rows = q.build().fetch_all(db).await?;
    let mut page = rows
        .iter()
        .map(|row| Change::read(row, &read.columns, 3))
        .collect::<sqlx::Result<Vec<_>>>()?;
    hide(db, read, &mut page).await?;
    Ok(page)
}

/// Where the newest-first snapshot of `assets` stands: the last `(coalesce(taken_utc, '-infinity'), id)` it read.
pub type Taken = (String, String);

/// The next `limit` assets that `read` takes after `after`, newest first and undated last, but those it does not see;
/// and where the next page starts, `None` after the last.
pub async fn newest(
    db: &PgPool,
    read: &Read,
    after: Option<&Taken>,
    limit: i64,
) -> sqlx::Result<(Vec<Change>, Option<Taken>)> {
    const TAKEN: &str = "coalesce(t.taken_utc, '-infinity'::timestamptz)";
    let mut q: QueryBuilder<'static, Postgres> = QueryBuilder::new("SELECT t.txid::text, ");
    push_key(&mut q, read.entity);
    q.push(format!(
        "::text, false, p.taken::text, t.id::text, {} FROM (SELECT t.ctid AS row, {TAKEN} AS taken, t.id FROM assets t \
         WHERE (",
        read.columns.select
    ));
    (read.rows)(&mut q);
    q.push(")");
    if let Some((taken, id)) = after {
        q.push(format!(" AND ({TAKEN}, t.id) < (")).push_bind(taken.clone());
        q.push("::timestamptz, ").push_bind(id.clone()).push("::uuid)");
    }
    q.push(format!(" ORDER BY {TAKEN} DESC, t.id DESC LIMIT "));
    q.push_bind(limit);
    q.push(") p JOIN assets t ON t.ctid = p.row ORDER BY p.taken DESC, p.id DESC");
    let rows = q.build().fetch_all(db).await?;
    let next = match rows.last() {
        Some(last) if rows.len() as i64 == limit => Some((last.try_get(3)?, last.try_get(4)?)),
        _ => None,
    };
    let mut page = rows
        .iter()
        .map(|row| Change::read(row, &read.columns, 5))
        .collect::<sqlx::Result<Vec<_>>>()?;
    hide(db, read, &mut page).await?;
    page.retain(|change| !change.deleted);
    Ok((page, next))
}

/// The rows of `read`'s entity whose `column` is one of `ids`, rows a stream holds, as they are now, but those `read`
/// does not see. Its `rows` are not asked: what hangs off a row of a stream is in that stream.
pub async fn linked(db: &PgPool, read: &Read, column: &str, ids: &[String]) -> sqlx::Result<Vec<Change>> {
    found(db, read, column, ids, false).await
}

/// The rows `read` takes whose `column` is one of `ids`, as they are now, but those it does not see.
pub async fn current(db: &PgPool, read: &Read, column: &str, ids: &[String]) -> sqlx::Result<Vec<Change>> {
    found(db, read, column, ids, true).await
}

async fn found(db: &PgPool, read: &Read, column: &str, ids: &[String], rows: bool) -> sqlx::Result<Vec<Change>> {
    if ids.is_empty() {
        return Ok(vec![]);
    }
    let mut q: QueryBuilder<'static, Postgres> = QueryBuilder::new("SELECT t.txid::text, ");
    push_key(&mut q, read.entity);
    // Joined from the ids, so that the plan goes by them whatever the statistics say.
    q.push(format!("::text, false, {} FROM unnest(", read.columns.select));
    q.push_bind(ids.to_vec()).push(format!(
        "::uuid[]) AS i (id) JOIN {} t ON t.{column} = i.id",
        read.entity.table
    ));
    if rows {
        q.push(" WHERE ");
        (read.rows)(&mut q);
    }
    let rows = q.build().fetch_all(db).await?;
    let mut page = rows
        .iter()
        .map(|row| Change::read(row, &read.columns, 3))
        .collect::<sqlx::Result<Vec<_>>>()?;
    hide(db, read, &mut page).await?;
    page.retain(|change| !change.deleted);
    Ok(page)
}

/// The watermark, below which every transaction has ended, and one past the newest transaction that has ended.
pub async fn watermark(db: impl PgExecutor<'_>) -> sqlx::Result<(u64, u64)> {
    let (xmin, xmax): (String, String) =
        sqlx::query_as("SELECT pg_snapshot_xmin(s)::text, pg_snapshot_xmax(s)::text FROM pg_current_snapshot() AS s")
            .fetch_one(db)
            .await?;
    Ok((xid(xmin)?, xid(xmax)?))
}

/// Deletes the tombstones older than `retention` and raises the horizon to the newest of them; returns how many.
pub async fn purge_tombstones(db: impl PgExecutor<'_>, retention: Duration) -> sqlx::Result<u64> {
    let purged: i64 = sqlx::query_scalar(
        "WITH purged AS (DELETE FROM tombstones WHERE deleted_at < now() - make_interval(secs => $1) RETURNING txid),
         raised AS (INSERT INTO tombstone_horizon (txid) SELECT max(txid) FROM purged HAVING count(*) > 0
                    ON CONFLICT (singleton) DO UPDATE SET txid = greatest(tombstone_horizon.txid, excluded.txid))
         SELECT count(*) FROM purged",
    )
    .bind(retention.as_secs_f64())
    .fetch_one(db)
    .await?;
    Ok(purged as u64)
}

/// The newest txid of a purged tombstone. A client whose cursor is at or below it may hold rows deleted since, so
/// it starts over from a snapshot; `None` until the first purge.
pub async fn horizon(db: impl PgExecutor<'_>) -> sqlx::Result<Option<u64>> {
    let txid: Option<String> = sqlx::query_scalar("SELECT txid::text FROM tombstone_horizon")
        .fetch_optional(db)
        .await?;
    txid.map(xid).transpose()
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use sqlx::PgPool;

    use super::*;
    use crate::{
        migrate::{Upgrade, embedded, upgrade},
        testpg::{self, TestDb},
    };

    async fn migrated() -> TestDb {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        db
    }

    async fn text(db: impl PgExecutor<'_>, sql: &str, binds: &[&str]) -> String {
        binds
            .iter()
            .fold(sqlx::query_scalar(sql), |query, value| query.bind(*value))
            .fetch_one(db)
            .await
            .unwrap()
    }

    async fn user(db: impl PgExecutor<'_>) -> String {
        let sql = "INSERT INTO users (id, handle, display_name) VALUES (gen_random_uuid(), gen_random_uuid(), 'u')
                   RETURNING id::text";
        text(db, sql, &[]).await
    }

    /// Inserts a tag of `owner` with `id` (a new one if empty) and returns its key.
    async fn tag(db: impl PgExecutor<'_>, owner: &str, id: &str) -> String {
        let sql = "INSERT INTO tags (id, owner_id, name, path)
                   VALUES (coalesce(nullif($1, '')::uuid, gen_random_uuid()), $2::uuid, gen_random_uuid(), '')
                   RETURNING jsonb_build_object('id', id)::text";
        text(db, sql, &[id, owner]).await
    }

    /// The uuid in a `{"id": "…"}` key.
    fn id(key: &str) -> &str {
        &key[8..44]
    }

    /// Up to `limit` changes of `table` after `after` below the current watermark; with `scope`, only those of that
    /// scope, which does not filter a vocabulary.
    async fn page(pool: &PgPool, table: &str, scope: Option<&str>, after: &Cursor, limit: i64) -> Vec<Change> {
        let entity = find(table).unwrap();
        let columns = columns(pool, entity, &[]).await.unwrap();
        let scope = entity.scope.zip(scope.map(str::to_string));
        let (by, scope): (Option<(&str, String)>, _) = (scope.clone(), scope);
        let rows = move |q: &mut QueryBuilder<'_, Postgres>| match &by {
            Some((column, id)) => {
                q.push(format!("t.{column} = ")).push_bind(id.clone()).push("::uuid");
            }
            None => {
                q.push("true");
            }
        };
        let tombstones = move |q: &mut QueryBuilder<'_, Postgres>| match &scope {
            Some((_, id)) => {
                q.push("scope = ").push_bind(id.clone()).push("::uuid");
            }
            None => {
                q.push("true");
            }
        };
        let read = Read {
            entity,
            columns: Arc::new(columns),
            rows: Box::new(rows),
            tombstones: Some(Box::new(tombstones)),
            visible: None,
        };
        let below = watermark(pool).await.unwrap().0;
        changes(pool, &read, after, below, limit).await.unwrap()
    }

    /// Reads the changes after `cursor` until there are none, two at a time, and moves the cursor.
    async fn drain(pool: &PgPool, table: &str, scope: Option<&str>, cursor: &mut Cursor) -> Vec<Change> {
        let mut read = Vec::new();
        loop {
            let page = page(pool, table, scope, cursor, 2).await;
            let Some(last) = page.last() else {
                return read;
            };
            *cursor = last.cursor();
            read.extend(page);
        }
    }

    /// Every change of `table` in `scope` once the transactions running now have ended.
    async fn all(db: &TestDb, table: &str, scope: Option<&str>) -> Vec<(String, bool)> {
        testpg::settle(&db.pool).await;
        let read = drain(&db.pool, table, scope, &mut Cursor::default()).await;
        read.into_iter().map(|change| (change.key, change.deleted)).collect()
    }

    #[tokio::test]
    async fn a_long_transaction_that_commits_last_is_not_skipped() {
        let db = migrated().await;
        let owner = user(&db.pool).await;
        let mut long = db.pool.begin().await.unwrap();
        let early = tag(&mut *long, &owner, "").await;
        let late = tag(&db.pool, &owner, "").await;
        let mut cursor = Cursor::default();
        let before = drain(&db.pool, "tags", Some(&owner), &mut cursor).await;
        assert_eq!(before, [], "the open transaction holds back the later commit");
        long.commit().await.unwrap();
        testpg::settle(&db.pool).await;
        let read = drain(&db.pool, "tags", Some(&owner), &mut cursor).await;
        let keys: Vec<&str> = read.iter().map(|change| change.key.as_str()).collect();
        assert_eq!(keys, [early.as_str(), late.as_str()]);
        assert!(read[0].txid < read[1].txid);
    }

    struct Rng(u64);

    impl Rng {
        fn below(&mut self, n: usize) -> usize {
            self.0 ^= self.0 << 13;
            self.0 ^= self.0 >> 7;
            self.0 ^= self.0 << 17;
            (self.0 % n as u64) as usize
        }
    }

    /// Inserts, updates, deletes and inserts again tags of `owner` in transactions of random length, some of which
    /// roll back.
    async fn write(pool: PgPool, owner: String, seed: u64) {
        let mut rng = Rng(seed.wrapping_mul(0x9e37_79b9_7f4a_7c15) | 1);
        let (mut live, mut gone): (Vec<String>, Vec<String>) = Default::default();
        for round in 0..30 {
            let mut tx = pool.begin().await.unwrap();
            let (mut now_live, mut now_gone) = (live.clone(), gone.clone());
            for _ in 0..=rng.below(3) {
                match rng.below(4) {
                    0 if !now_live.is_empty() => {
                        let key = now_live.swap_remove(rng.below(now_live.len()));
                        sqlx::query("DELETE FROM tags WHERE id = $1::uuid")
                            .bind(id(&key))
                            .execute(&mut *tx)
                            .await
                            .unwrap();
                        now_gone.push(key);
                    }
                    1 if !now_live.is_empty() => {
                        sqlx::query("UPDATE tags SET color = $1 WHERE id = $2::uuid")
                            .bind(round.to_string())
                            .bind(id(&now_live[rng.below(now_live.len())]))
                            .execute(&mut *tx)
                            .await
                            .unwrap();
                    }
                    2 if !now_gone.is_empty() => {
                        let key = now_gone.swap_remove(rng.below(now_gone.len()));
                        now_live.push(tag(&mut *tx, &owner, id(&key)).await);
                    }
                    _ => now_live.push(tag(&mut *tx, &owner, "").await),
                }
            }
            let hold = match rng.below(5) {
                0 => 50 + rng.below(200),
                _ => rng.below(10),
            };
            tokio::time::sleep(Duration::from_millis(hold as u64)).await;
            if rng.below(10) == 0 {
                tx.rollback().await.unwrap();
            } else {
                tx.commit().await.unwrap();
                (live, gone) = (now_live, now_gone);
            }
        }
    }

    fn apply(replica: &mut BTreeMap<String, u64>, page: Vec<Change>) {
        for change in page {
            match change.deleted {
                true => replica.remove(&change.key),
                false => replica.insert(change.key, change.txid),
            };
        }
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_reader_following_concurrent_long_and_short_transactions_ends_with_every_row() {
        let db = migrated().await;
        let owner = user(&db.pool).await;
        let writers: Vec<_> = (1..=6)
            .map(|seed| tokio::spawn(write(db.pool.clone(), owner.clone(), seed)))
            .collect();
        let (mut replica, mut cursor, mut while_writing) = (BTreeMap::new(), Cursor::default(), 0);
        while !writers.iter().all(|writer| writer.is_finished()) {
            let page = page(&db.pool, "tags", Some(&owner), &cursor, 7).await;
            if let Some(last) = page.last() {
                cursor = last.cursor();
            }
            while_writing += page.len();
            apply(&mut replica, page);
            tokio::time::sleep(Duration::from_millis(3)).await;
        }
        for writer in writers {
            writer.await.unwrap();
        }
        testpg::settle(&db.pool).await;
        apply(&mut replica, drain(&db.pool, "tags", Some(&owner), &mut cursor).await);
        let rows: Vec<(String, String)> =
            sqlx::query_as("SELECT jsonb_build_object('id', id)::text, txid::text FROM tags WHERE owner_id = $1::uuid")
                .bind(&owner)
                .fetch_all(&db.pool)
                .await
                .unwrap();
        let live: BTreeMap<String, u64> = rows.into_iter().map(|(key, txid)| (key, xid(txid).unwrap())).collect();
        assert!(while_writing > 0, "the reader ran alongside the writers");
        assert!(live.len() > 20, "{} rows", live.len());
        assert_eq!(replica, live);
    }

    #[tokio::test]
    async fn changes_are_in_numeric_txid_order_across_a_power_of_ten() {
        let db = migrated().await;
        let owner = user(&db.pool).await;
        let first = tag(&db.pool, &owner, "").await;
        sqlx::raw_sql(
            "DO $$ DECLARE digits int := length(pg_current_xact_id()::text);
             BEGIN WHILE length(pg_current_xact_id()::text) = digits LOOP COMMIT; END LOOP; END $$",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let second = tag(&db.pool, &owner, "").await;
        let read = all(&db, "tags", Some(&owner)).await;
        assert_eq!(read, [(first, false), (second, false)]);
    }

    #[tokio::test]
    async fn a_delete_leaves_a_tombstone_in_its_scope_until_the_key_returns() {
        let db = migrated().await;
        let (owner, other) = (user(&db.pool).await, user(&db.pool).await);
        let (kept, dropped) = (tag(&db.pool, &owner, "").await, tag(&db.pool, &owner, "").await);
        sqlx::query("DELETE FROM tags WHERE id = $1::uuid")
            .bind(id(&dropped))
            .execute(&db.pool)
            .await
            .unwrap();
        let expected = [(kept.clone(), false), (dropped.clone(), true)];
        assert_eq!(all(&db, "tags", Some(&owner)).await, expected);
        assert_eq!(all(&db, "tags", Some(&other)).await, []);
        assert_eq!(all(&db, "tags", None).await, expected);

        tag(&db.pool, &owner, id(&dropped)).await;
        let mut tx = db.pool.begin().await.unwrap();
        sqlx::query("DELETE FROM tags WHERE id = $1::uuid")
            .bind(id(&kept))
            .execute(&mut *tx)
            .await
            .unwrap();
        tag(&mut *tx, &owner, id(&kept)).await;
        tx.commit().await.unwrap();
        let read = all(&db, "tags", Some(&owner)).await;
        assert_eq!(
            read,
            [(dropped, false), (kept, false)],
            "the newest write of each key, once"
        );
        let tombstones: i64 = sqlx::query_scalar("SELECT count(*) FROM tombstones")
            .fetch_one(&db.pool)
            .await
            .unwrap();
        assert_eq!(tombstones, 0);
    }

    #[tokio::test]
    async fn moving_a_composite_key_or_cascading_a_delete_leaves_tombstones_in_each_scope() {
        let db = migrated().await;
        let (owner, first, second) = (user(&db.pool).await, user(&db.pool).await, user(&db.pool).await);
        let sql = "INSERT INTO libraries (id, owner_id, name, kind, root_uri)
                   VALUES (gen_random_uuid(), $1::uuid, 'l', 'managed', 'x') RETURNING id::text";
        let library = text(&db.pool, sql, &[&owner]).await;
        let sql = "SELECT jsonb_build_object('library_id', $1::uuid, 'user_id', $2::uuid)::text";
        let was = text(&db.pool, sql, &[&library, &first]).await;
        let is = text(&db.pool, sql, &[&library, &second]).await;
        sqlx::query("INSERT INTO library_members VALUES ($1::uuid, $2::uuid, 'viewer')")
            .bind(&library)
            .bind(&first)
            .execute(&db.pool)
            .await
            .unwrap();
        sqlx::query("UPDATE library_members SET user_id = $1::uuid")
            .bind(&second)
            .execute(&db.pool)
            .await
            .unwrap();
        assert_eq!(all(&db, "library_members", Some(&first)).await, [(was.clone(), true)]);
        assert_eq!(all(&db, "library_members", Some(&second)).await, [(is.clone(), false)]);

        sqlx::query("DELETE FROM libraries").execute(&db.pool).await.unwrap();
        assert_eq!(all(&db, "library_members", Some(&second)).await, [(is, true)]);
        let gone = format!(r#"{{"id": "{library}"}}"#);
        assert_eq!(all(&db, "libraries", Some(&owner)).await, [(gone, true)]);
    }

    #[tokio::test]
    async fn shared_vocabularies_have_no_scope() {
        let db = migrated().await;
        sqlx::raw_sql(
            "INSERT INTO ml_labels VALUES ('cat', '{}'), ('dog', '{}'); DELETE FROM ml_labels WHERE id = 'cat'",
        )
        .execute(&db.pool)
        .await
        .unwrap();
        let read = all(&db, "ml_labels", Some("00000000-0000-0000-0000-000000000000")).await;
        let expected = [
            (r#"{"id": "cat"}"#.to_string(), true),
            (r#"{"id": "dog"}"#.to_string(), false),
        ];
        assert_eq!(
            read, expected,
            "one transaction, in key order; a scope does not filter a vocabulary"
        );
    }

    /// Inserts an asset of `library` with `taken_utc` (none if empty) and returns its id.
    async fn asset(db: impl PgExecutor<'_>, library: &str, taken: &str) -> String {
        let sql = "INSERT INTO assets (id, library_id, owner_id, source, taken_utc)
                   SELECT gen_random_uuid(), id, owner_id, 'upload', nullif($2, '')::timestamptz FROM libraries
                   WHERE id = $1::uuid RETURNING id::text";
        text(db, sql, &[library, taken]).await
    }

    async fn library(db: &TestDb) -> String {
        let owner = user(&db.pool).await;
        let sql = "INSERT INTO libraries (id, owner_id, name, kind, root_uri)
                   VALUES (gen_random_uuid(), $1::uuid, 'l', 'managed', 'x') RETURNING id::text";
        text(&db.pool, sql, &[&owner]).await
    }

    fn sql(sql: &'static str) -> Push {
        Box::new(move |q| {
            q.push(sql);
        })
    }

    /// Every row of `entity`, but those whose `column` is not in the ids `visible` gives, and no tombstone.
    fn every(entity: &'static Entity, columns: &Columns, column: &'static str, visible: &'static str) -> Read {
        Read {
            entity,
            columns: Arc::new(columns.clone()),
            rows: sql("true"),
            tombstones: None,
            visible: Some((column, sql(visible))),
        }
    }

    #[tokio::test]
    async fn a_row_reads_as_its_typed_columns_and_an_invisible_one_as_its_key() {
        let db = migrated().await;
        let library = library(&db).await;
        let id = asset(&db.pool, &library, "2025-05-01T10:00:00.1239Z").await;
        sqlx::query(
            "UPDATE assets SET taken_local = '2025-05-01 12:00:00.1239', rating = 4, facets = '{live,raw}',
             lat = 0.5, meta_core = '\\x0102', color = '{\"a\": 1}', raw_metadata = '{}' WHERE id = $1::uuid",
        )
        .bind(&id)
        .execute(&db.pool)
        .await
        .unwrap();
        let hidden = asset(&db.pool, &library, "").await;
        sqlx::query("UPDATE assets SET locked = true WHERE id = $1::uuid")
            .bind(&hidden)
            .execute(&db.pool)
            .await
            .unwrap();
        testpg::settle(&db.pool).await;
        let entity = find("assets").unwrap();
        let columns = columns(&db.pool, entity, &["raw_metadata", "source_ref"])
            .await
            .unwrap();
        assert!(
            !columns
                .names
                .iter()
                .any(|name| name == "raw_metadata" || name == "source_ref")
        );
        let read = every(entity, &columns, "id", "SELECT id FROM assets WHERE NOT locked");
        let below = watermark(&db.pool).await.unwrap().0;
        let read = changes(&db.pool, &read, &Cursor::default(), below, 10).await.unwrap();
        let shown = read.iter().find(|change| change.key.contains(&id)).unwrap();
        let value = |name| shown.get(&columns, name).unwrap().clone();
        assert_eq!(value("id"), Value::Text(id.clone()));
        assert_eq!(
            value("taken_utc"),
            Value::Integer(1_746_093_600_123),
            "milliseconds, rounded down"
        );
        assert_eq!(value("taken_local"), Value::Text("2025-05-01T12:00:00.1239".into()));
        assert_eq!(value("rating"), Value::Integer(4));
        assert_eq!(value("archived"), Value::Boolean(false));
        assert_eq!(value("facets"), Value::Text(r#"["live","raw"]"#.into()));
        assert_eq!(value("lat"), Value::Real(0.5));
        assert_eq!(value("meta_core"), Value::Blob(vec![1, 2]));
        assert_eq!(value("color"), Value::Text(r#"{"a": 1}"#.into()));
        assert_eq!(value("title"), Value::Null);
        assert_eq!(value("txid"), Value::Integer(shown.txid as i64));
        let locked = read.iter().find(|change| change.key.contains(&hidden)).unwrap();
        assert!(locked.deleted && locked.values.is_empty(), "{locked:?}");
    }

    #[tokio::test]
    async fn visible_assets_page_newest_first_with_the_undated_last_and_bring_what_hangs_off_them() {
        let db = migrated().await;
        let library = library(&db).await;
        let mut ids = vec![];
        for taken in ["2020-01-01Z", "", "2024-01-01Z", "2022-01-01Z", "2024-01-01Z", ""] {
            ids.push(asset(&db.pool, &library, taken).await);
        }
        let entity = find("assets").unwrap();
        let columns = columns(&db.pool, entity, &[]).await.unwrap();
        sqlx::query("UPDATE assets SET locked = true WHERE id = $1::uuid")
            .bind(&ids[3])
            .execute(&db.pool)
            .await
            .unwrap();
        let read = every(entity, &columns, "id", "SELECT id FROM assets WHERE NOT locked");
        let (mut after, mut order) = (None, vec![]);
        loop {
            let (page, next) = newest(&db.pool, &read, after.as_ref(), 4).await.unwrap();
            order.extend(
                page.into_iter()
                    .map(|change| ids.iter().position(|id| change.key.contains(id)).unwrap()),
            );
            after = next;
            if after.is_none() {
                break;
            }
        }
        let (newer, older) = if ids[2] > ids[4] { (2, 4) } else { (4, 2) };
        let (undated, other) = if ids[1] > ids[5] { (1, 5) } else { (5, 1) };
        assert_eq!(
            order,
            [newer, older, 0, undated, other],
            "ties by id, descending; a page skips what is not visible"
        );

        sqlx::query("INSERT INTO asset_files (id, asset_id, role, storage, key) SELECT gen_random_uuid(), id, 'original', 's', id::text FROM assets")
            .execute(&db.pool)
            .await
            .unwrap();
        let entity = find("asset_files").unwrap();
        let columns = super::columns(&db.pool, entity, &[]).await.unwrap();
        let read = every(entity, &columns, "asset_id", "SELECT id FROM assets");
        let files = linked(&db.pool, &read, "asset_id", &ids[..2]).await.unwrap();
        let mut owners: Vec<_> = files
            .iter()
            .map(|file| file.get(&columns, "asset_id").unwrap().clone())
            .collect();
        owners.sort_by_key(|owner| format!("{owner:?}"));
        let mut expected = vec![Value::Text(ids[0].clone()), Value::Text(ids[1].clone())];
        expected.sort_by_key(|owner| format!("{owner:?}"));
        assert_eq!(owners, expected);

        let read = Read {
            rows: sql("t.asset_id IN (SELECT id FROM assets WHERE taken_utc IS NOT NULL)"),
            ..every(entity, &columns, "asset_id", "SELECT id FROM assets")
        };
        let files = current(&db.pool, &read, "asset_id", &[ids[0].clone(), ids[1].clone()])
            .await
            .unwrap();
        let owners: Vec<_> = files
            .iter()
            .map(|file| file.get(&columns, "asset_id").unwrap())
            .collect();
        assert_eq!(
            owners,
            [&Value::Text(ids[0].clone())],
            "current rows pass the read's rows too"
        );
    }

    /// Tables that stay on the server, which no client replicates.
    const LOCAL: &[&str] = &[
        "photolib_instance",
        "schema_migrations",
        "data_migrations",
        "quarantined_rows",
        "jobs",
        "job_schedules",
        "audit_events",
        "stores",
        "file_intents",
        "integrity_findings",
        "uploads",
        "api_keys",
        "password_records",
        "password_setups",
        "sessions",
        "oidc_identities",
        "passkeys",
        "totp_secrets",
        "recovery_codes",
        "tombstones",
        "tombstone_horizon",
        "job_pauses",
        "face_consents",
        "face_scans",
        "instance_settings",
        "library_scans",
        "library_files",
        "scrubs",
        "device_backups",
        "events",
        "webhooks",
        "policy_switches",
        "account_keys",
        "unlock_paths",
        "backup_runs",
        "scan_dirs",
        "processed_mutations",
        "album_item_states",
    ];

    #[tokio::test]
    async fn every_table_is_captured_as_its_entity_says_or_stays_on_the_server() {
        let db = migrated().await;
        let tables: Vec<(String, Option<String>, Option<Vec<u8>>)> = sqlx::query_as(
            "SELECT c.relname::text, format_type(a.atttypid, NULL) || CASE WHEN a.attnotnull THEN ' not null' END,
                    t.tgargs
             FROM pg_class c
             LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'txid'
             LEFT JOIN pg_trigger t ON t.tgrelid = c.oid AND t.tgname = 'sync_capture'
             WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r' ORDER BY 1",
        )
        .fetch_all(&db.pool)
        .await
        .unwrap();
        let mut captured = Vec::new();
        for (table, txid, args) in tables {
            let Some(entity) = find(&table) else {
                assert!(
                    LOCAL.contains(&table.as_str()),
                    "{table} is neither captured nor listed as local"
                );
                continue;
            };
            assert_eq!(txid.as_deref(), Some("xid8 not null"), "{table}.txid");
            let args = String::from_utf8(args.expect(&table)).unwrap();
            let mut expected = vec![entity.scope.unwrap_or("")];
            expected.extend(entity.key);
            assert_eq!(
                args.trim_end_matches('\0').split('\0').collect::<Vec<_>>(),
                expected,
                "{table}"
            );
            captured.push(table);
        }
        assert_eq!(captured.len(), ENTITIES.len(), "every entity is a table");
    }

    #[tokio::test]
    async fn the_watermark_is_the_oldest_transaction_still_running() {
        let db = migrated().await;
        let mut tx = db.pool.begin().await.unwrap();
        let open = xid(text(&mut *tx, "SELECT pg_current_xact_id()::text", &[]).await).unwrap();
        let ended = xid(text(&db.pool, "SELECT pg_current_xact_id()::text", &[]).await).unwrap();
        let (xmin, xmax) = watermark(&db.pool).await.unwrap();
        assert!(
            xmin <= open && open < ended && ended < xmax,
            "{xmin} <= {open} < {ended} < {xmax}"
        );
        tx.commit().await.unwrap();
        testpg::settle(&db.pool).await;
        assert!(watermark(&db.pool).await.unwrap().0 > open);
    }

    #[tokio::test]
    async fn purging_drops_expired_tombstones_and_only_ever_raises_the_horizon() {
        let db = migrated().await;
        let owner = user(&db.pool).await;
        let mut txids = Vec::new();
        for _ in 0..3 {
            let key = tag(&db.pool, &owner, "").await;
            let txid: String =
                sqlx::query_scalar("DELETE FROM tags WHERE id = $1::uuid RETURNING pg_current_xact_id()::text")
                    .bind(id(&key))
                    .fetch_one(&db.pool)
                    .await
                    .unwrap();
            txids.push(txid);
        }
        let age = |txid: &str, days: i32| {
            sqlx::query("UPDATE tombstones SET deleted_at = now() - make_interval(days => $2) WHERE txid = $1::xid8")
                .bind(txid.to_string())
                .bind(days)
                .execute(&db.pool)
        };
        let retention = Duration::from_secs(90 * 86_400);
        assert_eq!(purge_tombstones(&db.pool, retention).await.unwrap(), 0);
        assert_eq!(horizon(&db.pool).await.unwrap(), None);

        age(&txids[1], 91).await.unwrap();
        age(&txids[2], 89).await.unwrap();
        assert_eq!(purge_tombstones(&db.pool, retention).await.unwrap(), 1);
        let newest = xid(txids[1].clone()).unwrap();
        assert_eq!(horizon(&db.pool).await.unwrap(), Some(newest));

        age(&txids[0], 120).await.unwrap();
        assert_eq!(purge_tombstones(&db.pool, retention).await.unwrap(), 1);
        assert_eq!(
            horizon(&db.pool).await.unwrap(),
            Some(newest),
            "an older purge never lowers it"
        );
        let left: Vec<String> = sqlx::query_scalar("SELECT txid::text FROM tombstones")
            .fetch_all(&db.pool)
            .await
            .unwrap();
        assert_eq!(left, [txids[2].clone()]);
    }

    #[tokio::test]
    async fn a_tombstone_dated_2100_outlives_the_purge() {
        let db = migrated().await;
        let owner = user(&db.pool).await;
        let key = tag(&db.pool, &owner, "").await;
        let sql = "DELETE FROM tags WHERE id = $1::uuid RETURNING pg_current_xact_id()::text";
        let txid = text(&db.pool, sql, &[id(&key)]).await;
        sqlx::query("UPDATE tombstones SET deleted_at = '2100-01-01T00:00:00Z'")
            .execute(&db.pool)
            .await
            .unwrap();
        assert_eq!(purge_tombstones(&db.pool, Duration::ZERO).await.unwrap(), 0);
        assert_eq!(horizon(&db.pool).await.unwrap(), None);
        let left: Vec<String> = sqlx::query_scalar("SELECT txid::text FROM tombstones")
            .fetch_all(&db.pool)
            .await
            .unwrap();
        assert_eq!(left, [txid]);
    }
}
