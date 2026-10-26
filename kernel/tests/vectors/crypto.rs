//! The known-answer vectors of crypto suite v1 (testvectors/crypto/*.json, from tools/cryptoref) as kernel calls:
//! each case imports the keys it needs into a fresh keyring, then makes the call the vector describes. Envelopes the
//! vectors pin only by hash are rebuilt by an independent writer and checked against that hash.

use super::{BASE64, Outcome, call_case, fail, hex, pattern, respond};
use base64::Engine as _;
use chacha20poly1305::{AeadInOut, ChaCha20Poly1305, KeyInit, Nonce, Tag};
use hkdf::Hkdf;
use photolib_kernel::proto::kernel::v1::{
    CallErrorCode, CheckKdfParamsRequest, CheckKdfParamsResponse, CodeResponse, DatabaseKeyRequest,
    DatabaseKeyResponse, DecryptBlobRequest, DecryptBlobResponse, DedupTokenRequest, DedupTokenResponse,
    DeriveKeyRequest, DerivePasswordKeyRequest, EncryptBlobRequest, EncryptBlobResponse, EpochCodeRequest,
    ImportKeyRequest, InboxPublicKeyRequest, InboxPublicKeyResponse, KdfPolicy, KeyPair, KeyResponse,
    LinkFragmentRequest, LinkFragmentResponse, LinkKeysRequest, LinkKeysResponse, LockboxSlot, Method,
    OpenJournalEntryRequest, OpenJournalEntryResponse, OpenLockboxRequest, ReadLockboxRequest, ReadLockboxResponse,
    RecoveryKeyRequest, RecoveryPhraseRequest, RecoveryPhraseResponse, SafetyNumberRequest, SealJournalEntryRequest,
    SealJournalEntryResponse, SealLockboxRequest, SealLockboxResponse, UnwrapKeyRequest, WrapContext, WrapKeyRequest,
    WrapKeyResponse,
};
use prost::Message;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};
use std::{fs, path::Path};

#[path = "sharing.rs"]
mod sharing;

const KATS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/testvectors/crypto");
const HEADER: usize = 88;

fn kat(name: &str) -> Value {
    let text = fs::read_to_string(Path::new(KATS).join(format!("{name}.json"))).unwrap();
    serde_json::from_str(&text).unwrap()
}

/// The known-answer vector files, each of which runs as kernel calls.
const FILES: [&str; 9] = [
    "plb", "plw", "plh", "pls", "kdf", "opaque", "lockbox", "journal", "recovery",
];

/// The cases and the blobs (large envelopes) their streams push.
pub fn cases() -> (Vec<Value>, Value) {
    let mut files: Vec<_> = fs::read_dir(KATS)
        .unwrap()
        .map(|f| f.unwrap().path().file_stem().unwrap().to_string_lossy().into_owned())
        .collect();
    files.sort();
    let mut known = FILES.map(String::from).to_vec();
    known.sort();
    assert_eq!(files, known, "a crypto vector file the kernel does not run");
    let (mut cases, mut blobs) = (Vec::new(), Map::new());
    plb(&kat("plb"), &mut cases, &mut blobs);
    plw(&kat("plw"), &mut cases);
    kdf(&kat("kdf"), &mut cases);
    lockbox(&kat("lockbox"), &mut cases);
    journal(&kat("journal"), &mut cases);
    recovery(&kat("recovery"), &mut cases);
    sharing::cases(&mut cases);
    streams(&kat("plb"), &blobs, &mut cases);
    random_access(&kat("plb"), &mut cases);
    (cases, Value::Object(blobs))
}

/// Every secret the known-answer vectors name: keys, seeds, derived keys, Argon2id outputs, randomness. Not a dedup
/// token, which the server stores to compare.
pub fn secrets() -> Vec<Vec<u8>> {
    fn walk(value: &Value, out: &mut Vec<Vec<u8>>) {
        const FIELDS: [&str; 24] = [
            "key",
            "entropy",
            "wrapping_key",
            "ddk",
            "inbox_key",
            "randomness",
            "file_key",
            "secret",
            "hardware",
            "argon2id",
            "output",
            "dedup_key",
            "link_key",
            "link_auth",
            "recipient_seed",
            "eseed",
            "signing_seed",
            "x_wing_seed",
            "oprf_seed",
            "server_private_key",
            "blind_registration",
            "blind_login",
            "client_keyshare_seed",
            "server_keyshare_seed",
        ];
        match value {
            Value::Object(map) => {
                let token = map.get("function").is_some_and(|f| f == "dedup_token");
                for (field, value) in map {
                    match value.as_str() {
                        Some(text)
                            if FIELDS.contains(&field.as_str())
                                && !(token && field == "output")
                                && text.len() >= 64
                                && text.bytes().all(|b| b.is_ascii_hexdigit()) =>
                        {
                            out.push(hex(value))
                        }
                        _ => walk(value, out),
                    }
                }
            }
            Value::Array(items) => items.iter().for_each(|item| walk(item, out)),
            _ => {}
        }
    }
    let mut out = Vec::new();
    for name in FILES {
        walk(&kat(name), &mut out);
    }
    out
}

pub fn key_id(key: &[u8]) -> Vec<u8> {
    let mut id = vec![0; 16];
    Hkdf::<Sha256>::new(None, key)
        .expand(b"photolib/v1/key-id", &mut id)
        .unwrap();
    id
}

