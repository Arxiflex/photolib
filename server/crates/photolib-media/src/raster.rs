//! Formats libvips has no loader for (photolib-design docs/08 §2.1), decoded in the sandboxed renderer once their
//! header is within the pixel limit: BMP by the image crate, and the composite that a PSD or PSB document keeps
//! beside its layers, which are never rendered.

use image::{ImageDecoder, codecs::bmp::BmpDecoder};
use rs_vips::{
    VipsImage,
    enums::{
        BandFormat,
        Interpretation::{self, BW, Cmyk, Grey16, Rgb16, Srgb},
    },
    voption::{Setter, VOption},
};

use crate::Failure;

/// A BMP's pixels: palette, 16, 24 and 32-bit, bit fields, RLE, top-down or bottom-up.
pub(crate) fn bmp(file: &[u8], limit: u64) -> Result<VipsImage, Failure> {
    let decoder = BmpDecoder::new(std::io::Cursor::new(file)).map_err(damaged)?;
    let (width, height) = decoder.dimensions();
    within(width, height, limit)?;
    let bands = decoder.color_type().channel_count();
    let mut pixels = vec![0; usize::try_from(decoder.total_bytes()).map_err(damaged)?];
    decoder.read_image(&mut pixels).map_err(damaged)?;
    let interpretation = if bands < 3 { BW } else { Srgb };
    tagged(
        &plane(&pixels, width, height, bands, BandFormat::Uchar)?,
        interpretation,
    )
}

/// A PSD's or PSB's composite: bitmap, grey, duotone and multichannel (as grey), indexed, RGB or CMYK, at 1, 8, 16
/// or 32 bits, raw or RLE-coded, with its ICC profile; extra channels are ignored.
pub(crate) fn psd(file: &[u8], limit: u64) -> Result<VipsImage, Failure> {
    let mut psd = Reader(file);
    let psb = match (psd.take(4)?, psd.u16()?) {
        (b"8BPS", 1) => false,
        (b"8BPS", 2) => true,
        _ => return Err(damaged("no PSD signature")),
    };
    psd.take(6)?;
    let (channels, height, width, depth, mode) = (psd.u16()?, psd.u32()?, psd.u32()?, psd.u16()?, psd.u16()?);
    within(width, height, limit)?;
    let length = psd.u32()?;
    let palette = psd.take(length)?;
    let length = psd.u32()?;
    let icc = profile(Reader(psd.take(length)?));
    let length = if psb { psd.u64()? } else { psd.u32()?.into() };
    psd.take(length)?;
    let (bands, interpretation, format) = match (mode, depth) {
        (0, 1) | (1 | 7 | 8, 8) => (1, BW, BandFormat::Uchar),
        (1 | 7 | 8, 16) => (1, Grey16, BandFormat::Ushort),
        (1 | 7 | 8, 32) => (1, BW, BandFormat::Float),
        (2, 8) => (1, Srgb, BandFormat::Uchar),
        (3, 8) => (3, Srgb, BandFormat::Uchar),
        (3, 16) => (3, Rgb16, BandFormat::Ushort),
        (3, 32) => (3, Srgb, BandFormat::Float),
        (4, 8) => (4, Cmyk, BandFormat::Uchar),
        (4, 16) => (4, Cmyk, BandFormat::Ushort),
        _ => {
            return Err(Failure::Unsupported(format!(
                "a PSD in colour mode {mode} at {depth} bits"
            )));
        }
    };
    if channels < bands {
        return Err(damaged("fewer channels than its colour mode"));
    }
    let row = match depth {
        1 => width.div_ceil(8),
        _ => width
            .checked_mul((depth / 8).into())
            .ok_or_else(|| damaged("too wide"))?,
    };
    let row = usize::try_from(row).map_err(damaged)?;
    let mut planes = stored(&mut psd, psb, (channels, height, bands), row)?;
    for plane in &mut planes {
        if mode == 4 {
            // CMYK is stored inverted: 0 is full ink.
            for b in plane.iter_mut() {
                *b = !*b;
            }
        }
        *plane = samples(plane, depth, row, width);
    }
    let planes = match mode {
        2 => indexed(planes.first().map_or(&[][..], Vec::as_slice), palette)?,
        _ => planes,
    };
    let planes: Vec<_> = (planes.iter())
        .map(|p| plane(p, width, height, 1, format))
        .collect::<Result<_, _>>()?;
    let mut image = tagged(&VipsImage::bandjoin(&planes).map_err(damaged)?, interpretation)?;
    if let Some(icc) = icc {
        image.set_blob_copy("icc-profile-data", icc).map_err(damaged)?;
    }
    Ok(image)
}

