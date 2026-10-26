//! The conformance vectors in testvectors/: the cases they are generated from, and the Rust runner, which runs them
//! as every binding does. After changing or adding a case, run `BLESS=1 cargo test --test vectors` and commit the
//! rewritten files.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

#[path = "support/heif_builder.rs"]
mod builder;
#[path = "vectors/capture_time.rs"]
mod capture_time;
#[path = "vectors/crypto.rs"]
mod crypto;
#[path = "vectors/faces.rs"]
mod faces;
#[path = "vectors/heif.rs"]
mod heif;
#[path = "vectors/metadata.rs"]
mod metadata;
#[path = "vectors/recipe.rs"]
mod recipe;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode, CallResponse, DatabaseKeyResponse, DecryptBlobRequest, DeriveKeyRequest, Develop,
    DevelopRequest, DevelopResponse, DropKeyRequest, EditCopyRequest, EditCopyResponse, EncodeThumbHashRequest,
    EncodeThumbHashResponse, EncryptBlobRequest, EncryptBlobResponse, GainMap, Image, ImportKeyRequest, LivePhotoPair,
    LivePhotoPart, Lut, MapAssetsRequest, MapAssetsResponse, MapCluster, MapFilter, MapIndexBuildRequest,
    MapIndexBuildResponse, MapIndexDropRequest, MapIndexDropResponse, MapQueryRequest, MapQueryResponse, Method,
    PairLivePhotosRequest, PairLivePhotosResponse, ParseQueryRequest, ParseQueryResponse, PrepareImageRequest,
    QueryNode, QueryNodeList, QueryTerm, Rect, ResolveCaptureTimeResponse, call_response, query_node::Node,
};
use photolib_kernel::{Keyring, call};
use prost::Message;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::{fs, path::Path};

const DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/testvectors");

fn files() -> Vec<(String, Value)> {
    let mut files: Vec<_> = fs::read_dir(DIR)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.extension().is_some_and(|e| e == "json"))
        .map(|path| {
            let text = fs::read_to_string(&path).unwrap();
            (path.display().to_string(), serde_json::from_str(&text).unwrap())
        })
        .collect();
    files.sort_by(|a, b| a.0.cmp(&b.0));
    files
}

#[test]
fn vectors_pass() {
    let mut ran = 0;
    for (path, file) in files() {
        for case in file["cases"].as_array().unwrap() {
            let (got, want) = (run(case, &file), expected(case));
            assert!(
                got == want,
                "{path} {}: got {:?}, want {:?}",
                case["name"],
                show(case, &got),
                show(case, &want)
            );
            ran += 1;
        }
    }
    assert!(ran > 0, "no vectors in {DIR}");
}

/// A case runs on a fresh keyring: its setup calls, then its own call, or its stream with one response per piece
/// pushed and one for finishing. A stream case may pin the SHA-256 of its responses rather than list them.
fn run(case: &Value, file: &Value) -> Vec<Vec<u8>> {
    let mut keyring = Keyring::default();
    let mut responses: Vec<_> = steps(case)
        .map(|step| keyring.call(method(step), &bytes(&step["request"])))
        .collect();
    let (method, request) = (method(case), bytes(&case["request"]));
    let Some(pieces) = case.get("stream") else {
        responses.push(keyring.call(method, &request));
        return responses;
    };
    let mut stream = keyring.open_stream(method, &request);
    let mut out: Vec<_> = pieces
        .as_array()
        .unwrap()
        .iter()
        .map(|p| stream.push(&piece(p, file)))
        .collect();
    out.push(stream.finish());
    match case.get("responses_sha256") {
        Some(_) => responses.push(Sha256::digest(out.concat()).to_vec()),
        None => responses.extend(out),
    }
    responses
}

fn expected(case: &Value) -> Vec<Vec<u8>> {
    let mut responses: Vec<_> = steps(case).map(|step| bytes(&step["response"])).collect();
    if let Some(hash) = case.get("responses_sha256") {
        responses.push(hex(hash));
    } else if let Some(steps) = case.get("responses") {
        responses.extend(steps.as_array().unwrap().iter().map(bytes));
    } else {
        responses.push(bytes(&case["response"]));
    }
    responses
}

fn steps(case: &Value) -> impl Iterator<Item = &Value> {
    case.get("setup").and_then(Value::as_array).into_iter().flatten()
}

fn method(step: &Value) -> u32 {
    u32::try_from(step["method"].as_u64().unwrap()).unwrap()
}

/// A piece pushed into a stream: base64, `{"pattern": n}` (byte i = i mod 251) or ranges of one of the file's blobs.
fn piece(piece: &Value, file: &Value) -> Vec<u8> {
    if let Some(n) = piece.get("pattern") {
        return pattern(usize::try_from(n.as_u64().unwrap()).unwrap());
    }
    let Some(name) = piece.get("blob") else {
        return bytes(piece);
    };
    let blob = bytes(&file["blobs"][name.as_str().unwrap()]);
    let range = |r: &Value| r[0].as_u64().unwrap() as usize..r[1].as_u64().unwrap() as usize;
    piece["ranges"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|r| blob[range(r)].to_vec())
        .collect()
}

