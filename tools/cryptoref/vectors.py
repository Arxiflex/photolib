#!/usr/bin/env python3
"""Known-answer vectors of crypto suite v1 (docs/dev/crypto-v1.md).

    python3 tools/cryptoref/vectors.py           # rewrite kernel/testvectors/crypto/*.json
    python3 tools/cryptoref/vectors.py --check   # fail unless the committed vectors are exactly what this generates

Both first check every primitive against its published vectors (standards.json), so the generated vectors rest on
implementations that agree with the RFCs and drafts the specification pins.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

import formats
import opaque
import prims
from prims import sha256

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = ROOT / "kernel" / "testvectors" / "crypto"
SPEC = "docs/dev/crypto-v1.md"
h = bytes.fromhex


def check_primitives():
    std = json.loads((HERE / "standards.json").read_text())
    problems = []

    def expect(name, got, want):
        if got != want:
            problems.append(f"{name}: got {got.hex() if isinstance(got, bytes) else got}")

    v = std["chacha20poly1305 (RFC 8439 2.8.2)"]
    expect("chacha20poly1305", prims.aead_seal(h(v["key"]), h(v["nonce"]), h(v["plaintext"]), h(v["aad"])),
           h(v["ciphertext"]))
    v = std["xchacha20poly1305 (draft-irtf-cfrg-xchacha-03 A.3.1)"]
    expect("xchacha20poly1305", prims.xaead_seal(h(v["key"]), h(v["nonce"]), h(v["plaintext"]), h(v["aad"])),
           h(v["ciphertext"]))
    expect("xchacha20poly1305 open", prims.xaead_open(h(v["key"]), h(v["nonce"]), h(v["ciphertext"]), h(v["aad"])),
           h(v["plaintext"]))
    v = std["hkdf-sha256 (RFC 5869 A.1)"]
    expect("hkdf-sha256", prims.hkdf(h(v["ikm"]), h(v["info"]), 42, h(v["salt"])), h(v["okm"]))
    for i, v in enumerate(std["x25519 (RFC 7748 5.2)"]):
        expect(f"x25519 #{i}", prims.x25519(h(v["scalar"]), h(v["u"])), h(v["out"]))
    for i, v in enumerate(std["ed25519 (RFC 8032 7.1)"]):
        expect(f"ed25519 public #{i}", prims.ed25519_public(h(v["secret"])), h(v["public"]))
        expect(f"ed25519 sign #{i}", prims.ed25519_sign(h(v["secret"]), h(v["message"])), h(v["signature"]))
        expect(f"ed25519 verify #{i}", prims.ed25519_verify(h(v["public"]), h(v["message"]), h(v["signature"])), True)
    v = std["argon2id (RFC 9106 5.3)"]
    expect("argon2id", prims.argon2id(h(v["password"]), h(v["salt"]), v["m_kib"], v["t"], v["p"], 32, h(v["secret"]),
                                      h(v["ad"])), h(v["tag"]))
    for i, v in enumerate(std["x-wing (draft-connolly-cfrg-xwing-kem-11 C)"]):
        expect(f"x-wing public #{i}", prims.xwing_public(h(v["sk"])), h(v["pk"]))
        expect(f"x-wing encaps #{i}", prims.xwing_encaps(h(v["pk"]), h(v["eseed"])), (h(v["ss"]), h(v["ct"])))
        expect(f"x-wing decaps #{i}", prims.xwing_decaps(h(v["sk"]), h(v["ct"])), h(v["ss"]))
    v = std["hpke x-wing (draft-ietf-hpke-pq-05 A.5)"]
    expect("hpke public", prims.xwing_public(h(v["skRm"])), h(v["pkRm"]))
    expect("hpke encaps", prims.xwing_encaps(h(v["pkRm"]), h(v["ikmE"])), (h(v["shared_secret"]), h(v["enc"])))
    key, nonce, exporter = prims.hpke_schedule(h(v["shared_secret"]), h(v["info"]))
    expect("hpke key schedule", (key, nonce, exporter), (h(v["key"]), h(v["base_nonce"]), h(v["exporter_secret"])))
    expect("hpke seal", prims.hpke_seal(h(v["pkRm"]), h(v["ikmE"]), h(v["info"]), h(v["aad"]), h(v["pt"])),
           (h(v["enc"]), h(v["ct"])))
    expect("hpke open", prims.hpke_open(h(v["skRm"]), h(v["enc"]), h(v["info"]), h(v["aad"]), h(v["ct"])), h(v["pt"]))
    expect("hpke export", prims.hpke_export(exporter, h(v["exporter_context"]), 32), h(v["exported_value"]))
    v = std["hpke x25519 (RFC 9180 A.2.1)"]
    expect("dhkem derive key pair", prims.dhkem_key_pair(h(v["ikmR"])), (h(v["skRm"]), h(v["pkRm"])))
    expect("dhkem encaps", prims.dhkem_encaps(h(v["pkRm"]), h(v["ikmE"])), (h(v["shared_secret"]), h(v["enc"])))
    expect("dhkem decaps", prims.dhkem_decaps(h(v["skRm"]), h(v["enc"])), h(v["shared_secret"]))
    expect("hpke x25519 key schedule", prims.hpke_schedule(h(v["shared_secret"]), h(v["info"]), prims.X25519_KEM),
           (h(v["key"]), h(v["base_nonce"]), h(v["exporter_secret"])))
    expect("hpke x25519 seal", prims.hpke_seal(h(v["pkRm"]), h(v["ikmE"]), h(v["info"]), h(v["aad"]), h(v["pt"]),
                                               prims.X25519_KEM), (h(v["enc"]), h(v["ct"])))
    expect("hpke x25519 open", prims.hpke_open(h(v["skRm"]), h(v["enc"]), h(v["info"]), h(v["aad"]), h(v["ct"]),
                                               prims.X25519_KEM), h(v["pt"]))
    v = std["ristretto255 (RFC 9496 A.1, A.3)"]
    point = prims.IDENTITY
    for i, enc in enumerate(v["multiples"]):
        expect(f"ristretto255 {i}*B", prims.ristretto_encode(point), h(enc))
        expect(f"ristretto255 decode {i}*B", prims.ristretto_same(prims.ristretto_decode(h(enc)), point), True)
        point = prims._add(point, prims.ristretto_decode(h(v["multiples"][1])))
    for i, u in enumerate(v["from_uniform"]):
        expect(f"ristretto255 from uniform #{i}", prims.ristretto_encode(prims.ristretto_from_uniform(h(u["input"]))),
               h(u["output"]))
    v = std["oprf ristretto255-sha512 (RFC 9497 A.1.1)"]
    sk = opaque.derive_key_pair(h(v["seed"]), h(v["key_info"]))[0]
    expect("oprf derive key pair", sk.to_bytes(32, "little"), h(v["sk"]))
    for i, t in enumerate(v["vectors"]):
        r = scalar(t["Blind"])
        expect(f"oprf blind #{i}", opaque.blind(h(t["Input"]), r), h(t["BlindedElement"]))
        expect(f"oprf evaluate #{i}", opaque.blind_evaluate(sk, h(t["BlindedElement"])), h(t["EvaluationElement"]))
        expect(f"oprf finalize #{i}", opaque.finalize(h(t["Input"]), r, h(t["EvaluationElement"])), h(t["Output"]))
    v = std["opaque-3dh ristretto255-sha512 identity ksf (RFC 9807 C.1.1)"]
    identity = lambda x: x
    reg = opaque.register(h(v["password"]), h(v["credential_identifier"]), h(v["oprf_seed"]),
                          h(v["server_public_key"]), scalar(v["blind_registration"]), h(v["envelope_nonce"]), identity)
    expect("opaque registration", [reg[k] for k in ("registration_request", "registration_response",
                                                    "registration_record", "export_key")],
           [h(v[k]) for k in ("registration_request", "registration_response", "registration_upload", "export_key")])
    out = opaque.login(h(v["password"]), h(v["registration_upload"]), h(v["credential_identifier"]),
                       h(v["oprf_seed"]), scalar(v["server_private_key"]), h(v["server_public_key"]), h(v["Context"]),
                       identity, opaque_randomness(v, "blind_login"))
    expect("opaque login", [out[k] for k in ("KE1", "KE2", "KE3", "session_key", "export_key")],
           [h(v[k]) for k in ("KE1", "KE2", "KE3", "session_key", "export_key")])
    expect("bip-39 english word list", sha256(formats.WORDLIST.read_bytes()).hex(), formats.WORDLIST_SHA256)
    for i, v in enumerate(std["bip-39 english (trezor/python-mnemonic vectors.json, 256-bit entropy)"]):
        expect(f"bip-39 #{i}", formats.recovery_phrase(h(v["entropy"])), v["mnemonic"])
        expect(f"bip-39 read #{i}", formats.recovery_entropy(v["mnemonic"]), h(v["entropy"]))
    return problems


def scalar(hex_le):
    return int.from_bytes(h(hex_le), "little")


def opaque_randomness(v, blind_key):
    names = ("client_nonce", "client_keyshare_seed", "masking_nonce", "server_nonce", "server_keyshare_seed")
    return {"blind": scalar(v[blind_key]), **{k: h(v[k]) for k in names}}


# --- deterministic inputs: every "random" value is SHAKE256 of a label, so regeneration is byte-identical

def rnd(label, n=32):
    return hashlib.shake_256(b"photolib/v1/test-vector/" + label.encode()).digest(n)


def pattern(n):
    return bytes(i % 251 for i in range(n))


def hx(data):
    return data.hex()


ALICE, BOB, CAROL = rnd("user alice", 16), rnd("user bob", 16), rnd("user carol", 16)
ALBUM, FILE, LINK, GRANT, DEVICE = (rnd(x, 16) for x in ("album", "file", "link", "grant", "device"))
SEEDS = {u: rnd("signing seed " + n) for u, n in ((ALICE, "alice"), (BOB, "bob"), (CAROL, "carol"))}
XWING = {u: rnd("x-wing seed " + n) for u, n in ((ALICE, "alice"), (BOB, "bob"), (CAROL, "carol"))}
DIRECTORY = {u: prims.ed25519_public(s) for u, s in SEEDS.items()}
TIME = 1767225600000
ALBUM_KEYS = [rnd("album key epoch 0"), rnd("album key epoch 1")]
FILE_KEY = rnd("file key")
ALICE_NEXT = rnd("signing seed alice 2")


def mutate(data, mutations):
    data = bytearray(data)
    for m in mutations:
        if "flip" in m:
            data[m["flip"]] ^= 1
        elif "truncate" in m:
            del data[m["truncate"]:]
        elif "repeat" in m:
            data += data[m["repeat"][0]:sum(m["repeat"])]
        elif "set" in m:
            off, value = m["set"][0], h(m["set"][1])
            data[off:off + len(value)] = value
        elif "swap" in m:
            a, b, n = m["swap"]
            data[a:a + n], data[b:b + n] = data[b:b + n], data[a:a + n]
    return bytes(data)


def expect_error(case, fn):
    try:
        fn()
    except prims.Reject as e:
        return None if str(e) == case["error"] else f"{case['id']}: rejected with {e}, want {case['error']}"
    return f"{case['id']}: accepted, want {case['error']}"


def merged(case, doc, field):
    """An invalid case: the fields of its base valid case overridden by its own, with the input in full or as
    mutations of the base's."""
    base = next((v for v in doc["valid"] if v["id"] == case.get("base")), {})
    data = h(case[field]) if field in case else mutate(blob_of(base, field), case.get("mutations", []))
    return {**base, **case, field: data}


