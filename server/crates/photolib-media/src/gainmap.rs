//! Gain maps in JPEG derivatives (photolib-design docs/08 §4, ADR-0390): an Ultra HDR or ISO 21496-1 picture is its SDR
//! picture and, beside it, a second image that says how much brighter each place is on an HDR display. A rendition
//! made from it keeps the pair: the map is scaled and turned with the picture, and the container is written again (the
//! XMP directory with the map's new length, the ISO 21496-1 metadata, the Multi-Picture Format index with its new
//! offset). The map comes from a JPEG's second picture or from a HEIF file's (`heif`).

use std::{
    fmt::Write as _,
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::Path,
};

use crate::heif::Reader;

/// The most of the file read to find the pictures' index: the primary's header segments.
const HEADER: u64 = 1 << 20;
/// The APP1 namespace of XMP.
const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
/// The APP2 prefix of an ISO 21496-1 gain map's metadata.
const ISO: &[u8] = b"urn:iso:std:iso:ts:21496:-1\0";
/// The APP2 prefix of the Multi-Picture Format's index.
const MPF: &[u8] = b"MPF\0";
/// The denominator of the fractions this module writes.
const DENOMINATOR: u32 = 1_000_000;

/// How a gain map is applied: `min`, `max` and the capacities in stops (log2), as ISO 21496-1 and Ultra HDR's XMP say
/// them, per channel (red, green, blue). The HDR picture is `(sdr + offset_sdr) × 2^(gain × weight) − offset_hdr`, the
/// gain running from `min` to `max` over the map's values raised to `1 / gamma`.
#[derive(Clone, Debug, PartialEq)]
pub struct Boost {
    /// The gain at a map value of 0, in stops.
    pub min: [f64; 3],
    /// The gain at a map value of 1, in stops.
    pub max: [f64; 3],
    /// The exponent the map's values are raised to.
    pub gamma: [f64; 3],
    /// What is added to the SDR picture before the gain.
    pub offset_sdr: [f64; 3],
    /// What is taken from the HDR picture after it.
    pub offset_hdr: [f64; 3],
    /// The display headroom at which the gain is none, in stops.
    pub capacity_min: f64,
    /// The display headroom at which the gain is all, in stops.
    pub capacity_max: f64,
    /// Whether the channels differ.
    pub multichannel: bool,
}

/// A fraction's value; none when the denominator is 0.
fn quotient(numerator: f64, denominator: f64) -> Option<f64> {
    (denominator != 0.0).then(|| numerator / denominator)
}

/// `numerator` as the signed 32-bit number its four bytes were.
fn signed(numerator: u64) -> f64 {
    f64::from(i32::from_be_bytes(
        u32::try_from(numerator).unwrap_or_default().to_be_bytes(),
    ))
}

impl Boost {
    /// Apple's (docs "Applying Apple HDR effect to your photos"): `sdr × (1 + (headroom − 1) × map)`, for a map
    /// already linear, which `apple_map` makes it of Apple's Rec.709-coded one.
    pub fn apple(headroom: f64) -> Self {
        let stops = headroom.max(1.0).log2();
        Self {
            min: [0.0; 3],
            max: [stops; 3],
            gamma: [1.0; 3],
            offset_sdr: [0.0; 3],
            offset_hdr: [0.0; 3],
            capacity_min: 0.0,
            capacity_max: stops,
            multichannel: false,
        }
    }

    /// The metadata of ISO 21496-1 from its minimum version on, as a `tmap` item holds it after its own version byte
    /// and an APP2 segment of the gain map's JPEG holds it. None for a version this does not read, a map that runs
    /// from the alternate to the base picture, or a field that is not a number.
    pub fn from_iso(iso: &[u8]) -> Option<Self> {
        let mut r = Reader::new(iso);
        if r.uint(2)? != 0 {
            return None;
        }
        r.uint(2)?;
        let flags = r.uint(1)?;
        let channels = if flags & 0x80 == 0 { 1 } else { 3 };
        if flags & 4 != 0 {
            return None;
        }
        // With a common denominator the numerators come alone, the denominator having been read; else in pairs.
        let common = if flags & 8 == 0 { None } else { Some(r.uint(4)?) };
        let mut value = |signed_value: bool| -> Option<f64> {
            let numerator = r.uint(4)?;
            let numerator = if signed_value {
                signed(numerator)
            } else {
                f64::from(u32::try_from(numerator).ok()?)
            };
            let denominator = match common {
                Some(common) => common,
                None => r.uint(4)?,
            };
            quotient(numerator, f64::from(u32::try_from(denominator).ok()?))
        };
        let capacity_min = value(false)?;
        let capacity_max = value(false)?;
        let mut parameters = vec![];
        for _ in 0..channels {
            let (min, max) = (value(true)?, value(true)?);
            parameters.push([min, max, value(false)?, value(true)?, value(true)?]);
        }
        // A channel the metadata does not give has the first one's.
        let first = parameters.first().copied()?;
        let channel = |n: usize| parameters.get(n).copied().unwrap_or(first);
        let pick =
            |at: usize| [channel(0).get(at), channel(1).get(at), channel(2).get(at)].map(|v| v.copied().unwrap_or(0.0));
        let boost = Self {
            min: pick(0),
            max: pick(1),
            gamma: pick(2),
            offset_sdr: pick(3),
            offset_hdr: pick(4),
            capacity_min,
            capacity_max,
            multichannel: channels == 3,
        };
        // A base picture that is the brighter one is no picture to apply a map to.
        let forward = boost.capacity_max > boost.capacity_min;
        (forward && boost.gamma.iter().all(|g| *g > 0.0)).then_some(boost)
    }