/// A case's setup, the keys it imports in handle order, and the call or stream that follows.
#[derive(Default)]
pub struct Session {
    setup: Vec<Value>,
    last: u32,
}

impl Session {
    pub fn import(&mut self, secret: &[u8]) -> u32 {
        let (request, response) = (
            ImportKeyRequest {
                secret: secret.to_vec(),
            },
            self.new_key(secret),
        );
        self.step(Method::ImportKey, request, response);
        self.last += 1;
        self.last
    }

    pub fn step(&mut self, method: Method, request: impl Message, response: Outcome) {
        self.setup
            .push(call_case("", method as u32, request.encode_to_vec(), response));
    }

    /// The response of a call that adds `key` to the keyring.
    fn new_key(&self, key: &[u8]) -> Outcome {
        ok(KeyResponse {
            key: self.last + 1,
            key_id: key_id(key),
        })
    }

    pub fn call(self, name: &str, method: Method, request: impl Message, response: Outcome) -> Value {
        self.with_setup(call_case(name, method as u32, request.encode_to_vec(), response))
    }

    fn stream(self, name: &str, method: Method, request: impl Message, pieces: Value, steps: Vec<Outcome>) -> Value {
        let hash = Sha256::digest(steps.into_iter().map(respond).collect::<Vec<_>>().concat());
        self.with_setup(
            json!({"name": name, "method": method as u32, "request": BASE64.encode(request.encode_to_vec()),
                               "stream": pieces, "responses_sha256": hex_string(&hash)}),
        )
    }

    fn with_setup(self, mut case: Value) -> Value {
        if !self.setup.is_empty() {
            let steps = self.setup.into_iter().map(|mut step| {
                step.as_object_mut().unwrap().remove("name");
                step
            });
            case["setup"] = steps.collect();
        }
        case
    }
}

fn ok(message: impl Message) -> Outcome {
    Ok(message.encode_to_vec())
}

fn hex_string(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn int(value: &Value) -> usize {
    usize::try_from(value.as_u64().unwrap()).unwrap()
}

fn number(value: &Value) -> u32 {
    u32::try_from(int(value)).unwrap()
}

fn rejected(reason: &str) -> Outcome {
    let code = match reason {
        "commitment_mismatch" | "auth_failed" => CallErrorCode::DecryptionFailed,
        _ => CallErrorCode::InvalidInput,
    };
    fail(code, &[("reason", reason)])
}

fn base<'a>(case: &Value, doc: &'a Value) -> Option<&'a Value> {
    doc["valid"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["id"] == case["base"])
}

/// An invalid case's fields: its base valid case's, overridden by its own.
fn merged(case: &Value, doc: &Value) -> Value {
    let mut merged = base(case, doc).cloned().unwrap_or(json!({}));
    for (field, value) in case.as_object().unwrap() {
        merged[field] = value.clone();
    }
    merged
}

/// The invalid cases as calls of `method` with the request `build` makes from their merged fields and session.
fn rejections<M: Message>(
    doc: &Value,
    method: Method,
    build: impl Fn(&Value, &Value, &mut Session) -> M,
) -> Vec<Value> {
    let cases = doc["invalid"].as_array().unwrap().iter();
    cases
        .map(|c| {
            let mut s = Session::default();
            let request = build(c, &merged(c, doc), &mut s);
            s.call(
                c["id"].as_str().unwrap(),
                method,
                request,
                rejected(c["error"].as_str().unwrap()),
            )
        })
        .collect()
}

/// What an invalid case reads: its own `field`, or its base's (`of`) with its mutations applied in order.
fn input(case: &Value, doc: &Value, field: &str, of: impl Fn(&Value) -> Vec<u8>) -> Vec<u8> {
    if let Some(value) = case.get(field) {
        return hex(value);
    }
    let mut data = of(base(case, doc).unwrap());
    for m in case.get("mutations").and_then(Value::as_array).into_iter().flatten() {
        if let Some(offset) = m.get("flip") {
            data[int(offset)] ^= 1;
        } else if let Some(n) = m.get("truncate") {
            data.truncate(int(n));
        } else if let Some(r) = m.get("repeat") {
            let copy = data[int(&r[0])..int(&r[0]) + int(&r[1])].to_vec();
            data.extend(copy);
        } else if let Some(s) = m.get("set") {
            let (offset, value) = (int(&s[0]), hex(&s[1]));
            data[offset..offset + value.len()].copy_from_slice(&value);
        } else if let Some(s) = m.get("swap") {
            let (a, b, n) = (int(&s[0]), int(&s[1]), int(&s[2]));
            let first = data[a..a + n].to_vec();
            data.copy_within(b..b + n, a);
            data[b..b + n].copy_from_slice(&first);
        }
    }
    data
}

/// The same mutations as ranges of the base, for a stream to push from a blob: truncate, swap and repeat.
fn ranges(mutations: &Value, length: usize) -> Value {
    let [m] = mutations.as_array().unwrap().as_slice() else {
        panic!("one mutation per large case")
    };
    let ranges = if let Some(n) = m.get("truncate") {
        vec![[0, int(n)]]
    } else if let Some(s) = m.get("swap") {
        let (a, b, n) = (int(&s[0]), int(&s[1]), int(&s[2]));
        assert!(a + n <= b);
        vec![[0, a], [b, b + n], [a + n, b], [a, a + n], [b + n, length]]
    } else if let Some(r) = m.get("repeat") {
        vec![[0, length], [int(&r[0]), int(&r[0]) + int(&r[1])]]
    } else {
        panic!("no ranges for {m}")
    };
    json!(ranges)
}

