//! The contract of a benchmark binary with tools/perf/instructions.sh, which includes this file: `--list` names the
//! benchmarks, `<name>` runs one, and Callgrind counts only what `measured` runs, not the setup. Without a name
//! (`cargo bench`) each runs once.
use std::{
    fs,
    hint::black_box,
    path::{Path, PathBuf},
};

pub type Bench = (String, Box<dyn Fn()>);

pub fn bench(name: impl Into<String>, run: impl Fn() + 'static) -> Bench {
    (name.into(), Box::new(run))
}

pub fn run(benches: &[Bench]) {
    match std::env::args().nth(1).as_deref() {
        Some("--list") => benches.iter().for_each(|(name, _)| println!("{name}")),
        Some(name) if !name.starts_with('-') => (benches.iter().find(|b| b.0 == name)).expect("no such benchmark").1(),
        _ => benches.iter().for_each(|(_, bench)| bench()),
    }
}

/// Runs `run` twice: first to warm the allocator's caches, as a hot path finds them, else what setup left there would
/// move the count; then counted.
pub fn measured<T>(mut run: impl FnMut() -> T) -> T {
    black_box(run());
    counted(run)
}

/// What Callgrind counts: `run` and everything it calls.
#[inline(never)]
fn counted<T>(mut run: impl FnMut() -> T) -> T {
    black_box(run())
}

/// The folders of the media corpus (testdata/corpus/files), each with the files below it, all sorted.
pub fn corpus(root: &str) -> Vec<(String, Vec<PathBuf>)> {
    (sorted(Path::new(root)).into_iter())
        .map(|dir| (dir.file_name().unwrap().display().to_string(), files(&dir)))
        .collect()
}

fn files(dir: &Path) -> Vec<PathBuf> {
    (sorted(dir).into_iter())
        .flat_map(|path| if path.is_dir() { files(&path) } else { vec![path] })
        .collect()
}

fn sorted(dir: &Path) -> Vec<PathBuf> {
    let mut paths: Vec<_> = (fs::read_dir(dir).unwrap()).map(|e| e.unwrap().path()).collect();
    paths.sort();
    paths
}
