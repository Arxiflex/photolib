//! Edited copies of JPEG photos (`METHOD_EDIT_COPY`; design 11 §2.5, §5; ADR-0331). The original's bytes never change.
//! An edit of geometry alone keeps the original's compressed pixels: its turns and mirrors become the EXIF orientation
//! and a crop keeps whole blocks (`jpeg.rs`). Any other edit renders the original, decoded by the host as shown, with
//! `develop.rs` and encodes it. The copy keeps the original's EXIF, XMP, ICC profile and IPTC but what its new shape
//! makes untrue (a sphere's projection, faces' regions), tells its new orientation and size, and records in its XMP the
//! edit (`photolib:recipe`) and the original's BLAKE3, which the host hashed (`xmpMM:DerivedFrom`), from which the
//! version model (M8) makes it a version of its original.

mod jpeg;

use crate::proto::kernel::v1::{
    CallError, CallErrorCode::InvalidRequest, Develop, DevelopRequest, EditCopyRequest, EditCopyResponse, Image, Rect,
    RenderRecipeRequest,
};
use crate::proto::model::v1::{CaptureTime, DigitalSourceType, EditRecipe, operation::Kind};
use crate::{develop, error, metadata, recipe};
use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use jpeg::{Jpeg, Segment};
use prost::Message;
use sha2::{Digest, Sha256};

const EXIF: &[u8] = b"Exif\0\0";
const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
const XMP_EXTENSION: &[u8] = b"http://ns.adobe.com/xmp/extension/\0";
const ICC: &[u8] = b"ICC_PROFILE\0";
/// Where an ICC profile's colour space is in its first segment: after the name, the chunk's number and count, and 16
/// bytes of the profile's header.
const ICC_SPACE: std::ops::Range<usize> = 30..34;
/// The namespace of Photolib's XMP properties.
const NAMESPACE: &str = "http://ns.photolib.org/1.0/";
/// The quality of an encoded copy, unless its original's was higher.
const QUALITY: u16 = 92;
/// XMP properties that a copy no longer has: the original's orientation, size and identity, and its record of an edit.
const STALE: [&str; 12] = [
    "tiff:Orientation",
    "tiff:ImageWidth",
    "tiff:ImageLength",
    "exif:PixelXDimension",
    "exif:PixelYDimension",
    "xmpMM:DocumentID",
    "xmpMM:InstanceID",
    "xmpMM:DerivedFrom",
    "photolib:recipe",
    "photolib:editRecipe",
    "photolib:recipeSha256",
    "Iptc4xmpExt:DigitalSourceType",
];
/// XMP properties of what follows the image in a motion photo or an Ultra HDR JPEG, which a still copy leaves out.
const COMPOSITE: [&str; 12] = [
    "GCamera:MotionPhoto",
    "GCamera:MotionPhotoVersion",
    "GCamera:MotionPhotoPresentationTimestampUs",
    "GCamera:MicroVideo",
    "GCamera:MicroVideoVersion",
    "GCamera:MicroVideoOffset",
    "GCamera:MicroVideoPresentationTimestampUs",
    "Camera:MotionPhoto",
    "Camera:MotionPhotoVersion",
    "Camera:MotionPhotoPresentationTimestampUs",
    "Container:Directory",
    "hdrgm:Version",
];
/// GPano's properties of a photo sphere, which a copy turned, mirrored or cropped no longer is: it shows flat.
const PANORAMA: [&str; 9] = [
    "GPano:ProjectionType",
    "GPano:UsePanoramaViewer",
    "GPano:FullPanoWidthPixels",
    "GPano:FullPanoHeightPixels",
    "GPano:CroppedAreaLeftPixels",
    "GPano:CroppedAreaTopPixels",
    "GPano:CroppedAreaImageWidthPixels",
    "GPano:CroppedAreaImageHeightPixels",
    "GPano:PoseHeadingDegrees",
];

