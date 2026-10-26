//! Data migrations: resumable background jobs that rewrite rows in batches, with progress in `data_migrations`.

use async_trait::async_trait;
use sqlx::{PgConnection, PgPool};

/// One rewrite of existing rows, such as a backfill. Its batches must be idempotent: a batch retried after a crash
/// finds its work already done.
#[async_trait]
pub trait DataMigration: Send + Sync {
    fn id(&self) -> &str;
    fn description(&self) -> &str;
    /// Handles the rows after `cursor`; `None` when there are none left.
    async fn batch(&self, conn: &mut PgConnection, cursor: Option<String>) -> sqlx::Result<Option<Batch>>;
    /// The rows still to handle: the progress total at the start, and zero once the migration is complete.
    async fn remaining(&self, conn: &mut PgConnection) -> sqlx::Result<i64>;
}

#[derive(Debug)]
pub struct Batch {
    pub processed: i64,
    /// Where the next batch starts.
    pub cursor: Option<String>,
}

fn text(error: sqlx::Error) -> String {
    error.to_string()
}

/// Runs `migration` until it is done or `stop` returns true. Each batch commits together with its cursor, so a
/// stopped or crashed run resumes where it left off. `Ok(true)` once the migration is done and verified.
pub async fn run(pool: &PgPool, migration: &dyn DataMigration, stop: impl Fn() -> bool) -> Result<bool, String> {
    let id = migration.id();
    let mut conn = pool.acquire().await.map_err(text)?;
    let total = migration.remaining(&mut conn).await.map_err(text)?;
    sqlx::query("INSERT INTO data_migrations (id, description, total) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING")
        .bind(id)
        .bind(migration.description())
        .bind(total)
        .execute(&mut *conn)
        .await
        .map_err(text)?;
    drop(conn);
    loop {
        let mut tx = pool.begin().await.map_err(text)?;
        let (status, cursor): (String, Option<String>) =
            sqlx::query_as("SELECT status, cursor FROM data_migrations WHERE id = $1 FOR UPDATE")
                .bind(id)
                .fetch_one(&mut *tx)
                .await
                .map_err(text)?;
        if status == "done" {
            return Ok(true);
        }
        if stop() {
            return Ok(false);
        }
        let batch = match migration.batch(&mut tx, cursor).await {
            Ok(batch) => batch,
            Err(error) => {
                drop(tx);
                return Err(fail(pool, id, format!("batch failed: {error}")).await);
            }
        };
        let Some(batch) = batch else {
            let left = migration.remaining(&mut tx).await.map_err(text)?;
            drop(tx);
            if left > 0 {
                return Err(fail(pool, id, format!("verification failed: {left} rows remain")).await);
            }
            sqlx::query(
                "UPDATE data_migrations SET status = 'done', updated_at = now(), finished_at = now() WHERE id = $1",
            )
            .bind(id)
            .execute(pool)
            .await
            .map_err(text)?;
            return Ok(true);
        };
        sqlx::query(
            "UPDATE data_migrations SET status = 'running', cursor = $2, processed = processed + $3, error = NULL,
             updated_at = now() WHERE id = $1",
        )
        .bind(id)
        .bind(batch.cursor)
        .bind(batch.processed)
        .execute(&mut *tx)
        .await
        .map_err(text)?;
        tx.commit().await.map_err(text)?;
    }
}

/// Runs `migration` to the end inside the caller's transaction and records it as done: the pre-scan of a schema
/// migration, which must also catch rows written after an earlier background run.
pub(crate) async fn finish(conn: &mut PgConnection, migration: &dyn DataMigration) -> Result<(), String> {
    let (mut cursor, mut processed) = (None, 0);
    while let Some(batch) = migration.batch(conn, cursor.take()).await.map_err(text)? {
        processed += batch.processed;
        cursor = batch.cursor;
    }
    let left = migration.remaining(conn).await.map_err(text)?;
    if left > 0 {
        return Err(format!("verification failed: {left} rows remain"));
    }
    sqlx::query(
        "INSERT INTO data_migrations (id, description, status, processed, total, finished_at)
         VALUES ($1, $2, 'done', $3, $3, now())
         ON CONFLICT (id) DO UPDATE SET status = 'done', processed = data_migrations.processed + $3, error = NULL,
         updated_at = now(), finished_at = now()",
    )
    .bind(migration.id())
    .bind(migration.description())
    .bind(processed)
    .execute(conn)
    .await
    .map_err(text)?;
    Ok(())
}

