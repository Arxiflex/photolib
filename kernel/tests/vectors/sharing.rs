//! The public-key half of crypto suite v1 as kernel calls: PLH wraps, PLS logs and statements, and OPAQUE.

use super::{Session, context, hex, input, int, kat, number, ok, rejected, rejections};
use photolib_kernel::proto::kernel::v1::{
    AcceptKeyRequest, CallResponse, Checkpoint, Device, Identity, KeyPair, Link, Member, Method, OpaqueClientResponse,
    OpaqueLoginRequest, OpaqueRegisterRequest, OpaqueServerLoginRequest, OpaqueServerRegisterRequest,
    OpaqueServerResponse, PublicKeyRequest, PublicKeyResponse, ShareKeyRequest, ShareKeyResponse, SignEntryRequest,
    SignEntryResponse, SignedWrap, UnwrapKeyRequest, Upload, VerifyIdentityLogRequest, VerifyIdentityLogResponse,
    VerifyMembershipLogRequest, VerifyMembershipLogResponse, call_response,
};
use prost::Message;
use serde_json::Value;
use sha2::{Digest, Sha256};

pub fn cases(cases: &mut Vec<Value>) {
    plh(&kat("plh"), cases);
    pls(&kat("pls"), cases);
    opaque(&kat("opaque"), cases);
}

pub fn sha256(bytes: &[u8]) -> Vec<u8> {
    Sha256::digest(bytes).to_vec()
}

/// What PublicKey answers for a seed: its public key and pk_id.
pub fn public_key(name: &str, seed: &[u8], key_pair: KeyPair, public_key: &[u8]) -> Value {
    let mut s = Session::default();
    let request = PublicKeyRequest {
        key: s.import(seed),
        key_pair: key_pair.into(),
    };
    let response = ok(PublicKeyResponse {
        public_key: public_key.to_vec(),
        key_id: sha256(public_key)[..16].to_vec(),
    });
    s.call(name, Method::PublicKey, request, response)
}

/// Opening a PLH as its recipient, with the SHA-256 a verified entry names for it: the key it holds, or an error.
fn accept(name: &str, v: &Value, wrap: Vec<u8>, signed: Vec<u8>, key: Result<&[u8], &str>) -> Value {
    let mut s = Session::default();
    let request = AcceptKeyRequest {
        key: s.import(&hex(&v["recipient_seed"])),
        wrapped_type: v.get("wrapped_type").map_or(3, number),
        context: context(&v["context"]),
        wrap,
        signed_sha256: signed,
    };
    let response = key.map_or_else(rejected, |key| s.new_key(key));
    s.call(name, Method::AcceptKey, request, response)
}

fn plh(doc: &Value, cases: &mut Vec<Value>) {
    for v in doc["valid"].as_array().unwrap() {
        let id = v["id"].as_str().unwrap();
        let (key, wrap) = (hex(&v["key"]), hex(&v["wrap"]));
        let (seed, pk) = (hex(&v["recipient_seed"]), hex(&v["recipient_pk"]));
        cases.push(public_key(&format!("{id}: public key"), &seed, KeyPair::XWing, &pk));
        let mut s = Session::default();
        let request = ShareKeyRequest {
            key: s.import(&key),
            public_key: pk,
            wrapped_type: number(&v["wrapped_type"]),
            context: context(&v["context"]),
            sender_key_id: hex(&v["sender_key_id"]),
            randomness: hex(&v["eseed"]),
        };
        let response = ok(ShareKeyResponse { wrap: wrap.clone() });
        cases.push(s.call(&format!("{id}: share"), Method::ShareKey, request, response));
        let signed = sha256(&wrap);
        cases.push(accept(&format!("{id}: accept"), v, wrap, signed, Ok(&key)));
    }
    cases.extend(rejections(doc, Method::AcceptKey, |c, fields, s| {
        let wrap = input(c, doc, "wrap", |b| hex(&b["wrap"]));
        AcceptKeyRequest {
            key: s.import(&hex(&fields["recipient_seed"])),
            wrapped_type: number(&fields["wrapped_type"]),
            context: context(&fields["context"]),
            signed_sha256: sha256(&wrap),
            wrap,
        }
    }));
}

/// An object's entries, its hex keys as bytes.
fn keyed(value: &Value) -> impl Iterator<Item = (Vec<u8>, &Value)> {
    let map = value.as_object().unwrap();
    map.iter().map(|(id, v)| (hex(&Value::from(id.as_str())), v))
}

fn hexes(value: &Value) -> Vec<Vec<u8>> {
    value.as_array().unwrap().iter().map(hex).collect()
}

fn word(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0, |n, &b| n << 8 | u64::from(b))
}

