"""Crypto suite v1 formats of docs/dev/crypto-v1.md, built on prims. Reference only: every check raises Reject with
the error code the specification assigns, in the order the specification lists the checks."""
import base64
import hashlib
import hmac
import re
import struct
import unicodedata
from pathlib import Path

import prims
from prims import Reject, hkdf, hkdf_expand, hkdf_extract, sha256

MAGIC, VERSION, SUITE = b"PL", 1, 1
BLOB, MANIFEST, WRAP, HPKE, SIGNED, LOCKBOX, JOURNAL = b"B", b"X", b"W", b"H", b"S", b"L", b"J"
Z16, Z32 = bytes(16), bytes(32)

CONTENT_KINDS = {1: "original", 2: "preview", 3: "thumbnail", 4: "metadata", 5: "embedding", 6: "stream",
                 7: "stream_index", 8: "sidecar", 9: "edit_recipe", 10: "manifest", 11: "local"}
WRAPPED_TYPES = {1: "AMK", 2: "LibraryKey", 3: "AlbumKey", 4: "VaultKey", 5: "FileKey", 6: "RenditionKey",
                 7: "LinkSecret", 8: "SigningKey", 9: "DecryptionKey", 10: "GrantSessionKey", 11: "OutputKey",
                 12: "DeviceDataKey"}
LOG_TYPES = {1: "identity", 2: "album", 3: "library", 4: "statement"}
IDENTITY_BODIES = {1: "genesis", 2: "rotate_encryption_key", 3: "rotate_signing_key", 4: "add_device",
                   5: "remove_device", 6: "rotate_amk"}
MEMBERSHIP_BODIES = {1: "create", 2: "add_member", 3: "remove_member", 4: "set_role", 5: "new_epoch", 6: "add_link",
                     7: "remove_link", 8: "set_drop_key", 9: "update_member_key"}
PUBLIC_KEYS = ("identity signing key", "identity encryption key", "device encryption key", "member signing key",
               "drop key", "grant worker key", "instance signing key", "OPAQUE server key", "inbox key")
LOCAL_FILES = ("lockbox", "journal entry")
FACTORS = {1: "keystore", 2: "passcode", 3: "biometric", 4: "recovery code", 5: "account"}
PASSCODE, ACCOUNT = 2, 5
VIEWER, CONTRIBUTOR, ADMIN = 1, 2, 3
XWING_PK = 1216


def u16(n):
    return struct.pack(">H", n)


def u32(n):
    return struct.pack(">I", n)


def u64(n):
    return struct.pack(">Q", n)


def key_id(key):
    return hkdf(key, b"photolib/v1/key-id", 16)


def public_key_id(pk):
    return sha256(pk)[:16]


def _prefix(obj, types):
    if len(obj) < 8:
        raise Reject("bad_length")
    if obj[:2] != MAGIC:
        raise Reject("bad_magic")
    if obj[2:3] not in types:
        raise Reject("wrong_type")
    if obj[3] != VERSION:
        raise Reject("unsupported_version")
    if obj[4] != SUITE:
        raise Reject("unsupported_suite")


# --- derivations

def subkey(key, label, context=b""):
    return hkdf(key, b"photolib/v1/" + label + context)


def object_key(file_key, kind):
    return hkdf(file_key, b"photolib/v1/file-key" + bytes([kind]))


def kdf_params(m_kib, t, salt, p=1):
    return bytes([1]) + u32(m_kib) + u32(t) + bytes([p]) + salt


def check_account_params(params, m_min=131072):
    """The account policy: Argon2id, 128 MiB to 2 GiB, 3 to 64 passes, one lane, 16-byte salt."""
    if len(params) != 26 or params[0] != 1:
        raise Reject("kdf_params_rejected")
    m, t = struct.unpack(">II", params[1:9])
    if not (m_min <= m <= 2097152 and 3 <= t <= 64 and params[9] == 1):
        raise Reject("kdf_params_rejected")


def check_device_params(params):
    """The device policy: as the account's, from 64 MiB."""
    check_account_params(params, 65536)


def argon2id(secret, params, length=32):
    m, t = struct.unpack(">II", params[1:9])
    return prims.argon2id(secret, params[10:], m, t, params[9], length)


def password_bytes(password):
    return unicodedata.normalize("NFC", password).encode()


def kek_password(password, params):
    return hkdf(argon2id(password_bytes(password), params), b"photolib/v1/kek/password")


