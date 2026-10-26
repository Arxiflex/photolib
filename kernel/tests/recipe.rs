//! Edit recipes through the kernel's ABI (roadmap M8-01, ADR-0391): resolving, comparing, mapping regions between
//! versions and rendering, on recipes built here.
// Tiny test pictures: their sizes and positions are exact in f32. An empty list is read as `is_empty()` without the
// type annotation `assert_eq!` would need.
#![allow(clippy::cast_precision_loss, clippy::cast_sign_loss, clippy::assert_is_empty)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode, CallResponse, CompareRecipesRequest, CompareRecipesResponse, Develop, DevelopRequest,
    DevelopResponse, Image, Lut, MapRegionsRequest, MapRegionsResponse, Method, RecipeChangeKind,
    RecipeFromDevelopRequest, RecipeFromDevelopResponse, Rect, Region, RenderRecipeRequest, RenderRecipeResponse,
    ResolveRecipeRequest, ResolveRecipeResponse, call_response,
};
use photolib_kernel::proto::model::v1::{
    AdjustOperation, CropOperation, DigitalSourceType, EditRecipe, FlipOperation, InpaintOperation,
    LocalAdjustOperation, LutOperation, ModelUse, Operation, Parameter, Provenance, StoredOutput, StoredOutputKind,
    TurnOperation, operation::Kind,
};
use prost::Message;

