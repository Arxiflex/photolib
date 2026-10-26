//! The CPU reference renderer of the editor rendering spike (ADR-0054) through the kernel's ABI. The expected pixel
//! values were computed independently, in double precision, from the definitions in src/develop.rs.

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode, CallResponse, Develop, DevelopRequest, DevelopResponse, GainMap, Guide, Image, Lut,
    Method, Rect, call_response,
};
use prost::Message;

fn develop(request: &DevelopRequest) -> Result<DevelopResponse, CallError> {
    let answer = CallResponse::decode(call(Method::Develop as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(DevelopResponse::decode(r.as_slice()).unwrap()),
        call_response::Result::Error(e) => Err(e),
    }
}

/// The neutral develop with the adjustments that `set` makes.
fn edit(set: impl FnOnce(&mut Develop)) -> Develop {
    let mut develop = Develop::default();
    set(&mut develop);
    develop
}

fn request(develop: Develop, image: Image) -> DevelopRequest {
    DevelopRequest {
        develop: Some(develop),
        image: Some(image),
        ..Default::default()
    }
}

fn rect(x: u32, y: u32, width: u32, height: u32) -> Option<Rect> {
    Some(Rect { x, y, width, height })
}

fn image(width: u32, height: u32, pixel: impl Fn(u32, u32) -> [u8; 3]) -> Image {
    let rgba = (0..width * height)
        .flat_map(|i| {
            let [r, g, b] = pixel(i % width, i / width);
            [r, g, b, 255]
        })
        .collect();
    Image { width, height, rgba }
}

fn render(develop: Develop, image: Image) -> Image {
    self::develop(&request(develop, image)).unwrap().image.unwrap()
}

fn rgb(image: &Image) -> Vec<[u8; 3]> {
    image.rgba.chunks(4).map(|p| [p[0], p[1], p[2]]).collect()
}

fn one(develop: Develop, colour: [u8; 3]) -> [u8; 3] {
    rgb(&render(develop, image(1, 1, |_, _| colour)))[0]
}

/// A texture of colours that varies at every scale, from a hash of the position.
fn texture(x: u32, y: u32) -> [u8; 3] {
    let h = (x.wrapping_mul(374_761_393) ^ y.wrapping_mul(668_265_263)).wrapping_mul(1_274_126_177);
    let base = |c: u32| ((x * c + y * (9 - c) + (h >> (8 * c)) % 64) % 256) as u8;
    [base(1), base(2), base(3)]
}

fn lut(size: u32, entry: impl Fn([f64; 3]) -> [f64; 3]) -> Lut {
    let mut rgb16 = Vec::new();
    let at = |i: u32| f64::from(i) / f64::from(size - 1);
    for b in 0..size {
        for g in 0..size {
            for r in 0..size {
                for v in entry([at(r), at(g), at(b)]) {
                    rgb16.extend(((v * 65535.0).round() as u16).to_le_bytes());
                }
            }
        }
    }
    Lut { size, rgb16 }
}

#[test]
fn a_neutral_develop_changes_no_pixel() {
    let input = image(256, 3, |x, y| match y {
        0 => [x as u8; 3],
        1 => texture(x, y),
        _ => [x as u8, 255 - x as u8, (x * 7) as u8],
    });
    assert_eq!(render(Develop::default(), input.clone()), input);
}

#[test]
fn each_adjustment_follows_its_definition() {
    let cases = [
        (edit(|d| d.exposure = 1.0), [128; 3], [176; 3]),
        (edit(|d| d.exposure = -1.0), [200; 3], [146; 3]),
        (edit(|d| d.temperature = 1.0), [128; 3], [150, 128, 109]),
        (edit(|d| d.tint = 1.0), [128; 3], [128, 109, 128]),
        (edit(|d| d.contrast = 1.0), [64, 128, 192], [40, 128, 216]),
        (edit(|d| d.contrast = -1.0), [64, 0, 255], [88, 0, 255]),
        (edit(|d| d.saturation = -1.0), [200, 100, 50], [128; 3]),
        (edit(|d| d.saturation = 1.0), [200, 100, 50], [248, 55, 0]),
    ];
    for (develop, input, want) in cases {
        assert_eq!(one(develop.clone(), input), want, "{develop:?} of {input:?}");
    }
}

#[test]
fn a_lut_maps_encoded_colours_by_trilinear_interpolation() {
    let identity = lut(2, |c| c);
    let invert = lut(2, |c| c.map(|v| 1.0 - v));
    // The centre entry of a 3³ table is raised by 0.25; a colour near it rises by 0.25 times the centre's weight.
    let bump = lut(3, |c| c.map(|v| if c == [0.5; 3] { v + 0.25 } else { v }));
    let by = |lut: &Lut| edit(|d| d.lut = Some(lut.clone()));
    for colour in [[0, 0, 0], [255, 255, 255], [12, 200, 77], [128, 64, 250]] {
        assert_eq!(one(by(&identity), colour), colour);
        assert_eq!(one(by(&invert), colour), colour.map(|v| 255 - v));
    }
    assert_eq!(one(by(&bump), [102; 3]), [135; 3]);
    assert_eq!(one(by(&bump), [64; 3]), [72; 3]);
    assert_eq!(one(by(&bump), [64, 128, 128]), [96, 160, 160]);
}

#[test]
fn clarity_raises_contrast_against_the_surroundings() {
    let spot = |x: u32, y: u32| {
        if (24..40).contains(&x) && (24..40).contains(&y) {
            [180; 3]
        } else {
            [60; 3]
        }
    };
    let at = |image: &Image, x: usize, y: usize| image.rgba[(y * 64 + x) * 4];
    let clarity = |amount| render(edit(|d| d.clarity = amount), image(64, 64, spot));
    let (plain, more, less) = (clarity(0.0), clarity(1.0), clarity(-1.0));
    // Just inside the spot's edge and just outside it.
    assert!(at(&more, 25, 32) > at(&plain, 25, 32) && at(&more, 22, 32) < at(&plain, 22, 32));
    assert!(at(&less, 25, 32) < at(&plain, 25, 32) && at(&less, 22, 32) > at(&plain, 22, 32));
    // Far from the spot, the surroundings are their own guide.
    assert_eq!(at(&more, 0, 0), 60);
    let flat = image(64, 64, |_, _| [90, 120, 30]);
    assert_eq!(render(edit(|d| d.clarity = 1.0), flat.clone()), flat);
}

#[test]
fn the_guide_has_64_cells_on_the_long_side_and_follows_the_luminance() {
    let guide = |w, h, colour| {
        let whole = request(Develop::default(), image(w, h, |_, _| colour));
        develop(&whole).unwrap().guide.unwrap()
    };
    let wide = guide(640, 480, [255; 3]);
    assert_eq!((wide.width, wide.height), (64, 48));
    assert!(wide.log2_luminance.iter().all(|&v| v.abs() < 1e-5));
    let tall = guide(30, 100, [0; 3]);
    assert_eq!((tall.width, tall.height), (19, 64));
    assert!(tall.log2_luminance.iter().all(|&v| (v + 12.0).abs() < 1e-5));
    assert_eq!(guide(5, 3, [128; 3]).width, 5);
}

#[test]
fn tiles_rendered_with_the_guide_of_the_whole_equal_the_whole() {
    let develop = Develop {
        temperature: 0.3,
        exposure: 0.7,
        contrast: 0.5,
        clarity: 0.8,
        saturation: 0.4,
        lut: Some(lut(5, |c| [c[1], c[2], c[0]])),
        ..Default::default()
    };
    let whole = image(100, 70, texture);
    let expected = self::develop(&request(develop.clone(), whole.clone())).unwrap();
    let mut tiled = vec![0; whole.rgba.len()];
    for (x, y, w, h) in [(0, 0, 64, 64), (64, 0, 36, 64), (0, 64, 64, 6), (64, 64, 36, 6)] {
        let tile = DevelopRequest {
            guide: expected.guide.clone(),
            full_width: 100,
            full_height: 70,
            tile_x: x,
            tile_y: y,
            ..request(develop.clone(), image(w, h, |i, j| texture(x + i, y + j)))
        };
        let out = self::develop(&tile).unwrap();
        assert_eq!(out.guide, None);
        for row in 0..h {
            let at = ((y + row) * 100 + x) as usize * 4;
            let from = (row * w) as usize * 4;
            tiled[at..at + w as usize * 4]
                .copy_from_slice(&out.image.as_ref().unwrap().rgba[from..from + w as usize * 4]);
        }
    }
    assert_eq!(tiled, expected.image.unwrap().rgba);
}

#[test]
fn geometry_turns_then_crops_without_resampling() {
    let numbered = image(3, 2, |x, y| [(10 * y + x) as u8; 3]);
    let turned = |quarter_turns, crop| {
        let develop = edit(|d| (d.quarter_turns, d.crop) = (quarter_turns, crop));
        let out = render(develop, numbered.clone());
        (
            out.width,
            out.height,
            rgb(&out).iter().map(|p| p[0]).collect::<Vec<_>>(),
        )
    };
    assert_eq!(turned(0, None), (3, 2, vec![0, 1, 2, 10, 11, 12]));
    assert_eq!(turned(1, None), (2, 3, vec![10, 0, 11, 1, 12, 2]));
    assert_eq!(turned(2, None), (3, 2, vec![12, 11, 10, 2, 1, 0]));
    assert_eq!(turned(3, None), (2, 3, vec![2, 12, 1, 11, 0, 10]));
    assert_eq!(turned(1, rect(1, 1, 1, 2)), (1, 2, vec![1, 2]));
}

#[test]
fn geometry_turns_then_mirrors_then_crops() {
    let numbered = image(3, 2, |x, y| [(10 * y + x) as u8; 3]);
    let flipped = |quarter_turns, crop| {
        let develop = edit(|d| (d.quarter_turns, d.flip, d.crop) = (quarter_turns, true, crop));
        let out = render(develop, numbered.clone());
        (
            out.width,
            out.height,
            rgb(&out).iter().map(|p| p[0]).collect::<Vec<_>>(),
        )
    };
    assert_eq!(flipped(0, None), (3, 2, vec![2, 1, 0, 12, 11, 10]));
    assert_eq!(flipped(1, None), (2, 3, vec![0, 10, 1, 11, 2, 12]));
    assert_eq!(flipped(1, rect(1, 0, 1, 2)), (1, 2, vec![10, 11]));
}

const OFFSET: f32 = 1.0 / 64.0;

fn srgb_to_linear(v: u8) -> f64 {
    let v = f64::from(v) / 255.0;
    if v <= 0.04045 {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}

/// An image whose gain map, one map pixel per `scale`² block, boosts each block by up to `max_log2` stops.
fn hdr(width: u32, height: u32, scale: u32, max_log2: f32) -> (Image, GainMap) {
    let base = image(width, height, |x, y| {
        [(40 + 50 * ((x + y) % 5)) as u8, 255, (17 * x + y) as u8]
    });
    let map = image(width / scale, height / scale, |x, y| {
        [(255 - (80 * x + 50 * y) % 256) as u8; 3]
    });
    let gain_map = GainMap {
        image: Some(map),
        min_log2: 0.0,
        max_log2,
        gamma: 1.0,
        offset_sdr: OFFSET,
        offset_hdr: OFFSET,
        hdr_capacity_min: 0.0,
        hdr_capacity_max: max_log2,
    };
    (base, gain_map)
}

/// The HDR rendition of each pixel, per channel.
fn reconstruct(base: &Image, map: &GainMap) -> Vec<[f64; 3]> {
    let image = map.image.as_ref().unwrap();
    let scale = base.width / image.width;
    let offset = f64::from(OFFSET);
    (0..base.height * base.width)
        .map(|i| {
            let (x, y) = (i % base.width, i / base.width);
            let m = ((y / scale * image.width + x / scale) * 4) as usize;
            std::array::from_fn(|c| {
                let recovery = (f64::from(image.rgba[m + c]) / 255.0).powf(1.0 / f64::from(map.gamma));
                let log2 = f64::from(map.min_log2) + f64::from(map.max_log2 - map.min_log2) * recovery;
                (srgb_to_linear(base.rgba[i as usize * 4 + c]) + offset) * log2.exp2() - offset
            })
        })
        .collect()
}

#[test]
fn a_geometry_only_edit_keeps_the_gain_map_bit_for_bit() {
    let (base, gain_map) = hdr(8, 12, 4, 3.0);
    let turned = edit(|d| (d.quarter_turns, d.crop) = (1, rect(4, 0, 8, 8)));
    let edit = DevelopRequest {
        gain_map: Some(gain_map.clone()),
        ..request(turned, base)
    };
    let out = develop(&edit).unwrap().gain_map.unwrap();
    // The 2×3 map turned is 3×2; the crop keeps its last two columns.
    let map = gain_map.image.as_ref().unwrap();
    let at = |x: u32, y: u32| map.rgba[((y * 2 + x) * 4) as usize..][..4].to_vec();
    let want = [at(0, 1), at(0, 0), at(1, 1), at(1, 0)].concat();
    assert_eq!(
        out.image,
        Some(Image {
            width: 2,
            height: 2,
            rgba: want
        })
    );
    assert_eq!(
        GainMap { image: None, ..out },
        GainMap {
            image: None,
            ..gain_map
        }
    );
}

#[test]
fn a_tonal_edit_recomputes_the_gain_map_for_the_new_headroom() {
    let (base, gain_map) = hdr(10, 10, 1, 3.0);
    let edit = DevelopRequest {
        gain_map: Some(gain_map.clone()),
        ..request(edit(|d| d.exposure = 1.0), base.clone())
    };
    let response = develop(&edit).unwrap();
    let (image, map) = (response.image.unwrap(), response.gain_map.unwrap());
    // A white pixel boosted 3 stops is 16× brighter than its clipped edit: one stop more headroom.
    let offset = f64::from(OFFSET);
    let headroom = ((16.0 * (1.0 + offset) - offset) / (1.0 + offset)).log2();
    assert!((f64::from(map.max_log2) - headroom).abs() < 1e-3, "{map:?}");
    assert_eq!(
        (map.min_log2, map.gamma, map.hdr_capacity_max),
        (0.0, 1.0, map.max_log2)
    );
    let (before, after) = (reconstruct(&base, &gain_map), reconstruct(&image, &map));
    for (before, after) in before.iter().zip(&after) {
        for c in 0..3 {
            let want = 2.0 * before[c];
            assert!(
                (after[c] - want).abs() <= 0.01 * want + 0.002,
                "{after:?} for {before:?}"
            );
        }
    }
}

#[test]
fn inconsistent_requests_name_the_field() {
    let field = |request: DevelopRequest| {
        let error = develop(&request).unwrap_err();
        assert_eq!(error.code, CallErrorCode::InvalidRequest as i32);
        error.params["field"].clone()
    };
    let small = || image(4, 4, texture);
    let short = Image {
        rgba: vec![0; 15],
        ..small()
    };
    let (base, gain_map) = hdr(8, 8, 4, 2.0);
    let mapped = |develop, map| DevelopRequest {
        gain_map: Some(GainMap {
            image: Some(map),
            ..gain_map.clone()
        }),
        ..request(develop, base.clone())
    };
    let tile = |values: usize, full_height| DevelopRequest {
        guide: Some(Guide {
            width: 1,
            height: 1,
            log2_luminance: vec![0.0; values],
        }),
        full_width: 4,
        full_height,
        ..request(Develop::default(), small())
    };
    let bad_lut = Lut {
        size: 2,
        rgb16: vec![0; 47],
    };
    for (request, want) in [
        (request(Develop::default(), short), "image"),
        (DevelopRequest::default(), "image"),
        (request(edit(|d| d.exposure = f32::NAN), small()), "develop"),
        (request(edit(|d| d.lut = Some(bad_lut)), small()), "lut"),
        (request(edit(|d| d.crop = rect(2, 0, 3, 1)), small()), "crop"),
        (
            mapped(edit(|d| d.crop = rect(1, 0, 4, 4)), image(2, 2, texture)),
            "crop",
        ),
        (mapped(Develop::default(), image(3, 3, texture)), "gain_map"),
        (tile(2, 4), "guide"),
        (tile(1, 3), "guide"),
    ] {
        assert_eq!(field(request), want);
    }
}
