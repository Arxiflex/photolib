//! The gain map of a HEIF still (HEIC or AVIF): where it is, what it says, and the map's coded image as a HEIF file of
//! its own, which libheif decodes like any picture. Apple's is an auxiliary image (`urn:com:apple:photo:2020:aux:
//! hdrgainmap`) whose strength is in the EXIF maker note; ISO 21496-1's (Samsung, Google and Apple's newer files) is
//! the input of a `tmap` item, which holds the metadata. libheif reads neither, and libvips reads only the picture.

use std::{
    collections::BTreeMap,
    fs::File,
    io::{Read, Seek, SeekFrom},
    path::Path,
};

use crate::gainmap::Boost;

/// The largest `meta` box read: a grid of thousands of tiles has a few hundred KiB.
const META: u64 = 16 << 20;
/// The largest item copied out of a file.
const ITEM: u64 = 64 << 20;
/// The most items a picture is made of.
const ITEMS: usize = 4096;
/// The type of Apple's gain map, a HEIF auxiliary image.
const APPLE_GAIN_MAP: &[u8] = b"urn:com:apple:photo:2020:aux:hdrgainmap";
/// The properties that turn or crop a picture.
const TURNS: [&[u8; 4]; 3] = [b"clap", b"irot", b"imir"];

type Kind = [u8; 4];
/// The properties a file keeps: their boxes, and for each item the (1-based) indices of its own.
type Kept = (Vec<Vec<u8>>, Vec<(u16, Vec<u16>)>);

struct Item {
    kind: Kind,
}

struct Reference {
    kind: Kind,
    from: u32,
    to: Vec<u32>,
}

/// Where an item's bytes are: in the file, or in the `idat` box.
struct Location {
    in_idat: bool,
    extents: Vec<(u64, u64)>,
}

/// What a `meta` box says of its items.
pub struct Meta {
    primary: u32,
    items: BTreeMap<u32, Item>,
    references: Vec<Reference>,
    /// Each property box, whole, in the order `ipco` lists them.
    properties: Vec<Vec<u8>>,
    associations: BTreeMap<u32, Vec<u16>>,
    locations: BTreeMap<u32, Location>,
    idat: Vec<u8>,
}

/// A box of `buf` at `at`: its type, its payload and where it ends.
fn parse_box(buf: &[u8], at: usize) -> Option<(Kind, &[u8], usize)> {
    let size = usize::try_from(u32::from_be_bytes(buf.get(at..at.checked_add(4)?)?.try_into().ok()?)).ok()?;
    let kind: Kind = buf.get(at.checked_add(4)?..at.checked_add(8)?)?.try_into().ok()?;
    let (header, end) = match size {
        0 => (8, buf.len()),
        1 => {
            let large = u64::from_be_bytes(buf.get(at.checked_add(8)?..at.checked_add(16)?)?.try_into().ok()?);
            (16, at.checked_add(usize::try_from(large).ok()?)?)
        }
        _ => (8, at.checked_add(size)?),
    };
    Some((kind, buf.get(at.checked_add(header)?..end)?, end))
}

/// The boxes of `buf`: type, payload and the whole box.
fn children(buf: &[u8]) -> Vec<(Kind, &[u8], &[u8])> {
    let (mut at, mut found) = (0, vec![]);
    while let Some((kind, payload, end)) = parse_box(buf, at) {
        let Some(whole) = buf.get(at..end) else {
            break;
        };
        found.push((kind, payload, whole));
        at = end;
    }
    found
}

fn be(bytes: &[u8]) -> Option<u64> {
    if bytes.len() > 8 {
        return None;
    }
    bytes
        .iter()
        .try_fold(0u64, |n, b| n.checked_mul(256)?.checked_add(u64::from(*b)))
}

/// A cursor over big-endian fields.
pub(crate) struct Reader<'a>(&'a [u8]);

impl<'a> Reader<'a> {
    pub(crate) fn new(bytes: &'a [u8]) -> Self {
        Self(bytes)
    }

    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let (head, rest) = self.0.split_at_checked(n)?;
        self.0 = rest;
        Some(head)
    }

    pub(crate) fn uint(&mut self, n: usize) -> Option<u64> {
        be(self.take(n)?)
    }

    fn id(&mut self, n: usize) -> Option<u32> {
        u32::try_from(self.uint(n)?).ok()
    }
}

/// `value` as a box of `kind`.
fn boxed(kind: &[u8], body: &[u8]) -> Option<Vec<u8>> {
    let mut bytes = u32::try_from(body.len().checked_add(8)?).ok()?.to_be_bytes().to_vec();
    bytes.extend(kind);
    bytes.extend(body);
    Some(bytes)
}