fn pattern(len: usize) -> Vec<u8> {
    (0..len).map(|i| (i % 251) as u8).collect()
}

fn bytes(value: &Value) -> Vec<u8> {
    BASE64.decode(value.as_str().unwrap()).unwrap()
}

fn hex(value: &Value) -> Vec<u8> {
    let text = value.as_str().unwrap();
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap())
        .collect()
}

/// Responses for a failure message: capture times decoded in full, anything else as its first bytes.
fn show(case: &Value, responses: &[Vec<u8>]) -> Vec<String> {
    let show = |r: &Vec<u8>| match CallResponse::decode(r.as_slice()).map(|r| r.result) {
        Ok(Some(call_response::Result::Response(bytes))) if case["method"] == Method::ResolveCaptureTime as u32 => {
            format!("{:?}", ResolveCaptureTimeResponse::decode(bytes.as_slice()))
        }
        other => format!("{other:?}").chars().take(200).collect(),
    };
    responses.iter().map(show).collect()
}

#[test]
#[allow(clippy::too_many_lines)] // the table of every vector file
fn vectors_are_generated_from_the_cases() {
    let (crypto, blobs) = crypto::cases();
    for (file, description, cases, blobs) in [
        (
            "abi.json",
            "The call ABI: unknown methods, undecodable requests, keyrings, streams.",
            abi_cases(),
            json!(null),
        ),
        (
            "capture_time.json",
            "Capture-time resolution: claims, plausibility, agreement, zones, conflicts and bounds (design doc 13 §4).",
            capture_time::capture_time_cases(),
            json!(null),
        ),
        (
            "crypto.json",
            "Crypto suite v1: the known-answer vectors of testvectors/crypto as kernel calls, and PLB streams.",
            crypto,
            blobs,
        ),
        (
            "filename_patterns.json",
            "Every rule of the file-name registry, F01 to F56, and folder dates (design doc 13 §5).",
            capture_time::filename_cases(),
            json!(null),
        ),
        (
            "heif.json",
            "HEIF stills: where the coded images, their configuration and their transforms are (ADR-0387).",
            heif::heif_cases(),
            json!(null),
        ),
        (
            "live_photo.json",
            "Live Photo pairing (design doc 08 §3.4).",
            live_photo_cases(),
            json!(null),
        ),
        (
            "metadata.json",
            "Embedded metadata: EXIF, XMP and IPTC IIM (design doc 13 §7).",
            metadata::metadata_cases(),
            json!(null),
        ),
        (
            "query.json",
            "Search query parsing (design doc 09 §4.2).",
            query_cases(),
            json!(null),
        ),
        (
            "thumb_hash.json",
            "ThumbHash encoding: the reference implementation's cases of testdata/thumbhash.json (ADR-0070).",
            thumb_hash_cases(),
            json!(null),
        ),
        (
            "develop.json",
            "The editor spike's CPU reference renderer (ADR-0054); its output pins every binding to the same pixels.",
            develop_cases(),
            json!(null),
        ),
        (
            "ml.json",
            "The input of image models (design doc 09 §2.2, ADR-0254); its tensors pin every binding to the same values.",
            prepare_image_cases(),
            json!(null),
        ),
        (
            "map.json",
            "The map index: clusters of a viewport, time and lasso filters, assets of a viewport (design doc 14).",
            map_cases(),
            json!(null),
        ),
        (
            "edit_copy.json",
            "Edited copies of JPEG photos (ADR-0331): lossless turns and crops, and encoded edits.",
            edit_copy_cases(),
            json!(null),
        ),
    ] {
        generated(file, description, &cases, blobs);
    }
    generated("faces.json", faces::DESCRIPTION, &faces::face_cases(), json!(null));
    recipe::generate();
}

fn generated(file: &str, description: &str, cases: &[Value], blobs: Value) {
    let path = Path::new(DIR).join(file);
    let mut doc = json!({"description": description, "cases": cases});
    if !blobs.is_null() {
        doc["blobs"] = blobs;
    }
    let text = serde_json::to_string_pretty(&doc).unwrap() + "\n";
    if std::env::var_os("BLESS").is_some() {
        // Atomically, so that vectors_pass, running alongside, never reads half a file.
        fs::write(path.with_extension("tmp"), &text).unwrap();
        fs::rename(path.with_extension("tmp"), &path).unwrap();
    }
    assert!(
        fs::read_to_string(&path).ok() == Some(text),
        "{file} is stale: run BLESS=1 cargo test --test vectors"
    );
}

type Outcome = Result<Vec<u8>, CallError>;

