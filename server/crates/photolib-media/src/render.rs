//! Image renditions with libvips (photolib-design docs/08 §4): one decode per image for every rendition asked of it,
//! upright, colour-managed and without metadata, and its ThumbHash. The loader is the one for the MIME type the parent
//! sniffed from the magic bytes, never one libvips picks, so no other loader (ImageMagick, PDF, SVG) ever runs.

use std::path::{Path, PathBuf};

use photolib_kernel::proto::kernel::v1::{
    CallResponse, EncodeThumbHashRequest, EncodeThumbHashResponse, Method, call_response,
};
use prost::Message;
use rs_vips::{
    Vips, VipsImage,
    enums::{Access, Angle, BandFormat, Direction, ForeignKeep, Interpretation},
    voption::{Setter, VOption},
};
use serde::{Deserialize, Serialize};

use crate::{Failure, Limits, Policy, Worker, child::SYSTEM, gainmap, hdr, heif, probe::probe, raster};

mod edit;

/// One image and the renditions to make of it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Request {
    pub input: PathBuf,
    pub mime: String,
    /// The orientation to apply instead of the image's own: a RAW's, for its embedded preview.
    pub orientation: Option<u8>,
    /// The edit recipe (`photolib.model.v1.EditRecipe`, encoded) of the version to render, in a file the child may
    /// read: the picture is edited, upright, before the outputs are fitted (ADR-0391).
    #[serde(default)]
    pub edit: Option<PathBuf>,
    pub outputs: Vec<Output>,
}