/// `value` as a box of `kind`, version 0 and no flags.
fn full(kind: &[u8], body: &[u8]) -> Option<Vec<u8>> {
    boxed(kind, &[&[0u8; 4][..], body].concat())
}

fn id16(id: u32) -> Option<[u8; 2]> {
    Some(u16::try_from(id).ok()?.to_be_bytes())
}

impl Meta {
    /// Parses the payload of a `meta` box, without its version and flags.
    fn parse(meta: &[u8]) -> Option<Self> {
        let mut found = Self {
            primary: 0,
            items: BTreeMap::new(),
            references: vec![],
            properties: vec![],
            associations: BTreeMap::new(),
            locations: BTreeMap::new(),
            idat: vec![],
        };
        for (kind, payload, _) in children(meta) {
            match &kind {
                b"pitm" => {
                    let mut r = Reader::new(payload);
                    let version = r.uint(1)?;
                    r.take(3)?;
                    found.primary = r.id(if version == 0 { 2 } else { 4 })?;
                }
                b"iinf" => found.items(payload)?,
                b"iref" => found.references(payload)?,
                b"iprp" => found.properties(payload)?,
                b"iloc" => found.locations(payload)?,
                b"idat" => found.idat = payload.to_vec(),
                _ => {}
            }
        }
        Some(found)
    }

    fn items(&mut self, payload: &[u8]) -> Option<()> {
        let mut r = Reader::new(payload);
        let version = r.uint(1)?;
        r.take(3)?;
        r.take(if version == 0 { 2 } else { 4 })?;
        for (kind, payload, _) in children(r.0) {
            if &kind != b"infe" {
                continue;
            }
            let mut r = Reader::new(payload);
            let version = r.uint(1)?;
            r.take(3)?;
            if version < 2 {
                continue;
            }
            let id = r.id(if version == 2 { 2 } else { 4 })?;
            r.take(2)?;
            let kind: Kind = r.take(4)?.try_into().ok()?;
            self.items.insert(id, Item { kind });
        }
        Some(())
    }

    fn references(&mut self, payload: &[u8]) -> Option<()> {
        let mut r = Reader::new(payload);
        let version = r.uint(1)?;
        r.take(3)?;
        let width = if version == 0 { 2 } else { 4 };
        for (kind, payload, _) in children(r.0) {
            let mut r = Reader::new(payload);
            let from = r.id(width)?;
            let count = r.uint(2)?;
            let to = (0..count).map(|_| r.id(width)).collect::<Option<_>>()?;
            self.references.push(Reference { kind, from, to });
        }
        Some(())
    }

    fn properties(&mut self, payload: &[u8]) -> Option<()> {
        for (kind, payload, _) in children(payload) {
            match &kind {
                b"ipco" => {
                    self.properties = children(payload)
                        .into_iter()
                        .map(|(_, _, whole)| whole.to_vec())
                        .collect();
                }
                b"ipma" => {
                    let mut r = Reader::new(payload);
                    let version = r.uint(1)?;
                    let flags = r.uint(3)?;
                    for _ in 0..r.uint(4)? {
                        let id = r.id(if version < 1 { 2 } else { 4 })?;
                        let mut list = vec![];
                        for _ in 0..r.uint(1)? {
                            let index = if flags & 1 == 1 {
                                r.uint(2)? & 0x7fff
                            } else {
                                r.uint(1)? & 0x7f
                            };
                            list.push(u16::try_from(index).ok()?);
                        }
                        self.associations.insert(id, list);
                    }
                }
                _ => {}
            }
        }
        Some(())
    }

    fn locations(&mut self, payload: &[u8]) -> Option<()> {
        let mut r = Reader::new(payload);
        let version = r.uint(1)?;
        r.take(3)?;
        let sizes = r.uint(2)?;
        let size = |shift: u32| usize::try_from(sizes >> shift & 15).ok();
        let (offset_size, length_size, base_size) = (size(12)?, size(8)?, size(4)?);
        let index_size = if version == 1 || version == 2 { size(0)? } else { 0 };
        let count = if version < 2 { r.uint(2)? } else { r.uint(4)? };
        for _ in 0..count {
            let id = r.id(if version < 2 { 2 } else { 4 })?;
            let method = if version == 1 || version == 2 {
                r.uint(2)? & 15
            } else {
                0
            };
            r.take(2)?;
            let base = r.uint(base_size)?;
            let mut extents = vec![];
            for _ in 0..r.uint(2)? {
                r.take(index_size)?;
                let (offset, length) = (r.uint(offset_size)?, r.uint(length_size)?);
                extents.push((base.checked_add(offset)?, length));
            }
            // Method 2 refers to another item: not for image data.
            if method > 1 {
                continue;
            }
            self.locations.insert(
                id,
                Location {
                    in_idat: method == 1,
                    extents,
                },
            );
        }
        Some(())
    }

