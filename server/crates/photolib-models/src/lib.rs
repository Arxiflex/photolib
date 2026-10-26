//! The model registry (ADR-0064, design 09 §12): every model that photolibd and the apps may download, pinned by
//! SHA-256 and size, with the licence of its weights. `registry.json` is compiled in, and `gate`, the licence gate,
//! runs over it in `cargo test`.

use std::sync::LazyLock;

use serde::{Deserialize, Serialize};

mod store;
pub use store::{Imported, Store};

/// A model at one revision; `id@revision` names it everywhere, so that revisions coexist during a migration.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Model {
    /// family-size-resolution, such as `siglip2-b16-256`
    pub id: String,
    /// The export build
    pub revision: String,
    pub task: Task,
    pub licence: Licence,
    /// What an image input is made of, by the kernel's PrepareImage on every target (design 09 §2.2)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preprocess: Option<Preprocess>,
    /// The length of an embedding
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dim: Option<u32>,
    /// Installed only when asked for by id: `photolibd models fetch` leaves it out
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub optional: bool,
    pub files: Vec<File>,
}

/// The image resized to a square of `size`, each channel scaled to 0–1, less `mean`, over `std`: as the model's own
/// processor prepares it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Preprocess {
    /// The side of the square
    pub size: u32,
    /// Each channel's mean, subtracted
    pub mean: [f32; 3],
    /// Each channel's standard deviation, divided by
    pub std: [f32; 3],
    /// Whether the short side is resized to `size` and the centred square kept, else the whole image is squashed
    pub crop: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Task {
    ImageTextEmbedding,
    FaceDetection,
    FaceEmbedding,
    /// PP-OCR's detector of lines of text
    TextDetection,
    /// PP-OCR's recogniser of one script
    TextRecognition,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Licence {
    /// The SPDX id of the weights' licence, else a `LicenseRef-`
    pub spdx: String,
    /// The notice the apps' attribution screen shows
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attribution: Option<String>,
    /// The licence text at the pinned revision
    pub source: String,
    /// Restrictive or undisclosed terms of the training data, reviewed before 1.0
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data_caveat: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct File {
    pub name: String,
    pub sha256: String,
    pub size: u64,
    pub targets: Vec<Target>,
    /// Where to download it, tried in order; none for a bring-your-own model
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub urls: Vec<String>,
    /// What the ML role's self-test runs (ADR-0245); a file without it runs on the CPU only
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub golden: Option<Golden>,
}

/// A deterministic input and its fp32 outputs on ONNX Runtime's CPU, as `app/packages/photolib_ml` makes them.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Golden {
    /// What the model takes
    pub inputs: Vec<GoldenInput>,
    /// The outputs compared, one after another
    pub outputs: Vec<String>,
    /// At most 1,024 evenly spaced values of those outputs
    pub sample: Vec<f32>,
}

/// An input tensor of a golden.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GoldenInput {
    /// The model's name for it
    pub name: String,
    /// Its dimensions
    pub shape: Vec<i64>,
    /// Its values
    pub fill: Fill,
}

/// How a golden input's values are made.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Fill {
    /// The synthetic picture of `photolib_ml::picture`, times the first value plus the second
    Picture([f32; 2]),
    /// Token ids, then zeros
    Tokens(Vec<i64>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Target {
    Server,
    Android,
    Ios,
    Macos,
    Windows,
    Linux,
    Web,
}

impl Target {
    /// The server and every device: what `photolibd models fetch` installs, so that devices download from it.
    pub const ALL: [Self; 7] = [
        Self::Server,
        Self::Android,
        Self::Ios,
        Self::Macos,
        Self::Windows,
        Self::Linux,
        Self::Web,
    ];
}

/// Design 09 §12.1's licence classes: only the first two may be in the registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Class {
    Permissive,
    Attribution,
    Copyleft,
    Restricted,
}

impl Licence {
    /// An SPDX id this does not know is restricted, so that a custom licence never passes by accident.
    pub fn class(&self) -> Class {
        match self.spdx.as_str() {
            "Apache-2.0" | "MIT" | "BSD-2-Clause" | "BSD-3-Clause" | "CC0-1.0" | "ISC" => Class::Permissive,
            "CC-BY-3.0" | "CC-BY-4.0" => Class::Attribution,
            spdx if ["GPL-", "AGPL-", "LGPL-", "MPL-", "CC-BY-SA-"]
                .iter()
                .any(|prefix| spdx.starts_with(prefix)) =>
            {
                Class::Copyleft
            }
            _ => Class::Restricted,
        }
    }
}

