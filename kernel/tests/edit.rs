//! Edited copies of JPEG photos through the kernel's ABI (`METHOD_EDIT_COPY`, ADR-0331), on corpus files.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode, CallResponse, Develop, DevelopRequest, DevelopResponse, EditCopyRequest,
    EditCopyResponse, FileRange, Image, Method, ReadMetadataRequest, ReadMetadataResponse, Rect, call_response,
};
use photolib_kernel::proto::model::v1::{
    CaptureTime, CropOperation, DigitalSourceType, EditRecipe, InpaintOperation, ModelUse, Operation, StoredOutput,
    StoredOutputKind, TurnOperation, operation::Kind,
};
use prost::Message;

fn corpus(path: &str) -> Vec<u8> {
    #[allow(clippy::disallowed_methods)] // a test reads its fixtures
    std::fs::read(format!(
        "{}/../testdata/corpus/files/{path}",
        env!("CARGO_MANIFEST_DIR")
    ))
    .unwrap()
}

fn kernel<R: Message + Default>(method: Method, request: &impl Message) -> Result<R, CallError> {
    let answer = CallResponse::decode(call(method as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(R::decode(r.as_slice()).unwrap()),
        call_response::Result::Error(e) => Err(e),
    }
}

/// A BLAKE3 the host says the original has (the empty input's).
const HASH: &str = "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";

fn edit_copy(original: &[u8], develop: Develop, image: Option<Image>) -> Result<EditCopyResponse, CallError> {
    let request = EditCopyRequest {
        original: original.to_vec(),
        develop: Some(develop),
        image,
        original_blake3: HASH.into(),
        ..Default::default()
    };
    kernel(Method::EditCopy, &request)
}

fn copy(original: &[u8], develop: Develop) -> EditCopyResponse {
    edit_copy(original, develop, None).unwrap()
}

fn metadata(file: &[u8]) -> ReadMetadataResponse {
    let request = ReadMetadataRequest {
        ranges: vec![FileRange {
            offset: 0,
            data: file.to_vec(),
        }],
        size: file.len() as u64,
    };
    kernel(Method::ReadMetadata, &request).unwrap()
}

fn turned(quarter_turns: u32, flip: bool) -> Develop {
    Develop {
        quarter_turns,
        flip,
        ..Default::default()
    }
}

fn cropped(quarter_turns: u32, x: u32, y: u32, width: u32, height: u32) -> Develop {
    Develop {
        crop: Some(Rect { x, y, width, height }),
        ..turned(quarter_turns, false)
    }
}

fn field(error: &CallError) -> (CallErrorCode, &str) {
    (error.code(), error.params["field"].as_str())
}

/// Where the image data starts: the first scan's header.
fn scan(jpeg: &[u8]) -> &[u8] {
    let at = jpeg.windows(2).position(|w| w == [0xff, 0xda]).unwrap();
    &jpeg[at..]
}

/// The pixels of a `width` × `height` grid numbered row by row, as EXIF's orientation `o` shows them (EXIF 2.32,
/// 4.6.4 A: where the stored first row and column are seen), and their size.
fn shown(orientation: u32, width: u32, height: u32) -> (u32, u32, Vec<u32>) {
    let (w, h) = if orientation >= 5 {
        (height, width)
    } else {
        (width, height)
    };
    let pixels = (0..w * h)
        .map(|i| {
            let (x, y) = (i % w, i / w);
            let (sx, sy) = match orientation {
                1 => (x, y),
                2 => (width - 1 - x, y),
                3 => (width - 1 - x, height - 1 - y),
                4 => (x, height - 1 - y),
                5 => (y, x),
                6 => (y, height - 1 - x),
                7 => (width - 1 - y, height - 1 - x),
                _ => (width - 1 - y, x),
            };
            sy * width + sx
        })
        .collect();
    (w, h, pixels)
}

#[test]
fn an_edit_shows_through_the_orientation_it_composes() {
    for o in 1..=8 {
        let (w, h, pixels) = shown(o, 3, 2);
        let rgba: Vec<u8> = pixels.iter().flat_map(|&p| [p as u8, 0, 0, 255]).collect();
        for quarter_turns in 0..4 {
            for flip in [false, true] {
                let request = DevelopRequest {
                    develop: Some(turned(quarter_turns, flip)),
                    image: Some(Image {
                        width: w,
                        height: h,
                        rgba: rgba.clone(),
                    }),
                    ..Default::default()
                };
                let edited: DevelopResponse = kernel(Method::Develop, &request).unwrap();
                let file = if o == 1 {
                    corpus("stills/baseline.jpg")
                } else {
                    corpus(&format!("compound/orientation/orientation-{o}.jpg"))
                };
                let copy = copy(&file, turned(quarter_turns, flip));
                let (cw, ch, want) = shown(metadata(&copy.jpeg).orientation.max(1), 3, 2);
                let image = edited.image.unwrap();
                let got: Vec<u32> = image.rgba.chunks(4).map(|p| u32::from(p[0])).collect();
                assert_eq!(
                    (cw, ch, want),
                    (image.width, image.height, got),
                    "{o} {quarter_turns} {flip}"
                );
                assert!(copy.lossless);
            }
        }
    }
}

#[test]
fn a_turn_keeps_the_image_data_and_every_other_fact() {
    let original = corpus("stills/gps-sydney.jpg");
    let copy = copy(&original, turned(1, false));
    assert!(copy.lossless);
    assert_eq!(scan(&copy.jpeg), scan(&original));
    let (before, after) = (metadata(&original), metadata(&copy.jpeg));
    assert_eq!(after.orientation, 6);
    assert_eq!(
        ReadMetadataResponse {
            orientation: 0,
            ..after.clone()
        },
        ReadMetadataResponse {
            orientation: 0,
            ..before
        }
    );
    assert!(after.location.is_some() && !after.times.is_empty());
}

#[test]
fn a_photo_sphere_s_copy_is_flat_once_its_geometry_changes() {
    for path in ["compound/pano/photosphere.jpg", "compound/pano/photosphere-cropped.jpg"] {
        let original = corpus(path);
        let sphere = metadata(&original).panorama;
        assert!(sphere.is_some(), "{path}");
        assert_eq!(
            metadata(&copy(&original, turned(0, false)).jpeg).panorama,
            sphere,
            "{path}"
        );
        for develop in [
            turned(1, false),
            turned(2, false),
            turned(0, true),
            cropped(0, 0, 0, 1024, 512),
        ] {
            let after = metadata(&copy(&original, develop.clone()).jpeg);
            assert_eq!(after.panorama, None, "{path}: {develop:?}");
        }
    }
}

#[test]
fn a_turn_back_to_upright_sets_orientation_one() {
    let original = corpus("compound/orientation/orientation-6.jpg");
    let after = metadata(&copy(&original, turned(3, false)).jpeg);
    assert_eq!((after.orientation, after.times), (1, metadata(&original).times));
}

#[test]
fn a_crop_keeps_whole_blocks_moving_its_corner_onto_their_grid() {
    let original = corpus("stills/gps-sydney.jpg");
    // 4:2:0, so 16 × 16 blocks: (21, 37) moves to (16, 32) and the far corner stays.
    let copy = copy(&original, cropped(0, 21, 37, 300, 200));
    assert!(copy.lossless);
    let (before, after) = (metadata(&original), metadata(&copy.jpeg));
    assert_eq!((after.width, after.height), (305, 205));
    assert_eq!(
        (after.location, after.times, after.make),
        (before.location, before.times, before.make)
    );
    // Turned a quarter, (10, 20) to (110, 220) is (20, 370) to (220, 470) as stored, whose corner moves to (16, 368).
    let copy = self::copy(&original, cropped(1, 10, 20, 100, 200));
    let after = metadata(&copy.jpeg);
    assert_eq!((after.width, after.height, after.orientation), (204, 102, 6));
}

fn rect(r: &EditCopyResponse) -> Option<(u32, u32, u32, u32)> {
    r.crop.as_ref().map(|c| (c.x, c.y, c.width, c.height))
}

#[test]
fn the_copy_says_which_part_of_the_edited_picture_it_shows() {
    let original = corpus("stills/gps-sydney.jpg");
    // Moved to the block grid: (21, 37) of 300 × 200 shows from (16, 32), 305 × 205.
    assert_eq!(
        rect(&copy(&original, cropped(0, 21, 37, 300, 200))),
        Some((16, 32, 305, 205))
    );
    // Turned and mirrored too: the copy's displayed size is the crop's, and it holds what was asked, at most one
    // block (15 pixels) more on a side.
    for (turns, flip) in [
        (0, false),
        (1, false),
        (2, false),
        (3, false),
        (0, true),
        (1, true),
        (2, true),
        (3, true),
    ] {
        let develop = Develop {
            flip,
            ..cropped(turns, 21, 37, 100, 120)
        };
        let copy = copy(&original, develop);
        let (x, y, w, h) = rect(&copy).unwrap_or_else(|| panic!("turns {turns}, flip {flip}: no crop"));
        let shown = metadata(&copy.jpeg);
        let displayed = if shown.orientation >= 5 {
            (shown.height, shown.width)
        } else {
            (shown.width, shown.height)
        };
        assert_eq!((w, h), displayed, "turns {turns}, flip {flip}");
        let (left, top, right, bottom) = (x, y, x + w, y + h);
        assert!(
            left <= 21 && 21 - left < 16 && top <= 37 && 37 - top < 16,
            "turns {turns}, flip {flip}: {:?}",
            rect(&copy)
        );
        assert!(
            right.abs_diff(121) < 16 && bottom.abs_diff(157) < 16,
            "turns {turns}, flip {flip}: {:?}",
            rect(&copy)
        );
    }
    // Nothing is cropped from a copy that shows the whole picture, and an encoded copy is cropped exactly.
    assert_eq!(rect(&copy(&original, turned(1, true))), None);
    let encoded = Develop {
        exposure: 0.25,
        ..cropped(0, 21, 37, 100, 120)
    };
    let size = metadata(&original);
    let encoded = edit_copy(&original, encoded, Some(gradient(size.width, size.height))).unwrap();
    assert!(!encoded.lossless);
    assert_eq!(rect(&encoded), Some((21, 37, 100, 120)));
}

#[test]
fn an_edit_that_cannot_keep_the_image_data_needs_the_decoded_original() {
    let enhance = Develop {
        exposure: 0.5,
        ..Default::default()
    };
    let error = edit_copy(&corpus("stills/baseline.jpg"), enhance, None).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "image"));
    let progressive = corpus("stills/progressive.jpg");
    let error = edit_copy(&progressive, cropped(0, 0, 0, 10, 10), None).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "image"));
    let wrong = Image {
        width: 1,
        height: 1,
        rgba: vec![0; 4],
    };
    let error = edit_copy(&progressive, cropped(0, 0, 0, 10, 10), Some(wrong)).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "image"));
    // A turn alone keeps even a progressive JPEG's image data.
    assert!(copy(&progressive, turned(2, true)).lossless);
}

