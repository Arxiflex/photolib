//! A face cut out for SFace: the similarity transform (rotation, uniform scale, shift) that puts the five landmarks as
//! near as it can to ArcFace's template in 112 × 112, and the picture sampled through it bilinearly, black beyond its
//! edges. OpenCV's `FaceRecognizerSF.alignCrop` does the same.

use crate::invalid_request;
use crate::proto::kernel::v1::{AlignFaceRequest, AlignFaceResponse, CallError};

/// The side of SFace's input.
const SIDE: u16 = 112;
/// ArcFace's template of the right eye, left eye, nose and right and left mouth corner in it.
const TEMPLATE: [Complex; 5] = [
    (38.2946, 51.6963),
    (73.5318, 51.5014),
    (56.0252, 71.7366),
    (41.5493, 92.3655),
    (70.7299, 92.2041),
];

/// A complex number as (real, imaginary): similarity transforms of the plane are `z ↦ c·z + t`.
type Complex = (f64, f64);

fn times((a, b): Complex, (c, d): Complex) -> Complex {
    (a.mul_add(c, -b * d), a.mul_add(d, b * c))
}

fn minus(a: Complex, b: Complex) -> Complex {
    (a.0 - b.0, a.1 - b.1)
}

fn mean(points: &[Complex]) -> Complex {
    let sum = points.iter().fold((0.0, 0.0), |s, p| (s.0 + p.0, s.1 + p.1));
    let n = f64::from(u8::try_from(points.len()).unwrap_or(1).max(1));
    (sum.0 / n, sum.1 / n)
}

/// The least-squares similarity transform from `from` to `to`, as `(c, t)`; none if the points coincide.
fn similarity(from: &[Complex], to: &[Complex]) -> Option<(Complex, Complex)> {
    let (mean_from, mean_to) = (mean(from), mean(to));
    let (mut sum, mut spread) = ((0.0, 0.0), 0.0);
    for (a, b) in from.iter().zip(to) {
        let (a, b) = (minus(*a, mean_from), minus(*b, mean_to));
        // conj(a) · b
        let product = times((a.0, -a.1), b);
        sum = (sum.0 + product.0, sum.1 + product.1);
        spread += a.0.mul_add(a.0, a.1 * a.1);
    }
    if spread.is_nan() || spread <= 1e-9 {
        return None;
    }
    let c = (sum.0 / spread, sum.1 / spread);
    Some((c, minus(mean_to, times(c, mean_from))))
}

/// `a` at 0 to `b` at 1.
fn lerp(a: f32, b: f32, weight: f32) -> f32 {
    a.mul_add(1.0 - weight, b * weight)
}

/// The picture to sample.
struct Picture<'a> {
    rgba: &'a [u8],
    width: usize,
    height: usize,
}

impl Picture<'_> {
    /// A channel of a pixel, 0 beyond the picture.
    fn at(&self, x: i64, y: i64, channel: usize) -> f32 {
        let (Ok(x), Ok(y)) = (usize::try_from(x), usize::try_from(y)) else {
            return 0.0;
        };
        if x >= self.width || y >= self.height {
            return 0.0;
        }
        let i = y.saturating_mul(self.width).saturating_add(x).saturating_mul(4);
        self.rgba.get(i.saturating_add(channel)).map_or(0.0, |&v| f32::from(v))
    }

    /// A channel at a position, between the four pixels around it; a pixel's centre is its integer position.
    #[allow(clippy::cast_possible_truncation)] // the position is clamped to the range of an i32 first
    fn bilinear(&self, (x, y): Complex, channel: usize) -> f32 {
        let limit = f64::from(i32::MAX);
        let (x, y) = (x.clamp(-limit, limit), y.clamp(-limit, limit));
        let (fx, fy) = (libm::floor(x), libm::floor(y));
        let (wx, wy) = ((x - fx) as f32, (y - fy) as f32);
        let (x0, y0) = (fx as i64, fy as i64);
        let row = |y: i64| lerp(self.at(x0, y, channel), self.at(x0.saturating_add(1), y, channel), wx);
        lerp(row(y0), row(y0.saturating_add(1)), wy)
    }
}

/// Three finite values, red first, that each pass `ok`.
fn channels(values: &[f32], ok: impl Fn(f32) -> bool) -> Option<[f32; 3]> {
    <[f32; 3]>::try_from(values)
        .ok()
        .filter(|v| v.iter().all(|&v| v.is_finite() && ok(v)))
}

/// A model's scaling of the channels: their means and standard deviations.
type Scaling = ([f32; 3], [f32; 3]);

/// The model's scaling of each channel: none for values 0 to 255.
fn scaling(request: &AlignFaceRequest) -> Result<Option<Scaling>, CallError> {
    if request.mean.is_empty() && request.std.is_empty() {
        return Ok(None);
    }
    let mean = channels(&request.mean, |_| true).ok_or_else(|| invalid_request("mean"))?;
    let std = channels(&request.std, |v| v != 0.0).ok_or_else(|| invalid_request("std"))?;
    Ok(Some((mean, std)))
}

pub(crate) fn align_face(request: &AlignFaceRequest) -> Result<AlignFaceResponse, CallError> {
    let (width, height) = super::picture(request.width, request.height, &request.rgba)?;
    let scaling = scaling(request)?;
    let landmarks: Vec<Complex> = request
        .landmarks
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&[x, y]| (f64::from(x) * f64::from(width), f64::from(y) * f64::from(height)))
        .collect();
    let finite = request.landmarks.iter().all(|v| v.is_finite());
    let (c, t) = (landmarks.len() == TEMPLATE.len() && request.landmarks.len() == 10 && finite)
        .then(|| similarity(&landmarks, &TEMPLATE))
        .flatten()
        .ok_or_else(|| invalid_request("landmarks"))?;
    // The transform maps the picture onto the face; each pixel of the face reads where it came from, at (z - t) / c.
    let norm = c.0.mul_add(c.0, c.1 * c.1);
    let picture = Picture {
        rgba: &request.rgba,
        width: usize::from(width),
        height: usize::from(height),
    };
    let mut tensor = Vec::with_capacity(usize::from(SIDE).saturating_mul(usize::from(SIDE)).saturating_mul(12));
    for channel in 0..3 {
        for y in 0..SIDE {
            for x in 0..SIDE {
                let (dx, dy) = (f64::from(x) - t.0, f64::from(y) - t.1);
                let source = (c.0.mul_add(dx, c.1 * dy) / norm, c.0.mul_add(dy, -c.1 * dx) / norm);
                let value = picture.bilinear(source, channel);
                let scaled = match scaling {
                    Some((mean, std)) => {
                        (value / 255.0 - mean.get(channel).copied().unwrap_or(0.0))
                            / std.get(channel).copied().unwrap_or(1.0)
                    }
                    None => value,
                };
                tensor.extend(scaled.to_le_bytes());
            }
        }
    }
    Ok(AlignFaceResponse { tensor })
}