fn kernel<R: Message + Default>(method: Method, request: &impl Message) -> Result<R, CallError> {
    let answer = CallResponse::decode(call(method as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(R::decode(r.as_slice()).unwrap()),
        call_response::Result::Error(e) => Err(e),
    }
}

fn resolve(recipe: &EditRecipe, size: (u32, u32)) -> Result<ResolveRecipeResponse, CallError> {
    kernel(
        Method::ResolveRecipe,
        &ResolveRecipeRequest {
            recipe: Some(recipe.clone()),
            width: size.0,
            height: size.1,
        },
    )
}

/// The field a failed call names.
fn field(error: &CallError) -> &str {
    assert_eq!(error.code, CallErrorCode::InvalidRequest as i32, "{error:?}");
    error.params.get("field").map_or("", String::as_str)
}

fn op(id: &str, kind: Kind) -> Operation {
    Operation {
        operation_id: id.into(),
        disabled: false,
        kind: Some(kind),
    }
}

fn turn(id: &str, quarter_turns: u32) -> Operation {
    op(id, Kind::Turn(TurnOperation { quarter_turns }))
}

fn flip(id: &str, vertical: bool) -> Operation {
    op(id, Kind::Flip(FlipOperation { vertical }))
}

fn crop(id: &str, x: f32, y: f32, width: f32, height: f32) -> Operation {
    op(id, Kind::Crop(CropOperation { x, y, width, height }))
}

fn adjust(id: &str, set: impl FnOnce(&mut AdjustOperation)) -> Operation {
    let mut a = AdjustOperation::default();
    set(&mut a);
    op(id, Kind::Adjust(a))
}

fn recipe(operations: Vec<Operation>) -> EditRecipe {
    EditRecipe {
        schema_version: 1,
        operations,
        ..Default::default()
    }
}

fn mask(id: &str, width: u32, height: u32, model: Option<&str>) -> StoredOutput {
    StoredOutput {
        output_id: id.into(),
        kind: StoredOutputKind::Mask as i32,
        width,
        height,
        data: vec![255; (width * height) as usize],
        model: model.map(|m| ModelUse {
            model_id: m.into(),
            model_version: "1".into(),
            parameters: vec![Parameter {
                name: "seed".into(),
                value: "7".into(),
            }],
        }),
    }
}

fn patch(id: &str, width: u32, height: u32, rgba: [u8; 4], model: Option<&str>) -> StoredOutput {
    StoredOutput {
        output_id: id.into(),
        kind: StoredOutputKind::Patch as i32,
        width,
        height,
        data: rgba.repeat((width * height) as usize),
        model: model.map(|m| ModelUse {
            model_id: m.into(),
            model_version: "2".into(),
            parameters: vec![],
        }),
    }
}

fn local(id: &str, output: &str, exposure: f32) -> Operation {
    op(
        id,
        Kind::LocalAdjust(LocalAdjustOperation {
            output_id: output.into(),
            adjust: Some(AdjustOperation {
                exposure,
                ..Default::default()
            }),
        }),
    )
}

fn inpaint(id: &str, output: &str, at: (f32, f32, f32, f32)) -> Operation {
    op(
        id,
        Kind::Inpaint(InpaintOperation {
            output_id: output.into(),
            x: at.0,
            y: at.1,
            width: at.2,
            height: at.3,
        }),
    )
}

#[test]
fn a_recipe_without_operations_changes_nothing_and_has_a_hash() {
    let answer = resolve(&recipe(vec![]), (400, 300)).unwrap();
    assert!(answer.identity && answer.geometry_only);
    assert_eq!((answer.width, answer.height), (400, 300));
    assert_eq!(answer.sha256.len(), 32);
    assert_eq!(resolve(&recipe(vec![]), (10, 10)).unwrap().sha256, answer.sha256);
}

#[test]
fn geometry_steps_compose_into_one_turn_mirror_and_crop_of_the_turned_image() {
    // A quarter turn of 400×300 makes 300×400; the crop is half the width from a quarter in, in that frame.
    let steps = recipe(vec![turn("t", 1), crop("c", 0.25, 0.0, 0.5, 1.0)]);
    let answer = resolve(&steps, (400, 300)).unwrap();
    assert_eq!((answer.width, answer.height), (150, 400));
    let develop = answer.develop.unwrap();
    assert_eq!((develop.quarter_turns, develop.flip), (1, false));
    assert_eq!(
        develop.crop,
        Some(Rect {
            x: 75,
            y: 0,
            width: 150,
            height: 400
        })
    );
    assert!(answer.geometry_only && !answer.identity);

    // A crop made before a turn is the same pixels as the turned crop: 3/4 of the width of the original from the left.
    let before = recipe(vec![crop("c", 0.0, 0.0, 0.75, 1.0), turn("t", 1)]);
    let answer = resolve(&before, (400, 300)).unwrap();
    assert_eq!((answer.width, answer.height), (300, 300));
    let develop = answer.develop.unwrap();
    assert_eq!(develop.quarter_turns, 1);
    assert_eq!(
        develop.crop,
        Some(Rect {
            x: 0,
            y: 0,
            width: 300,
            height: 300
        })
    );
}

#[test]
fn turns_and_mirrors_reduce_to_a_quarter_turn_count_and_a_horizontal_mirror() {
    let size = (400, 300);
    let develop = |ops| resolve(&recipe(ops), size).unwrap().develop.unwrap();
    // Four turns are none; a vertical mirror is a half turn and a horizontal mirror.
    assert!(
        resolve(&recipe(vec![turn("a", 3), turn("b", 1)]), size)
            .unwrap()
            .identity
    );
    let vertical = develop(vec![flip("v", true)]);
    assert_eq!((vertical.quarter_turns, vertical.flip), (2, true));
    // Two mirrors cancel.
    assert!(
        resolve(&recipe(vec![flip("a", false), flip("b", false)]), size)
            .unwrap()
            .identity
    );
    // A turn after a mirror is the opposite turn before it: mirror, then a clockwise turn = turn counter-clockwise, then mirror.
    let both = develop(vec![flip("a", false), turn("b", 1)]);
    assert_eq!((both.quarter_turns, both.flip), (3, true));
}

#[test]
fn global_adjustments_add_up_within_their_ranges_and_disabled_steps_count_for_nothing() {
    let mut off = adjust("off", |a| a.exposure = 5.0);
    off.disabled = true;
    let steps = recipe(vec![
        adjust("a", |a| {
            a.exposure = 5.0;
            a.contrast = 0.75;
        }),
        adjust("b", |a| {
            a.exposure = 5.0;
            a.contrast = 0.75;
            a.temperature = -0.25;
        }),
        off,
    ]);
    let develop = resolve(&steps, (4, 4)).unwrap().develop.unwrap();
    assert_eq!(
        (develop.exposure, develop.contrast, develop.temperature),
        (8.0, 1.0, -0.25)
    );
    let answer = resolve(&steps, (4, 4)).unwrap();
    assert!(!answer.geometry_only && !answer.identity);
    let neutral = recipe(vec![
        adjust("a", |a| a.exposure = 1.0),
        adjust("b", |a| a.exposure = -1.0),
    ]);
    assert!(resolve(&neutral, (4, 4)).unwrap().identity);
}

#[test]
fn the_last_enabled_lut_counts() {
    let lut = |id: &str, v: u8| {
        op(
            id,
            Kind::Lut(LutOperation {
                size: 2,
                rgb16: vec![v; 2 * 2 * 2 * 6],
            }),
        )
    };
    let mut off = lut("off", 3);
    off.disabled = true;
    let develop = resolve(&recipe(vec![lut("a", 1), lut("b", 2), off]), (4, 4))
        .unwrap()
        .develop
        .unwrap();
    assert_eq!(develop.lut.unwrap().rgb16[0], 2);
}

#[test]
fn what_the_recipe_was_made_with_is_derived_from_its_outputs_and_steps() {
    let model_less = recipe(vec![crop("c", 0.0, 0.0, 0.5, 0.5)]);
    let answer = resolve(&model_less, (8, 8)).unwrap().recipe.unwrap();
    assert_eq!(
        answer.provenance.unwrap().digital_source_type,
        DigitalSourceType::HumanEdits as i32
    );

    // A mask from a model: algorithmically enhanced; the model is recorded once, with its parameters.
    let mut masked = recipe(vec![local("m1", "mask", 1.0), local("m2", "mask", -1.0)]);
    masked.outputs = vec![mask("mask", 2, 2, Some("sam2-tiny"))];
    let provenance = resolve(&masked, (8, 8)).unwrap().recipe.unwrap().provenance.unwrap();
    assert_eq!(
        provenance.digital_source_type,
        DigitalSourceType::AlgorithmicallyEnhanced as i32
    );
    assert_eq!(provenance.models.len(), 1);
    assert_eq!(provenance.models[0].model_id, "sam2-tiny");
    assert_eq!(provenance.models[0].parameters[0].value, "7");

    // A generated patch: composite with trained algorithmic media, whatever the caller claimed.
    let mut filled = recipe(vec![inpaint("i", "fill", (0.0, 0.0, 0.5, 0.5))]);
    filled.outputs = vec![patch("fill", 2, 2, [1, 2, 3, 255], Some("lama"))];
    filled.provenance = Some(Provenance {
        tool: "photolib/1.0".into(),
        models: vec![],
        digital_source_type: DigitalSourceType::HumanEdits as i32,
    });
    let provenance = resolve(&filled, (8, 8)).unwrap().recipe.unwrap().provenance.unwrap();
    assert_eq!(provenance.tool, "photolib/1.0");
    assert_eq!(
        provenance.digital_source_type,
        DigitalSourceType::CompositeWithTrainedAlgorithmicMedia as i32
    );

    // A patch from the user's own clone stamp has no model: a human edit.
    filled.outputs = vec![patch("fill", 2, 2, [1, 2, 3, 255], None)];
    let provenance = resolve(&filled, (8, 8)).unwrap().recipe.unwrap().provenance.unwrap();
    assert_eq!(provenance.digital_source_type, DigitalSourceType::HumanEdits as i32);
    assert!(provenance.models.is_empty());
}

#[test]
fn equal_edits_have_equal_canonical_bytes_and_hash() {
    let a = recipe(vec![crop("c", 0.0, -0.0, 0.5, 0.5)]);
    let mut b = recipe(vec![crop("c", 0.0, 0.0, 0.5, 0.5)]);
    b.provenance = Some(Provenance {
        digital_source_type: DigitalSourceType::CompositeWithTrainedAlgorithmicMedia as i32,
        ..Default::default()
    });
    let (a, b) = (resolve(&a, (8, 8)).unwrap(), resolve(&b, (8, 8)).unwrap());
    assert_eq!(a.sha256, b.sha256);
    assert_eq!(a.recipe.unwrap().encode_to_vec(), b.recipe.unwrap().encode_to_vec());
    let other = resolve(&recipe(vec![crop("c", 0.0, 0.0, 0.5, 0.25)]), (8, 8)).unwrap();
    assert_ne!(other.sha256, a.sha256);
}

#[test]
fn a_recipe_that_is_not_valid_names_the_field() {
    let size = (100, 100);
    let named = |r: &EditRecipe| field(&resolve(r, size).unwrap_err()).to_owned();

    let mut future = recipe(vec![]);
    future.schema_version = 2;
    assert_eq!(named(&future), "schema_version");
    future.schema_version = 0;
    assert_eq!(named(&future), "schema_version");

    assert_eq!(
        named(&recipe(vec![Operation {
            operation_id: "x".into(),
            ..Default::default()
        }])),
        "operations[0]"
    );
    assert_eq!(named(&recipe(vec![turn("", 1)])), "operations[0].operation_id");
    assert_eq!(
        named(&recipe(vec![turn(&"x".repeat(65), 1)])),
        "operations[0].operation_id"
    );
    assert_eq!(
        named(&recipe(vec![turn("a", 1), turn("a", 2)])),
        "operations[1].operation_id"
    );
    assert_eq!(named(&recipe(vec![turn("a", 0)])), "operations[0].quarter_turns");
    assert_eq!(named(&recipe(vec![turn("a", 4)])), "operations[0].quarter_turns");

    for (x, y, w, h) in [
        (0.0, 0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0, 0.0),
        (-0.1, 0.0, 0.5, 0.5),
        (0.6, 0.0, 0.5, 0.5),
        (0.0, 0.6, 0.5, 0.5),
        (f32::NAN, 0.0, 0.5, 0.5),
        (0.0, 0.0, f32::INFINITY, 0.5),
    ] {
        assert_eq!(
            named(&recipe(vec![crop("c", x, y, w, h)])),
            "operations[0].crop",
            "{x} {y} {w} {h}"
        );
    }
    // A crop that leaves less than a pixel.
    assert_eq!(
        named(&recipe(vec![crop("c", 0.0, 0.0, 0.001, 0.5)])),
        "operations[0].crop"
    );

    assert_eq!(
        named(&recipe(vec![adjust("a", |a| a.contrast = 1.5)])),
        "operations[0].adjust"
    );
    assert_eq!(
        named(&recipe(vec![adjust("a", |a| a.exposure = 8.5)])),
        "operations[0].adjust"
    );
    assert_eq!(
        named(&recipe(vec![adjust("a", |a| a.tint = f32::NAN)])),
        "operations[0].adjust"
    );

    let too_many = recipe((0..257).map(|i| turn(&format!("t{i}"), 1)).collect());
    assert_eq!(named(&too_many), "operations");
}

#[test]
fn stored_outputs_are_checked_against_their_sizes_their_uses_and_each_other() {
    let size = (100, 100);
    let named = |r: &EditRecipe| field(&resolve(r, size).unwrap_err()).to_owned();
    let with = |ops: Vec<Operation>, outputs: Vec<StoredOutput>| EditRecipe { outputs, ..recipe(ops) };

    // Used, of the right kind and size: valid.
    assert!(resolve(&with(vec![local("l", "m", 1.0)], vec![mask("m", 4, 4, None)]), size).is_ok());
    // Unknown, unreferenced, the wrong kind, duplicated.
    assert_eq!(
        named(&with(vec![local("l", "m", 1.0)], vec![])),
        "operations[0].output_id"
    );
    assert_eq!(named(&with(vec![], vec![mask("m", 4, 4, None)])), "outputs[0]");
    assert_eq!(
        named(&with(vec![local("l", "p", 1.0)], vec![patch("p", 2, 2, [0; 4], None)])),
        "operations[0].output_id"
    );
    assert_eq!(
        named(&with(
            vec![inpaint("i", "m", (0.0, 0.0, 0.5, 0.5))],
            vec![mask("m", 2, 2, None)]
        )),
        "operations[0].output_id"
    );
    assert_eq!(
        named(&with(
            vec![local("l", "m", 1.0)],
            vec![mask("m", 2, 2, None), mask("m", 2, 2, None)]
        )),
        "outputs[1].output_id"
    );
    // Data of another length than its dimensions; empty and oversized dimensions.
    let mut short = mask("m", 4, 4, None);
    short.data.pop();
    assert_eq!(named(&with(vec![local("l", "m", 1.0)], vec![short])), "outputs[0].data");
    assert_eq!(
        named(&with(vec![local("l", "m", 1.0)], vec![mask("m", 0, 4, None)])),
        "outputs[0].width"
    );
    let mut huge = mask("m", 8193, 1, None);
    huge.data.clear();
    assert_eq!(named(&with(vec![local("l", "m", 1.0)], vec![huge])), "outputs[0].width");
    let mut unknown = mask("m", 2, 2, None);
    unknown.kind = 0;
    assert_eq!(
        named(&with(vec![local("l", "m", 1.0)], vec![unknown])),
        "outputs[0].kind"
    );
    // A patch must land inside the image and cover at least a pixel.
    let ok = vec![patch("p", 2, 2, [0; 4], None)];
    assert_eq!(
        named(&with(vec![inpaint("i", "p", (0.8, 0.0, 0.5, 0.5))], ok.clone())),
        "operations[0].inpaint"
    );
    assert_eq!(
        named(&with(vec![inpaint("i", "p", (0.0, 0.0, 0.0, 0.5))], ok)),
        "operations[0].inpaint"
    );
    // A model with too many parameters.
    let mut busy = mask("m", 2, 2, Some("sam"));
    busy.model.as_mut().unwrap().parameters = (0..33)
        .map(|i| Parameter {
            name: format!("p{i}"),
            value: String::new(),
        })
        .collect();
    assert_eq!(named(&with(vec![local("l", "m", 1.0)], vec![busy])), "outputs[0].model");
}

#[test]
fn a_recipe_is_bounded_in_bytes_and_a_garbled_request_is_refused() {
    // 65 outputs.
    let outputs: Vec<_> = (0..65).map(|i| mask(&format!("m{i}"), 1, 1, None)).collect();
    let ops: Vec<_> = (0..65)
        .map(|i| local(&format!("l{i}"), &format!("m{i}"), 1.0))
        .collect();
    let r = EditRecipe { outputs, ..recipe(ops) };
    assert_eq!(field(&resolve(&r, (4, 4)).unwrap_err()), "outputs");
    // Together more than 64 MiB of pixels.
    let big = |id: &str| mask(id, 8192, 4100, None);
    let r = EditRecipe {
        outputs: vec![big("a"), big("b")],
        ..recipe(vec![local("l1", "a", 1.0), local("l2", "b", 1.0)])
    };
    assert_eq!(field(&resolve(&r, (4, 4)).unwrap_err()), "outputs");
    // No request at all, or bytes that are no message.
    let answer = CallResponse::decode(call(Method::ResolveRecipe as u32, &[0xff, 0xff, 0xff]).as_slice()).unwrap();
    assert!(matches!(answer.result, Some(call_response::Result::Error(_))));
    assert!(resolve(&recipe(vec![]), (0, 0)).is_ok());
    let missing: Result<ResolveRecipeResponse, _> = kernel(Method::ResolveRecipe, &ResolveRecipeRequest::default());
    assert_eq!(field(&missing.unwrap_err()), "recipe");
}

/// A picture whose pixel at (x, y) says where it is.
fn picture(width: u32, height: u32) -> Image {
    let rgba = (0..width * height)
        .flat_map(|i| {
            let (x, y) = (i % width, i / width);
            [
                (x as u8).wrapping_mul(3),
                (y as u8).wrapping_mul(5),
                ((x ^ y) as u8).wrapping_mul(7),
                255,
            ]
        })
        .collect();
    Image { width, height, rgba }
}

fn pixel(image: &Image, x: u32, y: u32) -> [u8; 4] {
    let at = ((y * image.width + x) * 4) as usize;
    image.rgba[at..at + 4].try_into().unwrap()
}

fn render(recipe: &EditRecipe, image: &Image) -> Result<Image, CallError> {
    kernel::<RenderRecipeResponse>(
        Method::RenderRecipe,
        &RenderRecipeRequest {
            recipe: Some(recipe.clone()),
            image: Some(image.clone()),
        },
    )
    .map(|r| r.image.unwrap())
}

/// What `METHOD_DEVELOP` makes of `image` with `develop`.
fn developed(develop: Develop, image: &Image) -> Image {
    let request = DevelopRequest {
        develop: Some(develop),
        image: Some(image.clone()),
        ..Default::default()
    };
    kernel::<DevelopResponse>(Method::Develop, &request)
        .unwrap()
        .image
        .unwrap()
}

#[test]
fn geometry_and_adjustments_render_as_the_develop_they_resolve_to() {
    let image = picture(40, 30);
    let steps = recipe(vec![
        crop("c1", 0.1, 0.2, 0.8, 0.7),
        turn("t", 1),
        flip("f", false),
        adjust("a", |a| {
            a.exposure = 0.5;
            a.saturation = -0.25;
            a.clarity = 0.5;
        }),
        crop("c2", 0.0, 0.25, 0.5, 0.75),
    ]);
    let resolved = resolve(&steps, (40, 30)).unwrap();
    let want = developed(resolved.develop.unwrap(), &image);
    let got = render(&steps, &image).unwrap();
    assert_eq!((got.width, got.height), (resolved.width, resolved.height));
    assert_eq!(got, want);
    // Nothing to do: the same pixels, without a round trip through linear light.
    assert_eq!(render(&recipe(vec![]), &image).unwrap(), image);
    let mut off = adjust("a", |a| a.exposure = 2.0);
    off.disabled = true;
    assert_eq!(render(&recipe(vec![off]), &image).unwrap(), image);
}

#[test]
fn a_patch_replaces_its_rectangle_by_its_alpha() {
    let image = picture(8, 8);
    let with = |rgba: [u8; 4]| EditRecipe {
        outputs: vec![patch("p", 2, 2, rgba, Some("lama"))],
        ..recipe(vec![inpaint("i", "p", (0.5, 0.0, 0.5, 0.5))])
    };
    let solid = render(&with([200, 100, 50, 255]), &image).unwrap();
    for y in 0..8 {
        for x in 0..8 {
            let inside = x >= 4 && y < 4;
            let want = if inside {
                [200, 100, 50, 255]
            } else {
                pixel(&image, x, y)
            };
            assert_eq!(pixel(&solid, x, y), want, "({x}, {y})");
        }
    }
    // Fully transparent: the picture. Half: halfway between the two.
    assert_eq!(render(&with([200, 100, 50, 0]), &image).unwrap(), image);
    let half = pixel(&render(&with([200, 100, 50, 128]), &image).unwrap(), 4, 0);
    let was = pixel(&image, 4, 0);
    for c in 0..3 {
        let middle = f32::midpoint(f32::from(was[c]), f32::from([200u8, 100, 50][c]));
        assert!((f32::from(half[c]) - middle).abs() <= 2.0, "{half:?} {was:?}");
    }
    assert_eq!(half[3], 255);
}

#[test]
fn a_masked_adjustment_changes_only_where_the_mask_is() {
    let image = picture(8, 4);
    let mut half = mask("m", 8, 4, Some("sam2-tiny"));
    half.data = (0..32).map(|i| if i % 8 < 4 { 255 } else { 0 }).collect();
    let steps = EditRecipe {
        outputs: vec![half],
        ..recipe(vec![local("l", "m", 1.0)])
    };
    let got = render(&steps, &image).unwrap();
    let brighter = developed(
        Develop {
            exposure: 1.0,
            ..Default::default()
        },
        &image,
    );
    for y in 0..4 {
        for x in 0..8 {
            let want = if x < 4 {
                pixel(&brighter, x, y)
            } else {
                pixel(&image, x, y)
            };
            assert_eq!(pixel(&got, x, y), want, "({x}, {y})");
        }
    }
    // A mask of another size is sampled smoothly: a 2×1 mask [255, 0] fades from full to nothing across the picture.
    let mut coarse = mask("m", 2, 1, None);
    coarse.data = vec![255, 0];
    let steps = EditRecipe {
        outputs: vec![coarse],
        ..recipe(vec![local("l", "m", 1.0)])
    };
    let got = render(&steps, &picture(16, 2)).unwrap();
    let original = picture(16, 2);
    let full = developed(
        Develop {
            exposure: 1.0,
            ..Default::default()
        },
        &original,
    );
    assert_eq!(pixel(&got, 0, 0), pixel(&full, 0, 0), "full strength at the left edge");
    assert_eq!(pixel(&got, 15, 0), pixel(&original, 15, 0), "none at the right edge");
    let middle = pixel(&got, 8, 0);
    assert_ne!(middle, pixel(&full, 8, 0));
    assert_ne!(middle, pixel(&original, 8, 0));
}

#[test]
fn local_operations_work_on_the_original_so_a_crop_chosen_later_keeps_them() {
    let image = picture(8, 8);
    let steps = EditRecipe {
        outputs: vec![patch("p", 1, 1, [9, 9, 9, 255], None)],
        // The crop comes first in the list but the patch is still placed on the original's pixels.
        ..recipe(vec![
            crop("c", 0.5, 0.5, 0.5, 0.5),
            inpaint("i", "p", (0.5, 0.5, 0.25, 0.25)),
        ])
    };
    let got = render(&steps, &image).unwrap();
    assert_eq!((got.width, got.height), (4, 4));
    assert_eq!(pixel(&got, 0, 0), [9, 9, 9, 255]);
    assert_eq!(pixel(&got, 1, 1), [9, 9, 9, 255]);
    assert_eq!(pixel(&got, 2, 2), pixel(&image, 6, 6));
}

#[test]
fn rendering_refuses_what_is_not_a_picture_or_a_recipe() {
    let image = picture(4, 4);
    let mut short = image.clone();
    short.rgba.pop();
    assert_eq!(field(&render(&recipe(vec![]), &short).unwrap_err()), "image");
    assert_eq!(field(&render(&recipe(vec![]), &Image::default()).unwrap_err()), "image");
    assert_eq!(
        field(&render(&recipe(vec![turn("t", 0)]), &image).unwrap_err()),
        "operations[0].quarter_turns"
    );
    // A crop that leaves no pixel of this picture.
    assert_eq!(
        field(&render(&recipe(vec![crop("c", 0.0, 0.0, 0.01, 1.0)]), &image).unwrap_err()),
        "operations[0].crop"
    );
    let none: Result<RenderRecipeResponse, _> = kernel(Method::RenderRecipe, &RenderRecipeRequest::default());
    assert_eq!(field(&none.unwrap_err()), "recipe");
}

/// A difference as the tests write it: the subject, how it differs, what it is and the fields that differ.
type Change = (String, RecipeChangeKind, String, Vec<String>);

fn compare(before: &EditRecipe, after: &EditRecipe) -> Result<Vec<Change>, CallError> {
    let answer: CompareRecipesResponse = kernel(
        Method::CompareRecipes,
        &CompareRecipesRequest {
            before: Some(before.clone()),
            after: Some(after.clone()),
        },
    )?;
    Ok(answer
        .changes
        .into_iter()
        .map(|c| (c.subject.clone(), c.kind(), c.what, c.fields))
        .collect())
}

fn change(subject: &str, kind: RecipeChangeKind, what: &str, fields: &[&str]) -> Change {
    (
        subject.into(),
        kind,
        what.into(),
        fields.iter().map(ToString::to_string).collect(),
    )
}

#[test]
fn two_versions_compare_step_by_step_by_operation_id() {
    use RecipeChangeKind::{Added, Changed, Removed};
    let base = recipe(vec![
        turn("t", 1),
        crop("c", 0.0, 0.0, 0.5, 0.5),
        adjust("a", |a| a.exposure = 1.0),
    ]);
    assert!(compare(&base, &base).unwrap().is_empty());

    // A parameter, a step switched off, a step removed, a step added.
    let mut off = crop("c", 0.0, 0.0, 0.5, 0.5);
    off.disabled = true;
    let after = recipe(vec![
        turn("t", 1),
        off,
        adjust("a", |a| a.exposure = 2.0),
        flip("f", false),
    ]);
    assert_eq!(
        compare(&base, &after).unwrap(),
        vec![
            change("c", Changed, "crop", &["disabled"]),
            change("a", Changed, "adjust", &["exposure"]),
            change("f", Added, "flip", &[]),
        ]
    );
    let after = recipe(vec![turn("t", 2), adjust("a", |a| a.exposure = 1.0)]);
    assert_eq!(
        compare(&base, &after).unwrap(),
        vec![
            change("t", Changed, "turn", &["quarter_turns"]),
            change("c", Removed, "crop", &[])
        ]
    );
    // Several fields of one step, and a step that became another kind.
    let after = recipe(vec![turn("t", 1), crop("c", 0.25, 0.0, 0.5, 0.25), flip("a", true)]);
    assert_eq!(
        compare(&base, &after).unwrap(),
        vec![
            change("c", Changed, "crop", &["x", "height"]),
            change("a", Changed, "flip", &["kind"])
        ]
    );
}

#[test]
fn steps_that_changed_places_are_moved_and_a_moved_change_says_so() {
    use RecipeChangeKind::{Changed, Moved};
    let before = recipe(vec![turn("t", 1), flip("f", false), crop("c", 0.0, 0.0, 0.5, 0.5)]);
    let after = recipe(vec![flip("f", false), turn("t", 1), crop("c", 0.0, 0.0, 0.5, 0.5)]);
    assert_eq!(
        compare(&before, &after).unwrap(),
        vec![change("t", Moved, "turn", &[]), change("f", Moved, "flip", &[])]
    );
    let after = recipe(vec![flip("f", false), turn("t", 3), crop("c", 0.0, 0.0, 0.5, 0.5)]);
    assert_eq!(
        compare(&before, &after).unwrap(),
        vec![
            change("t", Changed, "turn", &["quarter_turns", "position"]),
            change("f", Moved, "flip", &[])
        ]
    );
}

#[test]
fn outputs_and_provenance_are_compared_too() {
    use RecipeChangeKind::{Added, Changed, Removed};
    let with = |data: u8, tool: &str, model: &str| {
        let mut m = mask("m", 2, 2, Some(model));
        m.data = vec![data; 4];
        EditRecipe {
            outputs: vec![m],
            provenance: Some(Provenance {
                tool: tool.into(),
                ..Default::default()
            }),
            ..recipe(vec![local("l", "m", 1.0)])
        }
    };
    let before = with(1, "photolib/1", "sam2-tiny");
    assert!(compare(&before, &before).unwrap().is_empty());
    assert_eq!(
        compare(&before, &with(2, "photolib/1", "sam2-tiny")).unwrap(),
        vec![change("m", Changed, "output", &["data"])]
    );
    assert_eq!(
        compare(&before, &with(1, "photolib/2", "sam2-tiny")).unwrap(),
        vec![change("provenance", Changed, "provenance", &["tool"])]
    );
    assert_eq!(
        compare(&before, &with(1, "photolib/1", "sam2-large")).unwrap(),
        vec![
            change("m", Changed, "output", &["model"]),
            change("provenance", Changed, "provenance", &["models"])
        ]
    );
    // A different set of outputs.
    let mut other = with(1, "photolib/1", "sam2-tiny");
    other.outputs[0].output_id = "n".into();
    if let Some(Kind::LocalAdjust(l)) = other.operations[0].kind.as_mut() {
        l.output_id = "n".into();
    }
    assert_eq!(
        compare(&before, &other).unwrap(),
        vec![
            change("l", Changed, "local_adjust", &["output_id"]),
            change("m", Removed, "output", &[]),
            change("n", Added, "output", &[]),
        ]
    );
}

#[test]
fn a_recipe_that_is_not_valid_cannot_be_compared() {
    let good = recipe(vec![]);
    let bad = recipe(vec![turn("t", 0)]);
    assert_eq!(
        field(&compare(&bad, &good).unwrap_err()),
        "before.operations[0].quarter_turns"
    );
    assert_eq!(
        field(&compare(&good, &bad).unwrap_err()),
        "after.operations[0].quarter_turns"
    );
    let missing: Result<CompareRecipesResponse, _> = kernel(Method::CompareRecipes, &CompareRecipesRequest::default());
    assert_eq!(field(&missing.unwrap_err()), "before");
}

fn from_develop(develop: Develop, size: (u32, u32)) -> Result<EditRecipe, CallError> {
    kernel::<RecipeFromDevelopResponse>(
        Method::RecipeFromDevelop,
        &RecipeFromDevelopRequest {
            develop: Some(develop),
            width: size.0,
            height: size.1,
            tool: "photolib-alpha".into(),
        },
    )
    .map(|r| r.recipe.unwrap())
}

#[test]
fn the_develop_of_an_alpha_copy_becomes_a_recipe_that_renders_the_same() {
    let develop = Develop {
        exposure: 0.5,
        saturation: -0.25,
        quarter_turns: 5,
        flip: true,
        crop: Some(Rect {
            x: 4,
            y: 10,
            width: 24,
            height: 20,
        }),
        ..Default::default()
    };
    let image = picture(40, 30);
    let recipe = from_develop(develop.clone(), (40, 30)).unwrap();
    let ids: Vec<_> = recipe.operations.iter().map(|o| o.operation_id.as_str()).collect();
    assert_eq!(ids, ["turn", "flip", "crop", "adjust"]);
    assert_eq!(recipe.provenance.as_ref().unwrap().tool, "photolib-alpha");
    // A quarter turn of 40×30 makes 30×40, in which the crop is 24×20 from (4, 10).
    let resolved = resolve(&recipe, (40, 30)).unwrap();
    assert_eq!((resolved.width, resolved.height), (24, 20));
    let back = resolved.develop.unwrap();
    assert_eq!((back.quarter_turns, back.flip, back.crop), (1, true, develop.crop));
    assert_eq!(
        render(&recipe, &image).unwrap(),
        developed(
            Develop {
                quarter_turns: 1,
                ..develop
            },
            &image
        )
    );
}

#[test]
fn a_neutral_develop_is_an_empty_recipe_and_a_develop_that_does_not_fit_is_refused() {
    assert!(from_develop(Develop::default(), (0, 0)).unwrap().operations.is_empty());
    let named = |d: Develop, size| field(&from_develop(d, size).unwrap_err()).to_owned();
    let cropped = |x, y, width, height| Develop {
        crop: Some(Rect { x, y, width, height }),
        ..Default::default()
    };
    assert_eq!(named(cropped(10, 0, 40, 10), (40, 30)), "develop.crop");
    assert_eq!(named(cropped(0, 0, 10, 10), (0, 30)), "width");
    assert_eq!(
        named(
            Develop {
                exposure: f32::NAN,
                ..Default::default()
            },
            (4, 4)
        ),
        "develop"
    );
    assert_eq!(
        named(
            Develop {
                contrast: 2.0,
                ..Default::default()
            },
            (4, 4)
        ),
        "develop"
    );
    let lut = Lut {
        size: 66,
        rgb16: vec![0; 66 * 66 * 66 * 6],
    };
    assert_eq!(
        named(
            Develop {
                lut: Some(lut),
                ..Default::default()
            },
            (4, 4)
        ),
        "develop.lut"
    );
    // A crop of nothing means the whole picture, as in `Develop`.
    let whole = from_develop(cropped(0, 0, 0, 0), (40, 30)).unwrap();
    assert!(whole.operations.is_empty());
}

/// Small deterministic numbers for the property test.
struct Lcg(u64);

impl Lcg {
    fn below(&mut self, n: u32) -> u32 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        ((self.0 >> 33) % u64::from(n)) as u32
    }
}

