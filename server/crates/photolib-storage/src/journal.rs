//! Journaled file operations (photolib-design docs/07 §6, ADR-0022 point 3, ADR-0041). Every put, move and delete is
//! an intent in PostgreSQL: planned (the key reserved) → written and verified → switched in the caller's transaction,
//! with the caller's rows → finished (the replaced object deleted) → done; a put is done once switched. Recovery rolls
//! back a planned intent and completes a switched one, so after a crash every object has its rows or is gone. Each
//! process holds an advisory lock for its intents: recovery takes over only those of processes that are gone. A
//! delayed delete (ADR-0089) is switched with a due time and left to the purge.

use std::{path::Path, time::Duration};

use sqlx::{PgConnection, PgPool, Row, postgres::PgRow};
use uuid::Uuid;

use crate::{Error, Hash, Hook, Local, Meta, Result, marker::Stores};

/// Unfinished uploads older than this belong to no running operation.
const STALE: std::time::Duration = std::time::Duration::from_secs(24 * 3600);

pub struct Journal {
    pool: PgPool,
    stores: Stores,
    owner: i64,
    /// Holds the advisory lock `owner` while this journal lives.
    _lock: PgConnection,
    hook: Option<Hook>,
}

/// What a recovery pass did; `busy` intents belong to a process that is still running or a store that is offline.
#[derive(Debug, Default)]
pub struct Recovered {
    pub rolled_back: usize,
    pub completed: usize,
    pub busy: usize,
}

struct Intent {
    id: Uuid,
    kind: String,
    store: String,
    key: String,
    source: Option<String>,
    meta: Option<Meta>,
}

impl Intent {
    fn from_row(row: &PgRow) -> Result<Intent> {
        let hash: Option<Vec<u8>> = row.try_get("hash")?;
        let size: Option<i64> = row.try_get("size")?;
        let meta = match (hash, size) {
            (Some(hash), Some(size)) => Some(Meta {
                size: size as u64,
                hash: Some(Hash(
                    hash.try_into()
                        .map_err(|_| Error::Other("a malformed intent hash".into()))?,
                )),
            }),
            _ => None,
        };
        Ok(Intent {
            id: row.try_get("id")?,
            kind: row.try_get("kind")?,
            store: row.try_get("store")?,
            key: row.try_get("key")?,
            source: row.try_get("source")?,
            meta,
        })
    }
}

/// A planned operation whose bytes are in place. The caller switches it in the transaction that records its rows, then
/// finishes it.
pub struct Op<'a> {
    journal: &'a Journal,
    intent: Intent,
}

impl Op<'_> {
    pub async fn switch(&self, tx: &mut PgConnection) -> Result<()> {
        let switched = sqlx::query(
            "UPDATE file_intents SET state = CASE kind WHEN 'put' THEN 'done' ELSE 'switched' END, \
             finished_at = CASE kind WHEN 'put' THEN now() END WHERE id = $1 AND state = 'planned'",
        )
        .bind(self.intent.id)
        .execute(tx)
        .await?;
        match switched.rows_affected() {
            1 => Ok(()),
            _ => Err(Error::Other(format!(
                "the intent for {:?} was rolled back",
                self.intent.key
            ))),
        }
    }

    /// A put replaces nothing, so it can switch and finish in the caller's transaction: a job's writes then commit
    /// with the job, or roll back for recovery.
    pub async fn settle(self, tx: &mut PgConnection) -> Result<()> {
        if self.intent.kind != "put" {
            return Err(Error::Other(format!("a {} cannot settle", self.intent.kind)));
        }
        self.switch(tx).await
    }

    /// After the switch committed: deletes what the operation replaced and closes the intent.
    pub async fn finish(self) -> Result<()> {
        self.journal.complete(&self.intent).await
    }

    /// Rolls back an operation the caller will not switch, deleting what it wrote.
    pub async fn abandon(self) -> Result<()> {
        self.journal.roll_back(&self.intent).await
    }
}

impl Journal {
    pub async fn start(pool: PgPool, stores: Stores) -> Result<Journal> {
        let owner = Uuid::now_v7().as_u64_pair().1 as i64;
        let mut lock = pool.acquire().await?.detach();
        sqlx::query("SELECT pg_advisory_lock($1)")
            .bind(owner)
            .execute(&mut lock)
            .await?;
        Ok(Journal {
            pool,
            stores,
            owner,
            _lock: lock,
            hook: None,
        })
    }

