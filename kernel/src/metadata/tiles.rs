//! Where a HEIF still keeps its coded images, for a host that decodes them with a video decoder: the primary item's
//! (or its grid's tiles') configuration and byte ranges, `clap`, `irot` and `imir`, and the `thmb` item's. No pixel is
//! decoded and nothing is assumed of the codec beyond the configuration box's fields.

use super::containers::{self, Heif, be};
use super::file::File;
use crate::proto::kernel::v1::{
    ByteSpan, HeifClap, HeifCodec, HeifImage, HeifPicture, HeifStatus, ReadHeifRequest, ReadHeifResponse,
};
use std::fmt::Write;

pub(crate) fn read(request: &ReadHeifRequest) -> ReadHeifResponse {
    let file = File::new(request.ranges.iter().map(|r| (r.offset, r.data.as_slice())));
    let mut response = match containers::table(&file) {
        None => ReadHeifResponse::default(),
        Some(heif) => answer(&file, &heif),
    };
    // Images the file is too short to hold, such as those of a download cut off, are not offered.
    let fits = |p: &HeifPicture| {
        let ends = p.image.iter().chain(&p.tiles).flat_map(|i| &i.spans);
        request.size == 0
            || ends
                .into_iter()
                .all(|s| s.offset.saturating_add(s.length) <= request.size)
    };
    response.thumbnail = response.thumbnail.filter(fits);
    if response.picture.as_ref().is_some_and(|p| !fits(p)) {
        response = ReadHeifResponse::default();
    }
    if response.status == HeifStatus::Unspecified as i32 {
        response.set_status(HeifStatus::NotHeif);
    }
    response.missing = (file.missing().into_iter())
        .map(|(offset, length)| ByteSpan { offset, length })
        .collect();
    response
}

fn answer(file: &File, heif: &Heif) -> ReadHeifResponse {
    let mut response = ReadHeifResponse::default();
    match picture(file, heif, heif.primary) {
        Ok(picture) => {
            response.set_status(HeifStatus::Ok);
            response.picture = Some(picture);
            let mut thumbnails = heif.thumbnails.iter().filter(|(_, of)| *of == heif.primary);
            response.thumbnail = thumbnails.find_map(|&(id, _)| picture_of(file, heif, id).ok());
        }
        Err((status, item_type)) => {
            response.set_status(status);
            response.item_type = item_type;
        }
    }
    response
}

type Failure = (HeifStatus, String);

fn damaged() -> Failure {
    (HeifStatus::NotHeif, String::new())
}

fn kind_of(heif: &Heif, id: u64) -> Option<[u8; 4]> {
    heif.infos.iter().find(|(i, ..)| *i == id).map(|(_, kind, _)| *kind)
}

/// The picture an item makes: a tone-mapped image's base image, a grid of its inputs, or a coded image.
fn picture(file: &File, heif: &Heif, id: u64) -> Result<HeifPicture, Failure> {
    if kind_of(heif, id).ok_or_else(damaged)? == *b"tmap" {
        let base = heif.inputs.iter().find(|(from, _)| *from == id);
        return base.map_or_else(|| Err(damaged()), |&(_, base)| picture_of(file, heif, base));
    }
    picture_of(file, heif, id)
}

fn picture_of(file: &File, heif: &Heif, id: u64) -> Result<HeifPicture, Failure> {
    let kind = kind_of(heif, id).ok_or_else(damaged)?;
    let mut picture = HeifPicture::default();
    if kind == *b"grid" {
        // Version, flags (bit 0: 32-bit sizes), rows and columns less one, then the output's size.
        let data = heif.bytes(file, id).unwrap_or_default();
        let [_, flags, rows, columns, sizes @ ..] = data.as_slice() else {
            return Err(damaged());
        };
        let size = if flags & 1 == 1 { 4 } else { 2 };
        let (rows, columns) = (
            u32::from(*rows).saturating_add(1),
            u32::from(*columns).saturating_add(1),
        );
        let (width, height) = (
            sizes.get(..size).map(be),
            sizes.get(size..).and_then(|h| h.get(..size)).map(be),
        );
        let tiles: Vec<_> = heif.inputs.iter().filter(|(from, _)| *from == id).collect();
        if width.is_none()
            || height.is_none()
            || tiles.len() != usize::try_from(rows.saturating_mul(columns)).unwrap_or(0)
        {
            return Err(damaged());
        }
        picture.rows = rows;
        picture.columns = columns;
        picture.width = u32::try_from(width.unwrap_or(0)).unwrap_or(0);
        picture.height = u32::try_from(height.unwrap_or(0)).unwrap_or(0);
        for &(_, tile) in tiles {
            picture.tiles.push(image(file, heif, tile)?);
        }
    } else {
        let image = image(file, heif, id)?;
        (picture.width, picture.height) = (image.width, image.height);
        picture.image = Some(image);
    }
    for &(kind, start, end) in heif.properties_of(id) {
        let Some(data) = file.get(start, end.saturating_sub(start)) else {
            continue;
        };
        match (&kind, data) {
            (b"clap", _) if data.len() >= 32 => picture.clap = Some(clap(data)),
            (b"irot", [angle, ..]) => picture.rotation = u32::from(angle & 3),
            (b"imir", [axis, ..]) => picture.mirror = Some(u32::from(axis & 1)),
            _ => {}
        }
    }
    Ok(picture)
}

