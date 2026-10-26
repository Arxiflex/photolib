//! Faces (ADR-0389, design 09 §7): the account's consent, which is the one gate for everything the server computes
//! about faces, and the faces found. A row of `face_consents` is the opt-in; withdrawing deletes it with the faces,
//! people and scans of the account's assets and the queued face jobs, in one transaction, and both are audit events.

use std::sync::Arc;

use async_trait::async_trait;
use photolib_authz::{Capability, policy};
use photolib_jobs::{Handler, Job};
use photolib_media::render::{Format, Output};
use photolib_ml::faces::{self as ml_faces, Found, Models as FaceModels, Picture};
use photolib_models::REGISTRY;
use sqlx::{PgConnection, PgPool, Row};
use uuid::Uuid;

use crate::{
    ingest::local_path,
    ml::Models,
    render::{ORIGINAL, Render},
    video::Ffmpeg,
};

/// The version of the consent notice apps show; a change of the notice's meaning raises it, and accounts that agreed
/// to an older one are asked again before anything new is computed about them.
pub const NOTICE_VERSION: i32 = 1;

/// The job type of finding the faces of an asset.
pub const FACES: &str = "faces";

/// Where an account stands.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Consent {
    /// The version agreed to and when (microseconds since the epoch); none while the account has not agreed.
    pub granted: Option<(i32, i64)>,
}

/// Why a change of the consent was refused.
#[derive(Debug)]
pub enum ConsentError {
    /// The account was shown another version of the notice than the current one.
    Outdated,
    /// The database failed
    Db(sqlx::Error),
}

impl From<sqlx::Error> for ConsentError {
    fn from(error: sqlx::Error) -> Self {
        Self::Db(error)
    }
}

/// The account's consent.
pub async fn consent(pool: &PgPool, user: Uuid) -> sqlx::Result<Consent> {
    let granted = sqlx::query_as(
        "SELECT notice_version, (extract(EPOCH FROM granted_at) * 1e6)::bigint FROM face_consents WHERE user_id = $1",
    )
    .bind(user)
    .fetch_optional(pool)
    .await?;
    Ok(Consent { granted })
}

/// Records, in the transaction `tx` is, the audit event of a change of the consent.
async fn audit(tx: &mut PgConnection, user: Uuid, action: &str, version: i32) -> sqlx::Result<()> {
    sqlx::query("SELECT audit_append($1, $2, jsonb_build_object('user_id', $1::text), jsonb_build_object('notice_version', $3::int))")
        .bind(user)
        .bind(action)
        .bind(version)
        .execute(tx)
        .await
        .map(drop)
}

/// The account agrees to the notice of `version`, which must be the current one. Agreeing again is no change.
pub async fn grant(pool: &PgPool, user: Uuid, version: i32) -> Result<(), ConsentError> {
    if version != NOTICE_VERSION {
        return Err(ConsentError::Outdated);
    }
    let mut tx = pool.begin().await?;
    let before: Option<i32> =
        sqlx::query_scalar("SELECT notice_version FROM face_consents WHERE user_id = $1 FOR UPDATE")
            .bind(user)
            .fetch_optional(&mut *tx)
            .await?;
    if before == Some(version) {
        return Ok(());
    }
    sqlx::query(
        "INSERT INTO face_consents (user_id, notice_version) VALUES ($1, $2)
         ON CONFLICT (user_id) DO UPDATE SET notice_version = excluded.notice_version, granted_at = now()",
    )
    .bind(user)
    .bind(version)
    .execute(&mut *tx)
    .await?;
    audit(&mut tx, user, "faces.consent_grant", version).await?;
    Ok(tx.commit().await?)
}

