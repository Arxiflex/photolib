//! Face boxes against edits (ADR-0389): boxes are kept relative to the upright original, and MapFaces moves them to a
//! copy that was turned, mirrored or cropped, and back. The pixel tests render the real editor (Develop) over a
//! picture with a marked face and find the marks again.

#![allow(
    clippy::cast_precision_loss,
    clippy::cast_sign_loss,
    reason = "pixel positions of a 64 x 40 picture"
)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode::InvalidRequest, CallResponse, Develop, DevelopRequest, DevelopResponse, Face, Image,
    MapFacesRequest, MapFacesResponse, Method, Rect, call_response,
};
use prost::Message;

fn ask<Q: Message, R: Message + Default>(method: Method, request: &Q) -> Result<R, CallError> {
    let answer = CallResponse::decode(call(method as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(R::decode(r.as_slice()).unwrap()),
        call_response::Result::Error(e) => Err(e),
    }
}

fn edit(quarter_turns: u32, flip: bool, crop: Option<(u32, u32, u32, u32)>) -> Develop {
    Develop {
        quarter_turns,
        flip,
        crop: crop.map(|(x, y, width, height)| Rect { x, y, width, height }),
        ..Default::default()
    }
}

fn map(
    faces: &[Face],
    size: (u32, u32),
    edit: Develop,
    to_original: bool,
) -> Result<(Vec<Face>, Vec<bool>), CallError> {
    let request = MapFacesRequest {
        faces: faces.to_vec(),
        width: size.0,
        height: size.1,
        edit: Some(edit),
        to_original,
    };
    ask::<_, MapFacesResponse>(Method::MapFaces, &request).map(|r| (r.faces, r.visible))
}

fn face(x: f32, y: f32, width: f32, height: f32) -> Face {
    Face {
        x,
        y,
        width,
        height,
        landmarks: vec![],
        score: 0.9,
    }
}

fn close(a: f32, b: f32) -> bool {
    (a - b).abs() < 1e-5
}

fn same(a: &Face, b: &Face) -> bool {
    [a.x - b.x, a.y - b.y, a.width - b.width, a.height - b.height]
        .iter()
        .all(|d| d.abs() < 1e-5)
        && a.landmarks.len() == b.landmarks.len()
        && a.landmarks.iter().zip(&b.landmarks).all(|(p, q)| close(*p, *q))
        && close(a.score, b.score)
}

#[test]
fn a_quarter_turn_moves_a_box_with_the_picture() {
    // 100 × 50; the box is (10, 10) to (30, 30). A clockwise quarter turn makes the picture 50 × 100 and the box's
    // corners (40, 10) and (20, 30): the top left corner goes to the top right.
    let (faces, visible) = map(&[face(0.1, 0.2, 0.2, 0.4)], (100, 50), edit(1, false, None), false).unwrap();
    assert_eq!(visible, [true]);
    assert!(same(&faces[0], &face(0.4, 0.1, 0.4, 0.2)), "{:?}", faces[0]);
    // Twice is a half turn: (90, 40) and (70, 20) of the 100 × 50.
    let (faces, _) = map(&[face(0.1, 0.2, 0.2, 0.4)], (100, 50), edit(2, false, None), false).unwrap();
    assert!(same(&faces[0], &face(0.7, 0.4, 0.2, 0.4)), "{:?}", faces[0]);
    // Four are none, and 5 is one.
    let (faces, _) = map(&[face(0.1, 0.2, 0.2, 0.4)], (100, 50), edit(5, false, None), false).unwrap();
    assert!(same(&faces[0], &face(0.4, 0.1, 0.4, 0.2)), "{:?}", faces[0]);
}

#[test]
fn a_mirror_moves_a_box_across_and_swaps_the_sides_of_the_landmarks() {
    let mut original = face(0.1, 0.2, 0.2, 0.4);
    // right eye, left eye, nose, right mouth corner, left mouth corner
    original.landmarks = vec![0.12, 0.3, 0.18, 0.3, 0.15, 0.4, 0.13, 0.5, 0.17, 0.5];
    let (faces, _) = map(std::slice::from_ref(&original), (100, 50), edit(0, true, None), false).unwrap();
    let mirrored = &faces[0];
    assert!(
        close(mirrored.x, 0.7) && close(mirrored.y, 0.2) && close(mirrored.width, 0.2),
        "{mirrored:?}"
    );
    // The eye on the picture's left is the first, as a detector lists them on the mirrored picture: the old left eye.
    let expected = [0.82, 0.3, 0.88, 0.3, 0.85, 0.4, 0.83, 0.5, 0.87, 0.5];
    assert!(
        mirrored.landmarks.iter().zip(&expected).all(|(a, b)| close(*a, *b)),
        "{:?}",
        mirrored.landmarks
    );
}

#[test]
fn a_crop_moves_the_origin_and_resizes_and_a_face_it_cuts_in_half_or_more_is_gone() {
    let original = face(0.1, 0.2, 0.2, 0.4);
    // The box (10, 10) to (30, 30) in the crop (10, 10) of 50 × 25: (0, 0) to (20, 20).
    let (faces, visible) = map(
        std::slice::from_ref(&original),
        (100, 50),
        edit(0, false, Some((10, 10, 50, 25))),
        false,
    )
    .unwrap();
    assert_eq!(visible, [true]);
    assert!(same(&faces[0], &face(0.0, 0.0, 0.4, 0.8)), "{:?}", faces[0]);
    // The crop from x = 20 keeps half of the box's width (10 of 20): still visible, and clipped to what shows.
    let (faces, visible) = map(
        std::slice::from_ref(&original),
        (100, 50),
        edit(0, false, Some((20, 0, 80, 50))),
        false,
    )
    .unwrap();
    assert_eq!(visible, [true]);
    assert!(same(&faces[0], &face(0.0, 0.2, 0.125, 0.4)), "{:?}", faces[0]);
    // From x = 21 less than half stays.
    let (_, visible) = map(
        std::slice::from_ref(&original),
        (100, 50),
        edit(0, false, Some((21, 0, 79, 50))),
        false,
    )
    .unwrap();
    assert_eq!(visible, [false]);
    // Wholly outside: not visible, and its box is empty.
    let (faces, visible) = map(
        std::slice::from_ref(&original),
        (100, 50),
        edit(0, false, Some((60, 0, 40, 50))),
        false,
    )
    .unwrap();
    assert_eq!((visible, faces[0].width, faces[0].height), (vec![false], 0.0, 0.0));
}

#[test]
fn faces_go_back_to_the_original_by_the_same_edit() {
    let mut original = face(0.31, 0.22, 0.17, 0.28);
    original.landmarks = vec![0.35, 0.3, 0.43, 0.3, 0.39, 0.37, 0.36, 0.43, 0.42, 0.43];
    for turns in 0..4 {
        for flip in [false, true] {
            // The crop is in pixels of the turned picture: 100 × 50, or 50 × 100 turned an odd number of times.
            let crop = if turns % 2 == 1 { (8, 4, 38, 90) } else { (8, 4, 70, 40) };
            let there = edit(turns, flip, Some(crop));
            let (copy, visible) = map(std::slice::from_ref(&original), (100, 50), there.clone(), false).unwrap();
            assert_eq!(visible, [true], "turns {turns}, flip {flip}");
            let (back, visible) = map(&copy, (100, 50), there, true).unwrap();
            assert_eq!(visible, [true]);
            assert!(same(&back[0], &original), "turns {turns}, flip {flip}: {:?}", back[0]);
        }
    }
}

#[test]
fn an_edit_that_does_not_fit_the_picture_names_its_field() {
    let field = |error: CallError| {
        assert_eq!(error.code(), InvalidRequest);
        error.params.get("field").cloned()
    };
    let one = [face(0.1, 0.1, 0.1, 0.1)];
    assert_eq!(
        field(map(&one, (100, 50), edit(0, false, Some((60, 0, 50, 50))), false).unwrap_err()).as_deref(),
        Some("edit")
    );
    // 100 × 50 turned once is 50 × 100: a crop 60 wide does not fit.
    assert_eq!(
        field(map(&one, (100, 50), edit(1, false, Some((0, 0, 60, 10))), false).unwrap_err()).as_deref(),
        Some("edit")
    );
    assert_eq!(
        field(map(&one, (0, 50), edit(0, false, None), false).unwrap_err()).as_deref(),
        Some("width")
    );
    assert_eq!(
        field(map(&one, (100, 0), edit(0, false, None), false).unwrap_err()).as_deref(),
        Some("height")
    );
    let nan = [face(f32::NAN, 0.0, 0.1, 0.1)];
    assert_eq!(
        field(map(&nan, (100, 50), edit(0, false, None), false).unwrap_err()).as_deref(),
        Some("faces")
    );
    let odd = Face {
        landmarks: vec![0.5; 3],
        ..face(0.0, 0.0, 0.1, 0.1)
    };
    assert_eq!(
        field(map(&[odd], (100, 50), edit(0, false, None), false).unwrap_err()).as_deref(),
        Some("faces")
    );
    // Nothing to move is nothing moved; an empty crop is the whole picture.
    assert_eq!(map(&[], (100, 50), edit(1, true, None), false).unwrap().0.len(), 0);
    let (faces, _) = map(&one, (100, 50), edit(0, false, Some((0, 0, 0, 0))), false).unwrap();
    assert!(same(&faces[0], &one[0]));
}

fn develop(edit: Develop, image: Image) -> Image {
    let request = DevelopRequest {
        develop: Some(edit),
        image: Some(image),
        ..Default::default()
    };
    ask::<_, DevelopResponse>(Method::Develop, &request)
        .unwrap()
        .image
        .unwrap()
}

/// A dark 64 × 40 picture with a bright face box from (12, 6) to (30, 30) and a dot of its own colour at each of five
/// landmarks inside it, colour index 0 to 4.
fn marked_picture() -> (Image, Face) {
    let landmark_pixels = [(17u32, 13u32), (25, 13), (21, 19), (18, 25), (24, 25)];
    let mut rgba = Vec::new();
    for y in 0..40u32 {
        for x in 0..64u32 {
            let dot = landmark_pixels.iter().position(|&p| p == (x, y));
            let in_box = (12..30).contains(&x) && (6..30).contains(&y);
            let rgb = match (dot, in_box) {
                (Some(i), _) => [255, 0, 10 + 40 * i as u8],
                (None, true) => [250, 250, 250],
                (None, false) => [5, 5, 5],
            };
            rgba.extend([rgb[0], rgb[1], rgb[2], 255]);
        }
    }
    // The dots are at pixel centres: continuous (x + 0.5, y + 0.5).
    let landmarks = landmark_pixels
        .iter()
        .flat_map(|&(x, y)| [(x as f32 + 0.5) / 64.0, (y as f32 + 0.5) / 40.0])
        .collect();
    let face = Face {
        x: 12.0 / 64.0,
        y: 6.0 / 40.0,
        width: 18.0 / 64.0,
        height: 24.0 / 40.0,
        landmarks,
        score: 0.9,
    };
    (
        Image {
            width: 64,
            height: 40,
            rgba,
        },
        face,
    )
}

/// The box of the bright pixels of an image in fractions, and the continuous position of each dot, by colour index.
fn find(image: &Image) -> (Face, [Option<(f32, f32)>; 5]) {
    let (mut left, mut top, mut right, mut bottom) = (u32::MAX, u32::MAX, 0, 0);
    let mut dots = [None; 5];
    for (i, p) in image.rgba.chunks(4).enumerate() {
        let (x, y) = (i as u32 % image.width, i as u32 / image.width);
        if p[0] == 255 && p[1] == 0 {
            let n = usize::from((p[2] - 10) / 40);
            dots[n] = Some((x as f32 + 0.5, y as f32 + 0.5));
        }
        if p[0] > 200 {
            left = left.min(x);
            top = top.min(y);
            right = right.max(x + 1);
            bottom = bottom.max(y + 1);
        }
    }
    let (w, h) = (image.width as f32, image.height as f32);
    let face = face(
        left as f32 / w,
        top as f32 / h,
        (right - left) as f32 / w,
        (bottom - top) as f32 / h,
    );
    (face, dots)
}

/// What the editor shows of `picture` after `edit`, found again: the box of the bright pixels and the dots.
fn shown(picture: &Image, edit: &Develop) -> (Image, Face, [Option<(f32, f32)>; 5]) {
    let edited = develop(edit.clone(), picture.clone());
    let (found, dots) = find(&edited);
    (edited, found, dots)
}

/// The size of the 64 × 40 picture after `turns` quarter turns.
fn turned(turns: u32) -> (u32, u32) {
    if turns.is_multiple_of(2) { (64, 40) } else { (40, 64) }
}

/// The face's box in pixels of the turned and mirrored picture: `(x, y, width, height)`.
fn turned_box(original: &Face, turns: u32, flip: bool) -> (u32, u32, u32, u32) {
    let size = turned(turns);
    let (faces, _) = map(std::slice::from_ref(original), (64, 40), edit(turns, flip, None), false).unwrap();
    let f = &faces[0];
    let px = |v: f32, side: u32| (v * side as f32).round() as u32;
    (
        px(f.x, size.0),
        px(f.y, size.1),
        px(f.width, size.0),
        px(f.height, size.1),
    )
}

fn without_landmarks(f: &Face) -> Face {
    Face {
        landmarks: vec![],
        score: 0.0,
        ..f.clone()
    }
}

#[test]
fn the_boxes_and_landmarks_land_where_the_editor_puts_the_face() {
    let (picture, original) = marked_picture();
    let mut cases = 0;
    for turns in 0..4 {
        for flip in [false, true] {
            let (bx, by, bw, bh) = turned_box(&original, turns, flip);
            let (side_w, side_h) = turned(turns);
            let (left, top) = (bx.saturating_sub(3), by.saturating_sub(3));
            let loose = (left, top, (bw + 6).min(side_w - left), (bh + 6).min(side_h - top));
            for crop in [None, Some(loose), Some((bx, by, bw, bh))] {
                let edit = edit(turns, flip, crop);
                let (edited, found, dots) = shown(&picture, &edit);
                let (mapped, visible) = map(std::slice::from_ref(&original), (64, 40), edit, false).unwrap();
                let name = format!("turns {turns}, flip {flip}, crop {crop:?}");
                assert_eq!(visible, [true], "{name}");
                let m = &mapped[0];
                assert!(
                    same(&without_landmarks(&found), &without_landmarks(m)),
                    "{name}: the editor shows {found:?}, mapped {m:?}"
                );
                // The landmark list is in the order a detector gives them on the edited picture: a mirror swaps the
                // eyes and the mouth corners. Dot i of the original is list entry `order[i]`.
                let order = if flip { [1, 0, 2, 4, 3] } else { [0, 1, 2, 3, 4] };
                for (i, dot) in dots.iter().enumerate() {
                    let (dx, dy) = dot.unwrap_or_else(|| panic!("{name}: dot {i} lost"));
                    let k = order[i];
                    let (mx, my) = (
                        m.landmarks[2 * k] * edited.width as f32,
                        m.landmarks[2 * k + 1] * edited.height as f32,
                    );
                    assert!(
                        (mx - dx).abs() < 1e-3 && (my - dy).abs() < 1e-3,
                        "{name}: dot {i} is at ({dx}, {dy}), mapped ({mx}, {my})"
                    );
                }
                cases += 1;
            }
        }
    }
    assert_eq!(cases, 24);
}

#[test]
fn a_crop_that_cuts_the_face_clips_its_box_as_the_editor_clips_the_picture() {
    let (picture, original) = marked_picture();
    for turns in 0..4 {
        for flip in [false, true] {
            let (bx, by, _, bh) = turned_box(&original, turns, flip);
            let (side_w, side_h) = turned(turns);
            // Four pixels off the box's left side, and a margin of two above and below it.
            let top = by.saturating_sub(2);
            let crop = (bx + 4, top, side_w - (bx + 4), (bh + 4).min(side_h - top));
            let edit = edit(turns, flip, Some(crop));
            let (_, found, _) = shown(&picture, &edit);
            let (mapped, visible) = map(std::slice::from_ref(&original), (64, 40), edit, false).unwrap();
            let name = format!("turns {turns}, flip {flip}, crop {crop:?}");
            assert_eq!(visible, [true], "{name}: {:?}", mapped[0]);
            assert!(
                same(&without_landmarks(&found), &without_landmarks(&mapped[0])),
                "{name}: the editor shows {found:?}, mapped {:?}",
                mapped[0]
            );
        }
    }
}