    /// The bytes of item `id`.
    fn data(&self, file: &mut File, id: u32) -> Option<Vec<u8>> {
        let location = self.locations.get(&id)?;
        let total = location
            .extents
            .iter()
            .try_fold(0u64, |n, (_, length)| n.checked_add(*length))?;
        if total > ITEM {
            return None;
        }
        let mut bytes = Vec::with_capacity(usize::try_from(total).ok()?);
        for &(offset, length) in &location.extents {
            let length = usize::try_from(length).ok()?;
            if location.in_idat {
                let start = usize::try_from(offset).ok()?;
                bytes.extend(self.idat.get(start..start.checked_add(length)?)?);
            } else {
                file.seek(SeekFrom::Start(offset)).ok()?;
                let before = bytes.len();
                bytes.resize(before.checked_add(length)?, 0);
                file.read_exact(bytes.get_mut(before..)?).ok()?;
            }
        }
        Some(bytes)
    }

    fn kind(&self, id: u32) -> Option<Kind> {
        self.items.get(&id).map(|item| item.kind)
    }

    /// The properties of `id` of `kind`, whole.
    fn properties_of(&self, id: u32, kind: &[u8]) -> Vec<&[u8]> {
        let listed = self.associations.get(&id).map_or(&[][..], Vec::as_slice);
        (listed.iter())
            .filter_map(|&index| self.properties.get(usize::from(index).checked_sub(1)?))
            .filter(|property| property.get(4..8) == Some(kind))
            .map(Vec::as_slice)
            .collect()
    }

    /// The items that refer to `id` by `kind`.
    fn referring(&self, kind: &[u8], id: u32) -> Vec<u32> {
        (self.references.iter())
            .filter(|r| r.kind.as_slice() == kind && r.to.contains(&id))
            .map(|r| r.from)
            .collect()
    }

    fn inputs(&self, id: u32) -> Vec<u32> {
        (self.references.iter())
            .filter(|r| r.from == id && &r.kind == b"dimg")
            .flat_map(|r| r.to.clone())
            .collect()
    }

    /// `root` and the items it is derived from.
    fn closure(&self, root: u32) -> Option<Vec<u32>> {
        let mut ids = vec![root];
        let mut next = 0;
        while let Some(&id) = ids.get(next) {
            for input in self.inputs(id) {
                if !ids.contains(&input) {
                    ids.push(input);
                }
            }
            if ids.len() > ITEMS {
                return None;
            }
            next = next.checked_add(1)?;
        }
        Some(ids)
    }

    /// The properties `ids` keep in a file of their own: each item's own, but that `root` takes the turns and crops
    /// of `like` instead, and no auxiliary type. The property boxes, and for each item the (1-based) indices of its.
    fn kept(&self, ids: &[u32], root: u32, like: u32) -> Option<Kept> {
        let mut properties: Vec<Vec<u8>> = vec![];
        let mut index = |property: &[u8]| -> Option<u16> {
            let at = if let Some(at) = properties.iter().position(|p| p == property) {
                at
            } else {
                properties.push(property.to_vec());
                properties.len().checked_sub(1)?
            };
            u16::try_from(at.checked_add(1)?).ok()
        };
        let mut placed = vec![];
        for &id in ids {
            let mut listed = vec![];
            for &at in self.associations.get(&id)? {
                let property = self.properties.get(usize::from(at).checked_sub(1)?)?;
                let kind = property.get(4..8)?;
                let turns = TURNS.iter().any(|k| &k[..] == kind);
                if !(turns && id == root) && kind != b"auxC" {
                    listed.push(index(property)?);
                }
            }
            if id == root {
                for kind in TURNS {
                    for property in self.properties_of(like, kind) {
                        listed.push(index(property)?);
                    }
                }
            }
            placed.push((u16::try_from(id).ok()?, listed));
        }
        Some((properties, placed))
    }

