//! The full-size export of an edited image (roadmap M8-01, ADR-0391): the `export` job makes one JPEG of the current
//! version, role `edit_export`, which is what downloads of the edited version serve. A geometry-only edit of a JPEG
//! is made by the kernel without decoding it (turns as EXIF orientation, crops of whole blocks); any other edit is
//! rendered in the sandbox and the kernel gives the JPEG the original's EXIF, XMP and IPTC; a picture of another
//! format has no metadata to give but its capture time. Every export says how the edit was made: the recipe without
//! its masks' pixels, the models and parameters, and IPTC's DigitalSourceType.

use std::sync::Arc;

use async_trait::async_trait;
use photolib_jobs::{Handler, Job};
use photolib_kernel::proto::{
    kernel::v1::{CallResponse, EditCopyRequest, EditCopyResponse, Method, call_response},
    model::v1::{CaptureTime, EditRecipe},
};
use photolib_media::render::{Format, Output};
use photolib_storage::{Hash, journal::Journal};
use prost::Message;
use serde_json::{Value, json};
use sqlx::{PgConnection, Row};
use uuid::Uuid;

use crate::{
    edits::EXPORT_SPEC,
    render::{ORIGINAL, Render},
};

/// The job type.
pub const EXPORT: &str = "export";
/// The role of the file.
pub const ROLE: &str = "edit_export";
const STORE: &str = "local";
/// The JPEG quality of an export that is rendered; a lossless one keeps the original's.
const QUALITY: u8 = 92;
/// The longest original the kernel is given whole, in bytes.
const MAX_ORIGINAL: u64 = 512 << 20;

/// The `export` job's handler, on a `worker:cpu` role.
pub struct Export {
    render: Arc<Render>,
    journal: Arc<Journal>,
}

impl Export {
    /// The handler of `render`'s sandboxes and store.
    pub fn new(render: Arc<Render>) -> Self {
        let journal = render.journal();
        Self { render, journal }
    }
}

#[async_trait]
impl Handler for Export {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        self.export(job, tx).await.map_err(|error| error.to_string())
    }

    async fn committed(&self, _job: &Job) {
        if let Err(error) = self.journal.finish_switched().await {
            tracing::warn!(%error, "replaced exports stay until recovery deletes them");
        }
    }
}

type Fallible<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