/// A rendition: fitted so that its short side is `short` (none when 0) and its long side at most `long`, never
/// enlarged.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Output {
    /// A file name in the child's output directory.
    pub file: String,
    pub format: Format,
    pub short: u32,
    pub long: u32,
    pub quality: u8,
    /// A wide-gamut source stays wide, as Display P3 with its profile; anything else is sRGB without one.
    pub wide: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Format {
    Webp,
    /// WebP instead when the image has an alpha channel.
    Jpeg,
    /// 8-bit RGB pixels row by row, no header (the size is in [`Rendered`]), alpha flattened onto white: what OCR
    /// reads, which needs no decoder of its own in the process that asked.
    Raw,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rendered {
    /// Per output: its format, width and height.
    pub outputs: Vec<(Format, u32, u32)>,
    /// The ThumbHash of the smallest output.
    pub thumbhash: Vec<u8>,
}

impl Worker {
    /// A renderer reading the files linked into `input` and writing its outputs into `output`.
    pub fn renderer(photolibd: PathBuf, input: PathBuf, output: PathBuf) -> Self {
        let read = std::iter::once(input).chain(SYSTEM.map(PathBuf::from));
        let policy = Policy {
            read: read.collect(),
            write: Some(output),
            limits: Limits::IMAGE,
        };
        Worker::new(photolibd, policy, vec![])
    }

    pub async fn render(&mut self, request: &Request) -> Result<Rendered, Failure> {
        let line = serde_json::to_string(request).expect("a request serialises") + "\n";
        let reply = self.call(line.as_bytes(), |_| true).await?;
        serde_json::from_str(&reply).unwrap_or_else(|_| Err(Failure::DecoderCrash("a malformed answer".into())))
    }
}

/// Renders `request` in the child into its output directory `out`. libvips starts with the first request, inside
/// the sandbox, with one thread (a child is one worker slot) and no operation cache.
#[allow(clippy::too_many_lines)] // one pass over the decoded picture: header, sizes, decode, edit, then each output
pub fn render(request: &Request, out: &Path, limits: &Limits) -> Result<Rendered, Failure> {
    start();
    let raw = match request.mime.starts_with("image/x-") {
        true => Some(std::fs::read(&request.input).map_err(transient)?),
        false => None,
    };
    let preview = raw.as_deref().map(largest_jpeg).transpose()?;
    let decode = |shrink| load(&request.input, &request.mime, preview, shrink).map_err(failed("decode"));
    let file = || std::fs::read(&request.input).map_err(transient);
    let header = match request.mime.as_str() {
        "image/bmp" => raster::bmp(&file()?, limits.pixels)?,
        "image/vnd.adobe.photoshop" => raster::psd(&file()?, limits.pixels)?,
        _ => decode(1)?,
    };
    let (width, height) = (header.get_width() as u32, header.get_height() as u32);
    within(width, height, limits)?;
    let mut orientation = request.orientation.map_or(header.get_orientation(), i32::from);
    let mut turned = (5..=8).contains(&orientation);
    let mut upright = if turned { (height, width) } else { (width, height) };
    let recipe = request
        .edit
        .as_deref()
        .map(|path| edit::read(path, upright))
        .transpose()?;
    if let Some((_, size)) = &recipe {
        upright = *size;
    }
    let sizes: Vec<_> = request.outputs.iter().map(|o| fit(upright, o)).collect();
    let mut order: Vec<usize> = (0..sizes.len()).collect();
    order.sort_by_key(|&i| std::cmp::Reverse(sizes[i].0 * sizes[i].1));
    let largest = order
        .first()
        .and_then(|&i| sizes.get(i))
        .map_or(1, |size| size.0.max(size.1));
    let shrinks = request.mime == "image/jpeg" || preview.is_some();
    let shrink = if shrinks { shrink_for(largest, upright) } else { 1 };
    let (mut gain_map, mut hdr) = (Gain::of(request), hdr_of(request));
    let mut source = if shrink > 1 { decode(shrink)? } else { header };
    if let Some((recipe, _)) = &recipe {
        // The edit is made on the SDR picture, and a gain map no longer fits an edited one.
        if let Some(hdr) = hdr.take() {
            source = hdr::tone_map(&source, hdr).map_err(failed("tone-map"))?;
        }
        gain_map = None;
        source = edit::apply(&source, orientation, recipe)?;
        // The edited picture is upright, in sRGB.
        (orientation, turned) = (1, false);
    }
    let mut rendered = Rendered {
        outputs: vec![(Format::Webp, 0, 0); sizes.len()],
        thumbhash: vec![],
    };
    for &i in &order {
        let (output, (w, h)) = (&request.outputs[i], sizes[i]);
        // Each output is made from the one before it, the largest from the decoded image.
        let (w, h) = if turned { (h, w) } else { (w, h) };
        let scale = |to: u32, from: i32| f64::from(to) / f64::from(from);
        let options = VOption::new().set("vscale", scale(h, source.get_height()));
        source = (source.resize_with_opts(scale(w, source.get_width()), options))
            .and_then(|resized| resized.copy_memory())
            .map_err(failed("resize"))?;
        // PQ and HLG pictures become SDR once, at the largest size, as video frames do (ADR-0390).
        if let Some(hdr) = hdr.take() {
            source = hdr::tone_map(&source, hdr).map_err(failed("tone-map"))?;
        }
        let (image, p3) = orient(&source, orientation)
            .and_then(|image| colour(&image, output.wide))
            .map_err(failed("convert colours"))?;
        let format = match output.format {
            Format::Jpeg if !image.hasalpha() => Format::Jpeg,
            Format::Raw => Format::Raw,
            _ => Format::Webp,
        };
        let keep = if p3 { ForeignKeep::Icc } else { ForeignKeep::None };
        let options = VOption::new()
            .set("Q", i32::from(output.quality))
            .set("keep", keep as i32);
        let bytes = match format {
            Format::Raw => flat(&image),
            Format::Jpeg => image
                .jpegsave_buffer_with_opts(options.set("optimize-coding", true))
                .map(|jpeg| {
                    with_gain(
                        gain_map.as_ref(),
                        jpeg,
                        f64::from(w) / f64::from(width),
                        orientation,
                        output.quality,
                    )
                }),
            // The fastest effort: at these sizes a higher one costs twice the time for no fewer bytes.
            Format::Webp => image.webpsave_buffer_with_opts(options.set("effort", 0)),
        };
        std::fs::write(out.join(&output.file), bytes.map_err(failed("encode"))?).map_err(transient)?;
        rendered.outputs[i] = (format, image.get_width() as u32, image.get_height() as u32);
        if Some(&i) == order.last() {
            rendered.thumbhash = thumbhash(&image)?;
        }
    }
    Ok(rendered)
}

/// Whether a picture of `width` × `height` is within the pixels `limits` allows.
fn within(width: u32, height: u32, limits: &Limits) -> Result<(), Failure> {
    if u64::from(width) * u64::from(height) > limits.pixels {
        return Err(Failure::LimitExceeded(format!(
            "{width}×{height} is more than {} pixels",
            limits.pixels
        )));
    }
    Ok(())
}

/// Starts libvips, once, inside the sandbox, with one thread (a child is one worker slot) and no operation cache.
fn start() {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(|| {
        // glibc maps a block over its dynamic threshold anew and trims the heap beyond twice that, so each photo
        // would fault in every page of libvips' buffers again. Freeing a mapped block raises the threshold to its
        // size (mallopt(3)): to 32 MiB here, the most it rises to, its own size and its page aside.
        drop(std::hint::black_box(Vec::<u8>::with_capacity((32 << 20) - (8 << 10))));
        if Vips::init("photolibd").is_ok() {
            Vips::concurrency_set(1);
            Vips::cache_set_max(0);
        }
    });
}

/// How much a JPEG decodes smaller, 1/2, 1/4 or 1/8, when the largest output of `largest` pixels still fits `upright`.
fn shrink_for(largest: u32, upright: (u32, u32)) -> i32 {
    [8u32, 4, 2]
        .into_iter()
        .find(|s| largest.saturating_mul(*s) <= upright.0.max(upright.1))
        .map_or(1, |s| i32::try_from(s).unwrap_or(1))
}

/// The gain map of a source, from wherever its format keeps it.
enum Gain {
    Jpeg(gainmap::GainMap),
    Heif(heif::HeifMap, gainmap::Carried),
}

impl Gain {
    /// The gain map of the picture `request` renders, if it has one.
    fn of(request: &Request) -> Option<Self> {
        match request.mime.as_str() {
            "image/jpeg" => gainmap::read(&request.input).map(Self::Jpeg),
            "image/heic" | "image/avif" => heif::gain_map(&request.input).and_then(|map| {
                let carried = gainmap::Carried::of(&map.boost)?;
                Some(Self::Heif(map, carried))
            }),
            _ => None,
        }
    }
}

/// How the picture `request` renders codes its light, when it is PQ or HLG.
fn hdr_of(request: &Request) -> Option<hdr::Hdr> {
    let heif = matches!(request.mime.as_str(), "image/heic" | "image/avif");
    heif.then(|| heif::hdr(&request.input)).flatten()
}

/// `jpeg` with its `gain` map, which follows the picture's size and turn; one that does not decode is left out.
fn with_gain(gain: Option<&Gain>, jpeg: Vec<u8>, ratio: f64, orientation: i32, quality: u8) -> Vec<u8> {
    match gain {
        Some(map) => pair(map, &jpeg, ratio, orientation, quality).unwrap_or(jpeg),
        None => jpeg,
    }
}

/// `jpeg`, an upright rendition at `ratio` of the source's width, with `gain` behind it: scaled by the same ratio,
/// turned for `orientation` as the picture was (libheif has turned a HEIF's own), and encoded without metadata, which
/// `gainmap::attach` then writes again.
fn pair(gain: &Gain, jpeg: &[u8], ratio: f64, orientation: i32, quality: u8) -> Option<Vec<u8>> {
    let (map, carried, apple) = match gain {
        Gain::Jpeg(map) => {
            let image = VipsImage::jpegload_buffer(&map.image).ok()?.extract_band(0).ok()?;
            let scaled = orient(&image.resize(ratio.min(1.0)).ok()?, orientation).ok()?;
            (scaled, &map.carried, map.apple)
        }
        Gain::Heif(map, carried) => {
            let image = VipsImage::heifload_buffer(&map.heif).ok()?.extract_band(0).ok()?;
            (image.resize(ratio.min(1.0)).ok()?, carried, map.apple)
        }
    };
    let map = map.cast(BandFormat::Uchar).ok()?;
    let map = match apple {
        // Rec.709-coded, as Apple's formula wants it, to the linear gain every reader of Ultra HDR applies.
        Some(headroom) => {
            let lut = gainmap::apple_map(headroom);
            let pixels: Vec<u8> = map.write_to_memory().iter().map(|&p| lut[usize::from(p)]).collect();
            VipsImage::new_from_memory_copy(&pixels, map.get_width(), map.get_height(), 1, BandFormat::Uchar).ok()?
        }
        None => map,
    };
    let options = VOption::new()
        .set("Q", i32::from(quality))
        .set("keep", ForeignKeep::None as i32)
        .set("optimize-coding", true);
    let encoded = map.jpegsave_buffer_with_opts(options).ok()?;
    gainmap::attach(jpeg, carried, &encoded)
}

/// The pixels of `image` as 8-bit RGB, row by row, with transparency flattened onto white.
fn flat(image: &VipsImage) -> rs_vips::Result<Vec<u8>> {
    let white = [255.0];
    if image.hasalpha() {
        return Ok(image
            .flatten_with_opts(VOption::new().set("background", &white[..]))?
            .write_to_memory());
    }
    Ok(image.write_to_memory())
}

/// The size of `output` for an upright image of `size`.
fn fit((width, height): (u32, u32), output: &Output) -> (u32, u32) {
    let (short, long) = (width.min(height), width.max(height));
    let mut scale = f64::from(output.long) / f64::from(long);
    if output.short > 0 {
        scale = scale.min(f64::from(output.short) / f64::from(short));
    }
    let side = |n: u32| ((f64::from(n) * scale.min(1.0)).round() as u32).max(1);
    (side(width), side(height))
}

fn load(path: &Path, mime: &str, preview: Option<&[u8]>, shrink: i32) -> rs_vips::Result<VipsImage> {
    let path = path.to_string_lossy();
    // Read once, top to bottom, by the first resize: no copy of the whole decoded image.
    let shrunk = || {
        VOption::new()
            .set("shrink", shrink)
            .set("access", Access::Sequential as i32)
    };
    match (mime, preview) {
        (_, Some(jpeg)) => VipsImage::jpegload_buffer_with_opts(jpeg, shrunk()),
        ("image/jpeg", _) => VipsImage::jpegload_with_opts(&path, shrunk()),
        ("image/png" | "image/apng", _) => VipsImage::pngload(&path),
        ("image/webp", _) => VipsImage::webpload(&path),
        ("image/gif", _) => VipsImage::gifload(&path),
        ("image/tiff", _) => VipsImage::tiffload(&path),
        // libheif applies irot, imir and clap itself and libvips then drops the EXIF orientation.
        ("image/heic" | "image/avif", _) => VipsImage::heifload(&path),
        ("image/jxl", _) => VipsImage::jxlload(&path),
        _ => Err(rs_vips::error::Error::OperationError(format!("no loader for {mime}"))),
    }
}

/// The largest JPEG embedded in a RAW that libvips decodes: its preview (docs/08 §2.1). Lossless JPEG, the sensor
/// data of many RAWs, is no preview: libjpeg refuses its header.
fn largest_jpeg(file: &[u8]) -> Result<&[u8], Failure> {
    let mut found: Vec<(u64, usize)> = (0..file.len().saturating_sub(3))
        .filter(|&at| file[at..].starts_with(&[0xff, 0xd8, 0xff]))
        .filter_map(|at| {
            let probe = probe(&file[at..file.len().min(at + (1 << 16))], u64::MAX).ok()?;
            Some((u64::from(probe.width) * u64::from(probe.height), at))
        })
        .collect();
    found.sort_unstable_by_key(|&(pixels, _)| std::cmp::Reverse(pixels));
    let jpeg = (found.into_iter())
        .map(|(_, at)| &file[at..])
        .find(|jpeg| VipsImage::jpegload_buffer(jpeg).is_ok());
    Vips::error_clear();
    jpeg.ok_or_else(|| Failure::Unsupported("a RAW without a decodable embedded preview".into()))
}

/// Turns `image` upright for EXIF `orientation`, as libvips' autorot does.
fn orient(image: &VipsImage, orientation: i32) -> rs_vips::Result<VipsImage> {
    let mirror = |image: VipsImage| image.flip(Direction::Horizontal);
    match orientation {
        2 => mirror(image.copy()?),
        3 => image.rot(Angle::D180),
        4 => image.flip(Direction::Vertical),
        5 => mirror(image.rot(Angle::D90)?),
        6 => image.rot(Angle::D90),
        7 => mirror(image.rot(Angle::D270)?),
        8 => image.rot(Angle::D270),
        _ => Ok(image.clone()),
    }
}

/// 8-bit sRGB or, with `wide` and a source profile wider than sRGB, Display P3: true when its profile is to be kept.
fn colour(image: &VipsImage, wide: bool) -> rs_vips::Result<(VipsImage, bool)> {
    let profile = image.get_blob("icc-profile-data").ok();
    Vips::error_clear();
    let interpretation = image.get_interpretation();
    let cmyk = matches!(interpretation, Ok(Interpretation::Cmyk));
    if profile.is_none() && !cmyk {
        // A float TIFF runs from 0 to 1, where libvips' sRGB runs to 255 (scRGB aside).
        let image = match image.get_format()? {
            BandFormat::Float | BandFormat::Double if !matches!(interpretation, Ok(Interpretation::Scrgb)) => {
                image.linear(&[255.0], &[0.0])?
            }
            _ => image.clone(),
        };
        return Ok((image.colourspace(Interpretation::Srgb)?.cast(BandFormat::Uchar)?, false));
    }
    let p3 = wide && profile.as_deref().is_some_and(wide_gamut);
    let options = VOption::new()
        .set("embedded", true)
        .set("input-profile", if cmyk { "cmyk" } else { "srgb" })
        .set("depth", 8);
    Ok((
        image.icc_transform_with_opts(if p3 { "p3" } else { "srgb" }, options)?,
        p3,
    ))
}

/// Whether an ICC profile's red primary lies beyond sRGB's (X 0.436): Display P3 is at 0.515, Adobe RGB at 0.610.
fn wide_gamut(icc: &[u8]) -> bool {
    let be = |at: usize| icc.get(at..at + 4).map(|b| u32::from_be_bytes(b.try_into().unwrap()));
    let tags = be(128).unwrap_or(0).min(256) as usize;
    (0..tags).any(|n| {
        let at = 132 + 12 * n;
        icc.get(at..at + 4) == Some(b"rXYZ")
            && be(at + 4)
                .and_then(|data| be(data as usize + 8))
                .is_some_and(|x| x as i32 > 30_000)
    })
}

/// The ThumbHash of `image`, from at most 100 × 100 of its sRGB pixels, by the kernel's encoder (ADR-0070).
fn thumbhash(image: &VipsImage) -> Result<Vec<u8>, Failure> {
    let scale = (100.0 / f64::from(image.get_width().max(image.get_height()))).min(1.0);
    let small = colour(image, false)
        .and_then(|(c, _)| c.resize_with_opts(scale, VOption::new().set("vscale", scale)))
        .map_err(failed("hash"))?;
    let rgba = match small.get_bands() {
        3 => small.bandjoin_const(&[255.0]).map_err(failed("hash"))?,
        _ => small,
    };
    let request = EncodeThumbHashRequest {
        width: rgba.get_width() as u32,
        height: rgba.get_height() as u32,
        rgba: rgba.write_to_memory(),
    };
    let answer = photolib_kernel::call(Method::EncodeThumbHash as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).ok().and_then(|a| a.result) {
        Some(call_response::Result::Response(bytes)) => EncodeThumbHashResponse::decode(bytes.as_slice())
            .map(|r| r.hash)
            .map_err(|e| Failure::Unsupported(format!("cannot hash: {e}"))),
        other => Err(Failure::Unsupported(format!("cannot hash: {other:?}"))),
    }
}

fn failed(step: &'static str) -> impl Fn(rs_vips::error::Error) -> Failure {
    move |error| Failure::Unsupported(format!("cannot {step}: {error}"))
}

fn transient(error: impl std::fmt::Display) -> Failure {
    Failure::Transient(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 40×30 PNG whose pixel at (x, y) is (6x, 8y, 0), and a request to render it with `recipe` as a raw output.
    fn gradient(dir: &Path, recipe: &photolib_kernel::proto::model::v1::EditRecipe) -> Request {
        let pixels: Vec<u8> = (0..30u8)
            .flat_map(|y| (0..40u8).flat_map(move |x| [x * 6, y * 8, 0]))
            .collect();
        Vips::init("test").ok();
        VipsImage::new_from_memory_copy(&pixels, 40, 30, 3, BandFormat::Uchar)
            .and_then(|image| image.pngsave(&dir.join("g.png").to_string_lossy()))
            .unwrap();
        std::fs::write(dir.join("g.recipe"), recipe.encode_to_vec()).unwrap();
        Request {
            input: dir.join("g.png"),
            mime: "image/png".into(),
            orientation: None,
            edit: Some(dir.join("g.recipe")),
            outputs: vec![Output {
                file: "raw".into(),
                format: Format::Raw,
                short: 0,
                long: 1024,
                quality: 0,
                wide: false,
            }],
        }
    }

    fn step(
        id: &str,
        kind: photolib_kernel::proto::model::v1::operation::Kind,
    ) -> photolib_kernel::proto::model::v1::Operation {
        photolib_kernel::proto::model::v1::Operation {
            operation_id: id.into(),
            kind: Some(kind),
            ..Default::default()
        }
    }

    #[test]
    fn an_edit_is_applied_to_the_upright_picture_before_the_renditions_are_fitted() {
        use photolib_kernel::proto::model::v1::{
            AdjustOperation, CropOperation, EditRecipe, TurnOperation, operation::Kind,
        };
        let dir = tempfile::tempdir().unwrap();
        let recipe = EditRecipe {
            schema_version: 1,
            operations: vec![
                step(
                    "crop",
                    Kind::Crop(CropOperation {
                        x: 0.5,
                        y: 0.0,
                        width: 0.5,
                        height: 1.0,
                    }),
                ),
                step("turn", Kind::Turn(TurnOperation { quarter_turns: 1 })),
            ],
            ..Default::default()
        };
        let request = gradient(dir.path(), &recipe);
        let rendered = render(&request, dir.path(), &Limits::IMAGE).unwrap();
        // The right half is 20×30; turned a quarter clockwise, 30×20.
        assert_eq!(rendered.outputs, [(Format::Raw, 30, 20)]);
        let pixels = std::fs::read(dir.path().join("raw")).unwrap();
        assert_eq!(pixels.len(), 30 * 20 * 3);
        for (x, y) in [(0u8, 0u8), (29, 0), (0, 19), (29, 19), (7, 11)] {
            let at = (usize::from(y) * 30 + usize::from(x)) * 3;
            // The pixel (x, y) of the turned picture is (20 + y, 29 - x) of the original.
            assert_eq!(pixels[at..at + 3], [(20 + y) * 6, (29 - x) * 8, 0], "({x}, {y})");
        }

        // Adjustments change the colours, and the thumbhash is of the edited picture.
        let bright = EditRecipe {
            operations: vec![step(
                "light",
                Kind::Adjust(AdjustOperation {
                    exposure: 1.0,
                    ..Default::default()
                }),
            )],
            ..recipe
        };
        let request = gradient(dir.path(), &bright);
        let rendered = render(&request, dir.path(), &Limits::IMAGE).unwrap();
        assert_eq!(rendered.outputs, [(Format::Raw, 40, 30)]);
        let pixels = std::fs::read(dir.path().join("raw")).unwrap();
        assert!(
            pixels[(10 * 40 + 20) * 3] > 20 * 6,
            "brighter than the original's {}",
            20 * 6
        );
    }

    #[test]
    fn an_edit_that_is_no_recipe_or_does_not_fit_the_picture_fails_the_render() {
        use photolib_kernel::proto::model::v1::EditRecipe;
        let dir = tempfile::tempdir().unwrap();
        let mut request = gradient(
            dir.path(),
            &EditRecipe {
                schema_version: 1,
                ..Default::default()
            },
        );
        std::fs::write(dir.path().join("g.recipe"), [0xff, 0xff, 0xff]).unwrap();
        assert!(matches!(
            render(&request, dir.path(), &Limits::IMAGE),
            Err(Failure::Unsupported(_))
        ));
        request.edit = Some(dir.path().join("missing.recipe"));
        assert!(matches!(
            render(&request, dir.path(), &Limits::IMAGE),
            Err(Failure::Transient(_))
        ));
    }

    #[test]
    fn a_raw_output_is_the_upright_rgb_pixels_fitted_to_the_long_side() {
        let dir = tempfile::tempdir().unwrap();
        let request = |long| Request {
            input: Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../testdata/ocr/latin.png"),
            mime: "image/png".into(),
            orientation: None,
            edit: None,
            outputs: vec![Output {
                file: "ocr".into(),
                format: Format::Raw,
                short: 0,
                long,
                quality: 0,
                wide: false,
            }],
        };
        let mut sizes = vec![];
        for long in [1280, 400] {
            let rendered = render(&request(long), dir.path(), &Limits::IMAGE).unwrap();
            let (format, width, height) = rendered.outputs[0];
            let pixels = std::fs::read(dir.path().join("ocr")).unwrap();
            assert_eq!(pixels.len(), (width * height * 3) as usize);
            sizes.push((format, width, height));
            // The picture is white with black text: its corner is white, and some pixel is dark.
            assert_eq!(&pixels[..3], [255, 255, 255]);
            assert!(pixels.chunks(3).any(|p| p[0] < 64), "the text is in the pixels");
        }
        assert_eq!(sizes, [(Format::Raw, 800, 128), (Format::Raw, 400, 64)]);
    }
}