    /// The metadata of ISO 21496-1 (the bytes `from_iso` reads) in fractions of a millionth, with the map in the
    /// primary's colour space.
    pub fn iso(&self) -> Option<Vec<u8>> {
        let mut bytes = vec![0, 0, 0, 0, if self.multichannel { 0xc0 } else { 0x40 }];
        let mut fraction = |value: f64, signed_value: bool| -> Option<()> {
            let scaled = (value * f64::from(DENOMINATOR)).round();
            if !scaled.is_finite() || (!signed_value && scaled < 0.0) || scaled.abs() > f64::from(i32::MAX) {
                return None;
            }
            // In range, as checked: the rounded value of an i32.
            #[allow(clippy::cast_possible_truncation)]
            let numerator = scaled as i32;
            bytes.extend(numerator.to_be_bytes());
            bytes.extend(DENOMINATOR.to_be_bytes());
            Some(())
        };
        fraction(self.capacity_min, false)?;
        fraction(self.capacity_max, false)?;
        for c in 0..if self.multichannel { 3 } else { 1 } {
            fraction(*self.min.get(c)?, true)?;
            fraction(*self.max.get(c)?, true)?;
            fraction(*self.gamma.get(c)?, false)?;
            fraction(*self.offset_sdr.get(c)?, true)?;
            fraction(*self.offset_hdr.get(c)?, true)?;
        }
        Some(bytes)
    }

    /// The gain map's own XMP packet (Ultra HDR 1.0): nothing but its parameters.
    pub fn xmp(&self) -> Vec<u8> {
        let names = [
            ("GainMapMin", &self.min),
            ("GainMapMax", &self.max),
            ("Gamma", &self.gamma),
            ("OffsetSDR", &self.offset_sdr),
            ("OffsetHDR", &self.offset_hdr),
        ];
        let (mut attributes, mut elements) = (String::new(), String::new());
        for (name, values) in names {
            if self.multichannel {
                let mut list = String::new();
                for value in values {
                    write!(list, "<rdf:li>{value}</rdf:li>").ok();
                }
                write!(elements, "<hdrgm:{name}><rdf:Seq>{list}</rdf:Seq></hdrgm:{name}>").ok();
            } else {
                write!(
                    attributes,
                    " hdrgm:{name}=\"{}\"",
                    values.first().copied().unwrap_or_default()
                )
                .ok();
            }
        }
        format!(
            "<?xpacket begin=\"\u{feff}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\
             <x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\
             <rdf:Description rdf:about=\"\" xmlns:hdrgm=\"http://ns.adobe.com/hdr-gain-map/1.0/\" \
             hdrgm:Version=\"1.0\"{attributes} hdrgm:HDRCapacityMin=\"{}\" hdrgm:HDRCapacityMax=\"{}\" \
             hdrgm:BaseRenditionIsHDR=\"False\">{elements}</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end=\"w\"?>",
            self.capacity_min, self.capacity_max
        )
        .into_bytes()
    }
}

/// What a rendition's container says of its gain map, besides the map.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Carried {
    /// The `hdrgm:Version` of the primary's XMP, whose container directory lists the map; none writes no XMP.
    pub version: Option<String>,
    /// The primary's ISO 21496-1 payload (the version only, in files that follow Android's), none writes none.
    pub iso: Option<Vec<u8>>,
    /// The map's own APP1 and APP2 segments: marker and payload, namespace first.
    pub secondary: Vec<(u8, Vec<u8>)>,
}

impl Carried {
    /// Both ways of saying `boost`, so that readers of either find it.
    pub fn of(boost: &Boost) -> Option<Self> {
        let secondary = vec![
            (0xe1, [XMP, &boost.xmp()].concat()),
            (0xe2, [ISO, &boost.iso()?].concat()),
        ];
        Some(Self {
            version: Some("1.0".into()),
            iso: Some(vec![0; 4]),
            secondary,
        })
    }
}

/// The gain map of a JPEG, with the metadata that belongs to it.
#[derive(Clone, Debug, PartialEq)]
pub struct GainMap {
    /// The map as a JPEG of its own, with its own metadata.
    pub image: Vec<u8>,
    /// What the container says of it.
    pub carried: Carried,
    /// Apple's map is coded in Rec.709's transfer, and `carried` says how it is applied once `apple_map` has recoded it:
    /// the headroom (a ratio) it was computed from.
    pub apple: Option<f64>,
}

