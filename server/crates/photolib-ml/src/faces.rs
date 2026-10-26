//! Faces on the ML role (design 09 §7, ADR-0389): YuNet finds them, SFace (or AuraFace) describes them. The kernel
//! makes each model's input and reads its output, as on every device; this module runs the models through the `Pool`.

use photolib_kernel::proto::kernel::v1::{
    AlignFaceRequest, AlignFaceResponse, CallResponse, DecodeFacesRequest, DecodeFacesResponse, Method,
    NormalizeFaceEmbeddingRequest, NormalizeFaceEmbeddingResponse, PrepareFaceDetectionRequest,
    PrepareFaceDetectionResponse, call_response,
};
use photolib_models::{Model, Target, Task};
use prost::Message;

use crate::{Data, Input, Outputs, Pool};

pub use photolib_kernel::proto::kernel::v1::Face;

/// YuNet's outputs in the order the kernel's `DecodeFaces` reads them.
const OUTPUTS: [&str; 12] = [
    "cls_8", "cls_16", "cls_32", "obj_8", "obj_16", "obj_32", "bbox_8", "bbox_16", "bbox_32", "kps_8", "kps_16",
    "kps_32",
];

/// An upright 8-bit sRGB RGBA picture.
#[derive(Debug, Clone, Copy)]
pub struct Picture<'a> {
    /// In pixels
    pub width: u32,
    /// In pixels
    pub height: u32,
    /// Row by row, four bytes a pixel
    pub rgba: &'a [u8],
}

/// A model file of the pool and the names of its tensors.
#[derive(Debug, Clone)]
struct File {
    pool: String,
    input: String,
    output: String,
}

/// The two models that find and describe faces.
#[derive(Debug, Clone)]
pub struct Models {
    detector: File,
    embedder: File,
    mean: [f32; 3],
    std: [f32; 3],
    /// The embedding's length
    dim: usize,
}

/// A face and what describes it.
#[derive(Debug, Clone, PartialEq)]
pub struct Found {
    /// Where it is, in fractions of the picture, with its landmarks and YuNet's score
    pub face: Face,
    /// A unit vector of the embedding model's length
    pub embedding: Vec<f32>,
}

fn file(model: &Model, task: Task) -> Result<File, String> {
    if model.task != task {
        return Err(format!("{} is not a {task:?} model", model.name()));
    }
    let file = (model.files.iter())
        .find(|f| f.targets.contains(&Target::Server))
        .ok_or_else(|| format!("{} has no file for the server", model.name()))?;
    let golden = file
        .golden
        .as_ref()
        .ok_or_else(|| format!("{} has no golden, so it runs nowhere", file.name))?;
    let (input, output) = (golden.inputs.first(), golden.outputs.first());
    Ok(File {
        pool: format!("{}/{}", model.name(), file.name),
        input: input.ok_or("a golden without inputs")?.name.clone(),
        output: output.ok_or("a golden without outputs")?.clone(),
    })
}

impl Models {
    /// The detector and the embedder, both from the registry with their server file and golden.
    pub fn new(detector: &Model, embedder: &Model) -> Result<Self, String> {
        let preprocess = embedder
            .preprocess
            .as_ref()
            .ok_or_else(|| format!("{} has no preprocessing", embedder.name()))?;
        let dim = embedder.dim.ok_or_else(|| format!("{} has no dim", embedder.name()))?;
        Ok(Self {
            detector: file(detector, Task::FaceDetection)?,
            embedder: file(embedder, Task::FaceEmbedding)?,
            mean: preprocess.mean,
            std: preprocess.std,
            dim: usize::try_from(dim).map_err(|e| e.to_string())?,
        })
    }

    /// The pool names of the files this runs, such as `yunet@2026may/face_detection_yunet_2026may.onnx`.
    pub fn files(&self) -> [&str; 2] {
        [&self.detector.pool, &self.embedder.pool]
    }

    /// The length of an embedding.
    pub fn dim(&self) -> usize {
        self.dim
    }
}

