//! Versions through mutations (roadmap M8-01, ADR-0391). A `VersionEdit` adds the immutable record of one edit of an
//! asset's picture; `assets.current_version_id` is an ordinary field that the latest edit by clock decides, so a
//! revert is one edit. Whatever was found in a picture (faces, text) follows the version that is current: the faces
//! here, in the transaction of the edit that moved it; the text, the renditions and the export by jobs that the same
//! edit queues.

use std::collections::BTreeMap;

use photolib_kernel::proto::{kernel::v1::Region, model::v1::EditRecipe};
use photolib_proto::proto::photolib::sync::v1 as pb;
use prost::Message;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::edits::{self, FOLLOW};

/// The most versions an asset keeps.
pub(super) const MAX_VERSIONS: i64 = 500;
/// The longest label, in characters.
const MAX_LABEL: usize = 200;
/// A face with less than this share of its area in the picture of a version is cut out of it.
const HIDDEN_BELOW: f32 = 0.5;

/// A version to add, checked.
#[derive(Debug, PartialEq)]
pub(super) struct Add {
    pub asset: Uuid,
    pub version: Uuid,
    pub parent: Option<Uuid>,
    pub label: String,
    /// The recipe in its canonical encoding, and its SHA-256.
    pub recipe: Vec<u8>,
    pub hash: Vec<u8>,
    /// The device that made it.
    pub device: Uuid,
}

/// `edit` as a version to add, or `None` when it is no recipe the kernel accepts or names ids that are none.
pub(super) fn check(edit: &pb::VersionEdit, device: Uuid) -> Option<Add> {
    if edit.label.chars().count() > MAX_LABEL {
        return None;
    }
    let parent = match edit.parent_id.as_str() {
        "" => None,
        id => Some(id.parse().ok()?),
    };
    let checked = edits::check(&edit.recipe, (0, 0)).ok()?;
    Some(Add {
        asset: edit.asset_id.parse().ok()?,
        version: edit.version_id.parse().ok()?,
        parent,
        label: edit.label.clone(),
        recipe: checked.bytes,
        hash: checked.hash,
        device,
    })
}

/// Whether `add` is something the server may not keep, for what the database says: the asset is no picture, has all the
/// versions it may, or the version or its parent is another asset's or another recipe's under the same id.
pub(super) async fn unfit(conn: &mut PgConnection, add: &Add) -> sqlx::Result<bool> {
    let row: Option<(bool, i64, bool, Option<bool>)> = sqlx::query_as(
        "SELECT coalesce(a.media_kind = 'image', false),
                (SELECT count(*) FROM versions v WHERE v.asset_id = a.id),
                $3::uuid IS NULL OR EXISTS (SELECT FROM versions p WHERE p.id = $3 AND p.asset_id = a.id),
                (SELECT v.asset_id = a.id AND v.recipe_hash = $4 FROM versions v WHERE v.id = $2)
         FROM assets a WHERE a.id = $1",
    )
    .bind(add.asset)
    .bind(add.version)
    .bind(add.parent)
    .bind(&add.hash)
    .fetch_optional(&mut *conn)
    .await?;
    Ok(match row {
        None => false,
        Some((image, count, parent, held)) => {
            let room = held.is_some() || count < MAX_VERSIONS;
            !(image && room && parent && held.unwrap_or(true))
        }
    })
}

/// Whether `version` is none of `asset`'s.
pub(super) async fn foreign(conn: &mut PgConnection, asset: Uuid, version: Uuid) -> sqlx::Result<bool> {
    let held: bool = sqlx::query_scalar("SELECT EXISTS (SELECT FROM versions WHERE id = $1 AND asset_id = $2)")
        .bind(version)
        .bind(asset)
        .fetch_one(&mut *conn)
        .await?;
    Ok(!held)
}

/// Adds the version, unless it is there already; false when the asset is gone.
pub(super) async fn apply(tx: &mut PgConnection, add: &Add) -> sqlx::Result<bool> {
    let made = sqlx::query(
        "INSERT INTO versions (id, asset_id, parent_id, kind, origin, label, recipe_hash, process_version, recipe,
                               created_by_device)
         SELECT $1, a.id, $3, 'edit', 'app', nullif($4, ''), $5, 'recipe-1', $6, (SELECT id FROM devices WHERE id = $7)
         FROM assets a WHERE a.id = $2
         ON CONFLICT (id) DO NOTHING",
    )
    .bind(add.version)
    .bind(add.asset)
    .bind(add.parent)
    .bind(&add.label)
    .bind(&add.hash)
    .bind(&add.recipe)
    .bind(add.device)
    .execute(&mut *tx)
    .await?;
    if made.rows_affected() == 1 {
        return Ok(true);
    }
    sqlx::query_scalar("SELECT EXISTS (SELECT FROM versions WHERE id = $1 AND asset_id = $2)")
        .bind(add.version)
        .bind(add.asset)
        .fetch_one(&mut *tx)
        .await
}

