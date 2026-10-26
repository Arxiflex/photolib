//! A fake runtime and an installed model, and ONNX Runtime with the registry's models, for tests here and in
//! photolibd.

use std::{
    fs,
    path::{Path, PathBuf},
    time::Duration,
};

use photolib_models::{File, Fill, Golden, GoldenInput, Model, REGISTRY, Target};
use serde_json::{Value, json};

use crate::{Backend, Input, Outputs, Runtime, Session};

/// A runtime whose sessions answer `outputs(backend)` to anything.
pub struct Fake {
    /// What `backends` answers
    pub backends: Vec<Backend>,
    /// What every session of a backend answers, whatever its input
    pub outputs: fn(Backend) -> Result<Vec<f32>, String>,
}

struct FakeSession(Vec<f32>);

impl Session for FakeSession {
    fn batched(&self) -> bool {
        true
    }

    fn run(&mut self, inputs: &[Input]) -> Result<Outputs, String> {
        let n = inputs.first().and_then(|i| i.shape.first()).copied().unwrap_or(1);
        let values = (0..n).flat_map(|_| self.0.clone()).collect();
        Ok(vec![("fc1".into(), values)])
    }
}

impl Runtime for Fake {
    fn backends(&self) -> Vec<Backend> {
        self.backends.clone()
    }

    fn load(&self, _model: &Path, backend: Backend) -> Result<Box<dyn Session>, String> {
        Ok(Box::new(FakeSession((self.outputs)(backend)?)))
    }
}

/// The golden sample of `installed`'s `m.onnx`.
pub const GOLDEN: [f32; 4] = [0.5, -0.25, 1.0, 0.125];

/// `m@1`, installed in a temporary directory with its manifest: `m.onnx` for the server, with a golden if `golden`,
/// and `m_fp16.onnx` for Android.
pub fn installed(golden: bool) -> (tempfile::TempDir, Model) {
    let mut model: Model = serde_json::from_value(json!({
        "id": "m", "revision": "1", "task": "face_embedding",
        "licence": {"spdx": "MIT", "source": "https://example.org/LICENSE"},
        "files": [{"name": "m.onnx", "sha256": "ab".repeat(32), "size": 1, "targets": ["server"]},
                  {"name": "m_fp16.onnx", "sha256": "ab".repeat(32), "size": 1, "targets": ["android"]}]
    }))
    .unwrap();
    if golden {
        model.files[0].golden = Some(Golden {
            inputs: vec![GoldenInput {
                name: "data".into(),
                shape: vec![1, 3, 2, 2],
                fill: Fill::Picture([255.0, 0.0]),
            }],
            outputs: vec!["fc1".into()],
            sample: GOLDEN.to_vec(),
        });
    }
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir(dir.path().join("m@1")).unwrap();
    for file in ["m.onnx", "m_fp16.onnx"] {
        fs::write(dir.path().join("m@1").join(file), b"weights").unwrap();
    }
    fs::write(
        dir.path().join("m@1/manifest.json"),
        serde_json::to_vec(&model).unwrap(),
    )
    .unwrap();
    (dir, model)
}

const RUNTIME: &str = if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
    "ort-linux-arm64"
} else if cfg!(target_os = "macos") {
    "ort-macos-arm64"
} else {
    "ort-linux-x64"
};

fn tools() -> &'static Path {
    Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/../../../tools/ml"))
}

/// The local file of each artefact, downloaded on first use.
fn fetch(names: &[&str]) -> serde_json::Map<String, Value> {
    let mut python = photolib_spawn::tool("python3");
    python.arg(tools().join("fetch.py")).args(names);
    let output = photolib_spawn::output(&mut python, Duration::from_hours(1));
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    serde_json::from_slice(&output.stdout).unwrap()
}

fn first(files: &Value) -> &str {
    files[0].as_str().unwrap()
}

/// The local file of a photograph pinned in `tools/ml/artefacts.json` as a fixture (public domain), downloaded on first
/// use.
pub fn photo(name: &str) -> PathBuf {
    PathBuf::from(first(&fetch(&[name])[name]))
}

