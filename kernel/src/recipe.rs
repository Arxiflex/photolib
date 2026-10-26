//! Edit recipes (roadmap M8-01, ADR-0391): `EditRecipe` is checked and put in one canonical form here, whatever builds
//! it, and everything that reads one (a renderer, a database, a comparison, a face's box) goes through the checked
//! form. A render applies the local operations to the original as shown, then the geometry, then the global
//! adjustments summed, so the stored outputs of models stay valid when a crop changes.

mod compare;
mod geometry;
mod render;

use std::collections::{BTreeMap, BTreeSet};

use prost::Message;
use sha2::{Digest, Sha256};

use crate::proto::kernel::v1::{
    Develop, Lut, MapRegionsRequest, MapRegionsResponse, MappedRegion, RecipeFromDevelopRequest,
    RecipeFromDevelopResponse, Region, ResolveRecipeRequest, ResolveRecipeResponse,
};
use crate::proto::model::v1::{
    AdjustOperation, CropOperation, DigitalSourceType, EditRecipe, FlipOperation, LutOperation, ModelUse, Operation,
    Provenance, StoredOutput, StoredOutputKind, TurnOperation, operation::Kind,
};
use crate::{CallError, invalid_request};
pub(crate) use compare::compare;
use geometry::Geometry;
pub(crate) use render::render;

/// The layout this kernel reads and writes.
const SCHEMA_VERSION: u32 = 1;
const MAX_OPERATIONS: usize = 256;
const MAX_OUTPUTS: usize = 64;
/// The longest side of a stored output, in pixels.
const MAX_SIDE: u32 = 8192;
/// The pixel bytes of all the outputs of a recipe together.
const MAX_DATA: u64 = 64 << 20;
const MAX_ID: usize = 64;
const MAX_TEXT: usize = 256;
const MAX_PARAMETERS: usize = 32;
/// The most entries per side of a recipe's LUT.
const MAX_LUT: u32 = 65;
/// The range of each of the six adjustments, in the order of `AdjustOperation`.
const RANGES: [f32; 6] = [1.0, 1.0, 8.0, 1.0, 1.0, 1.0];

/// A recipe that passed every check, with what its renderers need.
pub(crate) struct Checked {
    /// The canonical form.
    pub(crate) recipe: EditRecipe,
    /// The geometry steps composed; the crop is in fractions until it meets a size.
    pub(crate) geometry: Geometry,
    /// The global adjustments, summed.
    pub(crate) adjust: AdjustOperation,
    /// The index of the last enabled LUT.
    lut: Option<usize>,
    /// Whether an enabled local operation changes the pixels.
    pub(crate) local: bool,
}

impl Checked {
    /// The `Develop` of the geometry and the global adjustments; its crop is in pixels of the original of `size`.
    pub(crate) fn develop(&self, size: Option<(u32, u32)>) -> Develop {
        let a = &self.adjust;
        let lut = self
            .lut
            .and_then(|at| match self.recipe.operations.get(at)?.kind.as_ref()? {
                Kind::Lut(l) => Some(Lut {
                    size: l.size,
                    rgb16: l.rgb16.clone(),
                }),
                _ => None,
            });
        Develop {
            temperature: a.temperature,
            tint: a.tint,
            exposure: a.exposure,
            contrast: a.contrast,
            clarity: a.clarity,
            saturation: a.saturation,
            lut,
            ..self.geometry.develop(size)
        }
    }

    /// Whether no global adjustment and no LUT changes the colours.
    pub(crate) fn neutral(&self) -> bool {
        let a = &self.adjust;
        self.lut.is_none()
            && [a.temperature, a.tint, a.exposure, a.contrast, a.clarity, a.saturation]
                .iter()
                .all(|&v| v == 0.0)
    }
}

/// What the steps seen so far add up to.
struct Walk<'a> {
    all: &'a [StoredOutput],
    by_id: BTreeMap<&'a str, usize>,
    size: Option<(u32, u32)>,
    ids: BTreeSet<String>,
    used: BTreeSet<usize>,
    geometry: Geometry,
    sum: [f32; 6],
    lut: Option<usize>,
    local: bool,
    /// The strongest claim about how the picture was made that a step makes (the enum's order is that strength).
    source: DigitalSourceType,
}

