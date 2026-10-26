use serde::{Deserialize, Serialize};

use crate::Failure;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Format {
    Png,
    Jpeg,
    Gif,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Probe {
    pub format: Format,
    pub width: u32,
    pub height: u32,
}

/// Reads the format and dimensions from the start of a file and refuses an image with more than `max_pixels`
/// pixels before anything decodes it: the defence against decompression bombs.
pub fn probe(head: &[u8], max_pixels: u64) -> Result<Probe, Failure> {
    let probe = dimensions(head).ok_or_else(|| Failure::Unsupported("unknown format".into()))?;
    let pixels = u64::from(probe.width) * u64::from(probe.height);
    if pixels > max_pixels {
        return Err(Failure::LimitExceeded(format!(
            "{}×{} is {pixels} pixels, more than the limit of {max_pixels}",
            probe.width, probe.height
        )));
    }
    Ok(probe)
}

fn dimensions(head: &[u8]) -> Option<Probe> {
    let be = |at: usize, len: usize| Some(head.get(at..at + len)?.iter().fold(0, |n, &b| n << 8 | u32::from(b)));
    let le16 = |at: usize| Some(be(at, 1)? | be(at + 1, 1)? << 8);
    let (format, width, height) = if head.starts_with(b"\x89PNG\r\n\x1a\n") {
        (Format::Png, be(16, 4)?, be(20, 4)?)
    } else if head.starts_with(b"GIF87a") || head.starts_with(b"GIF89a") {
        (Format::Gif, le16(6)?, le16(8)?)
    } else if head.starts_with(b"\xff\xd8") {
        // Walk the marker segments to the frame header (SOF0-15 except DHT, JPG and DAC).
        let mut at = 2;
        loop {
            let [0xff, marker] = *head.get(at..at + 2)? else {
                return None;
            };
            match marker {
                0xff => at += 1,
                0x01 | 0xd0..=0xd7 => at += 2,
                0xc0..=0xcf if ![0xc4, 0xc8, 0xcc].contains(&marker) => {
                    break (Format::Jpeg, be(at + 7, 2)?, be(at + 5, 2)?);
                }
                0xd9 | 0xda => return None,
                _ => at += 2 + be(at + 2, 2)? as usize,
            }
        }
    } else {
        return None;
    };
    Some(Probe { format, width, height })
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn png(width: u32, height: u32) -> Vec<u8> {
        let mut file = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
        file.extend(width.to_be_bytes());
        file.extend(height.to_be_bytes());
        file.extend([8, 6, 0, 0, 0]);
        file
    }

    /// A baseline JPEG with an APP0 segment before the frame header, or a progressive one (SOF2).
    pub fn jpeg(width: u16, height: u16, sof: u8) -> Vec<u8> {
        let mut file = b"\xff\xd8\xff\xe0\0\x10JFIF\0\x01\x01\0\0\x01\0\x01\0\0".to_vec();
        file.extend([0xff, sof, 0, 17, 8]);
        file.extend(height.to_be_bytes());
        file.extend(width.to_be_bytes());
        file.extend([3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]);
        file
    }

    #[test]
    fn reads_jpeg_and_gif_dimensions() {
        let at = |format, width, height| Ok(Probe { format, width, height });
        assert_eq!(
            probe(&jpeg(4032, 3024, 0xc0), 300_000_000),
            at(Format::Jpeg, 4032, 3024)
        );
        assert_eq!(probe(&jpeg(1, 65535, 0xc2), 300_000_000), at(Format::Jpeg, 1, 65535));
        assert_eq!(
            probe(b"GIF89a\x40\x01\xf0\x00\x80\0\0", 300_000_000),
            at(Format::Gif, 320, 240)
        );
    }

    #[test]
    fn reads_png_dimensions() {
        assert_eq!(
            probe(&png(640, 480), 300_000_000),
            Ok(Probe {
                format: Format::Png,
                width: 640,
                height: 480
            })
        );
    }

    #[test]
    fn refuses_a_bomb_before_decoding() {
        assert_eq!(
            probe(&png(100_000, 100_000), 300_000_000),
            Err(Failure::LimitExceeded(
                "100000×100000 is 10000000000 pixels, more than the limit of 300000000".into()
            ))
        );
        assert!(probe(&png(20_000, 15_000), 300_000_000).is_ok(), "exactly at the limit");
        assert!(probe(&png(20_000, 15_001), 300_000_000).is_err());
    }

    /// A truncated header gives the same answer or none; any single-byte change returns without a panic or a hang.
    #[test]
    fn survives_truncated_and_mutated_headers() {
        let samples = [png(640, 480), jpeg(640, 480, 0xc0), b"GIF87a\x01\0\x01\0".to_vec()];
        for sample in samples {
            let whole = probe(&sample, u64::MAX);
            for end in 0..sample.len() {
                let prefix = probe(&sample[..end], u64::MAX);
                assert!(
                    prefix == whole || matches!(prefix, Err(Failure::Unsupported(_))),
                    "{end}"
                );
            }
            for at in 0..sample.len() {
                for byte in [0, 1, 0x7f, 0xc0, 0xd9, 0xda, 0xff] {
                    let mut mutated = sample.clone();
                    mutated[at] = byte;
                    let _ = probe(&mutated, 1);
                }
            }
        }
    }
}