#[allow(clippy::too_many_lines)] // one decision after another: what the edit is, what it keeps, what it says
pub(crate) fn edit_copy(request: EditCopyRequest) -> Result<EditCopyResponse, CallError> {
    if request.rendered && !request.metadata_from.is_empty() {
        return from_rendered(&request);
    }
    let original = request.original.as_slice();
    let jpeg = jpeg::parse(original).ok_or_else(|| invalid("original"))?;
    let hash = request.original_blake3.as_str();
    if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        return Err(invalid("original_blake3"));
    }
    let meta = metadata::read_pieces([(0, original)], 0);
    let turns = geometry_of(&request)?;
    let turn = Turn::develop(turns.quarter_turns, turns.flip).after(Turn::exif(meta.orientation));
    let size = turn.size(jpeg.width, jpeg.height);
    // The recipe's geometry starts from the original as shown, its EXIF orientation applied.
    let (checked, develop, local) = edit_of(&request, Turn::exif(meta.orientation).size(jpeg.width, jpeg.height))?;
    let crop = match develop.crop.filter(|c| c.width > 0 && c.height > 0) {
        None => (0, 0, size.0, size.1),
        Some(c) => corners(c)
            .filter(|&(_, _, x1, y1)| x1 <= size.0 && y1 <= size.1)
            .ok_or_else(|| invalid("develop"))?,
    };
    let tonal = [
        develop.temperature,
        develop.tint,
        develop.exposure,
        develop.contrast,
        develop.clarity,
    ];
    let geometry = tonal.iter().chain([&develop.saturation]).all(|&v| v == 0.0) && develop.lut.is_none() && !local;
    let whole = crop == (0, 0, size.0, size.1);
    let cut = |(x0, y0, x1, y1): (usize, usize, usize, usize)| {
        let (mw, mh) = jpeg.mcu();
        let (x0, y0) = (
            x0.checked_div(mw)?.checked_mul(mw)?,
            y0.checked_div(mh)?.checked_mul(mh)?,
        );
        let (width, height) = (x1.checked_sub(x0)?, y1.checked_sub(y0)?);
        Some((
            (width, height),
            jpeg.crop(original, x0, y0, width, height)?,
            (x0, y0, x1, y1),
        ))
    };
    let lossless_crop = if geometry && !whole {
        cut(turn.inverse().rect(crop, size))
    } else {
        None
    };
    let mut shown = (!whole).then_some(crop);
    let copy = if geometry && whole {
        Copy {
            orientation: turn.exif_value(),
            size: None,
            data: original.get(jpeg.scan_at..).unwrap_or_default().to_vec(),
            encoded: false,
            converted: false,
        }
    } else if let Some((size, data, stored)) = lossless_crop {
        // The part of the edited picture the copy shows: the crop with its corner moved to the block grid.
        shown = Some(turn.rect(stored, (jpeg.width, jpeg.height)));
        Copy {
            orientation: turn.exif_value(),
            size: Some(size),
            data,
            encoded: false,
            converted: false,
        }
    } else {
        let edit = match &checked {
            Some(c) => Edit::Recipe(c.recipe.clone()),
            None => Edit::Develop(develop.clone()),
        };
        rendered(&jpeg, request.image, Turn::exif(meta.orientation), edit)?
    };
    let time = request.capture_time.filter(|_| meta.times.is_empty());
    let record = record(
        &develop.encode_to_vec(),
        hash,
        time.as_ref(),
        checked.as_ref().map(provenance).as_deref(),
    );
    let gone = stale(&develop, &copy, whole, turn);
    let jpeg = copy
        .write(&jpeg, &jpeg, &record, &gone)
        .ok_or_else(|| invalid("original"))?;
    Ok(EditCopyResponse {
        jpeg,
        lossless: !copy.encoded,
        crop: shown.map(rect),
    })
}

