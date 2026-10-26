//! Where each container keeps its pixels' size and its metadata blocks.

use super::exif;
use super::file::{File, MAX_SPAN, uint};
use super::movie::{self, codec};
use crate::proto::kernel::v1::{FileFormat, GeoPoint, Panorama, StereoMode};
use crate::proto::model::v1::CaptureTime;

/// The most inputs of a derived image the reader keeps: an iPhone's grid has 48 tiles.
const MAX_INPUTS: u64 = 4096;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools)] // independent facts a container states, no state machine
pub struct Found {
    pub format: FileFormat,
    pub width: u32,
    pub height: u32,
    /// HEIF's irot and imir, or a video track's matrix, as an EXIF orientation; their readers ignore the EXIF one.
    pub orientation: Option<u32>,
    pub exif: Option<Exif>,
    pub xmp: Option<Vec<u8>>,
    /// Photoshop image resources (JPEG APP13), which hold the IIM and its digest.
    pub photoshop: Vec<u8>,
    /// A movie's metadata, which has no EXIF or XMP to come from.
    pub duration_ms: u64,
    pub frame_rate: f64,
    pub codec: &'static str,
    pub times: Vec<CaptureTime>,
    pub location: Option<GeoPoint>,
    pub make: Option<String>,
    pub model: Option<String>,
    /// ITU-T H.273 transfer characteristics, from HEIF's or a video's colr.
    pub transfer: u32,
    pub dolby_vision: bool,
    /// A 360° video's projection.
    pub panorama: Option<Panorama>,
    pub stereo: StereoMode,
    pub content_identifier: Option<String>,
    /// JPEG pictures of the image the container holds: RAF's, CR3's, a HEIF thumbnail item coded as JPEG.
    pub previews: Vec<(u64, u64)>,
    /// A stereo pair: HEIF's ster group, or a video track marked as MV-HEVC.
    pub spatial: bool,
    /// A HEIF auxiliary image of depth or a portrait matte.
    pub depth: bool,
    /// Android's com.android.capture.fps, 0 when the movie does not say.
    pub capture_fps: f64,
    /// An ISO 21496-1 or Apple gain map, as the container marks it.
    pub gain_map: bool,
}

/// A TIFF block: in the file at an offset, or assembled from the pieces of a HEIF item; or CR3's IFD0, EXIF and GPS
/// blocks in the file.
pub enum Exif {
    At(u64),
    Item(Vec<u8>),
    Blocks(u64, Option<u64>, Option<u64>),
}