#[test]
fn a_mapped_region_lands_on_the_pixels_the_render_moved() {
    let (w, h) = (64u32, 48u32);
    let image = picture(w, h);
    let mut random = Lcg(7);
    let mut checked = 0;
    for round in 0..60 {
        let mut ops = vec![];
        for i in 0..=random.below(4) {
            ops.push(match random.below(3) {
                0 => turn(&format!("t{i}"), 1 + random.below(3)),
                1 => flip(&format!("f{i}"), random.below(2) == 1),
                _ => {
                    let (x, y) = (random.below(4), random.below(4));
                    let (cw, ch) = (1 + random.below(4 - x), 1 + random.below(4 - y));
                    crop(
                        &format!("c{i}"),
                        x as f32 / 4.0,
                        y as f32 / 4.0,
                        cw as f32 / 4.0,
                        ch as f32 / 4.0,
                    )
                }
            });
        }
        let steps = recipe(ops);
        let out = render(&steps, &image).unwrap();
        // A box of odd size on the pixel grid has a pixel at its centre.
        let (bx, by) = (random.below(w - 9), random.below(h - 9));
        let (bw, bh) = (1 + 2 * random.below(4), 1 + 2 * random.below(4));
        let source = region(
            bx as f32 / w as f32,
            by as f32 / h as f32,
            bw as f32 / w as f32,
            bh as f32 / h as f32,
        );
        let (mapped, visible) = moved(None, Some(&steps), source);
        if visible < 1.0 {
            continue;
        }
        checked += 1;
        let at = |v: f32, size: u32| ((v * size as f32).floor() as u32).min(size - 1);
        let (mx, my) = (mapped.x + mapped.width / 2.0, mapped.y + mapped.height / 2.0);
        let got = pixel(&out, at(mx, out.width), at(my, out.height));
        let want = pixel(&image, bx + bw / 2, by + bh / 2);
        assert_eq!(got, want, "round {round}: {steps:?}");
    }
    assert!(
        checked >= 20,
        "only {checked} of 60 recipes kept the box in the picture"
    );
}