/// A picture the host rendered from another JPEG (`metadata_from`): the host's pixels, with that file's metadata but its
/// colour profile and orientation, and the record of the recipe.
fn from_rendered(request: &EditCopyRequest) -> Result<EditCopyResponse, CallError> {
    let rendered = jpeg::parse(&request.original).ok_or_else(|| invalid("original"))?;
    let source = jpeg::parse(&request.metadata_from).ok_or_else(|| invalid("metadata_from"))?;
    let hash = request.original_blake3.as_str();
    if hash.len() != 64 || !hash.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
        return Err(invalid("original_blake3"));
    }
    let checked = (request.recipe.as_ref())
        .map(|r| recipe::check(r, (0, 0)).map_err(|e| prefixed(e, "recipe")))
        .transpose()?;
    let meta = metadata::read_pieces([(0, request.metadata_from.as_slice())], 0);
    let copy = Copy {
        orientation: 1,
        size: Some((rendered.width, rendered.height)),
        data: request.original.get(rendered.scan_at..).unwrap_or_default().to_vec(),
        encoded: true,
        converted: true,
    };
    let time = request.capture_time.clone().filter(|_| meta.times.is_empty());
    let record = record(
        &Develop::default().encode_to_vec(),
        hash,
        time.as_ref(),
        checked.as_ref().map(provenance).as_deref(),
    );
    let gone = stale(&Develop::default(), &copy, false, Turn::exif(1));
    let jpeg = copy
        .write(&rendered, &source, &record, &gone)
        .ok_or_else(|| invalid("metadata_from"))?;
    Ok(EditCopyResponse {
        jpeg,
        lossless: false,
        crop: None,
    })
}

/// The XMP properties the copy no longer has.
fn stale(develop: &Develop, copy: &Copy, whole: bool, turn: Turn) -> Vec<&'static str> {
    let mut gone = STALE.to_vec();
    if copy.size.is_some() {
        gone.extend(COMPOSITE);
    }
    if !develop.quarter_turns.is_multiple_of(4) || develop.flip || !whole {
        gone.extend(PANORAMA);
    }
    // The faces' regions are in the stored pixels, which a crop or an encoded turn moves.
    if !whole || copy.encoded && turn.exif_value() != 1 {
        gone.push("mwg-rs:Regions");
    }
    gone
}

/// The turns and the mirror of the edit, which a recipe's do not depend on the picture's size for: its crop needs it.
fn geometry_of(request: &EditCopyRequest) -> Result<Develop, CallError> {
    Ok(match (&request.recipe, request.rendered) {
        (Some(_), true) => Develop::default(),
        (Some(r), false) => recipe::check(r, (0, 0))
            .map_err(|e| prefixed(e, "recipe"))?
            .develop(None),
        (None, _) => request.develop.clone().unwrap_or_default(),
    })
}

/// The edit for the original as shown, of `size`: the recipe checked, its `Develop`, and whether it changes pixels
/// a `Develop` cannot. A picture the host rendered is kept as it is, whatever the recipe says.
fn edit_of(
    request: &EditCopyRequest,
    size: (usize, usize),
) -> Result<(Option<recipe::Checked>, Develop, bool), CallError> {
    let shown = (u32::try_from(size.0).unwrap_or(0), u32::try_from(size.1).unwrap_or(0));
    let checked = (request.recipe.as_ref())
        .map(|r| recipe::check(r, shown).map_err(|e| prefixed(e, "recipe")))
        .transpose()?;
    let (develop, local) = match &checked {
        Some(_) if request.rendered => (Develop::default(), false),
        Some(c) => (c.develop(Some(shown)), c.local),
        None => (request.develop.clone().unwrap_or_default(), false),
    };
    Ok((checked, develop, local))
}

/// The rectangle with corners (x0, y0) and (x1, y1), the far ones excluded.
fn rect((x0, y0, x1, y1): (usize, usize, usize, usize)) -> Rect {
    let to = |v: usize| u32::try_from(v).unwrap_or(0);
    Rect {
        x: to(x0),
        y: to(y0),
        width: to(x1.saturating_sub(x0)),
        height: to(y1.saturating_sub(y0)),
    }
}

fn invalid(field: &str) -> CallError {
    error(InvalidRequest, &[("field", field)])
}

/// A rectangle by its corners, the far ones excluded.
fn corners(rect: Rect) -> Option<(usize, usize, usize, usize)> {
    let [x, y, w, h] = [rect.x, rect.y, rect.width, rect.height].map(|v| usize::try_from(v).ok());
    let (x, y) = (x?, y?);
    Some((x, y, x.checked_add(w?)?, y.checked_add(h?)?))
}

