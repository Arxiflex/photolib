//! A version's edit recipe applied to the decoded picture (roadmap M8-01, ADR-0391), by the kernel's renderer, so that
//! a thumbnail, a preview, the text OCR reads and a full-size export all show what the editor showed. The picture is
//! held whole, as 8-bit RGBA, for the kernel: the edit is refused beyond `PIXELS`, which only a format that cannot
//! be decoded smaller (a PNG, a HEIC) reaches, since a JPEG is decoded at the size its outputs need.

// Conversions between a picture's 8-bit RGB and the kernel's RGBA, whose lengths and sizes this module has just
// computed from the same dimensions (libvips counts in i32, the kernel in u32).
#![allow(
    clippy::arithmetic_side_effects,
    clippy::indexing_slicing,
    clippy::cast_possible_wrap,
    clippy::cast_sign_loss,
    clippy::chunks_exact_to_as_chunks
)]

use std::path::Path;

use photolib_kernel::proto::{
    kernel::v1::{
        CallResponse, Image, Method, RenderRecipeRequest, RenderRecipeResponse, ResolveRecipeRequest,
        ResolveRecipeResponse, call_response,
    },
    model::v1::EditRecipe,
};
use prost::Message;
use rs_vips::{VipsImage, enums::BandFormat};

use super::{colour, flat, orient};
use crate::Failure;

/// The most pixels of a picture that an edit is rendered from.
const PIXELS: u64 = 48_000_000;

/// The recipe in `path` and the size of the edited picture for an upright original of `upright` pixels.
pub(super) fn read(path: &Path, upright: (u32, u32)) -> Result<(EditRecipe, (u32, u32)), Failure> {
    let bytes = std::fs::read(path).map_err(|e| Failure::Transient(e.to_string()))?;
    let recipe = EditRecipe::decode(bytes.as_slice()).map_err(|e| Failure::Unsupported(format!("no recipe: {e}")))?;
    let request = ResolveRecipeRequest {
        recipe: Some(recipe),
        width: upright.0,
        height: upright.1,
    };
    let resolved: ResolveRecipeResponse = kernel(Method::ResolveRecipe, &request)?;
    let recipe = resolved
        .recipe
        .ok_or_else(|| Failure::Unsupported("the kernel returned no recipe".into()))?;
    Ok((recipe, (resolved.width, resolved.height)))
}

/// `source`, turned upright for `orientation`, in sRGB and edited by `recipe`.
pub(super) fn apply(source: &VipsImage, orientation: i32, recipe: &EditRecipe) -> Result<VipsImage, Failure> {
    let failed =
        |step: &'static str| move |e: rs_vips::error::Error| Failure::Unsupported(format!("cannot {step}: {e}"));
    let upright = orient(source, orientation).map_err(failed("turn"))?;
    let (width, height) = (upright.get_width() as u32, upright.get_height() as u32);
    if u64::from(width) * u64::from(height) > PIXELS {
        return Err(Failure::LimitExceeded(format!(
            "{width}×{height} is more than the {PIXELS} pixels an edit is rendered from"
        )));
    }
    let (srgb, _) = colour(&upright, false).map_err(failed("convert colours"))?;
    let rgb = flat(&srgb).map_err(failed("read pixels"))?;
    let rgba = rgb.chunks_exact(3).flat_map(|p| [p[0], p[1], p[2], 255]).collect();
    let request = RenderRecipeRequest {
        recipe: Some(recipe.clone()),
        image: Some(Image { width, height, rgba }),
    };
    let edited = kernel::<RenderRecipeResponse>(Method::RenderRecipe, &request)?
        .image
        .ok_or_else(|| Failure::Unsupported("the kernel returned no picture".into()))?;
    let rgb: Vec<u8> = edited.rgba.chunks_exact(4).flat_map(|p| [p[0], p[1], p[2]]).collect();
    VipsImage::new_from_memory_copy(&rgb, edited.width as i32, edited.height as i32, 3, BandFormat::Uchar)
        .and_then(|image| image.copy_memory())
        .map_err(failed("load the edited picture"))
}

fn kernel<R: Message + Default>(method: Method, request: &impl Message) -> Result<R, Failure> {
    let answer = photolib_kernel::call(method as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).ok().and_then(|a| a.result) {
        Some(call_response::Result::Response(bytes)) => {
            R::decode(bytes.as_slice()).map_err(|e| Failure::Unsupported(format!("cannot edit: {e}")))
        }
        other => Err(Failure::Unsupported(format!("cannot edit: {other:?}"))),
    }
}
