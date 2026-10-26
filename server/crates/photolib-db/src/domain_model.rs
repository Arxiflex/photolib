//! The baseline schema stores every entity of the domain model, docs/04-domain-model.md in the design repository.

use std::collections::BTreeSet;

use crate::{
    doctor::drift,
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};

/// Each entity of the document (its ER diagram and entity tables), the table that stores it and the fields the
/// document gives it. The document is not in this repository (ADR-0017): add an entity here when it gains one.
#[rustfmt::skip]
const ENTITIES: &[(&str, &str, &[&str])] = &[
    ("USER", "users", &["id", "handle", "display_name", "email", "role", "status", "quota_bytes", "locale", "created_at"]),
    ("USER_KEYS", "user_keys", &["user_id", "key_bundle"]),
    ("DEVICE", "devices", &["id", "user_id", "name", "platform", "app_version", "capabilities", "device_public_key", "last_seen_at", "is_trusted_node"]),
    ("LIBRARY", "libraries", &["id", "owner_id", "kind", "privacy", "access", "root_uri", "is_upload_target", "storage_template", "scan_policy", "state"]),
    ("LIBRARY_MEMBER", "library_members", &["library_id", "user_id", "role"]),
    ("ASSET", "assets", &[
        "id", "library_id", "owner_id", "original_filename", "source", "source_ref", "created_at", "content_hash",
        "media_kind", "facets", "taken_local", "tz_offset_min", "tz_name", "taken_utc", "time_source",
        "time_confidence", "time_precision", "tz_assumed", "lat", "lon", "alt", "accuracy_m", "location_source",
        "place_id", "width", "height", "orientation", "duration_ms", "fps", "codec", "bitrate", "color",
        "file_size_total", "make", "model", "lens", "focal_mm", "focal_35mm", "f_number", "exposure_s", "iso", "flash",
        "software", "raw_metadata", "title", "description", "rating", "color_label", "archived", "locked",
        "trashed_at", "field_hlc", "rights", "stack_id", "stack_order", "current_version_id", "meta_core",
        "meta_user", "meta_ml",
    ]),
    ("CUSTOM_FIELD", "custom_fields", &["id", "library_id", "name", "kind"]),
    ("ASSET_CUSTOM_VALUE", "asset_custom_values", &["asset_id", "field_id", "value"]),
    ("ASSET_FILE", "asset_files", &["id", "asset_id", "role", "storage", "key", "mime", "size", "content_hash", "state", "crypto_header", "render_spec"]),
    ("VERSION", "versions", &[
        "id", "asset_id", "parent_id", "kind", "origin", "label", "batch_id", "recipe_hash", "process_version",
        "content_key", "base_missing", "recipe", "render_file_id", "created_by_device", "created_at", "note",
    ]),
    ("STACK", "stacks", &["id", "owner_id", "kind", "cover_asset_id", "origin", "review_state", "ranking"]),
    ("ASSET_USER_STATE", "asset_user_state", &["user_id", "asset_id", "favorite", "hidden_from_memories", "last_viewed_at", "playback_position_ms"]),
    ("ASSET_EMBEDDING", "asset_embeddings", &["asset_id", "model_id", "embedding"]),
    ("ASSET_OCR", "asset_ocr", &["asset_id", "model_id", "text"]),
    ("ASSET_QUALITY", "asset_quality", &["asset_id", "model_id", "scores"]),
    ("ML_LABEL", "ml_labels", &["id", "names"]),
    ("ASSET_ML_LABEL", "asset_ml_labels", &["asset_id", "label_id", "model_id", "score"]),
    ("ALBUM_FOLDER", "album_folders", &["id", "owner_id", "parent_id", "name", "sort_key"]),
    ("ALBUM", "albums", &[
        "id", "owner_id", "folder_id", "kind", "title", "description", "cover_asset_id", "sort_mode", "layout",
        "privacy", "created_at", "query", "tag_id", "source_library_id", "encrypted_meta",
    ]),
    ("ALBUM_ITEM", "album_items", &["id", "album_id", "kind", "asset_id", "caption", "body", "anchor_asset_id", "place_id", "sort_key"]),
    ("ALBUM_MEMBER", "album_members", &["album_id", "user_id", "role"]),
    ("ALBUM_USER_STATE", "album_user_state", &["user_id", "album_id", "hide_from_timeline", "hide_from_memories"]),
    ("LIBRARY_USER_STATE", "library_user_state", &["user_id", "library_id", "hide_from_timeline", "hide_from_memories"]),
    ("LINK", "links", &["id", "album_id", "token_hash", "expires_at", "revoked_at"]),
    ("PARTNER_SHARE", "partner_shares", &["owner_id", "partner_id"]),
    ("TAG", "tags", &["id", "owner_id", "parent_id", "name", "path", "color", "is_album", "origin"]),
    ("ASSET_TAG", "asset_tags", &["asset_id", "tag_id", "origin", "confidence", "created_at"]),
    ("PERSON", "persons", &["id", "owner_id", "kind", "name", "birth_date", "cover_face_id", "hidden", "merged_into"]),
    ("FACE", "faces", &["id", "asset_id", "version_basis", "bbox", "landmarks", "model_id", "embedding", "quality", "person_id", "assignment"]),
    ("FACE_CONSTRAINT", "face_constraints", &["face_id", "person_id", "other_face_id", "kind"]),
    ("PLACE", "places", &["id", "parent_id", "level", "names"]),
    ("USER_PLACE", "user_places", &["id", "user_id", "name", "lat", "lon", "radius_m"]),
    ("MEMORY", "memories", &["id", "owner_id", "kind", "title_template", "params", "date", "asset_ids", "cover_asset_id", "state"]),
    ("JOB", "jobs", &[
        "id", "type", "payload", "status", "priority", "placement", "grant_id", "attempts", "run_after",
        "lease_owner", "lease_until", "progress", "result", "error", "idempotency_key", "created_at",
    ]),
    ("PROCESSING_GRANT", "processing_grants", &[
        "id", "user_id", "processor", "scope", "purposes", "wrapped_keys", "created_at", "expires_at", "revoked_at",
        "ledger_ref", "user_signature",
    ]),
    ("AUDIT_EVENT", "audit_events", &["id", "at", "action", "prev_hash", "hash"]),
];

#[tokio::test]
async fn the_baseline_stores_every_entity_of_the_domain_model() {
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let columns: BTreeSet<(String, String)> = sqlx::query_as(
        "SELECT table_name::text, column_name::text FROM information_schema.columns WHERE table_schema = 'public'",
    )
    .fetch_all(&db.pool)
    .await
    .unwrap()
    .into_iter()
    .collect();
    let missing: Vec<String> = ENTITIES
        .iter()
        .flat_map(|(entity, table, fields)| {
            let columns = &columns;
            fields
                .iter()
                .filter(move |field| !columns.contains(&(table.to_string(), field.to_string())))
                .map(move |field| format!("{entity}: {table}.{field}"))
        })
        .collect();
    assert!(missing.is_empty(), "missing from the schema: {missing:#?}");
    assert_eq!(drift(&db.pool, &embedded()).await.unwrap(), Vec::<String>::new());
}
