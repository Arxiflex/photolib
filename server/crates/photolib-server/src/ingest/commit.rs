//! The rows an ingested file becomes: an asset with its files, sidecars, tags and first version, in the job's
//! transaction.

use photolib_kernel::proto::{
    kernel::v1::{Pace, ReadMetadataResponse},
    model::v1::CaptureTimePrecision as P,
};
use serde_json::Value;
use sqlx::PgConnection;
use uuid::Uuid;

use super::{
    Motion, Read, Sidecar, Source,
    group::{self, Role},
    sniff::{self, Kind},
};
use crate::external;

/// What a file says replaces what an asset checked again (`retype`) has, but for what a user wrote.
const RETYPED: &str = " ON CONFLICT (id) DO UPDATE SET media_kind = excluded.media_kind, facets = excluded.facets,
    taken_local = excluded.taken_local, tz_offset_min = excluded.tz_offset_min, tz_name = excluded.tz_name,
    taken_utc = excluded.taken_utc, time_source = excluded.time_source, time_confidence = excluded.time_confidence,
    time_precision = excluded.time_precision, lat = excluded.lat, lon = excluded.lon, alt = excluded.alt,
    location_source = excluded.location_source, width = excluded.width, height = excluded.height,
    orientation = excluded.orientation, duration_ms = excluded.duration_ms, fps = excluded.fps, codec = excluded.codec,
    color = excluded.color, make = excluded.make, model = excluded.model, raw_metadata = excluded.raw_metadata,
    title = coalesce(assets.title, excluded.title), description = coalesce(assets.description, excluded.description),
    rating = CASE assets.rating WHEN 0 THEN excluded.rating ELSE assets.rating END,
    color_label = coalesce(assets.color_label, excluded.color_label), burst_id = excluded.burst_id,
    sniff_version = excluded.sniff_version";

