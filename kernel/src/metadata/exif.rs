//! TIFF structure and the EXIF and GPS tags in it, wherever the TIFF block sits: a JPEG's APP1, a PNG's eXIf, a
//! HEIF Exif item, or a whole TIFF or TIFF-based RAW file.

use super::file::{File, uint};
use super::{claim, degrees, location};
use crate::proto::kernel::v1::GeoPoint;
use crate::proto::model::v1::CaptureTime;

const SUB_IFDS: u16 = 0x014a;
const NEW_SUBFILE_TYPE: u16 = 0x00fe;
const EXIF_IFD: u16 = 0x8769;
const GPS_IFD: u16 = 0x8825;
const JPEG_OFFSET: u16 = 0x0201;
const JPEG_LENGTH: u16 = 0x0202;

#[derive(Default)]
pub struct Exif {
    /// Of the full-size image, which a RAW file may keep in a SubIFD.
    pub width: u32,
    pub height: u32,
    pub orientation: Option<u32>,
    pub make: Option<String>,
    pub model: Option<String>,
    pub description: Option<String>,
    pub artist: Option<String>,
    pub copyright: Option<String>,
    pub location: Option<GeoPoint>,
    pub times: Vec<CaptureTime>,
    pub xmp: Option<Vec<u8>>,
    pub iim: Option<Vec<u8>>,
    pub photoshop: Option<Vec<u8>>,
    /// From Apple's MakerNote.
    pub content_identifier: Option<String>,
    pub burst_id: Option<String>,
    /// The JPEG images the IFDs point to besides the main one, such as IFD1's thumbnail and a RAW's previews, as
    /// offsets and lengths in the file.
    pub previews: Vec<(u64, u64)>,
}

pub fn read(file: &File, base: u64) -> Exif {
    read_blocks(file, base, None, None)
}

/// What `read` finds, the EXIF and GPS IFDs being the first of TIFF blocks of their own where given: Canon's CR3.
pub(crate) fn read_blocks(file: &File, base: u64, exif_at: Option<u64>, gps_at: Option<u64>) -> Exif {
    let mut exif = Exif::default();
    let Some(tiff) = Tiff::open(file, base) else {
        return exif;
    };
    let Some(first) = tiff.first_ifd() else {
        return exif;
    };
    let Some(zero) = tiff.ifd(first) else {
        return exif;
    };
    // IFD0's chain, IFD1 the thumbnail, and its SubIFDs.
    let mut chain = vec![];
    let mut next = tiff.next_ifd(first);
    while let Some(at) = next.filter(|&at| at != 0 && chain.len() < 4) {
        chain.extend(tiff.ifd(at));
        next = tiff.next_ifd(at);
    }
    exif.previews = [&zero]
        .into_iter()
        .chain(&chain)
        .chain(&tiff.sub_ifds(&zero))
        .filter_map(|ifd| tiff.jpeg(ifd))
        .collect();
    // An IFD and the TIFF block its offsets count from: one IFD0 points to, or the first of a block of its own.
    let sub = |tag, block: Option<u64>| match block {
        Some(at) => Tiff::open(file, at).and_then(|t| Some((t.ifd(t.first_ifd()?)?, t))),
        None => (zero.find(tag).and_then(|e| tiff.number(e))).and_then(|at| Some((tiff.ifd(at)?, tiff))),
    };
    let none = || (Ifd::default(), tiff);
    let (exif_ifd, gps) = (
        sub(EXIF_IFD, exif_at).unwrap_or_else(none),
        sub(GPS_IFD, gps_at).unwrap_or_else(none),
    );
    let zero = (zero, tiff);
    let number = |(ifd, t): &(Ifd, Tiff), tag| ifd.find(tag).and_then(|e| t.number(e));
    let text = |(ifd, t): &(Ifd, Tiff), tag| ifd.find(tag).and_then(|e| t.text(e));
    let rationals = |(ifd, t): &(Ifd, Tiff), tag| ifd.find(tag).map(|e| t.rationals(e));
    exif.make = text(&zero, 0x010f);
    exif.model = text(&zero, 0x0110);
    exif.description = text(&zero, 0x010e);
    exif.artist = text(&zero, 0x013b);
    exif.copyright = text(&zero, 0x8298);
    exif.orientation = number(&zero, 0x0112).and_then(|n| u32::try_from(n).ok());
    let bytes = |tag| zero.0.find(tag).and_then(|e| tiff.bytes(e)).map(<[u8]>::to_vec);
    (exif.xmp, exif.iim, exif.photoshop) = (bytes(0x02bc), bytes(0x83bb), bytes(0x8649));
    (exif.width, exif.height) = tiff.full_size(&zero.0);
    for (source, date, ifd, subsec, offset) in [
        ("exif:DateTimeOriginal", 0x9003, &exif_ifd, 0x9291, 0x9011),
        ("exif:CreateDate", 0x9004, &exif_ifd, 0x9292, 0x9012),
        ("exif:ModifyDate", 0x0132, &zero, 0x9290, 0x9010),
    ] {
        if let Some(date) = text(ifd, date) {
            let subsec = text(&exif_ifd, subsec);
            exif.times.push(claim(
                source,
                &date,
                subsec.as_deref(),
                text(&exif_ifd, offset).as_deref(),
            ));
        }
    }
    // Apple's MakerNote: "Apple iOS", a version and the byte order, then an IFD whose offsets count from its start.
    let note = exif_ifd.0.find(0x927c).map(|e| exif_ifd.1.base.saturating_add(e.at));
    if let Some(base) = note.filter(|&at| tiff.file.get(at, 10) == Some(b"Apple iOS\0")) {
        let apple = Tiff {
            base,
            big_endian: tiff.file.get(base + 12, 2) == Some(b"MM"),
            big: false,
            ..tiff
        };
        let note = apple.ifd(14).unwrap_or_default();
        let text = |tag| note.find(tag).and_then(|e| apple.text(e));
        (exif.content_identifier, exif.burst_id) = (text(0x0011), text(0x000b));
    }
    let coordinate = |tag, reference, negative| {
        let sign = if text(&gps, reference).as_deref() == Some(negative) {
            -1.0
        } else {
            1.0
        };
        degrees(&rationals(&gps, tag)?).map(|d| sign * d)
    };
    if let (Some(latitude), Some(longitude)) = (coordinate(0x0002, 0x0001, "S"), coordinate(0x0004, 0x0003, "W")) {
        let below = number(&gps, 0x0005) == Some(1);
        let altitude = rationals(&gps, 0x0006).and_then(|r| r.first().copied());
        exif.location = location(latitude, longitude, altitude.map(|a| if below { -a } else { a }));
    }
    let clock = rationals(&gps, 0x0007).unwrap_or_default();
    if let (Some(date), [hour, minute, second]) = (text(&gps, 0x001d), clock.as_slice())
        && [hour, minute, second].iter().all(|v| (0.0..100.0).contains(*v))
    {
        let whole = format!("{date} {:02}:{:02}:{:02}", *hour as u32, *minute as u32, *second as u32);
        let millis = second.fract() * 1000.0;
        let fraction = (millis >= 1.0).then(|| format!("{:03}", millis as u32));
        let mut time = claim("exif:GPSDateTime", &whole, fraction.as_deref(), None);
        time.offset_minutes.get_or_insert(0);
        exif.times.push(time);
    }
    exif
}

