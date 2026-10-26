//! Sequential JPEG (ITU T.81) at the level of its quantised DCT coefficients, for edit.rs: a crop keeps whole blocks of
//! the original, and edited pixels are encoded with the forward DCT. Decoding pixels is the host's (design 11 §2.3).
// A codec indexes blocks and tables and computes offsets: every bound comes from the frame and tables checked while
// parsing, and a slip panics (overflow checks are on in release builds), which the ABI fails as kernel.panic.
#![allow(clippy::arithmetic_side_effects, clippy::indexing_slicing)]

use crate::proto::kernel::v1::Image;
use libm::{cosf, sqrtf};

/// The natural (row by row) index of each coefficient in zigzag order.
const ZIGZAG: [usize; 64] = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
    28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54,
    47, 55, 62, 63,
];

/// T.81 Annex K's quantisation tables for luminance and chrominance, row by row, which quality scales.
const QUANT: [[u8; 64]; 2] = [
    [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29,
        51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121,
        120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
    ],
    [
        17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
    ],
];

/// Annex K's Huffman tables, which every copy uses: the code counts per length, then the symbols, for luminance's DC,
/// its AC, chrominance's DC and its AC.
const HUFFMAN: [(&[u8; 16], &[u8]); 4] = [
    (
        &[0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0],
        &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    ),
    (
        &[0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d],
        &[
            0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71,
            0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72,
            0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37,
            0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
            0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83,
            0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3,
            0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
            0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
            0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
        ],
    ),
    (
        &[0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0],
        &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    ),
    (
        &[0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77],
        &[
            0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22,
            0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1,
            0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36,
            0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
            0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
            0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a,
            0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba,
            0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
            0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
        ],
    ),
];

const SOS: u8 = 0xda;
const DHT: u8 = 0xc4;
const DQT: u8 = 0xdb;
const DRI: u8 = 0xdd;

type Block = [i16; 64];
type Codes = [(u16, u8); 256];

/// A marker segment before the image data: its marker and its body, after the length.
pub(crate) struct Segment<'a> {
    pub(crate) marker: u8,
    pub(crate) body: &'a [u8],
}

/// A component of the frame: its id, sampling factors and quantisation table.
#[derive(Clone, Copy)]
struct Component {
    id: u8,
    h: usize,
    v: usize,
    table: u8,
}

/// A JPEG up to its first scan: the segments before it, the frame, and where its scan header starts in the file.
pub(crate) struct Jpeg<'a> {
    pub(crate) segments: Vec<Segment<'a>>,
    pub(crate) width: usize,
    pub(crate) height: usize,
    frame: u8,
    precision: u8,
    components: Vec<Component>,
    pub(crate) scan_at: usize,
}

pub(crate) fn is_frame(marker: u8) -> bool {
    matches!(marker, 0xc0..=0xcf) && !matches!(marker, DHT | 0xc8 | 0xcc)
}

pub(crate) fn segment(marker: u8, body: &[u8]) -> Option<Vec<u8>> {
    let len = u16::try_from(body.len() + 2).ok()?;
    Some([&[0xff, marker], &len.to_be_bytes()[..], body].concat())
}