def kek_passcode(passcode, params, hw):
    return hkdf(argon2id(password_bytes(passcode), params) + hw, b"photolib/v1/kek/passcode")


# --- the recovery phrase: BIP-39's English encoding of the recovery entropy

WORDLIST = Path(__file__).resolve().parents[2] / "kernel" / "src" / "bip39-english.txt"
WORDLIST_SHA256 = "2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda"
WORDS = WORDLIST.read_text().split("\n")[:2048]
ASCII_UPPER = str.maketrans("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz")


def recovery_phrase(entropy):
    """24 words, each 11 bits of the entropy followed by the first byte of its SHA-256."""
    bits = int.from_bytes(entropy + sha256(entropy)[:1], "big")
    return " ".join(WORDS[bits >> 11 * (23 - i) & 2047] for i in range(24))


def recovery_entropy(phrase):
    """The entropy a typed phrase encodes: words split at ASCII whitespace, ASCII letters in any case."""
    words = [w for w in re.split("[\t\n\f\r ]", phrase) if w]
    if len(words) != 24:
        raise Reject("bad_length")
    bits = 0
    for i, word in enumerate(words):
        if word.translate(ASCII_UPPER) not in WORDS:
            error = Reject("unknown_word")
            error.word = i + 1
            raise error
        bits = bits << 11 | WORDS.index(word.translate(ASCII_UPPER))
    data = bits.to_bytes(33, "big")
    if sha256(data[:32])[:1] != data[32:]:
        raise Reject("bad_checksum")
    return data[:32]


def kek_recovery(entropy):
    return hkdf(entropy, b"photolib/v1/kek/recovery")


def link_params(link_id):
    """Link and export passwords: fixed 64 MiB, 3 passes, the link id as salt."""
    return kdf_params(65536, 3, link_id)


def link_keys(secret, link_id, password_hash=b""):
    """(LinkKey, LinkAuth, verifier) of a public link or a static export."""
    auth = hkdf(secret, b"photolib/v1/link/auth" + link_id)
    return hkdf(secret + password_hash, b"photolib/v1/link/key" + link_id), auth, sha256(auth)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def link_fragment(link_id, secret, password, manifest=None):
    parts = ["v1", b64url(link_id), b64url(secret)] + (["p"] if password else [])
    return ".".join(parts + ([b64url(sha256(manifest)[:8])] if manifest else []))


def dedup_token(dedup_key, content):
    return hmac.new(dedup_key, sha256(content), "sha256").digest()


def _digits(data, groups):
    return " ".join(f"{int.from_bytes(data[5 * i:5 * i + 5], 'big') % 100000:05d}" for i in range(groups))


def verification_code(user_a, sign_pk_a, user_b, sign_pk_b):
    """Safety number two users compare out of band: 30 digits per user, the lower user id first."""
    half = lambda u, pk: _digits(hashlib.sha512(b"photolib/v1/verification" + u + pk).digest(), 6)
    pair = sorted([(user_a, sign_pk_a), (user_b, sign_pk_b)])
    return half(*pair[0]) + " " + half(*pair[1])


def epoch_code(log_id, head):
    return _digits(sha256(b"photolib/v1/epoch-code" + log_id + head), 4)


def padme(n):
    e = n.bit_length() - 1
    mask = (1 << (e - e.bit_length())) - 1
    return (n + mask) & ~mask


# --- PLB / PLX: chunked envelope

def _plb_keys(key, salt):
    prk = hkdf_extract(salt, key)
    return hkdf_expand(prk, b"photolib/v1/plb/payload", 32), hkdf_expand(prk, b"photolib/v1/plb/commit", 32)


def _chunk_nonce(i, last):
    return i.to_bytes(11, "big") + bytes([last])


def plb_seal(key, plaintext, kind, salt, padded=False, chunk_log2=16, typ=BLOB, flags=None):
    if padded:
        plaintext += b"\x80" + bytes(padme(len(plaintext) + 1) - len(plaintext) - 1)
    payload_key, commit = _plb_keys(key, salt)
    header = MAGIC + typ + bytes([VERSION, SUITE, kind, chunk_log2, padded if flags is None else flags]) + \
        key_id(key) + salt + commit
    size = 1 << chunk_log2
    chunks = [plaintext[i:i + size] for i in range(0, len(plaintext), size)] or [b""]
    return header + b"".join(prims.aead_seal(payload_key, _chunk_nonce(i, i == len(chunks) - 1), c, header)
                             for i, c in enumerate(chunks))