#[test]
fn a_bad_original_or_crop_fails() {
    let error = edit_copy(b"not a jpeg", Develop::default(), None).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "original"));
    let error = edit_copy(&corpus("stills/baseline.jpg"), cropped(1, 0, 0, 481, 10), None).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "develop"));
    // The XMP names the original by a BLAKE3 in lowercase hex, nothing else.
    for hash in ["", &HASH[1..], &HASH.to_uppercase(), &format!("{}\"/>", &HASH[3..])] {
        let request = EditCopyRequest {
            original: corpus("stills/baseline.jpg"),
            develop: Some(turned(1, false)),
            original_blake3: hash.into(),
            ..Default::default()
        };
        let error = kernel::<EditCopyResponse>(Method::EditCopy, &request).unwrap_err();
        assert_eq!(
            field(&error),
            (CallErrorCode::InvalidRequest, "original_blake3"),
            "{hash}"
        );
    }
}

/// An image of `width` × `height` whose pixels say where they are.
fn gradient(width: u32, height: u32) -> Image {
    let rgba = (0..width * height)
        .flat_map(|i| {
            [
                (i % width * 255 / width) as u8,
                (i / width * 255 / height) as u8,
                128,
                255,
            ]
        })
        .collect();
    Image { width, height, rgba }
}