fn call_case(name: &str, method: u32, request: Vec<u8>, response: Outcome) -> Value {
    json!({"name": name, "method": method, "request": BASE64.encode(request), "response": encode(response)})
}

fn respond(outcome: Outcome) -> Vec<u8> {
    let result = match outcome {
        Ok(response) => call_response::Result::Response(response),
        Err(error) => call_response::Result::Error(error),
    };
    CallResponse { result: Some(result) }.encode_to_vec()
}

fn encode(outcome: Outcome) -> String {
    BASE64.encode(respond(outcome))
}

fn fail(code: CallErrorCode, params: &[(&str, &str)]) -> Outcome {
    let params = params.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect();
    Err(CallError {
        code: code.into(),
        params,
    })
}

fn abi_cases() -> Vec<Value> {
    let parse = Method::ParseQuery as u32;
    let unknown = || fail(CallErrorCode::UnknownMethod, &[]);
    let field = |name| fail(CallErrorCode::InvalidRequest, &[("field", name)]);
    let derive = |key| DeriveKeyRequest {
        key,
        label: "local/cache".into(),
        context: vec![],
    };
    let mut session = crypto::Session::default();
    session.import(&[7; 32]);
    session.step(Method::DropKey, DropKeyRequest { key: 1 }, Ok(vec![]));
    vec![
        call_case("method 0 is no function", 0, vec![], unknown()),
        call_case("the research envelope's method is retired", 1, vec![], unknown()),
        call_case("an unknown method", 99, vec![], unknown()),
        call_case("the largest method id", u32::MAX, vec![], unknown()),
        call_case(
            "a truncated request",
            parse,
            vec![0x0a, 0x05, b'a'],
            fail(CallErrorCode::InvalidRequest, &[]),
        ),
        call_case(
            "a string that is not UTF-8",
            parse,
            vec![0x0a, 0x01, 0xff],
            fail(CallErrorCode::InvalidRequest, &[]),
        ),
        json!({"name": "a function that does not stream", "method": parse, "request": "", "stream": [BASE64.encode("x")],
               "responses": [encode(unknown()), encode(unknown())]}),
        call_case(
            "a key handle the keyring does not hold",
            Method::DeriveKey as u32,
            derive(1).encode_to_vec(),
            field("key"),
        ),
        call_case(
            "a key of 31 bytes",
            Method::ImportKey as u32,
            ImportKeyRequest { secret: vec![7; 31] }.encode_to_vec(),
            field("secret"),
        ),
        session.call("a dropped key is gone", Method::DeriveKey, derive(1), field("key")),
    ]
}

/// Every key the vectors use, and every key they derive, must stay inside the kernel: no response to any vector, nor
/// to thousands of damaged requests, holds 16 consecutive bytes of one, raw or in hex.
#[test]
fn no_response_holds_key_material() {
    let imported = files().into_iter().flat_map(|(_, file)| {
        let cases = file["cases"].as_array().unwrap().clone();
        cases.into_iter().flat_map(|case| {
            let steps: Vec<_> = steps(&case).chain([&case]).cloned().collect();
            steps
                .into_iter()
                .filter(|step| method(step) == Method::ImportKey as u32)
                .map(|step| {
                    ImportKeyRequest::decode(bytes(&step["request"]).as_slice())
                        .unwrap()
                        .secret
                })
        })
    });
    let imported: HashSet<Vec<u8>> = imported.collect();
    let secrets: Vec<_> = crypto::secrets().into_iter().chain(imported.iter().cloned()).collect();
    let hex: Vec<Vec<u8>> = secrets
        .iter()
        .map(|s| s.iter().flat_map(|b| format!("{b:02x}").into_bytes()).collect())
        .collect();
    let windows: HashSet<&[u8]> = secrets.iter().flat_map(|s| s.windows(16)).collect();
    let hex_windows: HashSet<&[u8]> = hex.iter().flat_map(|s| s.windows(32)).collect();
    assert!(windows.len() > 1000, "too few secrets: {}", windows.len());
    let leaks = |method: u32, response: &[u8]| {
        // A database's page key is the one key a response may carry (ADR-0057), and never one the caller imported.
        if method == Method::DatabaseKey as u32
            && let Some(call_response::Result::Response(r)) = CallResponse::decode(response).unwrap().result
            && let Ok(DatabaseKeyResponse { page_key }) = DatabaseKeyResponse::decode(r.as_slice())
        {
            return page_key.len() != 32 || imported.contains(&page_key);
        }
        response.windows(16).any(|w| windows.contains(w)) || response.windows(32).any(|w| hex_windows.contains(w))
    };
    let mut seed = 0x9e37_79b9_7f4a_7c15_u64;
    let mut random = move |below: usize| {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        (seed % below.max(1) as u64) as usize
    };
    for (path, file) in files() {
        for case in file["cases"].as_array().unwrap() {
            for response in run(case, &file) {
                assert!(
                    !leaks(method(case), &response),
                    "{path} {}: key material in a response",
                    case["name"]
                );
            }
            for _ in 0..100 {
                let mut keyring = Keyring::default();
                for step in steps(case) {
                    keyring.call(method(step), &bytes(&step["request"]));
                }
                let mut request = bytes(&case["request"]);
                for _ in 0..=random(3) {
                    let at = random(request.len());
                    match random(3) {
                        0 if at < request.len() => request[at] ^= 1 << random(8),
                        1 => request.truncate(at),
                        _ => request.insert(at.min(request.len()), random(256) as u8),
                    }
                }
                let response = keyring.call(method(case), &request);
                assert!(
                    !leaks(method(case), &response),
                    "{path} {}: key material in {request:?}",
                    case["name"]
                );
            }
        }
    }
}