def plb_open(key, envelope, kind, typ=BLOB):
    _prefix(envelope, (typ,))
    if len(envelope) < 88:
        raise Reject("bad_length")
    header, body = envelope[:88], envelope[88:]
    if not 16 <= header[6] <= 22 or header[7] & ~1 or (typ == MANIFEST) != (header[5] == 10):
        raise Reject("bad_header")
    step = (1 << header[6]) + 16
    n, rest = divmod(len(body), step)
    if not body or 0 < rest < 16 or (rest == 16 and n):
        raise Reject("bad_length")
    n += rest > 0
    payload_key, commit = _plb_keys(key, header[24:56])
    if not hmac.compare_digest(commit, header[56:88]):
        raise Reject("commitment_mismatch")
    out = b"".join(prims.aead_open(payload_key, _chunk_nonce(i, i == n - 1), body[i * step:(i + 1) * step], header)
                   for i in range(n))
    if header[5] != kind:
        raise Reject("wrong_kind")
    if header[7] & 1:
        stripped = out.rstrip(b"\0")
        if not stripped.endswith(b"\x80") or len(out) != padme(len(stripped)):
            raise Reject("bad_padding")
        out = stripped[:-1]
    return out


# --- PLW: symmetric key wrap, PLH: HPKE key wrap

def wrap_context(user_id=Z16, container_id=Z16, subject_id=Z16, number=0):
    return user_id + container_id + subject_id + u32(number)


def _plw_keys(wrapping_key, nonce):
    prk = hkdf_extract(nonce, wrapping_key)
    return hkdf_expand(prk, b"photolib/v1/plw/key", 32), hkdf_expand(prk, b"photolib/v1/plw/commit", 32)


def plw_seal(wrapping_key, key, wrapped_type, context, nonce, wrapped_key_id=None):
    enc_key, commit = _plw_keys(wrapping_key, nonce)
    header = MAGIC + WRAP + bytes([VERSION, SUITE, wrapped_type, 0, 0]) + key_id(wrapping_key) + \
        (wrapped_key_id or key_id(key)) + nonce + commit
    return header + prims.xaead_seal(enc_key, nonce, key, header + context)


def _wrap_header(wrap, typ, size):
    _prefix(wrap, (typ,))
    if len(wrap) != size:
        raise Reject("bad_length")
    if wrap[5] not in WRAPPED_TYPES or wrap[6:8] != b"\0\0":
        raise Reject("bad_header")


def _check_unwrapped(wrap, key, wrapped_type, key_id_at):
    if key_id(key) != wrap[key_id_at:key_id_at + 16]:
        raise Reject("bad_key_id")
    if wrap[5] != wrapped_type:
        raise Reject("wrong_kind")
    return key


def plw_open(wrapping_key, wrap, wrapped_type, context):
    _wrap_header(wrap, WRAP, 144)
    enc_key, commit = _plw_keys(wrapping_key, wrap[40:64])
    if not hmac.compare_digest(commit, wrap[64:96]):
        raise Reject("commitment_mismatch")
    return _check_unwrapped(wrap, prims.xaead_open(enc_key, wrap[40:64], wrap[96:], wrap[:96] + context),
                            wrapped_type, 24)


def plh_seal(recipient_pk, key, wrapped_type, context, sender_key_id, eseed):
    header = MAGIC + HPKE + bytes([VERSION, SUITE, wrapped_type, 0, 0]) + public_key_id(recipient_pk) + \
        sender_key_id + key_id(key)
    enc, sealed = prims.hpke_seal(recipient_pk, eseed, b"photolib/v1/plh" + context, header, key)
    return header + enc + sealed


def plh_open(recipient_sk, wrap, wrapped_type, context):
    _wrap_header(wrap, HPKE, 1224)
    if wrap[8:24] != public_key_id(prims.xwing_public(recipient_sk)):
        raise Reject("wrong_recipient")
    key = prims.hpke_open(recipient_sk, wrap[56:1176], b"photolib/v1/plh" + context, wrap[:56], wrap[1176:])
    return _check_unwrapped(wrap, key, wrapped_type, 40)


# --- lockbox and sealed journal entries: local data protection

