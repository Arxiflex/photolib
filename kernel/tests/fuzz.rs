//! The fuzzer that runs in the gate: every corpus file and every vector's input, mutated the ways damaged files are
//! (bit flips, random bytes, cuts, insertions, copied runs, extreme lengths, splices of another file), through
//! ReadMetadata, whole and in pieces, and EditCopy, and through ResolveCaptureTime, with its other inputs damaged too;
//! and every crypto vector that reads untrusted bytes, with one field of its request damaged the same ways. All of them
//! go through the coverage-guided fuzzer's targets (`fuzz/src/lib.rs`), as does every find of it in `testdata/fuzz`.
//! A panic fails the test, and so do a request for more than the reader may ask, a file that makes the kernel hold more
//! than a few times its size, and damaged authenticated input that passes. Deterministic; FUZZ_ROUNDS and FUZZ_SEED run
//! it longer or elsewhere: `FUZZ_ROUNDS=1000 FUZZ_SEED=7 cargo test --release --test fuzz`.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

#[path = "../fuzz/src/lib.rs"]
mod targets;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use photolib_kernel::proto::kernel::v1::{CallResponse, Method, ResolveCaptureTimeRequest, call_response};
use prost::Message;
use prost::encoding::{WireType, decode_key, decode_varint, encode_key, encode_varint};
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::time::{Duration, Instant};
use std::{fs, path::Path, sync::mpsc, thread};
use targets::Random;

const KERNEL: &str = env!("CARGO_MANIFEST_DIR");

thread_local! {
    /// The heap bytes this thread holds, and their peak.
    static HEAP: Cell<(usize, usize)> = const { Cell::new((0, 0)) };
}

/// The system allocator, counting into `HEAP`: a panic cannot stop running out of memory, so tests bound it.
struct Counting;

fn count(grow: usize, shrink: usize) {
    let (live, peak) = HEAP.get();
    let live = (live + grow).saturating_sub(shrink);
    HEAP.set((live, peak.max(live)));
}

// A test's own allocator cannot be safe Rust: it only counts, and never ships (threat model T13).
#[allow(unsafe_code)]
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        count(layout.size(), 0);
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        count(layout.size(), 0);
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        count(0, layout.size());
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
        count(size, layout.size());
        unsafe { System.realloc(ptr, layout, size) }
    }
}

#[global_allocator]
static COUNTING: Counting = Counting;

/// The most `run` held on the heap at once, beyond what this thread held before.
fn peak_heap(run: impl FnOnce()) -> usize {
    let (before, _) = HEAP.get();
    HEAP.set((before, before));
    run();
    HEAP.get().1 - before
}

/// Damage like real files take, mostly where the metadata is: in the first 4 KiB.
fn mutate(random: &mut Random, seed: &[u8], other: &[u8]) -> Vec<u8> {
    let mut data = seed.to_vec();
    for _ in 0..=random.below(8) {
        let reach = if random.below(4) == 0 {
            data.len()
        } else {
            data.len().min(4096)
        };
        let at = random.below(reach);
        match random.below(8) {
            0 if at < data.len() => data[at] ^= 1 << random.below(8),
            1 if at < data.len() => data[at] = random.below(256) as u8,
            2 => data.truncate(at),
            3 => data.insert(at, random.below(256) as u8),
            4 if at < data.len() => {
                let extreme: [&[u8]; 4] = [&[0xff, 0xff, 0xff, 0xff], &[0, 0, 0, 0], &[0x7f, 0xff], &[0x80, 0]];
                let value = extreme[random.below(4)];
                let end = data.len().min(at + value.len());
                data[at..end].copy_from_slice(&value[..end - at]);
            }
            5 if at < data.len() => {
                let run = data[at..data.len().min(at + 1 + random.below(64))].to_vec();
                let to = random.below(reach);
                data.splice(to..to, run);
            }
            6 if !other.is_empty() => {
                let from = random.below(other.len());
                data.splice(at.min(data.len()).., other[from..].iter().take(256).copied());
            }
            _ => data.truncate(data.len().saturating_sub(random.below(16))),
        }
    }
    data
}

fn rounds() -> usize {
    std::env::var("FUZZ_ROUNDS").map_or(Ok(250), |r| r.parse()).unwrap()
}