/// A keyring holding key 1, and what it encrypts as a call and either way as a stream in pieces of `piece` bytes.
struct Blobs(Keyring);

impl Blobs {
    fn new() -> Self {
        let mut keyring = Keyring::default();
        keyring.call(
            Method::ImportKey as u32,
            &ImportKeyRequest { secret: vec![7; 32] }.encode_to_vec(),
        );
        Blobs(keyring)
    }

    fn seal(&mut self, plaintext: &[u8], padded: bool) -> Vec<u8> {
        let seal = EncryptBlobRequest {
            plaintext: plaintext.to_vec(),
            ..sealing(padded)
        };
        let response = response(&self.0.call(Method::EncryptBlob as u32, &seal.encode_to_vec()));
        EncryptBlobResponse::decode(response.as_slice()).unwrap().envelope
    }

    fn stream(&self, method: Method, request: impl Message, input: &[u8], piece: usize) -> Vec<u8> {
        let mut stream = self.0.open_stream(method as u32, &request.encode_to_vec());
        let mut out: Vec<u8> = input.chunks(piece).flat_map(|p| response(&stream.push(p))).collect();
        out.extend(response(&stream.finish()));
        out
    }

    fn open(&self, envelope: &[u8], piece: usize) -> Vec<u8> {
        self.stream(
            Method::DecryptBlob,
            DecryptBlobRequest {
                key: 1,
                kind: 1,
                ..Default::default()
            },
            envelope,
            piece,
        )
    }
}

fn sealing(padded: bool) -> EncryptBlobRequest {
    EncryptBlobRequest {
        key: 1,
        kind: 1,
        padded,
        salt: vec![5; 32],
        ..Default::default()
    }
}

/// A stream gives the bytes a call gives, whatever the pieces: at chunk boundaries and around them, padded or not. From
/// 4 MiB, Padmé's padding spans chunks, which a stream holds back until finishing shows they are padding.
#[test]
fn streams_give_the_same_bytes_whatever_the_split() {
    const C: usize = 1 << 16;
    let mut blobs = Blobs::new();
    for len in [0, 1, C - 1, C, C + 1, 2 * C, (4 << 20) + 1] {
        for padded in [false, true] {
            let (plaintext, envelope) = (pattern(len), blobs.seal(&pattern(len), padded));
            let pieces = [1, 87, 88, C + 15, C + 16, C + 17, envelope.len()];
            for piece in pieces.into_iter().filter(|&p| len <= 2 * C || p > C) {
                let at = format!("{len} bytes, padded {padded}, in pieces of {piece}");
                let sealed = blobs.stream(Method::EncryptBlob, sealing(padded), &plaintext, piece);
                assert!(sealed == envelope, "{at}: encrypted");
                assert!(blobs.open(&envelope, piece) == plaintext, "{at}: decrypted");
            }
        }
    }
}

/// Every run of a four-chunk envelope's chunks opens alone after its header, whatever the pieces (random access).
#[test]
fn any_run_of_chunks_decrypts_alone() {
    const C: usize = 1 << 16;
    let mut blobs = Blobs::new();
    let text = pattern(3 * C + 7);
    let envelope = blobs.seal(&text, false);
    let end_of = |chunk: usize| (88 + chunk * (C + 16)).min(envelope.len());
    for first in 0..4 {
        for end in first + 1..=4 {
            let request = DecryptBlobRequest {
                key: 1,
                kind: 1,
                first_chunk: first as u64,
                more: end < 4,
                ..Default::default()
            };
            let run = [&envelope[..88], &envelope[end_of(first)..end_of(end)]].concat();
            for piece in [1, C + 16, C + 17, run.len()] {
                let out = blobs.stream(Method::DecryptBlob, request.clone(), &run, piece);
                assert!(
                    out == text[first * C..(end * C).min(text.len())],
                    "chunks {first}..{end} in pieces of {piece}"
                );
            }
        }
    }
}

