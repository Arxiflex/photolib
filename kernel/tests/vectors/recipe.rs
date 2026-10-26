//! Conformance cases of the edit recipe calls (ADR-0391): what the Rust build answers is what every binding must,
//! pixel for pixel in the renders.

use super::{call_case, computed_case, fail, generated};
use photolib_kernel::proto::kernel::v1::{
    CallErrorCode, CompareRecipesRequest, Develop, EditCopyRequest, Image, MapRegionsRequest, Method,
    RecipeFromDevelopRequest, Rect, Region, RenderRecipeRequest, ResolveRecipeRequest,
};
use photolib_kernel::proto::model::v1::{
    AdjustOperation, CropOperation, EditRecipe, FlipOperation, InpaintOperation, LocalAdjustOperation, ModelUse,
    Operation, Parameter, StoredOutput, StoredOutputKind, TurnOperation, operation::Kind,
};
use prost::Message;
use serde_json::{Value, json};

/// Writes (and checks) `recipe.json`.
pub(crate) fn generate() {
    generated(
        "recipe.json",
        "Edit recipes (ADR-0391): resolving, comparing, mapping regions through and rendering, and the alpha's Develop.",
        &recipe_cases(),
        json!(null),
    );
}

fn op(id: &str, kind: Kind) -> Operation {
    Operation {
        operation_id: id.into(),
        disabled: false,
        kind: Some(kind),
    }
}

fn recipe(operations: Vec<Operation>, outputs: Vec<StoredOutput>) -> EditRecipe {
    EditRecipe {
        schema_version: 1,
        operations,
        outputs,
        ..Default::default()
    }
}

fn model(id: &str) -> ModelUse {
    ModelUse {
        model_id: id.into(),
        model_version: "1".into(),
        parameters: vec![Parameter {
            name: "seed".into(),
            value: "7".into(),
        }],
    }
}

fn picture(width: u32, height: u32) -> Image {
    Image {
        width,
        height,
        rgba: (0..width * height)
            .flat_map(|i| [(i * 37) as u8, (i * 11 + 90) as u8, (i * i) as u8, 255])
            .collect(),
    }
}

fn crop(x: f32, y: f32, width: f32, height: f32) -> Kind {
    Kind::Crop(CropOperation { x, y, width, height })
}

fn exposure(exposure: f32) -> Kind {
    Kind::Adjust(AdjustOperation {
        exposure,
        contrast: 0.25,
        ..Default::default()
    })
}

/// A recipe of geometry and adjustments only.
pub(crate) fn geometry() -> EditRecipe {
    recipe(
        vec![
            op("crop", crop(0.25, 0.0, 0.5, 1.0)),
            op("turn", Kind::Turn(TurnOperation { quarter_turns: 1 })),
            op("flip", Kind::Flip(FlipOperation { vertical: true })),
            op("adjust", exposure(0.5)),
            op("more", exposure(0.25)),
        ],
        vec![],
    )
}

/// The geometry alone, which a JPEG's lossless copy can make.
fn lossless() -> EditRecipe {
    let mut recipe = geometry();
    recipe.operations.retain(|o| !matches!(o.kind, Some(Kind::Adjust(_))));
    recipe
}

/// The edit copy cases of recipes, of the JPEG `original` and `small`, a smaller one.
pub(crate) fn copy_cases(original: &[u8], small: &[u8]) -> Vec<Value> {
    let request = |bytes: &[u8], recipe: EditRecipe| EditCopyRequest {
        original: bytes.to_vec(),
        recipe: Some(recipe),
        original_blake3: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262".into(),
        ..Default::default()
    };
    vec![
        computed_case(
            "a recipe of a turn and a crop keeps the image data and states how it was made",
            Method::EditCopy,
            &request(original, lossless()),
        ),
        computed_case(
            "a picture the host rendered keeps the metadata of its file and records the recipe",
            Method::EditCopy,
            &EditCopyRequest {
                rendered: true,
                metadata_from: original.to_vec(),
                ..request(small, geometry())
            },
        ),
    ]
}