/// Commits one asset, its tags and its version v0, as the current one, or what its file says to the asset `retyped`,
/// with what its `sidecars` say, oldest metadata first. Returns the asset's id.
pub async fn asset(
    tx: &mut PgConnection,
    files: &[(&Source, &Read, Role)],
    sidecars: &[&ReadMetadataResponse],
    dump: Option<Value>,
    retyped: Option<Uuid>,
) -> sqlx::Result<Uuid> {
    let [(upload, read, _), ..] = files else {
        unreachable!("an asset has an original");
    };
    let (metadata, located) = merged(&read.extraction.metadata, sidecars);
    let (metadata, capture) = (&metadata, &read.extraction.capture);
    let time = capture.capture_time.clone().unwrap_or_default();
    let (name, path) = match upload.path.as_deref() {
        Some(path) => (path.rsplit('/').next(), Some(path)),
        None => (None, None),
    };
    let turned = (5..=8).contains(&metadata.orientation);
    let (width, height) = match turned {
        true => (metadata.height, metadata.width),
        false => (metadata.width, metadata.height),
    };
    let precision = match time.precision() {
        P::Year => Some("year"),
        P::Month => Some("month"),
        P::Day => Some("day"),
        P::Minute => Some("minute"),
        P::Second => Some("second"),
        P::Millisecond => Some("ms"),
        P::Unspecified => None,
    };
    // A wall clock known to the year or month starts at its first day.
    let local = match time.local_datetime.len() {
        0 => None,
        4 => Some(format!("{}-01-01", time.local_datetime)),
        7 => Some(format!("{}-01", time.local_datetime)),
        _ => Some(time.local_datetime.clone()),
    };
    let utc = capture
        .taken_at
        .as_ref()
        .map(|at| at.seconds as f64 + f64::from(at.nanos) / 1e9);
    let hdr = matches!(metadata.transfer, 16 | 18) || metadata.dolby_vision;
    let facets: Vec<&str> = [
        (files.iter().any(|f| f.2 == Role::LiveMotion), "live"),
        (files.iter().any(|f| f.2 == Role::OriginalAlt), "raw_jpeg_pair"),
        (files.len() == 1 && group::raw(&read.media), "raw"),
        (metadata.motion_video.is_some(), "motion_photo"),
        (metadata.panorama.is_some(), "sphere_360"),
        (hdr, "hdr"),
        (!metadata.burst_id.is_empty(), "burst_member"),
        (metadata.spatial, "spatial"),
        (metadata.depth, "portrait_depth"),
        (metadata.pace() == Pace::SlowMotion, "slow_motion"),
        (metadata.pace() == Pace::TimeLapse, "time_lapse"),
    ]
    .into_iter()
    .filter_map(|(has, facet)| has.then_some(facet))
    .collect();
    let location = metadata.location.as_ref();
    let text = |s: &str| Some(s.to_owned()).filter(|s| !s.is_empty());
    let id = retyped.unwrap_or_else(Uuid::now_v7);
    let retype = if retyped.is_some() { RETYPED } else { "" };
    sqlx::query(&format!(
        "INSERT INTO assets (id, library_id, owner_id, original_filename, source, source_ref, content_hash, media_kind,
           facets, taken_local, tz_offset_min, tz_name, taken_utc, time_source, time_confidence, time_precision, lat,
           lon, alt, location_source, width, height, orientation, duration_ms, codec, color, file_size_total, make,
           model, raw_metadata, title, description, rating, color_label, burst_id, sniff_version, fps)
         VALUES ($1, $2, $3, $4, $34, $5, $6, $7, $8, $9::timestamp, $10, $11, to_timestamp($12), $13, $14, $15,
           $16, $17, $18, $37, $19, $20, $21, $22, $23, $24, $25, $26, $27,
           $28, $29, $30, coalesce($31, 0), $32, $33, $35, $36){retype}"
    ))
    .bind(id)
    .bind(upload.library)
    .bind(upload.owner)
    .bind(name)
    .bind(path)
    .bind(&upload.hash)
    .bind(match (read.media.supported(), read.media.kind) {
        (true, Kind::Image) => Some("image"),
        (true, Kind::Video) => Some("video"),
        _ => None,
    })
    .bind(&facets)
    .bind(local)
    .bind(time.offset_minutes)
    .bind(time.zone)
    .bind(utc)
    .bind(text(&time.source).unwrap_or_else(|| "unknown".into()))
    .bind(time.confidence.min(100) as i16)
    .bind(precision)
    .bind(location.map(|l| l.latitude))
    .bind(location.map(|l| l.longitude))
    .bind(location.and_then(|l| l.altitude_m))
    .bind(Some(width as i32).filter(|&w| w > 0))
    .bind(Some(height as i32).filter(|&h| h > 0))
    .bind(Some(metadata.orientation as i16).filter(|&o| o > 0))
    .bind(Some(metadata.duration_ms as i64).filter(|&d| d > 0))
    .bind(text(&metadata.codec))
    .bind(hdr.then(|| serde_json::json!({"transfer": metadata.transfer, "dolby_vision": metadata.dolby_vision})))
    .bind(files.iter().map(|f| f.0.length).sum::<i64>())
    .bind(text(&metadata.make))
    .bind(text(&metadata.model))
    .bind(dump)
    .bind(text(&metadata.title))
    .bind(text(&metadata.description))
    .bind(metadata.rating.map(|r| r.clamp(-1, 5) as i16))
    .bind(text(&metadata.label))
    .bind(text(&metadata.burst_id))
    .bind(upload.source)
    .bind(sniff::VERSION)
    .bind(Some(metadata.frame_rate).filter(|r| r.is_finite() && *r > 0.0))
    .bind(location.map(|_| if located { "sidecar" } else { "exif" }))
    .execute(&mut *tx)
    .await?;
    tags(tx, upload.owner, id, metadata).await?;
    if retyped.is_some() {
        return Ok(id);
    }
    let version = Uuid::now_v7();
    sqlx::query("INSERT INTO versions (id, asset_id, kind, origin) VALUES ($1, $2, 'original', $3)")
        .bind(version)
        .bind(id)
        .bind(upload.source)
        .execute(&mut *tx)
        .await?;
    sqlx::query("UPDATE assets SET current_version_id = $2 WHERE id = $1")
        .bind(id)
        .bind(version)
        .execute(&mut *tx)
        .await?;
    Ok(id)
}

/// A file's metadata under its sidecars' (design 13 §7.2), applied in order: their title, description, rating, label and
/// location replace the file's, and their keywords join its own. Whether the location is a sidecar's.
fn merged(file: &ReadMetadataResponse, sidecars: &[&ReadMetadataResponse]) -> (ReadMetadataResponse, bool) {
    let (mut merged, mut located) = (file.clone(), false);
    for sidecar in sidecars {
        for (to, from) in [
            (&mut merged.title, &sidecar.title),
            (&mut merged.description, &sidecar.description),
            (&mut merged.label, &sidecar.label),
        ] {
            if !from.is_empty() {
                to.clone_from(from);
            }
        }
        merged.rating = sidecar.rating.or(merged.rating);
        if sidecar.location.is_some() {
            (merged.location, located) = (sidecar.location, true);
        }
        for keyword in &sidecar.keywords {
            if !merged.keywords.contains(keyword) {
                merged.keywords.push(keyword.clone());
            }
        }
        for path in &sidecar.keyword_paths {
            if !merged.keyword_paths.contains(path) {
                merged.keyword_paths.push(path.clone());
            }
        }
    }
    (merged, located)
}

