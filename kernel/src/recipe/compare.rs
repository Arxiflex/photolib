//! Comparing two versions' recipes: which steps, stored outputs and provenance differ, and in what.

use std::collections::BTreeMap;

use prost::Message;

use super::check;
use crate::proto::kernel::v1::{
    CompareRecipesRequest, CompareRecipesResponse, RecipeChange, RecipeChangeKind as Kind, RecipeChangeKind,
};
use crate::proto::model::v1::{AdjustOperation, EditRecipe, Operation, StoredOutput, operation};
use crate::{CallError, invalid_request};

/// A step's or output's fields as (name, encoded value), to be compared one by one.
type Fields = Vec<(String, Vec<u8>)>;

/// `METHOD_COMPARE_RECIPES`.
pub(crate) fn compare(request: CompareRecipesRequest) -> Result<CompareRecipesResponse, CallError> {
    let checked = |recipe: Option<EditRecipe>, name: &str| {
        let recipe = recipe.ok_or_else(|| invalid_request(name))?;
        check(&recipe, (0, 0)).map(|c| c.recipe).map_err(|mut error| {
            if let Some(field) = error.params.get_mut("field") {
                *field = format!("{name}.{field}");
            }
            error
        })
    };
    let (before, after) = (checked(request.before, "before")?, checked(request.after, "after")?);
    let mut changes = steps(&before, &after);
    changes.extend(outputs(&before, &after));
    changes.extend(provenance(&before, &after));
    Ok(CompareRecipesResponse { changes })
}

fn steps(before: &EditRecipe, after: &EditRecipe) -> Vec<RecipeChange> {
    let in_after: BTreeMap<&str, &Operation> = after.operations.iter().map(|o| (o.operation_id.as_str(), o)).collect();
    let in_before: BTreeMap<&str, &Operation> =
        before.operations.iter().map(|o| (o.operation_id.as_str(), o)).collect();
    // The order of the steps both have, in each recipe: a step at another place in the two moved.
    let order = |recipe: &EditRecipe, other: &BTreeMap<&str, &Operation>| -> Vec<String> {
        (recipe.operations.iter())
            .filter(|o| other.contains_key(o.operation_id.as_str()))
            .map(|o| o.operation_id.clone())
            .collect()
    };
    let (was, is) = (order(before, &in_after), order(after, &in_before));
    let place = |list: &[String], id: &str| list.iter().position(|i| i == id);

    let mut changes = vec![];
    for step in &before.operations {
        let id = step.operation_id.as_str();
        let Some(&now) = in_after.get(id) else {
            changes.push(change(id, Kind::Removed, what(step), vec![]));
            continue;
        };
        let mut fields = differing(&step_fields(step), &step_fields(now));
        if what(step) != what(now) {
            // A step of another kind has other fields: only that it is another kind, and whether it was switched.
            fields.retain(|f| f == "kind" || f == "disabled");
        }
        let moved = place(&was, id) != place(&is, id);
        if moved && !fields.is_empty() {
            fields.push("position".into());
        }
        let kind = if fields.is_empty() && !moved {
            None
        } else if fields.is_empty() {
            Some(Kind::Moved)
        } else {
            Some(Kind::Changed)
        };
        if let Some(kind) = kind {
            changes.push(change(id, kind, what(now), fields));
        }
    }
    for step in &after.operations {
        if !in_before.contains_key(step.operation_id.as_str()) {
            changes.push(change(&step.operation_id, Kind::Added, what(step), vec![]));
        }
    }
    changes
}

fn outputs(before: &EditRecipe, after: &EditRecipe) -> Vec<RecipeChange> {
    let find = |recipe: &'_ EditRecipe, id: &str| recipe.outputs.iter().find(|o| o.output_id == id).cloned();
    let mut changes = vec![];
    for output in &before.outputs {
        match find(after, &output.output_id) {
            None => changes.push(change(&output.output_id, Kind::Removed, "output", vec![])),
            Some(now) => {
                let fields = differing(&output_fields(output), &output_fields(&now));
                if !fields.is_empty() {
                    changes.push(change(&output.output_id, Kind::Changed, "output", fields));
                }
            }
        }
    }
    for output in &after.outputs {
        if find(before, &output.output_id).is_none() {
            changes.push(change(&output.output_id, Kind::Added, "output", vec![]));
        }
    }
    changes
}

