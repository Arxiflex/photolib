//! YuNet's outputs read into faces: a score, a box and five landmarks for each cell of its three grids, then
//! non-maximum suppression. OpenCV's `FaceDetectorYN` does the same.

use crate::invalid_request;
use crate::proto::kernel::v1::{CallError, DecodeFacesRequest, DecodeFacesResponse, Face};

/// YuNet's strides: its three outputs of each kind, from the finest grid.
const STRIDES: [u16; 3] = [8, 16, 32];
/// What each of the four kinds of output (class, objectness, box, landmarks) holds per cell.
const PER_CELL: [usize; 4] = [1, 1, 4, 10];
/// The largest tensor side YuNet's outputs are read for.
const MAX_SIDE: u16 = 2048;
const MIN_SCORE: f32 = 0.7;
const MAX_OVERLAP: f32 = 0.3;
const MAX_FACES: u32 = 64;
const MAX_FACES_LIMIT: u32 = 1000;

/// A face in the tensor's pixels.
struct Candidate {
    score: f32,
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
    landmarks: [f32; 10],
}

impl Candidate {
    fn area(&self) -> f32 {
        (self.right - self.left) * (self.bottom - self.top)
    }

    /// The share of the union of the two boxes that both cover.
    fn overlap(&self, other: &Self) -> f32 {
        let width = (self.right.min(other.right) - self.left.max(other.left)).max(0.0);
        let height = (self.bottom.min(other.bottom) - self.top.max(other.top)).max(0.0);
        let both = width * height;
        both / (self.area() + other.area() - both)
    }

    fn finite(&self) -> bool {
        [self.left, self.top, self.right, self.bottom]
            .iter()
            .chain(&self.landmarks)
            .all(|v| v.is_finite())
    }
}

fn floats(bytes: &[u8]) -> Option<Vec<f32>> {
    if !bytes.len().is_multiple_of(4) {
        return None;
    }
    Some(
        bytes
            .as_chunks::<4>()
            .0
            .iter()
            .map(|b| f32::from_le_bytes(*b))
            .collect(),
    )
}

/// `value` unless it is 0 (the default), which must be finite and pass `ok`.
fn option(value: f32, default: f32, ok: impl Fn(f32) -> bool, field: &str) -> Result<f32, CallError> {
    if value == 0.0 {
        Ok(default)
    } else if value.is_finite() && ok(value) {
        Ok(value)
    } else {
        Err(invalid_request(field))
    }
}

/// A side of the tensor, in cells of `stride`.
fn cells(side: u16, stride: u16) -> usize {
    usize::from(side.checked_div(stride).unwrap_or(0))
}

/// The twelve outputs, checked to be the sizes a tensor of `width` × `height` gives.
fn outputs(request: &DecodeFacesRequest, width: u16, height: u16) -> Result<Vec<Vec<f32>>, CallError> {
    let outputs: Option<Vec<Vec<f32>>> = request.outputs.iter().map(|bytes| floats(bytes)).collect();
    let outputs = outputs
        .filter(|o| o.len() == 12)
        .ok_or_else(|| invalid_request("outputs"))?;
    let sized = PER_CELL.iter().enumerate().all(|(kind, per)| {
        STRIDES.iter().enumerate().all(|(s, &stride)| {
            let at = kind.saturating_mul(3).saturating_add(s);
            let cells = cells(width, stride).saturating_mul(cells(height, stride));
            outputs.get(at).map(Vec::len) == Some(cells.saturating_mul(*per))
        })
    });
    if sized {
        Ok(outputs)
    } else {
        Err(invalid_request("outputs"))
    }
}