// --- PLB

fn plb_cipher(key: &[u8], salt: &[u8]) -> (ChaCha20Poly1305, [u8; 32]) {
    let hkdf = Hkdf::<Sha256>::new(Some(salt), key);
    let (mut payload, mut commitment) = ([0; 32], [0; 32]);
    hkdf.expand(b"photolib/v1/plb/payload", &mut payload).unwrap();
    hkdf.expand(b"photolib/v1/plb/commit", &mut commitment).unwrap();
    (ChaCha20Poly1305::new(&payload.into()), commitment)
}

fn nonce(index: usize, last: bool) -> Nonce {
    let mut nonce = [0; 12];
    nonce[3..11].copy_from_slice(&(index as u64).to_be_bytes());
    nonce[11] = u8::from(last);
    Nonce::from(nonce)
}

/// An independent writer of unpadded envelopes.
pub fn seal(key: &[u8], plaintext: &[u8], kind: u8, salt: &[u8], chunk_log2: u8, typ: u8, flags: u8) -> Vec<u8> {
    let (cipher, commitment) = plb_cipher(key, salt);
    let mut envelope = vec![b'P', b'L', typ, 1, 1, kind, chunk_log2, flags];
    envelope.extend(key_id(key).iter().chain(salt).chain(&commitment));
    let header = envelope.clone();
    let chunks: Vec<_> = plaintext.chunks(1 << chunk_log2).collect();
    let chunks = if chunks.is_empty() { vec![&[][..]] } else { chunks };
    for (i, chunk) in chunks.iter().enumerate() {
        let mut sealed = chunk.to_vec();
        let tag = cipher
            .encrypt_inout_detached(&nonce(i, i + 1 == chunks.len()), &header, sealed.as_mut_slice().into())
            .unwrap();
        envelope.extend(sealed.iter().chain(tag.iter()));
    }
    envelope
}

/// What decrypting `envelope` as a stream in pieces of `lengths` returns, by an independent reader: each push gives
/// the chunks that more bytes now follow, finishing the last; a chunk that fails fails that step and every later one.
fn decrypt_steps(key: &[u8], envelope: &[u8], lengths: &[usize]) -> Vec<Outcome> {
    let header = &envelope[..HEADER];
    let (cipher, _) = plb_cipher(key, &header[24..56]);
    let sealed = (1 << header[6]) + 16;
    let open = |i: usize, last: bool| {
        let chunk = &envelope[HEADER + i * sealed..(HEADER + (i + 1) * sealed).min(envelope.len())];
        let (ciphertext, tag) = chunk.split_at(chunk.len() - 16);
        let mut plaintext = ciphertext.to_vec();
        let tag = Tag::try_from(tag).unwrap();
        cipher
            .decrypt_inout_detached(&nonce(i, last), header, plaintext.as_mut_slice().into(), &tag)
            .ok()
            .map(|()| plaintext)
    };
    let (mut steps, mut total, mut done) = (Vec::new(), 0, 0);
    for length in lengths {
        total += length;
        let ready = if total > HEADER {
            (total - HEADER - 1) / sealed
        } else {
            0
        };
        steps.push(
            (done..ready)
                .map(|i| open(i, false))
                .collect::<Option<Vec<_>>>()
                .map(|p| p.concat()),
        );
        done = ready;
    }
    steps.push(open(done, true));
    let failed = steps.iter().position(Option::is_none).unwrap_or(steps.len());
    (0..steps.len())
        .map(|i| match &steps[i] {
            Some(plaintext) if i < failed => Ok(plaintext.clone()),
            _ => rejected("auth_failed"),
        })
        .collect()
}

/// What encrypting as a stream in pieces of `lengths` returns: the header first, then every chunk that more bytes now
/// follow, finishing the last.
fn encrypt_steps(envelope: &[u8], lengths: &[usize]) -> Vec<Outcome> {
    let size = 1 << envelope[6];
    let (mut steps, mut total, mut at) = (Vec::new(), 0, 0);
    for length in lengths {
        total += length;
        let end = HEADER + total.saturating_sub(1) / size * (size + 16);
        steps.push(Ok(envelope[at..end].to_vec()));
        at = end;
    }
    steps.push(Ok(envelope[at..].to_vec()));
    steps
}

fn plaintext_of(v: &Value) -> Vec<u8> {
    match v.get("plaintext_length") {
        Some(n) => pattern(int(n)),
        None => hex(&v["plaintext"]),
    }
}

fn envelope_of(v: &Value) -> Vec<u8> {
    if let Some(envelope) = v.get("envelope") {
        return hex(envelope);
    }
    let typ = v["type"].as_str().unwrap().as_bytes()[0];
    let (kind, chunk_log2) = (number(&v["kind"]) as u8, number(&v["chunk_log2"]) as u8);
    let envelope = seal(
        &hex(&v["key"]),
        &plaintext_of(v),
        kind,
        &hex(&v["salt"]),
        chunk_log2,
        typ,
        0,
    );
    assert_eq!(
        hex_string(&Sha256::digest(&envelope)),
        v["envelope_sha256"],
        "{}",
        v["id"]
    );
    assert_eq!(envelope.len() as u64, v["envelope_length"].as_u64().unwrap());
    envelope
}