def blob_of(case, field):
    if field == "envelope" and "envelope" not in case:
        return formats.plb_seal(h(case["key"]), plaintext_of(case), case["kind"], h(case["salt"]), case["padded"],
                                case["chunk_log2"], case["type"].encode())
    return h(case[field])


def plaintext_of(case):
    return pattern(case["plaintext_length"]) if "plaintext_length" in case else h(case["plaintext"])


def rejection_cases(base, rows):
    """Invalid cases sharing a valid base: (id, description, overrides, error), in wire-field order."""
    return [{"id": id_, "description": description, "base": base, **overrides, "error": error}
            for id_, description, overrides, error in rows]


# --- PLB / PLX

def gen_plb():
    key, other = formats.object_key(FILE_KEY, 1), formats.object_key(FILE_KEY, 2)
    valid, invalid = [], []

    def add(id_, description, key, kind, plaintext, padded=False, chunk_log2=16, typ="B"):
        salt = rnd("plb salt " + id_)
        env = formats.plb_seal(key, plaintext, kind, salt, padded, chunk_log2, typ.encode())
        case = {"id": id_, "description": description, "type": typ, "kind": kind, "chunk_log2": chunk_log2,
                "padded": padded, "key": hx(key), "salt": hx(salt)}
        if len(plaintext) > 4096:
            case.update(plaintext_length=len(plaintext), envelope_length=len(env), envelope_sha256=hx(sha256(env)))
        else:
            case.update(plaintext=hx(plaintext), envelope=hx(env))
        valid.append(case)

    add("plb-empty", "empty plaintext: one empty final chunk", key, 1, b"")
    add("plb-short", "a short original in one final chunk", key, 1, b"photolib crypto v1")
    meta = b"\x0a\x12capture 2026-10-15"
    add("plb-padded", f"metadata padded: {len(meta)} bytes + 0x80 marker -> Padme({len(meta) + 1}) = "
        f"{formats.padme(len(meta) + 1)}", formats.object_key(FILE_KEY, 4), 4, meta, True)
    add("plb-one-full-chunk", "exactly one 64 KiB chunk: the full chunk is the final one", key, 1, pattern(65536))
    add("plb-three-chunks", "two full chunks and a partial final chunk", key, 1, pattern(2 * 65536 + 1000))
    add("plb-chunk-log2-17", "readers accept chunk_log2 16..22 (writers emit 16)", key, 1, pattern(70000), False, 17)
    add("plx-manifest", "a link or export manifest (type X, kind manifest)", rnd("link key"), 10, b"manifest", False,
        16, "X")
    step = 65536 + 16
    small = h(valid[1]["envelope"])
    for id_, description, mutations, error in [
        ("plb-bad-magic", "magic is not PL", [{"set": [0, hx(b"QL")]}], "bad_magic"),
        ("plb-wrong-type", "a wrap where a blob is expected", [{"set": [2, hx(b"W")]}], "wrong_type"),
        ("plb-unsupported-version", "format version 2 is unknown", [{"set": [3, "02"]}], "unsupported_version"),
        ("plb-unsupported-suite", "suite 2 is not defined", [{"set": [4, "02"]}], "unsupported_suite"),
        ("plb-experimental-suite", "experimental suites (0xF0-0xFE) are rejected by release builds",
         [{"set": [4, "f0"]}], "unsupported_suite"),
        ("plb-chunk-log2-15", "chunk_log2 below 16", [{"set": [6, "0f"]}], "bad_header"),
        ("plb-chunk-log2-23", "chunk_log2 above 22", [{"set": [6, "17"]}], "bad_header"),
        ("plb-unknown-flag", "flag bit 1 is reserved", [{"set": [7, "02"]}], "bad_header"),
        ("plb-short-header", "shorter than the 88-byte header", [{"truncate": 87}], "bad_length"),
        ("plb-short-chunk", "a final chunk shorter than its tag", [{"truncate": 88 + 15}], "bad_length"),
        ("plb-header-tampered", "key_id changed: the header is the AAD of every chunk", [{"flip": 8}], "auth_failed"),
        ("plb-kind-swapped", "content kind changed in the header", [{"set": [5, "02"]}], "auth_failed"),
        ("plb-commitment-tampered", "commitment changed", [{"flip": 60}], "commitment_mismatch"),
        ("plb-ciphertext-tampered", "a ciphertext bit flipped", [{"flip": 90}], "auth_failed"),
        ("plb-tag-tampered", "a tag bit flipped", [{"flip": len(small) - 1}], "auth_failed"),
    ]:
        invalid.append({"id": id_, "description": description, "base": "plb-short", "mutations": mutations,
                        "error": error})
    for id_, description, mutations, error in [
        ("plb-truncated", "the final chunk dropped: chunk 1 was not sealed as final", [{"truncate": 88 + 2 * step}],
         "auth_failed"),
        ("plb-reordered", "chunks 0 and 1 swapped: the index is in the nonce", [{"swap": [88, 88 + step, step]}],
         "auth_failed"),
        ("plb-extended", "a copy of chunk 0 appended", [{"repeat": [88, step]}], "auth_failed"),
    ]:
        invalid.append({"id": id_, "description": description, "base": "plb-three-chunks", "mutations": mutations,
                        "error": error})
    invalid.append({"id": "plb-wrong-key", "description": "opened with another key: rejected before decryption",
                    "base": "plb-short", "key": hx(other), "error": "commitment_mismatch"})
    invalid.append({"id": "plb-wrong-kind", "description": "a preview served where the original was asked for",
                    "base": "plb-short", "expected_kind": 2, "error": "wrong_kind"})
    invalid.append({"id": "plx-as-blob", "description": "a manifest presented as a blob", "base": "plx-manifest",
                    "mutations": [{"set": [2, hx(b"B")]}], "type": "B", "error": "bad_header"})
    salt = rnd("plb salt unpadded")
    invalid.append({"id": "plb-bad-padding", "description": "padded flag set but no 0x80 marker", "type": "B",
                    "kind": 4, "key": hx(key), "error": "bad_padding",
                    "envelope": hx(formats.plb_seal(key, b"no marker", 4, salt, flags=1))})
    return {"construction": "PLB blob envelope and PLX manifest", "spec": SPEC + "#plb-blob-envelope",
            "pattern": "plaintext_length means plaintext byte i = i mod 251", "valid": valid, "invalid": invalid}