def lockbox_seal(ddk, device_id, slots):
    """slots: (factor, binding, user_id, params, key, nonce) each."""
    out = MAGIC + LOCKBOX + bytes([VERSION, SUITE, len(slots), 0, 0]) + device_id + key_id(ddk)
    for factor, binding, user_id, params, key, nonce in slots:
        out += bytes([factor, binding]) + user_id + params + plw_seal(key, ddk, 12, wrap_context(user_id, device_id),
                                                                      nonce)
    return out


def lockbox_slots(lockbox):
    """The checked slots of a lockbox: (factor, binding, user_id, params, wrap) each."""
    _prefix(lockbox, (LOCKBOX,))
    if len(lockbox) < 40:
        raise Reject("bad_length")
    n = lockbox[5]
    if not 1 <= n <= 8 or lockbox[6:8] != b"\0\0":
        raise Reject("bad_header")
    if len(lockbox) != 40 + 188 * n:
        raise Reject("bad_length")
    slots = [(s[0], s[1], s[2:18], s[18:44], s[44:]) for s in (lockbox[40 + 188 * i:228 + 188 * i] for i in range(n))]
    for i, (factor, binding, user_id, params, wrap) in enumerate(slots):
        if factor not in FACTORS or (binding > 1 or binding and factor != PASSCODE) or \
                (user_id != Z16 and factor != ACCOUNT) or (params != bytes(26) and factor != PASSCODE) or \
                any(f == factor and (factor != ACCOUNT or u == user_id) for f, _, u, _, _ in slots[:i]) or \
                wrap[:8] != MAGIC + WRAP + bytes([VERSION, SUITE, 12, 0, 0]) or wrap[24:40] != lockbox[24:40]:
            raise Reject("bad_header")
    for factor, _, _, params, _ in slots:
        if factor == PASSCODE:
            check_device_params(params)
    return slots


def lockbox_open(lockbox, slot, key):
    _, _, user_id, _, wrap = lockbox_slots(lockbox)[slot]
    return plw_open(key, wrap, 12, wrap_context(user_id, lockbox[8:24]))


JOURNAL_INFO = b"photolib/v1/journal"


def inbox_public_key(inbox_key):
    return prims.dhkem_key_pair(inbox_key)[1]


def journal_seal(public_key, randomness, plaintext):
    header = MAGIC + JOURNAL + bytes([VERSION, SUITE, 0, 0, 0]) + public_key_id(public_key) + \
        prims.dhkem_key_pair(randomness)[1]
    return header + prims.hpke_seal(public_key, randomness, JOURNAL_INFO, header, plaintext, prims.X25519_KEM)[1]


def journal_open(inbox_key, entry):
    _prefix(entry, (JOURNAL,))
    if len(entry) < 72:
        raise Reject("bad_length")
    if entry[5:8] != b"\0\0\0":
        raise Reject("bad_header")
    sk, pk = prims.dhkem_key_pair(inbox_key)
    if entry[8:24] != public_key_id(pk):
        raise Reject("wrong_recipient")
    return prims.hpke_open(sk, entry[24:56], JOURNAL_INFO, entry[:56], entry[56:], prims.X25519_KEM)


# --- PLS: signed statements and hash-chained logs

def pls_sign(seed, log_type, body_type, log_id, seq, prev_hash, time_ms, body):
    msg = MAGIC + SIGNED + bytes([VERSION, SUITE, log_type]) + u16(body_type) + public_key_id(
        prims.ed25519_public(seed)) + log_id + u64(seq) + prev_hash + u64(time_ms) + u32(len(body)) + body
    return msg + prims.ed25519_sign(seed, msg)


def pls_parse(entry):
    _prefix(entry, (SIGNED,))
    if len(entry) < 156 or len(entry) != 156 + struct.unpack(">I", entry[88:92])[0]:
        raise Reject("bad_length")
    if entry[5] not in LOG_TYPES:
        raise Reject("bad_header")
    return {"log_type": entry[5], "body_type": struct.unpack(">H", entry[6:8])[0], "signer": entry[8:24],
            "log_id": entry[24:40], "seq": struct.unpack(">Q", entry[40:48])[0], "prev_hash": entry[48:80],
            "body": entry[92:-64]}


def entry_hash(entry):
    return sha256(entry)


def _verify_signature(entry, pk):
    if not prims.ed25519_verify(pk, entry[:-64], entry[-64:]):
        raise Reject("bad_signature")


