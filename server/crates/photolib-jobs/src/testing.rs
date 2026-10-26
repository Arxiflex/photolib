use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use std::time::Duration;

use sqlx::{PgPool, Postgres};
use uuid::Uuid;

use crate::Timing;

pub fn fast() -> Timing {
    Timing {
        lease: Duration::from_millis(400),
        retry: Duration::from_millis(50),
        poll_min: Duration::from_millis(10),
        poll_max: Duration::from_millis(50),
        tick: Duration::from_millis(50),
        reconcile: Duration::from_secs(3600),
    }
}

pub async fn exec(pool: &PgPool, sql: &str, id: Uuid) {
    sqlx::query(sql).bind(id).execute(pool).await.unwrap();
}

pub async fn scalar<T>(pool: &PgPool, sql: &str, id: Uuid) -> T
where
    T: for<'r> sqlx::Decode<'r, Postgres> + sqlx::Type<Postgres> + Send + Unpin,
{
    sqlx::query_scalar(sql).bind(id).fetch_one(pool).await.unwrap()
}

/// Waits until the job has `expected` status, for at most ten seconds.
pub async fn until(pool: &PgPool, id: Uuid, expected: &str) {
    let started = photolib_spawn::Running::start();
    loop {
        let status: String = scalar(pool, "SELECT status FROM jobs WHERE id = $1", id).await;
        if status == expected {
            return;
        }
        assert!(
            started.elapsed() < Duration::from_secs(10),
            "job {id} is {status}, not {expected}"
        );
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

/// An active processing grant to the server, of a user of its own.
pub async fn grant(pool: &PgPool) -> Uuid {
    sqlx::query_scalar(
        "WITH owner AS (INSERT INTO users (id, handle, display_name)
           VALUES (photolib_uuidv7(), gen_random_uuid()::text, 'Ann') RETURNING id)
         INSERT INTO processing_grants (id, user_id, processor, scope, purposes, user_signature)
         SELECT photolib_uuidv7(), id, 'server', '{}', '{thumbs}', '\\x00' FROM owner RETURNING id",
    )
    .fetch_one(pool)
    .await
    .unwrap()
}

/// A fresh database with every migration applied.
pub async fn database() -> PgPool {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    db.pool
}

pub async fn library(pool: &PgPool, privacy: &str) -> Uuid {
    sqlx::query_scalar(
        "WITH owner AS (INSERT INTO users (id, handle, display_name)
           VALUES (photolib_uuidv7(), gen_random_uuid()::text, 'Ann') RETURNING id)
         INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri)
         SELECT photolib_uuidv7(), id, 'Photos', 'managed', $1, 'file:///photos' FROM owner RETURNING id",
    )
    .bind(privacy)
    .fetch_one(pool)
    .await
    .unwrap()
}

pub async fn asset(pool: &PgPool, library: Uuid, kind: &str) -> Uuid {
    sqlx::query_scalar(
        "INSERT INTO assets (id, library_id, owner_id, source, media_kind)
         SELECT photolib_uuidv7(), id, owner_id, 'upload', $2 FROM libraries WHERE id = $1 RETURNING id",
    )
    .bind(library)
    .bind(kind)
    .fetch_one(pool)
    .await
    .unwrap()
}