/// An ICC profile's segment (APP2) of a profile in `space`: its name, chunk 1 of 1, and a header saying the space.
fn icc(space: [u8; 4]) -> Vec<u8> {
    let mut profile = vec![0; 132];
    profile[..4].copy_from_slice(&132u32.to_be_bytes());
    profile[12..20].copy_from_slice(&[*b"mntr", space].concat());
    profile[36..40].copy_from_slice(b"acsp");
    let body = [b"ICC_PROFILE\0\x01\x01" as &[u8], &profile].concat();
    [&[0xff, 0xe2][..], &(body.len() as u16 + 2).to_be_bytes(), &body].concat()
}

/// `jpeg` with `segment` after its start.
fn with(jpeg: &[u8], segment: &[u8]) -> Vec<u8> {
    [&jpeg[..2], segment, &jpeg[2..]].concat()
}

/// An XMP segment (APP1) of `description`.
fn xmp_segment(description: &str) -> Vec<u8> {
    let body = format!(
        "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF \
         xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">{description}</rdf:RDF></x:xmpmeta>"
    );
    [
        &[0xff, 0xe1][..],
        &(body.len() as u16 + 2).to_be_bytes(),
        body.as_bytes(),
    ]
    .concat()
}

#[test]
fn a_copy_keeps_its_face_regions_while_its_stored_pixels_stay() {
    let face = r#"<rdf:Description xmlns:mwg-rs="http://www.metadataworkinggroup.com/schemas/regions/" xmlns:stArea="http://ns.adobe.com/xmp/sType/Area#"><mwg-rs:Regions rdf:parseType="Resource"><mwg-rs:RegionList><rdf:Bag><rdf:li><rdf:Description mwg-rs:Name="Alice" mwg-rs:Type="Face"><mwg-rs:Area stArea:x="0.5" stArea:y="0.25" stArea:w="0.25" stArea:h="0.125" stArea:unit="normalized"/></rdf:Description></rdf:li></rdf:Bag></mwg-rs:RegionList></mwg-rs:Regions></rdf:Description>"#;
    let original = with(&corpus("stills/baseline.jpg"), &xmp_segment(face));
    assert_eq!(metadata(&original).regions.len(), 1);
    let colours = Develop {
        exposure: 0.25,
        ..Default::default()
    };
    let turned_colours = Develop {
        exposure: 0.25,
        ..turned(1, false)
    };
    for (develop, kept) in [
        (turned(1, false), true),
        (colours, true),
        (cropped(0, 16, 16, 64, 64), false),
        (turned_colours, false),
    ] {
        let copy = edit_copy(&original, develop.clone(), Some(gradient(640, 480))).unwrap();
        assert_eq!(metadata(&copy.jpeg).regions.len(), usize::from(kept), "{develop:?}");
    }
}

