//! IPTC IIM, the legacy records of captions, keywords and credits, and the Photoshop image resources that carry them.

use super::claim;
use super::file::uint;
use crate::proto::model::v1::CaptureTime;

#[derive(Default)]
pub struct Iim {
    pub title: Option<String>,
    pub description: Option<String>,
    pub keywords: Vec<String>,
    pub creators: Vec<String>,
    pub city: Option<String>,
    pub state: Option<String>,
    pub country: Option<String>,
    pub copyright: Option<String>,
    pub time: Option<CaptureTime>,
}

/// The IIM block and the IPTC digest, the MD5 of the IIM block that the last writer of the XMP saw, from Photoshop
/// image resources.
pub fn resources(data: &[u8]) -> (Option<&[u8]>, Option<&[u8]>) {
    let (mut iim, mut digest) = (None, None);
    let mut at = 0;
    while let Some(head) = data.get(at..at + 7).filter(|h| h.starts_with(b"8BIM")) {
        // The name is a Pascal string padded to an even length.
        let size_at = at + 6 + ((usize::from(head[6]) + 2) & !1);
        let Some(size) = data.get(size_at..size_at + 4).map(|s| uint(s, true) as usize) else {
            break;
        };
        let Some(body) = data.get(size_at + 4..).and_then(|b| b.get(..size)) else {
            break;
        };
        match uint(&head[4..6], true) {
            0x0404 => iim = Some(body),
            0x0425 => digest = Some(body),
            _ => {}
        }
        at = size_at + 4 + size + (size & 1);
    }
    (iim, digest)
}

pub fn read(block: &[u8]) -> Iim {
    let mut records = vec![];
    let mut at = 0;
    while let Some(&[0x1c, record, dataset, high, low]) = block.get(at..at + 5) {
        let mut len = usize::from(u16::from_be_bytes([high, low]));
        at += 5;
        if len & 0x8000 != 0 {
            // An extended dataset: the low bits count the bytes of the length that follows.
            let Some(bytes) = block.get(at..at + (len & 0x7fff)).filter(|b| b.len() <= 4) else {
                break;
            };
            at += bytes.len();
            len = uint(bytes, true) as usize;
        }
        let Some(data) = block.get(at..).and_then(|d| d.get(..len)) else {
            break;
        };
        records.push((record, dataset, data));
        at += len;
    }
    let utf8 = records.contains(&(1, 90, b"\x1b%G"));
    let text = |data: &[u8]| {
        let text = match std::str::from_utf8(data) {
            Ok(text) => text.to_string(),
            Err(_) if utf8 => String::from_utf8_lossy(data).into_owned(),
            Err(_) => data.iter().map(|&b| char::from(b)).collect(),
        };
        Some(text.trim().to_string()).filter(|t| !t.is_empty())
    };
    let mut iim = Iim::default();
    let (mut date, mut time) = (None, None);
    for (_, dataset, data) in records.into_iter().filter(|r| r.0 == 2) {
        let value = text(data);
        match dataset {
            5 => iim.title = value,
            25 => iim.keywords.extend(value),
            55 => date = value,
            60 => time = value,
            80 => iim.creators.extend(value),
            90 => iim.city = value,
            95 => iim.state = value,
            101 => iim.country = value,
            116 => iim.copyright = value,
            120 => iim.description = value,
            _ => {}
        }
    }
    iim.time = date.map(|date| {
        // CCYYMMDD and HHMMSS±HHMM.
        let digits = |text: &str, n| text.len() >= n && text.bytes().take(n).all(|b| b.is_ascii_digit());
        let time = time.filter(|t| digits(t, 6));
        let text = match (&time, digits(&date, 8)) {
            (Some(t), true) => format!(
                "{}-{}-{}T{}:{}:{}",
                &date[..4],
                &date[4..6],
                &date[6..8],
                &t[..2],
                &t[2..4],
                &t[4..6]
            ),
            (None, true) => format!("{}-{}-{}", &date[..4], &date[4..6], &date[6..8]),
            (_, false) => date,
        };
        claim(
            "iptc:DateCreated",
            &text,
            None,
            time.as_deref().and_then(|t| t.get(6..)),
        )
    });
    iim
}