#[derive(Clone, Copy)]
struct Tiff<'f, 'a> {
    file: &'f File<'a>,
    base: u64,
    big_endian: bool,
    /// BigTIFF: 8-byte offsets and counts.
    big: bool,
}

#[derive(Default)]
struct Ifd(Vec<Entry>);

struct Entry {
    tag: u16,
    kind: u16,
    count: u64,
    /// Where the value starts, from the start of the TIFF block.
    at: u64,
}

impl Ifd {
    fn find(&self, tag: u16) -> Option<&Entry> {
        self.0.iter().find(|e| e.tag == tag)
    }
}

impl<'f, 'a> Tiff<'f, 'a> {
    fn open(file: &'f File<'a>, base: u64) -> Option<Self> {
        let (big_endian, big) = magic(file.get(base, 4)?)?;
        Some(Tiff {
            file,
            base,
            big_endian,
            big,
        })
    }

    fn uint(&self, at: u64, len: u64) -> Option<u64> {
        let bytes = self.file.get(self.base.checked_add(at)?, len)?;
        Some(uint(bytes, self.big_endian))
    }

    fn word(&self) -> u64 {
        if self.big { 8 } else { 4 }
    }

    fn first_ifd(&self) -> Option<u64> {
        self.uint(self.word(), self.word())
    }

    fn sizes(&self) -> (u64, u64) {
        if self.big { (8, 20) } else { (2, 12) }
    }

    /// The offset of the IFD after the one at `at`; 0 when it is the last.
    fn next_ifd(&self, at: u64) -> Option<u64> {
        let (count_len, entry_len) = self.sizes();
        let count = self.uint(at, count_len)?.min(4096);
        self.uint(at.checked_add(count_len + count * entry_len)?, self.word())
    }

    fn ifd(&self, at: u64) -> Option<Ifd> {
        let word = self.word();
        let (count_len, entry_len) = self.sizes();
        let count = self.uint(at, count_len)?.min(4096);
        let table = self
            .file
            .get(self.base.checked_add(at.saturating_add(count_len))?, count * entry_len)?;
        let entries = table
            .chunks_exact(entry_len as usize)
            .zip(0..)
            .filter_map(|(entry, i)| {
                let field = |from: usize, len: u64| uint(&entry[from..from + len as usize], self.big_endian);
                let (tag, kind) = (field(0, 2) as u16, field(2, 2) as u16);
                let count = field(4, word);
                let value = at.saturating_add(count_len + i * entry_len + 4 + word);
                let size = count.checked_mul(type_size(kind)?)?;
                let at = if size <= word {
                    value
                } else {
                    field(4 + word as usize, word)
                };
                Some(Entry { tag, kind, count, at })
            });
        Some(Ifd(entries.collect()))
    }

