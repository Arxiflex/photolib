use std::{fs, path::Path, process::Command};

fn synthlib(args: &[&str]) -> (Option<i32>, String) {
    let out = Command::new(env!("CARGO_BIN_EXE_synthlib")).args(args).output().unwrap();
    (out.status.code(), String::from_utf8(out.stderr).unwrap())
}

#[test]
fn writes_a_library_with_a_manifest_and_refuses_to_mix_two() {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("cli");
    let _ = fs::remove_dir_all(&dir);
    let out = dir.to_str().unwrap();
    let (code, err) = synthlib(&["--assets", "2k", "--seed", "5", "--shape", "one-day", "--out", out]);
    assert_eq!(code, Some(0), "{err}");
    let manifest = fs::read_to_string(dir.join("manifest.json")).unwrap();
    let want = [r#""seed": 5"#, r#""assets": 2000"#, r#""shape": "one-day""#];
    assert!(want.iter().all(|w| manifest.contains(w)), "{manifest}");
    for table in ["users", "people", "assets", "stacks", "albums", "album_items", "album_members", "faces"] {
        let rows = fs::read_to_string(dir.join(format!("{table}.csv"))).unwrap().lines().count() - 1;
        assert!(manifest.contains(&format!(r#""{table}": {rows}"#)), "{table}: {rows} rows; {manifest}");
    }
    let (code, err) = synthlib(&["--assets", "2k", "--out", out]);
    assert!(code == Some(1) && err.contains("not empty"), "{code:?} {err}");
    fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn rejects_bad_arguments_with_usage() {
    for args in [
        &["--assets", "lots", "--out", "x"][..],
        &["--assets", "1k"],
        &["--out", "x"],
        &["--colour", "red"],
        &["--assets", "1k", "--out", "x", "--shape", "round"],
    ] {
        let (code, err) = synthlib(args);
        assert!(code == Some(2) && err.contains("usage: synthlib"), "{args:?}: {code:?} {err}");
    }
}