fn ask<Q: Message, R: Message + Default>(method: Method, request: &Q) -> Result<R, String> {
    let answer = CallResponse::decode(photolib_kernel::call(method as u32, &request.encode_to_vec()).as_slice())
        .map_err(|e| e.to_string())?;
    match answer.result {
        Some(call_response::Result::Response(bytes)) => R::decode(bytes.as_slice()).map_err(|e| e.to_string()),
        Some(call_response::Result::Error(error)) => Err(format!("the kernel refused {method:?}: {error:?}")),
        None => Err(format!("the kernel answered {method:?} with nothing")),
    }
}

fn floats(bytes: &[u8]) -> Vec<f32> {
    bytes
        .as_chunks::<4>()
        .0
        .iter()
        .map(|b| f32::from_le_bytes(*b))
        .collect()
}

fn output<'a>(outputs: &'a Outputs, name: &str) -> Result<&'a [f32], String> {
    (outputs.iter())
        .find(|(n, _)| n == name)
        .map(|(_, values)| values.as_slice())
        .ok_or_else(|| format!("the model gave no output {name}"))
}

/// Every face of `picture`, best first.
pub fn detect(pool: &Pool<'_>, models: &Models, picture: &Picture<'_>) -> Result<Vec<Face>, String> {
    let prepared: PrepareFaceDetectionResponse = ask(
        Method::PrepareFaceDetection,
        &PrepareFaceDetectionRequest {
            width: picture.width,
            height: picture.height,
            rgba: picture.rgba.to_vec(),
            max_side: 0,
        },
    )?;
    let shape = vec![1, 3, i64::from(prepared.height), i64::from(prepared.width)];
    let input = Input {
        name: models.detector.input.clone(),
        shape,
        data: Data::F32(floats(&prepared.tensor)),
    };
    let mut ran = pool.run(&models.detector.pool, &[vec![input]])?;
    let outputs = ran.pop().ok_or("the detector gave nothing")?;
    let decoded: DecodeFacesResponse = ask(
        Method::DecodeFaces,
        &DecodeFacesRequest {
            width: prepared.width,
            height: prepared.height,
            outputs: OUTPUTS
                .iter()
                .map(|name| Ok(output(&outputs, name)?.iter().flat_map(|v| v.to_le_bytes()).collect()))
                .collect::<Result<_, String>>()?,
            ..Default::default()
        },
    )?;
    Ok(decoded.faces)
}

/// The embeddings of `faces` of `picture`, in order.
pub fn embed(pool: &Pool<'_>, models: &Models, picture: &Picture<'_>, faces: &[Face]) -> Result<Vec<Vec<f32>>, String> {
    let items = faces
        .iter()
        .map(|face| {
            let aligned: AlignFaceResponse = ask(
                Method::AlignFace,
                &AlignFaceRequest {
                    width: picture.width,
                    height: picture.height,
                    rgba: picture.rgba.to_vec(),
                    landmarks: face.landmarks.clone(),
                    mean: models.mean.to_vec(),
                    std: models.std.to_vec(),
                },
            )?;
            Ok(vec![Input {
                name: models.embedder.input.clone(),
                shape: vec![1, 3, 112, 112],
                data: Data::F32(floats(&aligned.tensor)),
            }])
        })
        .collect::<Result<Vec<_>, String>>()?;
    if items.is_empty() {
        return Ok(Vec::new());
    }
    let ran = pool.run(&models.embedder.pool, &items)?;
    ran.iter()
        .map(|outputs| {
            let values = output(outputs, &models.embedder.output)?;
            if values.len() != models.dim {
                return Err(format!("an embedding of {} values, not {}", values.len(), models.dim));
            }
            let unit: NormalizeFaceEmbeddingResponse = ask(
                Method::NormalizeFaceEmbedding,
                &NormalizeFaceEmbeddingRequest {
                    values: values.to_vec(),
                },
            )?;
            Ok(unit.values)
        })
        .collect()
}

/// Every face of `picture` and its embedding.
pub fn find(pool: &Pool<'_>, models: &Models, picture: &Picture<'_>) -> Result<Vec<Found>, String> {
    let faces = detect(pool, models, picture)?;
    let embeddings = embed(pool, models, picture, &faces)?;
    Ok(faces
        .into_iter()
        .zip(embeddings)
        .map(|(face, embedding)| Found { face, embedding })
        .collect())
}