/// The type of Apple's gain map, which its JPEGs' second picture names in its XMP.
const APPLE_GAIN_MAP: &[u8] = b"urn:com:apple:photo:2020:aux:hdrgainmap";

/// A marker segment: its marker and its payload, which follows the two length bytes.
struct Segment<'a> {
    marker: u8,
    payload: &'a [u8],
    /// Where its marker starts.
    at: usize,
}

/// The segments of `jpeg` from the SOI to the start of the scan.
fn segments(jpeg: &[u8]) -> Option<Vec<Segment<'_>>> {
    if !jpeg.starts_with(&[0xff, 0xd8]) {
        return None;
    }
    let mut found = vec![];
    let mut at = 2usize;
    while let Some(&[0xff, marker, high, low]) = at.checked_add(4).and_then(|end| jpeg.get(at..end)) {
        if marker == 0xda {
            break;
        }
        let end = at
            .checked_add(2)?
            .checked_add(usize::from(u16::from_be_bytes([high, low])))?;
        let payload = jpeg.get(at.checked_add(4)?..end)?;
        found.push(Segment { marker, payload, at });
        at = end;
    }
    Some(found)
}

fn app(segments: &[Segment<'_>], marker: u8, prefix: &[u8]) -> Option<Vec<u8>> {
    let found = (segments.iter()).find(|s| s.marker == marker && s.payload.starts_with(prefix))?;
    Some(found.payload.get(prefix.len()..)?.to_vec())
}

/// A TIFF structure's numbers, in its byte order.
struct Tiff<'a> {
    bytes: &'a [u8],
    little: bool,
}

impl Tiff<'_> {
    fn u16(&self, at: usize) -> Option<usize> {
        let bytes: [u8; 2] = self.bytes.get(at..at.checked_add(2)?)?.try_into().ok()?;
        Some(usize::from(if self.little {
            u16::from_le_bytes(bytes)
        } else {
            u16::from_be_bytes(bytes)
        }))
    }

    fn u32(&self, at: usize) -> Option<u64> {
        let bytes: [u8; 4] = self.bytes.get(at..at.checked_add(4)?)?.try_into().ok()?;
        Some(u64::from(if self.little {
            u32::from_le_bytes(bytes)
        } else {
            u32::from_be_bytes(bytes)
        }))
    }
}