#[test]
fn every_copy_keeps_its_original_s_rgb_colour_profile() {
    let (rgb, cmyk) = (icc(*b"RGB "), icc(*b"CMYK"));
    let original = with(&corpus("stills/baseline.jpg"), &rgb);
    let encoded = Develop {
        exposure: 0.25,
        ..turned(1, false)
    };
    for copy in [
        copy(&original, turned(1, true)),
        copy(&original, cropped(0, 16, 16, 64, 64)),
        edit_copy(&original, encoded.clone(), Some(gradient(640, 480))).unwrap(),
    ] {
        let found = copy.jpeg.windows(rgb.len()).filter(|w| *w == rgb).count();
        assert_eq!(found, 1, "lossless {}", copy.lossless);
    }
    // An encoded copy is RGB: a profile of another space would mislead.
    let original = with(&corpus("stills/baseline.jpg"), &cmyk);
    let copy = edit_copy(&original, encoded, Some(gradient(640, 480))).unwrap();
    assert!(!copy.jpeg.windows(11).any(|w| w == b"ICC_PROFILE"));
}

#[test]
fn a_copy_of_a_live_photo_never_pairs_with_its_video() {
    let original = corpus("compound/live/IMG_2002.JPG");
    let before = metadata(&original);
    assert_ne!(before.content_identifier, "");
    // Every copy's EXIF is written the same way: whole and cropped are enough.
    for copy in [
        copy(&original, turned(1, false)),
        copy(&original, cropped(0, 0, 0, 32, 32)),
    ] {
        let after = metadata(&copy.jpeg);
        assert_eq!(
            (after.content_identifier.as_str(), &after.make, &after.times),
            ("", &before.make, &before.times)
        );
    }
}

#[test]
fn an_encoded_copy_is_upright_without_the_stale_thumbnail() {
    let original = corpus("stills/exif-thumbnail.jpg");
    assert!(metadata(&original).preview.is_some());
    let develop = Develop {
        exposure: 0.25,
        ..cropped(1, 0, 0, 480, 320)
    };
    let copy = edit_copy(&original, develop, Some(gradient(640, 480))).unwrap();
    assert!(!copy.lossless);
    let (before, after) = (metadata(&original), metadata(&copy.jpeg));
    assert_eq!((after.width, after.height, after.orientation.max(1)), (480, 320, 1));
    assert_eq!((after.preview, after.times), (None, before.times));
}