    /// Called at each step; crash-injection tests stop the process there.
    pub fn with_hook(mut self, hook: Hook) -> Journal {
        self.hook = Some(hook);
        self
    }

    pub fn stores(&self) -> &Stores {
        &self.stores
    }

    fn step(&self, name: &str) -> Result<()> {
        self.hook.as_ref().map_or(Ok(()), |hook| hook(name))
    }

    /// Writes a staged file under a new key and verifies it.
    pub async fn put(&self, store: &str, key: &str, staged: &Path, hash: Hash) -> Result<Op<'_>> {
        let size = std::fs::metadata(staged)
            .map_err(|e| Error::Other(format!("cannot read {}: {e}", staged.display())))?
            .len();
        let meta = Meta { size, hash: Some(hash) };
        let intent = self
            .plan("put", store, key, Some(staged.display().to_string()), Some(meta))
            .await?;
        let written = self.stores.get(store)?.put(key, staged, hash).await;
        self.written(intent, written.map(drop)).await
    }

    /// Writes `bytes`, such as a marker, under a new key.
    pub async fn put_bytes(&self, store: &str, key: &str, bytes: &[u8]) -> Result<Op<'_>> {
        let fail = |e: std::io::Error| Error::Other(format!("cannot stage {key}: {e}"));
        let staged = tempfile::NamedTempFile::new().map_err(fail)?;
        std::fs::write(staged.path(), bytes).map_err(fail)?;
        self.put(store, key, staged.path(), Hash::of(bytes)).await
    }

    /// Moves `from` to a new key in the same store: a copy verified against `hash`, then, once switched, a delete.
    pub async fn relocate(&self, store: &str, from: &str, to: &str, hash: Hash) -> Result<Op<'_>> {
        // Within one store nothing passes through scratch.
        (self.transfer("move", (store, from), (store, to), hash, Path::new(""))).await
    }

    /// Copies `from` to a new key `to`, both `(store, key)`, verified against `hash`: server-side within a store, else
    /// through a checked copy in `scratch`. Once switched the copy is a put that is done; the source stays.
    pub async fn copy(&self, from: (&str, &str), to: (&str, &str), hash: Hash, scratch: &Path) -> Result<Op<'_>> {
        self.transfer("put", from, to, hash, scratch).await
    }

    async fn transfer(
        &self,
        kind: &str,
        (store, from): (&str, &str),
        (to_store, to): (&str, &str),
        hash: Hash,
        scratch: &Path,
    ) -> Result<Op<'_>> {
        let (blobs, target) = (self.stores.get(store)?, self.stores.get(to_store)?);
        let found = blobs.head(from).await?.ok_or_else(|| Error::NotFound(from.into()))?;
        let meta = Meta {
            size: found.size,
            hash: Some(hash),
        };
        let mismatch = |found| Error::Integrity(format!("{from:?} is {found:?}, expected {meta:?}"));
        if found.hash.is_some_and(|found| found != hash) {
            return Err(mismatch(found));
        }
        let intent = self.plan(kind, to_store, to, Some(from.into()), Some(meta)).await?;
        let copied = match store == to_store {
            true => match blobs.copy(from, to).await {
                // A source without a recorded hash was hashed while copied: the copy carries what it really holds.
                Ok(copied) if copied != meta => {
                    let _ = blobs.delete(to).await;
                    Err(mismatch(copied))
                }
                copied => copied.map(drop),
            },
            false => {
                async {
                    let dir = tempfile::tempdir_in(scratch).map_err(|e| Error::Other(format!("scratch: {e}")))?;
                    let (Local::InPlace(path) | Local::Copy(path)) = blobs.local(from, hash, dir.path()).await?;
                    target.put(to, &path, hash).await.map(drop)
                }
                .await
            }
        };
        self.written(intent, copied).await
    }

    /// Deletes a key once the caller's rows no longer point at it.
    pub async fn delete(&self, store: &str, key: &str) -> Result<Op<'_>> {
        let intent = self.plan("delete", store, key, None, None).await?;
        Ok(Op { journal: self, intent })
    }

    /// Deletes `key` once `grace` has passed, in the transaction that stops the caller's rows naming it. The key stays
    /// reserved until the purge has deleted it.
    pub async fn delete_after(&self, tx: &mut PgConnection, store: &str, key: &str, grace: Duration) -> Result<()> {
        sqlx::query(
            "INSERT INTO file_intents (id, owner, kind, store, key, state, due) \
             VALUES ($1, $2, 'delete', $3, $4, 'switched', now() + make_interval(secs => $5))",
        )
        .bind(Uuid::now_v7())
        .bind(self.owner)
        .bind(store)
        .bind(key)
        .bind(grace.as_secs_f64())
        .execute(tx)
        .await
        .map_err(|e| reserved(e, key))?;
        Ok(())
    }

    /// Does the delayed deletes that are due in online stores, whoever made them; returns how many.
    pub async fn purge(&self) -> Result<usize> {
        let online: Vec<&str> = self.stores.online().map(|(name, _)| name).collect();
        let mut purged = 0;
        loop {
            let mut tx = self.pool.begin().await?;
            // Locked until it is closed, so that no other purge deletes the key once a new put may take it.
            let due: Option<(Uuid, String, String)> = sqlx::query_as(
                "SELECT id, store, key FROM file_intents WHERE state = 'switched' AND due <= now() \
                 AND store = ANY($1) ORDER BY due LIMIT 1 FOR UPDATE SKIP LOCKED",
            )
            .bind(&online)
            .fetch_optional(&mut *tx)
            .await?;
            let Some((id, store, key)) = due else {
                return Ok(purged);
            };
            self.stores.get(&store)?.delete(&key).await?;
            self.step("deleted")?;
            sqlx::query("UPDATE file_intents SET state = 'done', finished_at = now() WHERE id = $1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
            purged += 1;
        }
    }

    /// The object as a local file for a job; bytes that do not match `hash` are an integrity finding, recorded once
    /// while it is open.
    pub async fn local(&self, store: &str, key: &str, hash: Hash, scratch: &Path) -> Result<Local> {
        let local = self.stores.get(store)?.local(key, hash, scratch).await;
        if let Err(Error::Integrity(why)) = &local {
            self.found(store, key, why).await?;
        }
        local
    }

    /// Records that the bytes of `key` in `store` do not match their hash, once while that finding is open.
    pub async fn found(&self, store: &str, key: &str, why: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO integrity_findings (id, store, key, detail) SELECT $1, $2, $3, $4 WHERE NOT EXISTS
               (SELECT FROM integrity_findings WHERE store = $2 AND key = $3 AND kind = 'content'
                 AND resolved_at IS NULL)",
        )
        .bind(Uuid::now_v7())
        .bind(store)
        .bind(key)
        .bind(why)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn plan(
        &self,
        kind: &str,
        store: &str,
        key: &str,
        source: Option<String>,
        meta: Option<Meta>,
    ) -> Result<Intent> {
        let blobs = self.stores.get(store)?;
        if kind != "delete" && blobs.head(key).await?.is_some() {
            return Err(Error::Exists(key.into()));
        }
        let intent = Intent {
            id: Uuid::now_v7(),
            kind: kind.into(),
            store: store.into(),
            key: key.into(),
            source,
            meta,
        };
        sqlx::query(
            "INSERT INTO file_intents (id, owner, kind, store, key, source, hash, size) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
        )
        .bind(intent.id)
        .bind(self.owner)
        .bind(kind)
        .bind(store)
        .bind(key)
        .bind(&intent.source)
        .bind(meta.and_then(|m| m.hash).map(|h| h.0.to_vec()))
        .bind(meta.map(|m| m.size as i64))
        .execute(&self.pool)
        .await
        .map_err(|e| reserved(e, key))?;
        self.step("planned")?;
        Ok(intent)
    }

    async fn written(&self, intent: Intent, written: Result<()>) -> Result<Op<'_>> {
        match written.and_then(|()| self.step("written")) {
            Ok(()) => Ok(Op { journal: self, intent }),
            Err(error) => {
                // Should this fail too, recovery after the next start rolls it back.
                let _ = self.roll_back(&intent).await;
                Err(error)
            }
        }
    }

    async fn close(&self, intent: &Intent, from: &str, to: &str) -> Result<()> {
        sqlx::query("UPDATE file_intents SET state = $3, finished_at = now() WHERE id = $1 AND state = $2")
            .bind(intent.id)
            .bind(from)
            .bind(to)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    /// Deletes what a planned put or move wrote, recognised by its size and hash, and its unfinished uploads.
    async fn roll_back(&self, intent: &Intent) -> Result<()> {
        let store = self.stores.get(&intent.store)?;
        if intent.kind != "delete" {
            if store.head(&intent.key).await? == intent.meta {
                store.delete(&intent.key).await?;
            }
            for upload in store.uploads(&intent.key).await? {
                if upload.key == intent.key {
                    store.abort(&upload).await?;
                }
            }
        }
        self.close(intent, "planned", "rolled_back").await
    }

    /// Deletes the source of a switched move or the key of a switched delete, and closes the intent.
    async fn complete(&self, intent: &Intent) -> Result<()> {
        let store = self.stores.get(&intent.store)?;
        let replaced = match (intent.kind.as_str(), &intent.source) {
            ("move", Some(source)) => Some(source),
            ("delete", _) => Some(&intent.key),
            _ => None,
        };
        if let Some(key) = replaced {
            store.delete(key).await?;
            self.step("deleted")?;
        }
        self.close(intent, "switched", "done").await
    }

    /// Completes this process's switched intents whose callers could not finish them, such as a job's, which commit
    /// after its handler returns; returns how many. Planned intents are left to their callers, delayed deletes to the
    /// purge.
    pub async fn finish_switched(&self) -> Result<usize> {
        let rows = sqlx::query(
            "SELECT id, kind, store, key, source, hash, size FROM file_intents \
             WHERE owner = $1 AND state = 'switched' AND due IS NULL ORDER BY id",
        )
        .bind(self.owner)
        .fetch_all(&self.pool)
        .await?;
        for row in &rows {
            self.complete(&Intent::from_row(row)?).await?;
        }
        Ok(rows.len())
    }

    /// Rolls back or completes the open intents of processes that are gone, then aborts stale uploads.
    pub async fn recover(&self) -> Result<Recovered> {
        let mut recovered = Recovered::default();
        let owners: Vec<i64> = sqlx::query_scalar(
            "SELECT DISTINCT owner FROM file_intents \
             WHERE state IN ('planned', 'switched') AND due IS NULL AND owner <> $1",
        )
        .bind(self.owner)
        .fetch_all(&self.pool)
        .await?;
        let mut conn = self.pool.acquire().await?;
        for owner in owners {
            let free: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock($1)")
                .bind(owner)
                .fetch_one(&mut *conn)
                .await?;
            // Read only under the lock: a running owner may still switch or finish what it planned.
            let rows = sqlx::query(
                "SELECT id, kind, store, key, source, hash, size, state FROM file_intents \
                 WHERE owner = $1 AND state IN ('planned', 'switched') AND due IS NULL ORDER BY id",
            )
            .bind(owner)
            .fetch_all(&mut *conn)
            .await?;
            if !free {
                recovered.busy += rows.len();
                continue;
            }
            for row in rows {
                let intent = Intent::from_row(&row)?;
                if self.stores.get(&intent.store).is_err() {
                    recovered.busy += 1;
                } else if row.try_get::<&str, _>("state")? == "planned" {
                    self.roll_back(&intent).await?;
                    recovered.rolled_back += 1;
                } else {
                    self.complete(&intent).await?;
                    recovered.completed += 1;
                }
            }
            sqlx::query("SELECT pg_advisory_unlock($1)")
                .bind(owner)
                .execute(&mut *conn)
                .await?;
        }
        for (_, store) in self.stores.online() {
            for upload in store.uploads("").await? {
                if upload.started.elapsed().is_ok_and(|age| age > STALE) {
                    store.abort(&upload).await?;
                }
            }
        }
        Ok(recovered)
    }
}

fn reserved(error: sqlx::Error, key: &str) -> Error {
    match error {
        sqlx::Error::Database(e) if e.is_unique_violation() => Error::Exists(format!("{key} (reserved)")),
        e => e.into(),
    }
}