/// SignEntry rebuilding an entry from its fields.
fn sign(name: &str, seed: &[u8], entry: &[u8]) -> Value {
    let mut s = Session::default();
    let request = SignEntryRequest {
        key: s.import(seed),
        log_type: entry[5].into(),
        body_type: word(&entry[6..8]) as u32,
        log_id: entry[24..40].to_vec(),
        seq: word(&entry[40..48]),
        prev_hash: entry[48..80].to_vec(),
        time_ms: word(&entry[80..88]),
        body: entry[92..entry.len() - 64].to_vec(),
    };
    let response = ok(SignEntryResponse { entry: entry.to_vec() });
    s.call(name, Method::SignEntry, request, response)
}

/// The wraps a log's entries name, by entry: PLHs to recipients, and the back-link PLW of a new epoch first.
fn signed_wraps(doc: &Value, log: &str) -> Vec<SignedWrap> {
    let mut wraps: Vec<_> = doc["wraps"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|w| w["log"] == log)
        .map(|w| SignedWrap {
            seq: w["entry_seq"].as_u64().unwrap(),
            recipient_id: hex(&w["recipient_id"]),
            sha256: sha256(&hex(&w["plh"])),
        })
        .collect();
    if log == "membership" {
        let b = &doc["backlink"];
        wraps.push(SignedWrap {
            seq: b["entry_seq"].as_u64().unwrap(),
            recipient_id: vec![],
            sha256: sha256(&hex(&b["wrap"])),
        });
    }
    wraps.sort_by_key(|w| (w.seq, !w.recipient_id.is_empty()));
    wraps
}

fn checkpoint(c: &Value) -> Option<Checkpoint> {
    c.get("checkpoint").map(|c| Checkpoint {
        seq: c[0].as_u64().unwrap(),
        entry_hash: hex(&c[1]),
    })
}