/// A registry file that `tools/ml/artefacts.json` does not pin (the optional AuraFace, 261 MB), downloaded from its
/// registry URL into the tools cache once and checked against the registry's SHA-256.
fn download(file: &File) -> PathBuf {
    let cache = std::env::var_os("PHOTOLIB_TOOLS_CACHE").map_or_else(std::env::temp_dir, PathBuf::from);
    let dir = cache.join("ml").join(format!("registry-{}", &file.sha256[..16]));
    let path = dir.join(&file.name);
    if path.is_file() {
        return path;
    }
    fs::create_dir_all(&dir).unwrap();
    let partial = dir.join(format!("{}.part", file.name));
    let mut curl = photolib_spawn::tool("curl");
    curl.args(["--fail", "--location", "--silent", "--show-error", "--output"])
        .arg(&partial)
        .arg(file.urls.first().expect("a registry file has a URL"));
    let output = photolib_spawn::output(&mut curl, Duration::from_hours(1));
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let mut sum = photolib_spawn::tool("sha256sum");
    sum.arg(&partial);
    let output = photolib_spawn::output(&mut sum, Duration::from_mins(10));
    let got = String::from_utf8_lossy(&output.stdout);
    assert!(
        got.starts_with(&file.sha256),
        "{} is not the registry's {}: {got}",
        file.name,
        file.sha256
    );
    fs::rename(partial, &path).unwrap();
    path
}

/// ONNX Runtime's official library and a models directory with registry models' server files and manifests, both
/// pinned in `tools/ml/artefacts.json` and fetched by `tools/ml/fetch.py` (before the gate blocks egress): the face
/// models, and SigLIP 2 (1.5 GB) too with `PHOTOLIB_ML_MODELS=all`. `PHOTOLIB_ML_MODELS=auraface` (or any registry ids,
/// comma separated) adds those, downloaded from the registry when `artefacts.json` does not pin them.
pub fn onnx() -> (PathBuf, tempfile::TempDir, Vec<Model>) {
    let wanted = std::env::var("PHOTOLIB_ML_MODELS").unwrap_or_default();
    let ids: Vec<&str> = wanted.split(',').collect();
    installed_onnx(|m| {
        ids.contains(&"all") || ["yunet", "sface"].contains(&m.id.as_str()) || ids.contains(&m.id.as_str())
    })
}

/// [`onnx`] with PP-OCR's detector and three recognisers (about 190 MB) instead.
pub fn ocr() -> (PathBuf, tempfile::TempDir, Vec<Model>) {
    installed_onnx(|m| m.id.starts_with("ppocr-v5-"))
}

fn installed_onnx(wanted: impl Fn(&Model) -> bool) -> (PathBuf, tempfile::TempDir, Vec<Model>) {
    let models: Vec<Model> = REGISTRY.iter().filter(|m| wanted(m)).cloned().collect();
    let pins: Value = serde_json::from_str(&fs::read_to_string(tools().join("artefacts.json")).unwrap()).unwrap();
    let pins = pins.as_object().unwrap();
    let artefact = |sha256: &str| {
        let pin = pins.iter().find(|(_, pin)| pin["sha256"] == sha256);
        pin.map(|(name, _)| name.as_str())
    };
    let files: Vec<_> = (models.iter())
        .flat_map(|m| {
            m.files
                .iter()
                .filter(|f| f.targets.contains(&Target::Server))
                .map(move |f| (m, f))
        })
        .collect();
    let names: Vec<&str> = std::iter::once(RUNTIME)
        .chain(files.iter().filter_map(|(_, f)| artefact(&f.sha256)))
        .collect();
    let fetched = fetch(&names);
    let dir = tempfile::tempdir().unwrap();
    for (model, file) in files {
        let to = dir.path().join(model.name());
        fs::create_dir_all(&to).unwrap();
        let source = artefact(&file.sha256).map_or_else(|| download(file), |name| PathBuf::from(first(&fetched[name])));
        std::os::unix::fs::symlink(source, to.join(&file.name)).unwrap();
        fs::write(to.join("manifest.json"), serde_json::to_vec(model).unwrap()).unwrap();
    }
    (PathBuf::from(first(&fetched[RUNTIME])), dir, models)
}