def _check_chain(e, log_type, log_id, seq, prev):
    if e["log_type"] != log_type or e["log_id"] != log_id or e["seq"] != seq or e["prev_hash"] != prev:
        raise Reject("broken_chain")


def _body(e, sizes):
    """Checks the body type is known for the log and the body has its exact length."""
    size, body = sizes.get(e["body_type"]), e["body"]
    if size is None or len(body) != (size(body) if callable(size) else size):
        raise Reject("invalid_entry")
    return body


IDENTITY_SIZES = {1: 32 + XWING_PK, 2: XWING_PK, 3: 33, 4: 16 + XWING_PK + 32, 5: 16, 6: 4}


def _check_checkpoint(entries, checkpoint):
    """A reader that follows a log keeps its last verified (seq, entry_hash) and refuses a view without it."""
    if checkpoint and (len(entries) <= checkpoint[0] or entry_hash(entries[checkpoint[0]]) != checkpoint[1]):
        raise Reject("rollback")


def verify_identity_log(entries, user_id, checkpoint=None):
    """Replays a user's identity log; returns the state after each entry or raises at the first bad one."""
    _check_checkpoint(entries, checkpoint)
    states = []
    for seq, entry in enumerate(entries):
        e = pls_parse(entry)
        _check_chain(e, 1, user_id, seq, states[-1]["head"] if states else Z32)
        if seq == 0:
            body = _body(e, {1: IDENTITY_SIZES[1]})
            state = {"sign_keys": [body[:32]], "enc_pk": body[32:], "devices": {}, "amk_generation": 0}
        else:
            state = {**states[-1], "devices": dict(states[-1]["devices"])}
        if e["signer"] != public_key_id(state["sign_keys"][-1]):
            raise Reject("unauthorized")
        _verify_signature(entry, state["sign_keys"][-1])
        body = _body(e, {k: v for k, v in IDENTITY_SIZES.items() if (k == 1) == (seq == 0)})
        kind, wraps = IDENTITY_BODIES[e["body_type"]], {}
        if kind == "rotate_encryption_key":
            state["enc_pk"] = body
        elif kind == "rotate_signing_key":
            if body[0] != SUITE:
                raise Reject("invalid_entry")
            state["sign_keys"] = state["sign_keys"] + [body[1:]]
        elif kind == "add_device":
            if body[:16] in state["devices"]:
                raise Reject("invalid_entry")
            state["devices"][body[:16]] = body[16:16 + XWING_PK]
            wraps = {body[:16]: body[16 + XWING_PK:]}
        elif kind == "remove_device":
            if state["devices"].pop(body[:16], None) is None:
                raise Reject("invalid_entry")
        elif kind == "rotate_amk":
            if struct.unpack(">I", body)[0] != state["amk_generation"] + 1:
                raise Reject("invalid_entry")
            state["amk_generation"] += 1
        states.append({**state, "head": entry_hash(entry), "wraps": wraps})
    return states


MEMBERSHIP_SIZES = {1: 32, 2: 65, 3: 16, 4: 17, 6: 17, 7: 16, 8: 16 + XWING_PK, 9: 32,
                    5: lambda body: 38 + 48 * struct.unpack(">H", body[36:38])[0] if len(body) >= 38 else -1}


def _key_index(directory, user, kid):
    """Position of a signing key in the user's verified identity log (oldest first), or None."""
    return next((i for i, pk in enumerate(directory.get(user, [])) if public_key_id(pk) == kid), None)


def _signer(state, e, directory):
    """The member whose pinned signing key signed the entry, and that key."""
    for user, (role, kid) in state["members"].items():
        if kid == e["signer"]:
            return user, directory[user][_key_index(directory, user, kid)]
    raise Reject("unauthorized")


def verify_membership_log(entries, log_type, log_id, directory, checkpoint=None):
    """Replays an album or library membership log. `directory` maps each user id to the signing public keys of their
    verified identity log, oldest first. Returns the state after each entry."""
    _check_checkpoint(entries, checkpoint)
    states = []
    for seq, entry in enumerate(entries):
        e = pls_parse(entry)
        _check_chain(e, log_type, log_id, seq, states[-1]["head"] if states else Z32)
        if seq == 0:
            body = _body(e, {1: 32})
            if _key_index(directory, body[:16], body[16:]) is None:
                raise Reject("invalid_entry")
            state = {"owner": body[:16], "members": {body[:16]: (ADMIN, body[16:])}, "epoch": 0,
                     "rotation_due": False, "links": {}, "wraps": {}}
        else:
            state = states[-1]
        signer, pk = _signer(state, e, directory)
        _verify_signature(entry, pk)
        if seq > 0:
            state = _apply_membership(state, e, signer, directory)
        states.append({**state, "head": entry_hash(entry)})
    return states