def run_plb(doc):
    problems = []
    for v in doc["valid"]:
        env = blob_of(v, "envelope")
        if "envelope_sha256" in v and (hx(sha256(env)) != v["envelope_sha256"] or len(env) != v["envelope_length"]):
            problems.append(f"{v['id']}: envelope differs")
        if formats.plb_open(h(v["key"]), env, v["kind"], v["type"].encode()) != plaintext_of(v):
            problems.append(f"{v['id']}: plaintext differs")
    for case in doc["invalid"]:
        c = merged(case, doc, "envelope")
        kind = c.get("expected_kind", c["kind"])
        problems.append(expect_error(c, lambda: formats.plb_open(h(c["key"]), c["envelope"], kind, c["type"].encode())))
    return problems


# --- PLW and PLH

def ctx(context):
    return formats.wrap_context(*(h(context[k]) for k in ("user_id", "container_id", "subject_id")),
                                context["number"])


def context_of(user_id=formats.Z16, container_id=formats.Z16, subject_id=formats.Z16, number=0):
    return {"user_id": hx(user_id), "container_id": hx(container_id), "subject_id": hx(subject_id), "number": number}


AMK = rnd("amk alice")
KEK_PW = rnd("kek password alice")
PLW_CASES = [
    ("plw-amk-under-password-kek", "AMK generation 0 under KEK_pw", KEK_PW, AMK, 1, context_of(ALICE)),
    ("plw-album-key-under-amk", "AlbumKey epoch 0 under its owner's AMK", AMK, ALBUM_KEYS[0], 3,
     context_of(ALICE, ALBUM)),
    ("plw-album-backlink", "AlbumKey epoch 0 under AlbumKey epoch 1: the history chain", ALBUM_KEYS[1], ALBUM_KEYS[0],
     3, context_of(container_id=ALBUM)),
    ("plw-file-key-under-album-key", "FileKey under AlbumKey epoch 1", ALBUM_KEYS[1], FILE_KEY, 5,
     context_of(container_id=ALBUM, subject_id=FILE, number=1)),
    ("plw-preview-key-under-link-key", "a preview key under a public link's LinkKey", rnd("link key"),
     formats.object_key(FILE_KEY, 2), 6, context_of(container_id=LINK, subject_id=FILE, number=2)),
    ("plw-signing-key-under-amk", "the identity signing seed under the AMK", AMK, SEEDS[ALICE], 8, context_of(ALICE)),
]


def gen_plw():
    valid = []
    for id_, description, wrapping_key, key, wrapped_type, context in PLW_CASES:
        nonce = rnd("plw nonce " + id_, 24)
        valid.append({"id": id_, "description": description, "wrapping_key": hx(wrapping_key), "key": hx(key),
                      "wrapped_type": wrapped_type, "context": context, "nonce": hx(nonce),
                      "wrap": hx(formats.plw_seal(wrapping_key, key, wrapped_type, ctx(context), nonce))})
    base = valid[3]
    moved = dict(base["context"], subject_id=hx(rnd("another file", 16)))
    invalid = rejection_cases(base["id"], [
        ("plw-moved-to-another-file", "a FileKey wrap replayed for another file", {"context": moved}, "auth_failed"),
        ("plw-wrong-epoch", "the context names epoch 0", {"context": dict(base["context"], number=0)}, "auth_failed"),
        ("plw-wrong-key", "another key: rejected by the commitment before decryption",
         {"wrapping_key": hx(ALBUM_KEYS[0])}, "commitment_mismatch"),
        ("plw-type-swapped", "wrapped_type changed from FileKey to RenditionKey",
         {"mutations": [{"set": [5, "06"]}], "wrapped_type": 6}, "auth_failed"),
        ("plw-wrong-type", "a FileKey wrap used where a LinkSecret is expected", {"wrapped_type": 7}, "wrong_kind"),
        ("plw-unknown-type", "wrapped_type 0 is not assigned", {"mutations": [{"set": [5, "00"]}]}, "bad_header"),
        ("plw-reserved", "reserved bytes must be zero", {"mutations": [{"set": [6, "01"]}]}, "bad_header"),
        ("plw-bad-length", "one byte short", {"mutations": [{"truncate": 143}]}, "bad_length"),
        ("plw-tag-tampered", "tag bit flipped", {"mutations": [{"flip": 143}]}, "auth_failed"),
    ])
    nonce = rnd("plw nonce mislabelled", 24)
    invalid.append({"id": "plw-bad-key-id", "description": "authentic wrap whose wrapped_key_id names another key",
                    "wrapping_key": base["wrapping_key"], "wrapped_type": 5, "context": base["context"],
                    "wrap": hx(formats.plw_seal(ALBUM_KEYS[1], FILE_KEY, 5, ctx(base["context"]), nonce,
                                                formats.key_id(ALBUM_KEYS[0]))), "error": "bad_key_id"})
    return {"construction": "PLW symmetric key wrap", "spec": SPEC + "#plw-symmetric-key-wrap", "valid": valid,
            "invalid": invalid}


def run_plw(doc):
    problems = []
    for v in doc["valid"]:
        wrap = formats.plw_seal(h(v["wrapping_key"]), h(v["key"]), v["wrapped_type"], ctx(v["context"]), h(v["nonce"]))
        if hx(wrap) != v["wrap"] or formats.plw_open(h(v["wrapping_key"]), wrap, v["wrapped_type"],
                                                    ctx(v["context"])) != h(v["key"]):
            problems.append(f"{v['id']}: wrap differs")
    for case in doc["invalid"]:
        c = merged(case, doc, "wrap")
        problems.append(expect_error(c, lambda: formats.plw_open(h(c["wrapping_key"]), c["wrap"], c["wrapped_type"],
                                                                 ctx(c["context"]))))
    return problems


def plh_case(id_, description, recipient, key, wrapped_type, context, sender_key_id):
    pk, eseed = prims.xwing_public(recipient), rnd("plh eseed " + id_, 64)
    return {"id": id_, "description": description, "recipient_seed": hx(recipient), "recipient_pk": hx(pk),
            "key": hx(key), "wrapped_type": wrapped_type, "context": context, "sender_key_id": hx(sender_key_id),
            "eseed": hx(eseed),
            "wrap": hx(formats.plh_seal(pk, key, wrapped_type, ctx(context), sender_key_id, eseed))}


def sender(user):
    return formats.public_key_id(DIRECTORY[user])


def gen_plh():
    worker = rnd("x-wing seed grant worker")
    valid = [
        plh_case("plh-album-key-to-member", "AlbumKey epoch 0 shared with Bob (S1)", XWING[BOB], ALBUM_KEYS[0], 3,
                 context_of(BOB, ALBUM), sender(ALICE)),
        plh_case("plh-grant-session-key", "a GrantSessionKey to a processing-grant worker's ephemeral key", worker,
                 rnd("grant session key"), 10, context_of(ALICE, GRANT), sender(ALICE)),
        plh_case("plh-anonymous-drop", "a FileKey sealed to a collect link's drop key by an anonymous guest",
                 rnd("x-wing seed drop key"), FILE_KEY, 5, context_of(container_id=LINK, subject_id=FILE),
                 formats.Z16),
    ]
    base = valid[0]
    invalid = rejection_cases(base["id"], [
        ("plh-wrong-recipient", "Carol cannot open Bob's wrap", {"recipient_seed": hx(XWING[CAROL])}, "wrong_recipient"),
        ("plh-wrong-context", "the wrap replayed for another album",
         {"context": dict(base["context"], container_id=hx(rnd("another album", 16)))}, "auth_failed"),
        ("plh-enc-tampered", "the X-Wing ciphertext changed", {"mutations": [{"flip": 100}]}, "auth_failed"),
        ("plh-header-tampered", "sender_key_id changed: the header is the AAD",
         {"mutations": [{"flip": 30}]}, "auth_failed"),
        ("plh-bad-length", "one byte short", {"mutations": [{"truncate": 1223}]}, "bad_length"),
    ])
    return {"construction": "PLH public-key wrap (HPKE base mode with X-Wing)", "spec": SPEC + "#plh-public-key-wrap",
            "valid": valid, "invalid": invalid}


def run_plh(doc):
    problems = []
    for v in doc["valid"]:
        pk = prims.xwing_public(h(v["recipient_seed"]))
        wrap = formats.plh_seal(pk, h(v["key"]), v["wrapped_type"], ctx(v["context"]), h(v["sender_key_id"]),
                                h(v["eseed"]))
        if hx(pk) != v["recipient_pk"] or hx(wrap) != v["wrap"] or formats.plh_open(
                h(v["recipient_seed"]), wrap, v["wrapped_type"], ctx(v["context"])) != h(v["key"]):
            problems.append(f"{v['id']}: wrap differs")
    for case in doc["invalid"]:
        c = merged(case, doc, "wrap")
        problems.append(expect_error(c, lambda: formats.plh_open(h(c["recipient_seed"]), c["wrap"], c["wrapped_type"],
                                                                 ctx(c["context"]))))
    return problems