/// The file's segments up to its first scan and its frame; None if it is no JPEG or has no frame before the scan.
pub(crate) fn parse(file: &[u8]) -> Option<Jpeg<'_>> {
    if !file.starts_with(&[0xff, 0xd8]) {
        return None;
    }
    let (mut at, mut segments) = (2, Vec::new());
    loop {
        while file.get(at..at + 2) == Some(&[0xff, 0xff]) {
            at += 1;
        }
        let &[0xff, marker, high, low] = file.get(at..at + 4)? else {
            return None;
        };
        let len = usize::from(u16::from_be_bytes([high, low]));
        let body = file.get(at + 4..(at + 2 + len).max(at + 4))?;
        if marker == SOS {
            break;
        }
        segments.push(Segment { marker, body });
        at += 2 + len;
    }
    let frame = segments.iter().find(|s| is_frame(s.marker))?;
    let (precision, size, count) = (
        *frame.body.first()?,
        frame.body.get(1..5)?,
        usize::from(*frame.body.get(5)?),
    );
    let components = frame
        .body
        .get(6..6 + 3 * count)?
        .chunks(3)
        .map(|c| Component {
            id: c[0],
            h: usize::from(c[1] >> 4),
            v: usize::from(c[1] & 15),
            table: c[2],
        })
        .collect::<Vec<_>>();
    let ok = count > 0
        && components
            .iter()
            .all(|c| (1..=4).contains(&c.h) && (1..=4).contains(&c.v));
    let height = usize::from(u16::from_be_bytes([size[0], size[1]]));
    let width = usize::from(u16::from_be_bytes([size[2], size[3]]));
    (ok && width > 0 && height > 0).then_some(Jpeg {
        frame: frame.marker,
        segments,
        width,
        height,
        precision,
        components,
        scan_at: at,
    })
}

impl Jpeg<'_> {
    /// The size of an MCU in pixels: what a lossless crop moves by.
    pub(crate) fn mcu(&self) -> (usize, usize) {
        mcu(&self.components)
    }

    /// The crop from (`x`, `y`), a corner of an MCU, of `width` × `height` pixels as image data: frame, Huffman
    /// tables, scan header and entropy-coded data, up to the end of the image. None unless the file is a baseline or
    /// extended sequential 8-bit JPEG of one Huffman scan.
    pub(crate) fn crop(&self, file: &[u8], x: usize, y: usize, width: usize, height: usize) -> Option<Vec<u8>> {
        let (mw, mh) = self.mcu();
        let (cols, _) = grid(&self.components, self.width, self.height);
        let (left, top) = (x / mw, y / mh);
        let (keep_cols, keep_rows) = grid(&self.components, width, height);
        let mut encoder = Encoder::new(self.components.len());
        self.decode(file, (top + keep_rows) * cols, |at, blocks| {
            let (col, row) = (at % cols, at / cols);
            if (left..left + keep_cols).contains(&col) && (top..top + keep_rows).contains(&row) {
                blocks.iter().try_for_each(|&(c, block)| encoder.block(c, &block))?;
            }
            Some(())
        })?;
        let frame = frame(self.frame, width, height, &self.components)?;
        Some([frame, scan(&self.components, encoder.finish())?].concat())
    }

    /// Decodes the scan's first `limit` MCUs, calling `mcu` with each one's index and blocks, each with its component.
    fn decode(
        &self,
        file: &[u8],
        limit: usize,
        mut mcu: impl FnMut(usize, &[(usize, Block)]) -> Option<()>,
    ) -> Option<()> {
        if !matches!(self.frame, 0xc0 | 0xc1) || self.precision != 8 {
            return None;
        }
        let (mut dc, mut ac) = (vec![None; 4], vec![None; 4]);
        let mut interval = 0;
        for s in &self.segments {
            match s.marker {
                DHT => tables(s.body, &mut dc, &mut ac)?,
                DRI => interval = usize::from(u16::from_be_bytes([*s.body.first()?, *s.body.get(1)?])),
                _ => {}
            }
        }
        let header = file.get(self.scan_at + 4..)?;
        let count = usize::from(*header.first()?);
        if count != self.components.len() || header.get(1 + 2 * count..4 + 2 * count)? != [0, 63, 0] {
            return None;
        }
        let mut coders = Vec::new();
        for (c, pair) in self.components.iter().zip(header[1..].chunks(2)) {
            let (dc, ac) = (dc.get(usize::from(pair[1] >> 4))?, ac.get(usize::from(pair[1] & 15))?);
            (pair[0] == c.id).then_some(())?;
            coders.push((dc.clone()?, ac.clone()?));
        }
        let mut reader = Reader {
            data: header.get(4 + 2 * count..)?,
            at: 0,
            acc: 0,
            bits: 0,
            past: false,
        };
        let (cols, rows) = grid(&self.components, self.width, self.height);
        let units = units(&self.components);
        let (mut preds, mut blocks) = (vec![0; count], Vec::with_capacity(units.len()));
        for at in 0..(cols * rows).min(limit) {
            if interval > 0 && at > 0 && at % interval == 0 {
                reader.restart()?;
                preds.fill(0);
            }
            blocks.clear();
            for &c in &units {
                let (dc, ac) = &coders[c];
                blocks.push((c, reader.block(dc, ac, &mut preds[c])?));
            }
            mcu(at, &blocks)?;
        }
        Some(())
    }
}

