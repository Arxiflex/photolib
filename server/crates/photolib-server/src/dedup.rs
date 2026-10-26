//! Per-user deduplication (photolib-design docs/07 §7, ADR-0092): a file that its owner's libraries already hold is
//! linked to what holds it instead of being stored again. Only the owner's own libraries count, so that no account
//! learns whether another holds a file, and only files the scrub has not found damaged, which an upload repairs.

use std::collections::HashMap;

use photolib_authz::{Action, Kind, Principal, scope};
use sqlx::{PgPool, QueryBuilder};
use uuid::Uuid;

/// The files that hold an owner's bytes: originals and their partners, present, of assets out of the trash, in
/// libraries that are online. The owner's id follows.
const FILES: &str = "FROM asset_files f JOIN assets a ON a.id = f.asset_id JOIN libraries l ON l.id = a.library_id
    WHERE f.role IN ('original', 'original_alt', 'live_motion') AND f.state = 'present' AND a.trashed_at IS NULL
    AND l.state IN ('online', 'scanning') AND l.owner_id = ";
/// The scrub found the file `f` damaged (ADR-0234): it holds its bytes no longer.
const DAMAGED: &str = " EXISTS (SELECT FROM integrity_findings i WHERE i.store = f.storage AND i.key = f.key
    AND i.kind <> 'orphan' AND i.resolved_at IS NULL AND (i.library_id IS NULL OR i.library_id = a.library_id))";

/// For each of `hashes`, the earliest asset of `owner`'s libraries that holds it and that `who` may view.
pub async fn assets(pool: &PgPool, who: Principal, owner: Uuid, hashes: &[Vec<u8>]) -> sqlx::Result<Vec<Option<Uuid>>> {
    let mut q = QueryBuilder::new("SELECT DISTINCT ON (content_hash) * FROM (SELECT f.content_hash, f.asset_id ");
    q.push(FILES).push_bind(owner).push(" AND NOT").push(DAMAGED);
    q.push(" AND f.content_hash = ANY(").push_bind(hashes);
    q.push(") AND a.id IN (");
    scope(who, Action::View, Kind::Asset, &mut q);
    q.push(")) held ORDER BY content_hash, asset_id");
    let held: HashMap<Vec<u8>, Uuid> = q.build_query_as().fetch_all(pool).await?.into_iter().collect();
    Ok(hashes.iter().map(|hash| held.get(hash).copied()).collect())
}

/// Whether `owner`'s libraries hold `hash` already: in an asset, or in a complete upload that ingest has yet to record.
pub async fn held(pool: &PgPool, owner: Uuid, hash: &[u8]) -> sqlx::Result<bool> {
    let mut q = QueryBuilder::new("SELECT EXISTS (SELECT ");
    q.push(FILES).push_bind(owner).push(" AND NOT").push(DAMAGED);
    q.push(" AND f.content_hash = ").push_bind(hash);
    q.push(") OR EXISTS (SELECT FROM uploads u JOIN libraries l ON l.id = u.library_id");
    q.push(" WHERE u.completed_at IS NOT NULL AND u.owner_id = l.owner_id AND l.owner_id = ");
    q.push_bind(owner).push(" AND u.hash = ").push_bind(hash).push(")");
    q.build_query_scalar().fetch_one(pool).await
}

/// The files of `owner`'s that would hold `hash` but that the scrub found damaged, in stores (an external library is
/// never written), as `(store, key)`.
pub async fn damaged(pool: &PgPool, owner: Uuid, hash: &[u8]) -> sqlx::Result<Vec<(String, String)>> {
    let mut q = QueryBuilder::new("SELECT DISTINCT f.storage, f.key ");
    q.push(FILES).push_bind(owner).push(" AND").push(DAMAGED);
    q.push(" AND f.storage <> 'external' AND f.content_hash = ")
        .push_bind(hash);
    q.build_query_as().fetch_all(pool).await
}

/// Keeps the vector that upload `id` handed off for the assets of `owner`'s standard libraries that hold `hash`, unless
/// they have one of its model already: the first stays.
pub async fn hand_off(pool: &PgPool, owner: Uuid, hash: &[u8], id: Uuid) -> sqlx::Result<()> {
    let mut q = QueryBuilder::new("INSERT INTO asset_embeddings (asset_id, model_id, embedding) ");
    q.push("SELECT held.asset_id, u.embedding_model, u.embedding FROM uploads u, (SELECT DISTINCT f.asset_id ");
    q.push(FILES)
        .push_bind(owner)
        .push(" AND l.privacy = 'standard' AND f.content_hash = ");
    q.push_bind(hash).push(") held WHERE u.id = ").push_bind(id);
    q.push(" AND u.embedding IS NOT NULL ON CONFLICT DO NOTHING");
    q.build().execute(pool).await.map(drop)
}

#[cfg(test)]
mod tests {
    use photolib_db::{
        migrate::{Upgrade, embedded, upgrade},
        testpg,
    };

    use super::*;

    /// A hash finds its files through an index, however many files the libraries hold.
    #[tokio::test]
    async fn a_hash_is_found_by_an_index() {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let mut conn = db.pool.acquire().await.unwrap();
        sqlx::query("SET enable_seqscan = off")
            .execute(&mut *conn)
            .await
            .unwrap();
        let held = format!("EXPLAIN SELECT f.content_hash {FILES}$1 AND NOT{DAMAGED} AND f.content_hash = $2");
        let plan: Vec<String> = sqlx::query_scalar(&held)
            .bind(Uuid::nil())
            .bind(vec![0u8; 32])
            .fetch_all(&mut *conn)
            .await
            .unwrap();
        assert!(plan.join("\n").contains("asset_files_content_hash"), "{plan:#?}");
    }
}
