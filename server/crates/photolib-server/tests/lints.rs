//! The lint rule of F-13 holds: server code that builds a Connect error, which always carries a message, fails clippy.

use std::{fs, path::Path, time::Duration};

use photolib_spawn::{output, tool};

/// Lints a one-file crate under the server's clippy.toml; returns whether clippy passed, and its output.
fn clippy_with(source: &str) -> (bool, String) {
    let server = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let work = Path::new(env!("CARGO_TARGET_TMPDIR")).join("server-lint-canary");
    // Its own source directory, since checkouts that share a target directory may run this test at the same time.
    let canary = work.join(format!("canary-{}", std::process::id()));
    fs::create_dir_all(canary.join("src")).unwrap();
    for file in ["clippy.toml", "Cargo.lock"] {
        fs::copy(server.join(file), canary.join(file)).unwrap();
    }
    let manifest = "[package]\nname = \"canary\"\nedition = \"2024\"\n\n[workspace]\n\n[dependencies]\n\
                    connectrpc = { version = \"0.9.1\", default-features = false }\n";
    fs::write(canary.join("Cargo.toml"), manifest).unwrap();
    fs::write(canary.join("src/lib.rs"), source).unwrap();
    let out = output(
        tool(env!("CARGO"))
            .args(["clippy", "--offline", "--quiet", "--target-dir"])
            .arg(work.join("target"))
            .args(["--", "-D", "warnings"])
            .current_dir(&canary),
        Duration::from_secs(600),
    );
    fs::remove_dir_all(&canary).unwrap();
    (out.status.success(), String::from_utf8_lossy(&out.stderr).into_owned())
}

#[test]
fn a_connect_error_with_a_message_fails_the_lints() {
    let (passed, out) = clippy_with("pub fn canary() -> connectrpc::ErrorCode { connectrpc::ErrorCode::NotFound }\n");
    assert!(passed, "the canary does not pass without prose:\n{out}");
    for prose in [
        "connectrpc::ConnectError::new(connectrpc::ErrorCode::NotFound, \"no such asset\")",
        "connectrpc::ConnectError::internal(\"the database is down\")",
        "connectrpc::error::ConnectError::unauthenticated(\"sign in first\")",
    ] {
        let (passed, out) = clippy_with(&format!("pub fn canary() -> connectrpc::ConnectError {{ {prose} }}\n"));
        assert!(
            !passed && out.contains("disallowed method"),
            "{prose} passed the lints:\n{out}"
        );
    }
}