#[test]
fn a_still_copy_of_a_motion_photo_or_an_ultra_hdr_jpeg_leaves_out_what_follows_the_image() {
    for path in [
        "compound/motion/PXL_20230330_184138390.MP.jpg",
        "compound/motion/MVIMG_20190215_193501.jpg",
        "hdr/ultra-hdr.jpg",
    ] {
        let original = corpus(path);
        let before = metadata(&original);
        assert!(before.motion_photo.is_some(), "{path}");
        // A turn keeps it whole.
        let turn = copy(&original, turned(1, false)).jpeg;
        let after = metadata(&turn);
        let video = |file: &[u8], m: &ReadMetadataResponse| m.motion_video.map(|v| file[v.offset as usize..].to_vec());
        assert_eq!(after.motion_photo, before.motion_photo, "{path}");
        assert_eq!(video(&turn, &after), video(&original, &before), "{path}");
        let crop = copy(&original, cropped(0, 0, 0, 1024, 768));
        let after = metadata(&crop.jpeg);
        assert_eq!(
            (after.motion_photo, after.motion_video, after.width),
            (None, None, 1024),
            "{path}"
        );
        assert!(crop.jpeg.ends_with(&[0xff, 0xd9]), "{path}");
    }
}

/// The copy's XMP packet.
fn xmp(jpeg: &[u8]) -> String {
    let start = jpeg.windows(10).position(|w| w == b"<x:xmpmeta").unwrap();
    let end = jpeg.windows(12).position(|w| w == b"</x:xmpmeta>").unwrap();
    String::from_utf8(jpeg[start..end].to_vec()).unwrap()
}

#[test]
fn the_copy_records_the_edit_and_the_original_in_its_xmp() {
    let original = corpus("compound/motion/PXL_20230330_184138390.MP.jpg");
    let edit = cropped(3, 8, 8, 64, 64);
    let copy = copy(&original, edit.clone());
    let packet = xmp(&copy.jpeg);
    let recipe = packet
        .split("photolib:recipe=\"")
        .nth(1)
        .unwrap()
        .split('"')
        .next()
        .unwrap();
    assert_eq!(
        Develop::decode(STANDARD.decode(recipe).unwrap().as_slice()).unwrap(),
        edit
    );
    let hash = format!("<stRef:documentID>blake3:{HASH}</stRef:documentID>");
    assert!(packet.contains(&hash) && packet.contains("xmlns:photolib=\"http://ns.photolib.org/1.0/\""));
    assert!(!packet.contains("GCamera:MotionPhoto") && !packet.contains("Container:Directory"));
    // A copy of the copy records only its own edit and original.
    let request = EditCopyRequest {
        original: copy.jpeg,
        develop: Some(turned(1, false)),
        original_blake3: "0".repeat(64),
        ..Default::default()
    };
    let again = xmp(&kernel::<EditCopyResponse>(Method::EditCopy, &request).unwrap().jpeg);
    assert_eq!(again.matches("photolib:recipe=").count(), 1);
    assert_eq!(again.matches("<xmpMM:DerivedFrom").count(), 1);
    assert!(again.contains(&format!("blake3:{}<", "0".repeat(64))));
}

#[test]
fn the_copy_keeps_a_capture_time_its_original_had_only_outside_its_metadata() {
    let original = corpus("stills/mpf-secondary.jpg");
    assert_eq!(metadata(&original).times, vec![]);
    let time = CaptureTime {
        local_datetime: "2021-06-01T09:30:00".into(),
        offset_minutes: Some(-150),
        ..Default::default()
    };
    let request = |original: &[u8]| EditCopyRequest {
        original: original.to_vec(),
        develop: Some(turned(1, false)),
        capture_time: Some(time.clone()),
        original_blake3: HASH.into(),
        ..Default::default()
    };
    let copy: EditCopyResponse = kernel(Method::EditCopy, &request(&original)).unwrap();
    let times = metadata(&copy.jpeg).times;
    assert_eq!(times.len(), 1);
    assert_eq!(
        (times[0].local_datetime.as_str(), times[0].offset_minutes),
        ("2021-06-01T09:30:00", Some(-150))
    );
    // The original's own time wins.
    let dated = corpus("stills/baseline.jpg");
    let copy: EditCopyResponse = kernel(Method::EditCopy, &request(&dated)).unwrap();
    assert_eq!(metadata(&copy.jpeg).times, metadata(&dated).times);
}

#[test]
fn the_decoded_original_comes_as_shown() {
    let original = corpus("compound/orientation/orientation-6.jpg");
    let develop = Develop {
        exposure: 0.25,
        ..turned(1, false)
    };
    let stored = edit_copy(&original, develop.clone(), Some(gradient(640, 480))).unwrap_err();
    assert_eq!(field(&stored), (CallErrorCode::InvalidRequest, "image"));
    let copy = edit_copy(&original, develop, Some(gradient(480, 640))).unwrap();
    let after = metadata(&copy.jpeg);
    assert_eq!((after.width, after.height, after.orientation.max(1)), (640, 480, 1));
}

