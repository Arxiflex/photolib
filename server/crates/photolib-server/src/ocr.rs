//! The `ocr` job (ADR-0388, design 09 §6): the text in a picture, read by PP-OCRv5 on the models of the `ml` role and
//! kept in `asset_ocr`. The pixels come from the sandboxed renderer as raw RGB, so no decoder of pictures runs here;
//! the text is data from then on, cleaned of control and bidirectional characters and never interpreted.

use std::sync::{Arc, OnceLock};

use async_trait::async_trait;
use photolib_jobs::{Handler, Job};
use photolib_media::render::{Format, Output};
use photolib_ml::{
    Pool,
    ocr::{Rgb, clean, read_lines},
};
use serde_json::Value;
use sqlx::{PgConnection, Row};
use uuid::Uuid;

use crate::render::{ORIGINAL, Render};

/// The job type.
pub const OCR: &str = "ocr";
/// The model id its text is kept under: the pipeline and its models, as one (a new pipeline reads every image again).
pub const MODEL: &str = "ppocr-v5";
/// The long side of the picture the models read: PP-OCR's detector reduces anything larger.
const LONG: u32 = 1280;

/// The pool of the `ml` role, set once its self-test is done.
pub type Models = Arc<OnceLock<Pool<'static>>>;

/// The `ocr` job's handler, on the process that has the `ml` role.
pub struct Ocr {
    render: Arc<Render>,
    models: Models,
}

impl Ocr {
    /// The handler of `render`'s sandboxes with the models `models` will hold.
    pub fn new(render: Arc<Render>, models: Models) -> Self {
        Self { render, models }
    }
}

#[async_trait]
impl Handler for Ocr {
    async fn run(&self, job: &Job, tx: &mut PgConnection) -> Result<(), String> {
        self.read(job, tx).await.map_err(|error| error.to_string())
    }
}

type Fallible<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

impl Ocr {
    async fn read(&self, job: &Job, tx: &mut PgConnection) -> Fallible<()> {
        let payload: Value = serde_json::from_slice(&job.payload)?;
        let asset: Uuid = serde_json::from_value(payload.get("asset").cloned().unwrap_or_default())?;
        if payload.get("model_id").and_then(Value::as_str) != Some(MODEL) {
            return Err("the job names no OCR model of this server".into());
        }
        if self.models.get().is_none() {
            return Err("the OCR models are not loaded yet".into());
        }
        let Some(row) = sqlx::query(ORIGINAL).bind(asset).fetch_optional(&mut *tx).await? else {
            return Ok(());
        };
        let ocr = Output {
            file: "ocr".into(),
            format: Format::Raw,
            short: 0,
            long: LONG,
            quality: 0,
            wide: false,
        };
        let (rendered, dir) = self.render.sandboxed(tx, &row, |_| vec![ocr]).await?;
        let file = dir.join("out").join("ocr");
        let pixels = std::fs::read(&file)?;
        drop(std::fs::remove_file(&file));
        let &[(Format::Raw, width, height)] = rendered.outputs.as_slice() else {
            return Err("the renderer wrote no raw picture".into());
        };
        let image = Rgb {
            width: width as usize,
            height: height as usize,
            pixels,
        };
        let models = self.models.clone();
        let lines = tokio::task::spawn_blocking(move || {
            let pool = models.get().ok_or("the OCR models are not loaded yet")?;
            let mut infer = |file: &str, input| {
                let mut outputs = pool.run(file, &[vec![input]])?;
                outputs.pop().ok_or_else(|| "the model answered nothing".to_owned())
            };
            read_lines(&mut infer, &image)
        })
        .await??;
        // The text is the lines' together, cleaned as one; each region says where its line is in the version read.
        let text = clean(&lines.iter().map(|l| l.text.as_str()).collect::<Vec<_>>().join("\n"));
        let regions: Vec<Value> = (lines.iter())
            .map(|l| {
                serde_json::json!({
                    "text": l.text,
                    "x": l.x0,
                    "y": l.y0,
                    "width": l.x1 - l.x0,
                    "height": l.y1 - l.y0,
                })
            })
            .collect();
        sqlx::query(
            "INSERT INTO asset_ocr (asset_id, model_id, text, version_id, regions) VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (asset_id, model_id) DO UPDATE SET text = excluded.text, version_id = excluded.version_id,
                 regions = excluded.regions",
        )
        .bind(asset)
        .bind(MODEL)
        .bind(text)
        .bind(row.get::<Option<Uuid>, _>("current_version_id"))
        .bind(Value::Array(regions))
        .execute(&mut *tx)
        .await?;
        Ok(())
    }
}
