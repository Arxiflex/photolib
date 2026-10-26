//! PrepareImage (design 09 §2.2, ADR-0254): the input of image models, made by the same code on the server and every
//! device so that their outputs compare. The whole image is resized to the model's square, as SigLIP 2's processor
//! does, or cropped to it for a model whose processor crops: each channel goes through a separable triangle filter,
//! the bilinear filter widened to the scale when shrinking, then is normalised. Only f32 arithmetic in a fixed order,
//! so that native and WebAssembly builds agree bit for bit.

use crate::invalid_request;
use crate::proto::kernel::v1::{CallError, PrepareImageRequest, PrepareImageResponse};

/// The largest input a model takes.
const MAX_SIZE: u16 = 1024;

/// For each output along an axis, the first source it reads and the weights from there on, which sum to one.
type Taps = Vec<(usize, Vec<f32>)>;

pub(crate) fn prepare_image(request: &PrepareImageRequest) -> Result<PrepareImageResponse, CallError> {
    let (Ok(width), Ok(height)) = (u16::try_from(request.width), u16::try_from(request.height)) else {
        return Err(invalid_request("rgba"));
    };
    let pixels = usize::from(width).checked_mul(usize::from(height));
    if pixels == Some(0) || pixels.and_then(|n| n.checked_mul(4)) != Some(request.rgba.len()) {
        return Err(invalid_request("rgba"));
    }
    let size = u16::try_from(request.size)
        .ok()
        .filter(|size| (1..=MAX_SIZE).contains(size))
        .ok_or_else(|| invalid_request("size"))?;
    let mean = channels(&request.mean, |_| true).ok_or_else(|| invalid_request("mean"))?;
    let std = channels(&request.std, |v| v != 0.0).ok_or_else(|| invalid_request("std"))?;

    let span = |length: u16| if request.crop { width.min(height) } else { length };
    let (columns, rows) = (taps(width, span(width), size), taps(height, span(height), size));
    let side = usize::from(size);
    let stride = usize::from(width).saturating_mul(4);
    let tensor = mean
        .into_iter()
        .zip(std)
        .enumerate()
        .flat_map(|(channel, (mean, std))| {
            let at = |y: usize, x: usize| {
                let i = y.saturating_mul(stride).saturating_add(x.saturating_mul(4));
                request
                    .rgba
                    .get(i.saturating_add(channel))
                    .map_or(0.0, |&v| f32::from(v))
            };
            // Along the lines of the axis that reads fewer first, so that a long thin image costs no more than its
            // square.
            let plane = if reach(&rows).len() <= reach(&columns).len() {
                separable(at, &rows, &columns)
            } else {
                let transposed = separable(|x, y| at(y, x), &columns, &rows);
                (0..side)
                    .flat_map(|y| transposed.iter().skip(y).step_by(side).copied())
                    .collect()
            };
            plane
                .into_iter()
                .flat_map(move |v| ((v / 255.0 - mean) / std).to_le_bytes())
        })
        .collect();
    Ok(PrepareImageResponse { tensor })
}

/// The red, green and blue planes of an RGBA image of `width` × `height` resized to `out_width` × `out_height` by the
/// same filter, as values 0 to 255 not rounded.
pub(crate) fn resample(rgba: &[u8], (width, height): (u16, u16), (out_width, out_height): (u16, u16)) -> [Vec<f32>; 3] {
    let (columns, rows) = (taps(width, width, out_width), taps(height, height, out_height));
    let stride = usize::from(width).saturating_mul(4);
    std::array::from_fn(|channel| {
        let at = |y: usize, x: usize| {
            let i = y.saturating_mul(stride).saturating_add(x.saturating_mul(4));
            rgba.get(i.saturating_add(channel)).map_or(0.0, |&v| f32::from(v))
        };
        separable(at, &rows, &columns)
    })
}

/// Three finite values, red first, that each pass `ok`.
fn channels(values: &[f32], ok: impl Fn(f32) -> bool) -> Option<[f32; 3]> {
    <[f32; 3]>::try_from(values)
        .ok()
        .filter(|v| v.iter().all(|&v| v.is_finite() && ok(v)))
}

/// The filter along an axis `length` long whose centred `span` is scaled to `size`. Sources beyond the image do not
/// count.
#[allow(clippy::suboptimal_flops)] // unfused, as below
fn taps(length: u16, span: u16, size: u16) -> Taps {
    let scale = f32::from(size) / f32::from(span);
    let support = (1.0 / scale).max(1.0);
    let offset = f32::from(length.saturating_sub(span)) / 2.0;
    (0..size)
        .map(|out| {
            let centre = (f32::from(out) + 0.5) / scale + offset;
            let first = clamp((centre - support).floor(), length);
            let weights: Vec<f32> = (first..clamp((centre + support).ceil(), length))
                .map(|i| (1.0 - (f32::from(i) + 0.5 - centre).abs() / support).max(0.0))
                .collect();
            let sum: f32 = weights.iter().sum();
            (usize::from(first), weights.into_iter().map(|w| w / sum).collect())
        })
        .collect()
}

/// The sources an axis's taps read.
fn reach(taps: &Taps) -> std::ops::Range<usize> {
    let end = taps
        .iter()
        .map(|(first, weights)| first.saturating_add(weights.len()))
        .max();
    taps.first().map_or(0, |tap| tap.0)..end.unwrap_or(0)
}

/// `at(line, i)` filtered along each line that `lines` reads by `along`, then across them by `lines`: a row of
/// `along.len()` values for each of `lines`.
// Sums of products stay unfused: a fused multiply-add rounds once, so results would differ by where it exists.
#[allow(clippy::suboptimal_flops)]
fn separable(at: impl Fn(usize, usize) -> f32, lines: &Taps, along: &Taps) -> Vec<f32> {
    let at = &at;
    let top = reach(lines).start;
    let filtered: Vec<f32> = reach(lines)
        .flat_map(|line| {
            along.iter().map(move |(first, weights)| {
                weights
                    .iter()
                    .enumerate()
                    .fold(0.0, |sum, (k, w)| sum + at(line, first.saturating_add(k)) * w)
            })
        })
        .collect();
    lines
        .iter()
        .flat_map(|(first, weights)| {
            let mut line = vec![0.0f32; along.len()];
            for (row, w) in filtered
                .chunks_exact(along.len())
                .skip(first.saturating_sub(top))
                .zip(weights)
            {
                for (out, v) in line.iter_mut().zip(row) {
                    *out += v * w;
                }
            }
            line
        })
        .collect()
}

#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)] // clamped to 0..=u16::MAX first
fn clamp(v: f32, length: u16) -> u16 {
    v.clamp(0.0, f32::from(length)) as u16
}