/// The account withdraws: its faces, people, scans and face jobs not running go, and it is no longer processed. A job that
/// runs meanwhile finds the consent gone when it looks (`consented`) and keeps nothing.
pub async fn withdraw(pool: &PgPool, user: Uuid) -> sqlx::Result<()> {
    let mut tx = pool.begin().await?;
    let version: Option<i32> =
        sqlx::query_scalar("DELETE FROM face_consents WHERE user_id = $1 RETURNING notice_version")
            .bind(user)
            .fetch_optional(&mut *tx)
            .await?;
    for sql in [
        "DELETE FROM faces WHERE asset_id IN (SELECT id FROM assets WHERE owner_id = $1)",
        "DELETE FROM persons WHERE owner_id = $1",
        "DELETE FROM face_scans WHERE asset_id IN (SELECT id FROM assets WHERE owner_id = $1)",
        "DELETE FROM jobs WHERE type = 'faces' AND status <> 'running' AND
           convert_from(payload, 'UTF8')::jsonb ->> 'asset' IN (SELECT id::text FROM assets WHERE owner_id = $1)",
    ] {
        sqlx::query(sql).bind(user).execute(&mut *tx).await?;
    }
    if let Some(version) = version {
        audit(&mut tx, user, "faces.consent_withdraw", version).await?;
    }
    tx.commit().await
}

/// Whether `user` has agreed to the current notice, looked at in the transaction a job writes in, with the row held so
/// that a withdrawal waits for the job's commit (or the job sees it gone): nothing is kept for an account that has not.
pub async fn consented(tx: &mut PgConnection, user: Uuid) -> sqlx::Result<bool> {
    let version: Option<i32> =
        sqlx::query_scalar("SELECT notice_version FROM face_consents WHERE user_id = $1 FOR SHARE")
            .bind(user)
            .fetch_optional(tx)
            .await?;
    Ok(version == Some(NOTICE_VERSION))
}

/// A face as kept.
#[derive(Debug, Clone)]
pub struct Face {
    /// Its id
    pub id: Uuid,
    /// Left, top, width and height, in fractions of the original
    pub bbox: [f32; 4],
    /// Ten values, or none
    pub landmarks: Vec<f32>,
    /// The detector's confidence
    pub score: f32,
    /// The keyframe of a video, in milliseconds
    pub time_ms: Option<i32>,
    /// The embedding model, `id@revision`
    pub model_id: String,
}

type FaceRow = (
    Uuid,
    Vec<f32>,
    Option<serde_json::Value>,
    Option<f32>,
    Option<i32>,
    String,
);

/// The faces of an asset, best first.
pub async fn list(pool: &PgPool, asset: Uuid) -> sqlx::Result<Vec<Face>> {
    let rows: Vec<FaceRow> = sqlx::query_as(
        "SELECT id, bbox, landmarks, score, time_ms, model_id FROM faces WHERE asset_id = $1
         ORDER BY score DESC NULLS LAST, time_ms NULLS FIRST, id",
    )
    .bind(asset)
    .fetch_all(pool)
    .await?;
    Ok(rows
        .into_iter()
        .filter_map(|(id, bbox, landmarks, score, time_ms, model_id)| {
            let bbox = <[f32; 4]>::try_from(bbox).ok()?;
            let points = landmarks
                .as_ref()
                .and_then(|l| l.get("points"))
                .and_then(|p| p.as_array());
            #[allow(clippy::cast_possible_truncation)] // landmarks are fractions near 0 to 1
            let landmarks = points
                .map(|p| {
                    p.iter()
                        .filter_map(serde_json::Value::as_f64)
                        .map(|v| v as f32)
                        .collect()
                })
                .unwrap_or_default();
            Some(Face {
                id,
                bbox,
                landmarks,
                score: score.unwrap_or(0.0),
                time_ms,
                model_id,
            })
        })
        .collect())
}

/// The job that queues the face jobs of every account that agreed: every minute, for the scheduler.
pub const SWEEP: &str = "faces-sweep";
/// The long side of the picture the models read, rendered in the sandbox as raw pixels.
const LONG: u32 = 1280;
/// Face jobs one sweep queues.
const BATCH: i64 = 200;
/// Frames of a video looked at, two seconds apart at least.
const KEYFRAMES: u32 = 16;

/// 8-bit RGB pixels as opaque RGBA.
fn rgba(rgb: &[u8]) -> Vec<u8> {
    rgb.as_chunks::<3>()
        .0
        .iter()
        .flat_map(|&[r, g, b]| [r, g, b, 255])
        .collect()
}

