//! The kernel's fuzz targets (ADR-0036): libFuzzer drives them on the build machine (`tools/kernel/fuzz.sh`), and the
//! gate's `tests/fuzz.rs` runs its damaged inputs and every find minimized into `testdata/fuzz/<target>/` through
//! them. A panic is a find: the kernel's own, an error where a response is due, or a span the reader may not ask for.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use photolib_kernel::proto::kernel::v1::{
    CallResponse, Develop, EditCopyRequest, FileRange, Method, ReadHeifRequest, ReadHeifResponse, ReadMetadataRequest,
    ReadMetadataResponse, Rect, ResolveCaptureTimeRequest, call_response,
};
use photolib_kernel::{Keyring, call};
use prost::Message;
use serde_json::Value;
use std::sync::OnceLock;
use std::{fs, path::Path};

pub type Target = fn(&[u8]);

/// Each target by its name in `cargo fuzz` and `testdata/fuzz`.
pub const TARGETS: [(&str, Target); 5] = [
    ("read_metadata", read_metadata),
    ("edit_copy", edit_copy),
    ("edit_recipe", edit_recipe),
    ("resolve_capture_time", resolve_capture_time),
    ("crypto_readers", crypto_readers),
];

/// ReadMetadata on a file whole and in pieces that its bytes choose, and ResolveCaptureTime on it as a head.
pub fn read_metadata(data: &[u8]) {
    let whole = FileRange {
        offset: 0,
        data: data.to_vec(),
    };
    read(vec![whole], data.len());
    read(pieces(&mut chosen(data), data), data.len());
    let head = ResolveCaptureTimeRequest {
        head: data.to_vec(),
        file_name: "IMG_20190509_154733.jpg".into(),
        ..Default::default()
    };
    response(&call(Method::ResolveCaptureTime as u32, &head.encode_to_vec()));
}

/// EditCopy on a file, turned, mirrored and cropped as its bytes choose: a crop reads its JPEG's blocks, a turn rewrites
/// its EXIF, and either keeps its XMP. Without a decoded original an edit that cannot be lossless fails, as it may.
pub fn edit_copy(data: &[u8]) {
    let random = &mut chosen(data);
    let crop = (random.below(4) != 0).then(|| Rect {
        x: random.below(32) as u32,
        y: random.below(32) as u32,
        width: 1 + random.below(32) as u32,
        height: 1 + random.below(32) as u32,
    });
    let edit = EditCopyRequest {
        original: data.to_vec(),
        develop: Some(Develop {
            quarter_turns: random.below(4) as u32,
            flip: random.below(2) == 1,
            crop,
            ..Default::default()
        }),
        original_blake3: "0".repeat(64),
        ..Default::default()
    };
    call(Method::EditCopy as u32, &edit.encode_to_vec());
}

/// The edit recipe calls on a request the first byte picks: recipes arrive from any client, with the bytes of masks and
/// patches, and every call must answer or fail without a panic and within the memory its input is worth.
pub fn edit_recipe(data: &[u8]) {
    if let Some((&pick, request)) = data.split_first() {
        call(RECIPE_CALLS[usize::from(pick) % RECIPE_CALLS.len()] as u32, request);
    }
}

/// The calls `edit_recipe` picks from.
const RECIPE_CALLS: [Method; 5] = [
    Method::ResolveRecipe,
    Method::CompareRecipes,
    Method::MapRegions,
    Method::RenderRecipe,
    Method::RecipeFromDevelop,
];

/// ResolveCaptureTime on a request, which fails only when it does not decode.
pub fn resolve_capture_time(request: &[u8]) {
    let answer = call(Method::ResolveCaptureTime as u32, request);
    if ResolveCaptureTimeRequest::decode(request).is_ok() {
        response(&answer);
    }
}

/// A crypto reader's vector case, picked by the first byte, on the rest as its request.
pub fn crypto_readers(data: &[u8]) {
    if let Some((&pick, request)) = data.split_first() {
        let cases = reader_cases();
        let case = &cases[usize::from(pick) % cases.len()];
        case.keyring().call(case.method, request);
    }
}

/// The methods that read untrusted bytes, and the fields of their requests that are authenticated input.
pub const READERS: [(Method, &[u32]); 15] = [
    (Method::DecryptBlob, &[4]),
    (Method::UnwrapKey, &[4]),
    (Method::AcceptKey, &[4, 5]),
    (Method::OpenJournalEntry, &[2]),
    (Method::VerifyIdentityLog, &[1, 2]),
    (Method::VerifyMembershipLog, &[2, 3]),
    (Method::OpaqueLogin, &[4]),
    (Method::OpaqueServerLogin, &[7]),
    (Method::OpaqueRegister, &[]),
    (Method::OpaqueServerRegister, &[]),
    (Method::ReadLockbox, &[]),
    (Method::OpenLockbox, &[]),
    (Method::CheckKdfParams, &[]),
    (Method::SealJournalEntry, &[]),
    (Method::ShareKey, &[]),
];

/// A call of `crypto.json`, with the calls that set up its keyring.
pub struct Case {
    pub name: String,
    pub method: u32,
    pub request: Vec<u8>,
    setup: Vec<(u32, Vec<u8>)>,
}

impl Case {
    pub fn keyring(&self) -> Keyring {
        let mut keyring = Keyring::default();
        for (method, request) in &self.setup {
            keyring.call(*method, request);
        }
        keyring
    }
}