def _apply_membership(state, e, signer, directory):
    body = _body(e, {k: v for k, v in MEMBERSHIP_SIZES.items() if k != 1})
    kind, user = MEMBERSHIP_BODIES[e["body_type"]], body[:16]
    if state["members"][signer][0] != ADMIN and not (kind == "update_member_key" and user == signer):
        raise Reject("unauthorized")
    members, links, wraps = dict(state["members"]), dict(state["links"]), {}
    if state["rotation_due"] and kind not in ("remove_member", "new_epoch"):
        raise Reject("invalid_entry")
    if kind == "add_member":
        if user in members or _key_index(directory, user, body[16:32]) is None or body[32] not in (1, 2, 3):
            raise Reject("invalid_entry")
        members[user], wraps = (body[32], body[16:32]), {user: body[33:65]}
    elif kind in ("remove_member", "set_role", "update_member_key"):
        if user not in members or (user == state["owner"] and kind != "update_member_key"):
            raise Reject("invalid_entry")
        role, kid = members.pop(user)
        if kind == "set_role":
            if body[16] not in (1, 2, 3):
                raise Reject("invalid_entry")
            members[user] = (body[16], kid)
        elif kind == "update_member_key":
            new = _key_index(directory, user, body[16:32])
            if new is None or new <= _key_index(directory, user, kid):
                raise Reject("invalid_entry")
            members[user] = (role, body[16:32])
    elif kind == "new_epoch":
        wraps = {body[38 + 48 * i:54 + 48 * i]: body[54 + 48 * i:86 + 48 * i]
                 for i in range(struct.unpack(">H", body[36:38])[0])}
        if struct.unpack(">I", body[:4])[0] != state["epoch"] + 1 or len(wraps) != struct.unpack(">H", body[36:38])[0] \
                or set(wraps) != set(members) - {signer}:
            raise Reject("invalid_entry")
    elif kind == "add_link":
        if user in links or body[16] & ~7:
            raise Reject("invalid_entry")
        links[user] = None
    elif user not in links:
        raise Reject("invalid_entry")
    elif kind == "remove_link":
        del links[user]
    else:
        links[user] = body[16:]
    return {**state, "members": members, "links": links, "wraps": wraps,
            "epoch": state["epoch"] + (kind == "new_epoch"),
            "rotation_due": (state["rotation_due"] or kind == "remove_member") and kind != "new_epoch"}


def accept_shared_key(state, recipient_id, sk, plh, wrapped_type, context):
    """A recipient opens a PLH only if the verified log entry that delivered it (its state, from verify_*_log) names
    its hash for this recipient."""
    if state["wraps"].get(recipient_id) != sha256(plh):
        raise Reject("unsigned_wrap")
    return plh_open(sk, plh, wrapped_type, context)


def verify_upload(statement, log_id, membership_states, directory):
    """An uploader's signed statement: the signer may upload at the log position it names and still may at the
    reader's head, and no new epoch was due there."""
    e = pls_parse(statement)
    _check_chain(e, 4, log_id, 0, Z32)
    body = _body(e, {1: 92})
    seq = struct.unpack(">Q", body[20:28])[0]
    if seq >= len(membership_states) or membership_states[seq]["head"] != body[28:60]:
        raise Reject("invalid_entry")
    at, head = membership_states[seq], membership_states[-1]
    signer, pk = _signer(at, e, directory)
    _verify_signature(statement, pk)
    if struct.unpack(">I", body[16:20])[0] != at["epoch"] or at["rotation_due"]:
        raise Reject("invalid_entry")
    if at["members"][signer][0] < CONTRIBUTOR or head["members"].get(signer, (0,))[0] < CONTRIBUTOR:
        raise Reject("unauthorized")
    return {"file_id": body[:16], "objects_hash": body[60:92], "uploader": signer}


def objects_hash(envelopes):
    return sha256(b"".join(sha256(e) for e in envelopes))