fn random() -> Random {
    Random(
        std::env::var("FUZZ_SEED")
            .map_or(Ok(0x2545_f491_4f6c_dd1d), |s| s.parse())
            .unwrap(),
    )
}

/// Runs a target on an input, which must not panic nor make the kernel hold more than `heap` bytes at once.
fn survives(target: targets::Target, input: &[u8], heap: usize, at: &str) {
    let mut held = 0;
    let survived = catch_unwind(AssertUnwindSafe(|| held = peak_heap(|| target(input))));
    assert!(
        survived.is_ok() && held <= heap,
        "{at}: held {held} bytes, input {}",
        BASE64.encode(input)
    );
}

/// What reading a file may hold: buffers and lists the size of the file, never the sizes it declares.
fn file_heap(input: &[u8]) -> usize {
    (32 << 20) + 8 * input.len()
}

/// A file through the coverage-guided fuzzer's targets that read files.
fn read_and_edit(data: &[u8]) {
    targets::read_metadata(data);
    targets::edit_copy(data);
}

#[test]
fn damaged_files_never_crash_the_kernel() {
    let (rounds, mut random) = (rounds(), random());
    let seeds = targets::seeds(Path::new(KERNEL), "read_metadata");
    assert!(seeds.len() > 300, "the corpus is missing");
    for (index, seed) in seeds.iter().enumerate() {
        for round in 0..rounds {
            let other = &seeds[random.below(seeds.len())];
            let data = mutate(&mut random, seed, other);
            let at = format!("seed {index}, round {round}");
            survives(read_and_edit, &data, file_heap(&data), &at);
        }
    }
}

/// The capture-time vectors' requests damaged whole, which reaches host claims and zones, and with their file names
/// and folders damaged as text, through ResolveCaptureTime.
#[test]
fn damaged_requests_never_crash_the_resolver() {
    let (rounds, mut random) = (rounds(), random());
    let requests = targets::seeds(Path::new(KERNEL), "resolve_capture_time");
    for (index, request) in requests.iter().enumerate() {
        for round in 0..rounds {
            let other = &requests[random.below(requests.len())];
            let damaged = mutate(&mut random, request, other);
            let mut renamed = ResolveCaptureTimeRequest::decode(request.as_slice()).unwrap();
            let mut text = |t: &str| String::from_utf8_lossy(&mutate(&mut random, t.as_bytes(), other)).into_owned();
            (renamed.file_name, renamed.folder) = (text(&renamed.file_name), text(&renamed.folder));
            for input in [damaged, renamed.encode_to_vec()] {
                let at = format!("request {index}, round {round}");
                survives(targets::resolve_capture_time, &input, file_heap(&input), &at);
            }
        }
    }
}

/// The edit recipe vectors' requests damaged whole, which reaches stored outputs of every size, steps of every kind and
/// regions of any value, through all five calls.
#[test]
fn damaged_recipes_never_crash_the_kernel() {
    let (rounds, mut random) = (rounds(), random());
    let requests = targets::seeds(Path::new(KERNEL), "edit_recipe");
    assert!(requests.len() >= 8, "the recipe vectors are missing");
    for (index, request) in requests.iter().enumerate() {
        for round in 0..rounds {
            let other = &requests[random.below(requests.len())];
            // The pick byte stays, so that the damage lands in the request.
            let damaged = [&request[..1], &mutate(&mut random, &request[1..], &other[1..])].concat();
            let at = format!("request {index}, round {round}");
            survives(targets::edit_recipe, &damaged, file_heap(&damaged), &at);
        }
    }
}

/// What the coverage-guided fuzzer found (`tools/kernel/fuzz.sh`), minimized into `testdata/fuzz/<target>/`, survives
/// too, within 10 seconds each; a crypto reader may hold what its KDF parameters allow.
#[test]
fn found_inputs_never_crash_the_kernel() {
    for (name, target) in targets::TARGETS {
        let Ok(found) = fs::read_dir(Path::new(KERNEL).join("../testdata/fuzz").join(name)) else {
            continue;
        };
        for path in found.map(|entry| entry.unwrap().path()) {
            let input = fs::read(&path).unwrap();
            let heap = if name == "crypto_readers" {
                usize::MAX
            } else {
                file_heap(&input)
            };
            let (done, wait) = mpsc::channel();
            let at = path.display().to_string();
            thread::spawn(move || {
                survives(target, &input, heap, &at);
                done.send(()).unwrap();
            });
            match wait.recv_timeout(Duration::from_secs(10)) {
                Ok(()) => {}
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    panic!("{} takes over 10 s", path.display())
                }
                Err(_) => panic!("{} failed", path.display()),
            }
        }
    }
}