/// Makes what was found in the picture of `asset` follow its current version: its faces move to the frame of that
/// version, and a job queues the rest.
pub(super) async fn follow(tx: &mut PgConnection, asset: Uuid) -> sqlx::Result<()> {
    let current: Option<Uuid> = sqlx::query_scalar("SELECT current_version_id FROM assets WHERE id = $1")
        .bind(asset)
        .fetch_one(&mut *tx)
        .await?;
    faces(tx, asset, current).await?;
    let payload = serde_json::json!({ "asset": asset }).to_string();
    let key = format!(
        "{FOLLOW}:{asset}:{}",
        current.map(|v| v.to_string()).unwrap_or_default()
    );
    let queued: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO jobs (id, type, payload, status, placement, idempotency_key)
         VALUES (photolib_uuidv7(), $1, convert_to($2, 'UTF8'), 'queued', 'server', $3)
         ON CONFLICT (idempotency_key) DO UPDATE SET status = 'queued', attempts = 0, run_after = now(), error = NULL
         WHERE jobs.status NOT IN ('queued', 'running')
         RETURNING id",
    )
    .bind(FOLLOW)
    .bind(payload)
    .bind(key)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(id) = queued {
        photolib_jobs::notify(&mut *tx, id).await?;
    }
    Ok(())
}

/// A recipe by the version that holds it; none for the original.
async fn recipe(tx: &mut PgConnection, version: Option<Uuid>) -> sqlx::Result<Option<EditRecipe>> {
    let Some(version) = version else {
        return Ok(None);
    };
    let bytes: Option<Option<Vec<u8>>> = sqlx::query_scalar("SELECT recipe FROM versions WHERE id = $1")
        .bind(version)
        .fetch_optional(&mut *tx)
        .await?;
    // A recipe the kernel does not read any more stands for nothing: the faces keep their boxes in the original.
    Ok(bytes.flatten().and_then(|b| EditRecipe::decode(b.as_slice()).ok()))
}

fn region(bbox: &[f32]) -> Option<Region> {
    let [x, y, width, height] = bbox else {
        return None;
    };
    Some(Region {
        x: *x,
        y: *y,
        width: *width,
        height: *height,
    })
}

/// The faces of `asset`, in the frame of `current`: each is placed from its box in the original's frame (`source_bbox`,
/// made from the box in its version's frame the first time), and one that less than half is left of is marked `cropped`,
/// keeping its place for a revert.
async fn faces(tx: &mut PgConnection, asset: Uuid, current: Option<Uuid>) -> sqlx::Result<()> {
    type Face = (Uuid, Vec<f32>, Option<Vec<f32>>, Option<Uuid>);
    let rows: Vec<Face> = sqlx::query_as(
        "SELECT id, bbox, source_bbox, version_basis FROM faces
         WHERE asset_id = $1 AND version_basis IS DISTINCT FROM $2 ORDER BY id FOR UPDATE",
    )
    .bind(asset)
    .bind(current)
    .fetch_all(&mut *tx)
    .await?;
    if rows.is_empty() {
        return Ok(());
    }
    let to = recipe(tx, current).await?;
    let mut basis: BTreeMap<Option<Uuid>, Option<EditRecipe>> = BTreeMap::new();
    for (_, _, _, version) in &rows {
        if !basis.contains_key(version) {
            let held = recipe(tx, *version).await?;
            basis.insert(*version, held);
        }
    }
    for (id, bbox, source, version) in rows {
        let Some(shown) = region(&bbox) else {
            continue;
        };
        // Where it is in the original: the box kept, else the box in the frame of the version it was found in, mapped back.
        let source = source.as_deref().and_then(region).unwrap_or_else(|| {
            let from = basis.get(&version).and_then(Option::as_ref);
            let back = from.map(|from| edits::map(Some(from), None, vec![shown]).unwrap_or_default());
            (back.iter().flatten().next())
                .filter(|m| m.visible > 0.0)
                .and_then(|m| m.region)
                .unwrap_or(shown)
        });
        let mapped = edits::map(None, to.as_ref(), vec![source]).unwrap_or_default();
        let (place, visible) = mapped
            .first()
            .map_or((shown, 1.0), |m| (m.region.unwrap_or(shown), m.visible));
        let cropped = visible < HIDDEN_BELOW;
        // A face the frame cuts out keeps its last box, for the clients that still list it.
        let bbox = if visible > 0.0 { place } else { shown };
        sqlx::query("UPDATE faces SET bbox = $2, source_bbox = $3, cropped = $4, version_basis = $5 WHERE id = $1")
            .bind(id)
            .bind([bbox.x, bbox.y, bbox.width, bbox.height].to_vec())
            .bind([source.x, source.y, source.width, source.height].to_vec())
            .bind(cropped)
            .bind(current)
            .execute(&mut *tx)
            .await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_label_ids_and_a_recipe_decide_whether_a_version_is_accepted() {
        let at = Uuid::nil();
        let edit = |label: &str, recipe: Vec<u8>| pb::VersionEdit {
            asset_id: Uuid::nil().to_string(),
            version_id: Uuid::now_v7().to_string(),
            label: label.into(),
            recipe,
            ..Default::default()
        };
        let good = EditRecipe {
            schema_version: 1,
            ..Default::default()
        }
        .encode_to_vec();
        assert!(check(&edit("ok", good.clone()), at).is_some());
        assert!(check(&edit(&"é".repeat(200), good.clone()), at).is_some());
        assert!(check(&edit(&"é".repeat(201), good), at).is_none());
        assert!(check(&edit("", vec![]), at).is_none(), "an empty recipe is no recipe");
    }
}