fn region(x: f32, y: f32, width: f32, height: f32) -> Region {
    Region { x, y, width, height }
}

fn map(
    from: Option<&EditRecipe>,
    to: Option<&EditRecipe>,
    regions: Vec<Region>,
) -> Result<MapRegionsResponse, CallError> {
    kernel(
        Method::MapRegions,
        &MapRegionsRequest {
            from: from.cloned(),
            to: to.cloned(),
            regions,
        },
    )
}

/// Where `r` ends up, and how much of it is left.
fn moved(from: Option<&EditRecipe>, to: Option<&EditRecipe>, r: Region) -> (Region, f32) {
    let answer = map(from, to, vec![r]).unwrap();
    assert_eq!(answer.regions.len(), 1);
    let one = &answer.regions[0];
    (one.region.unwrap(), one.visible)
}

fn near(a: &Region, b: (f32, f32, f32, f32)) {
    for (got, want) in [(a.x, b.0), (a.y, b.1), (a.width, b.2), (a.height, b.3)] {
        assert!((got - want).abs() < 1e-5, "{a:?} is not {b:?}");
    }
}

#[test]
fn a_region_moves_with_the_crop_that_a_version_applies() {
    let cropped = recipe(vec![crop("c", 0.25, 0.25, 0.5, 0.5)]);
    // Without edits the regions stay.
    near(&moved(None, None, region(0.1, 0.2, 0.3, 0.4)).0, (0.1, 0.2, 0.3, 0.4));
    // Inside the crop: the same part of the picture, in the crop's fractions.
    let (inside, visible) = moved(None, Some(&cropped), region(0.4, 0.4, 0.2, 0.2));
    near(&inside, (0.3, 0.3, 0.4, 0.4));
    assert_eq!(visible, 1.0);
    // Half of it out on each side: clipped, a quarter left.
    let (clipped, visible) = moved(None, Some(&cropped), region(0.1, 0.1, 0.3, 0.3));
    near(&clipped, (0.0, 0.0, 0.3, 0.3));
    assert!((visible - 0.25).abs() < 1e-5, "{visible}");
    // Out of the frame altogether: nothing left of it.
    let (gone, visible) = moved(None, Some(&cropped), region(0.0, 0.0, 0.1, 0.1));
    near(&gone, (0.0, 0.0, 0.0, 0.0));
    assert_eq!(visible, 0.0);
    // And back: a region of the cropped version is where it was in the original.
    near(
        &moved(Some(&cropped), None, region(0.3, 0.3, 0.4, 0.4)).0,
        (0.4, 0.4, 0.2, 0.2),
    );
}