fn plb(doc: &Value, cases: &mut Vec<Value>, blobs: &mut Map<String, Value>) {
    let (encrypt, decrypt) = (Method::EncryptBlob, Method::DecryptBlob);
    for v in doc["valid"].as_array().unwrap() {
        let id = v["id"].as_str().unwrap();
        let (key, plaintext, envelope) = (hex(&v["key"]), plaintext_of(v), envelope_of(v));
        let (kind, manifest, large) = (
            number(&v["kind"]),
            v["type"] == "X",
            v.get("plaintext_length").is_some(),
        );
        let mut s = Session::default();
        let key_handle = s.import(&key);
        let mut request = DecryptBlobRequest {
            key: key_handle,
            kind,
            manifest,
            ..Default::default()
        };
        if large {
            blobs.insert(id.into(), BASE64.encode(&envelope).into());
            let pieces = json!([{"blob": id, "ranges": [[0, envelope.len()]]}]);
            let steps = decrypt_steps(&key, &envelope, &[envelope.len()]);
            cases.push(s.stream(&format!("{id}: decrypt"), decrypt, request, pieces, steps));
        } else {
            request.envelope = envelope.clone();
            let response = ok(DecryptBlobResponse {
                plaintext: plaintext.clone(),
            });
            cases.push(s.call(&format!("{id}: decrypt"), decrypt, request, response));
        }
        if v["chunk_log2"] != 16 {
            continue;
        }
        let mut s = Session::default();
        let mut request = EncryptBlobRequest {
            key: s.import(&key),
            kind,
            manifest,
            padded: v["padded"].as_bool().unwrap(),
            salt: hex(&v["salt"]),
            plaintext: vec![],
        };
        let name = format!("{id}: encrypt");
        if large {
            let steps = encrypt_steps(&envelope, &[plaintext.len()]);
            let pieces = json!([{"pattern": plaintext.len()}]);
            cases.push(s.stream(&name, encrypt, request, pieces, steps));
        } else {
            request.plaintext = plaintext;
            let response = ok(EncryptBlobResponse { envelope });
            cases.push(s.call(&name, encrypt, request, response));
        }
    }
    for c in doc["invalid"].as_array().unwrap() {
        let (id, fields) = (c["id"].as_str().unwrap(), merged(c, doc));
        let envelope = input(c, doc, "envelope", envelope_of);
        let key = hex(&fields["key"]);
        let mut s = Session::default();
        let request = DecryptBlobRequest {
            key: s.import(&key),
            kind: number(fields.get("expected_kind").unwrap_or(&fields["kind"])),
            manifest: fields["type"] == "X",
            ..Default::default()
        };
        let error = rejected(c["error"].as_str().unwrap());
        match base(c, doc).filter(|b| b.get("plaintext_length").is_some()) {
            Some(b) => {
                let pieces = json!([{"blob": b["id"], "ranges": ranges(&c["mutations"], envelope_of(b).len())}]);
                let steps = decrypt_steps(&key, &envelope, &[envelope.len()]);
                assert_eq!(steps.last(), Some(&error), "{id}");
                cases.push(s.stream(id, decrypt, request, pieces, steps));
            }
            None => {
                let request = DecryptBlobRequest { envelope, ..request };
                cases.push(s.call(id, decrypt, request, error));
            }
        }
    }
}

/// Streams in pieces, as the bindings push them: chunk by chunk, after an error, and while encrypting.
fn streams(doc: &Value, blobs: &Map<String, Value>, cases: &mut Vec<Value>) {
    let three = doc["valid"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["id"] == "plb-three-chunks")
        .unwrap();
    let (key, salt) = (hex(&three["key"]), hex(&three["salt"]));
    let envelope = BASE64.decode(blobs["plb-three-chunks"].as_str().unwrap()).unwrap();
    let cuts = [0, 1, HEADER, HEADER + 65552, HEADER + 65553, envelope.len()];
    let lengths: Vec<_> = cuts.windows(2).map(|w| w[1] - w[0]).collect();
    let pieces: Vec<_> = cuts
        .windows(2)
        .map(|w| json!({"blob": "plb-three-chunks", "ranges": [w]}))
        .collect();
    let mut s = Session::default();
    let request = DecryptBlobRequest {
        key: s.import(&key),
        kind: 1,
        ..Default::default()
    };
    cases.push(s.stream(
        "a stream returns each chunk once the next byte shows it is not the last",
        Method::DecryptBlob,
        request,
        json!(pieces),
        decrypt_steps(&key, &envelope, &lengths),
    ));
    let mut s = Session::default();
    let request = DecryptBlobRequest {
        key: s.import(&[9; 32]),
        kind: 1,
        ..Default::default()
    };
    let wrong = rejected("commitment_mismatch");
    cases.push(s.stream(
        "after an error every step repeats it",
        Method::DecryptBlob,
        request,
        json!([{"blob": "plb-three-chunks", "ranges": [[0, 44]]}, {"blob": "plb-three-chunks", "ranges": [[44, 200]]},
               BASE64.encode("")]),
        vec![Ok(vec![]), wrong.clone(), wrong.clone(), wrong],
    ));
    let plaintext = [pattern(65536), pattern(1000)].concat();
    let sealed = seal(&key, &plaintext, 1, &salt, 16, b'B', 0);
    let mut s = Session::default();
    let request = EncryptBlobRequest {
        key: s.import(&key),
        kind: 1,
        salt,
        ..Default::default()
    };
    cases.push(s.stream(
        "encrypting holds back the chunk that may be the last",
        Method::EncryptBlob,
        request,
        json!([{"pattern": 65536}, {"pattern": 1000}]),
        encrypt_steps(&sealed, &[65536, 1000]),
    ));
}