/// The size of an MCU of `components` in pixels; a single component's is a block.
fn mcu(components: &[Component]) -> (usize, usize) {
    match components {
        [_] => (8, 8),
        all => (
            8 * all.iter().map(|c| c.h).max().unwrap_or(1),
            8 * all.iter().map(|c| c.v).max().unwrap_or(1),
        ),
    }
}

/// The MCUs across and down an image of `width` × `height`.
fn grid(components: &[Component], width: usize, height: usize) -> (usize, usize) {
    let (mw, mh) = mcu(components);
    (width.div_ceil(mw), height.div_ceil(mh))
}

/// The component of each block of an MCU, in order: `h` × `v` of each, or one of a single component.
fn units(components: &[Component]) -> Vec<usize> {
    if components.len() == 1 {
        return vec![0];
    }
    (0..)
        .zip(components)
        .flat_map(|(i, c)| std::iter::repeat_n(i, c.h * c.v))
        .collect()
}

/// A Huffman table for decoding (T.81 F.2.2.3): per code length, the largest code, the first code and the index of
/// its symbol.
#[derive(Clone)]
struct Decoder {
    max: [i32; 17],
    min: [i32; 17],
    first: [usize; 17],
    symbols: Vec<u8>,
}

fn tables(body: &[u8], dc: &mut [Option<Decoder>], ac: &mut [Option<Decoder>]) -> Option<()> {
    let mut rest = body;
    while let [class_id, counts @ ..] = rest {
        let counts: &[u8; 16] = counts.get(..16)?.try_into().ok()?;
        let total = counts.iter().map(|&n| usize::from(n)).sum::<usize>();
        let symbols = rest.get(17..17 + total)?;
        let slot = usize::from(class_id & 15);
        let table = match class_id >> 4 {
            0 => dc.get_mut(slot)?,
            1 => ac.get_mut(slot)?,
            _ => return None,
        };
        *table = Some(decoder(counts, symbols)?);
        rest = &rest[17 + total..];
    }
    Some(())
}

fn decoder(counts: &[u8; 16], symbols: &[u8]) -> Option<Decoder> {
    let mut table = Decoder {
        max: [-1; 17],
        min: [0; 17],
        first: [0; 17],
        symbols: symbols.to_vec(),
    };
    let (mut code, mut k) = (0i32, 0);
    for (len, &n) in (1..=16).zip(counts) {
        let n = usize::from(n);
        if n > 0 {
            (table.first[len], table.min[len]) = (k, code);
            code += i32::try_from(n).ok()?;
            k += n;
            table.max[len] = code - 1;
            if code > 1 << len {
                return None;
            }
        }
        code <<= 1;
    }
    Some(table)
}

/// The entropy-coded data of a scan, read bit by bit, stuffed bytes undone. Reading on at a marker or the end of the
/// data reads zeros and marks the scan `past` its data: damaged, as a scan ends where its bits do.
struct Reader<'a> {
    data: &'a [u8],
    at: usize,
    acc: u64,
    bits: u32,
    past: bool,
}

