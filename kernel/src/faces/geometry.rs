//! Faces against edits: boxes are kept relative to the upright original, and an edit that turns, mirrors or crops it
//! moves them with the pixels, by the same arithmetic as `develop`'s geometry (turns clockwise, then the mirror, then
//! the crop in the turned picture).

use crate::invalid_request;
use crate::proto::kernel::v1::{CallError, Face, MapFacesRequest, MapFacesResponse};

/// A face keeps at least this share of its box in the copy to count as in it.
const VISIBLE: f32 = 0.5 - 1e-4;

/// A point in the plane.
type Point = (f64, f64);

/// The edit of a picture of known size.
struct Edit {
    /// The original's size.
    size: Point,
    /// Clockwise quarter turns, 0 to 3.
    turns: u32,
    flip: bool,
    /// The crop, in pixels of the turned and mirrored picture: where it starts and its size.
    crop: (Point, Point),
}

/// A fraction held in f64 while it moves, as the f32 faces keep it.
#[allow(clippy::cast_possible_truncation)] // fractions near 0 to 1 lose only precision beyond f32's
fn single(v: f64) -> f32 {
    v as f32
}

impl Edit {
    /// The size of the picture after the turns.
    fn turned(&self) -> Point {
        if self.turns.is_multiple_of(2) {
            self.size
        } else {
            (self.size.1, self.size.0)
        }
    }

    /// Where the fractions `(u, v)` of the original are, in fractions of the copy.
    fn forward(&self, (u, v): Point) -> Point {
        let (mut x, mut y, mut size) = (u * self.size.0, v * self.size.1, self.size);
        for _ in 0..self.turns {
            (x, y, size) = (size.1 - y, x, (size.1, size.0));
        }
        if self.flip {
            x = size.0 - x;
        }
        ((x - self.crop.0.0) / self.crop.1.0, (y - self.crop.0.1) / self.crop.1.1)
    }

    /// Where the fractions `(a, b)` of the copy are, in fractions of the original.
    fn backward(&self, (a, b): Point) -> Point {
        let mut size = self.turned();
        let mut x = a.mul_add(self.crop.1.0, self.crop.0.0);
        let mut y = b.mul_add(self.crop.1.1, self.crop.0.1);
        if self.flip {
            x = size.0 - x;
        }
        for _ in 0..self.turns {
            (x, y, size) = (y, size.0 - x, (size.1, size.0));
        }
        (x / self.size.0, y / self.size.1)
    }

    fn map(&self, to_original: bool, p: Point) -> Point {
        if to_original { self.backward(p) } else { self.forward(p) }
    }
}

/// Mirroring puts the face's right eye on the picture's right: a detector lists the eye that is on the left first, so
/// the pairs of eyes and of mouth corners change places.
fn swapped(landmarks: &[f32]) -> Vec<f32> {
    let order = [2, 3, 0, 1, 4, 5, 8, 9, 6, 7];
    order.iter().filter_map(|&i| landmarks.get(i).copied()).collect()
}

fn valid(face: &Face) -> bool {
    let finite = [face.x, face.y, face.width, face.height, face.score]
        .iter()
        .chain(&face.landmarks)
        .all(|v| v.is_finite());
    finite && face.width > 0.0 && face.height > 0.0 && (face.landmarks.is_empty() || face.landmarks.len() == 10)
}

/// The edit of a request: its turns, mirror and crop, which must fit the picture.
fn edit_of(request: &MapFacesRequest) -> Result<Edit, CallError> {
    let side = |v: u32, field: &str| {
        u16::try_from(v)
            .ok()
            .filter(|&v| v > 0)
            .map(f64::from)
            .ok_or_else(|| invalid_request(field))
    };
    let size = (side(request.width, "width")?, side(request.height, "height")?);
    let develop = request.edit.clone().unwrap_or_default();
    let mut edit = Edit {
        size,
        turns: develop.quarter_turns % 4,
        flip: develop.flip,
        crop: ((0.0, 0.0), size),
    };
    edit.crop.1 = edit.turned();
    if let Some(c) = develop.crop.filter(|c| c.width > 0 && c.height > 0) {
        let (start, extent) = (
            (f64::from(c.x), f64::from(c.y)),
            (f64::from(c.width), f64::from(c.height)),
        );
        let turned = edit.turned();
        if start.0 + extent.0 > turned.0 || start.1 + extent.1 > turned.1 {
            return Err(invalid_request("edit"));
        }
        edit.crop = (start, extent);
    }
    Ok(edit)
}

/// `face` moved by `edit`, and whether at least half of its box is in the picture it moved to.
fn moved(edit: &Edit, to_original: bool, face: &Face) -> (Face, bool) {
    let to = |[x, y]: [f32; 2]| edit.map(to_original, (f64::from(x), f64::from(y)));
    let (a, b) = (to([face.x, face.y]), to([face.x + face.width, face.y + face.height]));
    let (left, right) = (a.0.min(b.0), a.0.max(b.0));
    let (top, bottom) = (a.1.min(b.1), a.1.max(b.1));
    let mut landmarks: Vec<f32> = face
        .landmarks
        .as_chunks::<2>()
        .0
        .iter()
        .flat_map(|&point| {
            let (x, y) = to(point);
            [single(x), single(y)]
        })
        .collect();
    if edit.flip && !landmarks.is_empty() {
        landmarks = swapped(&landmarks);
    }
    let kept = |x0: f64, y0: f64, x1: f64, y1: f64| Face {
        x: single(x0),
        y: single(y0),
        width: single(x1 - x0),
        height: single(y1 - y0),
        landmarks: landmarks.clone(),
        score: face.score,
    };
    if to_original {
        return (kept(left, top, right, bottom), true);
    }
    // Clipped to the copy; a box wholly outside it is empty, not a sliver along its edge.
    let (clipped_left, clipped_top) = (left.max(0.0), top.max(0.0));
    let clipped_right = right.min(1.0).max(clipped_left);
    let clipped_bottom = bottom.min(1.0).max(clipped_top);
    let shown = (clipped_right - clipped_left) * (clipped_bottom - clipped_top);
    let area = (right - left) * (bottom - top);
    let mut face = kept(clipped_left, clipped_top, clipped_right, clipped_bottom);
    if shown <= 0.0 {
        (face.width, face.height) = (0.0, 0.0);
    }
    (face, single(shown / area) >= VISIBLE)
}

pub(crate) fn map_faces(request: &MapFacesRequest) -> Result<MapFacesResponse, CallError> {
    let edit = edit_of(request)?;
    if !request.faces.iter().all(valid) {
        return Err(invalid_request("faces"));
    }
    let (faces, visible) = request
        .faces
        .iter()
        .map(|face| moved(&edit, request.to_original, face))
        .unzip();
    Ok(MapFacesResponse { faces, visible })
}
