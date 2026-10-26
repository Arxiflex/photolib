//! Embedded metadata: EXIF, XMP and IPTC IIM in still images, merged by the Metadata Working Group's rules
//! (design doc 13 §7.2): EXIF first; IIM against XMP as the IPTC digest decides; every date kept as a claim.

mod containers;
mod exif;
mod file;
mod iptc;
mod motion;
mod movie;
mod tiles;
mod xmp;

pub(crate) use tiles::read as read_heif;

use crate::proto::kernel::v1::{
    ByteSpan, FileFormat, GeoPoint, ImageRegion, KeywordPath, Pace, ReadMetadataRequest, ReadMetadataResponse,
};
use crate::proto::model::v1::{CaptureTime, CaptureTimePrecision};
use containers::Exif;
use file::File;
use md5::{Digest, Md5};

/// Descriptions cameras write by default, which say nothing.
const BOILERPLATE: [&str; 3] = ["OLYMPUS DIGITAL CAMERA", "SONY DSC", "default"];

pub fn read(request: &ReadMetadataRequest) -> ReadMetadataResponse {
    let pieces = request.ranges.iter().map(|r| (r.offset, r.data.as_slice()));
    read_pieces(pieces, request.size)
}

/// What `read` finds in these pieces of a file, each at its offset, of `size` bytes if known (else 0).
pub fn read_pieces<'a>(pieces: impl IntoIterator<Item = (u64, &'a [u8])>, size: u64) -> ReadMetadataResponse {
    let file = File::new(pieces);
    let found = containers::walk(&file);
    let exif = match &found.exif {
        Some(Exif::At(base)) => exif::read(&file, *base),
        Some(Exif::Item(bytes)) => exif::read(&File::new([(0, bytes.as_slice())]), 0),
        Some(Exif::Blocks(zero, exif, gps)) => exif::read_blocks(&file, *zero, *exif, *gps),
        None => exif::Exif::default(),
    };
    // The smallest and the largest JPEG in the file (offsets in a HEIF Exif item are the item's), as far as each is
    // seen to be one.
    let in_file = !matches!(found.exif, Some(Exif::Item(_)));
    let mut previews: Vec<_> = (found.previews.iter())
        .chain(exif.previews.iter().filter(|_| in_file))
        .copied()
        .filter(|&(at, length)| {
            let head = file.prefix(at, 2);
            (size == 0 || at.checked_add(length).is_some_and(|end| end <= size)) && [0xff, 0xd8].starts_with(head)
        })
        .map(|(offset, length)| ByteSpan { offset, length })
        .collect();
    previews.sort_by_key(|span| span.length);
    let xmp = found
        .xmp
        .as_deref()
        .or(exif.xmp.as_deref())
        .map(xmp::read)
        .unwrap_or_default();
    let photoshop = Some(found.photoshop.as_slice())
        .filter(|p| !p.is_empty())
        .or(exif.photoshop.as_deref());
    let (block, digest) = photoshop.map(iptc::resources).unwrap_or_default();
    let block = block.or(exif.iim.as_deref());
    let iim = block.map(iptc::read).unwrap_or_default();
    // A digest that no longer matches means a tool that knows only IIM changed it after the XMP was written.
    let iim_first = block
        .zip(digest)
        .is_some_and(|(block, digest)| Md5::digest(block).as_slice() != digest);
    let pick = |xmp: Option<String>, iim: Option<String>| {
        if iim_first { iim.or(xmp) } else { xmp.or(iim) }
    };
    let pick_all = |xmp: Vec<String>, iim: Vec<String>| {
        if iim_first && !iim.is_empty() || xmp.is_empty() {
            iim
        } else {
            xmp
        }
    };
    let orientation = match found.format {
        FileFormat::Heif | FileFormat::Quicktime => found.orientation,
        _ => exif.orientation.or(xmp.orientation).filter(|o| (1..=8).contains(o)),
    };
    let (width, height) = match found.format {
        FileFormat::Tiff => (exif.width, exif.height),
        _ => (found.width, found.height),
    };
    let said = |text: Option<String>| text.filter(|t| !BOILERPLATE.iter().any(|b| t.eq_ignore_ascii_case(b)));
    let regions = xmp
        .regions
        .into_iter()
        .map(|r| displayed(r, orientation.unwrap_or(1)))
        .collect();
    let xmp_depth = xmp.depth;
    let response = ReadMetadataResponse {
        format: found.format.into(),
        width,
        height,
        orientation: orientation.unwrap_or(0),
        make: exif.make.or(xmp.make).or(found.make).unwrap_or_default(),
        model: exif.model.or(xmp.model).or(found.model).unwrap_or_default(),
        location: exif.location.or(xmp.location).or(found.location),
        times: exif
            .times
            .into_iter()
            .chain(xmp.times)
            .chain(iim.time)
            .chain(found.times)
            .collect(),
        title: pick(xmp.title, iim.title).unwrap_or_default(),
        description: said(exif.description)
            .or_else(|| said(pick(xmp.description, iim.description)))
            .unwrap_or_default(),
        keywords: pick_all(xmp.keywords, iim.keywords),
        keyword_paths: xmp.paths.into_iter().map(|nodes| KeywordPath { nodes }).collect(),
        rating: xmp.rating,
        label: xmp.label.unwrap_or_default(),
        creators: exif
            .artist
            .map_or_else(|| pick_all(xmp.creators, iim.creators), |a| vec![a]),
        copyright: exif
            .copyright
            .or_else(|| pick(xmp.copyright, iim.copyright))
            .unwrap_or_default(),
        city: pick(xmp.city, iim.city).unwrap_or_default(),
        state: pick(xmp.state, iim.state).unwrap_or_default(),
        country: pick(xmp.country, iim.country).unwrap_or_default(),
        regions,
        panorama: xmp.panorama.or(found.panorama),
        motion_photo: xmp.motion,
        duration_ms: found.duration_ms,
        frame_rate: found.frame_rate,
        codec: found.codec.into(),
        transfer: found.transfer,
        dolby_vision: found.dolby_vision,
        gain_map: found.gain_map || xmp.gain_map,
        stereo_mode: found.stereo.into(),
        content_identifier: exif.content_identifier.or(found.content_identifier).unwrap_or_default(),
        burst_id: exif.burst_id.or(xmp.burst_id).unwrap_or_default(),
        ..ReadMetadataResponse::default()
    };
    let samsung = response.make.eq_ignore_ascii_case("samsung");
    let markers = response.motion_photo.as_ref();
    let motion_video = motion::locate(&file, size, found.format, markers, samsung);
    // Samsung's trailer blocks; a movie's whoever made it, as Samsung's movies name no make.
    let movie = found.format == FileFormat::Quicktime;
    let sef = |name: &[u8]| (samsung || movie) && size > 0 && motion::sef(&file, size, name).is_some();
    let pace = match found.capture_fps {
        _ if movie && sef(b"Slow_Motion_Data") => Pace::SlowMotion,
        fps if fps > 60.0 || found.frame_rate >= 100.0 => Pace::SlowMotion,
        fps if fps > 0.0 && fps < 0.9 * found.frame_rate => Pace::TimeLapse,
        _ => Pace::Unspecified,
    };
    let depth = found.depth || xmp_depth || sef(b"DepthMap_Data");
    let missing = file
        .missing()
        .into_iter()
        .map(|(offset, length)| ByteSpan { offset, length });
    ReadMetadataResponse {
        missing: missing.collect(),
        motion_video,
        preview: previews.first().copied(),
        largest_preview: previews.last().copied(),
        spatial: found.spatial,
        depth,
        pace: pace.into(),
        ..response
    }
}