pub fn walk(file: &File) -> Found {
    let mut found = Found::default();
    let head = file.prefix(0, 256);
    let format = match head {
        [0xff, 0xd8, 0xff, ..] => jpeg(file, 0, &mut found),
        _ if exif::magic(head).is_some() => {
            found.exif = Some(Exif::At(0));
            Some(FileFormat::Tiff)
        }
        [0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n', ..] => png(file, &mut found),
        _ if head.starts_with(b"RIFF") && head.get(8..12) == Some(b"WEBP") => webp(file, &mut found),
        _ if head.starts_with(b"RIFF") && head.get(8..12) == Some(b"AVI ") => avi(file, &mut found),
        [b'G', b'I', b'F', b'8', b'7' | b'9', b'a', ..] => gif(file, &mut found),
        [_, _, _, _, b'f', b't', b'y', b'p', ..] => {
            heif(file, &mut found).or_else(|| Some(movie::read(file, &mut found)))
        }
        _ if head.starts_with(b"FUJIFILMCCD-RAW ") => {
            let at = uint(file.get(84, 4).unwrap_or_default(), true);
            found
                .previews
                .push((at, uint(file.get(88, 4).unwrap_or_default(), true)));
            jpeg(file, at, &mut found).map(|_| FileFormat::Raf)
        }
        _ if [&b"<?xpacket"[..], b"<x:xmpmeta", b"<rdf:RDF"]
            .iter()
            .any(|tag| head.windows(tag.len()).any(|w| w == *tag)) =>
        {
            found.xmp = Some(file.prefix(0, usize::MAX).to_vec());
            Some(FileFormat::Xmp)
        }
        _ => None,
    };
    found.format = format.unwrap_or_default();
    found
}

pub fn be(bytes: &[u8]) -> u64 {
    uint(bytes, true)
}

fn le(bytes: &[u8]) -> u64 {
    uint(bytes, false)
}

/// The transfer characteristics in a colr box's nclx (ISOBMFF) or nclc (QuickTime) colour; 0 for an ICC profile.
pub fn transfer(colr: &[u8]) -> u32 {
    match colr {
        [b'n', b'c', b'l', b'x' | b'c', _, _, high, low, ..] => u32::from(u16::from_be_bytes([*high, *low])),
        _ => 0,
    }
}

pub fn dimensions(found: &mut Found, width: u64, height: u64) {
    if found.width == 0 {
        (found.width, found.height) = (width as u32, height as u32);
    }
}

/// The APP2 segment of an ISO 21496-1 gain map, which the primary image holds too.
const ISO_GAIN_MAP: &[u8] = b"urn:iso:std:iso:ts:21496:-1\0";
/// The type of Apple's gain map, a HEIF auxiliary image.
const APPLE_GAIN_MAP: &[u8] = b"urn:com:apple:photo:2020:aux:hdrgainmap\0";

/// The most of a Multi-Picture Format index read, and of its second picture's start, whose XMP names Apple's gain map.
const MPF_INDEX: u64 = 1024;
const APPLE_HEAD: u64 = 2048;

/// Where the second picture of the Multi-Picture Format index at `body` (which starts "MPF\0") is in the file, and how
/// long: its entry in the MP index IFD, whose offsets count from the byte-order mark.
fn second_picture(index: &[u8], body: u64) -> Option<(u64, u64)> {
    let tiff = index.strip_prefix(b"MPF\0")?;
    let big_endian = match tiff.get(..2)? {
        b"MM" => true,
        b"II" => false,
        _ => return None,
    };
    let field = |at: usize, len: usize| Some(uint(tiff.get(at..at.checked_add(len)?)?, big_endian));
    let ifd = usize::try_from(field(4, 4)?).ok()?;
    for entry in 0..usize::try_from(field(ifd, 2)?).ok()?.min(32) {
        let at = entry.checked_mul(12)?.checked_add(ifd)?.checked_add(2)?;
        // MPEntry: undefined, 16 bytes a picture, at an offset (the pictures after the first).
        if field(at, 2)? == 0xb002 && field(at.checked_add(4)?, 4)? >= 32 {
            let second = usize::try_from(field(at.checked_add(8)?, 4)?).ok()?.checked_add(16)?;
            let (size, offset) = (field(second.checked_add(4)?, 4)?, field(second.checked_add(8)?, 4)?);
            return (size > 0 && offset > 0).then_some((body.checked_add(4)?.checked_add(offset)?, size));
        }
    }
    None
}

/// The segments up to the frame header: APP1 (EXIF, XMP), APP2 (an ISO gain map), APP13 (Photoshop) and the frame's
/// size.
fn jpeg(file: &File, start: u64, found: &mut Found) -> Option<FileFormat> {
    let mut at = start.checked_add(2)?;
    // The image data or the end of the file need no length after them.
    while !matches!(file.prefix(at, 2), [0xff, 0xd9 | 0xda])
        && let Some(&[0xff, marker, high, low]) = file.get(at, 4)
    {
        match marker {
            0xff => at += 1,
            0x01 | 0xd0..=0xd8 => at += 2,
            _ => {
                let Some(len) = u64::from(u16::from_be_bytes([high, low])).checked_sub(2) else {
                    break;
                };
                let body = at + 4;
                match marker {
                    0xe1 | 0xed => {
                        if let Some(data) = file.get(body, len) {
                            app(data, body, marker, found);
                        }
                    }
                    0xe2 => {
                        found.gain_map |= file.get(body, len.min(ISO_GAIN_MAP.len() as u64)) == Some(ISO_GAIN_MAP);
                        // Apple's JPEG: the map is the second picture of a Multi-Picture Format index.
                        if !found.gain_map && file.get(body, 4) == Some(b"MPF\0") {
                            found.gain_map |= file
                                .get(body, len.min(MPF_INDEX))
                                .and_then(|index| second_picture(index, body))
                                .is_some_and(|(at, size)| {
                                    file.get(at, size.min(APPLE_HEAD)).is_some_and(|head| {
                                        let name = APPLE_GAIN_MAP.strip_suffix(b"\0").unwrap_or_default();
                                        // Only where the name can start: cheaper than comparing every window.
                                        (head.iter().enumerate()).any(|(at, &byte)| {
                                            byte == b'u' && head.get(at..).is_some_and(|rest| rest.starts_with(name))
                                        })
                                    })
                                });
                        }
                    }
                    // The frame header comes after the metadata.
                    0xc0..=0xcf if !matches!(marker, 0xc4 | 0xc8 | 0xcc) => {
                        if let Some(frame) = file.get(body + 1, 4) {
                            dimensions(found, be(&frame[2..]), be(&frame[..2]));
                        }
                        break;
                    }
                    _ => {}
                }
                at = body + len;
            }
        }
    }
    Some(FileFormat::Jpeg)
}

fn app(data: &[u8], body: u64, marker: u8, found: &mut Found) {
    const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
    if marker == 0xed {
        if let Some(resources) = data.strip_prefix(b"Photoshop 3.0\0") {
            found.photoshop.extend_from_slice(resources);
        }
    } else if data.starts_with(b"Exif\0") {
        found.exif.get_or_insert(Exif::At(body + 6));
    } else if let Some(packet) = data.strip_prefix(XMP) {
        found.xmp.get_or_insert_with(|| packet.to_vec());
    }
}

/// The chunks before the image data: IHDR, eXIf and an uncompressed iTXt XMP packet.
fn png(file: &File, found: &mut Found) -> Option<FileFormat> {
    let mut at = 8;
    while let Some(head) = file.get(at, 8) {
        let (len, data) = (be(&head[..4]), at + 8);
        match &head[4..] {
            b"IHDR" => {
                if let Some(size) = file.get(data, 8) {
                    dimensions(found, be(&size[..4]), be(&size[4..]));
                }
            }
            b"eXIf" => exif_chunk(file, data, found),
            b"iTXt" => {
                let text = file
                    .get(data, len)
                    .and_then(|chunk| chunk.strip_prefix(b"XML:com.adobe.xmp\0\0"));
                if let Some(rest) = text {
                    // After the compression method, a language tag and a translated keyword, each NUL-terminated.
                    let mut parts = rest.get(1..).unwrap_or_default().splitn(3, |&b| b == 0);
                    found
                        .xmp
                        .get_or_insert_with(|| parts.nth(2).unwrap_or_default().to_vec());
                }
            }
            b"IDAT" | b"IEND" => break,
            _ => {}
        }
        at = data.saturating_add(len + 4);
    }
    Some(FileFormat::Png)
}

/// An EXIF chunk of PNG or WebP: the TIFF block, after an "Exif\0\0" that some writers add.
fn exif_chunk(file: &File, data: u64, found: &mut Found) {
    let skip = if file.prefix(data, 6) == b"Exif\0\0" { 6 } else { 0 };
    found.exif.get_or_insert(Exif::At(data + skip));
}

fn webp(file: &File, found: &mut Found) -> Option<FileFormat> {
    let end = le(file.get(4, 4)?).saturating_add(8);
    for (kind, data, chunk_end) in chunks(file, 12, end) {
        match &kind {
            b"VP8X" => {
                if let Some(size) = file.get(data + 4, 6) {
                    dimensions(found, le(&size[..3]) + 1, le(&size[3..]) + 1);
                }
            }
            b"VP8 " => {
                if let Some(frame) = file.get(data + 3, 7).filter(|f| f.starts_with(&[0x9d, 0x01, 0x2a])) {
                    dimensions(found, le(&frame[3..5]) & 0x3fff, le(&frame[5..]) & 0x3fff);
                }
            }
            b"VP8L" => {
                if let Some(bits) = file.get(data, 5).filter(|b| b[0] == 0x2f).map(|b| le(&b[1..])) {
                    dimensions(found, (bits & 0x3fff) + 1, (bits >> 14 & 0x3fff) + 1);
                }
            }
            b"EXIF" => exif_chunk(file, data, found),
            b"XMP " => {
                if let Some(packet) = file.get(data, chunk_end - data) {
                    found.xmp.get_or_insert_with(|| packet.to_vec());
                }
            }
            _ => {}
        }
    }
    Some(FileFormat::Webp)
}

/// An AVI's main header (frame count and length, frame size) and its first video stream's codec.
fn avi(file: &File, found: &mut Found) -> Option<FileFormat> {
    let end = le(file.get(4, 4)?).saturating_add(8);
    let list = |kind: &'static [u8; 4], start, end| {
        chunks(file, start, end)
            .find(move |&(id, at, _)| &id == b"LIST" && file.get(at, 4) == Some(kind))
            .map(|(_, at, end)| (at + 4, end))
    };
    let Some((start, end)) = list(b"hdrl", 12, end) else {
        return Some(FileFormat::Avi);
    };
    let header = chunks(file, start, end).find(|c| &c.0 == b"avih");
    // Microseconds per frame, the frame count, the frame size.
    if let Some(h) = header.and_then(|(_, at, _)| file.get(at, 40)) {
        let frame = le(&h[..4]);
        found.duration_ms = frame * le(&h[16..20]) / 1000;
        if let Ok(frame @ 1..) = u32::try_from(frame) {
            found.frame_rate = 1e6 / f64::from(frame);
        }
        dimensions(found, le(&h[32..36]), le(&h[36..40]));
    }
    let mut at = start;
    // Each stream's list holds its header (type and handler) and format (for video, the compression).
    while let Some((stream, end)) = list(b"strl", at, end) {
        let chunk = |kind: &[u8; 4], from, len| {
            let found = chunks(file, stream, end).find(|c| &c.0 == kind);
            found.and_then(|(_, at, _)| file.get(at + from, len))
        };
        if chunk(b"strh", 0, 4) == Some(b"vids") {
            let handler = chunk(b"strf", 16, 4).or(chunk(b"strh", 4, 4));
            found.codec = handler.map_or("", codec);
            break;
        }
        at = end;
    }
    Some(FileFormat::Avi)
}