/// A padded envelope whose data holds a long `0x80 ‖ 0*` run streams as fast as one without: the run, which may be the
/// padding, is held back as a count rather than rescanned at every step.
#[test]
fn padding_runs_stream_in_linear_time() {
    let mut blobs = Blobs::new();
    let mut run = pattern(65531);
    run.push(0x80);
    run.resize(16 << 20, 0);
    run.extend([7, 0x80, 0, 0]);
    let mut time = |data: &[u8]| {
        let envelope = blobs.seal(data, true);
        let started = std::time::Instant::now();
        assert!(blobs.open(&envelope, 65552) == data, "the plaintext differs");
        started.elapsed()
    };
    // The fastest of three each, interleaved: a loaded machine stalls any one.
    let plain = pattern(run.len());
    let (mut with_run, mut without) = (std::time::Duration::MAX, std::time::Duration::MAX);
    for _ in 0..3 {
        with_run = with_run.min(time(&run));
        without = without.min(time(&plain));
    }
    assert!(with_run < 3 * without, "{with_run:?} with the run, {without:?} without");
}

fn response(response: &[u8]) -> Vec<u8> {
    match CallResponse::decode(response).unwrap().result {
        Some(call_response::Result::Response(bytes)) => bytes,
        other => panic!("expected a response, got {other:?}"),
    }
}

fn live_photo_cases() -> Vec<Value> {
    let case = |name, files: &[(&str, bool, &str, Option<i64>, u64)], pairs: &[(u32, u32)]| {
        let files = files
            .iter()
            .map(|&(path, video, id, captured_ms, duration_ms)| LivePhotoPart {
                path: path.into(),
                video,
                content_identifier: id.into(),
                captured_ms,
                duration_ms,
            });
        let request = PairLivePhotosRequest { files: files.collect() };
        let pairs = pairs.iter().map(|&(still, video)| LivePhotoPair { still, video });
        let response = PairLivePhotosResponse { pairs: pairs.collect() };
        call_case(
            name,
            Method::PairLivePhotos as u32,
            request.encode_to_vec(),
            Ok(response.encode_to_vec()),
        )
    };
    vec![
        case(
            "equal content identifiers, whatever the names; else folder, name up to the first dot in any case, a clip \
             of at most 4 s within 2 s, the closest still first",
            &[
                ("DCIM/IMG_0001.HEIC", false, "A", Some(0), 0),
                ("Exports/clip.mov", true, "A", None, 9000),
                ("DCIM/IMG_0002.JPG", false, "", Some(10_000), 0),
                ("DCIM/img_0002.mov", true, "", Some(11_500), 4000),
                ("DCIM/PXL_1.jpg", false, "", Some(20_000), 0),
                ("DCIM/PXL_1.heic", false, "B", Some(21_000), 0),
                ("DCIM/PXL_1.MP.mp4", true, "", Some(21_200), 3000),
            ],
            &[(0, 1), (2, 3), (5, 6)],
        ),
        case(
            "no pair: a longer clip, 2.001 s apart, an unknown time, two identifiers, another folder, two stills, the \
             ends of time",
            &[
                ("DCIM/IMG_0003.JPG", false, "", Some(0), 0),
                ("DCIM/IMG_0003.MOV", true, "", Some(0), 4001),
                ("DCIM/IMG_0004.JPG", false, "", Some(0), 0),
                ("DCIM/IMG_0004.MOV", true, "", Some(2001), 3000),
                ("DCIM/IMG_0005.JPG", false, "", None, 0),
                ("DCIM/IMG_0005.MOV", true, "", Some(0), 3000),
                ("DCIM/IMG_0006.HEIC", false, "C", Some(0), 0),
                ("DCIM/IMG_0006.MOV", true, "D", Some(0), 3000),
                ("Other/IMG_0007.JPG", false, "", Some(0), 0),
                ("DCIM/IMG_0007.MOV", true, "", Some(0), 3000),
                ("DCIM/IMG_0008.JPG", false, "E", Some(0), 0),
                ("DCIM/IMG_0008.HEIC", false, "E", Some(0), 0),
                ("DCIM/IMG_0009.JPG", false, "", Some(i64::MIN), 0),
                ("DCIM/IMG_0009.MOV", true, "", Some(i64::MAX), 3000),
            ],
            &[],
        ),
    ]
}

fn query_cases() -> Vec<Value> {
    let node = |node| QueryNode { node: Some(node) };
    let all = |nodes| node(Node::All(QueryNodeList { nodes }));
    let any = |nodes| node(Node::Any(QueryNodeList { nodes }));
    let negated = |term| node(Node::Negated(Box::new(term)));
    let term = |key: &str, value: &str, phrase| {
        node(Node::Term(QueryTerm {
            key: key.into(),
            value: value.into(),
            phrase,
        }))
    };
    let case = |query: &str, root: Option<QueryNode>| {
        let request = ParseQueryRequest { query: query.into() }.encode_to_vec();
        call_case(
            query,
            Method::ParseQuery as u32,
            request,
            Ok(ParseQueryResponse { root }.encode_to_vec()),
        )
    };
    vec![
        case("", None),
        case(
            "tag:beach -has:gps",
            Some(all(vec![
                term("tag", "beach", false),
                negated(term("has", "gps", false)),
            ])),
        ),
        case(
            "(anna OR ben) \"happy birthday\"",
            Some(all(vec![
                any(vec![term("", "anna", false), term("", "ben", false)]),
                term("", "happy birthday", true),
            ])),
        ),
        case("colour:red )", Some(term("", "colour:red", false))),
    ]
}