/// Checks `recipe`, with the size of the original as shown when the caller has it (0 for none), and canonicalises it.
pub(crate) fn check(recipe: &EditRecipe, size: (u32, u32)) -> Result<Checked, CallError> {
    if recipe.schema_version != SCHEMA_VERSION {
        return Err(invalid_request("schema_version"));
    }
    if recipe.operations.len() > MAX_OPERATIONS {
        return Err(invalid_request("operations"));
    }
    if recipe.outputs.len() > MAX_OUTPUTS {
        return Err(invalid_request("outputs"));
    }
    let tool = recipe.provenance.as_ref().map_or("", |p| p.tool.as_str());
    if tool.chars().count() > MAX_TEXT {
        return Err(invalid_request("provenance.tool"));
    }
    let mut walk = Walk {
        all: &recipe.outputs,
        by_id: check_outputs(&recipe.outputs)?,
        size: (size.0 > 0 && size.1 > 0).then_some(size),
        ids: BTreeSet::new(),
        used: BTreeSet::new(),
        geometry: Geometry::IDENTITY,
        sum: [0.0; 6],
        lut: None,
        local: false,
        source: DigitalSourceType::Unspecified,
    };
    let mut canonical = recipe.clone();
    for (i, operation) in canonical.operations.iter_mut().enumerate() {
        walk.step(i, operation)
            .map_err(|what| invalid_request(&format!("operations[{i}]{what}")))?;
    }
    if let Some(unused) = (0..recipe.outputs.len()).find(|i| !walk.used.contains(i)) {
        return Err(invalid_request(&format!("outputs[{unused}]")));
    }
    canonical.provenance = Some(Provenance {
        tool: tool.to_owned(),
        models: models(&recipe.outputs),
        digital_source_type: walk.source.into(),
    });
    let mut sum = walk.sum;
    for (v, range) in sum.iter_mut().zip(RANGES) {
        *v = v.clamp(-range, range) + 0.0;
    }
    Ok(Checked {
        recipe: canonical,
        geometry: walk.geometry,
        adjust: rebuilt(sum),
        lut: walk.lut,
        local: walk.local,
    })
}