/// The face of `cell` of the grid `s`, if it scores `min_score`.
fn candidate(outputs: &[Vec<f32>], s: usize, columns: usize, cell: usize, min_score: f32) -> Option<Candidate> {
    let stride = f32::from(*STRIDES.get(s)?);
    let at = |kind: usize| -> Option<&[f32]> {
        let per = *PER_CELL.get(kind)?;
        let from = cell.checked_mul(per)?;
        outputs
            .get(kind.checked_mul(3)?.checked_add(s)?)?
            .get(from..from.checked_add(per)?)
    };
    let unit = |kind: usize| at(kind)?.first().filter(|v| v.is_finite()).map(|v| v.clamp(0.0, 1.0));
    let score = libm::sqrtf(unit(0)? * unit(1)?);
    if score < min_score {
        return None;
    }
    let [dx, dy, dw, dh] = <[f32; 4]>::try_from(at(2)?).ok()?;
    let column = f32::from(u16::try_from(cell.checked_rem(columns)?).ok()?);
    let row = f32::from(u16::try_from(cell.checked_div(columns)?).ok()?);
    let (centre_x, centre_y) = ((column + dx) * stride, (row + dy) * stride);
    let (width, height) = (libm::expf(dw) * stride, libm::expf(dh) * stride);
    let mut landmarks = [0.0; 10];
    for (n, (out, offset)) in landmarks.iter_mut().zip(at(3)?).enumerate() {
        *out = (offset + if n.is_multiple_of(2) { column } else { row }) * stride;
    }
    let candidate = Candidate {
        score,
        left: centre_x - width / 2.0,
        top: centre_y - height / 2.0,
        right: centre_x + width / 2.0,
        bottom: centre_y + height / 2.0,
        landmarks,
    };
    (candidate.finite() && candidate.area() > 0.0).then_some(candidate)
}

/// The candidate as fractions of the tensor, its box inside it.
fn face(c: &Candidate, width: f32, height: f32) -> Option<Face> {
    let (left, top) = (c.left.max(0.0), c.top.max(0.0));
    let (right, bottom) = (c.right.min(width), c.bottom.min(height));
    (right > left && bottom > top).then(|| Face {
        x: left / width,
        y: top / height,
        width: (right - left) / width,
        height: (bottom - top) / height,
        landmarks: c
            .landmarks
            .iter()
            .enumerate()
            .map(|(n, v)| v / if n.is_multiple_of(2) { width } else { height })
            .collect(),
        score: c.score,
    })
}

pub(crate) fn decode_faces(request: &DecodeFacesRequest) -> Result<DecodeFacesResponse, CallError> {
    let side = |v: u32| {
        u16::try_from(v)
            .ok()
            .filter(|v| v.is_multiple_of(32) && (32..=MAX_SIDE).contains(v))
    };
    let width = side(request.width).ok_or_else(|| invalid_request("width"))?;
    let height = side(request.height).ok_or_else(|| invalid_request("height"))?;
    let min_score = option(request.min_score, MIN_SCORE, |v| (0.0..=1.0).contains(&v), "min_score")?;
    let max_overlap = option(request.max_overlap, MAX_OVERLAP, |v| v > 0.0 && v <= 1.0, "max_overlap")?;
    let max_faces = match request.max_faces {
        0 => MAX_FACES,
        n if n <= MAX_FACES_LIMIT => n,
        _ => return Err(invalid_request("max_faces")),
    };
    let outputs = outputs(request, width, height)?;

    let mut found = Vec::new();
    for (s, &stride) in STRIDES.iter().enumerate() {
        let columns = cells(width, stride);
        let count = columns.saturating_mul(cells(height, stride));
        found.extend((0..count).filter_map(|cell| candidate(&outputs, s, columns, cell, min_score)));
    }
    // Best first, ties by the finer grid and the cell, which is the order they were found in.
    found.sort_by(|a, b| b.score.total_cmp(&a.score));
    let mut kept: Vec<Candidate> = Vec::new();
    for candidate in found {
        if kept.len() >= usize::try_from(max_faces).unwrap_or(usize::MAX) {
            break;
        }
        if kept.iter().all(|better| better.overlap(&candidate) <= max_overlap) {
            kept.push(candidate);
        }
    }
    let (width, height) = (f32::from(width), f32::from(height));
    Ok(DecodeFacesResponse {
        faces: kept.iter().filter_map(|c| face(c, width, height)).collect(),
    })
}
