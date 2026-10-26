//! Faces on real photographs (design 09 §7, ADR-0389): YuNet and SFace through the ML role's pool, with the kernel's
//! preprocessing and decoding, held to what OpenCV's `FaceDetectorYN` and `FaceRecognizerSF` make of the same pictures.
//! The photographs are public-domain NASA portraits pinned in `tools/ml/artefacts.json` (never committed).
#![allow(
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "pixel positions of pictures a few thousand pixels across"
)]

use photolib_kernel::proto::kernel::v1::{
    CallResponse, Develop, DevelopRequest, DevelopResponse, Image, MapFacesRequest, MapFacesResponse, Method, Rect,
    call_response,
};
use photolib_ml::faces::{self, Found, Models, Picture};
use photolib_ml::{Ort, Pool, rss, self_test, testing};
use photolib_models::Model;
use prost::Message;

struct Raster {
    width: u32,
    height: u32,
    rgba: Vec<u8>,
}

impl Raster {
    fn picture(&self) -> Picture<'_> {
        Picture {
            width: self.width,
            height: self.height,
            rgba: &self.rgba,
        }
    }
}

fn photo(name: &str) -> Raster {
    let image = image::open(testing::photo(name)).unwrap().to_rgba8();
    Raster {
        width: image.width(),
        height: image.height(),
        rgba: image.into_raw(),
    }
}