/// RIFF chunks in [at, end): type, data start and end.
fn chunks<'f>(file: &'f File, mut at: u64, end: u64) -> impl Iterator<Item = ([u8; 4], u64, u64)> + 'f {
    std::iter::from_fn(move || {
        if at.saturating_add(8) > end {
            return None;
        }
        let head = file.get(at, 8)?;
        let (data, len) = (at + 8, le(&head[4..]));
        at = data.saturating_add(len + (len & 1));
        Some((head[..4].try_into().ok()?, data, data.saturating_add(len)))
    })
}

/// The logical screen's size and the extensions before the first image, among them an XMP application extension.
fn gif(file: &File, found: &mut Found) -> Option<FileFormat> {
    let screen = file.get(6, 5)?;
    dimensions(found, le(&screen[..2]), le(&screen[2..4]));
    let mut at = 13
        + if screen[4] & 0x80 != 0 {
            3 << ((screen[4] & 7) + 1)
        } else {
            0
        };
    while !matches!(file.prefix(at, 1), [0x2c | 0x3b])
        && let Some(&[0x21, label]) = file.get(at, 2)
    {
        at += 2;
        let xmp = label == 0xff && file.get(at, 12) == Some(b"\x0bXMP DataXMP");
        let start = if xmp { at + 12 } else { at };
        // The XMP is raw text, not sub-blocks, but its 258-byte magic trailer makes a sub-block walk end at its end.
        let Some(end) = sub_blocks_end(file, start) else {
            break;
        };
        at = end;
        if xmp && let Some(packet) = file.get(start, at - start) {
            found.xmp.get_or_insert_with(|| packet.to_vec());
        }
    }
    Some(FileFormat::Gif)
}