/// The registry's detector and the embedder named `embedder`, with their server files.
pub fn face_models(embedder: &str) -> Result<(FaceModels, String, String), String> {
    let find = |id: &str| {
        REGISTRY
            .iter()
            .find(|m| m.id == id)
            .ok_or_else(|| format!("{id} is not in the registry"))
    };
    let (detector, embedder) = (find("yunet")?, find(embedder)?);
    Ok((FaceModels::new(detector, embedder)?, detector.name(), embedder.name()))
}

/// `values` as IEEE 754 binary16, little-endian, rounded to nearest even: the precision of every vector kept.
pub fn halves(values: &[f32]) -> Vec<u8> {
    values
        .iter()
        .flat_map(|v| half::f16::from_f32(*v).to_le_bytes())
        .collect()
}

/// Queues a face job for each photo of an account that agreed to the current notice and has none yet for the model
/// `embedder`: not in a private library, not where an `off` switch of face recognition sits at the server, the account
/// or the library (narrower `on` switches are left to the job, which asks the policy exactly), newest first. The job's
/// key names the model, so that a new model scans everything again; and a withdrawal deletes the account's jobs, so that
/// agreeing again queues them again.
pub async fn sweep(tx: &mut PgConnection, embedder: &str, videos: bool) -> sqlx::Result<u64> {
    let queued = sqlx::query(
        "INSERT INTO jobs (id, type, payload, status, placement, idempotency_key, priority)
         SELECT photolib_uuidv7(), 'faces', convert_to(json_build_object('asset', a.id)::text, 'UTF8'), 'queued',
                'server', concat_ws(':', 'faces', a.id, $1::text), -5
         FROM assets a
         JOIN libraries l ON l.id = a.library_id AND l.privacy <> 'private'
         JOIN face_consents c ON c.user_id = a.owner_id AND c.notice_version = $2
         WHERE (a.media_kind = 'image' OR $4 AND a.media_kind = 'video')
           AND NOT EXISTS (SELECT FROM face_scans s WHERE s.asset_id = a.id AND s.model_id = $1)
           AND NOT EXISTS (SELECT FROM policy_switches p WHERE p.capability = 'face_recognition' AND NOT p.enabled
                AND (p.user_id IS NULL AND p.library_id IS NULL OR p.user_id = a.owner_id OR p.library_id = a.library_id))
         ORDER BY a.created_at DESC
         LIMIT $3
         ON CONFLICT (idempotency_key) DO NOTHING",
    )
    .bind(embedder)
    .bind(NOTICE_VERSION)
    .bind(BATCH)
    .bind(videos)
    .execute(tx)
    .await?;
    Ok(queued.rows_affected())
}

/// The `faces-sweep` job's handler.
pub struct Sweep {
    /// The embedding model queued for, `id@revision`
    pub embedder: String,
    /// Whether videos are queued too: this process has FFmpeg for their keyframes
    pub videos: bool,
}

#[async_trait]
impl Handler for Sweep {
    async fn run(&self, _job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        sweep(tx, &self.embedder, self.videos)
            .await
            .map(drop)
            .map_err(|error| error.to_string())
    }
}