fn pls(doc: &Value, cases: &mut Vec<Value>) {
    let logs = doc["identity_logs"].as_array().unwrap();
    let identities: Vec<_> = logs
        .iter()
        .map(|l| Identity {
            user_id: hex(&l["user_id"]),
            signing_keys: hexes(&l["state"]["sign_keys"]),
        })
        .collect();
    // Every user's first signing key, by its pk_id, with the seed that makes it.
    let mut seeds = vec![];
    for (name, user) in doc["users"].as_object().unwrap() {
        let id = identities.iter().find(|i| i.user_id == hex(&user["user_id"])).unwrap();
        let seed = hex(&user["signing_seed"]);
        cases.push(public_key(
            &format!("pls {name}: signing key"),
            &seed,
            KeyPair::Ed25519,
            &id.signing_keys[0],
        ));
        seeds.push((sha256(&id.signing_keys[0])[..16].to_vec(), seed));
    }
    let m = &doc["membership_log"];
    let membership = hexes(&m["entries"]);
    let statements: Vec<_> = doc["statements"].as_array().unwrap().iter().collect();
    let signed = logs
        .iter()
        .flat_map(|l| hexes(&l["entries"]))
        .chain(membership.clone())
        .chain(statements.iter().map(|s| hex(&s["statement"])));
    for (i, entry) in signed.enumerate() {
        if let Some((_, seed)) = seeds.iter().find(|(id, _)| id[..] == entry[8..24]) {
            cases.push(sign(&format!("pls entry {i}: sign"), seed, &entry));
        }
    }
    for (i, l) in logs.iter().enumerate() {
        let (entries, state) = (hexes(&l["entries"]), &l["state"]);
        let request = VerifyIdentityLogRequest {
            user_id: hex(&l["user_id"]),
            entries: entries.clone(),
            checkpoint: None,
        };
        let response = ok(VerifyIdentityLogResponse {
            signing_keys: hexes(&state["sign_keys"]),
            encryption_key: hex(&state["enc_pk"]),
            devices: keyed(&state["devices"])
                .map(|(device_id, pk)| Device {
                    device_id,
                    public_key: hex(pk),
                })
                .collect(),
            amk_generation: number(&state["amk_generation"]),
            head: Some(Checkpoint {
                seq: entries.len() as u64 - 1,
                entry_hash: hex(&state["head"]),
            }),
            wraps: if i == 0 { signed_wraps(doc, "identity") } else { vec![] },
        });
        let name = format!("identity log {}: verify", l["user_id"].as_str().unwrap());
        cases.push(Session::default().call(&name, Method::VerifyIdentityLog, request, response));
    }
    let invalid = doc["invalid"].as_array().unwrap();
    let rejected_uploads: Vec<_> = invalid.iter().filter(|c| c.get("statement").is_some()).collect();
    let state = &m["state"];
    let uploads = statements
        .iter()
        .map(|s| Upload {
            file_id: hex(&s["file_id"]),
            uploader: hex(&s["uploader"]),
            objects_hash: hex(&s["objects_hash"]),
            rejected: String::new(),
        })
        .chain(rejected_uploads.iter().map(|c| Upload {
            rejected: c["error"].as_str().unwrap().into(),
            ..Default::default()
        }))
        .collect();
    let verify = |entries: Vec<Vec<u8>>, checkpoint, statements| VerifyMembershipLogRequest {
        log_type: number(&m["log_type"]),
        log_id: hex(&m["log_id"]),
        entries,
        checkpoint,
        identities: identities.clone(),
        statements,
    };
    let request = verify(
        membership.clone(),
        None,
        (statements.iter().chain(&rejected_uploads))
            .map(|s| hex(&s["statement"]))
            .collect(),
    );
    let response = ok(VerifyMembershipLogResponse {
        owner: hex(&state["owner"]),
        members: keyed(&state["members"])
            .map(|(user_id, m)| Member {
                user_id,
                role: number(&m[0]),
                signing_key_id: hex(&m[1]),
            })
            .collect(),
        epoch: number(&state["epoch"]),
        rotation_due: state["rotation_due"].as_bool().unwrap(),
        links: keyed(&state["links"])
            .map(|(link_id, pk)| Link {
                link_id,
                drop_key: if pk.is_null() { vec![] } else { hex(pk) },
            })
            .collect(),
        head: Some(Checkpoint {
            seq: membership.len() as u64 - 1,
            entry_hash: hex(&state["head"]),
        }),
        wraps: signed_wraps(doc, "membership"),
        uploads,
    });
    cases.push(Session::default().call(
        "membership log: verify, with upload statements",
        Method::VerifyMembershipLog,
        request,
        response,
    ));
    let alice = &logs[0];
    for c in invalid.iter().filter(|c| c.get("prefix").is_some()) {
        let mut view = if c["log"] == "identity" {
            hexes(&alice["entries"])
        } else {
            membership.clone()
        };
        view.truncate(int(&c["prefix"]));
        view.extend(c.get("entry").map(hex));
        let id = c["id"].as_str().unwrap();
        let error = rejected(c["error"].as_str().unwrap());
        let s = Session::default();
        cases.push(if c["log"] == "identity" {
            let request = VerifyIdentityLogRequest {
                user_id: hex(&alice["user_id"]),
                entries: view,
                checkpoint: checkpoint(c),
            };
            s.call(id, Method::VerifyIdentityLog, request, error)
        } else {
            let request = verify(view, checkpoint(c), vec![]);
            s.call(id, Method::VerifyMembershipLog, request, error)
        });
    }
    for w in doc["wraps"].as_array().unwrap() {
        let (plh, key) = (hex(&w["plh"]), hex(&w["key"]));
        let name = format!("{} log entry {}: accept", w["log"].as_str().unwrap(), w["entry_seq"]);
        cases.push(accept(&name, w, plh.clone(), sha256(&plh), Ok(&key)));
    }
    for c in invalid.iter().filter(|c| c.get("plh").is_some()) {
        let named = doc["wraps"].as_array().unwrap().iter().find(|w| {
            w["log"] == c["log"] && w["entry_seq"] == c["entry_seq"] && w["recipient_id"] == c["recipient_id"]
        });
        let signed = sha256(&hex(&named.unwrap()["plh"]));
        let (id, error) = (c["id"].as_str().unwrap(), c["error"].as_str().unwrap());
        cases.push(accept(id, c, hex(&c["plh"]), signed, Err(error)));
    }
    let b = &doc["backlink"];
    let mut s = Session::default();
    let request = UnwrapKeyRequest {
        wrapping_key: s.import(&hex(&b["wrapping_key"])),
        wrapped_type: 3,
        context: context(&b["context"]),
        wrap: hex(&b["wrap"]),
    };
    let response = s.new_key(&hex(&b["key"]));
    cases.push(s.call("membership log: back-link", Method::UnwrapKey, request, response));
}

/// What the kernel answers: for the messages of a flow that the vectors give only the end of.
fn answer<M: Message + Default>(method: Method, request: &impl Message) -> M {
    let response = photolib_kernel::call(method as u32, &request.encode_to_vec());
    match CallResponse::decode(response.as_slice()).unwrap().result {
        Some(call_response::Result::Response(bytes)) => M::decode(bytes.as_slice()).unwrap(),
        other => panic!("{other:?}"),
    }
}