fn sub_blocks_end(file: &File, mut at: u64) -> Option<u64> {
    loop {
        let len = u64::from(file.get(at, 1)?[0]);
        at += 1 + len;
        if len == 0 {
            return Some(at);
        }
    }
}

/// ISOBMFF boxes in [at, end): type, payload start and end.
pub struct Boxes<'f, 'a> {
    file: &'f File<'a>,
    at: u64,
    end: u64,
}

impl Iterator for Boxes<'_, '_> {
    type Item = ([u8; 4], u64, u64);

    fn next(&mut self) -> Option<Self::Item> {
        if self.at.saturating_add(8) > self.end {
            return None;
        }
        let head = self.file.get(self.at, 8)?;
        let (header, size) = match be(&head[..4]) {
            0 => (8, self.end - self.at),
            1 => (16, be(self.file.get(self.at + 8, 8)?)),
            size => (8, size),
        };
        let start = self.at;
        let end = start
            .checked_add(size)
            .filter(|&end| size >= header && end <= self.end)?;
        self.at = end;
        Some((head[4..].try_into().ok()?, start + header, end))
    }
}

pub fn boxes<'f, 'a>(file: &'f File<'a>, at: u64, end: u64) -> Boxes<'f, 'a> {
    Boxes { file, at, end }
}

