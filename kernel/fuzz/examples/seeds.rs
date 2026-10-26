//! Writes each target's seeds into `<dir>/<target>/`: `cargo run --example seeds -- <dir>`.
#![allow(clippy::disallowed_methods)]

use std::{env, fs, path::Path};

fn main() {
    let dir = env::args().nth(1).expect("usage: seeds <dir>");
    let kernel = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    for (target, _) in photolib_kernel_fuzz::TARGETS {
        let out = Path::new(&dir).join(target);
        fs::create_dir_all(&out).unwrap();
        for (index, seed) in photolib_kernel_fuzz::seeds(&kernel, target).iter().enumerate() {
            fs::write(out.join(index.to_string()), seed).unwrap();
        }
    }
}