fn provenance(before: &EditRecipe, after: &EditRecipe) -> Option<RecipeChange> {
    let fields = |r: &EditRecipe| -> Fields {
        let p = r.provenance.clone().unwrap_or_default();
        vec![
            ("tool".into(), p.tool.into_bytes()),
            (
                "models".into(),
                p.models.iter().flat_map(Message::encode_to_vec).collect(),
            ),
            (
                "digital_source_type".into(),
                p.digital_source_type.to_le_bytes().to_vec(),
            ),
        ]
    };
    let fields = differing(&fields(before), &fields(after));
    (!fields.is_empty()).then(|| change("provenance", Kind::Changed, "provenance", fields))
}

fn change(subject: &str, kind: RecipeChangeKind, what: &str, fields: Vec<String>) -> RecipeChange {
    RecipeChange {
        subject: subject.to_owned(),
        kind: kind.into(),
        what: what.to_owned(),
        fields,
    }
}

/// The names in `a` whose values are not those of the same name in `b`, in the order of `a` and then of `b`.
fn differing(a: &Fields, b: &Fields) -> Vec<String> {
    let get = |f: &Fields, name: &str| f.iter().find(|(n, _)| n == name).map(|(_, v)| v.clone());
    let only_in_b = b.iter().map(|(n, _)| n).filter(|n| !a.iter().any(|(m, _)| m == *n));
    (a.iter().map(|(n, _)| n).chain(only_in_b))
        .filter(|n| get(a, n) != get(b, n))
        .cloned()
        .collect()
}

fn what(step: &Operation) -> &'static str {
    use operation::Kind::{Adjust, Crop, Flip, Inpaint, LocalAdjust, Lut, Turn};
    match step.kind {
        Some(Turn(_)) => "turn",
        Some(Flip(_)) => "flip",
        Some(Crop(_)) => "crop",
        Some(Adjust(_)) => "adjust",
        Some(Lut(_)) => "lut",
        Some(LocalAdjust(_)) => "local_adjust",
        Some(Inpaint(_)) => "inpaint",
        None => "",
    }
}

fn float(name: &str, v: f32) -> (String, Vec<u8>) {
    (name.to_owned(), v.to_le_bytes().to_vec())
}

fn adjust_fields(prefix: &str, a: &AdjustOperation) -> Fields {
    let names = ["temperature", "tint", "exposure", "contrast", "clarity", "saturation"];
    let values = [a.temperature, a.tint, a.exposure, a.contrast, a.clarity, a.saturation];
    names
        .iter()
        .zip(values)
        .map(|(n, v)| float(&format!("{prefix}{n}"), v))
        .collect()
}

/// The fields of a step that a user could have changed, besides its id.
fn step_fields(step: &Operation) -> Fields {
    use operation::Kind::{Adjust, Crop, Flip, Inpaint, LocalAdjust, Lut, Turn};
    let mut fields: Fields = vec![
        ("kind".into(), what(step).as_bytes().to_vec()),
        ("disabled".into(), vec![u8::from(step.disabled)]),
    ];
    match &step.kind {
        Some(Turn(t)) => fields.push(("quarter_turns".into(), t.quarter_turns.to_le_bytes().to_vec())),
        Some(Flip(f)) => fields.push(("vertical".into(), vec![u8::from(f.vertical)])),
        Some(Crop(c)) => fields.extend([
            float("x", c.x),
            float("y", c.y),
            float("width", c.width),
            float("height", c.height),
        ]),
        Some(Adjust(a)) => fields.extend(adjust_fields("", a)),
        Some(Lut(l)) => {
            fields.push(("size".into(), l.size.to_le_bytes().to_vec()));
            fields.push(("rgb16".into(), l.rgb16.clone()));
        }
        Some(LocalAdjust(l)) => {
            fields.push(("output_id".into(), l.output_id.clone().into_bytes()));
            fields.extend(adjust_fields("adjust.", &l.adjust.unwrap_or_default()));
        }
        Some(Inpaint(p)) => {
            fields.push(("output_id".into(), p.output_id.clone().into_bytes()));
            fields.extend([
                float("x", p.x),
                float("y", p.y),
                float("width", p.width),
                float("height", p.height),
            ]);
        }
        None => {}
    }
    fields
}

fn output_fields(o: &StoredOutput) -> Fields {
    vec![
        ("kind".into(), o.kind.to_le_bytes().to_vec()),
        ("width".into(), o.width.to_le_bytes().to_vec()),
        ("height".into(), o.height.to_le_bytes().to_vec()),
        ("data".into(), o.data.clone()),
        (
            "model".into(),
            o.model.as_ref().map(Message::encode_to_vec).unwrap_or_default(),
        ),
    ]
}