    /// The `meta` box of a file of `ids`, whose data start at the offsets given.
    fn write_meta(&self, ids: &[u32], root: u32, kept: &Kept, locations: &[(u32, u32)]) -> Option<Vec<u8>> {
        let (properties, placed) = kept;
        let mut infe = vec![];
        for &id in ids {
            let mut body = vec![2, 0, 0, 0];
            body.extend(id16(id)?);
            body.extend([0, 0]);
            body.extend(self.kind(id)?);
            body.push(0);
            infe.extend(boxed(b"infe", &body)?);
        }
        let iinf = full(
            b"iinf",
            &[&u16::try_from(ids.len()).ok()?.to_be_bytes()[..], &infe].concat(),
        )?;
        let mut refs = vec![];
        for reference in self
            .references
            .iter()
            .filter(|r| &r.kind == b"dimg" && ids.contains(&r.from))
        {
            let mut body = id16(reference.from)?.to_vec();
            body.extend(u16::try_from(reference.to.len()).ok()?.to_be_bytes());
            for to in &reference.to {
                body.extend(id16(*to)?);
            }
            refs.extend(boxed(b"dimg", &body)?);
        }
        let essential = |property: &[u8]| {
            [&b"hvcC"[..], b"av1C", b"avcC", b"clap", b"irot", b"imir", b"vvcC"]
                .contains(&property.get(4..8).unwrap_or(&[]))
        };
        let mut ipma = u32::try_from(placed.len()).ok()?.to_be_bytes().to_vec();
        for (id, listed) in placed {
            ipma.extend(id.to_be_bytes());
            ipma.push(u8::try_from(listed.len()).ok()?);
            for &at in listed {
                let property = properties.get(usize::from(at).checked_sub(1)?)?;
                let flag = if essential(property) { 0x80 } else { 0 };
                ipma.push(u8::try_from(at).ok().filter(|at| *at < 128)? | flag);
            }
        }
        let iprp = boxed(
            b"iprp",
            &[boxed(b"ipco", &properties.concat())?, full(b"ipma", &ipma)?].concat(),
        )?;
        let mut iloc = vec![0x44, 0x00];
        iloc.extend(u16::try_from(ids.len()).ok()?.to_be_bytes());
        for ((id, _), (offset, length)) in placed.iter().zip(locations) {
            iloc.extend(id.to_be_bytes());
            iloc.extend([0, 0, 0, 1]);
            iloc.extend(offset.to_be_bytes());
            iloc.extend(length.to_be_bytes());
        }
        let hdlr = full(b"hdlr", &[&[0u8; 4][..], b"pict", &[0; 13]].concat())?;
        let pitm = full(b"pitm", &id16(root)?)?;
        full(
            b"meta",
            &[hdlr, pitm, iinf, full(b"iref", &refs)?, iprp, full(b"iloc", &iloc)?].concat(),
        )
    }

    /// `root` and the items it is derived from, as a HEIF file of its own: what libheif decodes as one picture. The
    /// picture turns and crops as `like` (the primary) does, whatever `root` says of itself.
    fn extract(&self, file: &mut File, root: u32, like: u32) -> Option<Vec<u8>> {
        let ids = self.closure(root)?;
        let kept = self.kept(&ids, root, like)?;
        let mut data = vec![];
        for &id in &ids {
            data.push(self.data(file, id)?);
        }
        let ftyp = boxed(b"ftyp", &[&b"mif1"[..], &[0; 4], b"mif1", b"heic"].concat())?;
        // The offsets are written once to size the box, and again once it is known where the data start.
        let sized = self.write_meta(&ids, root, &kept, &vec![(0, 0); ids.len()])?;
        let mut at = u32::try_from(ftyp.len().checked_add(sized.len())?.checked_add(8)?).ok()?;
        let mut locations = vec![];
        for bytes in &data {
            let length = u32::try_from(bytes.len()).ok()?;
            locations.push((at, length));
            at = at.checked_add(length)?;
        }
        let meta = self.write_meta(&ids, root, &kept, &locations)?;
        let mdat = boxed(b"mdat", &data.concat())?;
        Some([ftyp, meta, mdat].concat())
    }
}

/// The `meta` box of the HEIF file `file`, read where it is, before or after the media.
fn read_meta(file: &mut File) -> Option<Meta> {
    let size = file.metadata().ok()?.len();
    let mut at = 0u64;
    let mut first = true;
    while at.checked_add(8)? <= size {
        let mut header = [0u8; 16];
        file.seek(SeekFrom::Start(at)).ok()?;
        let n = file.read(&mut header).ok()?;
        let (len, kind) = (
            u64::from(u32::from_be_bytes(header.get(..4)?.try_into().ok()?)),
            header.get(4..8)?,
        );
        let (len, head) = match len {
            0 => (size.checked_sub(at)?, 8),
            1 if n >= 16 => (u64::from_be_bytes(header.get(8..16)?.try_into().ok()?), 16),
            _ => (len, 8),
        };
        if len < head || at.checked_add(len)? > size || (first && kind != b"ftyp") {
            return None;
        }
        first = false;
        if kind == b"meta" {
            if len > META {
                return None;
            }
            let mut body = vec![0; usize::try_from(len.checked_sub(head)?).ok()?];
            file.seek(SeekFrom::Start(at.checked_add(head)?)).ok()?;
            file.read_exact(&mut body).ok()?;
            return Meta::parse(body.get(4..)?);
        }
        at = at.checked_add(len)?;
    }
    None
}