# --- PLS: identity logs, a membership log with key epochs, and upload statements

u16, u32, u64 = formats.u16, formats.u32, formats.u64


def sign(user, log_type, body_type, log_id, seq, prev, body, seed=None):
    return formats.pls_sign(seed or SEEDS[user], log_type, body_type, log_id, seq, prev, TIME + 1000 * seq, body)


def chain(user, log_type, log_id, items):
    """Signs (body_type, body[, seed]) items into a log, with the user's signing seed unless the item names one."""
    entries = []
    for body_type, body, *seed in items:
        prev = formats.entry_hash(entries[-1]) if entries else formats.Z32
        entries.append(sign(user, log_type, body_type, log_id, len(entries), prev, body, *seed))
    return entries


def xpk(seed):
    return prims.xwing_public(seed)


def plh_to(user, epoch):
    return formats.plh_seal(xpk(XWING[user]), ALBUM_KEYS[epoch], 3, formats.wrap_context(user, ALBUM, number=epoch),
                            sender(ALICE), rnd(f"album key epoch {epoch} to {user.hex()}", 64))


def as_json(value):
    if isinstance(value, bytes):
        return hx(value)
    if isinstance(value, dict):
        return {as_json(k): as_json(v) for k, v in value.items()}
    return [as_json(v) for v in value] if isinstance(value, (list, tuple)) else value


def directory_of(identity_logs):
    """User id -> the signing keys of the user's verified identity log, oldest first."""
    return {h(log["user_id"]): formats.verify_identity_log([h(e) for e in log["entries"]], h(log["user_id"]))[-1]
            ["sign_keys"] for log in identity_logs}


def gen_pls():
    drop_seed, device_seed = rnd("x-wing seed drop key"), rnd("x-wing seed device")
    device_plh = formats.plh_seal(xpk(device_seed), AMK, 1, formats.wrap_context(ALICE, DEVICE), sender(ALICE),
                                  rnd("amk to device", 64))
    backlink = formats.plw_seal(ALBUM_KEYS[1], ALBUM_KEYS[0], 3, formats.wrap_context(container_id=ALBUM),
                                rnd("plw nonce plw-album-backlink", 24))
    alice_next = prims.ed25519_public(ALICE_NEXT)
    identity_items = {
        ALICE: [(1, DIRECTORY[ALICE] + xpk(XWING[ALICE])), (4, DEVICE + xpk(device_seed) + sha256(device_plh)),
                (2, xpk(rnd("x-wing seed alice 2"))), (6, u32(1)), (5, DEVICE), (3, bytes([1]) + alice_next),
                (6, u32(2), ALICE_NEXT)],
        BOB: [(1, DIRECTORY[BOB] + xpk(XWING[BOB]))],
        CAROL: [(1, DIRECTORY[CAROL] + xpk(XWING[CAROL]))],
    }
    identity = {u: chain(u, 1, u, items) for u, items in identity_items.items()}
    sid = lambda u: formats.public_key_id(DIRECTORY[u])
    directory = {u: formats.verify_identity_log(entries, u)[-1]["sign_keys"] for u, entries in identity.items()}
    add = lambda u, role: u + sid(u) + bytes([role]) + sha256(plh_to(u, 0))
    epoch_body = lambda epoch, users: u32(epoch) + sha256(backlink) + u16(len(users)) + b"".join(
        u + sha256(plh_to(u, 1)) for u in users)
    membership_items = [
        (1, ALICE + sid(ALICE)), (2, add(BOB, formats.CONTRIBUTOR)), (2, add(CAROL, formats.CONTRIBUTOR)),
        (4, CAROL + bytes([formats.VIEWER])), (6, LINK + bytes([0b101])), (8, LINK + xpk(drop_seed)),
        (9, ALICE + formats.public_key_id(alice_next)), (3, CAROL, ALICE_NEXT), (5, epoch_body(1, [BOB]), ALICE_NEXT),
    ]
    log = chain(ALICE, 2, ALBUM, membership_items)
    states = formats.verify_membership_log(log, 2, ALBUM, directory)
    objects = [h(v["envelope"]) for v in gen_plb()["valid"] if v["id"] in ("plb-short", "plb-padded")]

    def upload(user, seq, epoch, head=None):
        body = FILE + u32(epoch) + u64(seq) + (head or states[seq]["head"]) + formats.objects_hash(objects)
        return sign(user, 4, 1, ALBUM, 0, formats.Z32, body)

    def entry(user, log_type, body_type, log_id, seq, body, seed=None, prev=None):
        if prev is None:
            prev = formats.entry_hash((identity[ALICE] if log_type == 1 else log)[seq - 1])
        return hx(sign(user, log_type, body_type, log_id, seq, prev, body, seed))

    ident = lambda body_type, seq, body, user=ALICE, seed=None, prev=None: entry(user, 1, body_type, ALICE, seq, body,
                                                                                  seed, prev)
    member = lambda body_type, seq, body, user=ALICE, seed=ALICE_NEXT, log_id=ALBUM: entry(user, 2, body_type, log_id,
                                                                                           seq, body, seed)
    sig_flipped = bytearray(identity[ALICE][1])
    sig_flipped[-1] ^= 1
    s_plus_l = identity[ALICE][1][:-32] + (int.from_bytes(identity[ALICE][1][-32:], "little") + prims.L).to_bytes(
        32, "little")
    weak_pk = (1).to_bytes(32, "little")
    weak_msg = formats.pls_sign(rnd("unused"), 1, 1, ALICE, 0, formats.Z32, TIME, weak_pk + xpk(XWING[ALICE]))[:-64]
    weak_msg = weak_msg[:8] + formats.public_key_id(weak_pk) + weak_msg[24:]
    fork = chain(ALICE, 2, ALBUM, membership_items[:3] + [(4, CAROL + bytes([formats.ADMIN]))])[3]
    head = lambda entries, seq: [seq, hx(formats.entry_hash(entries[seq]))]
    invalid = [
        ("identity-bad-signature", "a signature bit flipped", "identity", 1, hx(bytes(sig_flipped)), "bad_signature"),
        ("identity-non-canonical-s", "S + L: the same signature with a non-canonical scalar", "identity", 1,
         hx(s_plus_l), "bad_signature"),
        ("identity-weak-key", "genesis with a small-order key and the signature (identity, 0), valid for every message "
         "under the cofactorless equation", "identity", 0, hx(weak_msg + weak_pk + bytes(32)), "bad_signature"),
        ("identity-wrong-signer", "an entry signed by Bob in Alice's log", "identity", 1,
         ident(2, 1, xpk(rnd("x-wing seed mallory")), BOB), "unauthorized"),
        ("identity-seq-gap", "sequence number 2 after 0", "identity", 1,
         ident(2, 2, xpk(rnd("x-wing seed alice 2")), prev=formats.entry_hash(identity[ALICE][0])), "broken_chain"),
        ("identity-bad-prev-hash", "prev_hash does not name entry 0", "identity", 1,
         ident(2, 1, xpk(rnd("x-wing seed alice 2")), prev=formats.Z32), "broken_chain"),
        ("identity-unknown-body", "body type 0x0099 is not defined for identity logs", "identity", 1,
         ident(0x99, 1, b""), "invalid_entry"),
        ("identity-genesis-twice", "a second genesis", "identity", 1,
         ident(1, 1, DIRECTORY[ALICE] + xpk(XWING[ALICE])), "invalid_entry"),
        ("identity-amk-generation-skip", "AMK generation 2 after 0", "identity", 3, ident(6, 3, u32(2)),
         "invalid_entry"),
        ("identity-old-key-after-rotation", "signed with the signing key that entry 5 replaced", "identity", 6,
         ident(6, 6, u32(2)), "unauthorized"),
        ("identity-rotate-to-undefined-suite", "a signing key for suite 2, which is not defined yet", "identity", 5,
         ident(3, 5, bytes([2]) + alice_next), "invalid_entry"),
        ("membership-stranger", "Carol signs before she is a member", "membership", 1,
         member(2, 1, membership_items[1][1], CAROL, SEEDS[CAROL]), "unauthorized"),
        ("membership-add-by-contributor", "Bob, a contributor, adds Carol", "membership", 2,
         member(2, 2, membership_items[2][1], BOB, SEEDS[BOB]), "unauthorized"),
        ("membership-substituted-key", "Alice added Bob under a signing key that is not in Bob's identity log",
         "membership", 1, member(2, 1, BOB + sid(CAROL) + membership_items[1][1][32:], seed=SEEDS[ALICE]),
         "invalid_entry"),
        ("membership-remove-owner", "the owner cannot be removed", "membership", 3,
         member(3, 3, ALICE, seed=SEEDS[ALICE]), "invalid_entry"),
        ("membership-other-log", "an entry of another album spliced in", "membership", 1,
         entry(ALICE, 2, 2, rnd("another album", 16), 1, membership_items[1][1], SEEDS[ALICE],
               formats.entry_hash(log[0])), "broken_chain"),
        ("membership-old-owner-key", "Alice signs with the key entry 6 replaced", "membership", 7,
         member(3, 7, CAROL, seed=SEEDS[ALICE]), "unauthorized"),
        ("membership-key-rollback", "a member's pin moved back to an older key", "membership", 7,
         member(9, 7, ALICE + sid(ALICE)), "invalid_entry"),
        ("membership-add-before-rotation", "a removal must be followed by a new epoch before anything else",
         "membership", 8, member(2, 8, membership_items[2][1]), "invalid_entry"),
        ("membership-epoch-skip", "epoch 2 after 0", "membership", 8, member(5, 8, epoch_body(2, [BOB])),
         "invalid_entry"),
        ("membership-epoch-misses-member", "the new epoch key is not wrapped for Bob", "membership", 8,
         member(5, 8, epoch_body(1, [])), "invalid_entry"),
        ("membership-epoch-includes-removed", "the new epoch key is wrapped for removed Carol", "membership", 8,
         member(5, 8, epoch_body(1, sorted([BOB, CAROL]))), "invalid_entry"),
    ]
    invalid = [dict(zip(("id", "description", "log", "prefix", "entry", "error"), c)) for c in invalid]
    invalid += [
        {"id": "identity-rollback", "description": "a view that stops before the signing-key rotation the reader "
         "already verified", "log": "identity", "prefix": 5, "checkpoint": head(identity[ALICE], 6),
         "error": "rollback"},
        {"id": "membership-rollback", "description": "a view that stops before Carol's removal", "log": "membership",
         "prefix": 6, "checkpoint": head(log, 8), "error": "rollback"},
        {"id": "membership-fork", "description": "a validly signed alternative entry 3 the reader never saw",
         "log": "membership", "prefix": 3, "entry": hx(fork), "checkpoint": head(log, 3), "error": "rollback"},
        {"id": "upload-by-viewer", "description": "Carol uploads while she is a viewer", "log": "statement",
         "statement": hx(upload(CAROL, 3, 0)), "error": "unauthorized"},
        {"id": "upload-backdated-by-removed-member", "description": "removed Carol signs an upload that names a "
         "position where she was a contributor", "log": "statement", "statement": hx(upload(CAROL, 2, 0)),
         "error": "unauthorized"},
        {"id": "upload-by-removed-member", "description": "Carol uploads after her removal", "log": "statement",
         "statement": hx(upload(CAROL, 8, 1)), "error": "unauthorized"},
        {"id": "upload-during-pending-rotation", "description": "Bob uploads after Carol's removal but before the new "
         "epoch, under a key Carol holds", "log": "statement", "statement": hx(upload(BOB, 7, 0)),
         "error": "invalid_entry"},
        {"id": "upload-wrong-epoch", "description": "Bob names epoch 0 at a position in epoch 1", "log": "statement",
         "statement": hx(upload(BOB, 8, 0)), "error": "invalid_entry"},
        {"id": "upload-unknown-head", "description": "the log head Bob names is not the reader's", "log": "statement",
         "statement": hx(upload(BOB, 8, 1, sha256(b"forked"))), "error": "invalid_entry"},
        {"id": "wrap-not-in-log", "description": "a valid PLH to Bob that entry 1 does not name", "log": "membership",
         "entry_seq": 1, "recipient_id": hx(BOB), "recipient_seed": hx(XWING[BOB]),
         "context": context_of(BOB, ALBUM), "plh": hx(formats.plh_seal(xpk(XWING[BOB]), ALBUM_KEYS[0], 3,
                                                                     formats.wrap_context(BOB, ALBUM), sender(ALICE),
                                                                     rnd("substituted", 64))),
         "error": "unsigned_wrap"},
    ]
    names = {ALICE: "alice", BOB: "bob", CAROL: "carol"}
    return {
        "construction": "PLS signed statements: identity logs, a membership log with key epochs, upload statements",
        "spec": SPEC + "#pls-signed-statements-and-logs",
        "users": {names[u]: {"user_id": hx(u), "signing_seed": hx(SEEDS[u]), "x_wing_seed": hx(XWING[u])}
                  for u in names},
        "identity_logs": [{"user_id": hx(u), "entries": [hx(e) for e in entries],
                           "state": as_json(formats.verify_identity_log(entries, u)[-1])}
                          for u, entries in identity.items()],
        "membership_log": {"log_type": 2, "log_id": hx(ALBUM), "entries": [hx(e) for e in log],
                           "state": as_json(states[-1])},
        "wraps": [{"log": "membership", "entry_seq": seq, "recipient_id": hx(u), "recipient_seed": hx(XWING[u]),
                   "wrapped_type": 3, "context": context_of(u, ALBUM, number=epoch), "plh": hx(plh_to(u, epoch)),
                   "key": hx(ALBUM_KEYS[epoch])} for seq, u, epoch in ((1, BOB, 0), (2, CAROL, 0), (8, BOB, 1))] + [
            {"log": "identity", "entry_seq": 1, "recipient_id": hx(DEVICE), "recipient_seed": hx(device_seed),
             "wrapped_type": 1, "context": context_of(ALICE, DEVICE), "plh": hx(device_plh), "key": hx(AMK)}],
        "backlink": {"entry_seq": 8, "wrap": hx(backlink), "wrapping_key": hx(ALBUM_KEYS[1]),
                     "context": context_of(container_id=ALBUM), "key": hx(ALBUM_KEYS[0])},
        "statements": [{"statement": hx(upload(BOB, 8, 1)), "file_id": hx(FILE), "uploader": hx(BOB),
                        "objects_hash": hx(formats.objects_hash(objects))}],
        "invalid": invalid}