impl Reader<'_> {
    fn byte(&mut self) -> u64 {
        match self.data.get(self.at..).unwrap_or_default() {
            [0xff, 0, ..] => {
                self.at += 2;
                0xff
            }
            [0xff, ..] | [] => {
                self.past = true;
                0
            }
            [b, ..] => {
                self.at += 1;
                u64::from(*b)
            }
        }
    }

    fn bits(&mut self, n: u32) -> i32 {
        while self.bits < n {
            self.acc = self.acc << 8 | self.byte();
            self.bits += 8;
        }
        self.bits -= n;
        // At most 16 bits, so the value fits.
        #[allow(clippy::cast_possible_truncation)]
        let value = (self.acc >> self.bits & ((1 << n) - 1)) as i32;
        value
    }

    fn decode(&mut self, table: &Decoder) -> Option<u8> {
        let mut code = self.bits(1);
        for len in 1..=16 {
            if code <= table.max[len] {
                let at = table.first[len] + usize::try_from(code - table.min[len]).ok()?;
                return table.symbols.get(at).copied();
            }
            code = code << 1 | self.bits(1);
        }
        None
    }

    /// A coefficient of `size` bits (T.81 F.2.2.1's RECEIVE and EXTEND).
    fn value(&mut self, size: u8) -> Option<i32> {
        let size = u32::from(size);
        if size > 16 {
            return None;
        }
        let v = self.bits(size);
        Some(if size > 0 && v < 1 << (size - 1) {
            v - (1 << size) + 1
        } else {
            v
        })
    }

    fn block(&mut self, dc: &Decoder, ac: &Decoder, pred: &mut i32) -> Option<Block> {
        let mut block = [0; 64];
        let size = self.decode(dc)?;
        *pred += self.value(size)?;
        block[0] = i16::try_from(*pred).ok()?;
        let mut k = 1;
        while k < 64 {
            let rs = self.decode(ac)?;
            let (run, size) = (usize::from(rs >> 4), rs & 15);
            if size == 0 {
                if run < 15 {
                    break;
                }
                k += 16;
                continue;
            }
            k += run;
            *block.get_mut(k)? = i16::try_from(self.value(size)?).ok()?;
            k += 1;
        }
        (!self.past).then_some(block)
    }

    fn restart(&mut self) -> Option<()> {
        (self.acc, self.bits) = (0, 0);
        let [0xff, 0xd0..=0xd7, ..] = self.data.get(self.at..)? else {
            return None;
        };
        self.at += 2;
        Some(())
    }
}

/// The frame header of an image of `width` × `height` with `components`.
fn frame(marker: u8, width: usize, height: usize, components: &[Component]) -> Option<Vec<u8>> {
    let mut body = vec![8];
    body.extend(u16::try_from(height).ok()?.to_be_bytes());
    body.extend(u16::try_from(width).ok()?.to_be_bytes());
    body.push(u8::try_from(components.len()).ok()?);
    for c in components {
        body.extend([c.id, u8::try_from(c.h << 4 | c.v).ok()?, c.table]);
    }
    segment(marker, &body)
}

/// Annex K's Huffman tables and the scan header for `components`, then `entropy`, then the end of the image.
fn scan(components: &[Component], entropy: Vec<u8>) -> Option<Vec<u8>> {
    let mut tables = Vec::new();
    // The class in the high half, the slot (0 for luminance, 1 for chrominance) in the low one.
    for (id, (counts, symbols)) in [0x00, 0x10, 0x01, 0x11].into_iter().zip(HUFFMAN) {
        tables.push(id);
        tables.extend_from_slice(counts);
        tables.extend_from_slice(symbols);
    }
    let mut header = vec![u8::try_from(components.len()).ok()?];
    for (i, c) in components.iter().enumerate() {
        header.extend([c.id, if i == 0 { 0x00 } else { 0x11 }]);
    }
    header.extend([0, 63, 0]);
    Some(
        [
            segment(DHT, &tables)?,
            segment(SOS, &header)?,
            entropy,
            vec![0xff, 0xd9],
        ]
        .concat(),
    )
}