#[test]
fn a_region_turns_and_mirrors_with_the_picture() {
    let turned = recipe(vec![turn("t", 1)]);
    // The top left corner of the picture is its top right after a clockwise quarter turn.
    near(
        &moved(None, Some(&turned), region(0.0, 0.0, 0.2, 0.1)).0,
        (0.9, 0.0, 0.1, 0.2),
    );
    let three = recipe(vec![turn("t", 3)]);
    near(
        &moved(None, Some(&three), region(0.0, 0.0, 0.2, 0.1)).0,
        (0.0, 0.8, 0.1, 0.2),
    );
    let half = recipe(vec![turn("t", 2)]);
    near(
        &moved(None, Some(&half), region(0.0, 0.0, 0.2, 0.1)).0,
        (0.8, 0.9, 0.2, 0.1),
    );
    let mirrored = recipe(vec![flip("f", false)]);
    near(
        &moved(None, Some(&mirrored), region(0.1, 0.2, 0.3, 0.4)).0,
        (0.6, 0.2, 0.3, 0.4),
    );
    let upside = recipe(vec![flip("f", true)]);
    near(
        &moved(None, Some(&upside), region(0.1, 0.2, 0.3, 0.4)).0,
        (0.1, 0.4, 0.3, 0.4),
    );
}

