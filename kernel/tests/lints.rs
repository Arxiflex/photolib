//! The crate's lint policy holds: building it with unsafe code or std I/O fails, and a test with unsafe code too.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

use std::fs;
use std::path::Path;
use std::process::Command;

fn copy_dir(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let path = entry.unwrap().path();
        let target = to.join(path.file_name().unwrap());
        if path.is_dir() {
            if !path.ends_with("target") {
                copy_dir(&path, &target);
            }
        } else {
            fs::copy(&path, &target).unwrap();
        }
    }
}

/// Runs clippy with `args` on a copy of the crate with `canary` appended to `file`; returns whether it passed, and its
/// output.
fn clippy_with(file: &str, canary: &str, args: &[&str]) -> (bool, String) {
    let work = Path::new(env!("CARGO_TARGET_TMPDIR")).join("lint-canary");
    let _ = fs::remove_dir_all(work.join("crate"));
    copy_dir(Path::new(env!("CARGO_MANIFEST_DIR")), &work.join("crate"));
    let file = work.join("crate").join(file);
    fs::write(&file, fs::read_to_string(&file).unwrap_or_default() + canary).unwrap();
    let out = Command::new(env!("CARGO"))
        .args(["clippy", "--offline", "-p", "photolib-kernel", "--target-dir"])
        .arg(work.join("target"))
        .args(args)
        .current_dir(work.join("crate"))
        .output()
        .unwrap();
    (out.status.success(), String::from_utf8_lossy(&out.stderr).into_owned())
}

#[test]
fn unsafe_code_and_std_io_fail_the_build() {
    let lib = |canary| clippy_with("src/lib.rs", canary, &["--lib", "--", "-D", "warnings"]);
    let (passed, out) = lib("\npub fn canary() -> Vec<u8> { std::fs::read(\"x\").unwrap_or_default() }\n");
    assert!(
        !passed && out.contains("disallowed method"),
        "std::fs::read passed the lints:\n{out}"
    );

    let (passed, out) = lib("\n#[allow(unsafe_code)]\npub fn canary() { unsafe {} }\n");
    assert!(
        !passed && out.contains("forbid(unsafe_code)"),
        "unsafe code passed the lints:\n{out}"
    );

    // Tests are no exception (threat model T13): unsafe code fails there too unless it allows it.
    let (passed, out) = clippy_with(
        "tests/canary.rs",
        "#[test]\nfn canary() { unsafe {} }\n",
        &["--test", "canary"],
    );
    assert!(
        !passed && out.contains("usage of an `unsafe` block"),
        "unsafe code in a test passed the lints:\n{out}"
    );
}