fn thumb_hash_cases() -> Vec<Value> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../testdata/thumbhash.json");
    let reference: Value = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
    let case = |name: &str, width, height, rgba: Vec<u8>, outcome| {
        let request = EncodeThumbHashRequest { width, height, rgba };
        call_case(name, Method::EncodeThumbHash as u32, request.encode_to_vec(), outcome)
    };
    let mut cases: Vec<Value> = reference["cases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            let hash = BASE64.decode(c["hash"].as_str().unwrap()).unwrap();
            let size = |key: &str| u32::try_from(c[key].as_u64().unwrap()).unwrap();
            case(
                c["name"].as_str().unwrap(),
                size("w"),
                size("h"),
                BASE64.decode(c["rgba"].as_str().unwrap()).unwrap(),
                Ok(EncodeThumbHashResponse { hash }.encode_to_vec()),
            )
        })
        .collect();
    let rgba = fail(CallErrorCode::InvalidRequest, &[("field", "rgba")]);
    cases.push(case("pixels short of the size", 2, 2, vec![0; 15], rgba.clone()));
    cases.push(case("no pixels", 0, 0, vec![], rgba.clone()));
    cases.push(case("over 100 px a side", 101, 1, vec![0; 404], rgba));
    cases
}

/// The renderer's own output, so that every binding is held to the pixels of the Rust build.
fn develop_cases() -> Vec<Value> {
    let image = |width: u32, height: u32| Image {
        width,
        height,
        rgba: (0..width * height)
            .flat_map(|i| [(i * 37) as u8, (i * 11 + 90) as u8, (i * i) as u8, 255])
            .collect(),
    };
    let all = Develop {
        temperature: 0.2,
        tint: -0.3,
        exposure: 0.6,
        contrast: 0.7,
        clarity: 0.8,
        saturation: 0.5,
        lut: Some(Lut {
            size: 2,
            rgb16: [0u16, 0, 0, 65535, 0, 0, 0, 65535, 0, 65535, 65535, 0]
                .iter()
                .chain(&[0, 0, 40000, 65535, 0, 65535, 0, 65535, 65535, 65535, 65535, 65535])
                .flat_map(|v| v.to_le_bytes())
                .collect(),
        }),
        ..Default::default()
    };
    let case = |name: &str, request: DevelopRequest| computed_case(name, Method::Develop, &request);
    let whole = DevelopRequest {
        develop: Some(all.clone()),
        image: Some(image(12, 8)),
        ..Default::default()
    };
    let guide = DevelopResponse::decode(response(&call(Method::Develop as u32, &whole.encode_to_vec())).as_slice())
        .unwrap()
        .guide;
    let gain_map = GainMap {
        image: Some(image(2, 2)),
        max_log2: 2.0,
        gamma: 1.0,
        offset_sdr: 1.0 / 64.0,
        offset_hdr: 1.0 / 64.0,
        hdr_capacity_max: 2.0,
        ..Default::default()
    };
    vec![
        case(
            "a neutral develop",
            DevelopRequest {
                image: Some(image(6, 4)),
                ..Default::default()
            },
        ),
        case("every adjustment", whole.clone()),
        case(
            "a tile with the guide of the whole image",
            DevelopRequest {
                image: Some(image(5, 3)),
                guide,
                full_width: 12,
                full_height: 8,
                tile_x: 7,
                tile_y: 5,
                ..whole
            },
        ),
        case(
            "a gain map recomputed after an edit",
            DevelopRequest {
                develop: Some(Develop {
                    exposure: 1.0,
                    quarter_turns: 1,
                    ..Default::default()
                }),
                image: Some(image(4, 6)),
                gain_map: Some(gain_map),
                ..Default::default()
            },
        ),
        case(
            "an image shorter than its size",
            DevelopRequest {
                image: Some(Image {
                    rgba: vec![0; 7],
                    ..image(2, 1)
                }),
                ..Default::default()
            },
        ),
    ]
}

/// A case whose response is what the Rust build answers.
fn computed_case(name: &str, method: Method, request: &impl Message) -> Value {
    let answer = call(method as u32, &request.encode_to_vec());
    let outcome = match CallResponse::decode(answer.as_slice()).unwrap().result.unwrap() {
        call_response::Result::Response(r) => Ok(r),
        call_response::Result::Error(e) => Err(e),
    };
    call_case(name, method as u32, request.encode_to_vec(), outcome)
}