impl Walk<'_> {
    /// Checks the step `i` and adds it up; the error names the part of the step that is wrong.
    fn step(&mut self, i: usize, operation: &mut Operation) -> Result<(), &'static str> {
        let id = &operation.operation_id;
        if id.is_empty() || id.chars().count() > MAX_ID || !self.ids.insert(id.clone()) {
            return Err(".operation_id");
        }
        let enabled = !operation.disabled;
        match operation.kind.as_mut().ok_or("")? {
            Kind::Turn(t) => {
                if !(1..=3).contains(&t.quarter_turns) {
                    return Err(".quarter_turns");
                }
                if enabled {
                    self.geometry = self.geometry.turn(t.quarter_turns);
                }
            }
            Kind::Flip(f) => {
                if enabled {
                    self.geometry = self.geometry.flip(f.vertical);
                }
            }
            Kind::Crop(c) => {
                let rect = clean_rect([c.x, c.y, c.width, c.height]).ok_or(".crop")?;
                [c.x, c.y, c.width, c.height] = rect;
                if enabled {
                    self.geometry = self.geometry.crop(rect.map(f64::from));
                    if self.size.is_some_and(|s| self.geometry.pixels(s).is_none()) {
                        return Err(".crop");
                    }
                }
            }
            Kind::Adjust(a) => {
                let values = adjustment(a).ok_or(".adjust")?;
                if enabled {
                    self.sum.iter_mut().zip(values).for_each(|(s, v)| *s += v);
                }
            }
            Kind::Lut(l) => {
                let cells = u64::from(l.size).saturating_pow(3).saturating_mul(6);
                if !(2..=MAX_LUT).contains(&l.size) || l.rgb16.len() as u64 != cells {
                    return Err(".lut");
                }
                if enabled {
                    self.lut = Some(i);
                }
            }
            Kind::LocalAdjust(l) => {
                let output = self.output(&l.output_id, StoredOutputKind::Mask).ok_or(".output_id")?;
                let values = l.adjust.as_ref().and_then(adjustment).ok_or(".adjust")?;
                l.adjust = Some(rebuilt(values));
                if enabled {
                    self.local = true;
                    if self.all.get(output).is_some_and(|o| o.model.is_some()) {
                        self.source = self.source.max(DigitalSourceType::AlgorithmicallyEnhanced);
                    }
                }
            }
            Kind::Inpaint(p) => {
                let output = self.output(&p.output_id, StoredOutputKind::Patch).ok_or(".output_id")?;
                let rect = clean_rect([p.x, p.y, p.width, p.height]).ok_or(".inpaint")?;
                [p.x, p.y, p.width, p.height] = rect;
                if enabled {
                    self.local = true;
                    if self.all.get(output).is_some_and(|o| o.model.is_some()) {
                        self.source = self.source.max(DigitalSourceType::CompositeWithTrainedAlgorithmicMedia);
                    }
                }
            }
        }
        if enabled {
            self.source = self.source.max(DigitalSourceType::HumanEdits);
        }
        Ok(())
    }

    /// The index of the output `id` names if it is of `kind`; it counts as used.
    fn output(&mut self, id: &str, kind: StoredOutputKind) -> Option<usize> {
        let at = self.by_id.get(id).copied()?;
        self.all.get(at).filter(|o| o.kind == kind as i32)?;
        self.used.insert(at);
        Some(at)
    }
}

/// The six values of an adjustment if each is finite and in its range, with negative zeros made zero.
fn adjustment(a: &AdjustOperation) -> Option<[f32; 6]> {
    let values = [a.temperature, a.tint, a.exposure, a.contrast, a.clarity, a.saturation];
    (values.iter().zip(RANGES).all(|(v, r)| v.is_finite() && v.abs() <= r)).then(|| values.map(|v| v + 0.0))
}

fn rebuilt([temperature, tint, exposure, contrast, clarity, saturation]: [f32; 6]) -> AdjustOperation {
    AdjustOperation {
        temperature,
        tint,
        exposure,
        contrast,
        clarity,
        saturation,
    }
}

/// A rectangle of fractions inside the unit square and not empty, with negative zeros made zero.
fn clean_rect(r: [f32; 4]) -> Option<[f32; 4]> {
    let [left, top, width, height] = r;
    let inside = |at: f32, size: f32| at >= 0.0 && size > 0.0 && f64::from(at) + f64::from(size) <= 1.0 + 1e-6;
    (r.iter().all(|v| v.is_finite()) && inside(left, width) && inside(top, height)).then(|| r.map(|v| v + 0.0))
}

/// The stored outputs by id, checked: kind, dimensions, data and model.
fn check_outputs(outputs: &[StoredOutput]) -> Result<BTreeMap<&str, usize>, CallError> {
    let mut by_id = BTreeMap::new();
    let mut bytes = 0_u64;
    for (i, o) in outputs.iter().enumerate() {
        let at = |what: &str| invalid_request(&format!("outputs[{i}]{what}"));
        if o.output_id.is_empty()
            || o.output_id.chars().count() > MAX_ID
            || by_id.insert(o.output_id.as_str(), i).is_some()
        {
            return Err(at(".output_id"));
        }
        let per_pixel = match StoredOutputKind::try_from(o.kind) {
            Ok(StoredOutputKind::Mask) => 1,
            Ok(StoredOutputKind::Patch) => 4,
            _ => return Err(at(".kind")),
        };
        if !(1..=MAX_SIDE).contains(&o.width) {
            return Err(at(".width"));
        }
        if !(1..=MAX_SIDE).contains(&o.height) {
            return Err(at(".height"));
        }
        let expected = u64::from(o.width)
            .saturating_mul(u64::from(o.height))
            .saturating_mul(per_pixel);
        if o.data.len() as u64 != expected {
            return Err(at(".data"));
        }
        bytes = bytes.saturating_add(expected);
        if bytes > MAX_DATA {
            return Err(invalid_request("outputs"));
        }
        if o.model.as_ref().is_some_and(|m| !model_ok(m)) {
            return Err(at(".model"));
        }
    }
    Ok(by_id)
}

