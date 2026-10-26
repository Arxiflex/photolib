//! ISOBMFF and QuickTime movies: the movie's length and times, its first video track's sample description and turn,
//! and Apple's keys and the user data that say where and with what it was filmed; and Canon's CR3, a RAW still.

use super::containers::{Exif, Found, be, boxes, dimensions, transfer};
use super::file::File;
use super::{claim, degrees, location, xmp};
use crate::proto::kernel::v1::{FileFormat, GeoPoint, Panorama, StereoMode};

/// The uuid box of Spherical Video V1, which holds its XML.
const SPHERICAL_V1: [u8; 16] = *b"\xff\xcc\x82\x63\xf8\x55\x4a\x93\x88\x14\x58\x7a\x02\x52\x1f\xdd";

/// Canon's uuid box in a CR3's moov, and the one of its PRVW.
const CANON: [u8; 16] = *b"\x85\xc0\xb6\x87\x82\x0f\x11\xe0\x81\x11\xf4\xce\x46\x2b\x6a\x48";
const PRVW: [u8; 16] = *b"\xea\xf4\x2b\x5e\x1c\x98\x4b\x88\xb9\xfb\xb7\xdc\x40\x6e\x4d\x16";

pub fn read(file: &File, found: &mut Found) -> FileFormat {
    if file.prefix(8, 4) == b"crx " {
        return cr3(file, found);
    }
    let Some((_, start, end)) = boxes(file, 0, u64::MAX).find(|b| &b.0 == b"moov") else {
        return FileFormat::Quicktime;
    };
    file.want(start, end - start);
    let (mut created, mut video) = (None, false);
    for (kind, start, end) in boxes(file, start, end) {
        match &kind {
            b"mvhd" => {
                let data = file.get(start, end - start).unwrap_or_default();
                let (clock, scale) = if data.first() == Some(&1) { (8, 20) } else { (4, 12) };
                let field = |at: usize, len: usize| data.get(at..at + len).map(be);
                created = field(4, clock).filter(|&c| c != 0);
                if let (Some(timescale @ 1..), Some(duration)) = (field(scale, 4), field(scale + 4, clock)) {
                    found.duration_ms = (u128::from(duration) * 1000 / u128::from(timescale)) as u64;
                }
            }
            b"trak" if !video => video = track(file, start, end, found),
            b"meta" => keys(file, start, end, found),
            b"udta" => {
                for (kind, start, end) in boxes(file, start, end) {
                    // QuickTime text: its length and language, then the text.
                    let Some(text) = file.get(start, end - start).and_then(|d| d.get(4..)) else {
                        continue;
                    };
                    let text = String::from_utf8_lossy(text);
                    match &kind {
                        b"\xa9xyz" => found.location = found.location.or(iso6709(&text)),
                        b"\xa9day" => found
                            .times
                            .push(claim("quicktime:ContentCreateDate", &text, None, None)),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    if let Some(seconds) = created {
        found
            .times
            .push(claim("quicktime:CreateDate", &clock(seconds), None, None));
    }
    FileFormat::Quicktime
}

/// Canon's CR3, a RAW still in ISOBMFF: IFD0, the EXIF IFD and GPS in TIFF blocks of their own (CMT1, CMT2, CMT4) in
/// Canon's uuid box in the moov, the image's size in the first track's sample entry, and JPEG pictures of it in THMB
/// beside the CMTs and in PRVW, a uuid box of its own.
fn cr3(file: &File, found: &mut Found) -> FileFormat {
    let mut blocks = [None; 3];
    // The media data comes last.
    for (kind, start, end) in boxes(file, 0, u64::MAX).take_while(|b| &b.0 != b"mdat") {
        match &kind {
            b"moov" => {
                file.want(start, end.saturating_sub(start));
                for (kind, start, end) in boxes(file, start, end) {
                    match &kind {
                        b"uuid" if file.get(start, 16) == Some(&CANON) => {
                            for (kind, start, end) in boxes(file, start.saturating_add(16), end) {
                                match &kind {
                                    b"CMT1" => blocks[0] = Some(start),
                                    b"CMT2" => blocks[1] = Some(start),
                                    b"CMT4" => blocks[2] = Some(start),
                                    b"THMB" => picture(file, start, end, found),
                                    _ => {}
                                }
                            }
                        }
                        b"trak" if found.width == 0 => _ = track(file, start, end, found),
                        _ => {}
                    }
                }
            }
            b"uuid" if file.get(start, 16) == Some(&PRVW) => picture(file, start.saturating_add(16), end, found),
            _ => {}
        }
    }
    if let [Some(zero), exif, gps] = blocks {
        found.exif = Some(Exif::Blocks(zero, exif, gps));
    }
    FileFormat::Cr3
}

/// The JPEG in a box of Canon's, after a header of at most 64 bytes, to the box's end.
fn picture(file: &File, start: u64, end: u64, found: &mut Found) {
    let head = file.get(start, end.saturating_sub(start).min(64)).unwrap_or_default();
    if let Some(at) = head.windows(3).position(|w| w == [0xff, 0xd8, 0xff]) {
        let at = start.saturating_add(at as u64);
        found.previews.push((at, end.saturating_sub(at)));
    }
}

/// A video track's first sample description and its matrix as an orientation; false for other tracks.
fn track(file: &File, start: u64, end: u64, found: &mut Found) -> bool {
    let child = |kind: &[u8; 4], (start, end): (u64, u64)| {
        boxes(file, start, end)
            .find(|b| &b.0 == kind)
            .map(|(_, start, end)| (start, end))
    };
    let Some(mdia) = child(b"mdia", (start, end)) else {
        return false;
    };
    if child(b"hdlr", mdia).and_then(|(at, _)| file.get(at + 8, 4)) != Some(b"vide") {
        return false;
    }
    let stbl = [b"minf", b"stbl"]
        .iter()
        .try_fold(mdia, |within, kind| child(kind, within));
    let stsd = stbl.and_then(|stbl| child(b"stsd", stbl));
    let stts = stbl.and_then(|stbl| child(b"stts", stbl));
    found.frame_rate = frame_rate(file, child(b"mdhd", mdia), stts).unwrap_or_default();
    if let Some((fourcc, entry, end)) = stsd.and_then(|(start, end)| boxes(file, start + 8, end).next()) {
        found.codec = codec(&fourcc);
        if let Some(size) = file.get(entry + 24, 4) {
            dimensions(found, be(&size[..2]), be(&size[2..]));
        }
        // The visual sample entry's own fields take 78 bytes; boxes follow.
        for (kind, start, end) in boxes(file, entry + 78, end) {
            match &kind {
                b"colr" => found.transfer = transfer(file.get(start, end - start).unwrap_or_default()),
                b"dvcC" | b"dvvC" | b"dvwC" => found.dolby_vision = true,
                // MV-HEVC's second view: Apple's video extended usage, or a layered HEVC configuration.
                b"vexu" | b"lhvC" => found.spatial = true,
                // Spherical Video V2.
                b"st3d" => {
                    let mode = file.get(start + 4, 1).map_or(0, |m| i32::from(m[0]));
                    found.stereo = StereoMode::try_from(mode).unwrap_or_default();
                }
                b"sv3d" => {
                    let proj = boxes(file, start, end).find(|b| &b.0 == b"proj");
                    let (width, height) = (found.width, found.height);
                    found.panorama = proj.and_then(|(_, start, end)| {
                        boxes(file, start, end).find_map(|(kind, start, _)| match &kind {
                            b"equi" => Some(equirectangular(file.get(start.saturating_add(4), 16), width, height)),
                            b"cbmp" => Some(sphere("cubemap")),
                            b"mshp" => Some(sphere("mesh")),
                            _ => None,
                        })
                    });
                }
                _ => {}
            }
        }
    }
    let v1 = boxes(file, start, end)
        .filter(|b| &b.0 == b"uuid")
        .find_map(|(_, start, end)| {
            let data = file.get(start, end - start)?;
            data.strip_prefix(&SPHERICAL_V1).map(xmp::spherical)
        });
    if let Some((projection, stereo)) = v1 {
        found.panorama = found.panorama.take().or(projection.as_deref().map(sphere));
        if found.stereo == StereoMode::Unspecified {
            found.stereo = stereo;
        }
    }
    let matrix = child(b"tkhd", (start, end))
        .and_then(|(at, _)| file.get(at + if file.prefix(at, 1) == [1] { 52 } else { 40 }, 20));
    if let Some(matrix) = matrix {
        let sign = |at: usize| (be(&matrix[at..at + 4]) as u32 as i32).signum();
        // a, b, c and d of the 2-D transform, turned clockwise then mirrored as EXIF numbers it.
        found.orientation = match [sign(0), sign(4), sign(12), sign(16)] {
            [-1, 0, 0, 1] => Some(2),
            [-1, 0, 0, -1] => Some(3),
            [1, 0, 0, -1] => Some(4),
            [0, 1, 1, 0] => Some(5),
            [0, 1, -1, 0] => Some(6),
            [0, -1, -1, 0] => Some(7),
            [0, -1, 1, 0] => Some(8),
            _ => None,
        };
    }
    true
}

/// A track's frames a second: its samples (stts' counts) over their length (stts' deltas) in its timescale (mdhd).
fn frame_rate(file: &File, mdhd: Option<(u64, u64)>, stts: Option<(u64, u64)>) -> Option<f64> {
    let (mdhd, (at, end)) = (mdhd?.0, stts?);
    let timescale = file.get(
        mdhd.saturating_add(if file.prefix(mdhd, 1) == [1] { 20 } else { 12 }),
        4,
    )?;
    let timescale = f64::from(u32::from_be_bytes(timescale.try_into().ok()?));
    let data = file.get(at, end.checked_sub(at)?)?;
    let count = usize::try_from(be(data.get(4..8)?)).ok()?;
    let (entries, _) = data.get(8..)?.as_chunks::<8>();
    let (frames, ticks) = entries
        .iter()
        .take(count)
        .fold((0.0, 0.0), |(frames, ticks), &[a, b, c, d, e, f, g, h]| {
            let n = f64::from(u32::from_be_bytes([a, b, c, d]));
            (
                frames + n,
                n.mul_add(f64::from(u32::from_be_bytes([e, f, g, h])), ticks),
            )
        });
    (ticks > 0.0).then_some(frames * timescale / ticks)
}

fn sphere(projection: &str) -> Panorama {
    Panorama {
        projection: projection.into(),
        ..Panorama::default()
    }
}

/// Spherical Video V2's equirectangular projection, cut by its bounds (equi's top, bottom, left and right): GPano's
/// pixels of the full panorama a picture of this size is cut from, unless the bounds cut nothing or leave nothing.
fn equirectangular(bounds: Option<&[u8]>, width: u32, height: u32) -> Panorama {
    let whole = sphere("equirectangular");
    let Some(&[top, bottom, left, right]) = bounds.map(|b| b.as_chunks::<4>().0) else {
        return whole;
    };
    let [top, bottom, left, right] = [top, bottom, left, right].map(u32::from_be_bytes);
    match (uncut(width, left, right), uncut(height, top, bottom)) {
        (Some((full_width, cropped_left)), Some((full_height, cropped_top)))
            if [top, bottom, left, right] != [0; 4] && width > 0 && height > 0 =>
        {
            Panorama {
                full_width,
                full_height,
                cropped_left,
                cropped_top,
                cropped_width: width,
                cropped_height: height,
                ..whole
            }
        }
        _ => whole,
    }
}

/// The full panorama's side and where the picture starts on it, both rounded, from the picture's side and the 0.32
/// fixed-point fractions of the full side cut off before and after it; None when they add up to the whole side.
fn uncut(side: u32, before: u32, after: u32) -> Option<(u32, u32)> {
    const ONE: u64 = 1 << 32;
    let kept = ONE.checked_sub(u64::from(before).checked_add(u64::from(after))?)?;
    let full = u64::from(side)
        .checked_mul(ONE)?
        .checked_add(kept / 2)?
        .checked_div(kept)?;
    let start = u64::from(before).checked_mul(full)?.checked_add(ONE / 2)? / ONE;
    Some((u32::try_from(full).ok()?, u32::try_from(start).ok()?))
}

/// QuickTime metadata: the names in keys and their values in ilst, such as com.apple.quicktime.creationdate.
fn keys(file: &File, start: u64, end: u64, found: &mut Found) {
    // ISOBMFF's meta has a version and flags, QuickTime's has not.
    let start = if file.get(start + 4, 4) == Some(b"hdlr") {
        start
    } else {
        start + 4
    };
    let mut names = vec![];
    for (kind, start, end) in boxes(file, start, end) {
        if &kind == b"keys" {
            // Each key is laid out as a box: its length, namespace and name.
            names = boxes(file, start + 8, end)
                .map(|(_, start, end)| file.get(start, end - start).map(String::from_utf8_lossy))
                .collect();
        } else if &kind == b"ilst" {
            for (index, start, end) in boxes(file, start, end) {
                let key = usize::try_from(be(&index))
                    .ok()
                    .and_then(|i| names.get(i.checked_sub(1)?));
                let value = boxes(file, start, end)
                    .find(|b| &b.0 == b"data")
                    .and_then(|(_, start, end)| file.get(start + 8, end.saturating_sub(start + 8)));
                let (Some(Some(key)), Some(value)) = (key, value) else {
                    continue;
                };
                let text = String::from_utf8_lossy(value).trim().to_string();
                match key.as_ref() {
                    "com.apple.quicktime.creationdate" => {
                        found.times.push(claim("quicktime:CreationDate", &text, None, None))
                    }
                    "com.apple.quicktime.location.ISO6709" => found.location = iso6709(&text),
                    "com.apple.quicktime.make" => found.make = Some(text),
                    "com.apple.quicktime.model" => found.model = Some(text),
                    "com.apple.quicktime.content.identifier" => found.content_identifier = Some(text),
                    "com.android.capture.fps" => found.capture_fps = text.parse().unwrap_or_default(),
                    _ => {}
                }
            }
        }
    }
}

/// A sample entry's four-character code, or AVI's, as a codec name; empty when unknown.
pub fn codec(fourcc: &[u8]) -> &'static str {
    match fourcc.to_ascii_lowercase().as_slice() {
        b"avc1" | b"avc3" | b"h264" | b"x264" => "h264",
        b"hvc1" | b"hev1" | b"dvh1" | b"dvhe" => "hevc",
        b"av01" => "av1",
        b"vp08" => "vp8",
        b"vp09" => "vp9",
        b"s263" | b"h263" => "h263",
        b"jpeg" | b"mjpg" | b"mjpa" | b"mjpb" => "mjpeg",
        b"apch" | b"apcn" | b"apcs" | b"apco" | b"ap4h" | b"ap4x" => "prores",
        b"mp4v" | b"xvid" | b"divx" | b"dx50" | b"fmp4" => "xvid",
        b"dvsd" | b"dvhd" | b"dvsl" | b"dvc " | b"dvcp" | b"dv5n" | b"dv5p" => "dv",
        _ => "",
    }
}

/// Seconds since 1904-01-01, QuickTime's epoch, as an ISO 8601 date and time (Howard Hinnant's civil_from_days, with
/// days counted from 0000-03-01).
fn clock(seconds: u64) -> String {
    let (days, time) = (seconds / 86_400 + 695_361, seconds % 86_400);
    let (era, day) = (days / 146_097, days % 146_097);
    let year = (day - day / 1460 + day / 36_524 - day / 146_096) / 365;
    let day = day - (365 * year + year / 4 - year / 100);
    let month = (5 * day + 2) / 153;
    let (day, month) = (day - (153 * month + 2) / 5 + 1, (month + 2) % 12 + 1);
    let year = year + era * 400 + u64::from(month <= 2);
    let (hour, minute, second) = (time / 3600, time / 60 % 60, time % 60);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}")
}

/// "+48.8584+002.2945+035.000/" (ISO 6709): latitude and longitude in degrees, or with minutes and seconds as the
/// digits before the point say, then an optional altitude in metres.
fn iso6709(text: &str) -> Option<GeoPoint> {
    let text = text.split('/').next()?;
    let starts: Vec<usize> = text.match_indices(['+', '-']).map(|(at, _)| at).collect();
    let field = |n: usize| text.get(*starts.get(n)?..starts.get(n + 1).copied().unwrap_or(text.len()));
    let angle = |n: usize, width: usize| {
        let field = field(n)?;
        let value = field.parse::<f64>().ok()?;
        let (sign, value) = (value.signum(), value.abs());
        let parts = match field[1..].find('.').unwrap_or(field.len() - 1).checked_sub(width)? {
            0 => vec![value],
            2 => vec![(value / 100.0).trunc(), value % 100.0],
            4 => vec![
                (value / 10_000.0).trunc(),
                (value / 100.0).trunc() % 100.0,
                value % 100.0,
            ],
            _ => return None,
        };
        degrees(&parts).map(|d| sign * d)
    };
    location(angle(0, 2)?, angle(1, 3)?, field(2).and_then(|a| a.parse().ok()))
}