/// Entropy-codes blocks with Annex K's tables: luminance's for the first component, chrominance's for the others.
struct Encoder {
    writer: Writer,
    preds: Vec<i32>,
    codes: [Codes; 4],
}

impl Encoder {
    fn new(components: usize) -> Self {
        Self {
            writer: Writer::default(),
            preds: vec![0; components],
            codes: HUFFMAN.map(|(counts, symbols)| encoder(counts, symbols)),
        }
    }

    fn block(&mut self, component: usize, block: &Block) -> Option<()> {
        let tables = usize::from(component > 0) * 2;
        let (dc, ac) = (&self.codes[tables], &self.codes[tables + 1]);
        self.writer.block(block, &mut self.preds[component], dc, ac)
    }

    fn finish(self) -> Vec<u8> {
        self.writer.finish()
    }
}

/// The code and its length of each symbol of a Huffman table (T.81 C.2).
fn encoder(counts: &[u8; 16], symbols: &[u8]) -> Codes {
    let mut codes = [(0, 0); 256];
    let (mut code, mut symbols) = (0u16, symbols.iter());
    for (len, &n) in (1..=16).zip(counts) {
        for _ in 0..n {
            if let Some(&s) = symbols.next() {
                codes[usize::from(s)] = (code, len);
            }
            code += 1;
        }
        code <<= 1;
    }
    codes
}

#[derive(Default)]
struct Writer {
    out: Vec<u8>,
    acc: u32,
    bits: u32,
}

impl Writer {
    fn put(&mut self, code: u32, len: u32) {
        self.acc = (self.acc << len | code & ((1 << len) - 1)) & 0xff_ffff;
        self.bits += len;
        while self.bits >= 8 {
            self.bits -= 8;
            let [.., byte] = (self.acc >> self.bits).to_be_bytes();
            self.out.push(byte);
            if byte == 0xff {
                self.out.push(0);
            }
        }
    }

    fn symbol(&mut self, table: &Codes, symbol: u8) -> Option<()> {
        let (code, len) = table[usize::from(symbol)];
        (len > 0).then(|| self.put(u32::from(code), u32::from(len)))
    }

    /// A coefficient's size category and its bits (T.81 F.1.2.1).
    fn value(&mut self, table: &Codes, run: u8, v: i32) -> Option<()> {
        let size = 32 - v.unsigned_abs().leading_zeros();
        self.symbol(table, run << 4 | u8::try_from(size).ok()?)?;
        let bits = if v < 0 { v - 1 } else { v };
        self.put(bits.cast_unsigned(), size);
        Some(())
    }

    fn block(&mut self, block: &Block, pred: &mut i32, dc: &Codes, ac: &Codes) -> Option<()> {
        let diff = i32::from(block[0]) - *pred;
        *pred = i32::from(block[0]);
        self.value(dc, 0, diff)?;
        let mut run = 0;
        for &v in &block[1..] {
            if v == 0 {
                run += 1;
                continue;
            }
            while run > 15 {
                self.symbol(ac, 0xf0)?;
                run -= 16;
            }
            self.value(ac, run, i32::from(v))?;
            run = 0;
        }
        if run > 0 {
            self.symbol(ac, 0)?;
        }
        Some(())
    }

    /// The data, its last byte padded with ones.
    fn finish(mut self) -> Vec<u8> {
        if self.bits > 0 {
            self.put(0xff, 8 - self.bits);
        }
        self.out
    }
}