/// The item table of a HEIC or AVIF file: its brands say so, and its meta box is read.
pub(super) fn table(file: &File) -> Option<Heif> {
    let (_, start, end) = boxes(file, 0, u64::MAX).next().filter(|b| &b.0 == b"ftyp")?;
    let brands = file.get(start, end - start)?;
    const HEIF: [&[u8]; 8] = [b"mif1", b"msf1", b"heic", b"heix", b"heim", b"heis", b"avif", b"avis"];
    if !brands.chunks(4).any(|brand| HEIF.contains(&brand)) {
        return None;
    }
    let (_, start, end) = boxes(file, end, u64::MAX).find(|b| &b.0 == b"meta")?;
    let mut heif = Heif::default();
    for (kind, start, end) in boxes(file, start + 4, end) {
        let data = || file.get(start, end - start).filter(|d| !d.is_empty());
        match &kind {
            b"pitm" => {
                let id = data().and_then(|d| d.get(4..if d[0] == 0 { 6 } else { 8 }));
                heif.primary = id.map_or(0, be);
            }
            b"iinf" => heif.infos(file, file.prefix(start, 1) == [0], start, end),
            b"iloc" => heif.locations(data().unwrap_or_default()),
            b"iprp" => heif.properties(file, start, end),
            b"iref" => heif.references(file, file.prefix(start, 1) == [0], start, end),
            b"idat" => heif.idat = start,
            b"grpl" => heif.spatial = boxes(file, start, end).any(|b| &b.0 == b"ster"),
            _ => {}
        }
    }
    Some(heif)
}

/// A HEIC or AVIF still: the primary item's ispe, irot and imir, and its Exif and XMP items.
fn heif(file: &File, found: &mut Found) -> Option<FileFormat> {
    let mut heif = table(file)?;
    found.spatial = heif.spatial;
    // A derived image without its own size, such as an ISO gain map's tmap, has its first input's.
    let input = heif
        .inputs
        .iter()
        .find(|(from, _)| *from == heif.primary)
        .map(|(_, to)| *to);
    for item in [Some(heif.primary), input].into_iter().flatten() {
        let properties: Vec<_> = heif.properties_of(item).copied().collect();
        for (kind, start, end) in properties {
            let Some(data) = file.get(start, end - start) else {
                continue;
            };
            match (&kind, data) {
                (b"ispe", _) if data.len() >= 12 => dimensions(found, be(&data[4..8]), be(&data[8..12])),
                (b"irot", [angle, ..]) if item == heif.primary => heif.turns = (4 - (angle & 3)) % 4,
                (b"imir", [axis, ..]) if item == heif.primary => heif.mirror = Some(axis & 1),
                (b"colr", _) if found.transfer == 0 => found.transfer = transfer(data),
                _ => {}
            }
        }
    }
    found.depth = (heif.props.iter().filter(|p| &p.0 == b"auxC")).any(|&(_, start, end)| {
        let at = start.saturating_add(4);
        let urn = file.get(at, end.saturating_sub(at)).unwrap_or_default();
        let urn = urn.split(|&b| b == 0).next().unwrap_or_default();
        [&b"auxid:2"[..], b":depth", b":portraiteffectsmatte"]
            .iter()
            .any(|end| urn.ends_with(end))
    });
    let mut turns = heif.turns;
    // imir's axis 0 exchanges top and bottom, 1 left and right (ISO/IEC 23008-12:2022 §6.5.12, as libheif reads it).
    if heif.mirror == Some(0) {
        turns = (turns + 2) % 4;
    }
    if heif.turns != 0 || heif.mirror.is_some() {
        // Turned clockwise, then mirrored left to right; a top-to-bottom mirror is that plus half a turn.
        found.orientation = Some([[1, 2], [6, 5], [3, 4], [8, 7]][turns as usize][usize::from(heif.mirror.is_some())]);
    }
    if let Some(item) = heif.item(file, |kind, _| kind == b"Exif") {
        let skip = item.get(..4).map_or(u64::MAX, be).saturating_add(4);
        if let Some(tiff) = item.get(usize::try_from(skip).unwrap_or(usize::MAX)..) {
            found.exif = Some(Exif::Item(tiff.to_vec()));
        }
    }
    found.xmp = heif.item(file, |kind, mime| kind == b"mime" && mime == b"application/rdf+xml");
    found.gain_map = heif.gain_map(file);
    // A JPEG thumbnail item in one piece; HEVC- or AV1-coded ones need a decoder of their own.
    for &(thumb, _) in heif.thumbnails.iter().filter(|(_, of)| *of == heif.primary) {
        let jpeg = heif.infos.iter().any(|(id, kind, _)| *id == thumb && kind == b"jpeg");
        if let (true, Some(Location { in_idat, extents, .. })) = (jpeg, heif.locations.iter().find(|l| l.id == thumb))
            && let [(offset, length)] = extents[..]
        {
            let base = if *in_idat { heif.idat } else { 0 };
            found.previews.extend(base.checked_add(offset).map(|at| (at, length)));
        }
    }
    Some(FileFormat::Heif)
}

