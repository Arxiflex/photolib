//! Rendering a recipe on the CPU: the reference every other renderer matches. The local operations change the original
//! as shown, in list order; then the geometry moves its pixels; then the global adjustments are `METHOD_DEVELOP`'s.
//! Stored outputs are sampled at the picture's size, so a proxy and the full picture render alike.

// Pixel loops over images whose size was checked against their bytes (`develop::sized`) and stored outputs checked
// against their dimensions (`check_outputs`): every index is in range, and a slip panics (overflow checks are on in
// release builds), which the ABI fails as kernel.panic. Unfused arithmetic, so that native and WebAssembly agree.
#![allow(
    clippy::arithmetic_side_effects,
    clippy::indexing_slicing,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss,
    clippy::suboptimal_flops,
    clippy::many_single_char_names
)]

use super::{Checked, check};
use crate::develop;
use crate::proto::kernel::v1::{Develop, DevelopRequest, Image, RenderRecipeRequest, RenderRecipeResponse};
use crate::proto::model::v1::{AdjustOperation, StoredOutput, operation::Kind};
use crate::{CallError, invalid_request};

/// `METHOD_RENDER_RECIPE`.
pub(crate) fn render(request: RenderRecipeRequest) -> Result<RenderRecipeResponse, CallError> {
    let recipe = request.recipe.ok_or_else(|| invalid_request("recipe"))?;
    let mut image = request
        .image
        .filter(develop::sized)
        .ok_or_else(|| invalid_request("image"))?;
    let size = (image.width, image.height);
    let checked = check(&recipe, size)?;
    for operation in checked.recipe.operations.iter().filter(|o| !o.disabled) {
        match &operation.kind {
            Some(Kind::LocalAdjust(l)) => {
                if let (Some(mask), Some(adjust)) = (output(&checked, &l.output_id), &l.adjust) {
                    image = adjusted(image, mask, adjust)?;
                }
            }
            Some(Kind::Inpaint(p)) => {
                if let Some(patch) = output(&checked, &p.output_id) {
                    place(&mut image, patch, [p.x, p.y, p.width, p.height].map(f64::from));
                }
            }
            _ => {}
        }
    }
    let develop = checked.develop(Some(size));
    let geometry = Develop {
        quarter_turns: develop.quarter_turns,
        flip: develop.flip,
        crop: develop.crop,
        ..Default::default()
    };
    if develop.quarter_turns != 0 || develop.flip || develop.crop.is_some() {
        image = develop::rearrange(&geometry, image)?;
    }
    if !checked.neutral() {
        let global = Develop {
            quarter_turns: 0,
            flip: false,
            crop: None,
            ..develop
        };
        image = run(global, image)?;
    }
    Ok(RenderRecipeResponse { image: Some(image) })
}

fn output<'a>(checked: &'a Checked, id: &str) -> Option<&'a StoredOutput> {
    checked.recipe.outputs.iter().find(|o| o.output_id == id)
}

fn run(develop: Develop, image: Image) -> Result<Image, CallError> {
    let request = DevelopRequest {
        develop: Some(develop),
        image: Some(image),
        ..Default::default()
    };
    develop::develop(request)?.image.ok_or_else(|| invalid_request("image"))
}

/// `image` with `adjust` applied where `mask` weighs it.
fn adjusted(image: Image, mask: &StoredOutput, adjust: &AdjustOperation) -> Result<Image, CallError> {
    let develop = Develop {
        temperature: adjust.temperature,
        tint: adjust.tint,
        exposure: adjust.exposure,
        contrast: adjust.contrast,
        clarity: adjust.clarity,
        saturation: adjust.saturation,
        ..Default::default()
    };
    let other = run(develop, image.clone())?;
    let (w, h) = (image.width, image.height);
    let mut rgba = image.rgba;
    for y in 0..h {
        let row = bilinear_row(mask, y, h, 1);
        for x in 0..w {
            let weight = row.sample(mask, x, w)[0] / 255.0;
            let at = ((y * w + x) * 4) as usize;
            for c in 0..3 {
                let (from, to) = (f32::from(rgba[at + c]), f32::from(other.rgba[at + c]));
                rgba[at + c] = (from + (to - from) * weight + 0.5) as u8;
            }
        }
    }
    Ok(Image {
        width: w,
        height: h,
        rgba,
    })
}

/// Puts `patch` over `rect`, fractions of the picture, by its alpha.
fn place(image: &mut Image, patch: &StoredOutput, rect: [f64; 4]) {
    let (w, h) = (image.width, image.height);
    let edge = |at: f64, len: f64, full: u32| {
        let f = f64::from(full);
        ((at * f).round().clamp(0.0, f), ((at + len) * f).round().clamp(0.0, f))
    };
    let ((x0, x1), (y0, y1)) = (edge(rect[0], rect[2], w), edge(rect[1], rect[3], h));
    let (x0, x1, y0, y1) = (x0 as u32, x1 as u32, y0 as u32, y1 as u32);
    if x1 <= x0 || y1 <= y0 {
        return;
    }
    for y in y0..y1 {
        let row = bilinear_row(patch, y - y0, y1 - y0, 4);
        for x in x0..x1 {
            let [r, g, b, a] = row.sample(patch, x - x0, x1 - x0);
            let alpha = a / 255.0;
            let at = ((y * w + x) * 4) as usize;
            for (c, v) in [r, g, b].into_iter().enumerate() {
                let from = f32::from(image.rgba[at + c]);
                image.rgba[at + c] = (from + (v - from) * alpha + 0.5) as u8;
            }
        }
    }
}

/// The two rows of a stored output that the row `y` of `rows` target rows lies between, and how far.
struct Row {
    above: u32,
    below: u32,
    t: f32,
    per_pixel: u32,
}

fn bilinear_row(source: &StoredOutput, y: u32, rows: u32, per_pixel: u32) -> Row {
    let (above, below, t) = taps(y, rows, source.height);
    Row {
        above,
        below,
        t,
        per_pixel,
    }
}

/// The source cells that the pixel `i` of `n` lies between, and how far, pixel centres against cell centres.
fn taps(i: u32, n: u32, cells: u32) -> (u32, u32, f32) {
    let at = (i as f32 + 0.5) * cells as f32 / n as f32 - 0.5;
    let low = at.floor();
    let t = at - low;
    let clamp = |v: f32| (v.max(0.0) as u32).min(cells - 1);
    (clamp(low), clamp(low + 1.0), t)
}

impl Row {
    /// The channels of the pixel `x` of `columns`, 0 to 255.
    fn sample(&self, source: &StoredOutput, x: u32, columns: u32) -> [f32; 4] {
        let (left, right, s) = taps(x, columns, source.width);
        let at = |row: u32, col: u32, c: u32| {
            let i = ((row * source.width + col) * self.per_pixel + c) as usize;
            f32::from(source.data.get(i).copied().unwrap_or(0))
        };
        std::array::from_fn(|c| {
            let c = c as u32;
            if c >= self.per_pixel {
                return 0.0;
            }
            let top = at(self.above, left, c) + (at(self.above, right, c) - at(self.above, left, c)) * s;
            let bottom = at(self.below, left, c) + (at(self.below, right, c) - at(self.below, left, c)) * s;
            top + (bottom - top) * self.t
        })
    }
}