fn model_ok(m: &ModelUse) -> bool {
    let short = |s: &str| s.chars().count() <= MAX_TEXT;
    !m.model_id.is_empty()
        && short(&m.model_id)
        && short(&m.model_version)
        && m.parameters.len() <= MAX_PARAMETERS
        && m.parameters
            .iter()
            .all(|p| !p.name.is_empty() && short(&p.name) && short(&p.value))
}

/// Every model the outputs came from, once each, in the order of the outputs.
fn models(outputs: &[StoredOutput]) -> Vec<ModelUse> {
    let mut seen: Vec<ModelUse> = vec![];
    for model in outputs.iter().filter_map(|o| o.model.as_ref()) {
        if !seen.contains(model) {
            seen.push(model.clone());
        }
    }
    seen
}

/// `METHOD_RESOLVE_RECIPE`.
pub(crate) fn resolve(request: ResolveRecipeRequest) -> Result<ResolveRecipeResponse, CallError> {
    let recipe = request.recipe.ok_or_else(|| invalid_request("recipe"))?;
    let size = (request.width, request.height);
    let checked = check(&recipe, size)?;
    let sized = (size.0 > 0 && size.1 > 0).then_some(size);
    let (width, height) = sized.map_or((0, 0), |s| checked.geometry.output_size(s));
    let develop = checked.develop(sized);
    let geometry_only = !checked.local && checked.neutral();
    let identity = geometry_only && checked.geometry.is_identity(sized);
    let sha256 = Sha256::digest(checked.recipe.encode_to_vec()).to_vec();
    Ok(ResolveRecipeResponse {
        recipe: Some(checked.recipe),
        sha256,
        width,
        height,
        develop: Some(develop),
        geometry_only,
        identity,
    })
}

/// A recipe's geometry, as `check` finds it; an error names the field under `name`.
fn geometry_of(recipe: Option<EditRecipe>, name: &str) -> Result<Geometry, CallError> {
    let recipe = recipe.unwrap_or_else(|| EditRecipe {
        schema_version: SCHEMA_VERSION,
        ..Default::default()
    });
    check(&recipe, (0, 0))
        .map(|checked| checked.geometry)
        .map_err(|mut error| {
            if let Some(field) = error.params.get_mut("field") {
                *field = format!("{name}.{field}");
            }
            error
        })
}

/// `METHOD_MAP_REGIONS`.
pub(crate) fn map_regions(request: MapRegionsRequest) -> Result<MapRegionsResponse, CallError> {
    let (from, to) = (geometry_of(request.from, "from")?, geometry_of(request.to, "to")?);
    let mut regions = Vec::with_capacity(request.regions.len());
    for (i, r) in request.regions.iter().enumerate() {
        let valid = [r.x, r.y, r.width, r.height].iter().all(|v| v.is_finite()) && r.width > 0.0 && r.height > 0.0;
        if !valid {
            return Err(invalid_request(&format!("regions[{i}]")));
        }
        let mapped = to.forward(from.backward([r.x, r.y, r.width, r.height].map(f64::from)));
        regions.push(clipped(mapped));
    }
    Ok(MapRegionsResponse { regions })
}

/// `r` inside the unit square, and the part of its area that is.
#[allow(clippy::cast_possible_truncation)] // fractions of a picture, in 0..=1
fn clipped([left, top, width, height]: [f64; 4]) -> MappedRegion {
    let (start, stop) = (
        (left.max(0.0), top.max(0.0)),
        ((left + width).min(1.0), (top + height).min(1.0)),
    );
    if stop.0 <= start.0 || stop.1 <= start.1 {
        return MappedRegion {
            region: Some(Region::default()),
            visible: 0.0,
        };
    }
    let (kept_width, kept_height) = (stop.0 - start.0, stop.1 - start.1);
    MappedRegion {
        region: Some(Region {
            x: start.0 as f32,
            y: start.1 as f32,
            width: kept_width as f32,
            height: kept_height as f32,
        }),
        visible: (kept_width * kept_height / (width * height)).min(1.0) as f32,
    }
}

