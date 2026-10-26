//! HDR stills as SDR (photolib-design docs/08 §5.6, ADR-0390): a PQ or HLG picture shown as its own code values is
//! washed out and dark; renditions show it as the video renditions show a frame of HDR, in linear light with 203 nits
//! as 1.0, into BT.709, through Mobius's curve, which keeps a pixel's hue.

use rs_vips::{
    VipsImage,
    enums::{BandFormat, Interpretation},
    voption::{Setter, VOption},
};

/// How an HDR picture's light is coded.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transfer {
    /// SMPTE ST 2084.
    Pq,
    /// ARIB STD-B67.
    Hlg,
}

/// An HDR picture's coding: the transfer, and whether its primaries are the wide ones (BT.2020) or P3's, else BT.709's.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hdr {
    /// How its light is coded.
    pub transfer: Transfer,
    /// Which colours its red, green and blue are.
    pub primaries: Primaries,
}

/// The colours of a picture's red, green and blue.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Primaries {
    /// sRGB's.
    Bt709,
    /// Display P3's.
    P3,
    /// The wide gamut of HDR video.
    Bt2020,
}

impl Hdr {
    /// From a HEIF `colr` box's nclx fields: ITU-T H.273's codes of the primaries and the transfer. None for SDR.
    pub fn from_codes(primaries: u16, transfer: u16) -> Option<Self> {
        let transfer = match transfer {
            16 => Transfer::Pq,
            18 => Transfer::Hlg,
            _ => return None,
        };
        let primaries = match primaries {
            1 => Primaries::Bt709,
            11 | 12 => Primaries::P3,
            // 9, and what a file leaves unsaid: HDR is BT.2020.
            _ => Primaries::Bt2020,
        };
        Some(Self { transfer, primaries })
    }
}

/// The nits of reference white (BT.2408).
const WHITE: f64 = 203.0;
/// The curve's knee: where Mobius stops being the identity.
const KNEE: f64 = 0.3;

/// The linear light, in units of reference white, of a coded value (0 to 1): PQ's absolute, HLG's the scene light that
/// the display's system gamma of 1.2 is then applied to, for a display of 1,000 nits, by the caller.
fn linear(transfer: Transfer, coded: f64) -> f64 {
    match transfer {
        Transfer::Pq => {
            let (m1, m2) = (2610.0 / 16384.0, 2523.0 / 4096.0 * 128.0);
            let (c1, c2, c3): (f64, f64, f64) = (3424.0 / 4096.0, 2413.0 / 4096.0 * 32.0, 2392.0 / 4096.0 * 32.0);
            let p = coded.powf(1.0 / m2);
            10_000.0 * ((p - c1).max(0.0) / c3.mul_add(-p, c2)).powf(1.0 / m1) / WHITE
        }
        Transfer::Hlg => {
            let (a, c): (f64, f64) = (0.178_832_77, 0.559_910_73);
            let b = 4.0f64.mul_add(-a, 1.0);
            // The inverse OETF: scene light, 0 to 1.
            if coded <= 0.5 {
                coded * coded / 3.0
            } else {
                (((coded - c) / a).exp() + b) / 12.0
            }
        }
    }
}

/// Ffmpeg's `tonemap=mobius` for `sig` with the signal peak `peak` (both in units of reference white).
fn mobius(sig: f64, peak: f64) -> f64 {
    let j = KNEE;
    if sig <= j || peak <= 1.0 {
        return sig.min(peak.max(1.0));
    }
    let a = -j * j * (peak - 1.0) / j.mul_add(j, (-2.0f64).mul_add(j, peak));
    let b = j.mul_add(j, (-2.0 * j).mul_add(peak, peak)) / (peak - 1.0).max(1e-6);
    b.mul_add(b, (2.0 * b).mul_add(j, j * j)) / (b - a) * (sig + a) / (sig + b)
}

/// sRGB's code (0 to 255) of linear light 0 to 1.
fn srgb(light: f64) -> u8 {
    let light = light.clamp(0.0, 1.0);
    let coded = if light <= 0.003_130_8 {
        12.92 * light
    } else {
        1.055f64.mul_add(light.powf(1.0 / 2.4), -0.055)
    };
    // Between 0 and 255, rounded.
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let code = (coded * 255.0).round() as u8;
    code
}