/// The preprocessing's own output, so that every binding is held to the tensors of the Rust build.
fn prepare_image_cases() -> Vec<Value> {
    let request = |width: u32, height: u32, size: u32| PrepareImageRequest {
        width,
        height,
        rgba: (0..width * height * 4).map(|i| (i * 37 % 251) as u8).collect(),
        size,
        mean: vec![0.5, 0.4, 0.3],
        std: vec![0.5, 0.25, 0.2],
        crop: false,
    };
    let case = |name: &str, request: PrepareImageRequest| computed_case(name, Method::PrepareImage, &request);
    let cropped = |request| PrepareImageRequest { crop: true, ..request };
    vec![
        case("a wide image shrunk whole to the square", request(9, 5, 3)),
        case("a tall image shrunk whole to the square", request(4, 7, 3)),
        case("a wide image shrunk and centre-cropped", cropped(request(9, 5, 3))),
        case("a tall image shrunk and centre-cropped", cropped(request(4, 7, 3))),
        case("a small image enlarged", request(2, 3, 5)),
        case("a small image enlarged and centre-cropped", cropped(request(2, 3, 5))),
        case(
            "an image shorter than its size",
            PrepareImageRequest {
                rgba: vec![0; 7],
                ..request(2, 1, 1)
            },
        ),
        case("no size", request(2, 2, 0)),
    ]
}

/// Copies of a corpus JPEG and of a 16 × 16 crop of it, which keeps the encoded case small.
fn edit_copy_cases() -> Vec<Value> {
    let run = |request: &EditCopyRequest| {
        let answer = call(Method::EditCopy as u32, &request.encode_to_vec());
        match CallResponse::decode(answer.as_slice()).unwrap().result.unwrap() {
            call_response::Result::Response(r) => Ok(r),
            call_response::Result::Error(e) => Err(e),
        }
    };
    let case = |name: &str, request: EditCopyRequest| {
        call_case(name, Method::EditCopy as u32, request.encode_to_vec(), run(&request))
    };
    let original = fs::read(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../testdata/corpus/files/stills/baseline.jpg"
    ))
    .unwrap();
    let edit = |develop: Develop, original: &[u8]| EditCopyRequest {
        original: original.to_vec(),
        develop: Some(develop),
        original_blake3: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262".into(),
        ..Default::default()
    };
    let crop = |x, y, width, height| Some(Rect { x, y, width, height });
    let small = edit(
        Develop {
            crop: crop(0, 0, 16, 16),
            ..Default::default()
        },
        &original,
    );
    let small = EditCopyResponse::decode(run(&small).unwrap().as_slice()).unwrap().jpeg;
    let exposure = Develop {
        exposure: 0.3,
        quarter_turns: 1,
        crop: crop(2, 2, 10, 12),
        ..Default::default()
    };
    let image = Image {
        width: 16,
        height: 16,
        rgba: (0..256u32)
            .flat_map(|i| [(i * 37) as u8, (i * 11 + 90) as u8, (i * i) as u8, 255])
            .collect(),
    };
    let mut cases = vec![
        case(
            "a quarter turn keeps the image data",
            edit(
                Develop {
                    quarter_turns: 1,
                    ..Default::default()
                },
                &original,
            ),
        ),
        case(
            "a mirrored crop keeps whole blocks",
            edit(
                Develop {
                    flip: true,
                    crop: crop(21, 37, 40, 30),
                    ..Default::default()
                },
                &original,
            ),
        ),
        case(
            "an exposure encodes the rendered original",
            EditCopyRequest {
                image: Some(image),
                ..edit(exposure.clone(), &small)
            },
        ),
        case("an exposure without the decoded original", edit(exposure, &small)),
    ];
    cases.extend(recipe::copy_cases(&original, &small));
    cases
}