/// The data migrations of this release, in the order they run.
pub fn registry() -> Vec<Box<dyn DataMigration>> {
    Vec::new()
}

/// Moves the rows of `table` that match the SQL condition `violating` to `quarantined_rows`, as JSON. A migration
/// that adds a UNIQUE, foreign-key or NOT NULL constraint to an existing table names one as its pre-scan.
pub struct Quarantine {
    pub id: &'static str,
    pub description: &'static str,
    pub table: &'static str,
    pub violating: &'static str,
}

#[async_trait]
impl DataMigration for Quarantine {
    fn id(&self) -> &str {
        self.id
    }

    fn description(&self) -> &str {
        self.description
    }

    async fn batch(&self, conn: &mut PgConnection, _: Option<String>) -> sqlx::Result<Option<Batch>> {
        let (table, violating) = (self.table, self.violating);
        let moved = sqlx::query(&format!(
            "WITH moved AS (DELETE FROM {table} WHERE ctid IN (SELECT ctid FROM {table} WHERE {violating} LIMIT 1000)
             RETURNING *)
             INSERT INTO quarantined_rows (table_name, data_migration, data) SELECT $1, $2, to_jsonb(moved) FROM moved"
        ))
        .bind(table)
        .bind(self.id)
        .execute(conn)
        .await?
        .rows_affected() as i64;
        Ok((moved > 0).then_some(Batch {
            processed: moved,
            cursor: None,
        }))
    }

    async fn remaining(&self, conn: &mut PgConnection) -> sqlx::Result<i64> {
        sqlx::query_scalar(&format!("SELECT count(*) FROM {} WHERE {}", self.table, self.violating))
            .fetch_one(conn)
            .await
    }
}

/// One line per data migration that is not done, for the "upgrading" status.
pub async fn unfinished(pool: &PgPool) -> sqlx::Result<Vec<String>> {
    sqlx::query_scalar(
        "SELECT format('%s: %s, %s of %s', id, status, processed, coalesce(total::text, '?'))
         || coalesce(' (' || error || ')', '')
         FROM data_migrations WHERE status <> 'done' ORDER BY started_at, id",
    )
    .fetch_all(pool)
    .await
}