def run_pls(doc):
    problems, alice = [], doc["identity_logs"][0]
    directory = directory_of(doc["identity_logs"])
    identity_states = formats.verify_identity_log([h(e) for e in alice["entries"]], h(alice["user_id"]))
    for log in doc["identity_logs"]:
        if as_json(formats.verify_identity_log([h(e) for e in log["entries"]], h(log["user_id"]))[-1]) != log["state"]:
            problems.append(f"identity log {log['user_id']}: state differs")
    m = doc["membership_log"]
    entries = [h(e) for e in m["entries"]]
    states = formats.verify_membership_log(entries, m["log_type"], h(m["log_id"]), directory)
    if as_json(states[-1]) != m["state"]:
        problems.append("membership log: state differs")
    for w in doc["wraps"] + [c for c in doc["invalid"] if "plh" in c]:
        state = (states if w["log"] == "membership" else identity_states)[w["entry_seq"]]
        open_ = lambda: formats.accept_shared_key(state, h(w["recipient_id"]), h(w["recipient_seed"]), h(w["plh"]),
                                                  w.get("wrapped_type", 3), ctx(w["context"]))
        if "error" in w:
            problems.append(expect_error(w, open_))
        elif open_() != h(w["key"]):
            problems.append(f"wrap at entry {w['entry_seq']}: key differs")
    b = doc["backlink"]
    body = formats.pls_parse(entries[b["entry_seq"]])["body"]
    if body[4:36] != sha256(h(b["wrap"])) or formats.plw_open(h(b["wrapping_key"]), h(b["wrap"]), 3,
                                                              ctx(b["context"])) != h(b["key"]):
        problems.append("backlink differs")
    for s in doc["statements"]:
        got = formats.verify_upload(h(s["statement"]), h(m["log_id"]), states, directory)
        if as_json(got) != {k: s[k] for k in ("file_id", "objects_hash", "uploader")}:
            problems.append("upload statement differs")
    for c in doc["invalid"]:
        view = [h(e) for e in (alice["entries"] if c["log"] == "identity" else m["entries"])][:c.get("prefix")]
        view += [h(c["entry"])] if "entry" in c else []
        checkpoint = (c["checkpoint"][0], h(c["checkpoint"][1])) if "checkpoint" in c else None
        if "statement" in c:
            fn = lambda: formats.verify_upload(h(c["statement"]), h(m["log_id"]), states, directory)
        elif c["log"] == "identity":
            fn = lambda: formats.verify_identity_log(view, h(alice["user_id"]), checkpoint)
        elif "plh" not in c:
            fn = lambda: formats.verify_membership_log(view, m["log_type"], h(m["log_id"]), directory, checkpoint)
        else:
            continue
        problems.append(expect_error(c, fn))
    return problems


# --- lockbox and sealed journal entries

DDK = rnd("device data key")
SLOTS = {"lockbox-l1": [(1, 0, formats.Z16, bytes(26), rnd("keystore key"))],
         "lockbox-l2": [(2, 1, formats.Z16, formats.kdf_params(65536, 3, rnd("passcode salt", 16)), rnd("kek passcode")),
                        (3, 0, formats.Z16, bytes(26), rnd("biometric key")),
                        (4, 0, formats.Z16, bytes(26), formats.subkey(rnd("recovery code entropy"), b"kek/recovery")),
                        (5, 0, ALICE, bytes(26), AMK)]}