fn step(id: &str, kind: Kind) -> Operation {
    Operation {
        operation_id: id.into(),
        kind: Some(kind),
        ..Default::default()
    }
}

fn recipe_copy(
    original: &[u8],
    recipe: EditRecipe,
    image: Option<Image>,
    rendered: bool,
) -> Result<EditCopyResponse, CallError> {
    let request = EditCopyRequest {
        original: original.to_vec(),
        recipe: Some(recipe),
        image,
        rendered,
        original_blake3: HASH.into(),
        ..Default::default()
    };
    kernel(Method::EditCopy, &request)
}

fn recipe(operations: Vec<Operation>) -> EditRecipe {
    EditRecipe {
        schema_version: 1,
        operations,
        ..Default::default()
    }
}

/// The attribute `name` of the copy's XMP.
fn attribute(packet: &str, name: &str) -> Option<String> {
    let rest = packet.split(&format!("{name}=\"")).nth(1)?;
    Some(rest.split('"').next()?.to_owned())
}

const HUMAN: &str = "http://cv.iptc.org/newscodes/digitalsourcetype/humanEdits";
const ENHANCED: &str = "http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicallyEnhanced";
const COMPOSITE: &str = "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia";

#[test]
fn a_recipe_of_geometry_makes_the_lossless_copy_its_develop_makes_and_says_how_it_was_made() {
    let original = corpus("stills/gps-sydney.jpg");
    let turn = recipe(vec![step("t", Kind::Turn(TurnOperation { quarter_turns: 1 }))]);
    let by_recipe = recipe_copy(&original, turn, None, false).unwrap();
    let by_develop = copy(&original, turned(1, false));
    assert!(by_recipe.lossless);
    assert_eq!(scan(&by_recipe.jpeg), scan(&by_develop.jpeg));
    assert_eq!(metadata(&by_recipe.jpeg).orientation, 6);
    let packet = xmp(&by_recipe.jpeg);
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(HUMAN)
    );
    assert!(packet.contains("xmlns:Iptc4xmpExt=\"http://iptc.org/std/Iptc4xmpExt/2008-02-02/\""));
    let hash = attribute(&packet, "photolib:recipeSha256").unwrap();
    assert_eq!(hash.len(), 64);
    // The Develop of the edit is still recorded, for the readers of the alpha's copies.
    let develop = attribute(&packet, "photolib:recipe").unwrap();
    assert_eq!(
        Develop::decode(STANDARD.decode(develop).unwrap().as_slice()).unwrap(),
        turned(1, false)
    );

    // A crop keeps whole blocks, as its develop's does.
    let crop = recipe(vec![step(
        "c",
        Kind::Crop(CropOperation {
            x: 0.0,
            y: 0.0,
            width: 0.5,
            height: 0.5,
        }),
    )]);
    let size = metadata(&original);
    let (w, h) = (size.width, size.height);
    let expected = copy(&original, cropped(0, 0, 0, w / 2, h / 2));
    let got = recipe_copy(&original, crop, None, false).unwrap();
    assert!(got.lossless);
    assert_eq!(scan(&got.jpeg), scan(&expected.jpeg));
}

#[test]
fn a_recipe_of_adjustments_needs_the_decoded_picture_and_the_copy_keeps_the_originals_metadata() {
    use photolib_kernel::proto::model::v1::AdjustOperation;
    let original = corpus("stills/gps-sydney.jpg");
    let light = recipe(vec![step(
        "a",
        Kind::Adjust(AdjustOperation {
            exposure: 0.5,
            ..Default::default()
        }),
    )]);
    let missing = recipe_copy(&original, light.clone(), None, false).unwrap_err();
    assert_eq!(field(&missing), (CallErrorCode::InvalidRequest, "image"));
    let size = metadata(&original);
    let got = recipe_copy(&original, light, Some(gradient(size.width, size.height)), false).unwrap();
    assert!(!got.lossless);
    let (before, after) = (metadata(&original), metadata(&got.jpeg));
    assert!(after.location == before.location && !after.times.is_empty());
    assert_eq!(after.times, before.times);
}