/// Weights that design 09 §2.1 excludes whatever licence an entry records: their code is often permissive where the
/// weights are not (InsightFace's code is MIT, its models non-commercial).
const EXCLUDED: &str = "insightface buffalo antelopev2 edgeface adaface jina-clip nllb-clip metaclip mobileclip rmbg \
    codeformer gfpgan depth-anything-v2-base depth-anything-v2-large megadescriptor clip-iqa qwen2.5-vl gemma-3 surya \
    ultralytics yoloe yolov5-face yolo-world";

/// `[a-z0-9]` then `[a-z0-9._-]`, plus `+` and capitals where `loose`: safe as a file name, never `..` or `@`.
fn plain(name: &str, loose: bool) -> bool {
    let ok = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit() || (loose && (c.is_ascii_uppercase() || c == '+'));
    name.starts_with(ok) && name.chars().all(|c| ok(c) || matches!(c, '.' | '_' | '-'))
}

fn hex(s: &str, len: usize) -> bool {
    s.len() == len && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

fn pinned(url: &str) -> bool {
    url.starts_with("https://") && url.split('/').any(|part| hex(part, 40))
}

impl Model {
    pub fn name(&self) -> String {
        format!("{}@{}", self.id, self.revision)
    }

    /// What makes this model unusable even as bring-your-own: names that are not plain file names, malformed pins.
    pub fn problems(&self) -> Vec<String> {
        let name = self.name();
        let mut problems = Vec::new();
        if !plain(&self.id, false) {
            problems.push(format!("{name}: the id is not [a-z0-9._-]"));
        }
        if !plain(&self.revision, true) {
            problems.push(format!("{name}: the revision is not [A-Za-z0-9.+_-]"));
        }
        if self.files.is_empty() {
            problems.push(format!("{name}: no files"));
        }
        for (i, file) in self.files.iter().enumerate() {
            let at = format!("{name}: {}", file.name);
            if !plain(&file.name, true) || file.name == "manifest.json" {
                problems.push(format!("{at} is not a plain file name"));
            }
            if self.files[..i].iter().any(|f| f.name == file.name) {
                problems.push(format!("{at} twice"));
            }
            if !hex(&file.sha256, 64) {
                problems.push(format!("{at}: the SHA-256 is not 64 lowercase hex digits"));
            }
            if file.size == 0 {
                problems.push(format!("{at} is empty"));
            }
            if file.targets.is_empty() {
                problems.push(format!("{at} has no targets"));
            }
        }
        problems
    }
}

/// The models in `registry.json`.
pub static REGISTRY: LazyLock<Vec<Model>> =
    LazyLock::new(|| serde_json::from_str(include_str!("../registry.json")).expect("registry.json is valid"));

/// The models `photolibd models fetch <ids>` installs: those named, else every one but the optional.
pub fn selected<'a>(registry: &'a [Model], ids: &[String]) -> Vec<&'a Model> {
    (registry.iter())
        .filter(|m| ids.contains(&m.id) || ids.is_empty() && !m.optional)
        .collect()
}

