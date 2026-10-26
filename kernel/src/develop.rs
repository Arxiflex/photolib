//! The CPU reference renderer of the editor rendering spike (roadmap M0-36, ADR-0054): the definition of each
//! adjustment, which the GPU path (app/packages/photolib_editor/shaders) must match within the spike's tolerances.
//! Only f32 arithmetic in a fixed order and libm, so that native and WebAssembly builds agree bit for bit.
//!
//! Per pixel, in linear sRGB: white balance and exposure, clarity against the guide, saturation; then, sRGB-encoded,
//! the contrast curve and the LUT. Geometry (quarter turns, mirror, crop) moves pixels first, without resampling.

use crate::error;
use crate::proto::kernel::v1::{
    CallError, CallErrorCode::InvalidRequest, Develop, DevelopRequest, DevelopResponse, GainMap, Guide, Image, Lut,
    Rect,
};
use libm::{exp2f, log2f, powf};

/// The guide's cells on the image's long side, taps per cell side, and its blur: a Gaussian of σ = 1.5 cells.
const CELLS: u32 = 64;
const TAPS: u32 = 8;
const BLUR: [f32; 5] = [0.26656, 0.2134445, 0.1095861, 0.036075, 0.0076144];
const DARKEST: f32 = -12.0;
const LUMA: [f32; 3] = [0.2126, 0.7152, 0.0722];

type Rgb = [f32; 3];

