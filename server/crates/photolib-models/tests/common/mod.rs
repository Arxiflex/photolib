use std::{fs, path::Path};

use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// A registry file entry holding `data`.
pub fn file(name: &str, data: &[u8], target: &str, urls: &[&str]) -> Value {
    json!({"name": name, "sha256": format!("{:x}", Sha256::digest(data)), "size": data.len(), "targets": [target],
           "urls": urls})
}

/// Every file under `dir`, relative to it.
pub fn listing(dir: &Path) -> Vec<String> {
    fn walk(root: &Path, dir: &Path, out: &mut Vec<String>) {
        for entry in fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                walk(root, &path, out);
            } else {
                out.push(path.strip_prefix(root).unwrap().display().to_string());
            }
        }
    }
    let mut out = Vec::new();
    walk(dir, dir, &mut out);
    out.sort();
    out
}