/// The gain map of a HEIF still, ready to be scaled into a JPEG's.
pub struct HeifMap {
    /// The map's coded image as a HEIF file of its own.
    pub heif: Vec<u8>,
    /// How the map is applied, for the map as it is coded.
    pub boost: Boost,
    /// Apple's map is coded in Rec.709's transfer, which `boost` assumes away: the headroom it was computed from.
    pub apple: Option<f64>,
}

/// The gain map of the HEIF file at `path`.
pub fn gain_map(path: &Path) -> Option<HeifMap> {
    let mut file = File::open(path).ok()?;
    let meta = read_meta(&mut file)?;
    let primary = meta.primary;
    // ISO 21496-1: a tmap item derived from the primary and the map, which says how.
    for tmap in meta
        .items
        .iter()
        .filter(|(_, item)| &item.kind == b"tmap")
        .map(|(id, _)| *id)
    {
        let inputs = meta.inputs(tmap);
        let &[base, map] = inputs.as_slice() else {
            continue;
        };
        if base != primary {
            continue;
        }
        let payload = meta.data(&mut file, tmap)?;
        let Some(boost) = payload
            .split_first()
            .filter(|(version, _)| **version == 0)
            .and_then(|(_, iso)| Boost::from_iso(iso))
        else {
            continue;
        };
        return Some(HeifMap {
            heif: meta.extract(&mut file, map, primary)?,
            boost,
            apple: None,
        });
    }
    // Apple's: an auxiliary image of the primary, of its own type, strong as its maker note says.
    for aux in meta.referring(b"auxl", primary) {
        let is_apple = (meta.properties_of(aux, b"auxC").into_iter())
            .any(|p| p.get(12..).is_some_and(|t| t.starts_with(APPLE_GAIN_MAP)));
        if !is_apple {
            continue;
        }
        let exif = meta
            .referring(b"cdsc", primary)
            .into_iter()
            .find(|id| meta.kind(*id) == Some(*b"Exif"))?;
        let headroom = apple_headroom(&meta.data(&mut file, exif)?)?;
        return Some(HeifMap {
            heif: meta.extract(&mut file, aux, primary)?,
            boost: Boost::apple(headroom),
            apple: Some(headroom),
        });
    }
    None
}

/// How the primary picture of the HEIF file at `path` codes its light, if it is PQ or HLG: the nclx `colr` of the
/// primary item, or of the first image a grid or overlay is made of.
pub fn hdr(path: &Path) -> Option<crate::hdr::Hdr> {
    let mut file = File::open(path).ok()?;
    let meta = read_meta(&mut file)?;
    let mut candidates = vec![meta.primary];
    candidates.extend(meta.inputs(meta.primary).into_iter().take(1));
    for id in candidates {
        for colr in meta.properties_of(id, b"colr") {
            if colr.get(8..12) == Some(b"nclx") {
                let primaries = u16::from_be_bytes(colr.get(12..14)?.try_into().ok()?);
                let transfer = u16::from_be_bytes(colr.get(14..16)?.try_into().ok()?);
                return crate::hdr::Hdr::from_codes(primaries, transfer);
            }
        }
    }
    None
}

/// Apple's headroom (a ratio) from an Exif item's maker note.
fn apple_headroom(exif: &[u8]) -> Option<f64> {
    let skip = usize::try_from(u32::from_be_bytes(exif.get(..4)?.try_into().ok()?)).ok()?;
    apple_headroom_of(exif.get(4usize.checked_add(skip)?..)?)
}

/// Apple's headroom (a ratio) from the maker note of an EXIF `tiff` structure: tags 33 and 48 as Apple's documentation
/// reads them, an absent 48 as 0.
pub(crate) fn apple_headroom_of(tiff: &[u8]) -> Option<f64> {
    let note = maker_note(tiff)?;
    let (maker33, maker48) = (apple_tag(note, 0x21)?, apple_tag(note, 0x30).unwrap_or(0.0));
    let stops = match (maker33 < 1.0, maker48 <= 0.01) {
        (true, true) => (-20.0f64).mul_add(maker48, 1.8),
        (true, false) => (-0.101f64).mul_add(maker48, 1.601),
        (false, true) => (-70.0f64).mul_add(maker48, 3.0),
        (false, false) => (-0.303f64).mul_add(maker48, 2.303),
    };
    Some(stops.max(0.0).exp2())
}