/// The original as `shown` (decoded, its EXIF orientation applied: `image`) rendered with the edit, then encoded.
fn rendered(jpeg: &Jpeg<'_>, image: Option<Image>, shown: Turn, edit: Edit) -> Result<Copy, CallError> {
    let size = |w: u32, h: u32| (usize::try_from(w).unwrap_or(0), usize::try_from(h).unwrap_or(0));
    let image = image
        .filter(|i| size(i.width, i.height) == shown.size(jpeg.width, jpeg.height))
        .ok_or_else(|| invalid("image"))?;
    let out = match edit {
        Edit::Develop(develop) => {
            let request = DevelopRequest {
                develop: Some(develop),
                image: Some(image),
                ..Default::default()
            };
            develop::develop(request)?.image
        }
        Edit::Recipe(recipe) => {
            let request = RenderRecipeRequest {
                recipe: Some(recipe),
                image: Some(image),
            };
            recipe::render(request)?.image
        }
    }
    .ok_or_else(|| invalid("image"))?;
    let data = jpeg::encode(&out, &jpeg::quality(jpeg, QUALITY)).ok_or_else(|| invalid("image"))?;
    Ok(Copy {
        orientation: 1,
        size: Some(size(out.width, out.height)),
        data,
        encoded: true,
        converted: false,
    })
}

/// How the pixels of a copy are made: by the alpha's `Develop`, or by a recipe.
enum Edit {
    Develop(Develop),
    Recipe(EditRecipe),
}

/// `error` with the name of the request field it refers to below `field`.
fn prefixed(mut error: CallError, field: &str) -> CallError {
    if let Some(name) = error.params.get_mut("field") {
        *name = format!("{field}.{name}");
    }
    error
}

/// What the copy's XMP says of how the recipe was made: IPTC's DigitalSourceType, the recipe without the pixels of its
/// outputs (an XMP packet holds 64 KB) and the SHA-256 of the whole recipe, which the version holds.
fn provenance(checked: &recipe::Checked) -> String {
    let uri = match DigitalSourceType::try_from(checked.recipe.provenance.as_ref().map_or(0, |p| p.digital_source_type))
    {
        Ok(DigitalSourceType::HumanEdits) => Some("humanEdits"),
        Ok(DigitalSourceType::AlgorithmicallyEnhanced) => Some("algorithmicallyEnhanced"),
        Ok(DigitalSourceType::CompositeWithTrainedAlgorithmicMedia) => Some("compositeWithTrainedAlgorithmicMedia"),
        _ => None,
    };
    let mut parts: Vec<String> = vec![];
    if let Some(uri) = uri {
        parts.push(format!(
            " xmlns:Iptc4xmpExt=\"http://iptc.org/std/Iptc4xmpExt/2008-02-02/\" \
             Iptc4xmpExt:DigitalSourceType=\"http://cv.iptc.org/newscodes/digitalsourcetype/{uri}\""
        ));
    }
    let mut summary = checked.recipe.clone();
    summary.outputs.iter_mut().for_each(|o| o.data.clear());
    for operation in &mut summary.operations {
        if let Some(Kind::Lut(lut)) = operation.kind.as_mut() {
            lut.rgb16.clear();
        }
    }
    let summary = STANDARD.encode(summary.encode_to_vec());
    if summary.len() <= 40_000 {
        parts.push(format!(" photolib:editRecipe=\"{summary}\""));
    }
    let digest = Sha256::digest(checked.recipe.encode_to_vec());
    parts.push(format!(
        " photolib:recipeSha256=\"{}\"",
        digest.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().concat()
    ));
    parts.concat()
}

/// What the copy's image is: its EXIF orientation, its stored size if not the original's, its image data after the
/// segments it keeps, and whether that data was encoded anew.
struct Copy {
    orientation: u16,
    size: Option<(usize, usize)>,
    data: Vec<u8>,
    encoded: bool,
    /// Whether its pixels are in sRGB whatever the original's profile was, which the copy then leaves out.
    converted: bool,
}