/// The files of a Multi-Picture Format index: each picture's offset from the start of the file and its size, the
/// first being the file's own picture.
fn pictures(segments: &[Segment<'_>], file_size: u64) -> Option<Vec<(u64, u64)>> {
    let mpf = segments
        .iter()
        .find(|s| s.marker == 0xe2 && s.payload.starts_with(MPF))?;
    // Offsets count from the byte-order mark, which sits after the 4 bytes of the prefix, the marker and its length.
    let base = u64::try_from(mpf.at.checked_add(4)?.checked_add(MPF.len())?).ok()?;
    let bytes = mpf.payload.get(MPF.len()..)?;
    let little = match bytes.get(..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let tiff = Tiff { bytes, little };
    if tiff.u16(2)? != 42 {
        return None;
    }
    let ifd = usize::try_from(tiff.u32(4)?).ok()?;
    let mut list = None;
    for entry in 0..tiff.u16(ifd)? {
        let at = ifd.checked_add(2)?.checked_add(entry.checked_mul(12)?)?;
        // MPEntry: undefined, 16 bytes per picture, at an offset.
        if tiff.u16(at)? == 0xb002 {
            let (count, offset) = (
                usize::try_from(tiff.u32(at.checked_add(4)?)?).ok()?,
                tiff.u32(at.checked_add(8)?)?,
            );
            if count % 16 != 0 || count == 0 || count > 16 * 16 {
                return None;
            }
            let offset = usize::try_from(offset).ok()?;
            list = Some(
                (0..count / 16)
                    .filter_map(|n| offset.checked_add(n.checked_mul(16)?))
                    .collect::<Vec<_>>(),
            );
        }
    }
    let mut pictures = vec![];
    for at in list? {
        let (size, offset) = (tiff.u32(at.checked_add(4)?)?, tiff.u32(at.checked_add(8)?)?);
        // The first picture is the file's own, at offset 0.
        let start = if pictures.is_empty() {
            0
        } else {
            base.checked_add(offset)?
        };
        if start.checked_add(size)? > file_size {
            return None;
        }
        pictures.push((start, size));
    }
    Some(pictures)
}

/// The XMP namespaces of a gain map's metadata: nothing else may travel into a rendition, which carries no metadata.
const NAMESPACES: [&str; 5] = [
    "adobe:ns:meta/",
    "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    "http://ns.adobe.com/hdr-gain-map/1.0/",
    "http://ns.google.com/photos/1.0/container/",
    "http://ns.google.com/photos/1.0/container/item/",
];

/// Whether `xmp` declares no namespace but those of a gain map and its container.
fn only_gain_map_namespaces(xmp: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(xmp) else {
        return false;
    };
    text.split("xmlns:").skip(1).all(|declaration| {
        let Some((_, rest)) = declaration.split_once(['"', '\'']) else {
            return false;
        };
        rest.split_once(['"', '\''])
            .is_some_and(|(namespace, _)| NAMESPACES.contains(&namespace))
    })
}

/// The primary's XMP for a map of `length` bytes: Ultra HDR's version and container directory, and nothing of what
/// the source's XMP held.
fn directory(version: &str, length: usize) -> Vec<u8> {
    format!(
        "<?xpacket begin=\"\u{feff}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\
         <x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\
         <rdf:Description rdf:about=\"\" xmlns:hdrgm=\"http://ns.adobe.com/hdr-gain-map/1.0/\" \
         xmlns:Container=\"http://ns.google.com/photos/1.0/container/\" \
         xmlns:Item=\"http://ns.google.com/photos/1.0/container/item/\" hdrgm:Version=\"{version}\">\
         <Container:Directory><rdf:Seq><rdf:li rdf:parseType=\"Resource\">\
         <Container:Item Item:Mime=\"image/jpeg\" Item:Semantic=\"Primary\" Item:Length=\"0\"/></rdf:li>\
         <rdf:li rdf:parseType=\"Resource\">\
         <Container:Item Item:Mime=\"image/jpeg\" Item:Semantic=\"GainMap\" Item:Length=\"{length}\"/></rdf:li>\
         </rdf:Seq></Container:Directory></rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end=\"w\"?>"
    )
    .into_bytes()
}

/// The `hdrgm:Version` an XMP packet declares.
fn version(xmp: &[u8]) -> Option<String> {
    let text = std::str::from_utf8(xmp).ok()?;
    let (_, rest) = text.split_once("hdrgm:Version=\"")?;
    let (version, _) = rest.split_once('"')?;
    (version.len() <= 8 && version.chars().all(|c| c.is_ascii_digit() || c == '.')).then(|| version.to_owned())
}

/// Apple's headroom as the map's own XMP says it (newer files), else the primary's maker note (older ones).
fn apple_headroom(xmp: &[u8], primary: &[Segment<'_>]) -> Option<f64> {
    let text = String::from_utf8_lossy(xmp);
    let key = "HDRGainMap:HDRGainMapHeadroom>";
    if let Some((_, rest)) = text.split_once(key) {
        let value = rest.split('<').next()?.trim().parse::<f64>().ok()?;
        return (value.is_finite() && value >= 1.0).then_some(value);
    }
    let exif = (primary.iter()).find(|s| s.marker == 0xe1 && s.payload.starts_with(b"Exif\0\0"))?;
    crate::heif::apple_headroom_of(exif.payload.get(6..)?)
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// The gain map of the JPEG at `path`, read without the picture: its header, and the map's bytes by the index. None
/// when there is none, or its metadata is more than a gain map's.
pub fn read(path: &Path) -> Option<GainMap> {
    let mut file = File::open(path).ok()?;
    let size = file.metadata().ok()?.len();
    let mut header = vec![];
    (&mut file).take(HEADER).read_to_end(&mut header).ok()?;
    let primary = segments(&header)?;
    let xmp = app(&primary, 0xe1, XMP);
    let iso = app(&primary, 0xe2, ISO);
    for (start, length) in pictures(&primary, size)?.into_iter().skip(1) {
        let mut image = vec![0; usize::try_from(length).ok()?];
        file.seek(SeekFrom::Start(start)).ok()?;
        file.read_exact(&mut image).ok()?;
        let parts = segments(&image)?;
        let secondary: Vec<(u8, Vec<u8>)> = (parts.iter())
            .filter(|s| {
                (s.marker == 0xe1 && s.payload.starts_with(XMP)) || (s.marker == 0xe2 && s.payload.starts_with(ISO))
            })
            .map(|s| (s.marker, s.payload.to_vec()))
            .collect();
        let apple = (secondary.iter())
            .find(|(marker, payload)| *marker == 0xe1 && contains(payload, APPLE_GAIN_MAP))
            .map(|(_, payload)| apple_headroom(payload, &primary));
        if let Some(headroom) = apple {
            let headroom = headroom?;
            return Some(GainMap {
                image,
                carried: Carried::of(&Boost::apple(headroom))?,
                apple: Some(headroom),
            });
        }
        let says_so = (secondary.iter()).any(|(marker, payload)| *marker == 0xe2 || contains(payload, b"hdr-gain-map"));
        if !says_so {
            continue;
        }
        if (secondary.iter()).any(|(marker, payload)| *marker == 0xe1 && !only_gain_map_namespaces(payload)) {
            return None;
        }
        let version = xmp.as_deref().and_then(version);
        return Some(GainMap {
            image,
            carried: Carried {
                version,
                iso,
                secondary,
            },
            apple: None,
        });
    }
    None
}

/// A segment of `marker` with `parts` as its payload.
fn segment(marker: u8, parts: &[&[u8]]) -> Option<Vec<u8>> {
    let length = parts.iter().try_fold(2usize, |n, part| n.checked_add(part.len()))?;
    let mut bytes = vec![0xff, marker];
    bytes.extend(u16::try_from(length).ok()?.to_be_bytes());
    for part in parts {
        bytes.extend(*part);
    }
    Some(bytes)
}

/// The Multi-Picture Format index segment of a file whose first picture is `size` bytes and whose map, `map_size`
/// bytes, starts `offset` bytes after the byte-order mark. It has the same size whatever it says.
fn index(size: u32, map_size: u32, offset: u32) -> Option<Vec<u8>> {
    let mut tiff = b"II*\0\x08\0\0\0\x03\0".to_vec();
    tiff.extend([0x00, 0xb0, 7, 0, 4, 0, 0, 0]);
    tiff.extend(b"0100");
    tiff.extend([0x01, 0xb0, 4, 0, 1, 0, 0, 0, 2, 0, 0, 0]);
    // MPEntry: 2 × 16 bytes, at 8 + 2 + 3 × 12 + 4 = 50.
    tiff.extend([0x02, 0xb0, 7, 0, 32, 0, 0, 0, 50, 0, 0, 0, 0, 0, 0, 0]);
    // The primary, then the map.
    tiff.extend(0x2003_0000u32.to_le_bytes());
    tiff.extend(size.to_le_bytes());
    tiff.extend([0; 8]);
    tiff.extend(0u32.to_le_bytes());
    tiff.extend(map_size.to_le_bytes());
    tiff.extend(offset.to_le_bytes());
    tiff.extend([0; 4]);
    segment(0xe2, &[MPF, &tiff])
}

/// `primary`, a JPEG with no gain map, together with `image`, the map (a JPEG without metadata, scaled and turned by
/// the caller), as one file: the container's XMP and index say where the map is. None when the pair cannot be
/// written, in which case the caller keeps the plain picture.
pub fn attach(primary: &[u8], carried: &Carried, image: &[u8]) -> Option<Vec<u8>> {
    if segments(image)?.iter().any(|s| s.marker == 0xe1 || s.marker == 0xe2) {
        return None;
    }
    let (soi, rest) = image.split_at_checked(2)?;
    let mut secondary = soi.to_vec();
    for (marker, payload) in &carried.secondary {
        secondary.extend(segment(*marker, &[payload])?);
    }
    secondary.extend(rest);

    let xmp = match &carried.version {
        Some(version) => Some(segment(0xe1, &[XMP, &directory(version, secondary.len())])?),
        None => None,
    };
    let iso = match &carried.iso {
        Some(iso) => Some(segment(0xe2, &[ISO, iso])?),
        None => None,
    };
    // After the JFIF header, if any, and before everything else.
    let after = segments(primary)?
        .iter()
        .find(|s| s.marker != 0xe0)
        .map_or(primary.len(), |s| s.at);
    let extra = [&xmp, &iso]
        .into_iter()
        .flatten()
        .try_fold(0usize, |n, s| n.checked_add(s.len()))?;
    let map_size = u32::try_from(secondary.len()).ok()?;
    let total = u32::try_from(primary.len().checked_add(extra)?.checked_add(index(0, 0, 0)?.len())?).ok()?;
    // The byte-order mark sits 8 bytes into the segment, which starts where the XMP and ISO segments end.
    let mark = u32::try_from(after.checked_add(extra)?.checked_add(8)?).ok()?;
    let index = index(total, map_size, total.checked_sub(mark)?)?;
    let (head, tail) = primary.split_at_checked(after)?;
    let mut bytes = head.to_vec();
    bytes.extend(xmp.into_iter().flatten());
    bytes.extend(iso.into_iter().flatten());
    bytes.extend(index);
    bytes.extend(tail);
    bytes.extend(secondary);
    Some(bytes)
}

/// The map of Apple's gain map pixels: a Rec.709-coded luminance of 0 to 255 as the code of the same boost in
/// `boost.max` stops, linear in the gain (gamma 1), which is how every reader of Ultra HDR applies it. One byte each.
pub fn apple_map(headroom: f64) -> [u8; 256] {
    let stops = headroom.max(1.0).log2();
    let mut lut = [0u8; 256];
    for (code, out) in (0u8..=255).zip(lut.iter_mut()) {
        let v = f64::from(code) / 255.0;
        // Rec.709's transfer function, undone.
        let linear = if v < 0.081 {
            v / 4.5
        } else {
            ((v + 0.099) / 1.099).powf(1.0 / 0.45)
        };
        let gain = (headroom - 1.0).mul_add(linear, 1.0).log2();
        // Clamped to the range of a byte, and rounded.
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let coded = (255.0 * gain / stops).round().clamp(0.0, 255.0) as u8;
        *out = if stops > 0.0 { coded } else { 0 };
    }
    lut
}

// Expected values of the tests are written as the documents give them, and compared as they are computed.
#[allow(
    clippy::float_cmp,
    clippy::suboptimal_flops,
    clippy::unreadable_literal,
    clippy::assert_is_empty,
    clippy::cast_precision_loss
)]
#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    /// A corpus Ultra HDR JPEG: 4,032 × 3,024, its gain map 6,822 bytes behind it.
    fn corpus(name: &str) -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../testdata/corpus/files")
            .join(name)
    }

    #[test]
    fn the_gain_map_of_an_ultra_hdr_jpeg_is_read_with_its_own_metadata() {
        let map = read(&corpus("hdr/ultra-hdr.jpg")).expect("a gain map");
        assert_eq!(map.image.len(), 6822);
        assert!(map.image.starts_with(&[0xff, 0xd8]));
        let parts = segments(&map.image).unwrap();
        let xmp = app(&parts, 0xe1, XMP).unwrap();
        assert!(contains(&xmp, b"hdrgm:GainMapMax=\"2.5\""));
        assert_eq!(map.carried.version.as_deref(), Some("1.0"));
        assert_eq!(map.carried.iso, None);
    }

    /// libvips, started once and used by one test at a time: its classes register on first use.
    fn vips() -> std::sync::MutexGuard<'static, ()> {
        static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
        let guard = LOCK.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        rs_vips::Vips::init("gainmap test").ok();
        guard
    }

    /// A JPEG of `width` × `height` made by libvips, as the renditions are.
    fn jpeg(width: i32, height: i32, bands: i32) -> Vec<u8> {
        use rs_vips::{
            VipsImage,
            voption::{Setter, VOption},
        };
        let _vips = vips();
        let image = VipsImage::black_with_opts(width, height, VOption::new().set("bands", bands)).unwrap();
        let image = image.cast(rs_vips::enums::BandFormat::Uchar).unwrap();
        image
            .jpegsave_buffer_with_opts(VOption::new().set("keep", rs_vips::enums::ForeignKeep::None as i32))
            .unwrap()
    }

    fn jpeg_size(bytes: &[u8]) -> (i32, i32) {
        let _vips = vips();
        let image = rs_vips::VipsImage::jpegload_buffer(bytes).unwrap();
        (image.get_width(), image.get_height())
    }

    #[test]
    fn a_gain_map_attached_to_another_picture_is_read_back_with_its_new_length_and_offset() {
        let map = read(&corpus("hdr/ultra-hdr.jpg")).unwrap();
        let (primary, small) = (jpeg(64, 48, 3), jpeg(16, 12, 1));
        let both = attach(&primary, &map.carried, &small).expect("a pair");
        let file = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(file.path(), &both).unwrap();
        let back = read(file.path()).expect("the pair reads back");
        assert!(back.image.len() > small.len(), "the map keeps its own metadata");
        assert!(back.image.len() < both.len() - primary.len());
        let xmp = app(&segments(&both).unwrap(), 0xe1, XMP).unwrap();
        let xmp = String::from_utf8(xmp).unwrap();
        assert!(
            xmp.contains(&format!(
                "Item:Semantic=\"GainMap\" Item:Length=\"{}\"",
                back.image.len()
            )),
            "{xmp}"
        );
        let parts = segments(&back.image).unwrap();
        assert!(contains(&app(&parts, 0xe1, XMP).unwrap(), b"hdrgm:GainMapMax=\"2.5\""));
        // The primary ends where the map begins, and both decode at the sizes they were given.
        let at = both.len() - back.image.len();
        assert_eq!(&both[at..], &back.image[..]);
        let (first, second) = (jpeg_size(&both[..at]), jpeg_size(&back.image));
        assert_eq!((first, second), ((64, 48), (16, 12)));
        let found = pictures(&segments(&both).unwrap(), both.len() as u64).unwrap();
        assert_eq!(found[1], (at as u64, back.image.len() as u64));
    }

    #[test]
    fn nothing_but_the_gain_maps_own_metadata_travels_into_a_rendition() {
        let map = read(&corpus("hdr/ultra-hdr.jpg")).unwrap();
        // A source's XMP never travels: the primary's is written afresh from its version.
        let both = attach(&jpeg(8, 8, 3), &map.carried, &jpeg(4, 4, 1)).unwrap();
        let text = String::from_utf8(app(&segments(&both).unwrap(), 0xe1, XMP).unwrap()).unwrap();
        assert!(text.contains("hdrgm:Version=\"1.0\"") && !text.contains("GPS") && !text.contains("exif"));
        // A map whose own XMP carries other namespaces is no gain map to keep.
        let mut foreign = std::fs::read(corpus("hdr/ultra-hdr.jpg")).unwrap();
        let at = foreign.len() - 6822;
        let marker = foreign[at..].windows(12).position(|w| w == b"xmlns:hdrgm=").unwrap() + at;
        foreign.splice(
            marker..marker,
            b"xmlns:dc=\"http://purl.org/dc/elements/1.1/\" ".iter().copied(),
        );
        let length = u16::from_be_bytes([foreign[at + 4], foreign[at + 5]]) + 43;
        assert_eq!(foreign[at + 3], 0xe1);
        foreign[at + 4..at + 6].copy_from_slice(&length.to_be_bytes());
        let file = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(file.path(), &foreign).unwrap();
        assert_eq!(read(file.path()), None);
        // A map with metadata of its own cannot be attached: it would be written twice.
        assert_eq!(attach(&jpeg(8, 8, 3), &map.carried, &map.image), None);
    }

    /// An Apple JPEG: the pictures of `attach`, the map's XMP as Apple writes it (`headroom` in it or not), and a
    /// primary with an EXIF APP1 that holds Apple's maker note when `note` is.
    fn apple_jpeg(headroom: Option<&str>, note: bool) -> tempfile::NamedTempFile {
        let apdi = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\
                    <rdf:Description rdf:about=\"\" xmlns:apdi=\"http://ns.apple.com/pixeldatainfo/1.0/\" \
                    xmlns:HDRGainMap=\"http://ns.apple.com/HDRGainMap/1.0/\"><apdi:AuxiliaryImageType>\
                    urn:com:apple:photo:2020:aux:hdrgainmap</apdi:AuxiliaryImageType>";
        let end = "</rdf:Description></rdf:RDF></x:xmpmeta>";
        let headroom = headroom.map_or(String::new(), |h| {
            format!("<HDRGainMap:HDRGainMapHeadroom>{h}</HDRGainMap:HDRGainMapHeadroom>")
        });
        let carried = Carried {
            version: None,
            iso: None,
            secondary: vec![(0xe1, [XMP, format!("{apdi}{headroom}{end}").as_bytes()].concat())],
        };
        let mut primary = jpeg(8, 8, 3);
        if note {
            // An Exif APP1 after the start of image, holding the maker note of a phone whose tag 33 is 0.8786.
            let mut note = b"Apple iOS\0\0\x01MM\0\x01".to_vec();
            note.extend([0, 0x21, 0, 10, 0, 0, 0, 1]);
            note.extend((14u32 + 2 + 12 + 4).to_be_bytes());
            note.extend([0; 4]);
            note.extend(22307i32.to_be_bytes());
            note.extend(25388i32.to_be_bytes());
            let mut tiff = b"MM\0*\0\0\0\x08".to_vec();
            tiff.extend([0, 1, 0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26, 0, 0, 0, 0]);
            tiff.extend([0, 1, 0x92, 0x7c, 0, 7]);
            tiff.extend((note.len() as u32).to_be_bytes());
            tiff.extend(44u32.to_be_bytes());
            tiff.extend([0; 4]);
            tiff.extend(note);
            let exif = segment(0xe1, &[b"Exif\0\0", &tiff]).unwrap();
            primary.splice(2..2, exif);
        }
        let both = attach(&primary, &carried, &jpeg(4, 4, 1)).unwrap();
        let file = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(file.path(), both).unwrap();
        file
    }

    #[test]
    fn apples_jpeg_gain_map_is_found_by_its_type_with_its_headroom_from_the_xmp_or_the_maker_note() {
        // Newer files say it in the map's XMP, as 4.53 times.
        let newer = apple_jpeg(Some("4.532783"), false);
        let map = read(newer.path()).expect("a gain map");
        assert!((map.apple.unwrap() - 4.532783).abs() < 1e-9);
        let boost = Boost::from_iso(&map.carried.secondary[1].1[ISO.len()..]).unwrap();
        assert!((boost.max[0] - 4.532783_f64.log2()).abs() < 1e-5 && boost.gamma == [1.0; 3]);
        // Older files leave it to the primary's maker note: tag 33 of 0.8786 is 1.8 stops.
        let older = apple_jpeg(None, true);
        assert!((read(older.path()).unwrap().apple.unwrap().log2() - 1.8).abs() < 1e-9);
        // Neither: nothing says how strong it is, so there is no map to apply.
        assert_eq!(read(apple_jpeg(None, false).path()), None);
        // A headroom that is no number, or below 1, is none.
        assert_eq!(read(apple_jpeg(Some("0.5"), false).path()), None);
        assert_eq!(read(apple_jpeg(Some("lots"), false).path()), None);
    }

    #[test]
    fn jpegs_without_a_gain_map_have_none() {
        for name in [
            "hdr/samsung-gain-map.jpg",
            "stills/baseline.jpg",
            "hdr/hlg.avif",
            "nothing",
        ] {
            assert_eq!(read(&corpus(name)), None, "{name}");
        }
    }

    /// The metadata of a real Samsung HEIC's `tmap` item, after its version byte: 2.3 stops, one channel.
    const SAMSUNG: &str = "0000000000400000000000000001009333330040000000000000000000010093333300400000000000010000000100\
                           000000000000010000000000000001";

    fn hex(text: &str) -> Vec<u8> {
        (0..text.len())
            .step_by(2)
            .map(|n| u8::from_str_radix(&text[n..n + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn iso_21496_1_metadata_of_a_real_phone_reads_and_is_written_again_for_a_jpeg() {
        let boost = Boost::from_iso(&hex(SAMSUNG)[1..]).expect("it reads");
        let stops = 9_646_899.0 / 4_194_304.0;
        assert_eq!(boost.min, [0.0; 3]);
        assert!((boost.max[0] - stops).abs() < 1e-9 && boost.max[1] == boost.max[0]);
        assert_eq!(
            (boost.gamma, boost.offset_sdr, boost.offset_hdr),
            ([1.0; 3], [0.0; 3], [0.0; 3])
        );
        assert_eq!((boost.capacity_min, boost.multichannel), (0.0, false));
        assert!((boost.capacity_max - stops).abs() < 1e-9);
        // Written in fractions of a millionth, it reads back to the same within one.
        let again = Boost::from_iso(&boost.iso().unwrap()).unwrap();
        assert!((again.max[0] - stops).abs() < 1e-6 && again.gamma == [1.0; 3]);
        let xmp = String::from_utf8(boost.xmp()).unwrap();
        assert!(xmp.contains("hdrgm:GainMapMax=\"2.299"), "{xmp}");
        assert!(xmp.contains("hdrgm:Version=\"1.0\"") && xmp.contains("hdrgm:BaseRenditionIsHDR=\"False\""));
        assert!(only_gain_map_namespaces(&boost.xmp()));
    }

    #[test]
    fn iso_metadata_that_cannot_be_applied_forward_or_is_cut_short_is_refused() {
        let good = hex(SAMSUNG)[1..].to_vec();
        let mut backward = good.clone();
        backward[4] |= 4;
        assert_eq!(
            Boost::from_iso(&backward),
            None,
            "a map from the HDR picture to the SDR one"
        );
        let mut newer = good.clone();
        newer[1] = 1;
        assert_eq!(Boost::from_iso(&newer), None, "a version this does not read");
        assert_eq!(Boost::from_iso(&good[..good.len() - 1]), None);
        assert_eq!(Boost::from_iso(&[]), None);
        // A base picture that is the brighter one (HDR, with a map down to SDR) is no map to apply to an SDR rendition:
        // libavif's seine_hdr_gainmap files, 2.46 stops at the base and 0 at the alternate.
        let mut hdr_base = Boost::from_iso(&good).unwrap();
        std::mem::swap(&mut hdr_base.capacity_min, &mut hdr_base.capacity_max);
        assert_eq!(
            Boost::from_iso(&hdr_base.iso().unwrap()),
            None,
            "a map from the HDR picture down"
        );
        // A zero denominator is no number.
        let mut zero = good;
        zero[9..13].copy_from_slice(&[0; 4]);
        assert_eq!(Boost::from_iso(&zero), None);
    }

    #[test]
    fn a_multichannel_map_says_each_channel_in_xmp_and_in_iso() {
        let mut boost = Boost::apple(4.0);
        boost.multichannel = true;
        boost.max = [2.0, 1.5, 1.0];
        let xmp = String::from_utf8(boost.xmp()).unwrap();
        assert!(xmp.contains("<hdrgm:GainMapMax><rdf:Seq><rdf:li>2</rdf:li><rdf:li>1.5</rdf:li><rdf:li>1</rdf:li>"));
        assert!(!xmp.contains("hdrgm:GainMapMax=\""));
        let again = Boost::from_iso(&boost.iso().unwrap()).unwrap();
        assert_eq!((again.max, again.multichannel), ([2.0, 1.5, 1.0], true));
    }

    #[test]
    fn apples_map_is_recoded_so_that_a_linear_gain_applies_its_formula() {
        let headroom = 2.0_f64.powf(1.8);
        let lut = apple_map(headroom);
        assert_eq!((lut[0], lut[255]), (0, 255));
        assert!(lut.windows(2).all(|w| w[0] <= w[1]), "monotone");
        // Apple: hdr = sdr × (1 + (headroom − 1) × linear(code)); here sdr × 2^(stops × lut / 255).
        for code in [20u32, 64, 128, 200] {
            let v = f64::from(code) / 255.0;
            let linear = ((v + 0.099) / 1.099).powf(1.0 / 0.45);
            let wanted = 1.0 + (headroom - 1.0) * linear;
            let got = (1.8 * f64::from(lut[code as usize]) / 255.0).exp2();
            assert!((got / wanted - 1.0).abs() < 0.01, "code {code}: {got} against {wanted}");
        }
        assert_eq!(apple_map(1.0), [0; 256], "no headroom, no gain");
    }
}