def gen_lockbox():
    valid = []
    for (id_, slots), description in zip(SLOTS.items(), ("level L1: the keystore key alone", "level L2: passcode "
                                                         "with hardware binding, biometrics, recovery code, account")):
        slots = [slot + (rnd(f"lockbox nonce {id_} {i}", 24),) for i, slot in enumerate(slots)]
        valid.append({"id": id_, "description": description, "ddk": hx(DDK), "device_id": hx(DEVICE),
                      "slots": [dict(zip(("factor", "binding", "user_id", "params", "key", "nonce"), map(
                          lambda x: x if isinstance(x, int) else hx(x), slot))) for slot in slots],
                      "lockbox": hx(formats.lockbox_seal(DDK, DEVICE, slots))})
    slot = lambda i, at=0: 40 + 188 * i + at
    invalid = [{"id": id_, "description": description, "base": "lockbox-l2", "mutations": mutations, "error": error}
               for id_, description, mutations, error in [
        ("lockbox-short-header", "shorter than the 40-byte header", [{"truncate": 39}], "bad_length"),
        ("lockbox-wrong-type", "a wrap where a lockbox is expected", [{"set": [2, hx(b"W")]}], "wrong_type"),
        ("lockbox-no-slots", "count 0", [{"set": [5, "00"]}], "bad_header"),
        ("lockbox-too-many-slots", "count 9", [{"set": [5, "09"]}], "bad_header"),
        ("lockbox-reserved", "reserved bytes must be zero", [{"set": [6, "01"]}], "bad_header"),
        ("lockbox-bad-length", "one byte short of count slots", [{"truncate": slot(4) - 1}], "bad_length"),
        ("lockbox-unknown-factor", "factor 6 is not assigned", [{"set": [slot(1), "06"]}], "bad_header"),
        ("lockbox-binding-on-biometric", "binding applies to the passcode only", [{"set": [slot(1, 1), "01"]}],
         "bad_header"),
        ("lockbox-user-on-passcode", "user_id applies to the account only", [{"set": [slot(0, 2), hx(ALICE)]}],
         "bad_header"),
        ("lockbox-duplicate-factor", "two passcode slots", [{"set": [slot(1), "02"]}], "bad_header"),
        ("lockbox-wrapped-type", "a slot wrapping an AMK instead of a DeviceDataKey", [{"set": [slot(0, 49), "01"]}],
         "bad_header"),
        ("lockbox-key-id-mismatch", "the slots wrap another key than the lockbox names", [{"flip": 24}],
         "bad_header"),
        ("lockbox-weak-params", "passcode parameters of 32 MiB, below the device floor",
         [{"set": [slot(0, 19), "00008000"]}], "kdf_params_rejected"),
        ("lockbox-other-device", "copied to another device: the device id is in every slot's context",
         [{"set": [8, hx(rnd("another device", 16))]}], "auth_failed"),
        ("lockbox-slot-tampered", "a bit of the passcode slot's sealed key flipped", [{"flip": slot(0, 44 + 100)}],
         "auth_failed"),
    ]]
    invalid.append({"id": "lockbox-other-account", "description": "the account slot moved to another user",
                    "base": "lockbox-l2", "mutations": [{"set": [slot(3, 2), hx(BOB)]}], "slot": 3,
                    "error": "auth_failed"})
    invalid.append({"id": "lockbox-wrong-passcode", "description": "another passcode: rejected by the commitment",
                    "base": "lockbox-l2", "key": hx(rnd("another kek passcode")), "error": "commitment_mismatch"})
    return {"construction": "Lockbox: the DeviceDataKey under each unlock factor", "spec": SPEC + "#lockbox",
            "note": "invalid cases open slot 0, or slot, with that slot's key unless they give one", "valid": valid,
            "invalid": invalid}


def run_lockbox(doc):
    problems = []
    for v in doc["valid"]:
        slots = [tuple(x if isinstance(x, int) else h(x) for x in s.values()) for s in v["slots"]]
        lockbox = formats.lockbox_seal(h(v["ddk"]), h(v["device_id"]), slots)
        if hx(lockbox) != v["lockbox"] or any(formats.lockbox_open(lockbox, i, s[4]) != h(v["ddk"])
                                              for i, s in enumerate(slots)):
            problems.append(f"{v['id']}: lockbox differs")
    for case in doc["invalid"]:
        c = merged(case, doc, "lockbox")
        i = c.get("slot", 0)
        problems.append(expect_error(c, lambda: formats.lockbox_open(c["lockbox"], i, h(c.get("key")
                                                                                        or c["slots"][i]["key"]))))
    return problems


INBOX = formats.subkey(DDK, b"local/inbox")


def gen_journal():
    public = formats.inbox_public_key(INBOX)
    valid = []
    for id_, description, plaintext in (("journal-entry", "an upload acknowledged while locked",
                                         b"\x08\x01\x12\x10upload 2026-10-15"),
                                        ("journal-empty", "an empty plaintext", b"")):
        randomness = rnd("journal randomness " + id_)
        valid.append({"id": id_, "description": description, "inbox_key": hx(INBOX), "public_key": hx(public),
                      "randomness": hx(randomness), "plaintext": hx(plaintext),
                      "entry": hx(formats.journal_seal(public, randomness, plaintext))})
    invalid = [{"id": id_, "description": description, "base": "journal-entry", "mutations": mutations,
                "error": error} for id_, description, mutations, error in [
        ("journal-short", "shorter than header and tag", [{"truncate": 71}], "bad_length"),
        ("journal-wrong-type", "a wrap where a journal entry is expected", [{"set": [2, hx(b"W")]}], "wrong_type"),
        ("journal-reserved", "reserved bytes must be zero", [{"set": [5, "01"]}], "bad_header"),
        ("journal-enc-tampered", "a bit of the ephemeral key flipped", [{"flip": 30}], "auth_failed"),
        ("journal-ciphertext-tampered", "a ciphertext bit flipped", [{"flip": 60}], "auth_failed"),
        ("journal-zero-shared-secret", "an ephemeral key of small order", [{"set": [24, hx(bytes(32))]}],
         "auth_failed"),
    ]]
    invalid.append({"id": "journal-wrong-recipient", "description": "opened with another device's inbox key",
                    "base": "journal-entry", "inbox_key": hx(formats.subkey(rnd("another ddk"), b"local/inbox")),
                    "error": "wrong_recipient"})
    return {"construction": "Sealed journal entries to the inbox key", "spec": SPEC + "#sealed-journal-entries",
            "valid": valid, "invalid": invalid}


def run_journal(doc):
    problems = []
    for v in doc["valid"]:
        entry = formats.journal_seal(h(v["public_key"]), h(v["randomness"]), h(v["plaintext"]))
        if hx(formats.inbox_public_key(h(v["inbox_key"]))) != v["public_key"] or hx(entry) != v["entry"] or \
                formats.journal_open(h(v["inbox_key"]), entry) != h(v["plaintext"]):
            problems.append(f"{v['id']}: entry differs")
    for case in doc["invalid"]:
        c = merged(case, doc, "entry")
        problems.append(expect_error(c, lambda: formats.journal_open(h(c["inbox_key"]), c["entry"])))
    return problems


# --- key derivations, parameter policy, codes and padding