impl Copy {
    /// The copy: the start of the image, its EXIF and XMP but the properties `gone`, the original's other segments
    /// that still hold, and its image data.
    fn write(&self, jpeg: &Jpeg<'_>, meta: &Jpeg<'_>, record: &str, gone: &[&str]) -> Option<Vec<u8>> {
        // A picture the host rendered keeps its own tables and frame as they are; what it says of its origin is `meta`'s.
        let (encoded, cropped) = if self.converted {
            (false, false)
        } else {
            (self.encoded, self.size.is_some())
        };
        let first = |prefix: &[u8], marker: u8| {
            meta.segments
                .iter()
                .find(|s| s.marker == marker && s.body.starts_with(prefix))
                .and_then(|s| s.body.get(prefix.len()..))
        };
        let mut out = vec![0xff, 0xd8];
        let jfif = jpeg
            .segments
            .first()
            .filter(|s| s.marker == 0xe0 && s.body.starts_with(b"JFIF\0"));
        if let Some(s) = jfif {
            out.extend(jpeg::segment(s.marker, s.body)?);
        }
        let size = self
            .size
            .map(|(w, h)| (u32::try_from(w).unwrap_or(0), u32::try_from(h).unwrap_or(0)));
        if let Some(tiff) = exif(first(EXIF, 0xe1), self.orientation, size) {
            out.extend(jpeg::segment(0xe1, &[EXIF, &tiff].concat())?);
        }
        let packet = xmp(first(XMP, 0xe1).map(String::from_utf8_lossy).as_deref(), gone, record);
        out.extend(jpeg::segment(0xe1, &[XMP, packet.as_bytes()].concat())?);
        for s in jpeg.segments.iter().skip(usize::from(jfif.is_some())) {
            if keep(s, encoded, cropped) {
                out.extend(jpeg::segment(s.marker, s.body)?);
            }
        }
        if self.converted {
            // The origin's IPTC and extended XMP; its colour profile is not the host's pixels'.
            for s in &meta.segments {
                if s.marker == 0xed || (s.marker == 0xe1 && s.body.starts_with(XMP_EXTENSION)) {
                    out.extend(jpeg::segment(s.marker, s.body)?);
                }
            }
        }
        out.extend_from_slice(&self.data);
        Some(out)
    }
}

/// Whether a segment of the original (but its EXIF and XMP, which the copy rewrites) stays in the copy: all of them
/// with the original's image data; but its multi-picture index and tables with a crop of it; only its extended XMP,
/// an RGB ICC profile and IPTC with an encoded image.
fn keep(s: &Segment<'_>, encoded: bool, cropped: bool) -> bool {
    let is = |marker: u8, prefix: &[u8]| s.marker == marker && s.body.starts_with(prefix);
    if is(0xe1, EXIF) || is(0xe1, XMP) {
        return false;
    }
    if encoded {
        let rgb = s.body.get(ICC_SPACE) == Some(b"RGB ");
        return is(0xe1, XMP_EXTENSION) || is(0xe2, ICC) && rgb || s.marker == 0xed;
    }
    !cropped || !(is(0xe2, b"MPF\0") || matches!(s.marker, 0xc4 | 0xdd) || jpeg::is_frame(s.marker))
}

/// The copy's EXIF (a TIFF block), from the original's: `orientation`, and when the image's stored `size` changed,
/// that size and no thumbnail (IFD1's would show the original). None without EXIF when the orientation is 1.
fn exif(original: Option<&[u8]>, orientation: u16, size: Option<(u32, u32)>) -> Option<Vec<u8>> {
    let Some(original) = original else {
        let mut tiff = b"MM\0\x2a\0\0\0\x08\0\x01\x01\x12\0\x03\0\0\0\x01".to_vec();
        tiff.extend(orientation.to_be_bytes());
        tiff.extend([0; 6]);
        return (orientation != 1).then_some(tiff);
    };
    let mut tiff = Tiff {
        bytes: original.to_vec(),
        big: original.starts_with(b"MM"),
    };
    let ifd0 = tiff.u32(4)?;
    let entries = tiff.entries(ifd0)?;
    let mut found = false;
    for &(tag, at) in &entries {
        match tag {
            0x0112 => {
                tiff.set(at, 3, u32::from(orientation))?;
                found = true;
            }
            0x0100 | 0x0101 => tiff.size(at, tag == 0x0100, size)?,
            0x8769 => {
                for (tag, at) in tiff.entries(tiff.u32(at.checked_add(8)?)?).unwrap_or_default() {
                    if matches!(tag, 0xa002 | 0xa003) {
                        tiff.size(at, tag == 0xa002, size)?;
                    } else if tag == 0x927c {
                        tiff.unpair(at);
                    }
                }
            }
            _ => {}
        }
    }
    let next = ifd0.checked_add(2)?.checked_add(12usize.checked_mul(entries.len())?)?;
    if size.is_some() {
        tiff.put(next, &[0; 4])?;
    }
    if !found && orientation != 1 {
        tiff.append_orientation(&entries, next, orientation)?;
    }
    Some(tiff.bytes)
}