#[test]
#[allow(clippy::too_many_lines)] // three recipes, each with what its XMP must say
fn what_models_made_is_recorded_with_its_parameters_and_stated_as_iptc_says() {
    let original = corpus("stills/gps-sydney.jpg");
    let size = metadata(&original);
    let image = || Some(gradient(size.width, size.height));
    let output = |id: &str, kind: StoredOutputKind, data: Vec<u8>, model: &str| StoredOutput {
        output_id: id.into(),
        kind: kind as i32,
        width: 1,
        height: 1,
        data,
        model: Some(ModelUse {
            model_id: model.into(),
            model_version: "2".into(),
            parameters: vec![photolib_kernel::proto::model::v1::Parameter {
                name: "seed".into(),
                value: "7".into(),
            }],
        }),
    };
    let fill = EditRecipe {
        outputs: vec![output("p", StoredOutputKind::Patch, vec![9, 9, 9, 255], "lama")],
        provenance: Some(photolib_kernel::proto::model::v1::Provenance {
            tool: "photolib/1.0 (linux)".into(),
            digital_source_type: DigitalSourceType::HumanEdits as i32,
            ..Default::default()
        }),
        ..recipe(vec![step(
            "i",
            Kind::Inpaint(InpaintOperation {
                output_id: "p".into(),
                x: 0.0,
                y: 0.0,
                width: 0.5,
                height: 0.5,
            }),
        )])
    };
    let got = recipe_copy(&original, fill, image(), false).unwrap();
    assert!(!got.lossless, "the patch is pixels");
    let packet = xmp(&got.jpeg);
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(COMPOSITE)
    );
    let summary = EditRecipe::decode(
        STANDARD
            .decode(attribute(&packet, "photolib:editRecipe").unwrap())
            .unwrap()
            .as_slice(),
    )
    .unwrap();
    let provenance = summary.provenance.unwrap();
    assert_eq!(provenance.tool, "photolib/1.0 (linux)");
    assert_eq!(provenance.models[0].model_id, "lama");
    assert_eq!(provenance.models[0].parameters[0].value, "7");
    assert!(
        summary.outputs.iter().all(|o| o.data.is_empty()),
        "the XMP holds no pixels of masks or patches"
    );

    // A mask from a model only enhances.
    let masked = EditRecipe {
        outputs: vec![output("m", StoredOutputKind::Mask, vec![255], "sam2-tiny")],
        ..recipe(vec![step(
            "l",
            Kind::LocalAdjust(photolib_kernel::proto::model::v1::LocalAdjustOperation {
                output_id: "m".into(),
                adjust: Some(photolib_kernel::proto::model::v1::AdjustOperation {
                    exposure: 0.5,
                    ..Default::default()
                }),
            }),
        )])
    };
    let packet = xmp(&recipe_copy(&original, masked, image(), false).unwrap().jpeg);
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(ENHANCED)
    );

    // An original that says it is a camera's picture says it is an edit once it is one, and says it once.
    let camera = with(
        &original,
        &xmp_segment(
            "<rdf:Description rdf:about=\"\" xmlns:Iptc4xmpExt=\"http://iptc.org/std/Iptc4xmpExt/2008-02-02/\" Iptc4xmpExt:DigitalSourceType=\"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture\"/>",
        ),
    );
    let turn = recipe(vec![step("t", Kind::Turn(TurnOperation { quarter_turns: 2 }))]);
    let packet = xmp(&recipe_copy(&camera, turn, None, false).unwrap().jpeg);
    assert_eq!(packet.matches("DigitalSourceType=").count(), 1, "{packet}");
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(HUMAN)
    );
}

#[test]
fn a_picture_the_host_rendered_is_recorded_as_a_version_of_its_original_without_being_edited_again() {
    let shell = corpus("stills/baseline.jpg");
    let edit = recipe(vec![step("t", Kind::Turn(TurnOperation { quarter_turns: 1 }))]);
    let got = recipe_copy(&shell, edit, None, true).unwrap();
    assert!(got.lossless);
    assert_eq!(
        scan(&got.jpeg),
        scan(&shell),
        "the pixels are the host's, turned or not"
    );
    assert_eq!(
        metadata(&got.jpeg).orientation,
        metadata(&shell).orientation,
        "no second turn"
    );
    let packet = xmp(&got.jpeg);
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(HUMAN)
    );
    assert!(packet.contains(&format!("blake3:{HASH}")));
    // An edit that changes nothing states nothing.
    let identity = recipe_copy(&shell, recipe(vec![]), None, true).unwrap();
    assert_eq!(attribute(&xmp(&identity.jpeg), "Iptc4xmpExt:DigitalSourceType"), None);
}