/// Records the failure and returns it.
async fn fail(pool: &PgPool, id: &str, error: String) -> String {
    let recorded =
        sqlx::query("UPDATE data_migrations SET status = 'failed', error = $2, updated_at = now() WHERE id = $1")
            .bind(id)
            .bind(&error)
            .execute(pool)
            .await;
    match recorded {
        Ok(_) => format!("data migration {id}: {error}"),
        Err(also) => {
            format!("data migration {id}: {error} (and recording the failure failed: {also})")
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::{
        migrate::{Migration, Upgrade, upgrade},
        testpg,
    };

    /// Marks items done, two per batch, in id order; the cursor is the last id handled.
    struct MarkDone;

    #[async_trait]
    impl DataMigration for MarkDone {
        fn id(&self) -> &str {
            "mark_done"
        }

        fn description(&self) -> &str {
            "marks every item done"
        }

        async fn batch(&self, conn: &mut PgConnection, cursor: Option<String>) -> sqlx::Result<Option<Batch>> {
            let after: i32 = cursor.map_or(0, |cursor| cursor.parse().unwrap());
            let ids: Vec<i32> = sqlx::query_scalar(
                "UPDATE items SET done = true WHERE id IN (SELECT id FROM items WHERE id > $1 ORDER BY id LIMIT 2)
                 RETURNING id",
            )
            .bind(after)
            .fetch_all(&mut *conn)
            .await?;
            Ok(ids.iter().max().map(|last| Batch {
                processed: ids.len() as i64,
                cursor: Some(last.to_string()),
            }))
        }

        async fn remaining(&self, conn: &mut PgConnection) -> sqlx::Result<i64> {
            sqlx::query_scalar("SELECT count(*) FROM items WHERE NOT done")
                .fetch_one(conn)
                .await
        }
    }

    async fn with_items(count: i32) -> testpg::TestDb {
        let db = testpg::database().await;
        let schema = [Migration::new(
            "0001_items.sql",
            "CREATE TABLE items (id int PRIMARY KEY, done boolean NOT NULL);",
        )
        .unwrap()];
        upgrade(&db.pool, &Upgrade::new(&schema)).await.unwrap();
        sqlx::query("INSERT INTO items SELECT i, false FROM generate_series(1, $1) AS i")
            .bind(count)
            .execute(&db.pool)
            .await
            .unwrap();
        db
    }

    async fn progress(db: &testpg::TestDb) -> (String, i64, Option<i64>, Option<String>) {
        sqlx::query_as("SELECT status, processed, total, cursor FROM data_migrations WHERE id = 'mark_done'")
            .fetch_one(&db.pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn a_data_migration_resumes_where_it_stopped_and_records_its_progress() {
        let db = with_items(5).await;
        let batches = AtomicUsize::new(0);
        let stop_after_one = || batches.fetch_add(1, Ordering::SeqCst) >= 1;
        assert_eq!(run(&db.pool, &MarkDone, stop_after_one).await, Ok(false));
        assert_eq!(progress(&db).await, ("running".into(), 2, Some(5), Some("2".into())));
        assert_eq!(unfinished(&db.pool).await.unwrap(), ["mark_done: running, 2 of 5"]);

        assert_eq!(run(&db.pool, &MarkDone, || false).await, Ok(true));
        assert_eq!(unfinished(&db.pool).await.unwrap(), Vec::<String>::new());
        assert_eq!(progress(&db).await, ("done".into(), 5, Some(5), Some("5".into())));
        let left: i64 = sqlx::query_scalar("SELECT count(*) FROM items WHERE NOT done")
            .fetch_one(&db.pool)
            .await
            .unwrap();
        assert_eq!(left, 0);

        assert_eq!(
            run(&db.pool, &MarkDone, || false).await,
            Ok(true),
            "a finished migration is not run again"
        );
        assert_eq!(progress(&db).await.1, 5);
    }

    /// Fails its batches, or (`gives_up`) claims to be done while rows remain.
    struct Faulty {
        gives_up: bool,
    }

    #[async_trait]
    impl DataMigration for Faulty {
        fn id(&self) -> &str {
            "mark_done"
        }

        fn description(&self) -> &str {
            "fails"
        }

        async fn batch(&self, conn: &mut PgConnection, _: Option<String>) -> sqlx::Result<Option<Batch>> {
            if self.gives_up {
                return Ok(None);
            }
            sqlx::query("UPDATE items SET done = NULL").execute(conn).await?;
            unreachable!("the update violates NOT NULL")
        }

        async fn remaining(&self, conn: &mut PgConnection) -> sqlx::Result<i64> {
            MarkDone.remaining(conn).await
        }
    }

    async fn error(db: &testpg::TestDb) -> String {
        sqlx::query_scalar("SELECT error FROM data_migrations WHERE status = 'failed'")
            .fetch_one(&db.pool)
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn failures_are_recorded_and_the_next_run_retries() {
        let db = with_items(3).await;
        let failed = run(&db.pool, &Faulty { gives_up: false }, || false).await.unwrap_err();
        assert!(
            failed.contains("mark_done") && failed.contains("null value"),
            "{failed}"
        );
        assert!(error(&db).await.contains("null value"));

        let unverified = run(&db.pool, &Faulty { gives_up: true }, || false).await.unwrap_err();
        assert!(
            unverified.contains("verification failed: 3 rows remain"),
            "{unverified}"
        );
        assert!(error(&db).await.contains("3 rows remain"));

        assert_eq!(run(&db.pool, &MarkDone, || false).await, Ok(true));
        assert_eq!(progress(&db).await, ("done".into(), 3, Some(3), Some("3".into())));
    }
}
