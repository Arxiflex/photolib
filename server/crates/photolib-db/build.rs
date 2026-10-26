//! Embeds every `server/migrations/*.sql` in name order, so that a new file needs no registration.
use std::{env, fs, path::Path};

fn main() {
    let dir = Path::new(&env::var("CARGO_MANIFEST_DIR").unwrap()).join("../../migrations");
    println!("cargo::rerun-if-changed={}", dir.display());
    let mut files: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "sql"))
        .collect();
    files.sort();
    let entries: String = files
        .iter()
        .map(|path| {
            let name = path.file_name().unwrap().to_str().unwrap();
            format!("({name:?}, include_str!({:?})),\n", path.canonicalize().unwrap())
        })
        .collect();
    let out = Path::new(&env::var("OUT_DIR").unwrap()).join("migrations.rs");
    fs::write(out, format!("&[\n{entries}]\n")).unwrap();
}
