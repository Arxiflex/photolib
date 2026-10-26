//! Formats by their magic bytes, never by a file's name.

/// The version of `sniff` each asset records: bump it when `sniff` names a new format as a photo or video, so that the
/// `retype` sweep checks again the assets an older version found none in (ADR-0066).
pub const VERSION: i16 = 1;

/// What a file's first bytes say it is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Media {
    pub container: &'static str,
    pub mime: &'static str,
    pub kind: Kind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Image,
    Video,
    Audio,
    Document,
    Unknown,
}

impl Media {
    /// Kinds the server keeps: anything else is listed, never ingested as media (docs/08 §3.5).
    pub fn supported(&self) -> bool {
        matches!(self.kind, Kind::Image | Kind::Video) && self.container != "svg"
    }
}

const fn media(container: &'static str, mime: &'static str, kind: Kind) -> Media {
    Media { container, mime, kind }
}

pub fn sniff(head: &[u8]) -> Media {
    use Kind::*;
    let at = |offset: usize, magic: &[u8]| head.get(offset..).is_some_and(|h| h.starts_with(magic));
    let image = |container, mime| media(container, mime, Image);
    let video = |container, mime| media(container, mime, Video);
    match head {
        [0xff, 0xd8, 0xff, ..] => image("jpeg", "image/jpeg"),
        [0x89, b'P', b'N', b'G', ..] if chunk(head, b"acTL") => image("png", "image/apng"),
        [0x89, b'P', b'N', b'G', ..] => image("png", "image/png"),
        [b'G', b'I', b'F', b'8', b'7' | b'9', b'a', ..] => image("gif", "image/gif"),
        [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] => image("webp", "image/webp"),
        [b'R', b'I', b'F', b'F', _, _, _, _, b'A', b'V', b'I', b' ', ..] => video("avi", "video/x-msvideo"),
        [b'B', b'M', ..] => image("bmp", "image/bmp"),
        [b'8', b'B', b'P', b'S', ..] => image("psd", "image/vnd.adobe.photoshop"),
        [0xff, 0x0a, ..] | [0, 0, 0, 0x0c, b'J', b'X', b'L', b' ', ..] => image("jxl", "image/jxl"),
        _ if at(0, b"FUJIFILMCCD-RAW") => image("raf", "image/x-fuji-raf"),
        [b'I', b'I', b'*' | b'+', 0, ..]
        | [b'M', b'M', 0, b'*' | b'+', ..]
        | [b'I', b'I', b'R', b'O' | b'S', ..]
        | [b'M', b'M', b'O', b'R', ..]
        | [b'I', b'I', b'U', 0, ..] => image("tiff", tiff(head)),
        _ if at(4, b"ftyp") => isobmff(head),
        _ if [b"moov", b"mdat", b"wide", b"free", b"pnot"].iter().any(|b| at(4, *b)) => {
            video("isobmff", "video/quicktime")
        }
        [0x1a, 0x45, 0xdf, 0xa3, ..] if find(head, b"webm") => video("ebml", "video/webm"),
        [0x1a, 0x45, 0xdf, 0xa3, ..] => video("ebml", "video/x-matroska"),
        [0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11, ..] => video("asf", "video/x-ms-wmv"),
        [b'F', b'L', b'V', 1, ..] => video("flv", "video/x-flv"),
        [0x47, ..] if at(188, &[0x47]) => video("mpegts", "video/mp2t"),
        [_, _, _, _, 0x47, ..] if at(196, &[0x47]) => video("m2ts", "video/mp2t"),
        [0, 0, 1, 0xba, ..] => video("mpegps", "video/mpeg"),
        [b'O', b'g', b'g', b'S', ..] => media("ogg", "audio/ogg", Audio),
        _ if at(0, b"%PDF-") => media("pdf", "application/pdf", Document),
        _ if at(0, b"%!PS-Adobe") || at(0, &[0xc5, 0xd0, 0xd3, 0xc6]) => {
            media("eps", "application/postscript", Document)
        }
        _ if svg(head) => image("svg", "image/svg+xml"),
        _ => media("unknown", "application/octet-stream", Unknown),
    }
}

/// An ISOBMFF file by its brands: HEIF and AVIF stills, Canon's CR3, and movies.
fn isobmff(head: &[u8]) -> Media {
    let size = head
        .get(..4)
        .map_or(0, |b| u32::from_be_bytes(b.try_into().unwrap()) as usize);
    let brands = head.get(8..size.min(head.len())).unwrap_or_default();
    let major = brands.get(..4).unwrap_or_default();
    // A generic major brand (mif1, msf1, miaf) leaves the choice to the compatible ones.
    let has = |brand: &[u8]| major == brand || brands.chunks(4).skip(2).any(|b| b == brand);
    let image = |mime| media("isobmff", mime, Kind::Image);
    let video = |mime| media("isobmff", mime, Kind::Video);
    match major {
        b"qt  " => video("video/quicktime"),
        b"crx " => image("image/x-canon-cr3"),
        [b'3', b'g', b'2', _] => video("video/3gpp2"),
        [b'3', b'g', _, _] => video("video/3gpp"),
        _ if has(b"avif") || has(b"avis") => image("image/avif"),
        _ if [b"heic", b"heix", b"heim", b"heis", b"hevc", b"hevx", b"mif1", b"msf1"]
            .iter()
            .any(|b| has(*b)) =>
        {
            image("image/heic")
        }
        _ => video("video/mp4"),
    }
}

