//! Bundles for air-gapped installs: what `photolibd models import` installs and what it refuses.

use std::{
    fs,
    path::{Path, PathBuf},
};

use common::{file, listing};
use photolib_models::{Imported, Model, Store};
use serde_json::json;
use tar::{Builder, EntryType, Header};

mod common;

type Entries<'a> = &'a [(&'a str, &'a [u8])];

fn url(name: &str) -> String {
    format!("https://example.org/0123456789abcdef0123456789abcdef01234567/{name}")
}

/// `m@1` with `a.onnx` and `b.onnx`.
fn registry() -> Vec<Model> {
    serde_json::from_value(json!([{
        "id": "m", "revision": "1", "task": "face_detection",
        "licence": {"spdx": "MIT", "source": url("LICENSE")},
        "files": [file("a.onnx", b"weights a", "server", &[&url("a.onnx")]),
                  file("b.onnx", b"weights b", "server", &[&url("b.onnx")])]
    }]))
    .unwrap()
}

fn byo(spdx: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "id": "byo", "revision": "1", "task": "face_embedding",
        "licence": {"spdx": spdx, "source": "https://example.org/terms"},
        "files": [file("w.onnx", b"their weights", "server", &[])]
    }))
    .unwrap()
}

fn tar(path: &Path, entries: Entries) -> PathBuf {
    let mut tar = Builder::new(fs::File::create(path).unwrap());
    for (name, data) in entries {
        let mut header = Header::new_gnu();
        header.set_size(data.len() as u64);
        header.set_mode(0o644);
        tar.append_data(&mut header, name, *data).unwrap();
    }
    tar.finish().unwrap();
    path.to_owned()
}

fn manifest(model: &Model) -> Vec<u8> {
    serde_json::to_vec(model).unwrap()
}

#[test]
fn a_bundle_installs_the_files_it_has_once_they_match_the_registry() {
    let dir = tempfile::tempdir().unwrap();
    let registry = registry();
    let bundle = tar(
        &dir.path().join("b.tar"),
        &[
            ("./m@1/manifest.json", &manifest(&registry[0])),
            ("./m@1/a.onnx", b"weights a"),
        ],
    );
    let models = dir.path().join("models");
    assert_eq!(
        Store::new(&models, &registry).import(&bundle, &[]),
        Ok(vec![Imported {
            name: "m@1".into(),
            warning: None
        }])
    );
    assert_eq!(listing(&models), ["m@1/a.onnx", "m@1/manifest.json"]);
    assert_eq!(fs::read(models.join("m@1/a.onnx")).unwrap(), b"weights a");
    let installed = fs::read(models.join("m@1/manifest.json")).unwrap();
    assert_eq!(serde_json::from_slice::<Model>(&installed).unwrap(), registry[0]);
    fs::create_dir(models.join("half@1")).unwrap();
    assert_eq!(
        Store::new(&models, &registry).installed(),
        registry,
        "what has its manifest"
    );
    assert_eq!(Store::new(dir.path().join("none"), &registry).installed(), []);
}

#[test]
fn a_file_that_differs_from_the_registry_installs_nothing_whatever_the_bundle_claims() {
    let dir = tempfile::tempdir().unwrap();
    let registry = registry();
    let mut claimed = registry[0].clone();
    claimed.files[1] = serde_json::from_value(file("b.onnx", b"tampered", "server", &[])).unwrap();
    let claimed = manifest(&claimed);
    let cases: [(Entries, &str); 5] = [
        (
            &[
                ("m@1/manifest.json", &claimed),
                ("m@1/a.onnx", b"weights a"),
                ("m@1/b.onnx", b"tampered"),
            ],
            "m@1: b.onnx does not match its SHA-256 and size",
        ),
        (
            &[
                ("m@1/manifest.json", &claimed),
                ("m@1/a.onnx", b"weights a"),
                ("m@1/extra.bin", b"x"),
            ],
            "m@1: extra.bin is not one of its files",
        ),
        (&[("m@1/a.onnx", b"weights a")], "m@1: no manifest.json"),
        (
            &[("n@1/manifest.json", &claimed), ("n@1/a.onnx", b"weights a")],
            "n@1 holds the manifest of m@1",
        ),
        (&[("m@1/manifest.json", b"{")], "m@1/manifest.json"),
    ];
    let models = dir.path().join("models");
    for (entries, expected) in cases {
        let bundle = tar(&dir.path().join("b.tar"), entries);
        let error = Store::new(&models, &registry).import(&bundle, &[]).unwrap_err();
        assert!(error.contains(expected), "expected '{expected}' in '{error}'");
        assert_eq!(listing(&models), Vec::<String>::new());
    }
}