#[test]
fn regions_go_between_any_two_versions_through_the_original() {
    let a = recipe(vec![crop("c", 0.1, 0.2, 0.6, 0.5), turn("t", 1), flip("f", false)]);
    let b = recipe(vec![turn("t", 3), crop("c", 0.0, 0.25, 0.75, 0.5)]);
    let r = region(0.3, 0.3, 0.2, 0.2);
    let there = moved(Some(&a), Some(&b), r).0;
    let in_original = moved(Some(&a), None, r).0;
    near(
        &moved(None, Some(&b), in_original).0,
        (there.x, there.y, there.width, there.height),
    );
    // To another version and back changes nothing while it stays inside both frames.
    let full = recipe(vec![turn("t", 2)]);
    let back = moved(Some(&full), Some(&a), moved(Some(&a), Some(&full), r).0).0;
    near(&back, (r.x, r.y, r.width, r.height));
}

#[test]
fn regions_that_are_not_boxes_and_recipes_that_are_not_valid_are_refused() {
    let named = |result: Result<MapRegionsResponse, CallError>| field(&result.unwrap_err()).to_owned();
    for bad in [
        region(f32::NAN, 0.0, 0.1, 0.1),
        region(0.0, 0.0, 0.0, 0.1),
        region(0.0, 0.0, 0.1, -0.1),
        region(0.0, f32::INFINITY, 0.1, 0.1),
    ] {
        assert_eq!(
            named(map(None, None, vec![region(0.0, 0.0, 0.1, 0.1), bad])),
            "regions[1]"
        );
    }
    let mut invalid = recipe(vec![]);
    invalid.schema_version = 9;
    assert_eq!(named(map(Some(&invalid), None, vec![])), "from.schema_version");
    assert_eq!(
        named(map(None, Some(&recipe(vec![turn("t", 0)])), vec![])),
        "to.operations[0].quarter_turns"
    );
    assert!(map(None, None, vec![]).unwrap().regions.is_empty());
}