/// The faces of an asset, kept in `tx`: the detector's automatic ones for the model replaced, and the asset marked as
/// scanned.
async fn keep(
    tx: &mut PgConnection,
    asset: Uuid,
    version: Option<Uuid>,
    (detector, embedder): (&str, &str),
    groups: &[(Option<i32>, Vec<Found>)],
) -> sqlx::Result<()> {
    sqlx::query("DELETE FROM faces WHERE asset_id = $1 AND model_id = $2 AND assignment = 'auto'")
        .bind(asset)
        .bind(embedder)
        .execute(&mut *tx)
        .await?;
    for (time_ms, group) in groups {
        for found in group {
            let face = &found.face;
            sqlx::query(
                "INSERT INTO faces (id, asset_id, version_basis, bbox, landmarks, model_id, embedding, score, detector, time_ms)
                 VALUES ($1, $2, $3, $4, jsonb_build_object('points', $5::float4[]), $6, $7, $8, $9, $10)",
            )
            .bind(Uuid::now_v7())
            .bind(asset)
            .bind(version)
            .bind(vec![face.x, face.y, face.width, face.height])
            .bind(&face.landmarks)
            .bind(embedder)
            .bind(halves(&found.embedding))
            .bind(face.score)
            .bind(detector)
            .bind(time_ms)
            .execute(&mut *tx)
            .await?;
        }
    }
    sqlx::query(
        "INSERT INTO face_scans (asset_id, model_id, faces) VALUES ($1, $2, $3)
         ON CONFLICT (asset_id, model_id) DO UPDATE SET faces = excluded.faces, scanned_at = now()",
    )
    .bind(asset)
    .bind(embedder)
    .bind(i32::try_from(groups.iter().map(|(_, found)| found.len()).sum::<usize>()).unwrap_or(i32::MAX))
    .execute(tx)
    .await?;
    Ok(())
}

/// The `faces` job's handler, on the process that has the `ml` role: nothing is rendered, run or kept for an account
/// that has not agreed, checked in the transaction that would write.
pub struct FaceJob {
    render: Arc<Render>,
    models: Models,
    pool: PgPool,
    face: FaceModels,
    names: (String, String),
    /// FFmpeg, for the keyframes of videos (ML-08); none, and videos are left alone
    ffmpeg: Option<Arc<Ffmpeg>>,
}

impl FaceJob {
    /// The handler of the registry's detector and the embedder `embedder`, an id such as `sface`.
    pub fn new(
        render: Arc<Render>,
        models: Models,
        pool: PgPool,
        embedder: &str,
        ffmpeg: Option<Arc<Ffmpeg>>,
    ) -> Result<Self, String> {
        let (face, detector, embedder) = face_models(embedder)?;
        Ok(Self {
            render,
            models,
            pool,
            face,
            names: (detector, embedder),
            ffmpeg,
        })
    }

    /// Whether videos are looked at too.
    pub fn videos(&self) -> bool {
        self.ffmpeg.is_some()
    }

    /// The embedding model's `id@revision`, which the sweep queues for.
    pub fn embedder(&self) -> &str {
        &self.names.1
    }
}

#[async_trait]
impl Handler for FaceJob {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        self.find(job, tx).await.map_err(|error| error.to_string())
    }
}

type Fallible<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

/// A picture to look for faces in: when in the video (none for a photo), its size and RGBA pixels.
type Frame = (Option<i32>, u32, u32, Vec<u8>);

impl FaceJob {
    /// The photo of `row`, rendered in the sandbox as raw pixels.
    async fn still(&self, tx: &mut PgConnection, row: &sqlx::postgres::PgRow) -> Fallible<Vec<Frame>> {
        let raw = Output {
            file: "faces".into(),
            format: Format::Raw,
            short: 0,
            long: LONG,
            quality: 0,
            wide: false,
        };
        let (rendered, dir) = self.render.sandboxed(tx, row, |_| vec![raw]).await?;
        let file = dir.join("out").join("faces");
        let pixels = std::fs::read(&file)?;
        drop(std::fs::remove_file(&file));
        let &[(Format::Raw, width, height)] = rendered.outputs.as_slice() else {
            return Err("the renderer wrote no raw picture".into());
        };
        Ok(vec![(None, width, height, rgba(&pixels))])
    }

    /// The keyframes of the video of `row`, extracted by FFmpeg in its sandbox.
    async fn keyframes(&self, tx: &mut PgConnection, row: &sqlx::postgres::PgRow) -> Fallible<Vec<Frame>> {
        let Some(ffmpeg) = &self.ffmpeg else {
            return Err("this process has no FFmpeg for videos".into());
        };
        let locals = self.render.staged(tx, row).await?;
        let out = self.render.scratch().join(format!("keyframes-{}", Uuid::now_v7()));
        std::fs::create_dir_all(&out)?;
        let frames = ffmpeg
            .keyframes(
                &local_path(locals.0.first().ok_or("no local file")?),
                &out,
                LONG,
                KEYFRAMES,
            )
            .await;
        drop(std::fs::remove_dir_all(&out));
        let frames = frames.map_err(|failure| format!("{failure:?}"))?;
        Ok(frames
            .each()
            .map(|(time, rgb)| (Some(time), frames.width, frames.height, rgba(rgb)))
            .collect())
    }

