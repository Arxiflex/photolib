//! The kernel's hot paths in CPU instructions, which Callgrind counts the same on any machine however loaded
//! (tools/perf/instructions.sh, ADR-0048).
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

#[path = "../../tools/perf/harness.rs"]
mod harness;

use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use harness::{bench, corpus, measured, run};
use photolib_kernel::proto::kernel::v1::{
    CallResponse, DecryptBlobRequest, DevelopRequest, EncryptBlobRequest, EncryptBlobResponse, FileRange, Image,
    ImportKeyRequest, Method, ParseQueryRequest, ReadMetadataRequest, ResolveCaptureTimeRequest, call_response,
};
use photolib_kernel::{Keyring, call};
use prost::Message;
use serde_json::Value;
use std::{fs, hint::black_box};

const KERNEL: &str = env!("CARGO_MANIFEST_DIR");

fn main() {
    let mut benches = vec![
        bench("call", || drop(measured(|| call(0, &[])))),
        bench("encrypt-1mib", || {
            let (mut keys, request) = sealing();
            measured(|| keys.call(Method::EncryptBlob as u32, &request));
        }),
        bench("decrypt-1mib", decrypt),
        bench("capture-time", || {
            // A 64 KiB file head, as a client reads one.
            let mut request: ResolveCaptureTimeRequest = vector("capture_time", "EXIF with sub-seconds and an offset");
            request.head.resize(64 << 10, 0);
            calls(Method::ResolveCaptureTime, &[request.encode_to_vec()]);
        }),
        bench("parse-query", || {
            let query = r#"(anna OR ben) "happy birthday" tag:beach -has:gps"#.into();
            calls(Method::ParseQuery, &[ParseQueryRequest { query }.encode_to_vec()]);
        }),
        bench("develop-256px", || {
            let mut request: DevelopRequest = vector("develop", "every adjustment");
            let rgba = (0..256 * 256 * 4).map(|i| (i * 7 % 251) as u8).collect();
            request.image = Some(Image {
                width: 256,
                height: 256,
                rgba,
            });
            calls(Method::Develop, &[request.encode_to_vec()]);
        }),
    ];
    // ReadMetadata on every file of each corpus folder, whole, so that a slower format shows in its folder.
    for (folder, paths) in corpus(&format!("{KERNEL}/../testdata/corpus/files")) {
        benches.push(bench(format!("read-metadata-{folder}"), move || {
            let requests: Vec<_> = (paths.iter().map(|path| fs::read(path).unwrap()))
                .map(|data| ReadMetadataRequest {
                    size: data.len() as u64,
                    ranges: vec![FileRange { offset: 0, data }],
                })
                .map(|request| request.encode_to_vec())
                .collect();
            calls(Method::ReadMetadata, &requests);
        }));
    }
    run(&benches);
}

fn calls(method: Method, requests: &[Vec<u8>]) {
    measured(|| {
        for request in requests {
            black_box(call(method as u32, request));
        }
    });
}

/// A keyring holding key 1 and the request that seals 1 MiB with it, as an original in sixteen 64 KiB chunks.
fn sealing() -> (Keyring, Vec<u8>) {
    let mut keys = Keyring::default();
    let key = ImportKeyRequest { secret: vec![7; 32] };
    keys.call(Method::ImportKey as u32, &key.encode_to_vec());
    let request = EncryptBlobRequest {
        key: 1,
        kind: 1,
        salt: vec![5; 32],
        plaintext: (0..1 << 20).map(|i| (i % 251) as u8).collect(),
        ..Default::default()
    };
    (keys, request.encode_to_vec())
}

/// Opens 1 MiB as a stream of its chunks, as apps and the viewer read originals and video.
fn decrypt() {
    let (mut keys, request) = sealing();
    let answer = CallResponse::decode(&*keys.call(Method::EncryptBlob as u32, &request)).unwrap();
    let Some(call_response::Result::Response(bytes)) = answer.result else {
        panic!("{answer:?}")
    };
    let envelope = EncryptBlobResponse::decode(&*bytes).unwrap().envelope;
    let open = DecryptBlobRequest {
        key: 1,
        kind: 1,
        ..Default::default()
    }
    .encode_to_vec();
    measured(|| {
        let mut stream = keys.open_stream(Method::DecryptBlob as u32, &open);
        for piece in envelope.chunks(65552) {
            black_box(stream.push(piece));
        }
        stream.finish()
    });
}

/// The request of the named case of `kernel/testvectors/<file>.json`.
fn vector<M: Message + Default>(file: &str, name: &str) -> M {
    let path = format!("{KERNEL}/testvectors/{file}.json");
    let vectors: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    let case = (vectors["cases"].as_array().unwrap().iter())
        .find(|case| case["name"] == name)
        .expect(name);
    M::decode(&*BASE64.decode(case["request"].as_str().unwrap()).unwrap()).unwrap()
}
