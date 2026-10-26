//! The server's hot paths in CPU instructions, which Callgrind counts the same on any machine however loaded
//! (tools/perf/instructions.sh, ADR-0048): what ingest does with every uploaded file (ADR-0066).

#[path = "../../../../tools/perf/harness.rs"]
mod harness;

use harness::{bench, corpus, measured, run};
use photolib_server::ingest::{
    extract::{Extraction, extract},
    group::{Part, group},
    sniff::{Media, sniff},
};
use photolib_storage::Hash;
use std::{fs::File, os::unix::fs::FileExt, path::PathBuf};

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../testdata/corpus/files");

fn main() {
    let mut benches = vec![bench("hash-1mib", || {
        let upload: Vec<u8> = (0..1 << 20).map(|i| (i % 251) as u8).collect();
        measured(|| Hash::of(&upload));
    })];
    let folders = corpus(CORPUS);
    for (folder, paths) in folders.clone() {
        benches.push(bench(format!("ingest-{folder}"), move || {
            let files: Vec<_> = paths.iter().map(open).collect();
            measured(|| files.iter().map(read).count());
        }));
    }
    // One batch of the whole corpus, Live Photos and RAW pairs among the rest.
    benches.push(bench("group-corpus", move || {
        let files: Vec<_> = folders.iter().flat_map(|f| &f.1).map(open).collect();
        let reads: Vec<_> = files.iter().map(read).collect();
        let parts: Vec<_> = (files.iter().zip(&reads))
            .map(|((_, _, path), (media, extraction))| Part {
                path,
                media: *media,
                extraction,
            })
            .collect();
        measured(|| group(&parts).unwrap());
    }));
    run(&benches);
}

/// A file, its size and its path below the corpus, as an upload names it.
fn open(path: &PathBuf) -> (File, u64, String) {
    let file = File::open(path).unwrap();
    let size = file.metadata().unwrap().len();
    (file, size, path.strip_prefix(CORPUS).unwrap().display().to_string())
}

/// What ingest reads of a file: its format by its first bytes, then a photo's or video's metadata and capture time with
/// the kernel.
fn read((file, size, path): &(File, u64, String)) -> (Media, Extraction) {
    let mut head = vec![0; (*size).min(4096) as usize];
    file.read_exact_at(&mut head, 0).unwrap();
    let media = sniff(&head);
    let extraction = if media.supported() {
        extract(file, *size, path, 1_767_225_600).unwrap()
    } else {
        Extraction::default()
    };
    (media, extraction)
}