/// A TIFF block being edited in place: values change, nothing moves, so every offset in it stays valid.
struct Tiff {
    bytes: Vec<u8>,
    big: bool,
}

impl Tiff {
    fn get<const N: usize>(&self, at: usize) -> Option<[u8; N]> {
        let mut b: [u8; N] = self.bytes.get(at..at.checked_add(N)?)?.try_into().ok()?;
        if !self.big {
            b.reverse();
        }
        Some(b)
    }

    fn u32(&self, at: usize) -> Option<usize> {
        usize::try_from(u32::from_be_bytes(self.get(at)?)).ok()
    }

    fn put(&mut self, at: usize, bytes: &[u8]) -> Option<()> {
        let end = at.checked_add(bytes.len())?;
        let target = self.bytes.get_mut(at..end)?;
        target.copy_from_slice(bytes);
        if !self.big {
            target.reverse();
        }
        Some(())
    }

    /// The tags of the IFD at `at` and where each entry starts.
    fn entries(&self, at: usize) -> Option<Vec<(u16, usize)>> {
        let count = usize::from(u16::from_be_bytes(self.get(at)?));
        (0..count)
            .map(|i| {
                let entry = at.checked_add(2)?.checked_add(i.checked_mul(12)?)?;
                Some((u16::from_be_bytes(self.get(entry)?), entry))
            })
            .collect()
    }

    /// Makes the entry at `at` one value of `kind` (3, SHORT, or 4, LONG).
    fn set(&mut self, at: usize, kind: u16, value: u32) -> Option<()> {
        let entry = at.checked_add(2)?;
        self.put(entry, &kind.to_be_bytes())?;
        self.put(entry.checked_add(2)?, &1u32.to_be_bytes())?;
        if kind == 3 {
            self.put(entry.checked_add(6)?, &u16::try_from(value).ok()?.to_be_bytes())?;
            self.put(entry.checked_add(8)?, &[0; 2])
        } else {
            self.put(entry.checked_add(6)?, &value.to_be_bytes())
        }
    }

    /// Blanks the Live Photo content identifier (0x0011) of Apple's MakerNote, whose entry is at `at`, so that the copy,
    /// a still, never pairs with its original's video (design 11 §5.2). The note is "Apple iOS", a version and its byte
    /// order, then an IFD whose offsets count from its start.
    fn unpair(&mut self, at: usize) -> Option<()> {
        let base = self.u32(at.checked_add(8)?)?;
        let header = self.bytes.get(base..base.checked_add(14)?)?;
        if !header.starts_with(b"Apple iOS\0") {
            return Some(());
        }
        let note = Self {
            big: header.ends_with(b"MM"),
            bytes: self.bytes.get(base..)?.to_vec(),
        };
        for (tag, entry) in note.entries(14)? {
            if tag == 0x0011 {
                let count = note.u32(entry.checked_add(4)?)?;
                let value = if count > 4 {
                    note.u32(entry.checked_add(8)?)?
                } else {
                    entry.checked_add(8)?
                };
                let start = base.checked_add(value)?;
                self.bytes.get_mut(start..start.checked_add(count)?)?.fill(0);
            }
        }
        Some(())
    }

    /// Sets a width (`wide`) or height entry to `size`'s, as a SHORT when it fits.
    fn size(&mut self, at: usize, wide: bool, size: Option<(u32, u32)>) -> Option<()> {
        let Some((w, h)) = size else { return Some(()) };
        let value = if wide { w } else { h };
        self.set(at, if value > 0xffff { 4 } else { 3 }, value)
    }