def gen_kdf():
    small = formats.kdf_params(64, 3, rnd("kdf salt", 16))
    cases = [{"function": "key_id", "key": hx(FILE_KEY), "output": hx(formats.key_id(FILE_KEY))},
             {"function": "public_key_id", "public_key": hx(DIRECTORY[ALICE]),
              "output": hx(formats.public_key_id(DIRECTORY[ALICE]))}]
    for password in ("correct horse battery staple", "Cafe\u0301 \u00e9t\u00e9", "Caf\u00e9 \u00e9t\u00e9"):
        cases.append({"function": "kek_password", "password": password,
                      "password_nfc_utf8": hx(formats.password_bytes(password)), "params": hx(small),
                      "argon2id": hx(formats.argon2id(formats.password_bytes(password), small)),
                      "output": hx(formats.kek_password(password, small))})
    for passcode, hw in (("123456", b""), ("123456", rnd("hardware binding")), ("Cafe\u0301 au lait", b"")):
        cases.append({"function": "kek_passcode", "passcode": passcode,
                      "passcode_nfc_utf8": hx(formats.password_bytes(passcode)), "params": hx(small), "hardware": hx(hw),
                      "argon2id": hx(formats.argon2id(formats.password_bytes(passcode), small)),
                      "output": hx(formats.kek_passcode(passcode, small, hw))})
    for label, secret in (("kek/recovery", rnd("recovery entropy")), ("kek/passkey", rnd("passkey prf output")),
                          ("kek/kit", rnd("shamir kit secret")), ("amk/dedup", AMK), ("amk/local-index", AMK),
                          ("amk/settings", AMK), ("grant/return", rnd("grant session key")), ("local/cache", DDK),
                          ("local/inbox", DDK), ("local/settings", DDK)):
        cases.append({"function": "subkey", "label": label, "key": hx(secret),
                      "output": hx(formats.subkey(secret, label.encode()))})
    for label, secret, context in (("local/db", DDK, rnd("database file", 16)),
                                   ("local/object", formats.subkey(DDK, b"local/cache"), rnd("cached object", 16))):
        cases.append({"function": "subkey", "label": label, "key": hx(secret), "context": hx(context),
                      "output": hx(formats.subkey(secret, label.encode(), context))})
    for kind in sorted(formats.CONTENT_KINDS):
        cases.append({"function": "object_key", "file_key": hx(FILE_KEY), "kind": kind,
                      "output": hx(formats.object_key(FILE_KEY, kind))})
    dedup_key = formats.subkey(AMK, b"amk/dedup")
    cases.append({"function": "dedup_token", "dedup_key": hx(dedup_key), "content": hx(b"photo bytes"),
                  "output": hx(formats.dedup_token(dedup_key, b"photo bytes"))})
    password = "hunter2"
    slow = [("argon2id-account-floor", formats.password_bytes("correct horse battery staple"),
             formats.kdf_params(131072, 3, rnd("kdf salt", 16))),
            ("argon2id-link-password", formats.password_bytes(password), formats.link_params(LINK))]
    cases += [argon2id_case(*case) for case in slow]
    secret = rnd("link secret")
    for pw_hash in (b"", h(cases[-1]["output"])):
        key, auth, verifier = formats.link_keys(secret, LINK, pw_hash)
        cases.append({"function": "link_keys", "secret": hx(secret), "link_id": hx(LINK), "password_hash": hx(pw_hash),
                      "link_key": hx(key), "link_auth": hx(auth), "verifier": hx(verifier),
                      "fragment": formats.link_fragment(LINK, secret, bool(pw_hash), b"manifest bytes"),
                      "manifest": hx(b"manifest bytes")})
    for m, t, p, salt_len, ok in ((131072, 3, 1, 16, True), (262144, 3, 1, 16, True), (2097152, 64, 1, 16, True),
                                  (131071, 3, 1, 16, False), (131072, 2, 1, 16, False), (131072, 3, 4, 16, False),
                                  (2097153, 3, 1, 16, False), (131072, 65, 1, 16, False),
                                  (131072, 3, 1, 15, False)):
        params = formats.kdf_params(m, t, bytes(salt_len), p)
        cases.append({"function": "check_account_params", "params": hx(params),
                      "error": None if ok else "kdf_params_rejected"})
    cases.append({"function": "check_account_params", "params": hx(b"\x02" + small[1:]),
                  "error": "kdf_params_rejected"})
    for m, t, p, salt_len, ok in ((65536, 3, 1, 16, True), (2097152, 64, 1, 16, True), (65535, 3, 1, 16, False),
                                  (65536, 2, 1, 16, False), (65536, 3, 2, 16, False), (65536, 3, 1, 15, False)):
        cases.append({"function": "check_device_params", "params": hx(formats.kdf_params(m, t, bytes(salt_len), p)),
                      "error": None if ok else "kdf_params_rejected"})
    for n in (1, 2, 7, 8, 9, 100, 1000, 65537, 1000000):
        cases.append({"function": "padme", "length": n, "output": formats.padme(n)})
    cases.append({"function": "verification_code", "user_a": hx(BOB), "signing_pk_a": hx(DIRECTORY[BOB]),
                  "user_b": hx(ALICE), "signing_pk_b": hx(DIRECTORY[ALICE]),
                  "output": formats.verification_code(BOB, DIRECTORY[BOB], ALICE, DIRECTORY[ALICE])})
    head = sha256(b"log head")
    cases.append({"function": "epoch_code", "log_id": hx(ALBUM), "head": hx(head),
                  "output": formats.epoch_code(ALBUM, head)})
    return {"construction": "Key derivations, Argon2id parameters, safety codes and padding",
            "spec": SPEC + "#key-derivation", "note": "kek_password and kek_passcode use m = 64 KiB to stay fast; "
            "the policies are the separate check_account_params and check_device_params", "cases": cases}


def run_kdf(doc):
    problems = []
    for c in doc["cases"]:
        f, got, want = c["function"], None, c.get("output")
        if f == "key_id":
            got = hx(formats.key_id(h(c["key"])))
        elif f == "public_key_id":
            got = hx(formats.public_key_id(h(c["public_key"])))
        elif f == "kek_password":
            pw = formats.password_bytes(c["password"])
            got = [hx(pw), hx(formats.argon2id(pw, h(c["params"]))), hx(formats.kek_password(c["password"],
                                                                                           h(c["params"])))]
            want = [c["password_nfc_utf8"], c["argon2id"], c["output"]]
        elif f == "kek_passcode":
            pw = formats.password_bytes(c["passcode"])
            got = [hx(pw), hx(formats.argon2id(pw, h(c["params"]))),
                   hx(formats.kek_passcode(c["passcode"], h(c["params"]), h(c["hardware"])))]
            want = [c["passcode_nfc_utf8"], c["argon2id"], c["output"]]
        elif f == "subkey":
            got = hx(formats.subkey(h(c["key"]), c["label"].encode(), h(c.get("context", ""))))
        elif f == "object_key":
            got = hx(formats.object_key(h(c["file_key"]), c["kind"]))
        elif f == "dedup_token":
            got = hx(formats.dedup_token(h(c["dedup_key"]), h(c["content"])))
        elif f == "argon2id":
            if not SLOW:
                continue
            got = hx(formats.argon2id(h(c["secret"]), h(c["params"])))
        elif f == "link_keys":
            got = [hx(x) for x in formats.link_keys(h(c["secret"]), h(c["link_id"]), h(c["password_hash"]))]
            got.append(formats.link_fragment(h(c["link_id"]), h(c["secret"]), bool(c["password_hash"]),
                                             h(c["manifest"])))
            want = [c["link_key"], c["link_auth"], c["verifier"], c["fragment"]]
        elif f in ("check_account_params", "check_device_params"):
            c, check = dict(c, id=f"{f} {c['params']}"), getattr(formats, f)
            if c["error"]:
                problems.append(expect_error(c, lambda: check(h(c["params"]))))
            else:
                check(h(c["params"]))
            continue
        elif f == "padme":
            got = formats.padme(c["length"])
        elif f == "verification_code":
            got = formats.verification_code(h(c["user_a"]), h(c["signing_pk_a"]), h(c["user_b"]),
                                            h(c["signing_pk_b"]))
        elif f == "epoch_code":
            got = formats.epoch_code(h(c["log_id"]), h(c["head"]))
        if got != want:
            problems.append(f"{f}: got {got}")
    return problems


# Argon2id at its real sizes takes minutes in Python, so these outputs are pinned here; --slow recomputes them.
SLOW_OUTPUTS = {"argon2id-account-floor": "982ddad331a03952c79014daad69beea1eaed8af1c0319450e9217f7fbf6df0d",
                "argon2id-link-password": "eebacbdedc424718fe72e6c344227d269564eec28ad282f34b5b2996d7a798c2"}
SLOW_PROBLEMS = []


def argon2id_case(id_, secret, params):
    output = SLOW_OUTPUTS[id_]
    if SLOW:
        output = hx(formats.argon2id(secret, params))
        if output != SLOW_OUTPUTS[id_]:
            SLOW_PROBLEMS.append(f"{id_}: computed {output}, pinned {SLOW_OUTPUTS[id_]}")
    return {"function": "argon2id", "id": id_, "secret": hx(secret), "params": hx(params), "output": output}


# --- OPAQUE with the suite v1 configuration

OPAQUE_PARAMS = formats.kdf_params(64, 3, bytes(16))


def opaque_ksf(params):
    return lambda output: formats.argon2id(output, params, 64)


def gen_opaque():
    server_sk, server_pk = opaque.derive_key_pair(rnd("opaque server seed"), b"OPAQUE-DeriveKeyPair")
    other_sk, other_pk = opaque.derive_key_pair(rnd("opaque other server seed"), b"OPAQUE-DeriveKeyPair")
    inputs = {"password": hx(formats.password_bytes("correct horse battery staple")),
              "credential_identifier": hx(ALICE),
              "oprf_seed": hx(rnd("opaque oprf seed", 64)), "server_private_key": hx(server_sk.to_bytes(32, "little")),
              "server_public_key": hx(server_pk), "ksf_params": hx(OPAQUE_PARAMS),
              "context": hx(b"photolib/v1/opaque"),
              "blind_registration": hx(scalar_from("blind registration")), "envelope_nonce": hx(rnd("envelope nonce")),
              "blind_login": hx(scalar_from("blind login")), "client_nonce": hx(rnd("client nonce")),
              "client_keyshare_seed": hx(rnd("client keyshare")), "masking_nonce": hx(rnd("masking nonce")),
              "server_nonce": hx(rnd("server nonce")), "server_keyshare_seed": hx(rnd("server keyshare"))}
    out = opaque_transcript(inputs)
    return {"construction": "OPAQUE-3DH registration and login, suite v1 configuration", "spec": SPEC + "#opaque",
            "configuration": "ristretto255-SHA512 OPRF, HKDF-SHA512, HMAC-SHA512, SHA-512, ristretto255, KSF "
                             "Argon2id(S = 16 zero bytes, p = 1, T = 64, m and t from ksf_params); ksf_params here are "
                             "below the account floor so the vector runs quickly",
            "inputs": inputs, "outputs": {k: hx(v) for k, v in out.items()},
            "invalid": [{"id": "opaque-wrong-password", "description": "the envelope does not open",
                         "password": hx(b"correct horse battery stapler"), "error": "envelope_recovery"},
                        {"id": "opaque-substituted-server-key", "description": "a server answering with another key "
                         "pair: the envelope binds the registered server public key",
                         "server_private_key": hx(other_sk.to_bytes(32, "little")), "server_public_key": hx(other_pk),
                         "error": "envelope_recovery"}]}