fn operation(id: &str, kind: Kind) -> Operation {
    Operation {
        operation_id: id.to_owned(),
        disabled: false,
        kind: Some(kind),
    }
}

/// `METHOD_RECIPE_FROM_DEVELOP`: the recipe of the `Develop` an alpha copy recorded (ADR-0331).
pub(crate) fn from_develop(request: RecipeFromDevelopRequest) -> Result<RecipeFromDevelopResponse, CallError> {
    let develop = request.develop.unwrap_or_default();
    let size = (request.width, request.height);
    let adjust = AdjustOperation {
        temperature: develop.temperature,
        tint: develop.tint,
        exposure: develop.exposure,
        contrast: develop.contrast,
        clarity: develop.clarity,
        saturation: develop.saturation,
    };
    let mut operations = vec![];
    let turns = develop.quarter_turns % 4;
    if turns != 0 {
        operations.push(operation("turn", Kind::Turn(TurnOperation { quarter_turns: turns })));
    }
    if develop.flip {
        operations.push(operation("flip", Kind::Flip(FlipOperation { vertical: false })));
    }
    if let Some(crop) = cropped(&develop, size, turns)? {
        operations.push(operation("crop", Kind::Crop(crop)));
    }
    if adjustment(&adjust).is_none() {
        return Err(invalid_request("develop"));
    }
    if adjust != AdjustOperation::default() {
        operations.push(operation("adjust", Kind::Adjust(adjust)));
    }
    if let Some(lut) = develop.lut {
        if !(2..=MAX_LUT).contains(&lut.size) {
            return Err(invalid_request("develop.lut"));
        }
        let (size, rgb16) = (lut.size, lut.rgb16);
        operations.push(operation("lut", Kind::Lut(LutOperation { size, rgb16 })));
    }
    let recipe = EditRecipe {
        schema_version: SCHEMA_VERSION,
        operations,
        provenance: Some(Provenance {
            tool: request.tool,
            ..Default::default()
        }),
        outputs: vec![],
    };
    let checked = check(&recipe, size).map_err(|error| match error.params.get("field") {
        Some(field) if field.ends_with("lut") => invalid_request("develop.lut"),
        _ => error,
    })?;
    Ok(RecipeFromDevelopResponse {
        recipe: Some(checked.recipe),
    })
}

/// The crop of `develop` in fractions of the turned original of `size`, none when it keeps the whole image.
#[allow(clippy::cast_possible_truncation)] // fractions of a picture, in 0..=1
fn cropped(develop: &Develop, size: (u32, u32), turns: u32) -> Result<Option<CropOperation>, CallError> {
    let Some(c) = develop.crop.filter(|c| c.width > 0 && c.height > 0) else {
        return Ok(None);
    };
    if size.0 == 0 {
        return Err(invalid_request("width"));
    }
    if size.1 == 0 {
        return Err(invalid_request("height"));
    }
    let (fw, fh) = if turns % 2 == 1 { (size.1, size.0) } else { size };
    let fits = |at: u32, len: u32, full: u32| u64::from(at).saturating_add(u64::from(len)) <= u64::from(full);
    if !fits(c.x, c.width, fw) || !fits(c.y, c.height, fh) {
        return Err(invalid_request("develop.crop"));
    }
    if (c.width, c.height) == (fw, fh) {
        return Ok(None);
    }
    let part = |v: u32, full: u32| (f64::from(v) / f64::from(full)) as f32;
    Ok(Some(CropOperation {
        x: part(c.x, fw),
        y: part(c.y, fh),
        width: part(c.width, fw),
        height: part(c.height, fh),
    }))
}