    /// A copy of IFD0, whose `entries` end at `next`, with an orientation entry, at the end of the block in place of
    /// the original's.
    fn append_orientation(&mut self, entries: &[(u16, usize)], next: usize, orientation: u16) -> Option<()> {
        let mut added = Self {
            bytes: vec![0; 12],
            big: self.big,
        };
        added.put(0, &0x0112u16.to_be_bytes())?;
        added.set(0, 3, u32::from(orientation))?;
        let mut rows: Vec<(u16, &[u8])> = entries
            .iter()
            .map(|&(tag, at)| Some((tag, self.bytes.get(at..at.checked_add(12)?)?)))
            .collect::<Option<_>>()?;
        rows.push((0x0112, &added.bytes));
        rows.sort_by_key(|&(tag, _)| tag);
        let mut ifd = Self {
            bytes: vec![0; 2],
            big: self.big,
        };
        ifd.put(0, &u16::try_from(rows.len()).ok()?.to_be_bytes())?;
        ifd.bytes.extend(rows.into_iter().flat_map(|(_, row)| row));
        ifd.bytes.extend(self.bytes.get(next..next.checked_add(4)?)?);
        let at = self.bytes.len().next_multiple_of(2);
        self.bytes.resize(at, 0);
        self.bytes.extend(ifd.bytes);
        self.put(4, &u32::try_from(at).ok()?.to_be_bytes())
    }
}

/// The copy's XMP packet: the original's but its properties `gone`, with `record` added.
fn xmp(original: Option<&str>, gone: &[&str], record: &str) -> String {
    let Some(mut xml) = original.filter(|x| x.contains("</rdf:RDF>")).map(String::from) else {
        return format!(
            "<?xpacket begin=\"\u{feff}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?><x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\
             <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">{record}</rdf:RDF></x:xmpmeta>\
             <?xpacket end=\"w\"?>"
        );
    };
    for name in gone {
        while let Some(range) = attribute(&xml, name).or_else(|| element(&xml, name)) {
            xml.replace_range(range, "");
        }
    }
    if let Some(at) = xml.rfind("</rdf:RDF>") {
        xml.insert_str(at, record);
    }
    xml
}

/// Where the attribute `name` is in a tag, with the space before it.
fn attribute(xml: &str, name: &str) -> Option<std::ops::Range<usize>> {
    xml.match_indices(name).find_map(|(at, _)| {
        let start = xml.get(..at)?.trim_end().len();
        let rest = xml.get(at..)?.strip_prefix(name)?.strip_prefix('=')?;
        let quote = rest.chars().next().filter(|&q| q == '"' || q == '\'')?;
        let value = rest.get(1..)?.find(quote)?;
        let end = xml.len().checked_sub(rest.len())?.checked_add(value)?.checked_add(2)?;
        (start < at).then_some(start..end)
    })
}

/// Where the element `name` is, from its start tag to its end tag.
fn element(xml: &str, name: &str) -> Option<std::ops::Range<usize>> {
    xml.match_indices('<').find_map(|(at, _)| {
        let rest = xml.get(at.checked_add(1)?..)?.strip_prefix(name)?;
        if !rest.starts_with(|c: char| c.is_whitespace() || c == '>' || c == '/') {
            return None;
        }
        let tag = xml.len().checked_sub(rest.len())?.checked_add(rest.find('>')?)?;
        if xml.get(..tag)?.ends_with('/') {
            return Some(at..tag.checked_add(1)?);
        }
        let close = format!("</{name}>");
        let end = tag
            .checked_add(xml.get(tag..)?.find(&close)?)?
            .checked_add(close.len())?;
        Some(at..end)
    })
}