/// A TIFF's MIME type: plain, or a camera's RAW format by its signature, DNGVersion or IFD0 Make.
fn tiff(head: &[u8]) -> &'static str {
    match head.get(..4) {
        Some(b"IIRO" | b"IIRS" | b"MMOR") => return "image/x-olympus-orf",
        Some(b"IIU\0") => return "image/x-panasonic-rw2",
        _ if head.get(8..10) == Some(b"CR") => return "image/x-canon-cr2",
        _ => {}
    }
    let big = head.starts_with(b"MM");
    let int = |at: usize, len: usize| -> Option<u64> {
        let bytes = head.get(at..at + len)?;
        Some(match big {
            true => bytes.iter().fold(0, |n, &b| n << 8 | u64::from(b)),
            false => bytes.iter().rev().fold(0, |n, &b| n << 8 | u64::from(b)),
        })
    };
    // BigTIFF has 8-byte offsets and counts and 20-byte entries.
    let (wide, step) = match int(2, 2) {
        Some(43) => (8, 20),
        _ => (4, 12),
    };
    let Some(ifd) = int(if wide == 8 { 8 } else { 4 }, wide)
        .map(|at| at as usize)
        .filter(|&at| at < head.len())
    else {
        return "image/tiff";
    };
    let count = int(ifd, if wide == 8 { 8 } else { 2 }).unwrap_or(0).min(512) as usize;
    let first = ifd + if wide == 8 { 8 } else { 2 };
    let mut make = &b""[..];
    for entry in (0..count).map(|n| first + n * step) {
        match int(entry, 2) {
            Some(0xc612) => return "image/x-adobe-dng",
            Some(0x010f) => {
                let len = int(entry + 4, wide).unwrap_or(0) as usize;
                let at = match len <= wide {
                    true => entry + 4 + wide,
                    false => int(entry + 4 + wide, wide).map_or(usize::MAX, |at| at as usize),
                };
                make = head.get(at..at.saturating_add(len)).unwrap_or_default();
            }
            _ => {}
        }
    }
    let make = String::from_utf8_lossy(make).to_lowercase();
    match () {
        _ if make.starts_with("nikon") => "image/x-nikon-nef",
        _ if make.starts_with("sony") => "image/x-sony-arw",
        _ if make.starts_with("pentax") || make.starts_with("ricoh") => "image/x-pentax-pef",
        _ => "image/tiff",
    }
}

/// A PNG chunk of this type before the image data.
fn chunk(head: &[u8], kind: &[u8; 4]) -> bool {
    let mut at = 8;
    while let Some(len) = head.get(at..at + 4) {
        let name = head.get(at + 4..at + 8);
        if name == Some(kind) {
            return true;
        }
        if name == Some(b"IDAT") {
            return false;
        }
        at += 12 + u32::from_be_bytes(len.try_into().unwrap()) as usize;
    }
    false
}

fn find(head: &[u8], needle: &[u8]) -> bool {
    head.windows(needle.len()).any(|w| w == needle)
}

/// Text that is an SVG document: an svg element after an optional prolog, comments and whitespace.
fn svg(head: &[u8]) -> bool {
    let text = String::from_utf8_lossy(head);
    let text = text.trim_start_matches('\u{feff}').trim_start();
    text.starts_with('<') && text.contains("<svg")
}

#[cfg(test)]
pub(crate) mod tests {
    use serde_json::Value;

    use super::*;

    const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../testdata/corpus");

    /// Every golden record of the media corpus with its file's bytes.
    pub fn corpus() -> Vec<(Value, Vec<u8>)> {
        let mut found = vec![];
        let mut dirs = vec![std::path::Path::new(CORPUS).join("golden")];
        while let Some(dir) = dirs.pop() {
            for entry in std::fs::read_dir(dir).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    dirs.push(path);
                    continue;
                }
                let record: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
                let file = format!("{CORPUS}/files/{}", record["path"].as_str().unwrap());
                found.push((record, std::fs::read(file).unwrap()));
            }
        }
        found.sort_by(|a, b| a.0["path"].as_str().cmp(&b.0["path"].as_str()));
        assert!(found.len() > 300, "the corpus is missing: {CORPUS}");
        found
    }

    /// Every corpus file is what its golden record's media says, from its first 4 KiB alone: names with the wrong
    /// extension or none are the corpus' own cases (extension_mismatch, no_extension).
    #[test]
    fn the_corpus_is_identified_by_its_magic_bytes() {
        let mut wrong = vec![];
        for (record, data) in corpus() {
            let path = record["path"].as_str().unwrap();
            let media = sniff(&data[..data.len().min(4096)]);
            let golden = &record["media"];
            let want = (
                golden["container"].as_str().unwrap(),
                golden["mime"].as_str().unwrap(),
                golden["kind"].as_str().unwrap(),
            );
            let kind = format!("{:?}", media.kind).to_lowercase();
            let got = (media.container, media.mime, kind.as_str());
            let supported = golden["support"] == "supported";
            if got != want || media.supported() != supported {
                wrong.push(format!("{path}: want {want:?} {supported}, got {got:?}"));
            }
        }
        assert!(wrong.is_empty(), "{}", wrong.join("\n"));
    }

    /// Hostile heads: every prefix and every byte changed of each kind of corpus file returns, never panics.
    #[test]
    fn damaged_heads_never_panic() {
        let mut seen = std::collections::HashSet::new();
        for (record, data) in corpus() {
            if !seen.insert(record["media"]["mime"].to_string()) {
                continue;
            }
            let head = &data[..data.len().min(512)];
            for end in 0..head.len() {
                sniff(&head[..end]);
            }
            for at in 0..head.len() {
                for byte in [0, 0x7f, 0xff] {
                    let mut damaged = head.to_vec();
                    damaged[at] = byte;
                    sniff(&damaged);
                }
            }
        }
    }
}