/// The stored planes of the first `bands` of `channels`, `height` rows of `row` bytes each, raw or RLE-coded (with
/// the lengths of every row of every channel first).
fn stored(
    psd: &mut Reader<'_>,
    psb: bool,
    (channels, height, bands): (u16, u32, u16),
    row: usize,
) -> Result<Vec<Vec<u8>>, Failure> {
    let mut lengths = match psd.u16()? {
        0 => None,
        1 => {
            let size: u8 = if psb { 4 } else { 2 };
            let rows = u64::from(channels)
                .saturating_mul(height.into())
                .saturating_mul(size.into());
            let lengths = psd.take(rows)?.chunks_exact(size.into());
            Some(lengths.map(|n| n.iter().fold(0u64, |n, &b| n.wrapping_mul(256).wrapping_add(b.into()))))
        }
        _ => return Err(Failure::Unsupported("a ZIP-coded PSD composite".into())),
    };
    (0..bands)
        .map(|_| {
            let mut stored = vec![];
            for _ in 0..height {
                match lengths.as_mut() {
                    None => stored.extend_from_slice(psd.take(row)?),
                    Some(lengths) => {
                        let length = lengths.next().ok_or_else(|| damaged("too few row lengths"))?;
                        unpack(psd.take(length)?, row, &mut stored)?;
                    }
                }
            }
            Ok(stored)
        })
        .collect()
}

/// A stored plane in the machine's byte order: 1-bit (1 is black) as 8-bit, 16-bit and float samples as they are.
fn samples(stored: &[u8], depth: u16, row: usize, width: u32) -> Vec<u8> {
    let bits = |b: u8| (0..8).map(move |i| if b & 0x80u8.wrapping_shr(i) == 0 { 255 } else { 0 });
    let width = usize::try_from(width).unwrap_or(usize::MAX);
    match depth {
        1 => (stored.chunks(row.max(1)))
            .flat_map(|r| r.iter().flat_map(|&b| bits(b)).take(width))
            .collect(),
        16 => (stored.as_chunks().0.iter())
            .flat_map(|&s| u16::from_be_bytes(s).to_ne_bytes())
            .collect(),
        32 => (stored.as_chunks().0.iter())
            .flat_map(|&s| f32::from_be_bytes(s).to_ne_bytes())
            .collect(),
        _ => stored.to_vec(),
    }
}

/// An indexed plane as red, green and blue planes, through the 256-entry palette of the colour mode data.
fn indexed(plane: &[u8], palette: &[u8]) -> Result<Vec<Vec<u8>>, Failure> {
    let (red, rest) = palette.split_at_checked(256).ok_or_else(|| damaged("no palette"))?;
    let (green, blue) = rest.split_at_checked(256).ok_or_else(|| damaged("no palette"))?;
    let map = |colours: &[u8]| {
        (plane.iter())
            .map(|&i| colours.get(usize::from(i)).copied().unwrap_or(0))
            .collect()
    };
    Ok(vec![map(red), map(green), map(blue)])
}

/// Appends a PackBits-coded row of `row` bytes to `plane`.
fn unpack(mut code: &[u8], row: usize, plane: &mut Vec<u8>) -> Result<(), Failure> {
    let end = plane.len().saturating_add(row);
    while plane.len() < end {
        let (&n, rest) = code.split_first().ok_or_else(|| damaged("a short RLE row"))?;
        code = rest;
        match n {
            0..=127 => {
                let (literal, rest) = (code.split_at_checked(usize::from(n).saturating_add(1)))
                    .ok_or_else(|| damaged("a short RLE row"))?;
                plane.extend_from_slice(literal);
                code = rest;
            }
            128 => {}
            _ => {
                let (&byte, rest) = code.split_first().ok_or_else(|| damaged("a short RLE row"))?;
                plane.extend(std::iter::repeat_n(
                    byte,
                    usize::from(n.wrapping_neg()).saturating_add(1),
                ));
                code = rest;
            }
        }
    }
    plane.truncate(end);
    Ok(())
}