/// The quantisation tables, in zigzag order, of `quality` but never coarser than the luminance and chrominance tables
/// of `original`, so that a copy keeps at least its original's quality.
pub(crate) fn quality(original: &Jpeg<'_>, quality: u16) -> [[u16; 64]; 2] {
    let quality = u32::from(quality.clamp(1, 100));
    let scale = if quality < 50 {
        5000 / quality
    } else {
        200 - 2 * quality
    };
    let mut tables = QUANT.map(|t| ZIGZAG.map(|n| ((u32::from(t[n]) * scale + 50) / 100).clamp(1, 255) as u16));
    let mut own = [None; 4];
    for s in original.segments.iter().filter(|s| s.marker == DQT) {
        let mut rest = s.body;
        while let [pq_tq, values @ ..] = rest {
            let wide = pq_tq >> 4 == 1;
            let Some(values) = values.get(..if wide { 128 } else { 64 }) else {
                break;
            };
            let table: [u16; 64] = std::array::from_fn(|k| {
                if wide {
                    u16::from_be_bytes([values[2 * k], values[2 * k + 1]])
                } else {
                    u16::from(values[k])
                }
            });
            if let Some(slot) = own.get_mut(usize::from(pq_tq & 15)) {
                *slot = Some(table);
            }
            rest = &rest[1 + values.len()..];
        }
    }
    let used = original
        .components
        .iter()
        .map(|c| own.get(usize::from(c.table)).copied().flatten());
    for (table, theirs) in tables.iter_mut().zip(used) {
        if let Some(theirs) = theirs {
            for (q, t) in table.iter_mut().zip(theirs) {
                *q = (*q).min(t.max(1));
            }
        }
    }
    tables
}

/// The image data of `image`, RGB with full-resolution chroma, quantised with `tables`: quantisation tables, frame,
/// Huffman tables, scan header and entropy-coded data, up to the end of the image.
pub(crate) fn encode(image: &Image, tables: &[[u16; 64]; 2]) -> Option<Vec<u8>> {
    let (width, height) = (usize::try_from(image.width).ok()?, usize::try_from(image.height).ok()?);
    let components: Vec<_> = (1..=3)
        .map(|id| Component {
            id,
            h: 1,
            v: 1,
            table: u8::from(id > 1),
        })
        .collect();
    let (dct, mut encoder) = (Dct::new(), Encoder::new(3));
    for y in (0..height).step_by(8) {
        for x in (0..width).step_by(8) {
            for (c, samples) in samples(image, width, height, x, y).iter().enumerate() {
                encoder.block(c, &dct.quantise(samples, &tables[usize::from(c > 0)]))?;
            }
        }
    }
    let mut dqt = Vec::new();
    for (slot, table) in [0, 1].into_iter().zip(tables) {
        dqt.push(slot);
        for &q in table {
            dqt.push(u8::try_from(q).ok()?);
        }
    }
    let frame = frame(0xc0, width, height, &components)?;
    Some([segment(DQT, &dqt)?, frame, scan(&components, encoder.finish())?].concat())
}

/// The level-shifted Y, Cb and Cr samples of the 8 × 8 block at (`left`, `top`), its edges repeating past the image's.
// Without FMA in hardware, mul_add is a slow library call; plain products keep native and WebAssembly builds equal.
#[allow(clippy::suboptimal_flops)]
fn samples(image: &Image, width: usize, height: usize, left: usize, top: usize) -> [[f32; 64]; 3] {
    let mut out = [[0.0; 64]; 3];
    let [luma, blue, red] = &mut out;
    for (i, ((y, cb), cr)) in luma.iter_mut().zip(blue.iter_mut()).zip(red.iter_mut()).enumerate() {
        let at = ((top + i / 8).min(height - 1) * width + (left + i % 8).min(width - 1)) * 4;
        let [r, g, b] = [0, 1, 2].map(|c| f32::from(image.rgba[at + c]));
        *y = 0.299 * r + 0.587 * g + 0.114 * b - 128.0;
        *cb = -0.168_736 * r - 0.331_264 * g + 0.5 * b;
        *cr = 0.5 * r - 0.418_688 * g - 0.081_312 * b;
    }
    out
}

/// The orthonormal 8-point DCT-II, as a matrix: T.81's forward DCT along each axis.
struct Dct([[f32; 8]; 8]);