/// The calls of `READERS` in `crypto.json`, but streams.
pub fn reader_cases() -> &'static [Case] {
    static CASES: OnceLock<Vec<Case>> = OnceLock::new();
    CASES.get_or_init(|| {
        let file: Value = serde_json::from_str(include_str!("../../testvectors/crypto.json")).unwrap();
        let call = |c: &Value| (c["method"].as_u64().unwrap() as u32, base64(&c["request"]));
        let cases = file["cases"].as_array().unwrap().iter();
        cases
            .filter(|c| c.get("stream").is_none())
            .filter(|c| READERS.iter().any(|r| r.0 as u32 == call(c).0))
            .map(|c| Case {
                name: c["name"].as_str().unwrap().into(),
                method: call(c).0,
                request: call(c).1,
                setup: (c.get("setup").into_iter())
                    .flat_map(|steps| steps.as_array().unwrap().iter().map(call))
                    .collect(),
            })
            .collect()
    })
}

fn base64(value: &Value) -> Vec<u8> {
    BASE64.decode(value.as_str().unwrap()).unwrap()
}

/// What a target starts from, read from the kernel's directory: every corpus file and file in the vectors, the
/// resolver's vector requests, or each crypto reader case's request after its pick.
pub fn seeds(kernel: &Path, target: &str) -> Vec<Vec<u8>> {
    let vectors = |file: &str| -> Vec<Vec<u8>> {
        let text = fs::read_to_string(kernel.join("testvectors").join(file)).unwrap();
        let file: Value = serde_json::from_str(&text).unwrap();
        let cases = file["cases"].as_array().unwrap().iter();
        cases.map(|c| base64(&c["request"])).collect()
    };
    let mut seeds = match target {
        "read_metadata" | "edit_copy" => {
            let (mut seeds, mut dirs) = (vec![], vec![kernel.join("../testdata/corpus/files")]);
            while let Some(dir) = dirs.pop() {
                for path in fs::read_dir(dir).unwrap().map(|e| e.unwrap().path()) {
                    if path.is_dir() {
                        dirs.push(path);
                    } else {
                        seeds.push(fs::read(path).unwrap());
                    }
                }
            }
            for request in vectors("metadata.json") {
                let read = ReadMetadataRequest::decode(request.as_slice()).unwrap();
                seeds.extend(read.ranges.into_iter().map(|r| r.data));
            }
            for request in vectors("capture_time.json") {
                let resolve = ResolveCaptureTimeRequest::decode(request.as_slice()).unwrap();
                seeds.push(resolve.head);
            }
            seeds
        }
        "resolve_capture_time" => [vectors("capture_time.json"), vectors("filename_patterns.json")].concat(),
        "edit_recipe" => {
            let text = fs::read_to_string(kernel.join("testvectors/recipe.json")).unwrap();
            let file: Value = serde_json::from_str(&text).unwrap();
            let pick = |method: u64| RECIPE_CALLS.iter().position(|&m| m as u64 == method).unwrap() as u8;
            (file["cases"].as_array().unwrap().iter())
                .map(|c| [&[pick(c["method"].as_u64().unwrap())][..], &base64(&c["request"])].concat())
                .collect()
        }
        _ => (reader_cases().iter().zip(0..=u8::MAX))
            .map(|(case, pick)| [&[pick][..], &case.request].concat())
            .collect(),
    };
    seeds.sort();
    seeds
}

pub struct Random(pub u64);

impl Random {
    pub fn below(&mut self, n: usize) -> usize {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 % n.max(1) as u64) as usize
    }
}

/// Randomness a file's bytes choose (their FNV-1a hash), so that an input always runs the same way.
fn chosen(data: &[u8]) -> Random {
    let fnv = data.iter().fold(0xcbf2_9ce4_8422_2325, |hash, &b| {
        (hash ^ u64::from(b)).wrapping_mul(0x0100_0000_01b3)
    });
    Random(fnv | 1)
}

/// A file in up to four pieces at their offsets, some of it missing.
fn pieces(random: &mut Random, data: &[u8]) -> Vec<FileRange> {
    let mut cuts: Vec<usize> = (0..random.below(4)).map(|_| random.below(data.len() + 1)).collect();
    cuts.extend([0, data.len()]);
    cuts.sort_unstable();
    cuts.windows(2)
        .filter(|_| random.below(4) != 0)
        .map(|w| FileRange {
            offset: w[0] as u64,
            data: data[w[0]..w[1]].to_vec(),
        })
        .collect()
}

fn response(answer: &[u8]) -> Vec<u8> {
    match CallResponse::decode(answer).unwrap().result {
        Some(call_response::Result::Response(bytes)) => bytes,
        other => panic!("expected a response, got {other:?}"),
    }
}

fn read(ranges: Vec<FileRange>, size: usize) {
    let request = ReadMetadataRequest {
        ranges,
        size: size as u64,
    };
    let answer = call(Method::ReadMetadata as u32, &request.encode_to_vec());
    let got = ReadMetadataResponse::decode(response(&answer).as_slice()).unwrap();
    assert!(got.missing.len() <= 16 && got.missing.iter().all(|span| span.length <= 1 << 22));
    let request = ReadHeifRequest {
        ranges: request.ranges,
        size: request.size,
    };
    let answer = call(Method::ReadHeif as u32, &request.encode_to_vec());
    let got = ReadHeifResponse::decode(response(&answer).as_slice()).unwrap();
    assert!(got.missing.len() <= 16 && got.missing.iter().all(|span| span.length <= 1 << 22));
    let pictures = got.picture.iter().chain(&got.thumbnail);
    let spans = pictures
        .flat_map(|p| p.image.iter().chain(&p.tiles))
        .flat_map(|i| &i.spans);
    assert!(
        spans
            .into_iter()
            .all(|s| request.size == 0 || s.offset.saturating_add(s.length) <= request.size)
    );
}