    async fn find(&self, job: &Job, tx: &mut PgConnection) -> Fallible<()> {
        let payload: serde_json::Value = serde_json::from_slice(&job.payload)?;
        let asset: Uuid = serde_json::from_value(payload.get("asset").cloned().unwrap_or_default())?;
        let Some((owner, library, kind)): Option<(Uuid, Uuid, Option<String>)> =
            sqlx::query_as("SELECT owner_id, library_id, media_kind FROM assets WHERE id = $1")
                .bind(asset)
                .fetch_optional(&mut *tx)
                .await?
        else {
            return Ok(());
        };
        // The one gate, looked at where the faces would be written: no consent, nothing is rendered or run.
        if !consented(tx, owner).await? {
            return Ok(());
        }
        let switches = policy(&self.pool, Some(owner), Some(library)).await?;
        if switches
            .iter()
            .any(|(c, on, _)| *c == Capability::FaceRecognition && !on)
        {
            return Ok(());
        }
        let scanned: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT FROM face_scans WHERE asset_id = $1 AND model_id = $2)")
                .bind(asset)
                .bind(&self.names.1)
                .fetch_one(&mut *tx)
                .await?;
        if scanned {
            return Ok(());
        }
        if self.models.get().is_none() {
            return Err("the face models are not loaded yet".into());
        }
        let video = kind.as_deref() == Some("video");
        let original = if video {
            ORIGINAL.replace("a.media_kind = 'image'", "a.media_kind = 'video'")
        } else {
            ORIGINAL.to_owned()
        };
        let Some(row) = sqlx::query(&original).bind(asset).fetch_optional(&mut *tx).await? else {
            return Ok(());
        };
        let version: Option<Uuid> = row.get("current_version_id");
        let frames = if video {
            self.keyframes(tx, &row).await?
        } else {
            self.still(tx, &row).await?
        };
        let (models, face) = (self.models.clone(), self.face.clone());
        let found = tokio::task::spawn_blocking(move || {
            let pool = models.get().ok_or("the face models are not loaded yet")?;
            frames
                .into_iter()
                .map(|(time, width, height, rgba)| {
                    let picture = Picture {
                        width,
                        height,
                        rgba: &rgba,
                    };
                    ml_faces::find(pool, &face, &picture).map(|found| (time, found))
                })
                .collect::<Result<Vec<_>, String>>()
        })
        .await??;
        keep(tx, asset, version, (&self.names.0, &self.names.1), &found).await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::tests::{asset, database, exec, library, user};

    #[test]
    fn vectors_are_kept_as_half_floats_rounded_to_nearest_even() {
        let kept = |values: &[f32]| -> Vec<u16> {
            halves(values)
                .chunks(2)
                .map(|b| u16::from_le_bytes([b[0], b[1]]))
                .collect()
        };
        // 1, -2, 0.5, 65504 (the largest), the smallest subnormal, 0, infinity and a value too large
        let got = kept(&[1.0, -2.0, 0.5, 65504.0, 5.960_464_5e-8, 0.0, f32::INFINITY, 1e9]);
        assert_eq!(got, [0x3c00, 0xc000, 0x3800, 0x7bff, 0x0001, 0, 0x7c00, 0x7c00]);
        // 2049 is between 2048 and 2050: the even one, 2048; 2051 between 2050 and 2052: 2052
        assert_eq!(kept(&[2049.0, 2051.0]), [0x6800, 0x6802]);
        assert_eq!(halves(&[]), Vec::<u8>::new());
    }

    async fn consent(pool: &PgPool, user: Uuid) {
        sqlx::query("INSERT INTO face_consents (user_id, notice_version) VALUES ($1, $2)")
            .bind(user)
            .bind(NOTICE_VERSION)
            .execute(pool)
            .await
            .unwrap();
    }