/// The copy's XMP description: the edit as a canonical `photolib.kernel.v1.Develop`, the original's BLAKE3 and the
/// capture time the original's metadata lacked.
fn record(recipe: &[u8], hash: &str, time: Option<&CaptureTime>, provenance: Option<&str>) -> String {
    let local = time
        .map(|t| t.local_datetime.as_str())
        .filter(|t| t.len() >= 16 && t.bytes().all(|b| b.is_ascii_digit() || b"-:T.".contains(&b)));
    let date = match (local, time.and_then(|t| t.offset_minutes)) {
        (None, _) => String::new(),
        (Some(local), None) => {
            format!(" xmlns:exif=\"http://ns.adobe.com/exif/1.0/\" exif:DateTimeOriginal=\"{local}\"")
        }
        (Some(local), Some(minutes)) => {
            let (sign, m) = (if minutes < 0 { '-' } else { '+' }, minutes.unsigned_abs());
            format!(
                " xmlns:exif=\"http://ns.adobe.com/exif/1.0/\" exif:DateTimeOriginal=\"{local}{sign}{:02}:{:02}\"",
                m / 60,
                m % 60
            )
        }
    };
    format!(
        "<rdf:Description rdf:about=\"\" xmlns:photolib=\"{NAMESPACE}\" \
         xmlns:xmpMM=\"http://ns.adobe.com/xap/1.0/mm/\" \
         xmlns:stRef=\"http://ns.adobe.com/xap/1.0/sType/ResourceRef#\"{date} photolib:recipe=\"{}\"{}>\
         <xmpMM:DerivedFrom rdf:parseType=\"Resource\"><stRef:documentID>blake3:{hash}</stRef:documentID>\
         </xmpMM:DerivedFrom></rdf:Description>",
        STANDARD.encode(recipe),
        provenance.unwrap_or_default(),
    )
}

/// A transform of the image as stored: a mirror left to right if `mirror`, then `turns` clockwise quarter turns.
#[derive(Clone, Copy, PartialEq, Eq)]
struct Turn {
    mirror: bool,
    turns: u32,
}

/// EXIF's orientations 1 to 8.
const ORIENTATIONS: [Turn; 8] = [
    Turn {
        mirror: false,
        turns: 0,
    },
    Turn { mirror: true, turns: 0 },
    Turn {
        mirror: false,
        turns: 2,
    },
    Turn { mirror: true, turns: 2 },
    Turn { mirror: true, turns: 3 },
    Turn {
        mirror: false,
        turns: 1,
    },
    Turn { mirror: true, turns: 1 },
    Turn {
        mirror: false,
        turns: 3,
    },
];

impl Turn {
    fn exif(orientation: u32) -> Self {
        let at = usize::try_from(orientation.saturating_sub(1)).unwrap_or(0);
        ORIENTATIONS.get(at).copied().unwrap_or(ORIENTATIONS[0])
    }

    fn exif_value(self) -> u16 {
        (1..).zip(ORIENTATIONS).find(|&(_, t)| t == self).map_or(1, |(o, _)| o)
    }

    /// Develop's geometry, quarter turns and then a mirror: the mirror first, then as many turns the other way.
    fn develop(quarter_turns: u32, flip: bool) -> Self {
        let turns = quarter_turns % 4;
        Self {
            mirror: flip,
            turns: if flip { turns.wrapping_neg() % 4 } else { turns },
        }
    }

    /// This transform after `first`.
    fn after(self, first: Self) -> Self {
        let turns = if self.mirror {
            first.turns.wrapping_neg()
        } else {
            first.turns
        };
        Self {
            mirror: self.mirror != first.mirror,
            turns: self.turns.wrapping_add(turns) % 4,
        }
    }

    fn inverse(self) -> Self {
        Self {
            mirror: self.mirror,
            turns: if self.mirror {
                self.turns
            } else {
                self.turns.wrapping_neg() % 4
            },
        }
    }

    /// The size of an image of `width` × `height` once transformed.
    fn size(self, width: usize, height: usize) -> (usize, usize) {
        if self.turns % 2 == 1 {
            (height, width)
        } else {
            (width, height)
        }
    }

    /// Where the rectangle with corners (x0, y0) and (x1, y1) of an image of `size` goes when it is transformed.
    fn rect(
        self,
        (x0, y0, x1, y1): (usize, usize, usize, usize),
        size: (usize, usize),
    ) -> (usize, usize, usize, usize) {
        let point = |mut x: usize, mut y: usize| {
            let (mut w, mut h) = size;
            if self.mirror {
                x = w.saturating_sub(x);
            }
            for _ in 0..self.turns {
                (x, y) = (h.saturating_sub(y), x);
                (w, h) = (h, w);
            }
            (x, y)
        };
        let ((ax, ay), (bx, by)) = (point(x0, y0), point(x1, y1));
        (ax.min(bx), ay.min(by), ax.max(bx), ay.max(by))
    }
}
