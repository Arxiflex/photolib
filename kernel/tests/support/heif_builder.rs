//! Byte builders for HEIF files: boxes, and a file of items, properties and references.

pub(crate) fn bx(kind: &[u8], payload: &[u8]) -> Vec<u8> {
    [&(8 + payload.len() as u32).to_be_bytes()[..], kind, payload].concat()
}

pub(crate) fn full(kind: &[u8], payload: &[u8]) -> Vec<u8> {
    bx(kind, &[&[0u8; 4][..], payload].concat())
}

pub(crate) fn be16(n: u16) -> [u8; 2] {
    n.to_be_bytes()
}

/// An item of a built file: id, type, the properties it has (numbered from 1) and its coded bytes.
pub(crate) struct Item(
    pub(crate) u16,
    pub(crate) &'static [u8; 4],
    pub(crate) Vec<u8>,
    pub(crate) Vec<u8>,
);

/// A HEIF file of these items, properties and references (kind, from, to), and its primary item.
pub(crate) fn built(items: &[Item], props: &[Vec<u8>], refs: &[(&[u8; 4], u16, Vec<u16>)], primary: u16) -> Vec<u8> {
    let infes: Vec<u8> = (items.iter())
        .flat_map(|i| bx(b"infe", &[&[2, 0, 0, 0][..], &be16(i.0), &[0, 0], i.1, b"\0"].concat()))
        .collect();
    let refs: Vec<u8> = refs
        .iter()
        .flat_map(|(kind, from, to)| {
            let to: Vec<u8> = to.iter().flat_map(|t| be16(*t)).collect();
            bx(*kind, &[&be16(*from)[..], &be16(to.len() as u16 / 2), &to].concat())
        })
        .collect();
    let ipma: Vec<u8> = items
        .iter()
        .flat_map(|i| [&be16(i.0)[..], &[i.2.len() as u8], &i.2].concat())
        .collect();
    let layout = |at: &[u32]| {
        let iloc: Vec<u8> = (items.iter().zip(at))
            .flat_map(|(i, at)| {
                [
                    &be16(i.0)[..],
                    &[0, 0, 0, 1],
                    &at.to_be_bytes(),
                    &(i.3.len() as u32).to_be_bytes(),
                ]
                .concat()
            })
            .collect();
        let meta = full(
            b"meta",
            &[
                full(b"hdlr", &[&[0u8; 4][..], b"pict", &[0u8; 13]].concat()),
                full(b"pitm", &be16(primary)),
                full(b"iloc", &[&[0x44, 0][..], &be16(items.len() as u16), &iloc].concat()),
                full(b"iinf", &[&be16(items.len() as u16)[..], &infes].concat()),
                full(b"iref", &refs),
                bx(
                    b"iprp",
                    &[
                        bx(b"ipco", &props.concat()),
                        full(b"ipma", &[&(items.len() as u32).to_be_bytes()[..], &ipma].concat()),
                    ]
                    .concat(),
                ),
            ]
            .concat(),
        );
        [bx(b"ftyp", b"heic\0\0\0\0mif1heic"), meta].concat()
    };
    let mut next = layout(&vec![0; items.len()]).len() as u32 + 8;
    let at: Vec<u32> = items
        .iter()
        .map(|i| {
            next += i.3.len() as u32;
            next - i.3.len() as u32
        })
        .collect();
    let data: Vec<u8> = items.iter().flat_map(|i| i.3.clone()).collect();
    [layout(&at), bx(b"mdat", &data)].concat()
}

pub(crate) fn ispe(w: u32, h: u32) -> Vec<u8> {
    full(b"ispe", &[w.to_be_bytes(), h.to_be_bytes()].concat())
}

pub(crate) const HVCC: [u8; 13] = [1, 1, 0x60, 0, 0, 0, 0xB0, 0, 0, 0, 0, 0, 93];