/// The matrix from `primaries`' linear RGB to BT.709's.
fn to_bt709(primaries: Primaries) -> [[f64; 3]; 3] {
    match primaries {
        Primaries::Bt709 => [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
        Primaries::P3 => [
            [1.224_940_2, -0.224_940_2, 0.0],
            [-0.042_056_95, 1.042_056_95, 0.0],
            [-0.019_637_55, -0.078_636_05, 1.098_273_6],
        ],
        Primaries::Bt2020 => [
            [1.660_491, -0.587_641_1, -0.072_849_9],
            [-0.124_550_5, 1.132_899_9, -0.008_349_4],
            [-0.018_150_8, -0.100_578_9, 1.118_729_7],
        ],
    }
}

/// The sum of each of `row`'s numbers times the one of `rgb` at its place.
fn dot(row: [f64; 3], rgb: [f64; 3]) -> f64 {
    row.iter().zip(rgb).map(|(m, c)| m * c).sum()
}

/// `image`, 8 or 16-bit RGB coded as `hdr` says over the whole range of its format, as 8-bit sRGB.
pub fn tone_map(image: &VipsImage, hdr: Hdr) -> rs_vips::Result<VipsImage> {
    let bands = image.get_bands();
    let (width, height) = (image.get_width(), image.get_height());
    let rgb = if bands >= 3 {
        image.extract_band_with_opts(0, VOption::new().set("n", 3))?
    } else {
        VipsImage::bandjoin(&[image.clone(), image.clone(), image.clone()])?
    };
    let wide = rgb.get_format()? == BandFormat::Ushort;
    let samples = rgb
        .cast(if wide { BandFormat::Ushort } else { BandFormat::Uchar })?
        .write_to_memory();
    let codes: Vec<usize> = if wide {
        (samples.as_chunks::<2>().0.iter())
            .map(|b| usize::from(u16::from_ne_bytes(*b)))
            .collect()
    } else {
        samples.iter().map(|b| usize::from(*b)).collect()
    };
    let (size, levels) = if wide { (65_535.0, 65_536u32) } else { (255.0, 256) };
    // Light of each code. HLG's system gamma needs the pixel's luminance, so its table holds the scene light.
    let table: Vec<f64> = (0..levels)
        .map(|code| linear(hdr.transfer, f64::from(code) / size))
        .collect();
    let matrix = to_bt709(hdr.primaries);
    let light = |pixel: &[usize]| -> [f64; 3] {
        let at = |i: usize| pixel.get(i).and_then(|code| table.get(*code)).copied().unwrap_or(0.0);
        let mut rgb = [at(0), at(1), at(2)];
        if hdr.transfer == Transfer::Hlg {
            // Display light of a 1,000 nit display: the scene light's luminance to the 0.2, times 1,000 / 203.
            let scale = dot([0.2627, 0.6780, 0.0593], rgb).max(1e-9).powf(0.2) * 1000.0 / WHITE;
            rgb = rgb.map(|c| c * scale);
        }
        matrix.map(|row| dot(row, rgb))
    };
    // The picture's own peak, in reference whites, never beyond what PQ codes.
    let peak = (codes.as_chunks::<3>().0.iter())
        .map(|pixel| light(pixel).into_iter().fold(0.0, f64::max))
        .fold(1.0, f64::max)
        .min(10_000.0 / WHITE);
    let out: Vec<u8> = (codes.as_chunks::<3>().0.iter())
        .flat_map(|pixel| {
            let rgb = light(pixel);
            let sig = rgb.into_iter().fold(0.0, f64::max);
            let ratio = if sig > 1e-9 { mobius(sig, peak) / sig } else { 1.0 };
            rgb.map(|c| srgb(c * ratio))
        })
        .collect();
    let made = VipsImage::new_from_memory_copy(&out, width, height, 3, BandFormat::Uchar)?;
    let made = made.copy_with_opts(VOption::new().set("interpretation", Interpretation::Srgb as i32))?;
    if bands == 4 || bands == 2 {
        // An alpha channel stays, as it was (its range scaled to 8 bits).
        let alpha = image.extract_band(bands.saturating_sub(1))?;
        let alpha = if wide {
            alpha.linear(&[255.0 / 65_535.0], &[0.0])?.cast(BandFormat::Uchar)?
        } else {
            alpha
        };
        return VipsImage::bandjoin(&[made, alpha]);
    }
    Ok(made)
}

// Expected values of the tests are written as the documents give them, and compared as they are computed.
#[allow(
    clippy::float_cmp,
    clippy::suboptimal_flops,
    clippy::unreadable_literal,
    clippy::assert_is_empty,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss
)]
#[cfg(test)]
mod tests {
    use super::*;