impl Dct {
    fn new() -> Self {
        Self(std::array::from_fn(|u| {
            let scale = if u == 0 { sqrtf(0.125) } else { 0.5 };
            std::array::from_fn(|x| {
                let (u, x) = (u16::try_from(u).unwrap_or(0), u16::try_from(x).unwrap_or(0));
                scale * cosf(f32::from((2 * x + 1) * u) * core::f32::consts::PI / 16.0)
            })
        }))
    }

    // As in samples.
    #[allow(clippy::suboptimal_flops)]
    fn quantise(&self, samples: &[f32; 64], table: &[u16; 64]) -> Block {
        let m = &self.0;
        let mut rows = [0.0; 64];
        for y in 0..8 {
            for u in 0..8 {
                rows[y * 8 + u] = (0..8).fold(0.0, |s, x| s + m[u][x] * samples[y * 8 + x]);
            }
        }
        std::array::from_fn(|k| {
            let (v, u) = (ZIGZAG[k] / 8, ZIGZAG[k] % 8);
            let coefficient = (0..8).fold(0.0, |s, y| s + m[v][y] * rows[y * 8 + u]);
            // Within ±1024 for 8-bit samples.
            #[allow(clippy::cast_possible_truncation)]
            let q = (coefficient / f32::from(table[k])).round() as i16;
            q
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn annex_k_codes_every_symbol_of_8_bit_data() {
        let ac: Vec<u8> = (0..16)
            .flat_map(|run| (1..=10).map(move |size| run << 4 | size))
            .chain([0, 0xf0])
            .collect();
        for (i, (counts, symbols)) in HUFFMAN.iter().enumerate() {
            let codes = encoder(counts, symbols);
            let want: Vec<u8> = if i % 2 == 0 { (0..12).collect() } else { ac.clone() };
            assert!(want.iter().all(|&s| codes[usize::from(s)].1 > 0), "table {i}");
            assert_eq!(symbols.len(), want.len());
        }
    }

    /// Every MCU of a JPEG file and its blocks.
    fn mcus(file: &[u8]) -> Vec<Vec<(usize, Block)>> {
        let mut all = Vec::new();
        parse(file)
            .unwrap()
            .decode(file, usize::MAX, |_, blocks| {
                all.push(blocks.to_vec());
                Some(())
            })
            .unwrap();
        all
    }

    #[test]
    fn a_crop_keeps_the_coefficients_of_its_blocks() {
        #[allow(clippy::disallowed_methods)] // a test reads its fixture
        let file = std::fs::read(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../testdata/corpus/files/stills/gps-sydney.jpg"
        ))
        .unwrap();
        let jpeg = parse(&file).unwrap();
        let tables = jpeg
            .segments
            .iter()
            .filter(|s| s.marker == DQT)
            .filter_map(|s| segment(DQT, s.body));
        let crop = jpeg.crop(&file, 16, 32, 305, 205).unwrap();
        let copy = [vec![0xff, 0xd8], tables.flatten().collect(), crop].concat();
        // 4:2:0 in 16 × 16 MCUs: 40 across the original, 20 by 13 in the crop, from the second column and third row.
        let (from, to) = (mcus(&file), mcus(&copy));
        assert_eq!(to.len(), 20 * 13);
        for (i, mcu) in to.iter().enumerate() {
            assert_eq!(mcu, &from[(2 + i / 20) * 40 + 1 + i % 20]);
        }
    }

    #[test]
    fn a_scan_that_runs_past_its_data_is_damaged() {
        #[allow(clippy::disallowed_methods)] // a test reads its fixture
        let file = std::fs::read(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../testdata/corpus/files/stills/baseline.jpg"
        ))
        .unwrap();
        let jpeg = parse(&file).unwrap();
        assert!(jpeg.crop(&file, 0, 0, 64, 480).is_some());
        let cut = [&file[..file.len() - 40], &[0xff, 0xd9]].concat();
        assert!(jpeg.crop(&cut, 0, 0, 64, 480).is_none());
    }
}