def scalar_from(label):
    return (int.from_bytes(rnd(label, 64), "little") % prims.L).to_bytes(32, "little")


def opaque_transcript(i, record=None, **over):
    """Registration (unless a record is given), then one login; `over` replaces login inputs."""
    ksf, j = opaque_ksf(h(i["ksf_params"])), dict(i, **over)
    out = {} if record else opaque.register(h(i["password"]), h(i["credential_identifier"]), h(i["oprf_seed"]),
                                            h(i["server_public_key"]), scalar(i["blind_registration"]),
                                            h(i["envelope_nonce"]), ksf)
    login = opaque.login(h(j["password"]), record or out["registration_record"], h(i["credential_identifier"]),
                         h(i["oprf_seed"]), scalar(j["server_private_key"]), h(j["server_public_key"]),
                         h(i["context"]), ksf, opaque_randomness(i, "blind_login"))
    return {**out, **login, "export_key": login["export_key"]}


def run_opaque(doc):
    i, problems = doc["inputs"], []
    if {k: hx(v) for k, v in opaque_transcript(i).items()} != doc["outputs"]:
        problems.append("opaque transcript differs")
    record = h(doc["outputs"]["registration_record"])
    for c in doc["invalid"]:
        problems.append(expect_error(c, lambda: opaque_transcript(i, record, **{k: v for k, v in c.items() if k in i})))
    return problems


def gen_recovery():
    entropy = rnd("recovery entropy")
    phrase = formats.recovery_phrase(entropy)
    words = phrase.split()
    typed = "  " + "\t".join(w.upper() if i % 2 else w for i, w in enumerate(words[:12])) + "\n" + " ".join(words[12:])
    other = rnd("other recovery entropy")
    valid = [{"id": id_, "entropy": hx(e), "phrase": p, "output": hx(formats.kek_recovery(e))}
             for id_, e, p in (("recovery-phrase", entropy, phrase), ("recovery-other", other,
                                                                      formats.recovery_phrase(other)),
                               ("recovery-typed", entropy, typed))]
    valid[2]["description"] = "case and whitespace as typed: ASCII letters in any case, any run of ASCII whitespace"
    last = formats.WORDS[(formats.WORDS.index(words[-1]) + 1) % 2048]
    rows = (("recovery-bad-checksum", "the last word changed", words[:-1] + [last], "bad_checksum"),
            ("recovery-unknown-word", "word 7 is not in the list", words[:6] + ["photolib"] + words[7:],
             "unknown_word"),
            ("recovery-non-ascii-letter", "word 3 is 'kite' with U+212A KELVIN SIGN, a k only outside ASCII",
             words[:2] + ["\u212aite"] + words[3:], "unknown_word"),
            ("recovery-23-words", "the last word missing", words[:-1], "bad_length"),
            ("recovery-25-words", "a word too many", words + ["abandon"], "bad_length"),
            ("recovery-12-words", "a valid 12-word BIP-39 phrase: only 24 words encode the 32-byte entropy",
             ["abandon"] * 11 + ["about"], "bad_length"))
    invalid = [{"id": id_, "description": d, "phrase": " ".join(w), "error": e} for id_, d, w, e in rows]
    invalid[1]["word"], invalid[2]["word"] = 7, 3
    return {"construction": "The recovery phrase and KEK_rec", "spec": SPEC + "#recovery-phrase", "valid": valid,
            "invalid": invalid}


def run_recovery(doc):
    problems = []
    for v in doc["valid"]:
        if formats.recovery_entropy(v["phrase"]) != h(v["entropy"]):
            problems.append(f"{v['id']}: reads as another entropy")
        if "description" not in v and formats.recovery_phrase(h(v["entropy"])) != v["phrase"]:
            problems.append(f"{v['id']}: phrase differs")
        if hx(formats.kek_recovery(h(v["entropy"]))) != v["output"]:
            problems.append(f"{v['id']}: KEK_rec differs")
    for c in doc["invalid"]:
        try:
            formats.recovery_entropy(c["phrase"])
            problems.append(f"{c['id']}: accepted, want {c['error']}")
        except prims.Reject as e:
            if (str(e), getattr(e, "word", None)) != (c["error"], c.get("word")):
                problems.append(f"{c['id']}: rejected with {e} at word {getattr(e, 'word', None)}")
    return problems


def check_mapping(spec, docs):
    """The threat-model mapping names every wrapped type, object type, log and public key, and cites only vectors
    that exist as invalid cases; every vector file points at a heading of the specification."""
    if not spec.exists():
        return [f"{spec} is missing"]
    text = spec.read_text()
    headings = {re.sub(r"[-\s]+", "-", re.sub(r"[^\w\s-]", "", line.lstrip("#")).strip().lower())
                for line in text.splitlines() if line.startswith("#")}
    problems = [f"{name}.json: no heading #{doc['spec'].split('#')[1]}" for name, doc in docs.items()
                if doc["spec"].split("#")[1] not in headings]
    ids = [c["id"] for doc in docs.values() for c in doc.get("invalid", [])]
    problems += [f"invalid vector id {i} is not unique" for i in sorted(set(ids)) if ids.count(i) > 1]
    section = text.split("## Threat-model mapping", 1)[-1].split("\n## ", 1)[0]
    rows = [[c.strip() for c in line.strip("|").split("|")] for line in section.splitlines()
            if line.startswith("| ") and not line.startswith("| Item")]
    expected = {"key wrap": set(formats.WRAPPED_TYPES.values()), "chunk": {"PLB chunk", "PLX chunk"},
                "log": set(formats.LOG_TYPES.values()), "public key": set(formats.PUBLIC_KEYS),
                "local": set(formats.LOCAL_FILES)}
    for kind, items in expected.items():
        found = {(re.match(r"`([^`]+)`", row[0]) or re.match(r"(.*)", row[0])).group(1) for row in rows
                 if len(row) == 5 and row[1] == kind}
        problems += [f"threat-model mapping: no {kind} row for {item}" for item in sorted(items - found)]
        problems += [f"threat-model mapping: unknown {kind} {item}" for item in sorted(found - items)]
    for row in rows:
        cited = re.findall(r"`([a-z0-9-]+)`", row[-1]) if len(row) == 5 else []
        if not cited or not row[2]:
            problems.append(f"threat-model mapping: row {row[0]} names no mechanism or rejection vector")
        problems += [f"threat-model mapping: {row[0]} cites unknown vector {i}" for i in cited if i not in ids]
    return problems


CONSTRUCTIONS = {"plb": (gen_plb, run_plb), "plw": (gen_plw, run_plw), "plh": (gen_plh, run_plh),
                 "pls": (gen_pls, run_pls), "kdf": (gen_kdf, run_kdf), "opaque": (gen_opaque, run_opaque),
                 "lockbox": (gen_lockbox, run_lockbox), "journal": (gen_journal, run_journal),
                 "recovery": (gen_recovery, run_recovery)}


SLOW = "--slow" in sys.argv


def main(argv):
    check = "--check" in argv
    out = Path(argv[argv.index("--dir") + 1]) if "--dir" in argv else OUT
    spec = Path(argv[argv.index("--spec") + 1]) if "--spec" in argv else ROOT / SPEC
    problems, docs = check_primitives(), {}
    for name, (generate, run) in CONSTRUCTIONS.items():
        path = out / f"{name}.json"
        text = json.dumps(generate(), indent=1, ensure_ascii=False) + "\n"
        if not check:
            out.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        elif not path.exists() or path.read_text() != text:
            problems.append(f"{path.relative_to(ROOT) if path.is_relative_to(ROOT) else path} is not what "
                            "vectors.py generates: run python3 tools/cryptoref/vectors.py")
        if path.exists():
            docs[name] = json.loads(path.read_text())
            problems += [p for p in run(docs[name]) if p]
    problems += check_mapping(spec, docs)
    problems += SLOW_PROBLEMS
    for p in problems:
        print(f"FAIL: {p}", file=sys.stderr)
    if not problems:
        print("ok: primitives match their published vectors; " + ("the committed vectors are current and pass"
                                                                    if check else f"vectors written to {out}"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