#[test]
fn a_recipe_that_is_not_valid_names_its_field() {
    let original = corpus("stills/baseline.jpg");
    let bad = recipe(vec![step(
        "c",
        Kind::Crop(CropOperation {
            x: 0.9,
            y: 0.0,
            width: 0.5,
            height: 1.0,
        }),
    )]);
    let error = recipe_copy(&original, bad, None, false).unwrap_err();
    assert_eq!(
        field(&error),
        (CallErrorCode::InvalidRequest, "recipe.operations[0].crop")
    );
    let mut future = recipe(vec![]);
    future.schema_version = 2;
    assert_eq!(
        field(&recipe_copy(&original, future, None, true).unwrap_err()).1,
        "recipe.schema_version"
    );
}

#[test]
fn a_picture_rendered_from_a_file_keeps_that_files_metadata_in_srgb_and_upright() {
    let original = with(&corpus("stills/gps-sydney.jpg"), &icc(*b"RGB "));
    let rendered = corpus("stills/baseline.jpg");
    let turn = recipe(vec![step("t", Kind::Turn(TurnOperation { quarter_turns: 1 }))]);
    let request = EditCopyRequest {
        original: rendered.clone(),
        recipe: Some(turn),
        rendered: true,
        metadata_from: original.clone(),
        original_blake3: HASH.into(),
        ..Default::default()
    };
    let got: EditCopyResponse = kernel(Method::EditCopy, &request).unwrap();
    assert!(!got.lossless, "its pixels are new");
    assert_eq!(scan(&got.jpeg), scan(&rendered), "the host's pixels");
    let (from, after) = (metadata(&original), metadata(&got.jpeg));
    assert_eq!(frame(&got.jpeg), frame(&rendered), "the host's size");
    assert_eq!(after.orientation.max(1), 1);
    assert_eq!(after.location, from.location, "where it was taken");
    assert_eq!(after.times, from.times, "when it was taken");
    assert!(
        !got.jpeg.windows(12).any(|w| w == b"ICC_PROFILE\0"),
        "the host's pixels are sRGB, the original's profile is not theirs"
    );
    let packet = xmp(&got.jpeg);
    assert_eq!(
        attribute(&packet, "Iptc4xmpExt:DigitalSourceType").as_deref(),
        Some(HUMAN)
    );
    assert!(packet.contains(&format!("blake3:{HASH}")));
    // Not a JPEG: refused, naming the field.
    let bad = EditCopyRequest {
        metadata_from: vec![1, 2, 3],
        ..request
    };
    let error = kernel::<EditCopyResponse>(Method::EditCopy, &bad).unwrap_err();
    assert_eq!(field(&error), (CallErrorCode::InvalidRequest, "metadata_from"));
}

/// The size in the first start-of-frame segment of a JPEG.
fn frame(jpeg: &[u8]) -> (u16, u16) {
    let at = jpeg
        .windows(2)
        .position(|w| w[0] == 0xff && (0xc0..=0xc2).contains(&w[1]))
        .unwrap();
    (
        u16::from_be_bytes([jpeg[at + 7], jpeg[at + 8]]),
        u16::from_be_bytes([jpeg[at + 5], jpeg[at + 6]]),
    )
}

#[test]
fn a_crop_of_the_right_half_and_a_turn_of_a_jpeg_stay_lossless() {
    let original = corpus("stills/gps-sydney.jpg");
    let edit = recipe(vec![
        step(
            "c",
            Kind::Crop(CropOperation {
                x: 0.5,
                y: 0.0,
                width: 0.5,
                height: 1.0,
            }),
        ),
        step("t", Kind::Turn(TurnOperation { quarter_turns: 1 })),
    ]);
    let got = recipe_copy(&original, edit, None, false);
    assert!(got.as_ref().is_ok_and(|g| g.lossless), "{:?}", got.map(|g| g.lossless));
}

#[test]
fn a_recipe_is_cropped_in_the_picture_as_shown_whatever_the_orientation_it_is_stored_in() {
    // Stored 640×480 and shown 480×640 (orientation 6): the top left quarter of what is shown.
    let original = corpus("compound/orientation/orientation-6.jpg");
    let quarter = recipe(vec![step(
        "c",
        Kind::Crop(CropOperation {
            x: 0.0,
            y: 0.0,
            width: 0.5,
            height: 0.5,
        }),
    )]);
    let got = recipe_copy(&original, quarter, None, false).unwrap();
    assert!(got.lossless);
    let (w, h) = frame(&got.jpeg);
    // Stored as 320×240 (a quarter of the shown picture, turned back), up to the block grid.
    assert!((320..=335).contains(&w) && (240..=255).contains(&h), "{w}x{h}");
}