fn clap(data: &[u8]) -> HeifClap {
    let word = |i: usize| data.as_chunks::<4>().0.get(i).map_or(0, |c| u32::from_be_bytes(*c));
    let signed = |i: usize| i32::from_be_bytes(word(i).to_be_bytes());
    HeifClap {
        width_num: word(0),
        width_den: word(1),
        height_num: word(2),
        height_den: word(3),
        x_num: signed(4),
        x_den: word(5),
        y_num: signed(6),
        y_den: word(7),
    }
}

/// A coded image: its codec by item type, the configuration box that goes with it, its size and its extents.
fn image(file: &File, heif: &Heif, id: u64) -> Result<HeifImage, Failure> {
    let kind = kind_of(heif, id).ok_or_else(damaged)?;
    let (codec, config_kind) = match &kind {
        b"hvc1" | b"hev1" => (HeifCodec::Hevc, *b"hvcC"),
        b"av01" => (HeifCodec::Av1, *b"av1C"),
        b"avc1" => (HeifCodec::Avc, *b"avcC"),
        _ => {
            return Err((
                HeifStatus::UnsupportedCodec,
                String::from_utf8_lossy(&kind).into_owned(),
            ));
        }
    };
    let mut config = None;
    let (mut width, mut height) = (0, 0);
    for &(property, start, end) in heif.properties_of(id) {
        let data = file.get(start, end.saturating_sub(start)).unwrap_or_default();
        if property == config_kind {
            config = Some(data).filter(|d| !d.is_empty());
        } else if &property == b"ispe" && data.len() >= 12 {
            let size = |from: usize| data.get(from..).and_then(|d| d.get(..4)).map_or(0, be);
            (width, height) = (u32::try_from(size(4)).unwrap_or(0), u32::try_from(size(8)).unwrap_or(0));
        }
    }
    let config = config.ok_or((HeifStatus::NoConfig, String::new()))?;
    let codec_string = codec_string(kind, config).ok_or((HeifStatus::NoConfig, String::new()))?;
    let location = heif.locations.iter().find(|l| l.id == id).ok_or_else(damaged)?;
    let base = if location.in_idat { heif.idat } else { 0 };
    let spans = (location.extents.iter())
        .filter_map(|&(offset, length)| {
            Some(ByteSpan {
                offset: base.checked_add(offset)?,
                length,
            })
        })
        .collect();
    Ok(HeifImage {
        codec: codec.into(),
        codec_string,
        config: config.to_vec(),
        width,
        height,
        spans,
    })
}

/// The WebCodecs codec string a configuration record makes (ISO/IEC 14496-15 Annex E; the AV1 codec mapping, §5;
/// RFC 6381 for AVC), None when the record is too short for it.
fn codec_string(kind: [u8; 4], config: &[u8]) -> Option<String> {
    let prefix = String::from_utf8_lossy(&kind);
    Some(match &kind {
        b"hvc1" | b"hev1" => {
            let [_, profile, f0, f1, f2, f3, constraints @ .., level] = config.get(..13)? else {
                return None;
            };
            let space = match profile >> 6 {
                1 => "A",
                2 => "B",
                3 => "C",
                _ => "",
            };
            let flags = u32::from_be_bytes([*f0, *f1, *f2, *f3]).reverse_bits();
            let tier = if profile & 0x20 == 0 { 'L' } else { 'H' };
            let kept = constraints
                .iter()
                .rposition(|b| *b != 0)
                .map_or(0, |i| i.saturating_add(1));
            let mut text = format!("{prefix}.{space}{}.{flags:X}.{tier}{level}", profile & 0x1f);
            for byte in constraints.iter().take(kept) {
                write!(text, ".{byte:X}").ok()?;
            }
            text
        }
        b"av01" => {
            let [_, levels, flags, ..] = config else {
                return None;
            };
            let depth = match (flags >> 6 & 1, flags >> 5 & 1) {
                (1, 1) => 12,
                (1, 0) => 10,
                _ => 8,
            };
            let tier = if flags >> 7 == 0 { 'M' } else { 'H' };
            format!("av01.{}.{:02}{tier}.{depth:02}", levels >> 5, levels & 0x1f)
        }
        _ => {
            let [_, profile, compatibility, level, ..] = config else {
                return None;
            };
            format!("avc1.{profile:02X}{compatibility:02X}{level:02X}")
        }
    })
}