/// Runs of chunks opened alone after the header, as a player seeking asks for them: the index and the last flag stay
/// bound by the nonce.
fn random_access(doc: &Value, cases: &mut Vec<Value>) {
    let valid = |id: &str| {
        let mut v = doc["valid"].as_array().unwrap().iter();
        v.find(|v| v["id"] == id).unwrap().clone()
    };
    let (three, text, c) = ("plb-three-chunks", pattern(132072), 65536);
    let (at, end) = (|i: usize| HEADER + i * (c + 16), 132208);
    let empty = || Ok(vec![]);
    let runs = [
        (
            "random access: the last chunk alone",
            three,
            2,
            false,
            json!([[[0, HEADER], [at(2), end]]]),
            vec![empty(), Ok(text[2 * c..].to_vec())],
        ),
        (
            "random access: with more after them, no chunk is the last",
            three,
            0,
            true,
            json!([[[0, at(1)]]]),
            vec![Ok(text[..c].to_vec()), empty()],
        ),
        (
            "random access streams too",
            three,
            1,
            false,
            json!([[[0, HEADER]], [[at(1), at(1) + 50]], [[at(1) + 50, end]]]),
            vec![
                empty(),
                empty(),
                Ok(text[c..2 * c].to_vec()),
                Ok(text[2 * c..].to_vec()),
            ],
        ),
        (
            "a chunk given at another index fails",
            three,
            0,
            false,
            json!([[[0, HEADER], [at(2), end]]]),
            vec![empty(), rejected("auth_failed")],
        ),
        (
            "a middle chunk opened as the last fails",
            three,
            1,
            false,
            json!([[[0, HEADER], [at(1), at(2)]]]),
            vec![empty(), rejected("auth_failed")],
        ),
        (
            "the last chunk opened with more after it fails",
            "plb-one-full-chunk",
            0,
            true,
            json!([[[0, at(1)]]]),
            vec![rejected("auth_failed"), rejected("auth_failed")],
        ),
        (
            "with more after them, a chunk cut short is bad_length",
            three,
            0,
            true,
            json!([[[0, at(1) - 1]]]),
            vec![empty(), rejected("bad_length")],
        ),
    ];
    for (name, blob, first_chunk, more, pieces, steps) in runs {
        let mut s = Session::default();
        let request = DecryptBlobRequest {
            key: s.import(&hex(&valid(blob)["key"])),
            kind: 1,
            first_chunk,
            more,
            ..Default::default()
        };
        let pieces = pieces.as_array().unwrap().iter();
        let pieces = pieces.map(|r| json!({"blob": blob, "ranges": r})).collect();
        cases.push(s.stream(name, Method::DecryptBlob, request, pieces, steps));
    }
    let padded = valid("plb-padded");
    let mut s = Session::default();
    let request = DecryptBlobRequest {
        key: s.import(&hex(&padded["key"])),
        kind: 4,
        envelope: envelope_of(&padded),
        more: true,
        ..Default::default()
    };
    let refused = fail(CallErrorCode::InvalidRequest, &[("field", "first_chunk")]);
    cases.push(s.call(
        "random access opens no padded envelope",
        Method::DecryptBlob,
        request,
        refused,
    ));
}

// --- PLW

fn context(c: &Value) -> Option<WrapContext> {
    Some(WrapContext {
        user_id: hex(&c["user_id"]),
        container_id: hex(&c["container_id"]),
        subject_id: hex(&c["subject_id"]),
        number: number(&c["number"]),
    })
}

fn plw(doc: &Value, cases: &mut Vec<Value>) {
    for v in doc["valid"].as_array().unwrap() {
        let id = v["id"].as_str().unwrap();
        let (wrapping_key, key, wrap) = (hex(&v["wrapping_key"]), hex(&v["key"]), hex(&v["wrap"]));
        let mut s = Session::default();
        let request = WrapKeyRequest {
            wrapping_key: s.import(&wrapping_key),
            key: s.import(&key),
            wrapped_type: number(&v["wrapped_type"]),
            context: context(&v["context"]),
            nonce: hex(&v["nonce"]),
        };
        let response = ok(WrapKeyResponse { wrap: wrap.clone() });
        cases.push(s.call(&format!("{id}: wrap"), Method::WrapKey, request, response));
        let mut s = Session::default();
        let request = UnwrapKeyRequest {
            wrapping_key: s.import(&wrapping_key),
            wrapped_type: number(&v["wrapped_type"]),
            context: context(&v["context"]),
            wrap,
        };
        let response = s.new_key(&key);
        cases.push(s.call(&format!("{id}: unwrap"), Method::UnwrapKey, request, response));
    }
    cases.extend(rejections(doc, Method::UnwrapKey, |c, fields, s| UnwrapKeyRequest {
        wrapping_key: s.import(&hex(&fields["wrapping_key"])),
        wrapped_type: number(&fields["wrapped_type"]),
        context: context(&fields["context"]),
        wrap: input(c, doc, "wrap", |b| hex(&b["wrap"])),
    }));
}