/// The ICC profile among the image resources: 8BIM blocks of an id, a padded Pascal name and padded data.
fn profile(mut resources: Reader<'_>) -> Option<&[u8]> {
    loop {
        if resources.take(4).ok()? != b"8BIM" {
            return None;
        }
        let id = resources.u16().ok()?;
        let name = resources.take(1).ok()?.first().copied()?;
        resources.take(name | 1).ok()?;
        let size = resources.u32().ok()?;
        let data = resources.take(size).ok()?;
        if id == 1039 {
            return Some(data);
        }
        let _padding = resources.take(size % 2);
    }
}

/// Bytes read from the front.
struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    fn take(&mut self, n: impl TryInto<usize>) -> Result<&'a [u8], Failure> {
        let n = n.try_into().map_err(|_| damaged("too long"))?;
        let (taken, rest) = self.0.split_at_checked(n).ok_or_else(|| damaged("too short"))?;
        self.0 = rest;
        Ok(taken)
    }

    fn array<const N: usize>(&mut self) -> Result<[u8; N], Failure> {
        self.take(N)?.try_into().map_err(damaged)
    }

    fn u16(&mut self) -> Result<u16, Failure> {
        self.array().map(u16::from_be_bytes)
    }

    fn u32(&mut self) -> Result<u32, Failure> {
        self.array().map(u32::from_be_bytes)
    }

    fn u64(&mut self) -> Result<u64, Failure> {
        self.array().map(u64::from_be_bytes)
    }
}

fn within(width: u32, height: u32, limit: u64) -> Result<(), Failure> {
    match u64::from(width).saturating_mul(height.into()) {
        0 => Err(damaged("no pixels")),
        pixels if pixels > limit => Err(Failure::LimitExceeded(format!(
            "{width}×{height} is more than {limit} pixels"
        ))),
        _ => Ok(()),
    }
}

fn plane(samples: &[u8], width: u32, height: u32, bands: u8, format: BandFormat) -> Result<VipsImage, Failure> {
    let side = |n: u32| i32::try_from(n).map_err(damaged);
    VipsImage::new_from_memory_copy(samples, side(width)?, side(height)?, bands.into(), format).map_err(damaged)
}

fn tagged(image: &VipsImage, interpretation: Interpretation) -> Result<VipsImage, Failure> {
    let options = VOption::new().set("interpretation", interpretation as i32);
    image.copy_with_opts(options).map_err(damaged)
}