/// A region in the stored frame, moved to the frame displayed after the EXIF orientation is applied.
fn displayed(region: ImageRegion, orientation: u32) -> ImageRegion {
    let point = |u: f64, v: f64| match orientation {
        2 => (1.0 - u, v),
        3 => (1.0 - u, 1.0 - v),
        4 => (u, 1.0 - v),
        5 => (v, u),
        6 => (1.0 - v, u),
        7 => (1.0 - v, 1.0 - u),
        8 => (v, 1.0 - u),
        _ => (u, v),
    };
    let (a, b) = (
        point(region.x, region.y),
        point(region.x + region.width, region.y + region.height),
    );
    ImageRegion {
        x: a.0.min(b.0),
        y: a.1.min(b.1),
        width: (a.0 - b.0).abs(),
        height: (a.1 - b.1).abs(),
        ..region
    }
}

/// Degrees from degrees, minutes and seconds, any of them fractional and the last ones optional.
pub fn degrees(parts: &[f64]) -> Option<f64> {
    let sum = parts.iter().zip([1.0, 60.0, 3600.0]).map(|(p, d)| p / d).sum();
    (1..=3).contains(&parts.len()).then_some(sum)
}

pub fn location(latitude: f64, longitude: f64, altitude: Option<f64>) -> Option<GeoPoint> {
    let valid = latitude.abs() <= 90.0 && longitude.abs() <= 180.0 && (latitude, longitude) != (0.0, 0.0);
    valid.then_some(GeoPoint {
        latitude,
        longitude,
        altitude_m: altitude.filter(|a| a.is_finite()),
    })
}

