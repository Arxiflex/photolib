//! A minimal PNG encoder: 8-bit RGB in one uncompressed (stored) zlib block.

/// An image of one colour.
pub fn solid(w: u32, h: u32, rgb: [u8; 3]) -> Vec<u8> {
    // Each row is a filter-type byte (0, none) followed by the pixels.
    let row: Vec<u8> = std::iter::once(0).chain(rgb.into_iter().cycle().take(3 * w as usize)).collect();
    let raw = row.repeat(h as usize);
    // One final stored block holds up to 64 KiB, plenty for a placeholder.
    let len = u16::try_from(raw.len()).expect("image too large for one stored block");
    let mut zlib = vec![0x78, 0x01, 1];
    zlib.extend(len.to_le_bytes().into_iter().chain((!len).to_le_bytes()));
    zlib.extend(&raw);
    let (a, b) = raw.iter().fold((1u32, 0u32), |(a, b), &x| ((a + x as u32) % 65_521, (b + a + x as u32) % 65_521));
    zlib.extend((b << 16 | a).to_be_bytes());
    let mut ihdr = [w.to_be_bytes(), h.to_be_bytes()].concat();
    ihdr.extend([8, 2, 0, 0, 0]); // bit depth, colour type RGB, compression, filter, no interlace
    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    for (kind, data) in [(b"IHDR", &ihdr), (b"IDAT", &zlib), (b"IEND", &Vec::new())] {
        png.extend((data.len() as u32).to_be_bytes());
        let start = png.len();
        png.extend(kind);
        png.extend(data);
        png.extend(crc32(&png[start..]).to_be_bytes());
    }
    png
}

fn crc32(bytes: &[u8]) -> u32 {
    !bytes
        .iter()
        .fold(!0u32, |c, &b| (0..8).fold(c ^ b as u32, |c, _| if c & 1 == 1 { 0xedb8_8320 ^ (c >> 1) } else { c >> 1 }))
}

#[cfg(test)]
mod tests {
    /// A 2x1 red image as Python's zlib (level 0) and binascii.crc32 encode it.
    #[test]
    fn encodes_like_an_independent_encoder() {
        let expected = [
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00,
            0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x7b, 0x40, 0xe8, 0xdd, 0x00, 0x00, 0x00,
            0x12, 0x49, 0x44, 0x41, 0x54, 0x78, 0x01, 0x01, 0x07, 0x00, 0xf8, 0xff, 0x00, 0xff, 0x00, 0x00, 0xff, 0x00,
            0x00, 0x08, 0xfe, 0x01, 0xff, 0xea, 0x5d, 0x79, 0xf7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
            0x42, 0x60, 0x82,
        ];
        assert_eq!(super::solid(2, 1, [255, 0, 0]), expected);
    }
}