// --- key derivations, Argon2id, codes, and Padmé through padded envelopes

fn kdf(doc: &Value, cases: &mut Vec<Value>) {
    let derive = Method::DeriveKey;
    let stretch = |password: &str, params: &Value, label: &str, hardware: Vec<u8>| DerivePasswordKeyRequest {
        password: password.into(),
        params: hex(params),
        label: label.into(),
        hardware,
    };
    for (i, c) in doc["cases"].as_array().unwrap().iter().enumerate() {
        let function = c["function"].as_str().unwrap();
        let name = format!("kdf {i}: {function}");
        let mut s = Session::default();
        match function {
            "key_id" => {
                let request = ImportKeyRequest { secret: hex(&c["key"]) };
                let response = ok(KeyResponse {
                    key: 1,
                    key_id: hex(&c["output"]),
                });
                cases.push(s.call(&name, Method::ImportKey, request, response));
            }
            "subkey" | "object_key" => {
                let (key, label, context) = match function {
                    "subkey" => (
                        &c["key"],
                        c["label"].as_str().unwrap(),
                        c.get("context").map_or(vec![], hex),
                    ),
                    _ => (&c["file_key"], "file-key", vec![number(&c["kind"]) as u8]),
                };
                if label == "local/db" {
                    let mut s = Session::default();
                    let request = DatabaseKeyRequest {
                        key: s.import(&hex(key)),
                        file_id: context.clone(),
                    };
                    let response = ok(DatabaseKeyResponse {
                        page_key: hex(&c["output"]),
                    });
                    let name = format!("{name}: database key");
                    cases.push(s.call(&name, Method::DatabaseKey, request, response));
                    let mut s = Session::default();
                    let request = DatabaseKeyRequest {
                        key: s.import(&hex(key)),
                        file_id: context[1..].to_vec(),
                    };
                    let error = fail(CallErrorCode::InvalidRequest, &[("field", "file_id")]);
                    cases.push(s.call(
                        &format!("{name}: file id of 15 bytes"),
                        Method::DatabaseKey,
                        request,
                        error,
                    ));
                }
                let request = DeriveKeyRequest {
                    key: s.import(&hex(key)),
                    label: label.into(),
                    context,
                };
                let response = s.new_key(&hex(&c["output"]));
                cases.push(s.call(&name, derive, request, response));
            }
            "kek_password" | "kek_passcode" => {
                let (password, label, hardware) = match function {
                    "kek_password" => (c["password"].as_str().unwrap(), "kek/password", vec![]),
                    _ => (c["passcode"].as_str().unwrap(), "kek/passcode", hex(&c["hardware"])),
                };
                let method = Method::DerivePasswordKey;
                for (name, label, hardware, output) in [
                    (name.clone(), label, hardware, &c["output"]),
                    (format!("{name}: argon2id"), "", vec![], &c["argon2id"]),
                ] {
                    let request = stretch(password, &c["params"], label, hardware);
                    cases.push(Session::default().call(&name, method, request, s.new_key(&hex(output))));
                }
            }
            "argon2id" => {
                let password = String::from_utf8(hex(&c["secret"])).unwrap();
                let response = s.new_key(&hex(&c["output"]));
                let request = stretch(&password, &c["params"], "", vec![]);
                cases.push(s.call(
                    &format!("{name} {}", c["id"]),
                    Method::DerivePasswordKey,
                    request,
                    response,
                ));
            }
            "check_account_params" | "check_device_params" => {
                let policy = match function {
                    "check_account_params" => KdfPolicy::Account,
                    _ => KdfPolicy::Device,
                };
                let request = CheckKdfParamsRequest {
                    params: hex(&c["params"]),
                    policy: policy.into(),
                };
                let response = match c["error"].as_str() {
                    Some(error) => rejected(error),
                    None => ok(CheckKdfParamsResponse {}),
                };
                cases.push(s.call(&name, Method::CheckKdfParams, request, response));
            }
            "public_key_id" => {
                let (pk, pls) = (hex(&c["public_key"]), kat("pls"));
                assert_eq!(sharing::sha256(&pk)[..16], hex(&c["output"]));
                let logs = pls["identity_logs"].as_array().unwrap();
                let log = logs.iter().find(|l| hex(&l["state"]["sign_keys"][0]) == pk);
                let user = pls["users"].as_object().unwrap().values();
                let user = user.clone().find(|u| u["user_id"] == log.unwrap()["user_id"]);
                let seed = hex(&user.unwrap()["signing_seed"]);
                cases.push(sharing::public_key(&name, &seed, KeyPair::Ed25519, &pk));
            }
            "dedup_token" => {
                let request = DedupTokenRequest {
                    key: s.import(&hex(&c["dedup_key"])),
                    sha256: sharing::sha256(&hex(&c["content"])),
                };
                let response = ok(DedupTokenResponse {
                    token: hex(&c["output"]),
                });
                cases.push(s.call(&name, Method::DedupToken, request, response));
            }
            "link_keys" => {
                let (secret, link_id) = (hex(&c["secret"]), hex(&c["link_id"]));
                let password_hash = hex(&c["password_hash"]);
                let request = LinkKeysRequest {
                    secret: s.import(&secret),
                    link_id: link_id.clone(),
                    password_hash: match password_hash.len() {
                        0 => 0,
                        _ => s.import(&password_hash),
                    },
                };
                let response = ok(LinkKeysResponse {
                    key: s.last + 1,
                    key_id: key_id(&hex(&c["link_key"])),
                    verifier: hex(&c["verifier"]),
                });
                cases.push(s.call(&name, Method::LinkKeys, request, response));
                let mut s = Session::default();
                let request = DeriveKeyRequest {
                    key: s.import(&secret),
                    label: "link/auth".into(),
                    context: link_id.clone(),
                };
                let response = s.new_key(&hex(&c["link_auth"]));
                cases.push(s.call(&format!("{name}: auth"), derive, request, response));
                let request = LinkFragmentRequest {
                    link_id,
                    secret,
                    password: !password_hash.is_empty(),
                    manifest: hex(&c["manifest"]),
                };
                let response = ok(LinkFragmentResponse {
                    fragment: c["fragment"].as_str().unwrap().into(),
                });
                let name = format!("{name}: fragment");
                cases.push(Session::default().call(&name, Method::LinkFragment, request, response));
            }
            "padme" => {
                let (length, padded) = (int(&c["length"]), int(&c["output"]));
                let plb = kat("plb");
                let valid = plb["valid"].as_array().unwrap();
                let v = valid.iter().find(|v| v["id"] == "plb-padded").unwrap();
                let (key, salt) = (hex(&v["key"]), hex(&v["salt"]));
                let mut plaintext = pattern(length - 1);
                plaintext.push(0x80);
                plaintext.resize(padded, 0);
                let envelope = seal(&key, &plaintext, 1, &salt, 16, b'B', 1);
                let mut request = EncryptBlobRequest {
                    key: s.import(&key),
                    kind: 1,
                    padded: true,
                    salt,
                    ..Default::default()
                };
                let (name, encrypt) = (format!("{name} {length}"), Method::EncryptBlob);
                if length < 4096 {
                    request.plaintext = pattern(length - 1);
                    let response = ok(EncryptBlobResponse { envelope });
                    cases.push(s.call(&name, encrypt, request, response));
                } else {
                    let steps = encrypt_steps(&envelope, &[length - 1]);
                    let pieces = json!([{"pattern": length - 1}]);
                    cases.push(s.stream(&name, encrypt, request, pieces, steps));
                }
            }
            "verification_code" => {
                let request = SafetyNumberRequest {
                    user_a: hex(&c["user_a"]),
                    signing_key_a: hex(&c["signing_pk_a"]),
                    user_b: hex(&c["user_b"]),
                    signing_key_b: hex(&c["signing_pk_b"]),
                };
                let response = ok(CodeResponse {
                    code: c["output"].as_str().unwrap().into(),
                });
                cases.push(s.call(&name, Method::SafetyNumber, request, response));
            }
            "epoch_code" => {
                let request = EpochCodeRequest {
                    log_id: hex(&c["log_id"]),
                    head: hex(&c["head"]),
                };
                let response = ok(CodeResponse {
                    code: c["output"].as_str().unwrap().into(),
                });
                cases.push(s.call(&name, Method::EpochCode, request, response));
            }
            other => panic!("kdf.json has a function the kernel does not run: {other}"),
        }
    }
}