fn tiff_u16(tiff: &[u8], at: usize, little: bool) -> Option<u16> {
    let bytes: [u8; 2] = tiff.get(at..at.checked_add(2)?)?.try_into().ok()?;
    Some(if little {
        u16::from_le_bytes(bytes)
    } else {
        u16::from_be_bytes(bytes)
    })
}

fn tiff_u32(tiff: &[u8], at: usize, little: bool) -> Option<u32> {
    let bytes: [u8; 4] = tiff.get(at..at.checked_add(4)?)?.try_into().ok()?;
    Some(if little {
        u32::from_le_bytes(bytes)
    } else {
        u32::from_be_bytes(bytes)
    })
}

/// An IFD's entry: its tag, type, count and where its value's four bytes are.
type Entry = (u16, u16, u32, usize);

/// The entries of the IFD at `at`.
fn ifd(tiff: &[u8], at: usize, little: bool) -> Option<Vec<Entry>> {
    let count = usize::from(tiff_u16(tiff, at, little)?);
    (0..count.min(512))
        .map(|n| {
            let entry = at.checked_add(2)?.checked_add(n.checked_mul(12)?)?;
            Some((
                tiff_u16(tiff, entry, little)?,
                tiff_u16(tiff, entry.checked_add(2)?, little)?,
                tiff_u32(tiff, entry.checked_add(4)?, little)?,
                entry.checked_add(8)?,
            ))
        })
        .collect()
}

/// The maker note of a TIFF structure (EXIF): its bytes.
fn maker_note(tiff: &[u8]) -> Option<&[u8]> {
    let little = match tiff.get(..2)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let at = |at: u32| usize::try_from(at).ok();
    let first = ifd(tiff, at(tiff_u32(tiff, 4, little)?)?, little)?;
    let &(_, _, _, pointer) = first.iter().find(|(tag, ..)| *tag == 0x8769)?;
    let exif = ifd(tiff, at(tiff_u32(tiff, pointer, little)?)?, little)?;
    let &(_, _, count, value) = exif.iter().find(|(tag, ..)| *tag == 0x927c)?;
    let start = at(tiff_u32(tiff, value, little)?)?;
    tiff.get(start..start.checked_add(at(count)?)?)
}