#[derive(Default)]
pub(super) struct Heif {
    pub(super) primary: u64,
    /// Item id, type and content type.
    pub(super) infos: Vec<(u64, [u8; 4], Vec<u8>)>,
    pub(super) locations: Vec<Location>,
    /// Type, payload start and end; associations number them from 1.
    pub(super) props: Vec<([u8; 4], u64, u64)>,
    /// Item id and property index.
    associations: Vec<(u64, u64)>,
    /// A derived image's id and one of its inputs, in order.
    pub(super) inputs: Vec<(u64, u64)>,
    /// A thumbnail item's id and that of the image it shows.
    pub(super) thumbnails: Vec<(u64, u64)>,
    pub(super) idat: u64,
    spatial: bool,
    turns: u8,
    mirror: Option<u8>,
}

pub(super) struct Location {
    pub(super) id: u64,
    pub(super) in_idat: bool,
    /// Offset and length of each extent.
    pub(super) extents: Vec<(u64, u64)>,
}

impl Heif {
    fn infos(&mut self, file: &File, version_0: bool, start: u64, end: u64) {
        let first = start + if version_0 { 6 } else { 8 };
        for (_, start, end) in boxes(file, first, end).filter(|b| &b.0 == b"infe") {
            let Some(data) = file.get(start, end - start) else {
                continue;
            };
            let (id, rest) = match data.first() {
                Some(2) => (data.get(4..6).map(be), data.get(8..)),
                Some(3) => (data.get(4..8).map(be), data.get(10..)),
                _ => continue,
            };
            let (Some(id), Some(rest)) = (id, rest.filter(|r| r.len() >= 4)) else {
                continue;
            };
            let mut strings = rest[4..].split(|&b| b == 0);
            let mime = strings.nth(1).filter(|_| &rest[..4] == b"mime").unwrap_or_default();
            self.infos
                .push((id, rest[..4].try_into().unwrap_or_default(), mime.to_vec()));
        }
    }

    fn locations(&mut self, data: &[u8]) {
        let mut at = 4;
        let mut take = |len: u8| {
            let value = data.get(at..at + usize::from(len)).map(be);
            at += usize::from(len);
            value
        };
        let version = data.first().copied().unwrap_or(0);
        let (Some(sizes), Some(more)) = (take(1), take(1)) else {
            return;
        };
        let (offset_len, length_len, base_len) = (sizes as u8 >> 4, sizes as u8 & 15, more as u8 >> 4);
        let index_len = if version > 0 { more as u8 & 15 } else { 0 };
        let wide = if version < 2 { 2 } else { 4 };
        let Some(count) = take(wide) else { return };
        // Extents may take no bytes at all: a file declaring more than any writer does would only cost memory.
        let mut budget = 4096;
        for _ in 0..count.min(1024) {
            let (Some(id), method) = (take(wide), if version > 0 { take(2) } else { Some(0) }) else {
                return;
            };
            let (Some(_), Some(base), Some(extents)) = (take(2), take(base_len), take(2)) else {
                return;
            };
            let mut spans = vec![];
            for _ in 0..extents {
                let (true, Some(_), Some(offset), Some(length)) =
                    (budget > 0, take(index_len), take(offset_len), take(length_len))
                else {
                    return;
                };
                budget -= 1;
                spans.push((base.saturating_add(offset), length));
            }
            self.locations.push(Location {
                id,
                in_idat: method.unwrap_or(0) & 15 == 1,
                extents: spans,
            });
        }
    }