fn opaque(doc: &Value, cases: &mut Vec<Value>) {
    let (i, o) = (&doc["inputs"], &doc["outputs"]);
    assert_eq!(hex(&i["context"]), b"photolib/v1/opaque");
    let password = |p: &Value| String::from_utf8(hex(p)).unwrap();
    // A scalar is the 64 random bytes it reduces from, padded with zeros.
    let blind = |b: &Value| [hex(b), vec![0; 32]].concat();
    let register = OpaqueRegisterRequest {
        password: password(&i["password"]),
        params: hex(&i["ksf_params"]),
        randomness: [blind(&i["blind_registration"]), hex(&i["envelope_nonce"])].concat(),
        response: vec![],
    };
    let login = |password, ke2| OpaqueLoginRequest {
        password,
        params: hex(&i["ksf_params"]),
        randomness: [
            blind(&i["blind_login"]),
            hex(&i["client_keyshare_seed"]),
            hex(&i["client_nonce"]),
        ]
        .concat(),
        ke2,
    };
    let server = |private_key: &Value, ke1, ke3| OpaqueServerLoginRequest {
        oprf_seed: hex(&i["oprf_seed"]),
        private_key: hex(private_key),
        credential_id: hex(&i["credential_identifier"]),
        record: hex(&o["registration_record"]),
        randomness: [
            hex(&i["masking_nonce"]),
            hex(&i["server_keyshare_seed"]),
            hex(&i["server_nonce"]),
        ]
        .concat(),
        ke1,
        ke3,
    };
    let client = |message: &str, session_key, export_key| {
        ok(OpaqueClientResponse {
            message: hex(&o[message]),
            session_key,
            export_key,
        })
    };
    let (session_key, export_key) = (hex(&o["session_key"]), hex(&o["export_key"]));
    let pw = password(&i["password"]);
    let steps: [(&str, Method, Vec<u8>, _); 7] = [
        (
            "opaque: registration request",
            Method::OpaqueRegister,
            register.encode_to_vec(),
            client("registration_request", vec![], vec![]),
        ),
        (
            "opaque: registration response",
            Method::OpaqueServerRegister,
            OpaqueServerRegisterRequest {
                oprf_seed: hex(&i["oprf_seed"]),
                private_key: hex(&i["server_private_key"]),
                credential_id: hex(&i["credential_identifier"]),
                request: hex(&o["registration_request"]),
            }
            .encode_to_vec(),
            ok(OpaqueServerResponse {
                message: hex(&o["registration_response"]),
                session_key: vec![],
            }),
        ),
        (
            "opaque: registration record",
            Method::OpaqueRegister,
            OpaqueRegisterRequest {
                response: hex(&o["registration_response"]),
                ..register.clone()
            }
            .encode_to_vec(),
            client("registration_record", vec![], export_key.clone()),
        ),
        (
            "opaque: KE1",
            Method::OpaqueLogin,
            login(pw.clone(), vec![]).encode_to_vec(),
            client("KE1", vec![], vec![]),
        ),
        (
            "opaque: KE2",
            Method::OpaqueServerLogin,
            server(&i["server_private_key"], hex(&o["KE1"]), vec![]).encode_to_vec(),
            ok(OpaqueServerResponse {
                message: hex(&o["KE2"]),
                session_key: vec![],
            }),
        ),
        (
            "opaque: KE3",
            Method::OpaqueLogin,
            login(pw.clone(), hex(&o["KE2"])).encode_to_vec(),
            client("KE3", session_key.clone(), export_key),
        ),
        (
            "opaque: the server checks KE3",
            Method::OpaqueServerLogin,
            server(&i["server_private_key"], hex(&o["KE1"]), hex(&o["KE3"])).encode_to_vec(),
            ok(OpaqueServerResponse {
                message: vec![],
                session_key,
            }),
        ),
    ];
    for (name, method, request, response) in steps {
        cases.push(super::call_case(name, method as u32, request, response));
    }
    for c in doc["invalid"].as_array().unwrap() {
        let password = c.get("password").map_or(pw.clone(), password);
        let key = c.get("server_private_key").unwrap_or(&i["server_private_key"]);
        let ke1: OpaqueClientResponse = answer(Method::OpaqueLogin, &login(password.clone(), vec![]));
        let ke2: OpaqueServerResponse = answer(Method::OpaqueServerLogin, &server(key, ke1.message, vec![]));
        let request = login(password, ke2.message);
        let error = rejected(c["error"].as_str().unwrap());
        let name = c["id"].as_str().unwrap();
        cases.push(Session::default().call(name, Method::OpaqueLogin, request, error));
    }
    let mut ke3 = hex(&o["KE3"]);
    ke3[0] ^= 1;
    let request = server(&i["server_private_key"], hex(&o["KE1"]), ke3);
    let error = rejected("auth_failed");
    let name = "opaque: the server rejects a tampered KE3";
    cases.push(Session::default().call(name, Method::OpaqueServerLogin, request, error));
}