/// Inputs crafted to make a careless parser quadratic, loop or allocate what lengths and counts in the file declare take
/// a moment and a few megabytes; each would take minutes or gigabytes if it did.
#[test]
fn crafted_inputs_stay_fast_and_small() {
    let xmp = |body: String| {
        format!(r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">{body}</rdf:RDF></x:xmpmeta>"#)
            .into_bytes()
    };
    let keywords: String = (0..50_000).map(|i| format!("<rdf:li>a|{i}</rdf:li>")).collect();
    let namespaces: String = (0..30_000).map(|i| format!(r#" xmlns:p{i}="u{i}""#)).collect();
    let elements: String = (0..60_000).map(|i| format!("<p{i}:e/>")).collect();
    let bx = |kind: &[u8], payload: &[u8]| [&(8 + payload.len() as u32).to_be_bytes()[..], kind, payload].concat();
    let properties: Vec<u8> = (0..32_000).flat_map(|_| bx(b"irot", &[1])).collect();
    // A thousand other items' associations first, then the primary item 1's, with two-byte indices.
    let entries: Vec<usize> = (0..1000)
        .map(|_| 2)
        .chain((0..32_000_usize.div_ceil(255)).map(|_| 1))
        .collect();
    let mut ipma = [&[0, 0, 0, 1][..], &(entries.len() as u32).to_be_bytes()].concat();
    for (entry, item) in entries.into_iter().enumerate() {
        ipma.extend([0, item as u8, 255]);
        ipma.extend((1..=255).flat_map(|i| ((entry * 255 + i) as u16 & 0x7fff).to_be_bytes()));
    }
    let iprp = bx(b"iprp", &[bx(b"ipco", &properties), bx(b"ipma", &ipma)].concat());
    let heif = |boxes: &[Vec<u8>]| {
        let meta = [&[0; 4][..], &bx(b"pitm", &[0, 0, 0, 0, 0, 1]), &boxes.concat()].concat();
        [bx(b"ftyp", b"heic\0\0\0\0mif1"), bx(b"meta", &meta)].concat()
    };
    // Item 2 is the Exif item; iloc version 0 locates `items` items from 2 on, each in `extents` extents of `length`
    // bytes at offset 0, without offset and base offset fields, nor length fields when the length is 0.
    let exif = bx(
        b"iinf",
        &[&[0, 0, 0, 0, 0, 1][..], &bx(b"infe", b"\x02\0\0\0\0\x02\0\0Exif\0")].concat(),
    );
    let iloc = |items: u16, extents: u16, length: u32| {
        let mut iloc = [&[0, 0, 0, 0, u8::from(length > 0) * 4, 0][..], &items.to_be_bytes()].concat();
        for id in 2..items + 2 {
            iloc.extend([&id.to_be_bytes()[..], &[0, 0], &extents.to_be_bytes()].concat());
            if length > 0 {
                iloc.extend((0..extents).flat_map(|_| length.to_be_bytes()));
            }
        }
        bx(b"iloc", &iloc)
    };
    // IFD0 claims 65,535 entries and lists 4,096: a reduced image whose eight SubIFDs, EXIF and GPS IFDs and next IFD
    // are all IFD0 itself, and text of 4 GiB.
    let mut tiff = b"II*\0\x08\0\0\0\xff\xff".to_vec();
    let subs = 10 + 4096 * 12 + 4;
    for (tag, kind, count, value) in [
        (0x00fe_u16, 4_u16, 1_u32, 1_u32),
        (0x014a, 4, 8, subs),
        (0x8769, 4, 1, 8),
        (0x8825, 4, 1, 8),
    ]
    .into_iter()
    .chain((0..4092).map(|i| (0x010f + i, 2, u32::MAX, 8)))
    {
        tiff.extend(
            [
                &tag.to_le_bytes()[..],
                &kind.to_le_bytes(),
                &count.to_le_bytes(),
                &value.to_le_bytes(),
            ]
            .concat(),
        );
    }
    tiff.extend((0..9).flat_map(|_| 8_u32.to_le_bytes()));
    for (name, data) in [
        (
            "50,000 hierarchical keywords",
            xmp(format!(
                r#"<rdf:Description xmlns:lr="http://ns.adobe.com/lightroom/1.0/"><lr:hierarchicalSubject><rdf:Bag>{keywords}</rdf:Bag></lr:hierarchicalSubject></rdf:Description>"#
            )),
        ),
        (
            "60,000 namespaces in scope",
            xmp(format!("<rdf:Description{namespaces}>{elements}</rdf:Description>")),
        ),
        ("32,000 properties of one HEIF item", heif(&[iprp])),
        ("TIFF IFDs that point back at IFD0", tiff),
        (
            "an Exif item of 4,096 extents of the same 64 KiB",
            [
                heif(&[exif.clone(), iloc(1, 4096, 1 << 16)]),
                bx(b"mdat", &[0; 1 << 16]),
            ]
            .concat(),
        ),
        (
            "1,024 HEIF items of 65,535 empty extents",
            heif(&[exif, iloc(1024, 65_535, 0)]),
        ),
    ] {
        let start = Instant::now();
        survives(read_and_edit, &data, file_heap(&data), name);
        assert!(
            start.elapsed() < Duration::from_secs(5),
            "{name} took {:?}",
            start.elapsed()
        );
    }
}

/// The length-delimited fields of a message: field number, where its key starts, and its bytes.
fn byte_fields(message: &[u8]) -> Vec<(u32, usize, std::ops::Range<usize>)> {
    let (mut buf, mut fields) = (message, vec![]);
    while !buf.is_empty() {
        let key = message.len() - buf.len();
        let (field, wire) = decode_key(&mut buf).unwrap();
        let value = decode_varint(&mut buf).unwrap() as usize;
        if wire == WireType::LengthDelimited {
            let at = message.len() - buf.len();
            fields.push((field, key, at..at + value));
            buf = &buf[value..];
        }
    }
    fields
}

#[test]
fn damaged_crypto_inputs_never_crash_the_kernel_nor_pass() {
    let (rounds, mut random) = (rounds() / 5, random());
    let cases = targets::reader_cases();
    let mut fuzzed = 0;
    for case in cases {
        let (_, authenticated) = targets::READERS.iter().find(|(m, _)| *m as u32 == case.method).unwrap();
        let (method, request) = (case.method, &case.request);
        let fields = byte_fields(request);
        for round in 0..rounds.min(fields.len() * rounds) {
            let (field, key, value) = fields[random.below(fields.len())].clone();
            let other = &cases[random.below(cases.len())].request;
            let damaged = mutate(&mut random, &request[value.clone()], other);
            let mut rebuilt = request[..key].to_vec();
            encode_key(field, WireType::LengthDelimited, &mut rebuilt);
            encode_varint(damaged.len() as u64, &mut rebuilt);
            rebuilt.extend([&damaged[..], &request[value.end..]].concat());
            let answer = catch_unwind(|| case.keyring().call(method, &rebuilt));
            let at = format!("{} round {round}: {}", case.name, BASE64.encode(&rebuilt));
            let answer = answer.unwrap_or_else(|_| panic!("{at}: the kernel panicked"));
            let passed = matches!(
                CallResponse::decode(answer.as_slice()).unwrap().result,
                Some(call_response::Result::Response(_))
            );
            // Without KE2 or KE3, OPAQUE's calls take the first step.
            let first_step = damaged.is_empty()
                && [Method::OpaqueLogin, Method::OpaqueServerLogin]
                    .map(|m| m as u32)
                    .contains(&method);
            let changed = damaged != request[value] && !first_step;
            assert!(!(passed && changed && authenticated.contains(&field)), "{at}: passed");
            fuzzed += 1;
        }
    }
    assert!(fuzzed > 1000, "only {fuzzed} damaged requests");
}