    fn vips() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
        let guard = LOCK.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        rs_vips::Vips::init("hdr test").ok();
        guard
    }

    /// PQ's code of `nits`.
    fn pq(nits: f64) -> f64 {
        let (m1, m2) = (2610.0 / 16384.0, 2523.0 / 4096.0 * 128.0);
        let (c1, c2, c3): (f64, f64, f64) = (3424.0 / 4096.0, 2413.0 / 4096.0 * 32.0, 2392.0 / 4096.0 * 32.0);
        let y = (nits / 10_000.0).powf(m1);
        ((c1 + c2 * y) / (1.0 + c3 * y)).powf(m2)
    }

    #[test]
    fn the_codes_of_the_files_say_whether_and_how_a_picture_is_hdr() {
        assert_eq!(
            Hdr::from_codes(9, 16),
            Some(Hdr {
                transfer: Transfer::Pq,
                primaries: Primaries::Bt2020
            })
        );
        assert_eq!(
            Hdr::from_codes(12, 18),
            Some(Hdr {
                transfer: Transfer::Hlg,
                primaries: Primaries::P3
            })
        );
        assert_eq!(
            Hdr::from_codes(2, 16).unwrap().primaries,
            Primaries::Bt2020,
            "unsaid primaries are BT.2020's"
        );
        for sdr in [1, 4, 6, 13, 0, 2] {
            assert_eq!(Hdr::from_codes(1, sdr), None, "transfer {sdr}");
        }
    }

    #[test]
    fn pq_reference_white_is_one_and_hlgs_white_is_a_thousand_nits() {
        assert!((linear(Transfer::Pq, pq(203.0)) - 1.0).abs() < 1e-6);
        assert!((linear(Transfer::Pq, pq(1000.0)) - 1000.0 / 203.0).abs() < 1e-5);
        assert_eq!(linear(Transfer::Pq, 0.0), 0.0);
        assert!(
            (linear(Transfer::Hlg, 1.0) - 1.0).abs() < 1e-6,
            "HLG's peak is scene light 1"
        );
        assert!((linear(Transfer::Hlg, 0.5) - 1.0 / 12.0).abs() < 1e-9);
    }

    #[test]
    fn the_curve_keeps_what_is_below_its_knee_and_brings_the_peak_to_white() {
        assert_eq!(mobius(0.2, 5.0), 0.2);
        assert!((mobius(5.0, 5.0) - 1.0).abs() < 1e-9);
        assert!(mobius(2.0, 5.0) > mobius(1.0, 5.0) && mobius(2.0, 5.0) < 1.0);
        assert_eq!(mobius(0.8, 1.0), 0.8, "a picture within SDR is untouched");
    }

    /// A 3 × 1 picture of 16-bit greys at 0, 18 and 203 nits of PQ, and a 1,000 nit one.
    fn greys() -> VipsImage {
        let nits = [0.0, 18.0, 203.0, 1000.0];
        let mut bytes = vec![];
        for n in nits {
            let code = (pq(n) * 65535.0).round() as u16;
            for _ in 0..3 {
                bytes.extend(code.to_ne_bytes());
            }
        }
        VipsImage::new_from_memory_copy(&bytes, 4, 1, 3, BandFormat::Ushort).unwrap()
    }

    #[test]
    fn greys_stay_grey_black_stays_black_and_the_peak_reaches_white() {
        let _vips = vips();
        let hdr = Hdr::from_codes(9, 16).unwrap();
        let sdr = tone_map(&greys(), hdr).unwrap();
        assert_eq!((sdr.get_width(), sdr.get_height(), sdr.get_bands()), (4, 1, 3));
        let pixels = sdr.write_to_memory();
        let grey = |n: usize| &pixels[3 * n..3 * n + 3];
        for n in 0..4 {
            assert!(
                grey(n)[0] == grey(n)[1] && grey(n)[1] == grey(n)[2],
                "pixel {n}: {:?}",
                grey(n)
            );
        }
        assert_eq!(grey(0)[0], 0);
        assert!((60..=115).contains(&grey(1)[0]), "18 nits shows as {}", grey(1)[0]);
        assert!(grey(2)[0] >= 195, "reference white shows as {}", grey(2)[0]);
        assert_eq!(grey(3)[0], 255, "the brightest pixel of the picture is white");
        // An 8-bit picture is the same picture at 1/257 of the codes.
        let narrow = greys()
            .linear(&[255.0 / 65535.0], &[0.0])
            .unwrap()
            .cast(BandFormat::Uchar)
            .unwrap();
        let again = tone_map(&narrow, hdr).unwrap().write_to_memory();
        assert!(again.iter().zip(&pixels).all(|(a, b)| a.abs_diff(*b) <= 6));
        // A picture with an alpha channel keeps it.
        let alpha = VipsImage::bandjoin(&[greys(), greys().extract_band(0).unwrap()]).unwrap();
        assert_eq!(tone_map(&alpha, hdr).unwrap().get_bands(), 4);
    }
}