    fn bytes(&self, entry: &Entry) -> Option<&'f [u8]> {
        let len = entry.count.checked_mul(type_size(entry.kind)?)?;
        self.file.get(self.base.checked_add(entry.at)?, len)
    }

    /// ASCII or EXIF 3's UTF-8, up to the first NUL and trimmed; Latin-1 when it is not UTF-8.
    fn text(&self, entry: &Entry) -> Option<String> {
        if !matches!(entry.kind, 2 | 7 | 129) {
            return None;
        }
        let bytes = self.bytes(entry)?;
        let bytes = bytes.split(|&b| b == 0).next().unwrap_or_default();
        let text = match std::str::from_utf8(bytes) {
            Ok(text) => text.to_string(),
            Err(_) => bytes.iter().map(|&b| char::from(b)).collect(),
        };
        let text = text.trim();
        (!text.is_empty()).then(|| text.to_string())
    }

    /// The first value of an unsigned integer or offset tag.
    fn number(&self, entry: &Entry) -> Option<u64> {
        let size = match entry.kind {
            1 => 1,
            3 => 2,
            4 | 13 => 4,
            16 | 18 => 8,
            _ => return None,
        };
        (entry.count > 0).then_some(())?;
        self.uint(entry.at, size)
    }

    fn rationals(&self, entry: &Entry) -> Vec<f64> {
        let signed = match entry.kind {
            5 => false,
            10 => true,
            _ => return vec![],
        };
        let at = |i: u64| self.uint(entry.at.saturating_add(4 * i), 4);
        let value = |n: u64| {
            if signed { f64::from(n as u32 as i32) } else { n as f64 }
        };
        (0..entry.count.min(3))
            .map_while(|i| Some(value(at(2 * i)?) / value(at(2 * i + 1)?)))
            .collect()
    }

    /// The size of the full-resolution image: IFD0's, unless IFD0 is a reduced one and a SubIFD holds the original.
    fn full_size(&self, zero: &Ifd) -> (u32, u32) {
        let reduced = |ifd: &Ifd| ifd.find(NEW_SUBFILE_TYPE).and_then(|e| self.number(e)).unwrap_or(0) & 1 == 1;
        let size = |ifd: &Ifd| {
            let dimension = |tag| {
                ifd.find(tag)
                    .and_then(|e| self.number(e))
                    .and_then(|n| u32::try_from(n).ok())
            };
            Some((dimension(0x0100)?, dimension(0x0101)?))
        };
        let full = if reduced(zero) {
            self.sub_ifds(zero).iter().find(|ifd| !reduced(ifd)).and_then(size)
        } else {
            None
        };
        full.or_else(|| size(zero)).unwrap_or_default()
    }

    fn sub_ifds(&self, zero: &Ifd) -> Vec<Ifd> {
        let Some((entry, size_each)) = zero.find(SUB_IFDS).and_then(|e| Some((e, type_size(e.kind)?))) else {
            return vec![];
        };
        (0..entry.count.min(8))
            .filter_map(|i| self.uint(entry.at.saturating_add(i * size_each), size_each))
            .filter_map(|at| self.ifd(at))
            .collect()
    }

    /// Where the JPEG an IFD points to is: JPEGInterchangeFormat, or the one strip of a JPEG-compressed YCbCr image,
    /// which a RAW's raw data never is.
    fn jpeg(&self, ifd: &Ifd) -> Option<(u64, u64)> {
        let number = |tag| ifd.find(tag).and_then(|e| self.number(e));
        let (offset, length) = match (number(JPEG_OFFSET), number(JPEG_LENGTH)) {
            (Some(offset), Some(length)) => (offset, length),
            _ if matches!(number(0x0103), Some(6 | 7)) && number(0x0106) == Some(6) => {
                let (strips, counts) = (ifd.find(0x0111)?, ifd.find(0x0117)?);
                (strips.count == 1 && counts.count == 1).then_some(())?;
                (self.number(strips)?, self.number(counts)?)
            }
            _ => return None,
        };
        (length > 0).then_some((self.base.checked_add(offset)?, length))
    }
}

/// Whether a TIFF header is big-endian and BigTIFF; Olympus ORF and Panasonic RW2 have their own magic numbers.
pub fn magic(head: &[u8]) -> Option<(bool, bool)> {
    match head.get(..4)? {
        b"II*\0" | b"IIRO" | b"IIU\0" => Some((false, false)),
        b"MM\0*" | b"MMOR" => Some((true, false)),
        b"II+\0" => Some((false, true)),
        b"MM\0+" => Some((true, true)),
        _ => None,
    }
}

/// Bytes per value of a TIFF field type; None for types this reader does not know.
fn type_size(kind: u16) -> Option<u64> {
    match kind {
        1 | 2 | 6 | 7 | 129 => Some(1),
        3 | 8 => Some(2),
        4 | 9 | 11 | 13 => Some(4),
        5 | 10 | 12 | 16 | 17 | 18 => Some(8),
        _ => None,
    }
}