// --- lockbox and journal

fn lockbox(doc: &Value, cases: &mut Vec<Value>) {
    for v in doc["valid"].as_array().unwrap() {
        let id = v["id"].as_str().unwrap();
        let (ddk, device_id, lockbox) = (hex(&v["ddk"]), hex(&v["device_id"]), hex(&v["lockbox"]));
        let slots = v["slots"].as_array().unwrap();
        let wrap = |i: usize| lockbox[40 + 188 * i + 44..40 + 188 * (i + 1)].to_vec();
        let mut s = Session::default();
        let key = s.import(&ddk);
        let request = SealLockboxRequest {
            key,
            device_id: device_id.clone(),
            slots: slots
                .iter()
                .map(|slot| LockboxSlot {
                    factor: number(&slot["factor"]),
                    hardware: slot["binding"] == 1,
                    user_id: hex(&slot["user_id"]),
                    params: hex(&slot["params"]),
                    key: s.import(&hex(&slot["key"])),
                    nonce: hex(&slot["nonce"]),
                    ..Default::default()
                })
                .collect(),
        };
        let sealed = ok(SealLockboxResponse {
            lockbox: lockbox.clone(),
        });
        let method = Method::SealLockbox;
        let mut kept = request.clone();
        for (i, slot) in kept.slots.iter_mut().enumerate().skip(1) {
            (slot.key, slot.wrap) = (0, wrap(i));
        }
        cases.push(s.call(&format!("{id}: seal"), method, request, sealed.clone()));
        let mut s = Session::default();
        for slot in [&v["ddk"]].into_iter().chain(slots.iter().map(|slot| &slot["key"])) {
            s.import(&hex(slot));
        }
        cases.push(s.call(
            &format!("{id}: seal, keeping all slots but the first"),
            method,
            kept,
            sealed,
        ));
        let read = ReadLockboxResponse {
            device_id: device_id.clone(),
            key_id: key_id(&ddk),
            slots: slots
                .iter()
                .enumerate()
                .map(|(i, slot)| LockboxSlot {
                    factor: number(&slot["factor"]),
                    hardware: slot["binding"] == 1,
                    user_id: if slot["factor"] == 5 {
                        hex(&slot["user_id"])
                    } else {
                        vec![]
                    },
                    params: if slot["factor"] == 2 {
                        hex(&slot["params"])
                    } else {
                        vec![]
                    },
                    wrap: wrap(i),
                    ..Default::default()
                })
                .collect(),
        };
        let request = ReadLockboxRequest {
            lockbox: lockbox.clone(),
        };
        let response = ok(read);
        cases.push(Session::default().call(&format!("{id}: read"), Method::ReadLockbox, request, response));
        for (i, slot) in slots.iter().enumerate() {
            let mut s = Session::default();
            let request = OpenLockboxRequest {
                lockbox: lockbox.clone(),
                slot: i as u32,
                key: s.import(&hex(&slot["key"])),
            };
            let response = s.new_key(&ddk);
            cases.push(s.call(&format!("{id}: open slot {i}"), Method::OpenLockbox, request, response));
        }
    }
    cases.extend(rejections(doc, Method::OpenLockbox, |c, fields, s| {
        let slot = c.get("slot").map_or(0, number);
        let key = c.get("key").unwrap_or(&fields["slots"][slot as usize]["key"]);
        OpenLockboxRequest {
            lockbox: input(c, doc, "lockbox", |b| hex(&b["lockbox"])),
            slot,
            key: s.import(&hex(key)),
        }
    }));
    let mut s = Session::default();
    let request = SealLockboxRequest {
        key: s.import(&[1; 32]),
        device_id: vec![2; 16],
        slots: vec![],
    };
    let error = fail(
        CallErrorCode::InvalidRequest,
        &[("field", "slots"), ("reason", "bad_header")],
    );
    cases.push(s.call(
        "a lockbox without slots is not sealed",
        Method::SealLockbox,
        request,
        error,
    ));
}