/// A rational of Apple's maker note (`note` starts at "Apple iOS"), whose offsets count from its start.
fn apple_tag(note: &[u8], wanted: u16) -> Option<f64> {
    if !note.starts_with(b"Apple iOS\0") {
        return None;
    }
    let little = match note.get(12..14)? {
        b"II" => true,
        b"MM" => false,
        _ => return None,
    };
    let (_, kind, _, value) = *ifd(note, 14, little)?.iter().find(|(tag, ..)| *tag == wanted)?;
    let at = usize::try_from(tiff_u32(note, value, little)?).ok()?;
    let (numerator, denominator) = (tiff_u32(note, at, little)?, tiff_u32(note, at.checked_add(4)?, little)?);
    if denominator == 0 || !matches!(kind, 5 | 10) {
        return None;
    }
    let numerator = if kind == 10 {
        f64::from(i32::from_be_bytes(numerator.to_be_bytes()))
    } else {
        f64::from(numerator)
    };
    Some(numerator / f64::from(denominator))
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
    use super::*;

    fn boxed(kind: &[u8], body: &[u8]) -> Vec<u8> {
        [&(body.len() as u32 + 8).to_be_bytes()[..], kind, body].concat()
    }

    fn full(kind: &[u8], body: &[u8]) -> Vec<u8> {
        boxed(kind, &[&[0u8; 4][..], body].concat())
    }

    /// A HEIF file: item 1 is the primary (hvcC, ispe, irot 1), item 2 a grid of items 3 and 4 that refers to it as an
    /// auxiliary image of Apple's type (its own irot 3), each tile holding a few bytes of "coded" data.
    fn file(aux_type: &[u8]) -> Vec<u8> {
        let properties = [
            boxed(b"hvcC", b"config-primary"),
            boxed(b"ispe", &[0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 6]),
            boxed(b"irot", &[1]),
            boxed(b"hvcC", b"config-tile"),
            boxed(b"ispe", &[0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2]),
            boxed(b"irot", &[3]),
            full(b"auxC", &[aux_type, &[0]].concat()),
        ];
        let infe = |id: u8, kind: &[u8; 4]| boxed(b"infe", &[&[2, 0, 0, 0][..], &[0, id, 0, 0], kind, &[0]].concat());
        let items = [infe(1, b"hvc1"), infe(2, b"grid"), infe(3, b"hvc1"), infe(4, b"hvc1")].concat();
        let iinf = full(b"iinf", &[&[0, 4][..], &items].concat());
        let iref = full(
            b"iref",
            &[
                boxed(b"dimg", &[0, 2, 0, 2, 0, 3, 0, 4]),
                boxed(b"auxl", &[0, 2, 0, 1, 0, 1]),
            ]
            .concat(),
        );
        // Items: 1 [hvcC, ispe, irot], 2 [ispe, irot', auxC], 3 and 4 [hvcC', ispe'].
        let ipma = full(
            b"ipma",
            &[
                &[0, 0, 0, 4][..],
                &[0, 1, 3, 1, 2, 3],
                &[0, 2, 3, 5, 6, 7],
                &[0, 3, 2, 4, 5],
                &[0, 4, 2, 4, 5],
            ]
            .concat(),
        );
        let iprp = boxed(b"iprp", &[boxed(b"ipco", &properties.concat()), ipma].concat());
        let data: [&[u8]; 4] = [
            b"primary-picture",
            b"\0\0\x01\x01\0\x08\0\x06",
            b"tile-three",
            b"tile-four!",
        ];
        let build = |offset: u32| {
            let mut iloc = vec![0x44, 0, 0, 4];
            let mut at = offset;
            for (n, bytes) in data.iter().enumerate() {
                iloc.extend([0, n as u8 + 1, 0, 0, 0, 1]);
                iloc.extend(at.to_be_bytes());
                iloc.extend((bytes.len() as u32).to_be_bytes());
                at += bytes.len() as u32;
            }
            let hdlr = full(b"hdlr", &[&[0u8; 4][..], b"pict", &[0; 13]].concat());
            let pitm = full(b"pitm", &[0, 1]);
            full(
                b"meta",
                &[
                    hdlr,
                    pitm,
                    iinf.clone(),
                    iref.clone(),
                    iprp.clone(),
                    full(b"iloc", &iloc),
                ]
                .concat(),
            )
        };
        let ftyp = boxed(b"ftyp", b"heic\0\0\0\0mif1heic");
        let offset = (ftyp.len() + build(0).len() + 8) as u32;
        [ftyp, build(offset), boxed(b"mdat", &data.concat())].concat()
    }

    fn open(bytes: &[u8]) -> (tempfile::NamedTempFile, File) {
        let temp = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(temp.path(), bytes).unwrap();
        let file = File::open(temp.path()).unwrap();
        (temp, file)
    }

    #[test]
    fn an_auxiliary_image_leaves_as_a_file_of_its_own_turning_as_the_primary_does() {
        let (_temp, mut file) = open(&file(APPLE_GAIN_MAP));
        let meta = read_meta(&mut file).expect("a meta box");
        assert_eq!(meta.primary, 1);
        assert_eq!(meta.referring(b"auxl", 1), [2]);
        let alone = meta.extract(&mut file, 2, 1).expect("a file of its own");
        let (_temp, mut file) = open(&alone);
        let again = read_meta(&mut file).expect("which parses");
        assert_eq!(
            (again.primary, again.items.keys().copied().collect::<Vec<_>>()),
            (2, vec![2, 3, 4])
        );
        assert_eq!(again.kind(2), Some(*b"grid"));
        assert_eq!(again.inputs(2), [3, 4]);
        assert_eq!(again.data(&mut file, 3).unwrap(), b"tile-three");
        assert_eq!(again.data(&mut file, 4).unwrap(), b"tile-four!");
        assert_eq!(again.data(&mut file, 2).unwrap(), b"\0\0\x01\x01\0\x08\0\x06");
        // The grid turns as the primary (irot 1), not as it did itself (irot 3), and says nothing of what it was.
        assert_eq!(again.properties_of(2, b"irot"), [&boxed(b"irot", &[1])[..]]);
        assert!(again.properties_of(2, b"auxC").is_empty());
        assert_eq!(again.properties_of(3, b"hvcC"), [&boxed(b"hvcC", b"config-tile")[..]]);
    }

    #[test]
    fn a_file_cut_anywhere_or_with_a_lying_box_is_refused_never_a_panic() {
        let whole = file(APPLE_GAIN_MAP);
        for length in 0..whole.len() {
            let (_temp, mut file) = open(&whole[..length]);
            if let Some(meta) = read_meta(&mut file) {
                // Whatever parsed answers within the file.
                for id in 1..=4 {
                    let _ = meta.extract(&mut file, id, 1);
                }
            }
        }
        for at in 0..whole.len() {
            let mut lying = whole.clone();
            lying[at] = lying[at].wrapping_add(0x41);
            let (_temp, mut file) = open(&lying);
            if let Some(meta) = read_meta(&mut file) {
                for id in 1..=4 {
                    let _ = meta.extract(&mut file, id, 1);
                    let _ = meta.referring(b"auxl", id);
                }
            }
        }
    }

    /// An EXIF TIFF (big-endian) whose Exif IFD holds a maker note of Apple's: tag 0x21 as a rational, and tag 0x30
    /// when `gain` is given, which Apple's files of recent years carry.
    fn exif(headroom: (i32, i32), gain: Option<(i32, i32)>) -> Vec<u8> {
        let mut note = b"Apple iOS\0\0\x01MM".to_vec();
        let tags = 1 + usize::from(gain.is_some());
        note.extend((tags as u16).to_be_bytes());
        let values = 14 + 2 + 12 * tags + 4;
        let mut entries = vec![];
        let mut data = vec![];
        for (tag, (n, d)) in [(0x21u16, Some(headroom)), (0x30, gain)]
            .into_iter()
            .filter_map(|(t, v)| Some((t, v?)))
        {
            entries.extend(tag.to_be_bytes());
            entries.extend([0, 10, 0, 0, 0, 1]);
            entries.extend(((values + data.len()) as u32).to_be_bytes());
            data.extend(n.to_be_bytes());
            data.extend(d.to_be_bytes());
        }
        note.extend(entries);
        note.extend([0; 4]);
        note.extend(data);
        // IFD0 at 8 with the Exif IFD pointer, the Exif IFD with the maker note after them.
        let mut tiff = b"MM\0*\0\0\0\x08".to_vec();
        tiff.extend([0, 1, 0x87, 0x69, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26, 0, 0, 0, 0]);
        tiff.extend([0, 1, 0x92, 0x7c, 0, 7]);
        tiff.extend((note.len() as u32).to_be_bytes());
        tiff.extend(44u32.to_be_bytes());
        tiff.extend([0; 4]);
        tiff.extend(note);
        // The Exif item: the offset of the TIFF header after its own field (6 for "Exif\0\0").
        [&6u32.to_be_bytes()[..], b"Exif\0\0", &tiff].concat()
    }

    #[test]
    fn apples_headroom_follows_its_documented_formula_and_an_absent_tag_48_is_zero() {
        let stops =
            |maker33: (i32, i32), maker48: Option<(i32, i32)>| apple_headroom(&exif(maker33, maker48)).unwrap().log2();
        let near = |got: f64, wanted: f64| (got - wanted).abs() < 1e-9;
        // The real file of a phone: tag 33 is 22307 / 25388 = 0.8786 and there is no tag 48: 1.8 stops.
        assert!(near(stops((22307, 25388), None), 1.8));
        // Tag 33 below 1: -20 g + 1.8 up to a tag 48 of 0.01, then -0.101 g + 1.601.
        assert!(near(stops((1, 2), Some((0, 1))), 1.8));
        assert!(near(stops((1, 2), Some((-1, 100))), 0.2 + 1.8));
        assert!(near(stops((1, 2), Some((1, 100))), -0.2 + 1.8));
        assert!(near(stops((1, 2), Some((1, 10))), -0.101 * 0.1 + 1.601));
        assert!(near(stops((1, 2), Some((2, 1))), -0.101 * 2.0 + 1.601));
        // At 1 or more: -70 g + 3 up to 0.01, then -0.303 g + 2.303, never below no headroom.
        assert!(near(stops((3, 2), Some((0, 1))), 3.0));
        assert!(near(stops((1, 1), Some((1, 100))), -0.7 + 3.0));
        assert!(near(stops((3, 2), Some((1, 2))), -0.303 * 0.5 + 2.303));
        assert!(
            near(stops((3, 2), Some((10, 1))), 0.0),
            "-0.303 × 10 + 2.303 is below 0"
        );
        // Anything that is not Apple's note says nothing.
        let mut other = exif((1, 2), None);
        let at = other.windows(9).position(|w| w == b"Apple iOS").unwrap();
        other[at] = b'B';
        assert_eq!(apple_headroom(&other), None);
        assert_eq!(apple_headroom(&other[..30]), None);
        assert_eq!(apple_headroom(&[]), None);
    }
}