fn damaged(error: impl std::fmt::Display) -> Failure {
    Failure::Unsupported(format!("cannot decode: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn started() {
        static STARTED: std::sync::Once = std::sync::Once::new();
        STARTED.call_once(|| rs_vips::Vips::init("test").unwrap());
    }

    /// A PSD (PSB when `psb`) of `planes`, each `width` × rows, raw or RLE-coded, with a resource block.
    fn document(psb: bool, mode: u16, depth: u16, width: u32, planes: &[&[u8]], rle: bool, colours: &[u8]) -> Vec<u8> {
        let row = if depth == 1 {
            width.div_ceil(8)
        } else {
            width * u32::from(depth / 8)
        } as usize;
        let height = planes[0].len() / row;
        let mut out = b"8BPS".to_vec();
        out.extend(if psb { [0, 2] } else { [0, 1] });
        out.extend([0; 6]);
        out.extend((planes.len() as u16).to_be_bytes());
        out.extend((height as u32).to_be_bytes());
        out.extend(width.to_be_bytes());
        out.extend(depth.to_be_bytes());
        out.extend(mode.to_be_bytes());
        out.extend((colours.len() as u32).to_be_bytes());
        out.extend(colours);
        let icc = b"a profile";
        let resources = [
            &b"8BIM\x04\x24\0\0\0\0\0\x03xmp\0"[..],
            b"8BIM\x04\x0f\x02ab\0\0\0\0\x09",
            icc,
            b"\0",
        ]
        .concat();
        out.extend((resources.len() as u32).to_be_bytes());
        out.extend(resources);
        out.extend(if psb { &[0; 8][..] } else { &[0; 4] });
        out.extend(u16::from(rle).to_be_bytes());
        let rows: Vec<&[u8]> = planes.iter().flat_map(|p| p.chunks(row)).collect();
        if !rle {
            out.extend(rows.concat());
            return out;
        }
        // Equal bytes as a run after a no-op, else one literal.
        let coded: Vec<Vec<u8>> = (rows.iter())
            .map(|r| {
                if r.len() > 1 && r.iter().all(|&b| b == r[0]) {
                    vec![128, (257 - r.len()) as u8, r[0]]
                } else {
                    [&[(r.len() - 1) as u8][..], r].concat()
                }
            })
            .collect();
        for c in &coded {
            let length = (c.len() as u32).to_be_bytes();
            out.extend(if psb { &length[..] } else { &length[2..] });
        }
        out.extend(coded.concat());
        out
    }

    fn pixels(image: &VipsImage) -> (i32, Interpretation, Vec<u8>) {
        (
            image.get_bands(),
            image.get_interpretation().unwrap(),
            image.write_to_memory(),
        )
    }

    #[test]
    fn rgb_composites_decode_raw_and_rle_in_psd_and_psb_without_their_extra_channels() {
        started();
        let (red, green, blue, alpha) = ([1, 2, 3, 4, 5, 6], [7, 7, 7, 7, 7, 7], [9; 6], [0; 6]);
        let want = vec![1, 7, 9, 2, 7, 9, 3, 7, 9, 4, 7, 9, 5, 7, 9, 6, 7, 9];
        for (psb, rle) in [(false, false), (false, true), (true, true)] {
            let file = document(psb, 3, 8, 3, &[&red, &green, &blue, &alpha], rle, &[]);
            let image = psd(&file, 100).unwrap();
            assert_eq!(pixels(&image), (3, Srgb, want.clone()), "psb {psb}, rle {rle}");
            assert_eq!(image.get_blob("icc-profile-data").unwrap(), b"a profile");
        }
    }

    #[test]
    fn cmyk_grey_bitmap_and_indexed_composites_decode() {
        started();
        let cmyk = psd(
            &document(false, 4, 8, 2, &[&[255, 0], &[0, 0], &[255, 255], &[1, 2]], true, &[]),
            100,
        );
        assert_eq!(
            pixels(&cmyk.unwrap()),
            (4, Cmyk, vec![0, 255, 0, 254, 255, 255, 0, 253])
        );
        let grey = psd(&document(false, 1, 16, 2, &[&[1, 2, 255, 255]], false, &[]), 100).unwrap();
        let want: Vec<u8> = [0x0102u16, 0xffff].iter().flat_map(|v| v.to_ne_bytes()).collect();
        assert_eq!(pixels(&grey), (1, Grey16, want));
        let float = psd(&document(false, 1, 32, 1, &[&0.5f32.to_be_bytes()], false, &[]), 100).unwrap();
        assert_eq!(pixels(&float).2, 0.5f32.to_ne_bytes());
        let bitmap = psd(
            &document(false, 0, 1, 10, &[&[0b1010_0000, 0b0100_0000]], true, &[]),
            100,
        )
        .unwrap();
        assert_eq!(pixels(&bitmap).2, [0, 255, 0, 255, 255, 255, 255, 255, 255, 0]);
        let palette: Vec<u8> = (0..768u32).map(|i| (i / 256 * 100 + i % 256) as u8).collect();
        let indexed = psd(&document(false, 2, 8, 2, &[&[0, 5]], false, &palette), 100).unwrap();
        assert_eq!(pixels(&indexed), (3, Srgb, vec![0, 100, 200, 5, 105, 205]));
    }

    #[test]
    fn bombs_lab_and_damage_are_refused_never_panicking() {
        started();
        let file = document(false, 3, 8, 3, &[&[1; 6], &[2; 6], &[3; 6]], true, &[]);
        assert!(matches!(psd(&file, 5), Err(Failure::LimitExceeded(_))));
        let mut lab = file.clone();
        lab[25] = 9;
        assert!(matches!(psd(&lab, 100), Err(Failure::Unsupported(e)) if e.contains("mode 9")));
        for end in 0..file.len() {
            assert!(psd(&file[..end], 100).is_err(), "{end} bytes");
        }
        for at in 0..file.len() {
            for byte in [0, 0x7f, 0xff] {
                let mut damaged = file.clone();
                damaged[at] = byte;
                let _ = psd(&damaged, 1000);
            }
        }
    }

    #[test]
    fn bmps_decode_within_the_limit() {
        started();
        let corpus = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../testdata/corpus/files/stills/24bit.bmp"
        );
        let file = std::fs::read(corpus).unwrap();
        let image = bmp(&file, 1 << 20).unwrap();
        assert_eq!(
            (image.get_width(), image.get_height(), image.get_bands()),
            (160, 120, 3)
        );
        assert!(matches!(bmp(&file, 100), Err(Failure::LimitExceeded(_))));
    }
}