/// What the kernel made of an edit copy: the JPEG, or the field it needs.
fn copy(request: &EditCopyRequest) -> Result<EditCopyResponse, String> {
    let answer = photolib_kernel::call(Method::EditCopy as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).ok().and_then(|a| a.result) {
        Some(call_response::Result::Response(bytes)) => {
            EditCopyResponse::decode(bytes.as_slice()).map_err(|e| e.to_string())
        }
        Some(call_response::Result::Error(e)) => Err(e
            .params
            .get("field")
            .cloned()
            .unwrap_or_else(|| format!("{:?}", e.code()))),
        None => Err("no answer".into()),
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().concat()
}

impl Export {
    async fn export(&self, job: &Job, tx: &mut PgConnection) -> Fallible<()> {
        let payload: Value = serde_json::from_slice(&job.payload)?;
        let id = |name: &str| -> Fallible<Uuid> {
            Ok(serde_json::from_value(payload.get(name).cloned().unwrap_or_default())?)
        };
        let (asset, version) = (id("asset")?, id("version")?);
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))")
            .bind(asset)
            .execute(&mut *tx)
            .await?;
        let Some(row) = sqlx::query(ORIGINAL).bind(asset).fetch_optional(&mut *tx).await? else {
            return Ok(());
        };
        // A newer edit or a revert has made this one's export useless.
        if row.get::<Option<Uuid>, _>("current_version_id") != Some(version) {
            return Ok(());
        }
        let Some(recipe) = row.get::<Option<Vec<u8>>, _>("recipe") else {
            return Ok(());
        };
        let recipe = EditRecipe::decode(recipe.as_slice())?;
        let content: Vec<u8> = row.get::<Option<Vec<u8>>, _>("content_hash").unwrap_or_default();
        let mime: String = row.get("mime");
        let size: i64 = row.get("size");
        if u64::try_from(size).unwrap_or(u64::MAX) > MAX_ORIGINAL {
            return Err("the original is too large to export".into());
        }
        let taken: Option<(String, Option<i32>)> = sqlx::query_as(
            "SELECT to_char(taken_local, 'YYYY-MM-DD\"T\"HH24:MI:SS'), tz_offset_min FROM assets
             WHERE id = $1 AND taken_local IS NOT NULL",
        )
        .bind(asset)
        .fetch_optional(&mut *tx)
        .await?;
        let request = EditCopyRequest {
            recipe: Some(recipe),
            original_blake3: hex(&content),
            capture_time: taken.map(|(local, offset)| CaptureTime {
                local_datetime: local,
                offset_minutes: offset,
                ..Default::default()
            }),
            ..Default::default()
        };
        let original = self.render.staged(tx, &row).await?;
        let path = original
            .0
            .first()
            .map(crate::ingest::local_path)
            .ok_or("the original is not here")?;
        let jpeg = mime == "image/jpeg";
        let lossless = if jpeg {
            let bytes = std::fs::read(&path)?;
            copy(&EditCopyRequest {
                original: bytes,
                ..request.clone()
            })
            .ok()
        } else {
            None
        };
        let made = match lossless {
            Some(made) => made,
            None => self.rendered(tx, &row, request, jpeg.then_some(path.as_path())).await?,
        };
        self.store(tx, &row, (asset, version), &made, &content).await
    }

    /// The export rendered by the sandbox, and given the metadata of the original `file` if it is a JPEG.
    async fn rendered(
        &self,
        tx: &mut PgConnection,
        row: &sqlx::postgres::PgRow,
        request: EditCopyRequest,
        file: Option<&std::path::Path>,
    ) -> Fallible<EditCopyResponse> {
        let output = Output {
            file: "export".into(),
            format: Format::Jpeg,
            short: 0,
            long: u32::MAX,
            quality: QUALITY,
            wide: false,
        };
        let (_, dir) = self.render.sandboxed(tx, row, |_| vec![output]).await?;
        let made = dir.join("out").join("export");
        let rendered = std::fs::read(&made)?;
        drop(std::fs::remove_file(&made));
        if !rendered.starts_with(&[0xff, 0xd8, 0xff]) {
            return Err("the renderer wrote no JPEG".into());
        }
        let metadata_from = file.map(std::fs::read).transpose()?.unwrap_or_default();
        let host = EditCopyRequest {
            original: rendered,
            rendered: true,
            metadata_from,
            ..request
        };
        Ok(copy(&host)?)
    }

    /// Keeps `made` as the asset's export for `version`, replacing the exports of other versions.
    async fn store(
        &self,
        tx: &mut PgConnection,
        row: &sqlx::postgres::PgRow,
        (asset, version): (Uuid, Uuid),
        made: &EditCopyResponse,
        source: &[u8],
    ) -> Fallible<()> {
        let library: Uuid = row.get("library_id");
        let (id, hash) = (Uuid::now_v7(), Hash::of(&made.jpeg));
        let shard = asset.simple().to_string().split_off(30);
        let key = format!("derived/{library}/{shard}/{asset}/{id}.jpg");
        self.journal
            .put_bytes(STORE, &key, &made.jpeg)
            .await?
            .switch(tx)
            .await?;
        let from = json!({"spec_id": EXPORT_SPEC, "generator": "edit-copy", "version_id": version,
            "lossless": made.lossless, "source_hash": hex(source)});
        sqlx::query(
            "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash, render_spec)
             VALUES ($1, $2, $3, $4, $5, 'image/jpeg', $6, $7, $8)",
        )
        .bind(id)
        .bind(asset)
        .bind(ROLE)
        .bind(STORE)
        .bind(key)
        .bind(i64::try_from(made.jpeg.len())?)
        .bind(hash.0.to_vec())
        .bind(from)
        .execute(&mut *tx)
        .await?;
        sqlx::query("UPDATE versions SET render_file_id = $2 WHERE id = $1")
            .bind(version)
            .bind(id)
            .execute(&mut *tx)
            .await?;
        let replaced: Vec<(String, String)> = sqlx::query_as(
            "DELETE FROM asset_files WHERE asset_id = $1 AND role = $2 AND id <> $3 RETURNING storage, key",
        )
        .bind(asset)
        .bind(ROLE)
        .bind(id)
        .fetch_all(&mut *tx)
        .await?;
        for (store, key) in replaced {
            self.journal.delete(&store, &key).await?.switch(tx).await?;
        }
        Ok(())
    }
}