/// Tags the asset `id` of `owner` with the keywords `metadata` holds (design 13 §7.4): a hierarchical one as the leaf of
/// a tree of the owner's tags, a flat one that names no node of those trees as a tag of its own. Tags are made in
/// path order, so that jobs that make the same ones wait for each other rather than deadlock.
async fn tags(tx: &mut PgConnection, owner: Uuid, id: Uuid, metadata: &ReadMetadataResponse) -> sqlx::Result<()> {
    let trees = metadata.keyword_paths.iter().map(|path| path.nodes.clone());
    let named = |keyword: &String| metadata.keyword_paths.iter().any(|path| path.nodes.contains(keyword));
    let flat = (metadata.keywords.iter())
        .filter(|keyword| !keyword.trim().is_empty() && !named(keyword))
        .map(|keyword| vec![keyword.clone()]);
    let mut paths: Vec<Vec<String>> = trees.chain(flat).collect();
    paths.sort();
    paths.dedup();
    for nodes in paths {
        let (mut parent, mut path) = (None::<Uuid>, String::new());
        for name in &nodes {
            if !path.is_empty() {
                path.push('|');
            }
            path.push_str(name);
            let made: Option<Uuid> = sqlx::query_scalar(
                "INSERT INTO tags (id, owner_id, parent_id, name, path, origin) VALUES ($1, $2, $3, $4, $5, 'import')
                 ON CONFLICT DO NOTHING RETURNING id",
            )
            .bind(Uuid::now_v7())
            .bind(owner)
            .bind(parent)
            .bind(name)
            .bind(&path)
            .fetch_optional(&mut *tx)
            .await?;
            let tag =
                match made {
                    Some(tag) => tag,
                    None => sqlx::query_scalar(
                        "SELECT id FROM tags WHERE owner_id = $1 AND parent_id IS NOT DISTINCT FROM $2 AND name = $3",
                    )
                    .bind(owner)
                    .bind(parent)
                    .bind(name)
                    .fetch_one(&mut *tx)
                    .await?,
                };
            parent = Some(tag);
        }
        sqlx::query(
            "INSERT INTO asset_tags (asset_id, tag_id, origin) VALUES ($1, $2, 'import') ON CONFLICT DO NOTHING",
        )
        .bind(id)
        .bind(parent)
        .execute(&mut *tx)
        .await?;
    }
    Ok(())
}

/// Commits the `sidecars` of asset `id`, read in place in an external library, as its `sidecar` files. They go out
/// only as downloads: an XML document shown in a browser could run script.
pub(super) async fn sidecars(tx: &mut PgConnection, id: Uuid, sidecars: &[&Sidecar]) -> sqlx::Result<()> {
    for sidecar in sidecars {
        sqlx::query(
            "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size)
             VALUES ($1, $2, 'sidecar', $3, $4, 'application/octet-stream', $5)",
        )
        .bind(Uuid::now_v7())
        .bind(id)
        .bind(external::STORE)
        .bind(&sidecar.key)
        .bind(sidecar.length)
        .execute(&mut *tx)
        .await?;
    }
    Ok(())
}

/// Commits the files of asset `id`, placed at `keys` in `store`: its original and partner files, and a motion photo's
/// video as a range of the original.
pub async fn files(
    tx: &mut PgConnection,
    id: Uuid,
    files: &[(&Source, &Read, Role)],
    store: &str,
    keys: &[String],
) -> sqlx::Result<()> {
    for ((upload, read, role), key) in files.iter().zip(keys) {
        sqlx::query(
            "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
        )
        .bind(Uuid::now_v7())
        .bind(id)
        .bind(role.as_str())
        .bind(store)
        .bind(key)
        .bind(read.media.mime)
        .bind(upload.length)
        .bind(&upload.hash)
        .execute(&mut *tx)
        .await?;
    }
    if let Some(motion) = &files[0].1.motion {
        self::motion(tx, id, store, &keys[0], motion).await?;
    }
    Ok(())
}

/// Commits a motion photo's video, a range of the original at `key` in `store`, as a file of asset `id`.
pub(crate) async fn motion(
    tx: &mut PgConnection,
    id: Uuid,
    store: &str,
    key: &str,
    motion: &Motion,
) -> sqlx::Result<()> {
    sqlx::query(
        "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash, byte_offset)
         VALUES ($1, $2, 'motion_extracted', $3, $4, $5, $6, $7, $8)",
    )
    .bind(Uuid::now_v7())
    .bind(id)
    .bind(store)
    .bind(key)
    .bind(motion.mime)
    .bind(motion.length as i64)
    .bind(motion.hash.0.to_vec())
    .bind(motion.offset as i64)
    .execute(&mut *tx)
    .await
    .map(drop)
}