/// The two face models on ONNX Runtime's CPU, as the ML role would run them.
fn with_pool<R>(run: impl FnOnce(&Pool<'_>, &Models) -> R) -> R {
    let (library, dir, models) = testing::onnx();
    let ort = Ort::load(&library).unwrap();
    let reports = self_test(ort, dir.path(), &models);
    let pool = Pool::new(ort, dir.path(), &reports, photolib_ml::MEMORY, rss);
    let by = |id: &str| -> &Model { models.iter().find(|m| m.id == id).unwrap() };
    run(&pool, &Models::new(by("yunet"), by("sface")).unwrap())
}

/// Intersection over union of two boxes `(x, y, width, height)`.
fn iou(a: [f32; 4], b: [f32; 4]) -> f32 {
    let width = (a[0] + a[2]).min(b[0] + b[2]) - a[0].max(b[0]);
    let height = (a[1] + a[3]).min(b[1] + b[3]) - a[1].max(b[1]);
    let both = width.max(0.0) * height.max(0.0);
    both / (a[2].mul_add(a[3], b[2] * b[3]) - both)
}

fn boxed(found: &Found) -> [f32; 4] {
    [found.face.x, found.face.y, found.face.width, found.face.height]
}

fn dot(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

#[test]
fn sface_describes_the_same_person_alike_and_other_people_unlike() {
    let (a, b, magnus, crew) = (
        photo("face-photo-armstrong-a"),
        photo("face-photo-armstrong-b"),
        photo("face-photo-magnus"),
        photo("face-photo-crew"),
    );
    with_pool(|pool, models| {
        let one = |p: &Raster| {
            let found = faces::find(pool, models, &p.picture()).unwrap();
            assert_eq!(found.len(), 1);
            found.into_iter().next().unwrap()
        };
        let (a, b, magnus) = (one(&a), one(&b), one(&magnus));
        assert_eq!(a.embedding.len(), models.dim());
        assert!((dot(&a.embedding, &a.embedding) - 1.0).abs() < 1e-4, "a unit vector");
        // OpenCV's FaceRecognizerSF on the same faces: 0.621 for Armstrong twice, 0.107 and 0.150 against Magnus.
        // Its own threshold for one person is 0.363.
        let same = dot(&a.embedding, &b.embedding);
        assert!((0.5..0.75).contains(&same), "the same person: {same}");
        for other in [&magnus] {
            for known in [&a, &b] {
                let different = dot(&known.embedding, &other.embedding);
                assert!(different < 0.3, "different people: {different}");
            }
        }
        let group = faces::find(pool, models, &crew.picture()).unwrap();
        assert!(group.len() >= 3, "{} faces of the crew", group.len());
        for (i, x) in group.iter().enumerate() {
            let [fx, fy, fw, fh] = boxed(x);
            assert!(
                fx >= 0.0 && fy >= 0.0 && fx + fw <= 1.0001 && fy + fh <= 1.0001,
                "{:?}",
                x.face
            );
            assert_eq!(x.face.landmarks.len(), 10);
            for y in &group[i + 1..] {
                assert!(dot(&x.embedding, &y.embedding) < 0.3, "two of the crew");
            }
        }
    });
}

/// The picture as the editor's geometry shows it: turned clockwise, mirrored, then cropped.
fn edited(p: &Raster, quarter_turns: u32, flip: bool, crop: Option<(u32, u32, u32, u32)>) -> (Raster, Develop) {
    let edit = Develop {
        quarter_turns,
        flip,
        crop: crop.map(|(x, y, width, height)| Rect { x, y, width, height }),
        ..Default::default()
    };
    let request = DevelopRequest {
        develop: Some(edit.clone()),
        image: Some(Image {
            width: p.width,
            height: p.height,
            rgba: p.rgba.clone(),
        }),
        ..Default::default()
    };
    let answer =
        CallResponse::decode(photolib_kernel::call(Method::Develop as u32, &request.encode_to_vec()).as_slice());
    let Some(call_response::Result::Response(bytes)) = answer.unwrap().result else {
        panic!("Develop refused");
    };
    let image = DevelopResponse::decode(bytes.as_slice()).unwrap().image.unwrap();
    let rgba = Raster {
        width: image.width,
        height: image.height,
        rgba: image.rgba,
    };
    (rgba, edit)
}

#[test]
fn boxes_mapped_through_an_edit_are_where_yunet_finds_the_face_of_the_edited_picture() {
    let portrait = photo("face-photo-armstrong-a");
    with_pool(|pool, models| {
        let original = faces::find(pool, models, &portrait.picture()).unwrap();
        assert_eq!(original.len(), 1);
        let [x, y, w, h] = boxed(&original[0]);
        let (px, py, pw, ph) = (
            x * portrait.width as f32,
            y * portrait.height as f32,
            w * portrait.width as f32,
            h * portrait.height as f32,
        );
        // A crop about a third larger than the face, and one that cuts away the left fifth of the picture.
        let around = (
            (px - pw / 3.0) as u32,
            (py - ph / 3.0) as u32,
            (pw * 5.0 / 3.0) as u32,
            (ph * 5.0 / 3.0) as u32,
        );
        let side = (portrait.width / 5, 0, portrait.width * 4 / 5, portrait.height);
        let mut seen = 0;
        for (turns, flip, crop) in [
            (0, false, Some(around)),
            (0, false, Some(side)),
            (0, true, None),
            (0, true, Some(around)),
            (1, false, None),
            (2, false, None),
            (3, true, Some((0, 0, portrait.height, portrait.width * 4 / 5))),
        ] {
            let (picture, edit) = edited(&portrait, turns, flip, crop);
            let mapped = MapFacesRequest {
                faces: vec![original[0].face.clone()],
                width: portrait.width,
                height: portrait.height,
                edit: Some(edit),
                to_original: false,
            };
            let answer = CallResponse::decode(
                photolib_kernel::call(Method::MapFaces as u32, &mapped.encode_to_vec()).as_slice(),
            )
            .unwrap();
            let Some(call_response::Result::Response(bytes)) = answer.result else {
                panic!("MapFaces refused");
            };
            let mapped = MapFacesResponse::decode(bytes.as_slice()).unwrap();
            let expected = [
                mapped.faces[0].x,
                mapped.faces[0].y,
                mapped.faces[0].width,
                mapped.faces[0].height,
            ];
            let found = faces::find(pool, models, &picture.picture()).unwrap();
            let best = found.iter().map(|f| iou(boxed(f), expected)).fold(0.0, f32::max);
            // YuNet reads upright faces: a face turned on its side or upside down it may not find at all (the
            // kernel's tests of the same arithmetic place marked pixels), and draws a different box round one it finds.
            let upright = turns == 0;
            assert!(
                !upright || !found.is_empty(),
                "turns {turns}, flip {flip}, crop {crop:?}: no face found"
            );
            assert!(
                found.is_empty() || best > if upright { 0.8 } else { 0.6 },
                "turns {turns}, flip {flip}, crop {crop:?}: best IoU {best}, found {:?} expected {expected:?}",
                found.iter().map(boxed).collect::<Vec<_>>()
            );
            seen += found.len();
        }
        assert!(seen >= 4, "{seen}");
    });
}

#[test]
fn a_picture_without_a_face_has_none() {
    with_pool(|pool, models| {
        // Bars of colour and a flat grey, and a one pixel picture
        let bars = Raster {
            width: 320,
            height: 200,
            rgba: (0..320 * 200u32)
                .flat_map(|i| [(i % 320 / 40 * 32) as u8, (i / 320 / 25 * 32) as u8, 128, 255])
                .collect(),
        };
        let flat = Raster {
            width: 64,
            height: 64,
            rgba: [90, 90, 90, 255].repeat(64 * 64),
        };
        let dot_pixel = Raster {
            width: 1,
            height: 1,
            rgba: vec![0, 0, 0, 255],
        };
        for picture in [&bars, &flat, &dot_pixel] {
            assert_eq!(faces::find(pool, models, &picture.picture()).unwrap(), vec![]);
        }
        let bad = Picture {
            width: 4,
            height: 4,
            rgba: &[0; 3],
        };
        assert!(faces::find(pool, models, &bad).unwrap_err().contains("rgba"));
    });
}

#[test]
fn yunet_finds_the_face_of_a_portrait_where_opencv_does() {
    let portrait = photo("face-photo-armstrong-a");
    with_pool(|pool, models| {
        let found = faces::find(pool, models, &portrait.picture()).unwrap();
        assert_eq!(found.len(), 1, "{found:?}");
        // FaceDetectorYN (OpenCV 5.0) on the same picture at 480 × 640: x, y, width, height as fractions.
        let opencv = [0.2912, 0.141, 0.4017, 0.4312];
        let got = boxed(&found[0]);
        assert!(iou(got, opencv) > 0.9, "{got:?} against {opencv:?}");
        assert!(found[0].face.score > 0.7);
        assert_eq!(found[0].face.landmarks.len(), 10);
    });
}

/// What finding the faces of a photograph costs on the CPU, printed as `faces_perf` lines for the record (ADR-0389), and
/// that the work is the same each time: the faces found, and as many on every run. A wall-clock budget does not belong
/// in a test that a loaded runner runs beside hundreds of others; the perf lane measures time.
#[test]
fn finding_the_faces_of_a_photograph_is_repeatable_and_its_cost_is_reported() {
    let (portrait, crew) = (photo("face-photo-armstrong-a"), photo("face-photo-crew"));
    with_pool(|pool, models| {
        for (name, p, expected) in [("portrait", &portrait, 1), ("crew", &crew, 3)] {
            let mut ms = Vec::new();
            let mut counts = Vec::new();
            for _ in 0..3 {
                let start = std::time::Instant::now();
                counts.push(faces::find(pool, models, &p.picture()).unwrap().len());
                ms.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            println!(
                "faces_perf {name} {}x{} faces={} ms={ms:.1?}",
                p.width, p.height, counts[0]
            );
            assert!(counts.iter().all(|&n| n == counts[0]), "{name}: {counts:?}");
            assert!(counts[0] >= expected, "{name}: {counts:?}");
        }
    });
}