/// A recipe with a mask and a patch, which models made.
fn local() -> EditRecipe {
    let output = |id: &str, kind, (width, height), data: Vec<u8>, model| StoredOutput {
        output_id: id.into(),
        kind: kind as i32,
        width,
        height,
        data,
        model: Some(model),
    };
    let light = Kind::LocalAdjust(LocalAdjustOperation {
        output_id: "mask".into(),
        adjust: Some(AdjustOperation {
            exposure: 1.0,
            ..Default::default()
        }),
    });
    let fill = Kind::Inpaint(InpaintOperation {
        output_id: "patch".into(),
        x: 0.5,
        y: 0.25,
        width: 0.25,
        height: 0.5,
    });
    recipe(
        vec![
            op("light", light),
            op("fill", fill),
            op("crop", crop(0.0, 0.0, 0.75, 1.0)),
        ],
        vec![
            output("mask", StoredOutputKind::Mask, (2, 1), vec![255, 0], model("sam2-tiny")),
            output(
                "patch",
                StoredOutputKind::Patch,
                (1, 1),
                vec![250, 40, 30, 200],
                model("lama"),
            ),
        ],
    )
}

fn recipe_cases() -> Vec<Value> {
    let (geometry, local) = (geometry(), local());
    let resolve = |name, recipe: &EditRecipe, (width, height)| {
        let request = ResolveRecipeRequest {
            recipe: Some(recipe.clone()),
            width,
            height,
        };
        computed_case(name, Method::ResolveRecipe, &request)
    };
    let render = |name, recipe: &EditRecipe, image| {
        let request = RenderRecipeRequest {
            recipe: Some(recipe.clone()),
            image: Some(image),
        };
        computed_case(name, Method::RenderRecipe, &request)
    };
    let region = |x, y, width, height| Region { x, y, width, height };
    let alpha = Develop {
        exposure: 0.5,
        quarter_turns: 1,
        flip: true,
        crop: Some(Rect {
            x: 4,
            y: 10,
            width: 24,
            height: 20,
        }),
        ..Default::default()
    };
    let mut cases = vec![
        resolve(
            "geometry and adjustments of a recipe resolve to one develop",
            &geometry,
            (40, 30),
        ),
        resolve("a recipe with outputs of models derives its provenance", &local, (8, 4)),
        resolve("a recipe without a size has no crop in pixels", &geometry, (0, 0)),
        render(
            "geometry and adjustments render as the develop they resolve to",
            &geometry,
            picture(16, 12),
        ),
        render(
            "a mask and a patch change the original before the crop",
            &local,
            picture(8, 4),
        ),
        computed_case(
            "regions move with the crop and the turn",
            Method::MapRegions,
            &MapRegionsRequest {
                from: None,
                to: Some(geometry.clone()),
                regions: vec![region(0.3, 0.1, 0.2, 0.3), region(0.0, 0.0, 0.2, 0.2)],
            },
        ),
        computed_case(
            "two versions compare step by step",
            Method::CompareRecipes,
            &CompareRecipesRequest {
                before: Some(geometry),
                after: Some(local),
            },
        ),
        computed_case(
            "the develop of an alpha copy becomes a recipe",
            Method::RecipeFromDevelop,
            &RecipeFromDevelopRequest {
                develop: Some(alpha),
                width: 40,
                height: 30,
                tool: "photolib-alpha".into(),
            },
        ),
    ];
    cases.extend(refusals());
    cases
}

/// Requests the kernel refuses, and the field it names.
fn refusals() -> Vec<Value> {
    let refused = |name, request: ResolveRecipeRequest, field| {
        let outcome = fail(CallErrorCode::InvalidRequest, &[("field", field)]);
        call_case(name, Method::ResolveRecipe as u32, request.encode_to_vec(), outcome)
    };
    vec![
        refused(
            "a turn of no quarter turns is refused",
            ResolveRecipeRequest {
                recipe: Some(recipe(
                    vec![op("turn", Kind::Turn(TurnOperation { quarter_turns: 0 }))],
                    vec![],
                )),
                ..Default::default()
            },
            "operations[0].quarter_turns",
        ),
        refused("no recipe is refused", ResolveRecipeRequest::default(), "recipe"),
    ]
}