/// A date as the file wrote it, unchecked: `text` in EXIF's or ISO 8601's form, with EXIF's separate sub-second
/// digits and offset. A text that is no date still makes a claim, with an empty value.
pub fn claim(source: &str, text: &str, subsec: Option<&str>, offset: Option<&str>) -> CaptureTime {
    let mut time = CaptureTime {
        source: source.into(),
        ..CaptureTime::default()
    };
    let Some((mut local, mut precision, inline)) = parse_time(text.trim()) else {
        return time;
    };
    let subsec = subsec.filter(|d| !d.is_empty() && d.bytes().all(|b| b.is_ascii_digit()));
    if let (Some(digits), CaptureTimePrecision::Second) = (subsec, precision) {
        local = format!("{local}.{:0<3}", &digits[..digits.len().min(3)]);
        precision = CaptureTimePrecision::Millisecond;
    }
    time.local_datetime = local;
    time.precision = precision.into();
    time.offset_minutes = offset.and_then(parse_offset).or(inline);
    time
}

/// "YYYY-MM-DDThh:mm:ss.sss±hh:mm" or EXIF's "YYYY:MM:DD hh:mm:ss", cut anywhere after the year: the wall clock as
/// ISO 8601 to milliseconds at most, its precision and the offset. Digits are not checked against the calendar.
fn parse_time(text: &str) -> Option<(String, CaptureTimePrecision, Option<i32>)> {
    use CaptureTimePrecision::{Day, Millisecond, Minute, Month, Second, Year};
    let b = text.as_bytes();
    let digits = |at: usize, n: usize| {
        let field = b.get(at..at + n)?;
        field.iter().all(u8::is_ascii_digit).then(|| &text[at..at + n])
    };
    let after = |at: usize, separators: &[u8]| b.get(at).is_some_and(|s| separators.contains(s));
    let mut local = digits(0, 4)?.to_string();
    let (mut at, mut precision) = (4, Year);
    for (next, separators, joint) in [(Month, &b"-:"[..], "-"), (Day, b"-:", "-"), (Minute, b"T ", "T")] {
        let Some(field) = digits(at + 1, 2).filter(|_| after(at, separators)) else {
            break;
        };
        local = format!("{local}{joint}{field}");
        (at, precision) = (at + 3, next);
        if next == Minute {
            let minutes = digits(at + 1, 2).filter(|_| after(at, b":"))?;
            local = format!("{local}:{minutes}");
            at += 3;
            if let Some(seconds) = digits(at + 1, 2).filter(|_| after(at, b":")) {
                local = format!("{local}:{seconds}");
                (at, precision) = (at + 3, Second);
                let fraction = b[at..].iter().skip(1).take_while(|d| d.is_ascii_digit()).count();
                if after(at, b".") && fraction > 0 {
                    local = format!("{local}.{:0<3}", &text[at + 1..at + 1 + fraction.min(3)]);
                    (at, precision) = (at + 1 + fraction, Millisecond);
                }
            }
        }
    }
    let offset = match &text[at..] {
        "" => None,
        "Z" => Some(0),
        rest => Some(parse_offset(rest)?),
    };
    Some((local, precision, offset))
}

/// "±hh:mm" or "±hhmm" in minutes; the digits are not checked against real zones.
fn parse_offset(text: &str) -> Option<i32> {
    let b = text.as_bytes();
    let sign = match b.first()? {
        b'+' => 1,
        b'-' => -1,
        _ => return None,
    };
    let minutes_at = match b.len() {
        6 if b[3] == b':' => 4,
        5 => 3,
        _ => return None,
    };
    let number = |at: usize| {
        let pair = b.get(at..at + 2)?;
        pair.iter()
            .all(u8::is_ascii_digit)
            .then(|| i32::from(pair[0] - b'0') * 10 + i32::from(pair[1] - b'0'))
    };
    Some(sign * (number(1)? * 60 + number(minutes_at)?))
}