fn journal(doc: &Value, cases: &mut Vec<Value>) {
    for v in doc["valid"].as_array().unwrap() {
        let id = v["id"].as_str().unwrap();
        let (inbox, public_key, entry) = (hex(&v["inbox_key"]), hex(&v["public_key"]), hex(&v["entry"]));
        let mut s = Session::default();
        let request = InboxPublicKeyRequest { key: s.import(&inbox) };
        let response = ok(InboxPublicKeyResponse {
            public_key: public_key.clone(),
        });
        cases.push(s.call(
            &format!("{id}: inbox public key"),
            Method::InboxPublicKey,
            request,
            response,
        ));
        let request = SealJournalEntryRequest {
            public_key,
            randomness: hex(&v["randomness"]),
            plaintext: hex(&v["plaintext"]),
        };
        let response = ok(SealJournalEntryResponse { entry: entry.clone() });
        let name = format!("{id}: seal");
        cases.push(Session::default().call(&name, Method::SealJournalEntry, request, response));
        let mut s = Session::default();
        let request = OpenJournalEntryRequest {
            key: s.import(&inbox),
            entry,
        };
        let response = ok(OpenJournalEntryResponse {
            plaintext: hex(&v["plaintext"]),
        });
        cases.push(s.call(&format!("{id}: open"), Method::OpenJournalEntry, request, response));
    }
    cases.extend(rejections(doc, Method::OpenJournalEntry, |c, fields, s| {
        OpenJournalEntryRequest {
            key: s.import(&hex(&fields["inbox_key"])),
            entry: input(c, doc, "entry", |b| hex(&b["entry"])),
        }
    }));
}

// --- the recovery phrase

fn recovery(doc: &Value, cases: &mut Vec<Value>) {
    for v in doc["valid"].as_array().unwrap() {
        let (id, entropy, phrase) = (
            v["id"].as_str().unwrap(),
            hex(&v["entropy"]),
            v["phrase"].as_str().unwrap(),
        );
        let s = Session::default();
        let response = s.new_key(&hex(&v["output"]));
        let request = RecoveryKeyRequest { phrase: phrase.into() };
        cases.push(s.call(id, Method::RecoveryKey, request, response));
        if v.get("description").is_none() {
            let response = ok(RecoveryPhraseResponse { phrase: phrase.into() });
            let request = RecoveryPhraseRequest { entropy };
            cases.push(Session::default().call(&format!("{id}: phrase"), Method::RecoveryPhrase, request, response));
        }
    }
    for c in doc["invalid"].as_array().unwrap() {
        let mut response = rejected(c["error"].as_str().unwrap());
        if let (Err(error), Some(word)) = (&mut response, c.get("word")) {
            error.params.insert("word".into(), word.to_string());
        }
        let request = RecoveryKeyRequest {
            phrase: c["phrase"].as_str().unwrap().into(),
        };
        cases.push(Session::default().call(c["id"].as_str().unwrap(), Method::RecoveryKey, request, response));
    }
    let request = RecoveryPhraseRequest { entropy: vec![0; 31] };
    let response = fail(CallErrorCode::InvalidRequest, &[("field", "entropy")]);
    cases.push(Session::default().call("recovery phrase of 31 bytes", Method::RecoveryPhrase, request, response));
}