/// The licence gate: every model must be well-formed, downloadable from pinned URLs and default-eligible.
pub fn gate(models: &[Model]) -> Vec<String> {
    let mut problems = Vec::new();
    for (i, model) in models.iter().enumerate() {
        let name = model.name();
        problems.extend(model.problems());
        if models[..i].iter().any(|m| m.name() == name) {
            problems.push(format!("{name} is listed twice"));
        }
        let licence = &model.licence;
        let class = licence.class();
        if !matches!(class, Class::Permissive | Class::Attribution) {
            problems.push(format!(
                "{name}: {} is {class:?}, not permissive: bring-your-own only",
                licence.spdx
            ));
        }
        if class == Class::Attribution && licence.attribution.is_none() {
            problems.push(format!("{name}: {} but no attribution", licence.spdx));
        }
        let urls = model.files.iter().flat_map(|f| &f.urls);
        for url in std::iter::once(&licence.source).chain(urls.clone()) {
            if !pinned(url) {
                problems.push(format!("{name}: {url} is not pinned to a commit over https"));
            }
        }
        let haystack = std::iter::once(&model.id).chain(urls).map(|s| s.to_lowercase());
        for excluded in haystack.flat_map(|s| EXCLUDED.split_whitespace().filter(move |e| s.contains(e))) {
            problems.push(format!(
                "{name} is excluded: {excluded} weights are bring-your-own only"
            ));
        }
        for file in model.files.iter().filter(|f| f.urls.is_empty()) {
            problems.push(format!("{name}: {} has no URL", file.name));
        }
    }
    problems
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    const COMMIT: &str = "0123456789abcdef0123456789abcdef01234567";

    fn model() -> Model {
        serde_json::from_value(json!({
            "id": "m", "revision": "1", "task": "face_detection",
            "licence": {"spdx": "MIT", "source": format!("https://example.org/m/blob/{COMMIT}/LICENSE")},
            "files": [{"name": "m.onnx", "sha256": "ab".repeat(32), "size": 1, "targets": ["server"],
                       "urls": [format!("https://example.org/m/resolve/{COMMIT}/m.onnx")]}]
        }))
        .unwrap()
    }

    #[test]
    fn the_registry_passes_the_licence_gate_and_covers_every_task() {
        assert_eq!(gate(&REGISTRY), Vec::<String>::new());
        for task in [
            Task::ImageTextEmbedding,
            Task::FaceDetection,
            Task::FaceEmbedding,
            Task::TextDetection,
            Task::TextRecognition,
        ] {
            assert!(REGISTRY.iter().any(|m| m.task == task), "{task:?}");
        }
    }

    #[test]
    fn siglip_2_takes_the_whole_image_as_its_own_processor_does() {
        let siglip = REGISTRY.iter().find(|m| m.id == "siglip2-b16-256").unwrap();
        let whole = Preprocess {
            size: 256,
            mean: [0.5; 3],
            std: [0.5; 3],
            crop: false,
        };
        assert_eq!(siglip.preprocess, Some(whole));
    }

    #[test]
    fn auraface_is_the_optional_face_embedding_for_the_server_and_desktops() {
        let aura = REGISTRY
            .iter()
            .find(|m| m.id == "auraface")
            .expect("AuraFace is in the registry");
        assert_eq!(
            (aura.task, aura.dim, aura.licence.spdx.as_str()),
            (Task::FaceEmbedding, Some(512), "Apache-2.0")
        );
        // (value - 127.5) / 127.5 of an aligned face, as ArcFace models take it
        let scaling = aura.preprocess.as_ref().map(|p| (p.size, p.mean, p.std));
        assert_eq!(scaling, Some((112, [0.5; 3], [0.5; 3])));
        let targets = &aura.files[0].targets;
        assert!(
            targets.contains(&Target::Server) && targets.contains(&Target::Linux),
            "{targets:?}"
        );
        assert!(
            ![Target::Android, Target::Ios, Target::Web]
                .iter()
                .any(|t| targets.contains(t)),
            "261 MB is no phone's"
        );
        // SFace stays the default: the first face embedding of the registry, and the only one `models fetch` installs
        // without being asked for the other.
        let first = REGISTRY.iter().find(|m| m.task == Task::FaceEmbedding).unwrap();
        assert_eq!(first.id, "sface");
        let ids = |wanted: &[&str]| -> Vec<String> {
            let wanted: Vec<String> = wanted.iter().map(ToString::to_string).collect();
            selected(&REGISTRY, &wanted).iter().map(|m| m.id.clone()).collect()
        };
        assert!(aura.optional);
        let defaults = ids(&[]);
        assert!(
            defaults.contains(&"sface".to_string()) && !defaults.contains(&"auraface".to_string()),
            "{defaults:?}"
        );
        assert_eq!(ids(&["auraface"]), ["auraface"]);
        assert_eq!(ids(&["auraface", "yunet"]), ["yunet", "auraface"]);
    }

    #[test]
    fn every_file_the_server_runs_has_a_golden_sample() {
        for model in REGISTRY.iter() {
            for file in model.files.iter().filter(|f| f.targets.contains(&Target::Server)) {
                let golden = file
                    .golden
                    .as_ref()
                    .unwrap_or_else(|| panic!("{} has no golden", file.name));
                assert!((1..=1024).contains(&golden.sample.len()), "{}", file.name);
                assert!(!golden.inputs.is_empty() && !golden.outputs.is_empty(), "{}", file.name);
            }
        }
    }

    #[test]
    fn every_file_a_device_runs_has_a_golden_and_every_embedding_its_input_and_size() {
        for model in REGISTRY.iter() {
            for file in model
                .files
                .iter()
                .filter(|f| f.targets.iter().any(|t| *t != Target::Server))
            {
                assert!(file.golden.is_some(), "{} has no golden", file.name);
            }
            if matches!(
                model.task,
                Task::FaceDetection | Task::TextDetection | Task::TextRecognition
            ) {
                continue;
            }
            let input = model
                .preprocess
                .as_ref()
                .unwrap_or_else(|| panic!("{} has no preprocess", model.id));
            assert!((1..=1024).contains(&input.size), "{}", model.id);
            assert!(input.std.iter().all(|s| *s > 0.0), "{}", model.id);
            let dim = model.dim.unwrap_or_else(|| panic!("{} has no dim", model.id));
            for golden in model.files.iter().filter_map(|f| f.golden.as_ref()) {
                assert_eq!(golden.sample.len(), dim as usize, "{}", model.id);
            }
        }
    }

    #[test]
    fn the_gate_refuses_what_is_not_permissive_pinned_and_well_formed() {
        type Change = fn(&mut Model);
        let cases: &[(Change, &str)] = &[
            (
                |m| m.licence.spdx = "CC-BY-NC-4.0".into(),
                "m@1: CC-BY-NC-4.0 is Restricted",
            ),
            (|m| m.licence.spdx = "LicenseRef-apple-amlr".into(), "Restricted"),
            (|m| m.licence.spdx = "AGPL-3.0-only".into(), "AGPL-3.0-only is Copyleft"),
            (|m| m.id = "insightface-buffalo-l".into(), "excluded: insightface"),
            (
                |m| m.files[0].urls[0] = format!("https://example.org/apple/MobileCLIP-S2/resolve/{COMMIT}/m.onnx"),
                "excluded: mobileclip",
            ),
            (|m| m.licence.spdx = "CC-BY-4.0".into(), "no attribution"),
            (
                |m| m.files[0].urls[0] = "https://example.org/m/resolve/main/m.onnx".into(),
                "not pinned to a commit",
            ),
            (
                |m| m.files[0].urls[0] = format!("http://example.org/{COMMIT}/m.onnx"),
                "not pinned to a commit",
            ),
            (
                |m| m.licence.source = "https://example.org/m".into(),
                "not pinned to a commit",
            ),
            (|m| m.files[0].urls.clear(), "m.onnx has no URL"),
            (|m| m.files[0].sha256 = "AB".repeat(32), "SHA-256"),
            (|m| m.files[0].size = 0, "empty"),
            (|m| m.files[0].targets.clear(), "no targets"),
            (|m| m.files[0].name = "../m.onnx".into(), "not a plain file name"),
            (|m| m.files[0].name = "manifest.json".into(), "not a plain file name"),
            (|m| m.revision = "1/2".into(), "revision"),
            (|m| m.id = "M".into(), "id"),
            (|m| m.files.push(m.files[0].clone()), "m.onnx twice"),
            (|m| m.files.clear(), "no files"),
        ];
        assert_eq!(gate(&[model()]), Vec::<String>::new());
        for (change, expected) in cases {
            let mut m = model();
            change(&mut m);
            let problems = gate(&[m]);
            assert!(
                problems.iter().any(|p| p.contains(expected)),
                "expected '{expected}' in {problems:?}"
            );
        }
        assert!(gate(&[model(), model()]).contains(&"m@1 is listed twice".into()));
    }

    #[test]
    fn attribution_licences_are_eligible_with_their_notice() {
        let mut m = model();
        m.licence.spdx = "CC-BY-4.0".into();
        m.licence.attribution = Some("Parakeet © NVIDIA".into());
        assert_eq!(gate(&[m]), Vec::<String>::new());
    }
}