pub fn develop(request: DevelopRequest) -> Result<DevelopResponse, CallError> {
    let develop = request.develop.unwrap_or_default();
    let tonal = [
        develop.temperature,
        develop.tint,
        develop.exposure,
        develop.contrast,
        develop.clarity,
        develop.saturation,
    ];
    if tonal.iter().any(|v| !v.is_finite()) {
        return invalid("develop");
    }
    let params = Params {
        gains: [
            exp2f(0.5 * develop.temperature + develop.exposure),
            exp2f(-0.5 * develop.tint + develop.exposure),
            exp2f(-0.5 * develop.temperature + develop.exposure),
        ],
        contrast: develop.contrast,
        clarity: develop.clarity,
        saturation: develop.saturation,
        lut: develop.lut.as_ref().map(lut).transpose()?,
    };
    let image = request.image.filter(sized).map_or(invalid("image"), Ok)?;
    let map = request.gain_map.map(hdr).transpose()?;
    let (image, map) = geometry(&develop, image, map)?;
    let lin: [f32; 256] = std::array::from_fn(|v| decode(v as f32 / 255.0));

    let computed = request.guide.is_none();
    let (guide, full, origin) = match request.guide {
        None => (guide(&image, &lin), (image.width, image.height), (0, 0)),
        Some(guide) => {
            if guide.width == 0
                || guide.log2_luminance.len() as u64 != u64::from(guide.width) * u64::from(guide.height)
                || !fits(request.tile_x, image.width, request.full_width)
                || !fits(request.tile_y, image.height, request.full_height)
            {
                return invalid("guide");
            }
            let full = (request.full_width, request.full_height);
            (guide, full, (request.tile_x, request.tile_y))
        }
    };

    let (w, h) = (image.width, image.height);
    let mut rgba = Vec::with_capacity(image.rgba.len());
    let mut map = map;
    for y in 0..h {
        for x in 0..w {
            let at = ((y * w + x) * 4) as usize;
            let c: Rgb = std::array::from_fn(|i| lin[usize::from(image.rgba[at + i])]);
            let detail =
                log_luminance(c) - sample(&guide, (origin.0 + x) as f32 + 0.5, (origin.1 + y) as f32 + 0.5, full);
            let factor = exp2f(params.clarity * detail / (1.0 + detail.abs()));
            let sdr = scene(c, factor, &params).map(|v| v.clamp(0.0, 1.0));
            let display = params.display(sdr.map(encode));
            let out = display.map(|v| (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8);
            rgba.extend(out);
            rgba.push(255);
            if let Some(map) = &mut map {
                // The HDR rendition gets the scene adjustments and the ratio by which display ones changed the SDR.
                let hdr = scene(map.hdr(c, x, y), factor, &params);
                let block = &mut map.sums[((y / map.scale) * map.map.width + x / map.scale) as usize];
                for i in 0..3 {
                    let ratio = (decode(display[i]) + map.meta.offset_sdr) / (sdr[i] + map.meta.offset_sdr);
                    block[i] += hdr[i].max(0.0) * ratio + map.meta.offset_hdr;
                    block[3 + i] += lin[usize::from(out[i])] + map.meta.offset_sdr;
                }
            }
        }
    }
    let neutral = tonal.iter().all(|&v| v == 0.0) && develop.lut.is_none();
    let gain_map = map.map(|map| if neutral { map.into_gain_map() } else { map.recompute() });
    Ok(DevelopResponse {
        image: Some(Image {
            width: w,
            height: h,
            rgba,
        }),
        gain_map,
        guide: computed.then_some(guide),
    })
}

struct Params {
    gains: Rgb,
    contrast: f32,
    clarity: f32,
    saturation: f32,
    /// The LUT's size and its entries.
    lut: Option<(usize, Vec<f32>)>,
}

impl Params {
    /// The adjustments made to sRGB-encoded values in [0, 1].
    fn display(&self, v: Rgb) -> Rgb {
        let v = v.map(|v| v + self.contrast * (v * v * (3.0 - 2.0 * v) - v));
        let Some((n, lut)) = &self.lut else { return v };
        let cell = |v: f32| {
            let p = v.clamp(0.0, 1.0) * (*n - 1) as f32;
            let i = (p.floor() as usize).min(n - 2);
            (i, p - i as f32)
        };
        let [(r, fr), (g, fg), (b, fb)] = v.map(cell);
        let at = |r: usize, g: usize, b: usize, c: usize| lut[((b * n + g) * n + r) * 3 + c];
        std::array::from_fn(|c| {
            let plane = |b| {
                let row = |g| lerp(at(r, g, b, c), at(r + 1, g, b, c), fr);
                lerp(row(g), row(g + 1), fg)
            };
            lerp(plane(b), plane(b + 1), fb)
        })
    }
}

/// White balance, exposure and clarity's factor, then saturation, in linear light.
fn scene(c: Rgb, factor: f32, params: &Params) -> Rgb {
    let c: Rgb = std::array::from_fn(|i| c[i] * params.gains[i] * factor);
    let y = luminance(c);
    c.map(|v| y + (v - y) * (1.0 + params.saturation))
}

fn luminance(c: Rgb) -> f32 {
    LUMA[0] * c[0] + LUMA[1] * c[1] + LUMA[2] * c[2]
}

fn log_luminance(c: Rgb) -> f32 {
    log2f(luminance(c)).max(DARKEST)
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// The sRGB transfer function and its inverse, on [0, 1].
fn encode(l: f32) -> f32 {
    if l <= 0.003_130_8 {
        12.92 * l
    } else {
        1.055 * powf(l, 1.0 / 2.4) - 0.055
    }
}

fn decode(v: f32) -> f32 {
    if v <= 0.040_45 {
        v / 12.92
    } else {
        powf((v + 0.055) / 1.055, 2.4)
    }
}

fn invalid<T>(field: &str) -> Result<T, CallError> {
    Err(error(InvalidRequest, &[("field", field)]))
}

/// Whether `size` from `at` stays within `full`.
fn fits(at: u32, size: u32, full: u32) -> bool {
    u64::from(at) + u64::from(size) <= u64::from(full)
}

pub(crate) fn sized(image: &Image) -> bool {
    image.width > 0
        && image.height > 0
        && image.rgba.len() as u64 == u64::from(image.width) * u64::from(image.height) * 4
}

fn lut(lut: &Lut) -> Result<(usize, Vec<f32>), CallError> {
    let n = lut.size as usize;
    if !(2..=256).contains(&n) || lut.rgb16.len() != n * n * n * 6 {
        return invalid("lut");
    }
    let entries = lut.rgb16.chunks(2);
    Ok((
        n,
        entries
            .map(|v| f32::from(u16::from_le_bytes([v[0], v[1]])) / 65535.0)
            .collect(),
    ))
}

/// The guide of an image: the mean log2 luminance of `TAPS`² pixels in each cell, blurred.
fn guide(image: &Image, lin: &[f32; 256]) -> Guide {
    let n = CELLS.min(image.width.max(image.height));
    let short = |s: u32, l: u32| ((u64::from(n) * u64::from(s) + u64::from(l / 2)) / u64::from(l)).max(1) as u32;
    let (gw, gh) = if image.width >= image.height {
        (n, short(image.height, image.width))
    } else {
        (short(image.width, image.height), n)
    };
    let tap = |cell: u32, t: u32, size: u32, cells: u32| {
        let at = (cell as f32 + (t as f32 + 0.5) / TAPS as f32) * size as f32 / cells as f32;
        (at as u32).min(size - 1)
    };
    let mut cells = Vec::with_capacity((gw * gh) as usize);
    for j in 0..gh {
        for i in 0..gw {
            let mut sum = 0.0;
            for b in 0..TAPS {
                let y = tap(j, b, image.height, gh);
                for a in 0..TAPS {
                    let at = ((y * image.width + tap(i, a, image.width, gw)) * 4) as usize;
                    sum += log_luminance(std::array::from_fn(|c| lin[usize::from(image.rgba[at + c])]));
                }
            }
            cells.push(sum / (TAPS * TAPS) as f32);
        }
    }
    let blur = |cells: &[f32], (dx, dy): (i64, i64)| -> Vec<f32> {
        let at = |x: i64, y: i64| {
            cells[(y.clamp(0, i64::from(gh) - 1) * i64::from(gw) + x.clamp(0, i64::from(gw) - 1)) as usize]
        };
        (0..i64::from(gh))
            .flat_map(|y| (0..i64::from(gw)).map(move |x| (x, y)))
            .map(|(x, y)| {
                let mut sum = BLUR[0] * at(x, y);
                for k in 1..5 {
                    sum += BLUR[k as usize] * (at(x - k * dx, y - k * dy) + at(x + k * dx, y + k * dy));
                }
                sum
            })
            .collect()
    };
    Guide {
        width: gw,
        height: gh,
        log2_luminance: blur(&blur(&cells, (1, 0)), (0, 1)),
    }
}

/// The guide at a pixel centre (`x`, `y`) of an image of size `full`, interpolated bilinearly between cell centres.
fn sample(guide: &Guide, x: f32, y: f32, full: (u32, u32)) -> f32 {
    let (gw, gh) = (guide.width, guide.log2_luminance.len() as u32 / guide.width);
    let u = x * gw as f32 / full.0 as f32 - 0.5;
    let v = y * gh as f32 / full.1 as f32 - 0.5;
    let (i, j) = (u.floor(), v.floor());
    let at = |i: f32, j: f32| {
        let (i, j) = ((i.max(0.0) as u32).min(gw - 1), (j.max(0.0) as u32).min(gh - 1));
        guide.log2_luminance[(j * gw + i) as usize]
    };
    let row = |j| lerp(at(i, j), at(i + 1.0, j), u - i);
    lerp(row(j), row(j + 1.0), v - j)
}

/// A gain map checked against its image, with the size of the block each of its pixels covers and, per block, the
/// sums of the edited HDR and SDR light with their offsets.
struct Hdr {
    map: Image,
    meta: GainMap,
    scale: u32,
    sums: Vec<[f32; 6]>,
}

fn hdr(mut meta: GainMap) -> Result<Hdr, CallError> {
    let map = meta.image.take().filter(sized).map_or(invalid("gain_map"), Ok)?;
    let floats = [meta.min_log2, meta.max_log2, meta.offset_sdr, meta.offset_hdr];
    if floats.iter().any(|v| !v.is_finite()) || !(meta.gamma > 0.0 && meta.gamma.is_finite()) {
        return invalid("gain_map");
    }
    Ok(Hdr {
        sums: vec![[0.0; 6]; map.rgba.len() / 4],
        map,
        meta,
        scale: 0,
    })
}

impl Hdr {
    /// The HDR rendition of the SDR pixel `c` at (`x`, `y`).
    fn hdr(&self, c: Rgb, x: u32, y: u32) -> Rgb {
        let at = (((y / self.scale) * self.map.width + x / self.scale) * 4) as usize;
        let meta = &self.meta;
        std::array::from_fn(|i| {
            let recovery = powf(f32::from(self.map.rgba[at + i]) / 255.0, 1.0 / meta.gamma);
            let boost = meta.min_log2 + (meta.max_log2 - meta.min_log2) * recovery;
            (c[i] + meta.offset_sdr) * exp2f(boost) - meta.offset_hdr
        })
    }

    /// A new map from each block's sums, spanning the new headroom.
    fn recompute(self) -> GainMap {
        let ratios: Vec<Rgb> = self
            .sums
            .iter()
            .map(|s| std::array::from_fn(|i| log2f(s[i] / s[3 + i])))
            .collect();
        let all = ratios.iter().flatten();
        let min = all.clone().fold(0.0f32, |a, &b| a.min(b));
        let max = all.fold(min, |a, &b| a.max(b));
        let rgba = ratios
            .iter()
            .flat_map(|r| {
                let m = r.map(|r| {
                    let t = if max > min { (r - min) / (max - min) } else { 0.0 };
                    (powf(t, self.meta.gamma) * 255.0 + 0.5) as u8
                });
                [m[0], m[1], m[2], 255]
            })
            .collect();
        GainMap {
            image: Some(Image { rgba, ..self.map }),
            min_log2: min,
            max_log2: max,
            hdr_capacity_max: max,
            ..self.meta
        }
    }

    fn into_gain_map(self) -> GainMap {
        GainMap {
            image: Some(self.map),
            ..self.meta
        }
    }
}

/// Moves the pixels of `image` as the geometry of `develop` says (turns, mirror, crop) and changes none.
pub(crate) fn rearrange(develop: &Develop, image: Image) -> Result<Image, CallError> {
    geometry(develop, image, None).map(|(image, _)| image)
}

/// Turns the image and its gain map clockwise by quarter turns, mirrors them if asked, then crops both.
fn geometry(develop: &Develop, image: Image, map: Option<Hdr>) -> Result<(Image, Option<Hdr>), CallError> {
    let place = |image| mirror(turn(image, develop.quarter_turns), develop.flip);
    let image = place(image);
    let (w, h) = (image.width, image.height);
    let map = match map {
        Some(mut hdr) => {
            hdr.map = place(hdr.map);
            let scale = w / hdr.map.width;
            if scale == 0 || hdr.map.width * scale != w || hdr.map.height * scale != h {
                return invalid("gain_map");
            }
            hdr.scale = scale;
            Some(hdr)
        }
        None => None,
    };
    let crop = develop.crop.filter(|c| c.width > 0 && c.height > 0);
    let Some(crop) = crop else {
        return Ok((image, map));
    };
    let aligned = map.as_ref().is_none_or(|m| {
        [crop.x, crop.y, crop.width, crop.height]
            .iter()
            .all(|v| v % m.scale == 0)
    });
    if !fits(crop.x, crop.width, w) || !fits(crop.y, crop.height, h) || !aligned {
        return invalid("crop");
    }
    let map = map.map(|mut hdr| {
        let s = hdr.scale;
        let scaled = Rect {
            x: crop.x / s,
            y: crop.y / s,
            width: crop.width / s,
            height: crop.height / s,
        };
        hdr.map = cut(&hdr.map, scaled);
        hdr
    });
    Ok((cut(&image, crop), map))
}

fn turn(image: Image, quarter_turns: u32) -> Image {
    let (w, h) = (image.width, image.height);
    let turns = quarter_turns % 4;
    if turns == 0 {
        return image;
    }
    let (nw, nh) = if turns % 2 == 1 { (h, w) } else { (w, h) };
    let mut rgba = Vec::with_capacity(image.rgba.len());
    for y in 0..nh {
        for x in 0..nw {
            let (sx, sy) = match turns {
                1 => (y, h - 1 - x),
                2 => (w - 1 - x, h - 1 - y),
                _ => (w - 1 - y, x),
            };
            let at = ((sy * w + sx) * 4) as usize;
            rgba.extend_from_slice(&image.rgba[at..at + 4]);
        }
    }
    Image {
        width: nw,
        height: nh,
        rgba,
    }
}

fn mirror(mut image: Image, flip: bool) -> Image {
    if flip {
        for row in image.rgba.chunks_mut(image.width as usize * 4) {
            row.reverse();
            row.chunks_mut(4).for_each(<[u8]>::reverse);
        }
    }
    image
}

fn cut(image: &Image, rect: Rect) -> Image {
    let row = (rect.width * 4) as usize;
    let rgba = (rect.y..rect.y + rect.height)
        .flat_map(|y| {
            let at = ((y * image.width + rect.x) * 4) as usize;
            image.rgba[at..at + row].iter().copied()
        })
        .collect();
    Image {
        width: rect.width,
        height: rect.height,
        rgba,
    }
}