#[test]
fn a_bring_your_own_model_needs_its_licence_accepted_and_is_imported_with_a_warning() {
    let dir = tempfile::tempdir().unwrap();
    let registry = registry();
    let models = dir.path().join("models");
    let store = Store::new(&models, &registry);
    let manifest = byo("CC-BY-NC-4.0");
    let bundle = tar(
        &dir.path().join("b.tar"),
        &[("byo@1/manifest.json", &manifest), ("byo@1/w.onnx", b"their weights")],
    );
    for accepted in [vec![], vec!["MIT".to_string()]] {
        let error = store.import(&bundle, &accepted).unwrap_err();
        assert!(
            error.contains("byo@1 is bring-your-own")
                && error.contains("CC-BY-NC-4.0 (Restricted)")
                && error.contains("--accept-licence CC-BY-NC-4.0"),
            "{error}"
        );
        assert_eq!(listing(&models), Vec::<String>::new());
    }
    let imported = store.import(&bundle, &["CC-BY-NC-4.0".into()]).unwrap();
    assert_eq!(imported[0].name, "byo@1");
    let warning = imported[0].warning.as_deref().unwrap();
    assert!(
        warning.contains("never downloads it or sends it to devices"),
        "{warning}"
    );
    assert_eq!(listing(&models), ["byo@1/manifest.json", "byo@1/w.onnx"]);
    let installed = fs::read(models.join("byo@1/manifest.json")).unwrap();
    assert_eq!(
        serde_json::from_slice::<Model>(&installed).unwrap(),
        serde_json::from_slice::<Model>(&manifest).unwrap()
    );

    let other = tar(
        &dir.path().join("other.tar"),
        &[
            ("byo@1/manifest.json", &byo("LicenseRef-other")),
            ("byo@1/w.onnx", b"their weights"),
        ],
    );
    let error = store.import(&other, &["LicenseRef-other".into()]).unwrap_err();
    assert!(error.contains("byo@1 is installed with another manifest"), "{error}");
}

#[test]
fn links_absolute_paths_and_parent_directories_are_refused() {
    let dir = tempfile::tempdir().unwrap();
    let registry = registry();
    let path = dir.path().join("b.tar");
    for (name, kind, expected) in [
        (
            &b"m@1/../../evil"[..],
            EntryType::Regular,
            "is not <id>@<revision>/<file>",
        ),
        (b"/m@1/a.onnx", EntryType::Regular, "is not <id>@<revision>/<file>"),
        (b"a.onnx", EntryType::Regular, "is not <id>@<revision>/<file>"),
        (b"m@1/x/a.onnx", EntryType::Regular, "is not <id>@<revision>/<file>"),
        (b"m@1/a.onnx", EntryType::Symlink, "is not a regular file"),
        (b"m@1/a.onnx", EntryType::Link, "is not a regular file"),
    ] {
        let mut tar = Builder::new(fs::File::create(&path).unwrap());
        let mut header = Header::new_old();
        header.as_old_mut().name[..name.len()].copy_from_slice(name);
        header.set_entry_type(kind);
        header.set_size(0);
        header.set_cksum();
        tar.append(&header, &b""[..]).unwrap();
        tar.finish().unwrap();
        drop(tar);
        let error = Store::new(dir.path().join("models"), &registry)
            .import(&path, &[])
            .unwrap_err();
        assert!(error.contains(expected), "expected '{expected}' in '{error}'");
        assert_eq!(listing(dir.path()), ["b.tar"]);
    }
}

#[test]
fn a_tar_of_a_store_is_a_bundle() {
    let dir = tempfile::tempdir().unwrap();
    let registry = registry();
    let bundle = tar(
        &dir.path().join("b.tar"),
        &[
            ("m@1/manifest.json", &manifest(&registry[0])),
            ("m@1/a.onnx", b"weights a"),
            ("m@1/b.onnx", b"weights b"),
        ],
    );
    let first = dir.path().join("first");
    Store::new(&first, &registry).import(&bundle, &[]).unwrap();
    let mut tar = Builder::new(fs::File::create(dir.path().join("store.tar")).unwrap());
    tar.append_dir_all(".", &first).unwrap();
    tar.into_inner().unwrap();
    let second = dir.path().join("second");
    let imported = Store::new(&second, &registry).import(&dir.path().join("store.tar"), &[]);
    assert_eq!(imported.map(|i| i.len()), Ok(1));
    assert_eq!(listing(&second), listing(&first));
}
