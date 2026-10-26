//! Conformance cases of the face calls (ADR-0389): what is prepared for YuNet and SFace, what is read from YuNet and
//! how boxes follow an edit. Every binding is held to the values of the Rust build.

use super::computed_case;
use photolib_kernel::proto::kernel::v1::{
    AlignFaceRequest, DecodeFacesRequest, Develop, Face, MapFacesRequest, Method, NormalizeFaceEmbeddingRequest,
    PrepareFaceDetectionRequest, Rect,
};
use serde_json::Value;

pub(crate) const DESCRIPTION: &str = "Face detection and embedding (ADR-0389): the inputs of YuNet and SFace, its outputs read, and boxes moved by an edit.";

fn floats(values: &[f32]) -> Vec<u8> {
    values.iter().flat_map(|v| v.to_le_bytes()).collect()
}

/// A picture of a pattern that varies at every scale.
fn pixels(width: u32, height: u32) -> Vec<u8> {
    (0..width * height * 4).map(|i| (i * 37 % 251) as u8).collect()
}

/// YuNet's outputs for a 64 × 32 tensor with two faces, one in the cell (3, 1) of stride 8 and one in (1, 0) of
/// stride 16, the rest empty.
fn outputs() -> Vec<Vec<u8>> {
    let cells = |s: u32| ((64 / s) * (32 / s)) as usize;
    let mut tensors: Vec<Vec<f32>> = [1usize, 1, 4, 10]
        .into_iter()
        .flat_map(|per| [8, 16, 32].map(|s| vec![0.0; cells(s) * per]))
        .collect();
    let mut put = |s: usize, cell: usize, scores: f32, bbox: [f32; 4], kps: [f32; 10]| {
        tensors[s][cell] = scores;
        tensors[3 + s][cell] = scores;
        tensors[6 + s][cell * 4..cell * 4 + 4].copy_from_slice(&bbox);
        tensors[9 + s][cell * 10..cell * 10 + 10].copy_from_slice(&kps);
    };
    put(
        0,
        8 + 3,
        0.93,
        [0.4, 0.6, 0.7, 0.9],
        [-0.6, -0.4, 0.5, -0.4, 0.0, 0.2, -0.4, 0.8, 0.4, 0.8],
    );
    put(
        1,
        1,
        0.81,
        [0.3, 0.5, 0.2, 0.3],
        [-0.3, -0.2, 0.3, -0.2, 0.0, 0.1, -0.2, 0.4, 0.2, 0.4],
    );
    tensors.iter().map(|t| floats(t)).collect()
}

pub(crate) fn face_cases() -> Vec<Value> {
    [detection_cases(), embedding_cases(), map_cases()].concat()
}

/// What YuNet takes and gives back.
fn detection_cases() -> Vec<Value> {
    let detection = |width: u32, height: u32, max_side: u32| PrepareFaceDetectionRequest {
        width,
        height,
        rgba: pixels(width, height),
        max_side,
    };
    let decode = DecodeFacesRequest {
        width: 64,
        height: 32,
        outputs: outputs(),
        ..Default::default()
    };
    let prepare = |name, request: &_| computed_case(name, Method::PrepareFaceDetection, request);
    vec![
        prepare("a wide image for YuNet", &detection(100, 50, 0)),
        prepare("a tall image for YuNet, at most 64", &detection(30, 90, 64)),
        prepare("no image for YuNet", &detection(0, 50, 0)),
        computed_case("two faces in YuNet's outputs", Method::DecodeFaces, &decode),
        computed_case(
            "YuNet's outputs, stricter",
            Method::DecodeFaces,
            &DecodeFacesRequest {
                min_score: 0.9,
                ..decode.clone()
            },
        ),
        computed_case(
            "YuNet's outputs of another size",
            Method::DecodeFaces,
            &DecodeFacesRequest { width: 32, ..decode },
        ),
    ]
}

/// What SFace takes and gives back.
fn embedding_cases() -> Vec<Value> {
    let align = |width: u32, height: u32, landmarks: Vec<f32>| AlignFaceRequest {
        width,
        height,
        rgba: pixels(width, height),
        landmarks,
        ..Default::default()
    };
    let landmarks = vec![0.35, 0.4, 0.65, 0.4, 0.5, 0.55, 0.38, 0.7, 0.62, 0.7];
    let normalize = |values: Vec<f32>| NormalizeFaceEmbeddingRequest { values };
    vec![
        computed_case("a face aligned for SFace", Method::AlignFace, &align(96, 80, landmarks)),
        computed_case(
            "a face at the edge aligned for SFace",
            Method::AlignFace,
            &align(24, 24, vec![0.2; 10]),
        ),
        computed_case("a face without landmarks", Method::AlignFace, &align(8, 8, vec![])),
        computed_case(
            "a face scaled for AuraFace",
            Method::AlignFace,
            &AlignFaceRequest {
                mean: vec![0.5; 3],
                std: vec![0.5; 3],
                ..align(96, 80, vec![0.35, 0.4, 0.65, 0.4, 0.5, 0.55, 0.38, 0.7, 0.62, 0.7])
            },
        ),
        computed_case(
            "an embedding made a unit vector",
            Method::NormalizeFaceEmbedding,
            &normalize(vec![1.5, -2.0, 0.25, 4.0]),
        ),
        computed_case(
            "an embedding of nothing",
            Method::NormalizeFaceEmbedding,
            &normalize(vec![0.0; 4]),
        ),
    ]
}

/// Faces moved by edits.
fn map_cases() -> Vec<Value> {
    let face = Face {
        x: 0.3,
        y: 0.2,
        width: 0.25,
        height: 0.4,
        landmarks: vec![0.35, 0.3, 0.5, 0.3, 0.42, 0.4, 0.37, 0.5, 0.48, 0.5],
        score: 0.875,
    };
    let edit = |quarter_turns, flip, crop: Option<(u32, u32, u32, u32)>| Develop {
        quarter_turns,
        flip,
        crop: crop.map(|(x, y, width, height)| Rect { x, y, width, height }),
        ..Default::default()
    };
    let map = |name, edit: Develop, to_original: bool| {
        let request = MapFacesRequest {
            faces: vec![face.clone()],
            width: 80,
            height: 60,
            edit: Some(edit),
            to_original,
        };
        computed_case(name, Method::MapFaces, &request)
    };
    vec![
        map("a face turned a quarter", edit(1, false, None), false),
        map("a face mirrored", edit(0, true, None), false),
        map(
            "a face turned, mirrored and cropped",
            edit(3, true, Some((5, 10, 40, 50))),
            false,
        ),
        map(
            "a face cut away by a crop",
            edit(0, false, Some((60, 0, 20, 60))),
            false,
        ),
        map(
            "a face of the copy back in the original",
            edit(2, true, Some((5, 10, 60, 40))),
            true,
        ),
        map(
            "a crop beyond the picture",
            edit(0, false, Some((60, 0, 40, 60))),
            false,
        ),
    ]
}
