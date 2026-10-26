//! Conformance cases of ReadMetadata: one per kind of evidence and container that the media corpus does not already
//! pin, with byte builders for TIFF, JPEG, IIM, XMP and HEIF.

use super::{Outcome, call_case};
use md5::{Digest, Md5};
use photolib_kernel::proto::kernel::v1::{
    ByteSpan, ContainerItem, FileFormat, FileRange, GeoPoint, ImageRegion, KeywordPath, Method, MotionPhotoMarkers,
    Pace, Panorama, ReadMetadataRequest, ReadMetadataResponse, StereoMode,
};
use photolib_kernel::proto::model::v1::{CaptureTime, CaptureTimePrecision};
use prost::Message;
use serde_json::Value;

pub enum Field {
    Text(&'static str),
    Short(u16),
    Long(u32),
    Byte(u8),
    Rationals(&'static [(u32, u32)]),
    Bytes(Vec<u8>),
    /// A sub-IFD behind a pointer.
    Ifd(Vec<(u16, Field)>),
}

pub const EXIF_IFD: u16 = 0x8769;
pub const GPS_IFD: u16 = 0x8825;

/// A TIFF block with these IFD0 entries.
pub fn tiff(big_endian: bool, entries: Vec<(u16, Field)>) -> Vec<u8> {
    let mut out = Vec::from(if big_endian {
        *b"MM\0*\0\0\0\x08"
    } else {
        *b"II*\0\x08\0\0\0"
    });
    ifd(&mut out, entries, big_endian);
    out
}

fn ifd(out: &mut Vec<u8>, mut entries: Vec<(u16, Field)>, big_endian: bool) {
    let n = |value: usize, len: usize| {
        let bytes = &(value as u64).to_be_bytes()[8 - len..];
        if big_endian {
            bytes.to_vec()
        } else {
            bytes.iter().rev().copied().collect()
        }
    };
    entries.sort_by_key(|(tag, _)| *tag);
    let table = out.len();
    out.extend(n(entries.len(), 2));
    out.resize(table + 2 + 12 * entries.len() + 4, 0);
    for (i, (tag, field)) in entries.into_iter().enumerate() {
        let (kind, count, value) = match field {
            Field::Text(text) => (2, text.len() + 1, format!("{text}\0").into_bytes()),
            Field::Short(v) => (3, 1, n(v.into(), 2)),
            Field::Long(v) => (4, 1, n(v as usize, 4)),
            Field::Byte(v) => (1, 1, vec![v]),
            Field::Rationals(parts) => {
                let bytes = parts
                    .iter()
                    .flat_map(|&(a, b)| [n(a as usize, 4), n(b as usize, 4)].concat());
                (5, parts.len(), bytes.collect())
            }
            Field::Bytes(bytes) => (7, bytes.len(), bytes),
            Field::Ifd(sub) => {
                let at = out.len();
                ifd(out, sub, big_endian);
                (4, 1, n(at, 4))
            }
        };
        let value = if value.len() <= 4 {
            [value.as_slice(), &[0; 4][value.len()..]].concat()
        } else {
            out.extend(&value);
            n(out.len() - value.len(), 4)
        };
        let entry = [n(tag.into(), 2), n(kind, 2), n(count, 4), value].concat();
        out[table + 2 + 12 * i..][..12].copy_from_slice(&entry);
    }
}

/// The TIFF block, little-endian, with an IFD1 of these entries after its IFD0.
fn with_ifd1(mut out: Vec<u8>, entries: Vec<(u16, Field)>) -> Vec<u8> {
    let count = usize::from(u16::from_le_bytes([out[8], out[9]]));
    let at = out.len() as u32;
    out[10 + 12 * count..][..4].copy_from_slice(&at.to_le_bytes());
    ifd(&mut out, entries, false);
    out
}

/// The entries of an IFD that points to a JPEG at `at` of `length` bytes.
fn jpeg_at(at: usize, length: usize) -> Vec<(u16, Field)> {
    vec![(0x0201, Field::Long(at as u32)), (0x0202, Field::Long(length as u32))]
}

/// A HEIC whose primary HEVC item 1 has a JPEG thumbnail item 2 in the mdat.
fn heic_thumbnail(thumbnail: &[u8]) -> (Vec<u8>, u64) {
    let infe = |id: u8, kind: &[u8; 4]| full(b"infe", 2, &[&[0, id, 0, 0], &kind[..], b"\0"].concat());
    let meta = |at: u32| {
        let iloc = [
            &[0x44, 0, 0, 1, 0, 2, 0, 0, 0, 1][..],
            &at.to_be_bytes(),
            &(thumbnail.len() as u32).to_be_bytes(),
        ]
        .concat();
        let boxes = [
            full(b"pitm", 0, &[0, 1]),
            full(b"iinf", 0, &[vec![0, 2], infe(1, b"hvc1"), infe(2, b"jpeg")].concat()),
            full(b"iref", 0, &bx(b"thmb", &[0, 2, 0, 1, 0, 1])),
            full(b"iloc", 0, &iloc),
        ];
        full(b"meta", 0, &boxes.concat())
    };
    let ftyp = bx(b"ftyp", b"heic\0\0\0\0mif1heic");
    let at = (ftyp.len() + meta(0).len() + 8) as u32;
    ([ftyp, meta(at), bx(b"mdat", thumbnail)].concat(), u64::from(at))
}

/// A JPEG of these marker segments, without image data.
pub fn jpeg(segments: &[(u8, Vec<u8>)]) -> Vec<u8> {
    let mut out = vec![0xff, 0xd8];
    for (marker, payload) in segments {
        out.extend([0xff, *marker]);
        out.extend(u16::try_from(payload.len() + 2).unwrap().to_be_bytes());
        out.extend(payload);
    }
    out.extend([0xff, 0xd9]);
    out
}

pub fn exif(tiff: Vec<u8>) -> (u8, Vec<u8>) {
    (0xe1, [b"Exif\0\0".as_slice(), &tiff].concat())
}

fn xmp(body: &str) -> (u8, Vec<u8>) {
    (
        0xe1,
        [b"http://ns.adobe.com/xap/1.0/\0".as_slice(), packet(body).as_bytes()].concat(),
    )
}

fn frame(width: u16, height: u16) -> (u8, Vec<u8>) {
    let (h, w) = (height.to_be_bytes(), width.to_be_bytes());
    (0xc0, vec![8, h[0], h[1], w[0], w[1], 1, 1, 0x11, 0])
}

/// An APP2 segment with a Multi-Picture Format index (little-endian) of two pictures: the first, the file's, and the
/// second, `second_size` bytes `second_offset` after the index's byte-order mark.
fn mpf(second_size: u32, second_offset: u32) -> (u8, Vec<u8>) {
    let mut tiff = b"II*\0\x08\0\0\0\x03\0".to_vec();
    tiff.extend([0x00, 0xb0, 7, 0, 4, 0, 0, 0]);
    tiff.extend(b"0100");
    tiff.extend([0x01, 0xb0, 4, 0, 1, 0, 0, 0, 2, 0, 0, 0]);
    tiff.extend([0x02, 0xb0, 7, 0, 32, 0, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0]);
    tiff.extend(0x2003_0000u32.to_le_bytes());
    tiff.extend([0; 12]);
    tiff.extend(0u32.to_le_bytes());
    tiff.extend(second_size.to_le_bytes());
    tiff.extend(second_offset.to_le_bytes());
    tiff.extend([0; 4]);
    (0xe2, [b"MPF\0".as_slice(), &tiff].concat())
}

fn packet(body: &str) -> String {
    format!(
        r#"<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">{body}</rdf:RDF></x:xmpmeta><?xpacket end="w"?>"#
    )
}

fn iim(records: &[(u8, u8, &str)]) -> Vec<u8> {
    let record = |&(record, dataset, text): &(u8, u8, &str)| {
        [
            &[0x1c, record, dataset][..],
            &(text.len() as u16).to_be_bytes(),
            text.as_bytes(),
        ]
        .concat()
    };
    records.iter().flat_map(record).collect()
}

/// An APP13 segment of Photoshop image resources.
fn photoshop(resources: &[(u16, &[u8])]) -> (u8, Vec<u8>) {
    let mut out = b"Photoshop 3.0\0".to_vec();
    for (id, data) in resources {
        out.extend(b"8BIM".iter().chain(&id.to_be_bytes()).chain(&[0, 0]));
        out.extend((data.len() as u32).to_be_bytes().iter().chain(*data));
        out.resize(out.len() + data.len() % 2, 0);
    }
    (0xed, out)
}

pub fn bx(kind: &[u8; 4], payload: &[u8]) -> Vec<u8> {
    [&(8 + payload.len() as u32).to_be_bytes(), kind, payload].concat()
}

fn full(kind: &[u8; 4], version: u8, payload: &[u8]) -> Vec<u8> {
    bx(kind, &[&[version, 0, 0, 0], payload].concat())
}

/// A HEIC whose primary item 1 has these properties, followed by an Exif item 2 and an XMP item 3.
fn heic(properties: &[Vec<u8>], exif: &[u8], xmp: &str) -> Vec<u8> {
    let items = [
        [&[0, 0, 0, 6], b"Exif\0\0".as_slice(), exif].concat(),
        xmp.as_bytes().to_vec(),
    ];
    let infe = |id: u8, kind: &[u8; 4], mime: &str| {
        full(
            b"infe",
            2,
            &[&[0, id, 0, 0], &kind[..], b"\0", mime.as_bytes()].concat(),
        )
    };
    let meta = |at: usize| {
        let mut iloc = vec![0x44, 0, 0, 2];
        for (id, (item, at)) in (2u8..).zip(items.iter().zip([at, at + items[0].len()])) {
            iloc.extend([0, id, 0, 0, 0, 1]);
            iloc.extend(
                (at as u32)
                    .to_be_bytes()
                    .iter()
                    .chain(&(item.len() as u32).to_be_bytes()),
            );
        }
        let associations: Vec<u8> = (1..=properties.len() as u8).collect();
        let infos = [
            vec![0, 3],
            infe(1, b"hvc1", ""),
            infe(2, b"Exif", ""),
            infe(3, b"mime", "application/rdf+xml\0"),
        ];
        let ipma = [&[0, 0, 0, 1, 0, 1, associations.len() as u8][..], &associations].concat();
        let iprp = bx(
            b"iprp",
            &[bx(b"ipco", &properties.concat()), full(b"ipma", 0, &ipma)].concat(),
        );
        let boxes = [
            full(b"pitm", 0, &[0, 1]),
            full(b"iinf", 0, &infos.concat()),
            full(b"iloc", 0, &iloc),
            iprp,
        ];
        full(b"meta", 0, &boxes.concat())
    };
    let ftyp = bx(b"ftyp", b"heic\0\0\0\0mif1heic");
    let start = ftyp.len() + meta(0).len() + 8;
    [ftyp, meta(start), bx(b"mdat", &items.concat())].concat()
}

/// A movie whose first track is video in this sample entry, turned by a matrix with this a, b, c and d, and ends with
/// the track's boxes; the moov ends with its boxes. mvhd is version 1, its creation time 2023-06-01T15:30:00 and its
/// length 2.5 s.
pub fn movie(entry: Vec<u8>, [a, b, c, d]: [i32; 4], track: &[Vec<u8>], boxes: &[Vec<u8>]) -> Vec<u8> {
    let mvhd = [
        &3_768_478_200u64.to_be_bytes()[..],
        &[0; 8],
        &600u32.to_be_bytes(),
        &1500u64.to_be_bytes(),
    ];
    let matrix = [a, b, 0, c, d].map(|v| (v << 16).to_be_bytes()).concat();
    let tkhd = full(b"tkhd", 0, &[&[0; 36][..], &matrix, &[0; 24]].concat());
    let hdlr = full(b"hdlr", 0, b"\0\0\0\0vide\0\0\0\0\0\0\0\0\0\0\0\0\0");
    let stbl = bx(b"stbl", &full(b"stsd", 0, &[&1u32.to_be_bytes()[..], &entry].concat()));
    let mdia = bx(b"mdia", &[hdlr, bx(b"minf", &stbl)].concat());
    let moov = [
        full(b"mvhd", 1, &[&mvhd.concat()[..], &[0; 80]].concat()),
        bx(b"trak", &[&[tkhd, mdia][..], track].concat().concat()),
    ];
    [
        bx(b"ftyp", b"qt  \0\0\0\0qt  "),
        bx(b"moov", &[&moov[..], boxes].concat().concat()),
    ]
    .concat()
}

/// A visual sample entry of this size with these boxes.
pub fn sample(fourcc: &[u8; 4], width: u16, height: u16, boxes: &[Vec<u8>]) -> Vec<u8> {
    let size = [width.to_be_bytes(), height.to_be_bytes()].concat();
    bx(fourcc, &[&[0; 24][..], &size, &[0; 50], &boxes.concat()].concat())
}

/// QuickTime metadata: keys and their UTF-8 values, in a meta without a version, as Apple writes it.
pub fn keys(pairs: &[(&str, &str)]) -> Vec<u8> {
    let names: Vec<u8> = pairs.iter().flat_map(|(key, _)| bx(b"mdta", key.as_bytes())).collect();
    let values: Vec<u8> = (1u32..)
        .zip(pairs)
        .flat_map(|(i, (_, value))| {
            bx(
                &i.to_be_bytes(),
                &bx(b"data", &[&[0, 0, 0, 1, 0, 0, 0, 0][..], value.as_bytes()].concat()),
            )
        })
        .collect();
    let hdlr = full(b"hdlr", 0, b"\0\0\0\0mdta\0\0\0\0\0\0\0\0\0\0\0\0\0");
    let keys = full(b"keys", 0, &[&(pairs.len() as u32).to_be_bytes()[..], &names].concat());
    bx(b"meta", &[hdlr, keys, bx(b"ilst", &values)].concat())
}

/// QuickTime user data text: its length and language, then the text.
fn text(kind: &[u8; 4], text: &str) -> Vec<u8> {
    bx(
        kind,
        &[&(text.len() as u16).to_be_bytes()[..], &[0x15, 0xc7], text.as_bytes()].concat(),
    )
}

/// Spherical Video V1's uuid box with these GSpherical elements.
fn spherical_v1(elements: &str) -> Vec<u8> {
    let xml = format!(
        r#"<?xml version="1.0"?><rdf:SphericalVideo xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/">{elements}</rdf:SphericalVideo>"#
    );
    let uuid = b"\xff\xcc\x82\x63\xf8\x55\x4a\x93\x88\x14\x58\x7a\x02\x52\x1f\xdd";
    bx(b"uuid", &[&uuid[..], xml.as_bytes()].concat())
}

/// A motion photo's XMP with a Container directory of these items, and the markers it gives.
fn directory(items: &[(&str, &str, usize)]) -> ((u8, Vec<u8>), MotionPhotoMarkers) {
    let rows: String = items
        .iter()
        .map(|(mime, semantic, length)| format!(r#"<rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="{mime}" Item:Semantic="{semantic}" Item:Length="{length}"/></rdf:li>"#))
        .collect();
    let packet = xmp(&format!(
        r#"<rdf:Description xmlns:Camera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/" Camera:MotionPhoto="1"><Container:Directory><rdf:Seq>{rows}</rdf:Seq></Container:Directory></rdf:Description>"#
    ));
    let items = items.iter().map(|&(mime, semantic, length)| ContainerItem {
        mime: mime.into(),
        semantic: semantic.into(),
        length_bytes: length as u64,
        padding_bytes: 0,
    });
    (
        packet,
        MotionPhotoMarkers {
            motion_photo: true,
            items: items.collect(),
            ..Default::default()
        },
    )
}

/// Samsung's SEF trailer of these named blocks: the blocks, a SEFH directory counting back to each, its length, SEFT.
fn sef(blocks: &[(&str, &[u8])]) -> Vec<u8> {
    let (mut body, mut directory) = (vec![], vec![]);
    for (kind, (name, data)) in (0x0a01u16..).zip(blocks) {
        let block = [
            &[0, 0][..],
            &kind.to_le_bytes(),
            &(name.len() as u32).to_le_bytes(),
            name.as_bytes(),
            data,
        ]
        .concat();
        directory.push((kind, body.len(), block.len()));
        body.extend(block);
    }
    let mut sefh = [
        &b"SEFH"[..],
        &107u32.to_le_bytes(),
        &(blocks.len() as u32).to_le_bytes(),
    ]
    .concat();
    for (kind, at, length) in directory {
        let back = (body.len() - at) as u32;
        sefh.extend(
            [
                &[0, 0][..],
                &kind.to_le_bytes(),
                &back.to_le_bytes(),
                &(length as u32).to_le_bytes(),
            ]
            .concat(),
        );
    }
    [
        body,
        sefh.clone(),
        (sefh.len() as u32).to_le_bytes().to_vec(),
        b"SEFT".to_vec(),
    ]
    .concat()
}

fn time(source: &str, local: &str, offset: Option<i32>, precision: CaptureTimePrecision) -> CaptureTime {
    CaptureTime {
        local_datetime: local.into(),
        offset_minutes: offset,
        precision: precision.into(),
        source: source.into(),
        ..CaptureTime::default()
    }
}

fn strings(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|t| t.to_string()).collect()
}

pub fn metadata_cases() -> Vec<Value> {
    use CaptureTimePrecision::{Millisecond, Minute, Month, Second};
    let read = |name: &str, ranges: Vec<(u64, Vec<u8>)>, size: usize, response: ReadMetadataResponse| {
        let ranges = ranges
            .into_iter()
            .map(|(offset, data)| FileRange { offset, data })
            .collect();
        let request = ReadMetadataRequest {
            ranges,
            size: size as u64,
        }
        .encode_to_vec();
        let outcome: Outcome = Ok(response.encode_to_vec());
        call_case(name, Method::ReadMetadata as u32, request, outcome)
    };
    let case = |name: &str, ranges, response| read(name, ranges, 0, response);
    let file = |name: &str, data: Vec<u8>, response| case(name, vec![(0, data)], response);
    let whole = |name: &str, data: Vec<u8>, response| read(name, vec![(0, data.clone())], data.len(), response);
    let of = |format: FileFormat| ReadMetadataResponse {
        format: format.into(),
        ..Default::default()
    };
    let jpg = || of(FileFormat::Jpeg);
    let dated = |source, local, offset| time(source, local, offset, Second);
    let described = |text: &str| {
        xmp(&format!(
            r#"<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:description><rdf:Alt><rdf:li xml:lang="x-default">{text}</rdf:li></rdf:Alt></dc:description><dc:subject><rdf:Bag><rdf:li>{text}</rdf:li></rdf:Bag></dc:subject></rdf:Description>"#
        ))
    };
    let older = iim(&[(2, 120, "Morning"), (2, 25, "Morning")]);
    let digest = Md5::digest(&older).to_vec();
    let camera = jpeg(&[
        exif(tiff(
            false,
            vec![
                (0x010f, Field::Text("Canon")),
                (0x0110, Field::Text("Canon EOS R5")),
                (0x0112, Field::Short(6)),
            ],
        )),
        frame(8192, 5464),
    ]);
    let canon = ReadMetadataResponse {
        width: 8192,
        height: 5464,
        orientation: 6,
        make: "Canon".into(),
        model: "Canon EOS R5".into(),
        ..jpg()
    };
    let exif_end = 6 + u64::from(u16::from_be_bytes([camera[4], camera[5]])) - 2;
    let film = |width, height, codec: &str| ReadMetadataResponse {
        width,
        height,
        times: vec![dated("quicktime:CreateDate", "2023-06-01T15:30:00", None)],
        duration_ms: 2500,
        codec: codec.into(),
        ..of(FileFormat::Quicktime)
    };
    let sphere = |projection: Option<&str>, stereo: StereoMode| ReadMetadataResponse {
        panorama: projection.map(|p| Panorama {
            projection: p.into(),
            ..Default::default()
        }),
        stereo_mode: stereo.into(),
        ..film(3840, 1920, "h264")
    };
    let video = [bx(b"ftyp", b"mp42\0\0\0\0isommp42"), bx(b"mdat", &[0; 32])].concat();
    let gain = jpeg(&[]);
    let (motion_xmp, markers) = directory(&[
        ("image/jpeg", "Primary", 0),
        ("image/jpeg", "GainMap", gain.len()),
        ("video/mp4", "MotionPhoto", video.len()),
    ]);
    let still = jpeg(&[motion_xmp]);
    let before = (still.len() + gain.len()) as u64;
    let photo = [still.clone(), gain.clone(), video.clone()].concat();
    let span = ByteSpan {
        offset: before,
        length: video.len() as u64,
    };
    let samsung = jpeg(&[exif(tiff(false, vec![(0x010f, Field::Text("samsung"))]))]);
    let trailer = sef(&[("Image_UTC_Data", b"1680000000000"), ("MotionPhoto_Data", &video)]);
    let in_trailer = samsung.len() + (8 + 14 + 13) + 8 + 16;
    let track = |handler: &[u8; 4], timescale: u32, stts: &[(u32, u32)], stsd: Vec<u8>| {
        let mdhd = full(b"mdhd", 0, &[&[0; 8][..], &timescale.to_be_bytes(), &[0; 8]].concat());
        let hdlr = full(b"hdlr", 0, &[&[0; 4][..], handler, &[0; 12]].concat());
        let entries: Vec<u8> = stts
            .iter()
            .flat_map(|(n, d)| [n.to_be_bytes(), d.to_be_bytes()].concat())
            .collect();
        let stts = full(b"stts", 0, &[&(stts.len() as u32).to_be_bytes()[..], &entries].concat());
        let stbl = bx(
            b"stbl",
            &[full(b"stsd", 0, &[&1u32.to_be_bytes()[..], &stsd].concat()), stts].concat(),
        );
        bx(b"trak", &bx(b"mdia", &[mdhd, hdlr, bx(b"minf", &stbl)].concat()))
    };
    // A movie of one 1080p video track at this frame rate, whose capture rate Android's key says.
    let paced = |fps: u32, capture: &str| {
        let video = track(b"vide", fps * 10, &[(fps, 10)], sample(b"avc1", 1920, 1080, &[]));
        let moov = [video, keys(&[("com.android.capture.fps", capture)])].concat();
        [bx(b"ftyp", b"isom\0\0\0\0isom"), bx(b"moov", &moov)].concat()
    };
    let paced_film = |fps: u32, pace: Pace| ReadMetadataResponse {
        width: 1920,
        height: 1080,
        codec: "h264".into(),
        frame_rate: f64::from(fps),
        pace: pace.into(),
        ..of(FileFormat::Quicktime)
    };
    vec![
        file("a JPEG's frame size and its EXIF camera and orientation", camera.clone(), canon.clone()),
        file(
            "EXIF dates with their sub-seconds and offsets, big-endian",
            jpeg(&[exif(tiff(true, vec![
                (0x0132, Field::Text("2019:05:10 08:00:00")),
                (EXIF_IFD, Field::Ifd(vec![
                    (0x9003, Field::Text("2019:05:09 15:47:33")),
                    (0x9291, Field::Text("25")),
                    (0x9011, Field::Text("+02:00")),
                    (0x9004, Field::Text("2019:05:09 15:47:34")),
                    (0x9010, Field::Text("-05:30")),
                ])),
            ]))]),
            ReadMetadataResponse {
                times: vec![
                    time("exif:DateTimeOriginal", "2019-05-09T15:47:33.250", Some(120), Millisecond),
                    dated("exif:CreateDate", "2019-05-09T15:47:34", None),
                    dated("exif:ModifyDate", "2019-05-10T08:00:00", Some(-330)),
                ],
                ..jpg()
            },
        ),
        file(
            "dates as written: a zero date and an impossible one pass, text that is no date has no value",
            jpeg(&[exif(tiff(false, vec![
                (EXIF_IFD, Field::Ifd(vec![
                    (0x9003, Field::Text("0000:00:00 00:00:00")),
                    (0x9004, Field::Text("2019:13:45 25:61:61")),
                ])),
                (0x0132, Field::Text("garbage")),
            ]))]),
            ReadMetadataResponse {
                times: vec![
                    dated("exif:DateTimeOriginal", "0000-00-00T00:00:00", None),
                    dated("exif:CreateDate", "2019-13-45T25:61:61", None),
                    time("exif:ModifyDate", "", None, CaptureTimePrecision::Unspecified),
                ],
                ..jpg()
            },
        ),
        file(
            "GPS south and west, below sea level, with the fix's UTC time to the millisecond",
            jpeg(&[exif(tiff(false, vec![(GPS_IFD, Field::Ifd(vec![
                (0x0001, Field::Text("S")),
                (0x0002, Field::Rationals(&[(33, 1), (45, 1), (0, 1)])),
                (0x0003, Field::Text("W")),
                (0x0004, Field::Rationals(&[(151, 1), (15, 1), (0, 1)])),
                (0x0005, Field::Byte(1)),
                (0x0006, Field::Rationals(&[(585, 10)])),
                (0x0007, Field::Rationals(&[(5, 1), (47, 1), (335, 10)])),
                (0x001d, Field::Text("2019:05:09")),
            ]))]))]),
            ReadMetadataResponse {
                location: Some(GeoPoint { latitude: -33.75, longitude: -151.25, altitude_m: Some(-58.5) }),
                times: vec![time("exif:GPSDateTime", "2019-05-09T05:47:33.500", Some(0), Millisecond)],
                ..jpg()
            },
        ),
        file(
            "GPS at 0,0 is no position",
            jpeg(&[exif(tiff(false, vec![(GPS_IFD, Field::Ifd(vec![
                (0x0001, Field::Text("N")),
                (0x0002, Field::Rationals(&[(0, 1), (0, 1), (0, 1)])),
                (0x0003, Field::Text("E")),
                (0x0004, Field::Rationals(&[(0, 1), (0, 1), (0, 1)])),
            ]))]))]),
            jpg(),
        ),
        file(
            "a DNG: the original's size in a SubIFD behind a reduced IFD0, and its XMP and IIM tags",
            tiff(false, vec![
                (0x00fe, Field::Long(1)),
                (0x0100, Field::Long(256)),
                (0x0101, Field::Long(171)),
                (0x010f, Field::Text("Leica Camera AG")),
                (0x014a, Field::Ifd(vec![
                    (0x00fe, Field::Long(0)),
                    (0x0100, Field::Long(6000)),
                    (0x0101, Field::Long(4000)),
                ])),
                (0x02bc, Field::Bytes(packet(r#"<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>"#).into_bytes())),
                (0x83bb, Field::Bytes(iim(&[(2, 25, "leica")]))),
            ]),
            ReadMetadataResponse {
                width: 6000,
                height: 4000,
                make: "Leica Camera AG".into(),
                rating: Some(4),
                keywords: strings(&["leica"]),
                ..of(FileFormat::Tiff)
            },
        ),
        file(
            "BigTIFF",
            [
                &b"II+\0\x08\0\0\0\x10\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0"[..],
                b"\x00\x01\x04\0\x01\0\0\0\0\0\0\0\x40\x01\0\0\0\0\0\0",
                b"\x01\x01\x04\0\x01\0\0\0\0\0\0\0\xf0\0\0\0\0\0\0\0",
                b"\x0f\x01\x02\0\x06\0\0\0\0\0\0\0Canon\0\0\0",
                &[0; 8],
            ]
            .concat(),
            ReadMetadataResponse { width: 320, height: 240, make: "Canon".into(), ..of(FileFormat::Tiff) },
        ),
        file(
            "XMP: Dublin Core, rating, label, place, dates, GPS and camera, whatever the prefixes",
            jpeg(&[xmp(r#"<rdf:Description rdf:about="" xmlns:d="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:ps="http://ns.adobe.com/photoshop/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmp:Rating="-1" xmp:Label="Red" ps:City="Paris" ps:DateCreated="2019-05" exif:GPSLatitude="48,30N" exif:GPSLongitude="2,15W" tiff:Make="Canon">
<d:title><rdf:Alt><rdf:li xml:lang="fr">Lac</rdf:li><rdf:li xml:lang="x-default">Lake &amp; hills</rdf:li></rdf:Alt></d:title>
<d:subject><rdf:Bag><rdf:li>lake</rdf:li><rdf:li>AC/DC</rdf:li></rdf:Bag></d:subject>
<d:creator><rdf:Seq><rdf:li>Alice</rdf:li><rdf:li>Bob</rdf:li></rdf:Seq></d:creator>
<d:rights><rdf:Alt><rdf:li xml:lang="x-default">© Alice</rdf:li></rdf:Alt></d:rights>
<ps:Country>France</ps:Country><ps:State><![CDATA[Île-de-France]]></ps:State>
<exif:DateTimeOriginal>2019-05-09T15:47:33.25+02:00</exif:DateTimeOriginal><xmp:CreateDate>2019-05-09T13:47Z</xmp:CreateDate>
</rdf:Description>"#)]),
            ReadMetadataResponse {
                make: "Canon".into(),
                location: Some(GeoPoint { latitude: 48.5, longitude: -2.25, altitude_m: None }),
                times: vec![
                    time("xmp-exif:DateTimeOriginal", "2019-05-09T15:47:33.250", Some(120), Millisecond),
                    time("xmp-photoshop:DateCreated", "2019-05", None, Month),
                    time("xmp-xmp:CreateDate", "2019-05-09T13:47", Some(0), Minute),
                ],
                title: "Lake & hills".into(),
                keywords: strings(&["lake", "AC/DC"]),
                rating: Some(-1),
                label: "Red".into(),
                creators: strings(&["Alice", "Bob"]),
                copyright: "© Alice".into(),
                city: "Paris".into(),
                state: "Île-de-France".into(),
                country: "France".into(),
                ..jpg()
            },
        ),
        file(
            "hierarchical keywords from Lightroom and digiKam, across descriptions, without duplicates",
            jpeg(&[xmp(r#"<rdf:Description xmlns:lr="http://ns.adobe.com/lightroom/1.0/"><lr:hierarchicalSubject><rdf:Bag><rdf:li>Places|France|Paris</rdf:li><rdf:li>People|Alice</rdf:li></rdf:Bag></lr:hierarchicalSubject></rdf:Description><rdf:Description xmlns:digiKam="http://www.digikam.org/ns/1.0/"><digiKam:TagsList><rdf:Seq><rdf:li>Places/France/Paris</rdf:li><rdf:li>Events/2019</rdf:li></rdf:Seq></digiKam:TagsList></rdf:Description>"#)]),
            ReadMetadataResponse {
                keyword_paths: [&["Places", "France", "Paris"][..], &["People", "Alice"], &["Events", "2019"]]
                    .iter()
                    .map(|nodes| KeywordPath { nodes: strings(nodes) })
                    .collect(),
                ..jpg()
            },
        ),
        file(
            "an mwg-rs face from its centre to its top-left corner, turned as the EXIF orientation shows it",
            jpeg(&[exif(tiff(false, vec![(0x0112, Field::Short(6))])), xmp(r#"<rdf:Description xmlns:mwg-rs="http://www.metadataworkinggroup.com/schemas/regions/" xmlns:stArea="http://ns.adobe.com/xmp/sType/Area#" xmlns:stDim="http://ns.adobe.com/xap/1.0/sType/Dimensions#"><mwg-rs:Regions rdf:parseType="Resource"><mwg-rs:AppliedToDimensions stDim:w="4000" stDim:h="3000" stDim:unit="pixel"/><mwg-rs:RegionList><rdf:Bag>
<rdf:li><rdf:Description mwg-rs:Name="Alice" mwg-rs:Type="Face"><mwg-rs:Area stArea:x="0.5" stArea:y="0.25" stArea:w="0.25" stArea:h="0.125" stArea:unit="normalized"/></rdf:Description></rdf:li>
<rdf:li rdf:parseType="Resource"><mwg-rs:Type>Pet</mwg-rs:Type><mwg-rs:Area stArea:x="10" stArea:y="10" stArea:w="5" stArea:h="5" stArea:unit="pixel"/></rdf:li>
</rdf:Bag></mwg-rs:RegionList></mwg-rs:Regions></rdf:Description>"#)]),
            ReadMetadataResponse {
                orientation: 6,
                regions: vec![ImageRegion {
                    name: "Alice".into(),
                    r#type: "Face".into(),
                    x: 0.6875,
                    y: 0.375,
                    width: 0.125,
                    height: 0.25,
                }],
                ..jpg()
            },
        ),
        file(
            "a cropped photo sphere's GPano",
            jpeg(&[xmp(r#"<rdf:Description xmlns:GPano="http://ns.google.com/photos/1.0/panorama/" GPano:ProjectionType="equirectangular" GPano:UsePanoramaViewer="True" GPano:FullPanoWidthPixels="8192" GPano:FullPanoHeightPixels="4096" GPano:CroppedAreaLeftPixels="0" GPano:CroppedAreaTopPixels="1024" GPano:CroppedAreaImageWidthPixels="8192" GPano:CroppedAreaImageHeightPixels="2048"/>"#)]),
            ReadMetadataResponse {
                panorama: Some(Panorama {
                    projection: "equirectangular".into(),
                    use_panorama_viewer: Some(true),
                    full_width: 8192,
                    full_height: 4096,
                    cropped_left: 0,
                    cropped_top: 1024,
                    cropped_width: 8192,
                    cropped_height: 2048,
                    pose_heading_degrees: None,
                }),
                ..jpg()
            },
        ),
        file(
            "GPano's compass heading, west as 270 degrees",
            jpeg(&[xmp(r#"<rdf:Description xmlns:GPano="http://ns.google.com/photos/1.0/panorama/" GPano:ProjectionType="equirectangular" GPano:PoseHeadingDegrees="-90"/>"#)]),
            ReadMetadataResponse {
                panorama: Some(Panorama {
                    projection: "equirectangular".into(),
                    pose_heading_degrees: Some(270.0),
                    ..Default::default()
                }),
                ..jpg()
            },
        ),
        file(
            "a motion photo's Camera and Container markers",
            jpeg(&[xmp(r#"<rdf:Description xmlns:Camera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" xmlns:Item="http://ns.google.com/photos/1.0/container/item/" Camera:MotionPhoto="1" Camera:MotionPhotoVersion="1" Camera:MotionPhotoPresentationTimestampUs="1500000"><Container:Directory><rdf:Seq>
<rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0" Item:Padding="0"/></rdf:li>
<rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" Item:Length="751" Item:Padding="8"/></rdf:li>
</rdf:Seq></Container:Directory></rdf:Description>"#)]),
            ReadMetadataResponse {
                motion_photo: Some(MotionPhotoMarkers {
                    motion_photo: true,
                    version: 1,
                    presentation_timestamp_us: Some(1_500_000),
                    items: vec![
                        ContainerItem { mime: "image/jpeg".into(), semantic: "Primary".into(), length_bytes: 0, padding_bytes: 0 },
                        ContainerItem { mime: "video/mp4".into(), semantic: "MotionPhoto".into(), length_bytes: 751, padding_bytes: 8 },
                    ],
                    ..Default::default()
                }),
                ..jpg()
            },
        ),
        file(
            "Apple's MakerNote, big-endian in a little-endian EXIF: a Live Photo's content identifier, a burst's UUID",
            {
                let mut note = b"Apple iOS\0\0\x01MM".to_vec();
                ifd(&mut note, vec![
                    (0x000b, Field::Text("6F1C2B3A-0D4E-4F50-8A6B-7C8D9E0F1A2B")),
                    (0x0011, Field::Text("9D2F6B0E-3A41-4C58-8E7B-1F0A5C6D7E81")),
                ], true);
                jpeg(&[exif(tiff(false, vec![(EXIF_IFD, Field::Ifd(vec![(0x927c, Field::Bytes(note))]))]))])
            },
            ReadMetadataResponse {
                content_identifier: "9D2F6B0E-3A41-4C58-8E7B-1F0A5C6D7E81".into(),
                burst_id: "6F1C2B3A-0D4E-4F50-8A6B-7C8D9E0F1A2B".into(),
                ..jpg()
            },
        ),
        file(
            "Google's Camera:BurstID",
            jpeg(&[xmp(r#"<rdf:Description xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" GCamera:BurstID="b2c5f1e0-1111-4a2b-9c3d-000000000001" GCamera:BurstPrimary="1"/>"#)]),
            ReadMetadataResponse { burst_id: "b2c5f1e0-1111-4a2b-9c3d-000000000001".into(), ..jpg() },
        ),
        file(
            "a legacy MicroVideo",
            jpeg(&[xmp(r#"<rdf:Description xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" GCamera:MicroVideo="1" GCamera:MicroVideoVersion="1" GCamera:MicroVideoOffset="4242" GCamera:MicroVideoPresentationTimestampUs="700000"/>"#)]),
            ReadMetadataResponse {
                motion_photo: Some(MotionPhotoMarkers {
                    micro_video: true,
                    micro_video_offset_bytes: 4242,
                    presentation_timestamp_us: Some(700_000),
                    ..Default::default()
                }),
                ..jpg()
            },
        ),
        file(
            "IPTC IIM in UTF-8: caption, keywords, credits, place and a date with its offset",
            jpeg(&[photoshop(&[(0x0404, &iim(&[
                (1, 90, "\x1b%G"),
                (2, 5, "Title"),
                (2, 25, "lake"),
                (2, 25, "hills"),
                (2, 55, "20190509"),
                (2, 60, "154733+0200"),
                (2, 80, "Alice"),
                (2, 90, "Paris"),
                (2, 95, "Île-de-France"),
                (2, 101, "France"),
                (2, 116, "© Alice"),
                (2, 120, "Morning"),
            ]))])]),
            ReadMetadataResponse {
                times: vec![dated("iptc:DateCreated", "2019-05-09T15:47:33", Some(120))],
                title: "Title".into(),
                description: "Morning".into(),
                keywords: strings(&["lake", "hills"]),
                creators: strings(&["Alice"]),
                copyright: "© Alice".into(),
                city: "Paris".into(),
                state: "Île-de-France".into(),
                country: "France".into(),
                ..jpg()
            },
        ),
        file(
            "XMP over IIM when the IPTC digest matches the IIM",
            jpeg(&[photoshop(&[(0x0404, &older), (0x0425, &digest)]), described("Evening")]),
            ReadMetadataResponse { description: "Evening".into(), keywords: strings(&["Evening"]), ..jpg() },
        ),
        file(
            "IIM over XMP when the digest no longer matches: a tool that knows only IIM edited it",
            jpeg(&[photoshop(&[(0x0404, &older), (0x0425, &[0; 16])]), described("Evening")]),
            ReadMetadataResponse { description: "Morning".into(), keywords: strings(&["Morning"]), ..jpg() },
        ),
        file(
            "EXIF over XMP, where camera boilerplate counts as no description",
            jpeg(&[
                exif(tiff(false, vec![
                    (0x010e, Field::Text("OLYMPUS DIGITAL CAMERA")),
                    (0x013b, Field::Text("Carol")),
                    (0x8298, Field::Text("Carol 2019")),
                ])),
                xmp(r#"<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:description><rdf:Alt><rdf:li xml:lang="x-default">Lake</rdf:li></rdf:Alt></dc:description><dc:creator><rdf:Seq><rdf:li>Alice</rdf:li></rdf:Seq></dc:creator><dc:rights>Alice</dc:rights></rdf:Description>"#),
            ]),
            ReadMetadataResponse {
                description: "Lake".into(),
                creators: strings(&["Carol"]),
                copyright: "Carol 2019".into(),
                ..jpg()
            },
        ),
        file(
            "a HEIC: the primary item's size, irot then imir as EXIF orientation 7, its Exif and XMP items",
            heic(
                &[full(b"ispe", 0, &[0, 0, 0x0f, 0xc0, 0, 0, 0x0b, 0xd0]), bx(b"irot", &[1]), bx(b"imir", &[1])],
                &tiff(true, vec![(0x010f, Field::Text("Apple")), (0x0112, Field::Short(3))]),
                &packet(r#"<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="3"/>"#),
            ),
            ReadMetadataResponse {
                width: 4032,
                height: 3024,
                orientation: 7,
                make: "Apple".into(),
                rating: Some(3),
                ..of(FileFormat::Heif)
            },
        ),
        file(
            "a HEIF auxiliary image of Apple's portrait matte keeps depth",
            heic(
                &[
                    full(b"ispe", 0, &[0, 0, 0x0f, 0xc0, 0, 0, 0x0b, 0xd0]),
                    full(b"auxC", 0, b"urn:com:apple:photo:2018:aux:portraiteffectsmatte\0"),
                ],
                &tiff(true, vec![]),
                &packet(""),
            ),
            ReadMetadataResponse { width: 4032, height: 3024, depth: true, ..of(FileFormat::Heif) },
        ),
        file("a capture rate below the frame rate: a time-lapse", paced(30, "1.0"), paced_film(30, Pace::TimeLapse)),
        file(
            "100 frames a second and more, without a capture rate: slow motion",
            paced(240, "0"),
            paced_film(240, Pace::SlowMotion),
        ),
        file(
            "a HEIC whose imir axis 0 exchanges top and bottom (ISO/IEC 23008-12:2022), as EXIF orientation 4",
            heic(&[full(b"ispe", 0, &[0, 0, 0x0f, 0xc0, 0, 0, 0x0b, 0xd0]), bx(b"imir", &[0])], &[], ""),
            ReadMetadataResponse { width: 4032, height: 3024, orientation: 4, ..of(FileFormat::Heif) },
        ),
        file(
            "a lossless WebP's size and its XMP chunk",
            {
                let vp8l = [&[0x2f][..], &(99u32 | 49 << 14).to_le_bytes()].concat();
                let packet = packet(r#"<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Label="Blue"/>"#);
                let chunk = |kind: &[u8], data: &[u8]| {
                    [kind, &(data.len() as u32).to_le_bytes(), data, &vec![0; data.len() % 2]].concat()
                };
                let body = [&b"WEBP"[..], &chunk(b"VP8L", &vp8l), &chunk(b"XMP ", packet.as_bytes())].concat();
                [&b"RIFF"[..], &(body.len() as u32).to_le_bytes(), &body].concat()
            },
            ReadMetadataResponse { width: 100, height: 50, label: "Blue".into(), ..of(FileFormat::Webp) },
        ),
        file(
            "a GIF's logical screen and its XMP application extension",
            {
                let packet = packet(r#"<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Label="Green"/>"#);
                let trailer: Vec<u8> = [1].into_iter().chain((0..=255).rev()).chain([0]).collect();
                let head = b"GIF89a\x40\x01\xf0\0\0\0\0\x21\xff\x0bXMP DataXMP";
                [&head[..], packet.as_bytes(), &trailer, b"\x3b"].concat()
            },
            ReadMetadataResponse { width: 320, height: 240, label: "Green".into(), ..of(FileFormat::Gif) },
        ),
        file(
            "an XMP sidecar",
            packet(r#"<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/"><xmp:Rating>2</xmp:Rating></rdf:Description>"#).into_bytes(),
            ReadMetadataResponse { rating: Some(2), ..of(FileFormat::Xmp) },
        ),
        file(
            "a movie: mvhd version 1, a transverse matrix, Apple's keys over the user data's ISO 6709 in seconds and minutes",
            movie(sample(b"apch", 3840, 2160, &[]), [0, -1, -1, 0], &[], &[
                keys(&[
                    ("com.apple.quicktime.make", "Apple"),
                    ("com.apple.quicktime.model", "iPhone 15 Pro"),
                    ("com.apple.quicktime.creationdate", "2023-06-01T08:30:00-0700"),
                    ("com.apple.quicktime.location.ISO6709", "+484500-00215+035.5/"),
                ]),
                bx(b"udta", &[text(b"\xa9xyz", "+10.0000+020.0000/"), text(b"\xa9day", "2023-06-01")].concat()),
            ]),
            ReadMetadataResponse {
                width: 3840,
                height: 2160,
                orientation: 7,
                make: "Apple".into(),
                model: "iPhone 15 Pro".into(),
                location: Some(GeoPoint { latitude: 48.75, longitude: -2.25, altitude_m: Some(35.5) }),
                times: vec![
                    dated("quicktime:CreationDate", "2023-06-01T08:30:00", Some(-420)),
                    time("quicktime:ContentCreateDate", "2023-06-01", None, CaptureTimePrecision::Day),
                    dated("quicktime:CreateDate", "2023-06-01T15:30:00", None),
                ],
                duration_ms: 2500,
                codec: "prores".into(),
                ..of(FileFormat::Quicktime)
            },
        ),
        file(
            "an HLG movie in QuickTime's nclc colour, with a Dolby Vision configuration",
            movie(
                sample(b"hvc1", 1920, 1080, &[bx(b"colr", b"nclc\0\x09\0\x12\0\x09"), bx(b"dvvC", &[0; 24])]),
                [1, 0, 0, 1],
                &[],
                &[],
            ),
            ReadMetadataResponse { transfer: 18, dolby_vision: true, ..film(1920, 1080, "hevc") },
        ),
        file(
            "Spherical Video V2 over V1: a mesh projection, the right view on the left",
            movie(
                sample(b"avc1", 3840, 1920, &[
                    full(b"st3d", 0, &[4]),
                    bx(b"sv3d", &bx(b"proj", &[full(b"prhd", 0, &[0; 12]), full(b"mshp", 0, &[0; 8])].concat())),
                ]),
                [1, 0, 0, 1],
                &[spherical_v1("<GSpherical:Spherical>true</GSpherical:Spherical><GSpherical:StereoMode>top-bottom</GSpherical:StereoMode>")],
                &[],
            ),
            sphere(Some("mesh"), StereoMode::RightLeft),
        ),
        file(
            "Spherical Video V2's projection bounds as GPano's pixels of the full panorama the picture is cut from",
            movie(
                sample(b"avc1", 1920, 1000, &[bx(b"sv3d", &bx(b"proj", &[
                    full(b"prhd", 0, &[0; 12]),
                    full(b"equi", 0, &[0x4000_0000u32, 0x2000_0000, 0x4000_0000, 0x4000_0000].map(u32::to_be_bytes).concat()),
                ].concat()))]),
                [1, 0, 0, 1],
                &[],
                &[],
            ),
            ReadMetadataResponse {
                panorama: Some(Panorama {
                    projection: "equirectangular".into(),
                    full_width: 3840,
                    full_height: 1600,
                    cropped_left: 960,
                    cropped_top: 400,
                    cropped_width: 1920,
                    cropped_height: 1000,
                    ..Default::default()
                }),
                ..film(1920, 1000, "h264")
            },
        ),
        file(
            "Spherical Video V2's projection bounds that leave nothing of the frame, ignored",
            movie(
                sample(b"avc1", 3840, 1920, &[bx(b"sv3d", &bx(b"proj", &[
                    full(b"prhd", 0, &[0; 12]),
                    full(b"equi", 0, &[0, 0, 0x8000_0000u32, 0x8000_0000].map(u32::to_be_bytes).concat()),
                ].concat()))]),
                [1, 0, 0, 1],
                &[],
                &[],
            ),
            sphere(Some("equirectangular"), StereoMode::Unspecified),
        ),
        file(
            "Spherical Video V1 alone, top-bottom",
            movie(
                sample(b"avc1", 3840, 1920, &[]),
                [1, 0, 0, 1],
                &[spherical_v1("<GSpherical:Spherical>True</GSpherical:Spherical><GSpherical:StereoMode>top-bottom</GSpherical:StereoMode>")],
                &[],
            ),
            sphere(Some("equirectangular"), StereoMode::TopBottom),
        ),
        file(
            "Spherical Video V1 that says the video is not spherical",
            movie(
                sample(b"avc1", 3840, 1920, &[]),
                [1, 0, 0, 1],
                &[spherical_v1("<GSpherical:Spherical>false</GSpherical:Spherical>")],
                &[],
            ),
            sphere(None, StereoMode::Unspecified),
        ),
        file(
            "a movie's frame rate: its video track's samples over the track's length, in the track's timescale",
            {
                let moov = [
                    track(b"soun", 48_000, &[(100, 1024)], vec![]),
                    track(b"vide", 30_000, &[(299, 1001), (1, 2002)], sample(b"avc1", 1920, 1080, &[])),
                ];
                [bx(b"ftyp", b"isom\0\0\0\0isom"), bx(b"moov", &moov.concat())].concat()
            },
            ReadMetadataResponse {
                width: 1920,
                height: 1080,
                codec: "h264".into(),
                frame_rate: 300.0 * 30_000.0 / 301_301.0,
                ..of(FileFormat::Quicktime)
            },
        ),
            whole(
                "a motion photo's video, last after a gain map, found from the end by its Container item",
                photo.clone(),
                ReadMetadataResponse { motion_photo: Some(markers.clone()), motion_video: Some(span), ..jpg() },
            ),
            whole(
                "markers whose video is gone point at no movie",
                [still.clone(), gain, vec![0; video.len()]].concat(),
                ReadMetadataResponse { motion_photo: Some(markers.clone()), ..jpg() },
            ),
            read(
                "a head asks for the first bytes of where the video should be",
                vec![(0, still)],
                photo.len(),
                ReadMetadataResponse {
                    motion_photo: Some(markers),
                    missing: vec![ByteSpan { offset: before + 4, length: 4 }],
                    ..jpg()
                },
            ),
            whole(
                "a Samsung camera's video in its SEF trailer, after another block",
                [samsung, trailer].concat(),
                ReadMetadataResponse {
                    make: "samsung".into(),
                    motion_video: Some(ByteSpan { offset: in_trailer as u64, length: video.len() as u64 }),
                    ..jpg()
                },
            ),
        {
            let mdat = bx(b"mdat", &[0; 100]);
            let file = [bx(b"ftyp", b"isom\0\0\0\0isom"), mdat.clone(), bx(b"moov", &[])].concat();
            case(
                "a movie whose moov follows the media data asks for the moov's header",
                vec![(0, file[..40].to_vec())],
                ReadMetadataResponse {
                    missing: vec![ByteSpan { offset: 20 + mdat.len() as u64, length: 8 }],
                    ..of(FileFormat::Quicktime)
                },
            )
        },
        {
            let (thumbnail, preview) = (jpeg(&[frame(160, 106)]), jpeg(&[frame(1620, 1080)]));
            let canon = [
                &b"\x85\xc0\xb6\x87\x82\x0f\x11\xe0\x81\x11\xf4\xce\x46\x2b\x6a\x48"[..],
                &bx(b"CMT1", &tiff(false, vec![(0x010f, Field::Text("Canon")), (0x0112, Field::Short(8))])),
                &bx(b"CMT2", &tiff(false, vec![(0x9003, Field::Text("2021:05:06 07:08:09"))])),
                &bx(b"CMT4", &tiff(true, vec![
                    (0x0001, Field::Text("S")),
                    (0x0002, Field::Rationals(&[(33, 1), (45, 1), (0, 1)])),
                    (0x0003, Field::Text("E")),
                    (0x0004, Field::Rationals(&[(151, 1), (15, 1), (0, 1)])),
                ])),
                &bx(b"THMB", &[&[0, 0, 0, 0, 0, 160, 0, 106][..], &(thumbnail.len() as u32).to_be_bytes(), &[0; 4], &thumbnail].concat()),
            ]
            .concat();
            let moov = movie(sample(b"CRAW", 6000, 4000, &[]), [1, 0, 0, 1], &[], &[bx(b"uuid", &canon)]);
            let prvw = [&[0, 0, 0, 0, 0, 1, 6, 84, 4, 56, 0, 1][..], &(preview.len() as u32).to_be_bytes(), &preview].concat();
            let uuid = b"\xea\xf4\x2b\x5e\x1c\x98\x4b\x88\xb9\xfb\xb7\xdc\x40\x6e\x4d\x16";
            let data = [
                bx(b"ftyp", b"crx \0\0\0\x01crx isom"),
                moov[20..].to_vec(),
                bx(b"uuid", &[&uuid[..], &[0, 0, 0, 0, 0, 0, 0, 1], &bx(b"PRVW", &prvw)].concat()),
                bx(b"mdat", &[0; 16]),
            ]
            .concat();
            let span = |jpeg: &[u8]| {
                let at = data.windows(jpeg.len()).position(|w| w == jpeg).unwrap();
                Some(ByteSpan { offset: at as u64, length: jpeg.len() as u64 })
            };
            whole(
                "Canon's CR3: IFD0, the EXIF IFD and GPS in TIFF blocks of their own, the size of the first track's \
                 image, and THMB's JPEG, smaller than PRVW's",
                data.clone(),
                ReadMetadataResponse {
                    width: 6000,
                    height: 4000,
                    orientation: 8,
                    make: "Canon".into(),
                    location: Some(GeoPoint { latitude: -33.75, longitude: 151.25, altitude_m: None }),
                    times: vec![dated("exif:DateTimeOriginal", "2021-05-06T07:08:09", None)],
                    preview: span(&thumbnail),
                    largest_preview: span(&preview),
                    ..of(FileFormat::Cr3)
                },
            )
        },
        file(
            "an AVI whose audio stream comes first: the frame size, count and rate, and the video stream's codec",
            {
                let chunk = |kind: &[u8], data: &[u8]| {
                    [kind, &(data.len() as u32).to_le_bytes(), data, &vec![0; data.len() % 2]].concat()
                };
                let list = |kind: &[u8], chunks: &[Vec<u8>]| chunk(b"LIST", &[kind, &chunks.concat()].concat());
                let words = |words: &[u32]| words.iter().flat_map(|w| w.to_le_bytes()).collect::<Vec<u8>>();
                let avih = words(&[40_000, 0, 0, 0x10, 75, 0, 2, 0, 1280, 720, 0, 0, 0, 0]);
                let stream = |kind: &[u8], handler: &[u8], format: Vec<u8>| {
                    list(b"strl", &[chunk(b"strh", &[kind, handler, &[0; 48]].concat()), chunk(b"strf", &format)])
                };
                let video = [&words(&[40, 1280, 720])[..], &[1, 0, 24, 0], b"H264", &[0; 20]].concat();
                let hdrl = list(b"hdrl", &[chunk(b"avih", &avih), stream(b"auds", b"\0\0\0\0", vec![1, 0, 2, 0, 0x44, 0xac, 0, 0, 0, 0, 0, 0, 4, 0, 16, 0]), stream(b"vids", b"x264", video)]);
                let body = [&b"AVI "[..], &hdrl, &list(b"movi", &[])].concat();
                [&b"RIFF"[..], &(body.len() as u32).to_le_bytes(), &body].concat()
            },
            ReadMetadataResponse { width: 1280, height: 720, duration_ms: 3000, codec: "h264".into(), frame_rate: 25.0, ..of(FileFormat::Avi) },
        ),
        file("bytes in no format this reader knows", b"not an image".to_vec(), ReadMetadataResponse::default()),
        case(
            "a head that ends inside the EXIF segment asks for the rest, and for what follows it",
            vec![(0, camera[..40].to_vec())],
            ReadMetadataResponse {
                missing: vec![ByteSpan { offset: 6, length: exif_end - 6 }, ByteSpan { offset: exif_end, length: 4 }],
                ..jpg()
            },
        ),
        case(
            "pieces given out of order and overlapping read as one",
            vec![(30, camera[30..].to_vec()), (0, camera[..40].to_vec())],
            canon,
        ),
        {
            let thumbnail = jpeg(&[frame(160, 120)]);
            let zero = tiff(false, vec![(0x010f, Field::Text("SONY"))]);
            let at = zero.len() + 2 + 2 * 12 + 4;
            let block = [with_ifd1(zero, jpeg_at(at, thumbnail.len())), thumbnail.clone()].concat();
            let data = jpeg(&[exif(block), frame(640, 480)]);
            let preview = |size| ByteSpan { offset: 12 + at as u64, length: thumbnail.len() as u64 + size };
            let found = ReadMetadataResponse {
                width: 640,
                height: 480,
                make: "SONY".into(),
                preview: Some(preview(0)),
                largest_preview: Some(preview(0)),
                ..jpg()
            };
            let past = jpeg(&[exif(with_ifd1(tiff(false, vec![]), jpeg_at(1 << 20, 100))), frame(8, 8)]);
            let not_jpeg = {
                let zero = tiff(false, vec![]);
                let at = zero.len() + 30;
                jpeg(&[exif([with_ifd1(zero, jpeg_at(at, 8)), b"not jpeg".to_vec()].concat()), frame(8, 8)])
            };
            let small = ReadMetadataResponse { width: 8, height: 8, ..jpg() };
            Value::Array(vec![
                whole("EXIF IFD1's thumbnail is the embedded preview, where it is in the file", data, found),
                whole("an IFD1 thumbnail past the end of the file is no preview", past, small.clone()),
                whole("bytes that are no JPEG are no preview", not_jpeg, small),
            ])
        },
        {
            // IFD0 holds the raw data, a SubIFD a JPEG preview and IFD1 a smaller thumbnail.
            let (preview, thumbnail) = (jpeg(&[frame(640, 480)]), jpeg(&[frame(160, 120)]));
            let raw = |ifd1: bool| {
                let layout = |data: usize| {
                    let strip = |at: usize, length: usize, photometric: u16| {
                        vec![
                            (0x0103, Field::Short(7)),
                            (0x0106, Field::Short(photometric)),
                            (0x0111, Field::Long(at as u32)),
                            (0x0117, Field::Long(length as u32)),
                        ]
                    };
                    let mut zero = strip(data, 4, 32803);
                    zero.push((0x010f, Field::Text("NIKON CORPORATION")));
                    zero.push((0x014a, Field::Ifd(strip(data + 4, preview.len(), 6))));
                    let block = tiff(false, zero);
                    let at = data + 4 + preview.len();
                    if ifd1 { with_ifd1(block, jpeg_at(at, thumbnail.len())) } else { block }
                };
                let length = layout(0).len();
                let file = [layout(length), vec![0xff, 0xd8, 0, 0], preview.clone(), thumbnail.clone()].concat();
                (file, length)
            };
            let (with, at) = raw(true);
            let (without, plain) = raw(false);
            let span = |offset: usize, length: usize| Some(ByteSpan { offset: offset as u64, length: length as u64 });
            // The data starts after the TIFF block: four bytes of raw data, then the preview.
            let nef = |data: usize, offset: usize, length: usize| ReadMetadataResponse {
                make: "NIKON CORPORATION".into(),
                preview: span(offset, length),
                largest_preview: span(data + 4, preview.len()),
                ..of(FileFormat::Tiff)
            };
            Value::Array(vec![
                whole(
                    "a RAW's smallest JPEG is its preview, its largest a SubIFD's: IFD1's thumbnail is smaller",
                    with,
                    nef(at, at + 4 + preview.len(), thumbnail.len()),
                ),
                whole(
                    "a RAW's JPEG-compressed YCbCr strip is a preview, its JPEG-compressed raw data never",
                    without,
                    nef(plain, plain + 4, preview.len()),
                ),
            ])
        },
        {
            let thumbnail = jpeg(&[frame(320, 240)]);
            let (data, at) = heic_thumbnail(&thumbnail);
            whole(
                "a HEIF thumbnail item coded as JPEG is the preview",
                data,
                ReadMetadataResponse {
                    preview: Some(ByteSpan { offset: at, length: thumbnail.len() as u64 }),
                    largest_preview: Some(ByteSpan { offset: at, length: thumbnail.len() as u64 }),
                    ..of(FileFormat::Heif)
                },
            )
        },
        file(
            "an ISO 21496-1 APP2 marks a JPEG's gain map",
            jpeg(&[(0xe2, b"urn:iso:std:iso:ts:21496:-1\0\0\0".to_vec())]),
            ReadMetadataResponse { gain_map: true, ..jpg() },
        ),
        {
            // Apple's JPEG: the gain map is the second picture of a Multi-Picture Format index, named in its own XMP.
            let apple = |name: &str| {
                xmp(&format!(
                    r#"<rdf:Description xmlns:apdi="http://ns.apple.com/pixeldatainfo/1.0/"><apdi:AuxiliaryImageType>{name}</apdi:AuxiliaryImageType></rdf:Description>"#
                ))
            };
            let paired = |second: Vec<u8>| {
                let first = jpeg(&[mpf(0, 0)]);
                // The offset counts from the byte-order mark: 2 (the start of image) + 4 + 4 (the prefix) in.
                let index = mpf(second.len() as u32, (first.len() - 10) as u32);
                (jpeg(&[index]), second)
            };
            let (primary, second) = paired(jpeg(&[apple("urn:com:apple:photo:2020:aux:hdrgainmap")]));
            let (plain_primary, plain) = paired(jpeg(&[apple("urn:com:apple:photo:2020:aux:depth")]));
            let mut cases = vec![
                whole(
                    "the second picture of an MPF index that Apple's XMP names a gain map marks a JPEG's",
                    [primary.clone(), second.clone()].concat(),
                    ReadMetadataResponse { gain_map: true, ..jpg() },
                ),
                whole(
                    "a second picture named as anything else is no gain map",
                    plain_primary.into_iter().chain(plain).collect(),
                    jpg(),
                ),
                // The host sends the second picture's start when the index says where it is.
                read(
                    "an MPF index's second picture is asked for when it was not sent",
                    vec![(0, primary.clone())],
                    primary.len() + second.len(),
                    ReadMetadataResponse {
                        missing: vec![ByteSpan { offset: primary.len() as u64, length: second.len() as u64 }],
                        ..jpg()
                    },
                ),
            ];
            // An index with no second picture, or an entry list cut short, marks nothing.
            let (one, _) = paired(vec![0xff, 0xd8, 0xff, 0xd9]);
            let mut short = one;
            let at = short.windows(4).position(|w| w == [0x02, 0xb0, 7, 0]).unwrap();
            short[at + 4] = 16;
            cases.push(whole("an MPF index of one picture marks nothing", short, jpg()));
            Value::Array(cases)
        },
        file(
            "an ICC profile's APP2 is no gain map",
            jpeg(&[(0xe2, b"ICC_PROFILE\0\x01\x01".to_vec())]),
            jpg(),
        ),
    ]
    .into_iter()
    // A block of several cases is an array of them.
    .flat_map(|case| match case {
        Value::Array(cases) => cases,
        case => vec![case],
    })
    .collect()
}