#[allow(clippy::too_many_lines)] // one table of cases
fn map_cases() -> Vec<Value> {
    // Two photos in Paris (days 1 and 5), one in Lisbon (day 3), one at a position that is not on the map.
    let build = MapIndexBuildRequest {
        latitudes: vec![48.85, 48.86, 38.72, f64::NAN],
        longitudes: vec![2.35, 2.36, -9.14, 0.0],
        times: vec![86_400, 5 * 86_400, 3 * 86_400, 0],
    };
    let built = MapIndexBuildResponse { index: 1, mapped: 3 };
    let setup = json!([{
        "method": Method::MapIndexBuild as u32,
        "request": BASE64.encode(build.encode_to_vec()),
        "response": encode(Ok(built.encode_to_vec())),
    }]);
    let query = |filter: Option<MapFilter>, zoom| MapQueryRequest {
        index: 1,
        west: -180.0,
        south: -85.0,
        east: 180.0,
        north: 85.0,
        zoom,
        filter,
    };
    let with_setup = |mut case: Value| {
        case["setup"] = setup.clone();
        case
    };
    let at = |query: MapQueryRequest, clusters: Vec<MapCluster>| {
        call_case(
            "",
            Method::MapQuery as u32,
            query.encode_to_vec(),
            Ok(MapQueryResponse { clusters }.encode_to_vec()),
        )
    };
    let named = |name: &str, mut case: Value| {
        case["name"] = json!(name);
        with_setup(case)
    };
    // The expected clusters are what the index returns today; the unit tests in tests/cluster.rs check their meaning.
    let mut ring = Keyring::default();
    ring.call(Method::MapIndexBuild as u32, &build.encode_to_vec());
    let expect = |ring: &mut Keyring, request: MapQueryRequest| {
        let bytes = ring.call(Method::MapQuery as u32, &request.encode_to_vec());
        let response = CallResponse::decode(bytes.as_slice()).unwrap();
        let Some(call_response::Result::Response(r)) = response.result else {
            panic!("{response:?}")
        };
        MapQueryResponse::decode(r.as_slice()).unwrap().clusters
    };
    let days = |from, to| MapFilter {
        time_from: from,
        time_to: to,
        polygon: vec![],
    };
    let lasso = MapFilter {
        polygon: vec![40.0, 0.0, 40.0, 5.0, 50.0, 5.0, 50.0, 0.0],
        ..MapFilter::default()
    };
    let mut cases = Vec::new();
    for (name, request) in [
        ("the world at zoom 3: Paris merged, Lisbon alone", query(None, 3)),
        ("zoom 20 separates the Paris photos", query(None, 20)),
        (
            "a time range keeps what was taken in it",
            query(Some(days(Some(2 * 86_400), Some(4 * 86_400))), 20),
        ),
        (
            "a lasso keeps what lies inside its polygon",
            query(Some(lasso.clone()), 20),
        ),
    ] {
        let clusters = expect(&mut ring, request.clone());
        cases.push(named(name, at(request, clusters)));
    }
    let assets = |name: &str, request: MapAssetsRequest, response: MapAssetsResponse| {
        named(
            name,
            call_case(
                "",
                Method::MapAssets as u32,
                request.encode_to_vec(),
                Ok(response.encode_to_vec()),
            ),
        )
    };
    let everywhere = MapAssetsRequest {
        index: 1,
        west: -180.0,
        south: -85.0,
        east: 180.0,
        north: 85.0,
        ..MapAssetsRequest::default()
    };
    cases.push(assets(
        "the assets of a viewport in order, cut by a limit but counted",
        MapAssetsRequest {
            limit: 2,
            ..everywhere.clone()
        },
        MapAssetsResponse {
            assets: vec![0, 1],
            total: 3,
        },
    ));
    cases.push(assets(
        "a lasso and a time range together",
        MapAssetsRequest {
            filter: Some(MapFilter {
                polygon: lasso.polygon,
                time_to: Some(3 * 86_400),
                ..MapFilter::default()
            }),
            ..everywhere
        },
        MapAssetsResponse {
            assets: vec![0],
            total: 1,
        },
    ));
    cases.push(named(
        "a dropped index is gone",
        call_case(
            "",
            Method::MapIndexDrop as u32,
            MapIndexDropRequest { index: 1 }.encode_to_vec(),
            Ok(MapIndexDropResponse {}.encode_to_vec()),
        ),
    ));
    cases.push(named(
        "an index that is not held",
        call_case(
            "",
            Method::MapQuery as u32,
            MapQueryRequest {
                index: 9,
                ..query(None, 3)
            }
            .encode_to_vec(),
            fail(CallErrorCode::InvalidRequest, &[("field", "index")]),
        ),
    ));
    cases.push(named(
        "an odd polygon",
        call_case(
            "",
            Method::MapQuery as u32,
            query(
                Some(MapFilter {
                    polygon: vec![1.0, 2.0, 3.0],
                    ..MapFilter::default()
                }),
                3,
            )
            .encode_to_vec(),
            fail(CallErrorCode::InvalidRequest, &[("field", "filter.polygon")]),
        ),
    ));
    cases.push(call_case(
        "positions and longitudes of different lengths",
        Method::MapIndexBuild as u32,
        MapIndexBuildRequest {
            latitudes: vec![1.0],
            longitudes: vec![],
            times: vec![],
        }
        .encode_to_vec(),
        fail(CallErrorCode::InvalidRequest, &[("field", "longitudes")]),
    ));
    cases.push(call_case(
        "times for some of the assets only",
        Method::MapIndexBuild as u32,
        MapIndexBuildRequest {
            latitudes: vec![1.0, 2.0],
            longitudes: vec![1.0, 2.0],
            times: vec![5],
        }
        .encode_to_vec(),
        fail(CallErrorCode::InvalidRequest, &[("field", "times")]),
    ));
    cases
}
