//! The geometry steps of a recipe composed into one: quarter turns, a mirror and a crop of the turned and mirrored
//! image, which is what `Develop` does. Rectangles are fractions of the image and stay axis-aligned, since the steps
//! only turn by quarter turns; they are f64 so that long chains of steps lose nothing a pixel could show.

// Unfused arithmetic on purpose, so that native and WebAssembly builds agree bit for bit, and casts of values clamped to
// a picture's size first.
#![allow(clippy::suboptimal_flops, clippy::cast_possible_truncation, clippy::cast_sign_loss)]

use crate::proto::kernel::v1::{Develop, Rect};

/// A rectangle as `[x, y, width, height]`, fractions of an image.
pub(crate) type Frac = [f64; 4];

const FULL: Frac = [0.0, 0.0, 1.0, 1.0];

/// What the steps so far do: turn clockwise `turns` quarter turns, mirror left to right if `mirror`, then keep `crop`
/// of that image.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Geometry {
    turns: u32,
    mirror: bool,
    crop: Frac,
}

/// `r` turned a quarter turn clockwise with the image: the top left corner goes to the top right.
fn rotate(r: Frac) -> Frac {
    [1.0 - (r[1] + r[3]), r[0], r[3], r[2]]
}

/// `r` mirrored left to right with the image.
fn mirrored(r: Frac) -> Frac {
    [1.0 - (r[0] + r[2]), r[1], r[2], r[3]]
}

impl Geometry {
    pub(crate) const IDENTITY: Self = Self {
        turns: 0,
        mirror: false,
        crop: FULL,
    };

    /// After `quarter_turns` more turns clockwise. A turn after a mirror is the opposite turn before it.
    pub(crate) fn turn(self, quarter_turns: u32) -> Self {
        let q = quarter_turns % 4;
        let by = if self.mirror { 4_u32.saturating_sub(q) } else { q };
        let turns = self.turns.wrapping_add(by) % 4;
        let crop = (0..q).fold(self.crop, |r, _| rotate(r));
        Self { turns, crop, ..self }
    }

    /// After a mirror left to right, or top to bottom (a half turn and a mirror left to right).
    pub(crate) fn flip(self, vertical: bool) -> Self {
        let this = if vertical { self.turn(2) } else { self };
        Self {
            mirror: !this.mirror,
            crop: mirrored(this.crop),
            ..this
        }
    }

    /// After keeping `part`, fractions of the image as it is now.
    pub(crate) fn crop(self, part: Frac) -> Self {
        let c = self.crop;
        Self {
            crop: [
                c[0] + part[0] * c[2],
                c[1] + part[1] * c[3],
                part[2] * c[2],
                part[3] * c[3],
            ],
            ..self
        }
    }

    /// Where `r`, a rectangle of the original, is in the edited image (unclipped).
    pub(crate) fn forward(self, r: Frac) -> Frac {
        let turned = (0..self.turns).fold(r, |r, _| rotate(r));
        let r = if self.mirror { mirrored(turned) } else { turned };
        let c = self.crop;
        [(r[0] - c[0]) / c[2], (r[1] - c[1]) / c[3], r[2] / c[2], r[3] / c[3]]
    }

    /// Where `r`, a rectangle of the edited image, is in the original.
    pub(crate) fn backward(self, r: Frac) -> Frac {
        let c = self.crop;
        let r = [c[0] + r[0] * c[2], c[1] + r[1] * c[3], r[2] * c[2], r[3] * c[3]];
        let r = if self.mirror { mirrored(r) } else { r };
        (0..4_u32.saturating_sub(self.turns) % 4).fold(r, |r, _| rotate(r))
    }

    /// The size of the image once turned.
    fn turned(self, (w, h): (u32, u32)) -> (u32, u32) {
        if self.turns % 2 == 1 { (h, w) } else { (w, h) }
    }

    /// The crop in pixels of the turned image of `size`; none when it leaves nothing.
    pub(crate) fn pixels(self, size: (u32, u32)) -> Option<Rect> {
        let (fw, fh) = self.turned(size);
        let span = |at: f64, len: f64, full: u32| {
            let start = (at * f64::from(full)).round().clamp(0.0, f64::from(full));
            let end = ((at + len) * f64::from(full)).round().clamp(0.0, f64::from(full));
            (end > start).then_some((start as u32, (end - start) as u32))
        };
        let (x, width) = span(self.crop[0], self.crop[2], fw)?;
        let (y, height) = span(self.crop[1], self.crop[3], fh)?;
        Some(Rect { x, y, width, height })
    }

    /// The size of the edited image.
    pub(crate) fn output_size(self, size: (u32, u32)) -> (u32, u32) {
        self.pixels(size)
            .map_or_else(|| self.turned(size), |r| (r.width, r.height))
    }

    /// Whether the image is left as it is: for a size, to the pixel.
    pub(crate) fn is_identity(self, size: Option<(u32, u32)>) -> bool {
        if self.turns != 0 || self.mirror {
            return false;
        }
        match size {
            Some(size) => self.output_size(size) == size && self.pixels(size).is_some_and(|r| r.x == 0 && r.y == 0),
            None => self.crop.iter().zip(FULL).all(|(a, b)| (a - b).abs() < 1e-9),
        }
    }

    /// The geometry as a `Develop` has it; its crop only for a size, and none when it keeps the whole image.
    pub(crate) fn develop(self, size: Option<(u32, u32)>) -> Develop {
        let crop = size.and_then(|s| {
            let r = self.pixels(s)?;
            let (fw, fh) = self.turned(s);
            (r.width != fw || r.height != fh).then_some(r)
        });
        Develop {
            quarter_turns: self.turns,
            flip: self.mirror,
            crop,
            ..Default::default()
        }
    }
}