    fn properties(&mut self, file: &File, start: u64, end: u64) {
        for (kind, start, end) in boxes(file, start, end) {
            if &kind == b"ipco" {
                self.props = boxes(file, start, end).collect();
            } else if let (b"ipma", Some(data)) = (&kind, file.get(start, end - start)) {
                let (version, wide) = (
                    data.first().copied().unwrap_or(0),
                    data.get(3).is_some_and(|f| f & 1 == 1),
                );
                let mut at = 8;
                for _ in 0..data.get(4..8).map_or(0, be) {
                    let id_len = if version < 1 { 2 } else { 4 };
                    let (Some(id), Some(&count)) = (data.get(at..at + id_len), data.get(at + id_len)) else {
                        return;
                    };
                    at += id_len + 1;
                    for _ in 0..count {
                        let index = if wide {
                            data.get(at..at + 2).map(|i| be(i) & 0x7fff)
                        } else {
                            data.get(at).map(|&i| u64::from(i & 0x7f))
                        };
                        let Some(index) = index else { return };
                        self.associations.push((be(id), index));
                        at += if wide { 2 } else { 1 };
                    }
                }
            }
        }
    }

    fn references(&mut self, file: &File, version_0: bool, start: u64, end: u64) {
        let size: usize = if version_0 { 2 } else { 4 };
        let width = size as u64;
        for (kind, start, _) in boxes(file, start.saturating_add(4), end) {
            let list = match &kind {
                b"dimg" => &mut self.inputs,
                b"thmb" => &mut self.thumbnails,
                _ => continue,
            };
            let Some(ids) = file.get(start, 2 * width + 2) else {
                continue;
            };
            let (from, rest) = ids.split_at(size);
            // Readers of one input want the first; a grid's tiles are all the box lists, as many as it holds.
            let count = if &kind == b"dimg" {
                be(rest.get(..2).unwrap_or_default()).clamp(1, MAX_INPUTS)
            } else {
                1
            };
            for i in 0..count {
                let at = start
                    .saturating_add(width.saturating_add(2))
                    .saturating_add(i.saturating_mul(width));
                if let Some(to) = file.get(at, width) {
                    list.push((be(from), be(to)));
                }
            }
        }
    }

    /// An ISO gain map is a tmap item; Apple's is an auxiliary image of its own type.
    fn gain_map(&self, file: &File) -> bool {
        self.infos.iter().any(|(_, kind, _)| kind == b"tmap")
            || self.props.iter().filter(|p| &p.0 == b"auxC").any(|&(_, start, end)| {
                let data = file.get(start, end.saturating_sub(start));
                data.and_then(|d| d.get(4..))
                    .is_some_and(|aux_type| aux_type.starts_with(APPLE_GAIN_MAP))
            })
    }

    /// The properties the item has, in the order of its associations.
    pub(super) fn properties_of(&self, item: u64) -> impl Iterator<Item = &([u8; 4], u64, u64)> {
        let indices = self.associations.iter().filter(move |(id, _)| *id == item);
        indices.filter_map(|&(_, i)| self.props.get(usize::try_from(i).ok()?.checked_sub(1)?))
    }

    /// The bytes of the first item whose type and content type match, at most the longest span: extents may repeat.
    fn item(&self, file: &File, wanted: impl Fn(&[u8; 4], &[u8]) -> bool) -> Option<Vec<u8>> {
        let (id, ..) = self.infos.iter().find(|(_, kind, mime)| wanted(kind, mime))?;
        self.bytes(file, *id)
    }

    /// The bytes of the item, at most the longest span.
    pub(super) fn bytes(&self, file: &File, id: u64) -> Option<Vec<u8>> {
        let location = self.locations.iter().find(|l| l.id == id)?;
        let base = if location.in_idat { self.idat } else { 0 };
        let mut bytes = vec![];
        for &(offset, length) in &location.extents {
            (bytes.len() as u64).checked_add(length).filter(|&n| n <= MAX_SPAN)?;
            bytes.extend_from_slice(file.get(base.checked_add(offset)?, length)?);
        }
        Some(bytes)
    }
}
