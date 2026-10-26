//! What migration 0035 adds for edit recipes and version history (M8-01, ADR-0391): versions that never change, and the
//! columns by which faces and OCR text follow the version they were found in.

use crate::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};

const WORLD: &str = "
INSERT INTO users (id, handle, display_name) VALUES (md5('ann')::uuid, 'ann', 'Ann');
INSERT INTO libraries (id, owner_id, name, kind, root_uri) VALUES (md5('L1')::uuid, md5('ann')::uuid, 'L1', 'managed', 'L1');
INSERT INTO assets (id, library_id, owner_id, source, media_kind)
VALUES (md5('a1')::uuid, md5('L1')::uuid, md5('ann')::uuid, 'upload', 'image');
INSERT INTO versions (id, asset_id, kind) VALUES (md5('v0')::uuid, md5('a1')::uuid, 'original');
INSERT INTO versions (id, asset_id, parent_id, kind, recipe, recipe_hash, label)
VALUES (md5('v1')::uuid, md5('a1')::uuid, md5('v0')::uuid, 'edit', '\\x0801'::bytea, '\\xabcd'::bytea, 'crop');
INSERT INTO faces (id, asset_id, bbox, model_id) VALUES (md5('f1')::uuid, md5('a1')::uuid, '{0,0,1,1}', 'm');
INSERT INTO asset_ocr (asset_id, model_id, text) VALUES (md5('a1')::uuid, 'ppocr-v5', 'text');
";

#[tokio::test]
async fn a_version_keeps_its_recipe_its_parent_and_its_kind_for_good() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    sqlx::raw_sql(WORLD).execute(&db.pool).await.unwrap();
    let v1 = "id = md5('v1')::uuid";
    for change in [
        "recipe = '\\x0802'::bytea",
        "recipe = NULL",
        "recipe_hash = '\\x0000'::bytea",
        "parent_id = NULL",
        "kind = 'original'",
        "asset_id = md5('other')::uuid",
        "process_version = 'next'",
        "created_at = now() - interval '1 day'",
    ] {
        let error = sqlx::query(&format!("UPDATE versions SET {change} WHERE {v1}"))
            .execute(&db.pool)
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains("versions are immutable"), "{change}: {error}");
    }
    // What describes a version rather than defines it may change: its label, its note, the file rendered for it.
    sqlx::query(&format!(
        "UPDATE versions SET label = 'warm', note = 'n', base_missing = true WHERE {v1}"
    ))
    .execute(&db.pool)
    .await
    .unwrap();
    // A version goes only with its asset.
    sqlx::query("DELETE FROM assets WHERE id = md5('a1')::uuid")
        .execute(&db.pool)
        .await
        .unwrap();
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM versions")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    assert_eq!(left, 0);
}

#[tokio::test]
async fn faces_and_text_say_which_version_they_are_in_and_where_they_are_in_the_original() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    sqlx::raw_sql(WORLD).execute(&db.pool).await.unwrap();
    let (cropped, source): (bool, Option<Vec<f32>>) =
        sqlx::query_as("SELECT cropped, source_bbox FROM faces WHERE id = md5('f1')::uuid")
            .fetch_one(&db.pool)
            .await
            .unwrap();
    assert_eq!((cropped, source), (false, None));
    sqlx::query("UPDATE faces SET source_bbox = '{0.1,0.1,0.2,0.2}', cropped = true")
        .execute(&db.pool)
        .await
        .unwrap();
    let bad = sqlx::query("UPDATE faces SET source_bbox = '{0.1,0.1}'")
        .execute(&db.pool)
        .await;
    assert!(bad.is_err(), "a box has four numbers");
    let (version, regions): (Option<String>, Option<String>) =
        sqlx::query_as("SELECT version_id::text, regions::text FROM asset_ocr WHERE asset_id = md5('a1')::uuid")
            .fetch_one(&db.pool)
            .await
            .unwrap();
    assert_eq!((version, regions), (None, None));
    sqlx::query("UPDATE asset_ocr SET version_id = md5('v1')::uuid, regions = '[]'::jsonb")
        .execute(&db.pool)
        .await
        .unwrap();
}
