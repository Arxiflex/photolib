//! Faces (design 09 §7, ADR-0389): what YuNet and SFace take and give back, so that the server and every device find
//! the same faces. The models run in the host; the kernel makes their inputs and reads their outputs with f32
//! arithmetic in a fixed order (`libm` for the functions), so that native and WebAssembly builds agree bit for bit.

mod align;
mod decode;
mod geometry;

pub(crate) use align::align_face;
pub(crate) use decode::decode_faces;
pub(crate) use geometry::map_faces;

use crate::invalid_request;
use crate::ml;
use crate::proto::kernel::v1::{
    CallError, NormalizeFaceEmbeddingRequest, NormalizeFaceEmbeddingResponse, PrepareFaceDetectionRequest,
    PrepareFaceDetectionResponse,
};

/// The longer side of YuNet's input unless asked otherwise, and the longest it is asked for.
const DETECTION_SIDE: u32 = 640;
const MAX_DETECTION_SIDE: u32 = 1280;
/// The longest embedding (SFace's has 128 values, AuraFace's 512).
const MAX_EMBEDDING: usize = 2048;

/// The size of an RGBA picture, if `rgba` holds exactly that many pixels.
fn picture(width: u32, height: u32, rgba: &[u8]) -> Result<(u16, u16), CallError> {
    let (Ok(w), Ok(h)) = (u16::try_from(width), u16::try_from(height)) else {
        return Err(invalid_request("rgba"));
    };
    let pixels = usize::from(w).checked_mul(usize::from(h));
    if pixels == Some(0) || pixels.and_then(|n| n.checked_mul(4)) != Some(rgba.len()) {
        return Err(invalid_request("rgba"));
    }
    Ok((w, h))
}

/// The shorter side of a picture whose longer side `long` becomes `long_out`, in multiples of 32 (at least one).
fn short_side(short: u64, long: u64, long_out: u64) -> u64 {
    // short · long_out / long, over 32, rounded to the nearest
    short
        .saturating_mul(long_out)
        .saturating_mul(2)
        .saturating_add(long.saturating_mul(32))
        .checked_div(long.saturating_mul(64))
        .unwrap_or(1)
        .max(1)
        .saturating_mul(32)
}

pub(crate) fn prepare_detection(
    request: &PrepareFaceDetectionRequest,
) -> Result<PrepareFaceDetectionResponse, CallError> {
    let (width, height) = picture(request.width, request.height, &request.rgba)?;
    let most = match request.max_side {
        0 => DETECTION_SIDE,
        n if (32..=MAX_DETECTION_SIDE).contains(&n) => n,
        _ => return Err(invalid_request("max_side")),
    };
    // The long side rounds up to a multiple of 32 but not past the most; the short one keeps the proportions.
    let (long, short) = (u64::from(width.max(height)), u64::from(width.min(height)));
    let cap = u64::from(most.div_euclid(32).saturating_mul(32));
    let long_out = long.div_ceil(32).saturating_mul(32).min(cap);
    let short_out = short_side(short, long, long_out);
    let (out_width, out_height) = if width >= height {
        (long_out, short_out)
    } else {
        (short_out, long_out)
    };
    let (Ok(out_width), Ok(out_height)) = (u16::try_from(out_width), u16::try_from(out_height)) else {
        return Err(invalid_request("max_side"));
    };
    let [red, green, blue] = ml::resample(&request.rgba, (width, height), (out_width, out_height));
    Ok(PrepareFaceDetectionResponse {
        width: u32::from(out_width),
        height: u32::from(out_height),
        tensor: [blue, green, red]
            .iter()
            .flatten()
            .flat_map(|v| v.to_le_bytes())
            .collect(),
    })
}

pub(crate) fn normalize_embedding(
    request: &NormalizeFaceEmbeddingRequest,
) -> Result<NormalizeFaceEmbeddingResponse, CallError> {
    let values = &request.values;
    if values.is_empty() || values.len() > MAX_EMBEDDING || !values.iter().all(|v| v.is_finite()) {
        return Err(invalid_request("values"));
    }
    // Scaled by the largest value so that the squares cannot overflow.
    let largest = values.iter().fold(0.0f32, |m, v| m.max(v.abs()));
    let sum: f32 = values.iter().map(|v| (v / largest) * (v / largest)).sum();
    let norm = libm::sqrtf(sum) * largest;
    if !norm.is_finite() || norm <= 0.0 {
        return Err(invalid_request("values"));
    }
    Ok(NormalizeFaceEmbeddingResponse {
        values: values.iter().map(|v| v / norm).collect(),
    })
}