    async fn queued(pool: &PgPool) -> Vec<Uuid> {
        let mut assets: Vec<String> = sqlx::query_scalar(
            "SELECT convert_from(payload, 'UTF8')::jsonb ->> 'asset' FROM jobs WHERE type = 'faces'",
        )
        .fetch_all(pool)
        .await
        .unwrap();
        assets.sort();
        let mut assets: Vec<Uuid> = assets.iter().map(|a| a.parse().unwrap()).collect();
        assets.sort();
        assets
    }

    #[tokio::test]
    async fn the_sweep_queues_the_photos_of_accounts_that_agreed_and_nobody_elses() {
        let pool = database().await;
        let (ann, bob, cyd) = (
            user(&pool, "user").await,
            user(&pool, "user").await,
            user(&pool, "user").await,
        );
        let (anns, bobs, cyds) = (
            library(&pool, ann, "standard").await,
            library(&pool, bob, "standard").await,
            library(&pool, cyd, "private").await,
        );
        let (a1, a2) = (asset(&pool, anns).await, asset(&pool, anns).await);
        let (b1, c1) = (asset(&pool, bobs).await, asset(&pool, cyds).await);
        exec(&pool, "UPDATE assets SET media_kind = 'video' WHERE id = $1", &[a2]).await;
        let a3 = asset(&pool, anns).await;
        // Ann and Cyd agreed; Bob did not. Cyd's library is private: its media never reach the server's models.
        consent(&pool, ann).await;
        consent(&pool, cyd).await;
        let embedder = "sface@2021dec";
        let mut conn = pool.acquire().await.unwrap();
        assert_eq!(sweep(&mut conn, embedder, false).await.unwrap(), 2);
        let mut expected = vec![a1, a3];
        expected.sort();
        assert_eq!(queued(&pool).await, expected);
        assert!(!queued(&pool).await.contains(&b1) && !queued(&pool).await.contains(&c1));
        // Again: nothing new; scanned photos are left out; a new model scans everything again.
        assert_eq!(sweep(&mut conn, embedder, false).await.unwrap(), 0);
        exec(&pool, "DELETE FROM jobs", &[]).await;
        sqlx::query("INSERT INTO face_scans (asset_id, model_id, faces) VALUES ($1, $2, 0)")
            .bind(a1)
            .bind(embedder)
            .execute(&pool)
            .await
            .unwrap();
        assert_eq!(sweep(&mut conn, embedder, false).await.unwrap(), 1);
        assert_eq!(
            sweep(&mut conn, "auraface@v1", false).await.unwrap(),
            2,
            "the other model has scanned nothing"
        );
        // Bob agrees later: his photo is queued then, and not before.
        consent(&pool, bob).await;
        assert!(sweep(&mut conn, embedder, false).await.unwrap() >= 1);
        assert!(queued(&pool).await.contains(&b1));
    }

    #[tokio::test]
    async fn the_sweep_leaves_out_the_libraries_where_face_recognition_is_off() {
        let pool = database().await;
        let ann = user(&pool, "user").await;
        let (off, on) = (
            library(&pool, ann, "standard").await,
            library(&pool, ann, "standard").await,
        );
        let (hidden, shown) = (asset(&pool, off).await, asset(&pool, on).await);
        consent(&pool, ann).await;
        exec(
            &pool,
            "INSERT INTO policy_switches (capability, library_id, enabled) VALUES ('face_recognition', $1, false)",
            &[off],
        )
        .await;
        let mut conn = pool.acquire().await.unwrap();
        assert_eq!(sweep(&mut conn, "sface@2021dec", false).await.unwrap(), 1);
        assert_eq!(queued(&pool).await, [shown]);
        assert_ne!(shown, hidden);
        exec(&pool, "DELETE FROM jobs", &[]).await;
        exec(
            &pool,
            "INSERT INTO policy_switches (capability, enabled) VALUES ('face_recognition', false)",
            &[],
        )
        .await;
        assert_eq!(
            sweep(&mut conn, "sface@2021dec", false).await.unwrap(),
            0,
            "off for the whole server"
        );
    }
}
