# Crypto suite v1: envelope formats, keys and logs

* **Status**: Accepted — 2026-10-15 ([ADR-0025](../adr/0025-crypto-suite-v1-specification.md)). The external
  cryptography audit (M6-14) reviews this specification before private mode leaves beta.
* **Design**: ADR-0010 and 06 §3–§5.
  **Vectors**: `kernel/testvectors/crypto/`.

This page is normative: two implementations that follow it produce identical bytes. MUST, SHOULD and MAY are used as
in RFC 2119. It fixes every format before anything is encrypted; [the end of the page](#owned-elsewhere) lists the
formats that later tasks add within its registries.

## Conventions

* Integers are unsigned big-endian unless a primitive's RFC says otherwise. `‖` is concatenation, `a..b)` a byte
  range, `Z(n)` n zero bytes.
* Identifiers (users, libraries, albums, files, links, grants, devices) are 16 bytes.
* `HKDF(ikm, info, L = 32)` is HKDF-SHA256 (RFC 5869) with an empty salt. Every `info` label starts with
  `photolib/v1/`; this page writes it as `…/`, so `…/key-id` means `photolib/v1/key-id`.
* `key_id(k) = HKDF(k, …/key-id, 16)` names a symmetric key; `pk_id(pk) = SHA-256(pk)[0..16)` names a public key.
* Readers compare secrets and tags in constant time and zeroize key material after use.

### Primitives

All of them exist in pure Rust ([ADR-0004), so the kernel runs natively and in WASM with no C dependency.

| Primitive | Specification | Rust crate |
|---|---|---|
| ChaCha20-Poly1305, XChaCha20-Poly1305 | RFC 8439; draft-irtf-cfrg-xchacha-03 | `chacha20poly1305` |
| HKDF-SHA256, HMAC-SHA256/512, SHA-256/512, SHA3, SHAKE | RFC 5869, RFC 2104, FIPS 180-4, FIPS 202 | `hkdf`, `hmac`, `sha2`, `sha3` |
| X-Wing (ML-KEM-768 + X25519) | draft-connolly-cfrg-xwing-kem-11, FIPS 203, RFC 7748 | `x-wing` or `ml-kem` + `x25519-dalek` |
| HPKE base mode, KEMs `0x647a` and DHKEM(X25519) `0x0020` | RFC 9180; draft-ietf-hpke-pq-05 (MLKEM768-X25519 ≡ X-Wing) | `hpke` |
| Ed25519 | RFC 8032, verified strictly (below) | `ed25519-dalek` (`verify_strict`) |
| Argon2id v1.3 | RFC 9106 | `argon2` |
| OPAQUE-3DH, OPRF ristretto255-SHA512 | RFC 9807, RFC 9497, RFC 9496 | `opaque-ke` |
| Randomness | OS CSPRNG; `crypto.getRandomValues` in WASM | `getrandom` |

`chacha20poly1305` 0.11, `hpke` 0.14.1 (feature `mlkem`, which brings `x-wing` 0.1.1), `ed25519-dalek` 3.0, `argon2`
0.6 and `opaque-ke` 4.0.1 (Argon2id as its KSF) reproduce the PLB, PLW, PLH, key-derivation and OPAQUE vectors byte
for byte and verify the log signatures strictly; none of them needs C code.

**Strict Ed25519**: a signature is valid only if the public key and `R` are canonical encodings of points that are not
of small order, `S < L`, and `[S]B = R + [k]A` (cofactorless). ed25519-dalek's `verify_strict` enforces the
small-order and `S < L` rules; implementations add the canonical-encoding check where their library does not.

### Versions and errors

Every object starts with the same five bytes: magic `PL`, a type byte (`B`, `X`, `W`, `H`, `S`, and on devices `L`
and `J`), `format_version` and `suite`. The type and
version fix the layout, the suite fixes every algorithm, and nothing is negotiated. Readers accept every released
`(type, format_version, suite)`; writers emit only the current one; suites `0xF0–0xFE` are experimental and release
builds reject them. The server keeps the type, version and suite of each stored object in its own columns, so a per-user
crypto inventory can count objects per suite, and a reader is removed only when its count is zero (15 §1).

Readers run their checks in the order below and report the first failure with its code; the vectors pin the codes.

| Order | Check | Error |
|---|---|---|
| 1 | Length at least 8; magic `PL` | `bad_length`, `bad_magic` |
| 2 | Type is the one expected; `format_version` 1; suite 1 | `wrong_type`, `unsupported_version`, `unsupported_suite` |
| 3 | Fixed header length, then header fields (reserved bytes zero, known codes, ranges) | `bad_length`, `bad_header` |
| 4 | Total length consistent with the layout | `bad_length` |
| 5 | Key commitment, before any decryption | `commitment_mismatch` |
| 6 | AEAD tags | `auth_failed` |
| 7 | After authentication: the key id matches, the content kind or wrapped type is the one asked for, the padding | `bad_key_id`, `wrong_kind`, `bad_padding` |

Logs add `rollback`, `broken_chain`, `unauthorized`, `bad_signature`, `invalid_entry` and `unsigned_wrap`
([below](#pls-signed-statements-and-logs)); public-key wraps and journal entries add `wrong_recipient`; parameter
sets `kdf_params_rejected`; OPAQUE `envelope_recovery`.

## PLB: blob envelope

Originals, renditions, metadata, embeddings, video streams, sidecars, edit recipes and local caches (type `B`), and
link or export manifests (type `X`, same layout, content kind 10 only). Suite 1 is HKDF-SHA256 + ChaCha20-Poly1305
STREAM with a 32-byte key commitment.

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | `PL` |
| 2 | 1 | type `B` (0x42) or `X` (0x58) |
| 3 | 1 | `format_version` = 1 |
| 4 | 1 | `suite` = 1 |
| 5 | 1 | `content_kind`: 1 original, 2 preview, 3 thumbnail, 4 metadata, 5 embedding, 6 stream, 7 stream index, 8 sidecar, 9 edit recipe, 10 manifest, 11 local |
| 6 | 1 | `chunk_log2`: 16..22; writers emit 16 (64 KiB) |
| 7 | 1 | `flags`: bit 0 padded; the other bits MUST be 0 |
| 8 | 16 | `key_id` of the object key |
| 24 | 32 | `salt`, random per object |
| 56 | 32 | `commitment` |
| 88 | … | chunks |

* `PRK = HKDF-Extract(salt, object_key)`, `payload_key = HKDF-Expand(PRK, …/plb/payload, 32)`,
  `commitment = HKDF-Expand(PRK, …/plb/commit, 32)`.
* The plaintext is split into `n = max(1, ⌈len / C⌉)` chunks of `C = 2^chunk_log2` bytes; only the last may be
  shorter, and it is empty only when the whole plaintext is. Chunk `i` is
  `ChaCha20-Poly1305(payload_key, nonce = i as 11 bytes ‖ last, aad = header[0..88))`, where `last` is 1 for the
  final chunk and 0 otherwise. The index and the final flag are therefore authenticated: reordering, dropping,
  duplicating or appending chunks fails.
* Chunk `i` starts at `88 + i·(C + 16)`, so any byte range decrypts on its own (HTTP Range, video seeking). The last
  chunk is the remainder: a remainder of 1–15 bytes, or an empty last chunk after full chunks, is `bad_length`. A
  reader that relies on the object length (reporting a size, seeking from the end) MUST first verify the last chunk.
* Readers check `chunk_log2`, the flags and that type `X` goes with kind 10 and type `B` with any other kind
  (`bad_header`), recompute the commitment before decrypting (`commitment_mismatch`), and after decryption check the
  content kind is the one they asked for (`wrong_kind`). The kind is free for future values; it is bound by the AAD.
* **Padding** (flag bit 0): `plaintext = data ‖ 0x80 ‖ Z(k)` with total length `Padmé(len(data) + 1)`. For
  `L ≥ 1`: `E = ⌊log2 L⌋`, `S = ⌊log2 E⌋ + 1` (0 for `E = 0`), `m = 2^(E−S) − 1`, `Padmé(L) = (L + m) & ¬m`. Readers
  strip the zeros and the marker and reject anything else (`bad_padding`). Which objects are padded is a policy of the
  writer, not part of the format.

## PLW: symmetric key wrap

A 32-byte key wrapped under another key, 144 bytes. Suite 1 is HKDF-SHA256 + XChaCha20-Poly1305 with a key
commitment, so a wrap opens under exactly one key: a server cannot build one ciphertext that tests many password
guesses at once (partitioning oracles).

| Offset | Size | Field |
|---|---|---|
| 0 | 5 | `PL`, type `W` (0x57), `format_version` 1, `suite` 1 |
| 5 | 1 | `wrapped_type` ([registry](#wrapped-types-and-contexts)) |
| 6 | 2 | reserved, zero |
| 8 | 16 | `wrapping_key_id` |
| 24 | 16 | `wrapped_key_id` |
| 40 | 24 | `nonce`, random |
| 64 | 32 | `commitment` |
| 96 | 48 | sealed key and tag |

`PRK = HKDF-Extract(nonce, wrapping_key)`, `enc_key = HKDF-Expand(PRK, …/plw/key, 32)`,
`commitment = HKDF-Expand(PRK, …/plw/commit, 32)`, sealed =
`XChaCha20-Poly1305(enc_key, nonce, key, aad = bytes[0..96) ‖ context)`. The context is not stored: the reader
rebuilds it from where it found the wrap, so a wrap moved to another file, album, epoch or user fails. After opening,
`key_id(key)` MUST equal `wrapped_key_id` (`bad_key_id`) and the wrapped type MUST be the one asked for
(`wrong_kind`).

### Wrapped types and contexts

`context = user_id ‖ container_id ‖ subject_id ‖ number` (16 + 16 + 16 + 4 = 52 bytes); a field that does not apply
is zero.

| Code | Wrapped key | Wrapped under (PLW) or sent to (PLH) | user_id | container_id | subject_id | number |
|---|---|---|---|---|---|---|
| 1 | AMK | `KEK_pw`, `KEK_rec`, `KEK_pk`, `KEK_dev`, `KEK_kit`; PLH to a new device | user | zero; device id for PLH | zero | AMK generation |
| 2 | LibraryKey | AMK; PLH to a partner | holder | library | zero | epoch |
| 3 | AlbumKey | AMK; next epoch's AlbumKey (history back-link); PLH to a member | holder (zero for the back-link) | album | zero | epoch of the wrapped key |
| 4 | VaultKey | AMK | user | zero | zero | zero |
| 5 | FileKey | LibraryKey, AlbumKey or VaultKey; PLH to a collect link's drop key | zero | library, album, user or link | file | epoch of the container key |
| 6 | RenditionKey (an object key, e.g. preview or original) | LinkKey, GrantSessionKey | zero | link or grant | file | content kind |
| 7 | LinkSecret | AlbumKey or LibraryKey | zero | album or library | link | epoch |
| 8 | SigningKey (Ed25519 seed) | AMK | user | zero | zero | AMK generation |
| 9 | DecryptionKey (X-Wing seed): identity, device or drop key | AMK; AlbumKey for a drop key | user, or zero | zero, or album | zero, device or link | AMK generation or epoch |
| 10 | GrantSessionKey | PLH to a grant worker's ephemeral key | owner | grant | zero | zero |
| 11 | OutputKey | the grant's ReturnKey | zero | grant | file | content kind |
| 12 | DeviceDataKey | the key of a [lockbox](#lockbox) slot | user for the account slot, else zero | device | zero | zero |

## PLH: public-key wrap

A 32-byte key sent to a public key, 1224 bytes: HPKE (RFC 9180) base mode, single shot, with KEM X-Wing `0x647a`,
KDF HKDF-SHA256 `0x0001` and AEAD ChaCha20-Poly1305 `0x0003` — the combination of draft-ietf-hpke-pq-05 appendix
A.5. Recipients re-wrap the key as a PLW under their own AMK on accept and the server deletes the PLH, so almost no
public-key ciphertext stays stored (harvest now, decrypt later).

| Offset | Size | Field |
|---|---|---|
| 0 | 5 | `PL`, type `H` (0x48), `format_version` 1, `suite` 1 |
| 5 | 1 | `wrapped_type` |
| 6 | 2 | reserved, zero |
| 8 | 16 | `recipient_key_id = pk_id(recipient X-Wing public key)` |
| 24 | 16 | `sender_key_id = pk_id(sender's identity signing key)`; zero for anonymous senders (collect links) |
| 40 | 16 | `wrapped_key_id` |
| 56 | 1120 | `enc`, the X-Wing ciphertext |
| 1176 | 48 | sealed key and tag |

`info = …/plh ‖ context`, `aad = bytes[0..56)`. A reader whose public key does not match `recipient_key_id` stops
with `wrong_recipient`; then the key id and wrapped type are checked as for PLW. HPKE base mode does not authenticate
the sender, so **a PLH is accepted only if a verified log entry names its SHA-256 for that recipient**
(`unsigned_wrap`): `add_member` and `new_epoch` for members, `add_device` for a device, the grant statement for a
worker. Drop-key PLHs from anonymous guests are labelled as link uploads and adopted only after a member's review.

## PLS: signed statements and logs

Suite 1 is strict Ed25519; suite 2 is reserved for Ed25519 + ML-DSA-65.

| Offset | Size | Field |
|---|---|---|
| 0 | 5 | `PL`, type `S` (0x53), `format_version` 1, `suite` 1 |
| 5 | 1 | `log_type`: 1 identity, 2 album membership, 3 library membership, 4 statement (not chained) |
| 6 | 2 | `body_type` |
| 8 | 16 | `signer_key_id = pk_id(signing public key)` |
| 24 | 16 | `log_id`: the user, album or library; for statements, the album or library they concern |
| 40 | 8 | `seq` |
| 48 | 32 | `prev_hash`: `entry_hash` of entry `seq − 1`, zero for entry 0 |
| 80 | 8 | `time_ms`, the signer's clock (informational) |
| 88 | 4 | `body_len` |
| 92 | `body_len` | body, a fixed binary layout per body type |
| 92 + `body_len` | 64 | Ed25519 signature over `bytes[0..92 + body_len)` |

`entry_hash = SHA-256(entire entry)`. Statements have `seq` 0 and a zero `prev_hash`.

A reader keeps a **checkpoint**, the last verified `(seq, entry_hash)`, of every log it follows, and first refuses a
view that does not contain it (`rollback`): a server cannot roll a log back or show a fork. It then replays the log
from entry 0 and, for each entry, checks in this order: the layout (`bad_length`, `bad_header`); `log_type`,
`log_id`, `seq` and `prev_hash` (`broken_chain`); that the signer is allowed to sign in this log at all
(`unauthorized`); the signature (`bad_signature`); the body type is defined for the log and the body has its exact
length (`invalid_entry`); the signer's role allows the body (`unauthorized`); the state rules (`invalid_entry`). The
first entry's body is read first, because it names the key that signs it. A PLH is accepted only against the state
of the verified entry that names it, never against raw entry bytes.

### Identity log

`log_id` is the user. Every entry is signed by the user's current signing key; the log's signing keys, oldest first,
are what membership logs verify that user's signatures with.

| Type | Body | Size | Rule |
|---|---|---|---|
| 1 `genesis` | `sign_pk(32) ‖ enc_pk(1216)` | 1248 | entry 0 only; signed by `sign_pk` |
| 2 `rotate_encryption_key` | `enc_pk(1216)` | 1216 | |
| 3 `rotate_signing_key` | `suite(1) ‖ sign_pk` | 33 for suite 1 | later entries are signed by the new key |
| 4 `add_device` | `device_id(16) ‖ device_enc_pk(1216) ‖ plh_hash(32)` | 1264 | the device is new; `plh_hash` names the PLH carrying the AMK to it |
| 5 `remove_device` | `device_id(16)` | 16 | the device is listed; for a lost or stolen device the client also rotates the signing key, the encryption key and the AMK generation in the same session |
| 6 `rotate_amk` | `generation(4)` | 4 | exactly the previous generation + 1 |

The signing key is pinned on first use and compared out of band with the **safety number**: for each of two users,
`SHA-512(…/verification ‖ user_id ‖ sign_pk)[0..30)` read as six 5-byte integers, each mod 100000 as five digits; the
lower user id's 30 digits come first, shown as twelve space-separated groups. Clients warn loudly when a pinned key
changes and gossip signed log heads inside shared albums.

**Migration to ML-DSA.** A `rotate_signing_key` with suite 2 and an Ed25519 + ML-DSA-65 key switches the log to
hybrid signatures (both signatures, both MUST verify); readers then reject suite-1 entries in that log. Earlier
entries stay valid: they are pinned by the hash chain, and forging a signature later does not rewrite a chain that
readers already hold. Suite 2's layout and vectors are added before its first use.

### Membership logs and key epochs

Album (log type 2) and library (log type 3) membership logs have the same bodies and rules. `log_id` is the album or
library; roles are 1 viewer, 2 contributor, 3 admin. The log pins one signing key per member (`create`, `add_member`,
`update_member_key`); a pinned key MUST be one of the keys of that user's verified identity log. An entry not signed
with a current member's pinned key is `unauthorized`, and every entry after `create` MUST be signed by an admin,
except `update_member_key`, which a member may also sign for itself.

| Type | Body | Size | Rule |
|---|---|---|---|
| 1 `create` | `owner_id(16) ‖ owner_sign_key_id(16)` | 32 | entry 0 only; the owner is an admin at epoch 0 and cannot be removed or demoted |
| 2 `add_member` | `user_id(16) ‖ sign_key_id(16) ‖ role(1) ‖ plh_hash(32)` | 65 | not a member yet; pins `sign_key_id`; `plh_hash` names the PLH carrying the current epoch key |
| 3 `remove_member` | `user_id(16)` | 16 | a member, not the owner; a new epoch is now due |
| 4 `set_role` | `user_id(16) ‖ role(1)` | 17 | a member, not the owner |
| 5 `new_epoch` | `epoch(4) ‖ backlink_hash(32) ‖ count(2) ‖ count × (user_id(16) ‖ plh_hash(32))` | 38 + 48·count | epoch = current + 1; exactly one entry per member other than the signer; `backlink_hash` names the PLW of the previous epoch's key under the new one |
| 6 `add_link` | `link_id(16) ‖ flags(1)`: bit 0 password, bit 1 originals, bit 2 collect; others zero | 17 | a new link |
| 7 `remove_link` | `link_id(16)` | 16 | an existing link |
| 8 `set_drop_key` | `link_id(16) ‖ drop_pk(1216)` | 1232 | an existing link; authenticates its collect key |
| 9 `update_member_key` | `user_id(16) ‖ sign_key_id(16)` | 32 | a member (the owner too); the new key is later in the user's identity log than the pinned one, so a pin never moves back to a replaced key |

While a new epoch is due, only `remove_member` and `new_epoch` are valid. A removed member keeps what it already saw;
new uploads use the new epoch, and members walk the back-link chain for history. The **epoch code** members can
compare is `SHA-256(…/epoch-code ‖ log_id ‖ entry_hash of the head)[0..20)` as four groups of five digits.

### Upload statements

An uploader signs a statement (log type 4, body type 1, `log_id` the album or library):
`file_id(16) ‖ epoch(4) ‖ log_seq(8) ‖ log_head(32) ‖ objects_hash(32)`, 92 bytes, where
`objects_hash = SHA-256(SHA-256(PLB_1) ‖ … ‖ SHA-256(PLB_n))` over the file's envelopes in content-kind order. A
reader checks `log_head` is its own `entry_hash` at `log_seq` (`invalid_entry`), the signer was a member there
(`unauthorized`), the signature, that the epoch is the one at that position and no new epoch was due there
(`invalid_entry`), and that the signer may upload (contributor or admin) both there and at the reader's head
(`unauthorized`). A removed or demoted member therefore cannot backdate uploads; when an admin removes or demotes
one, the admin's client re-signs, under the new epoch, the uploads the album keeps. Unsigned or unauthorised items
are hidden and flagged.

## Key derivation

All derivations are `HKDF(ikm, info)`; outputs are 32 bytes.

| Key | ikm | info |
|---|---|---|
| `KEK_pw` | `Argon2id(NFC(password) as UTF-8, account parameters)` | `…/kek/password` |
| `KEK_rec` | the 32-byte recovery entropy (the phrase is its [BIP-39 encoding](#recovery-phrase)) | `…/kek/recovery` |
| `KEK_pk` | the WebAuthn PRF output | `…/kek/passkey` |
| `KEK_kit` | the secret a recovery kit's shares combine to | `…/kek/kit` |
| DedupKey, LocalIndexKey, SettingsKey | AMK | `…/amk/dedup`, `…/amk/local-index`, `…/amk/settings` |
| object key of a file for content kind `c` | FileKey | `…/file-key ‖ c` (one byte) |
| LinkKey | `LinkSecret ‖ password_hash` (empty without a password) | `…/link/key ‖ link_id` |
| LinkAuth | `LinkSecret` | `…/link/auth ‖ link_id` |
| ReturnKey of a grant | GrantSessionKey | `…/grant/return` |

* `KEK_dev` is a random key held in the platform keystore; AMK, LibraryKey, AlbumKey, VaultKey, FileKey, LinkSecret
  and GrantSessionKey are random.
* **Dedup token** = `HMAC-SHA256(DedupKey, SHA-256(original bytes))`: equal only within one user's library.
* **Links and static exports** use the same keys. The server stores only `SHA-256(LinkAuth)` as the verifier. With a
  password, `password_hash = Argon2id(NFC(password), m = 64 MiB, t = 3, p = 1, salt = link_id)`. The manifest is a
  PLX under LinkKey; per-file object keys are RenditionKey PLWs under LinkKey. The URL fragment is
  `v1.<link_id>.<LinkSecret>[.p][.<SHA-256(manifest)[0..8)>]`, each value base64url without padding; `p` means a
  password is required.

### Argon2id parameters

A parameter set is stored per user and travels as 26 bytes: `alg(1) = 1 (Argon2id v1.3) ‖ m_kib(4) ‖ t(4) ‖
p(1) ‖ salt(16)`, output 32 bytes. The **account policy** accepts only `128 MiB ≤ m ≤ 2 GiB`, `3 ≤ t ≤ 64`, `p = 1`
(WASM has no threads without cross-origin isolation) and a 16-byte salt; clients check it before using parameters a
server sent (`kdf_params_rejected`), which also bounds the work a malicious server can demand. A client generates a
fresh random salt whenever it derives a new KEK (enrolment, password change, parameter upgrade), never reusing one it
received, so a server cannot make accounts share a salt and amortise guesses across them. Enrolment calibrates to
about one second on the enrolling device, starting from `m = 256 MiB, t = 3` and falling back to `m = 128 MiB, t = 6`
on constrained phones, and re-derives with stronger parameters at the next password entry on a stronger device.
Contexts that cannot spend the memory (share extensions) unlock with the device key instead.

### Recovery phrase

The recovery kit carries the 32 random bytes of recovery entropy, which give `KEK_rec`, as their
[BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki) English encoding: 24 words, each 11 bits of
`entropy ‖ SHA-256(entropy)[0]`, most significant first, indexing the BIP-39 English list (2048 words,
`kernel/src/bip39-english.txt`, SHA-256 `2f5eed53…24dbda`; MIT). Writers join the words with one space. Readers split
the phrase at runs of ASCII whitespace (U+0009, U+000A, U+000C, U+000D, U+0020), lowercase ASCII letters only, and
check the word count, 24 (`bad_length`), each word in the list (`unknown_word`, with its 1-based position as `word`),
then the checksum byte (`bad_checksum`). BIP-39's seed derivation (PBKDF2) is not used: the entropy is the secret.

## OPAQUE

Password login is OPAQUE-3DH (RFC 9807) with OPRF ristretto255-SHA512, HKDF-SHA512, HMAC-SHA512, SHA-512 and group
ristretto255; KSF `Argon2id(S = Z(16), p = 1, T = 64)` with `m` and `t` of the user's account parameters; context
`photolib/v1/opaque`; default identities (the public keys). The KSF matches the KEK's cost, so the login record is
not a cheaper target than the wrapped AMK. `KEK_pw` is derived independently of `export_key`: losing the server's OPRF
seed breaks login, never data access. The OPRF seed and the server key live outside the database.

## Local data protection

Every install encrypts what it stores under its DeviceDataKey (DDK), 32 random bytes that never leave the device
(21 §3–§4). The lockbox wraps the DDK under each factor that unlocks the device; work done while the app
is locked is written as sealed journal entries that only the DDK can open.

| Key | ikm | info |
|---|---|---|
| page key of database file `f` | DDK | `…/local/db ‖ f` |
| CacheKey | DDK | `…/local/cache` |
| object key of cached object `o` | CacheKey | `…/local/object ‖ o` |
| object key of class B object `o` | the key of `KS_bg` | `…/local/object ‖ o` |
| InboxKey | DDK | `…/local/inbox` |
| local SettingsKey | DDK | `…/local/settings` |
| `KEK_pass` | `Argon2id(NFC(passcode) as UTF-8, device parameters) ‖ HW` | `…/kek/passcode` |

* `f` and `o` are 16-byte ids. A page key is the one key that leaves the kernel (`DatabaseKey`,
  [ADR-0057](../adr/0057-encrypted-local-store.md)): SQLite3MultipleCiphers holds it. `HW` is the 32-byte output of
  the device's hardware binding over the parameter set's salt (StrongBox or TEE HMAC, Secure Enclave ECDH, a TPM
  key), or empty on devices without one.
* **Device parameters** are an Argon2id parameter set held to the device policy: `64 MiB ≤ m ≤ 2 GiB`, `3 ≤ t ≤ 64`,
  `p = 1` and a 16-byte salt (`kdf_params_rejected`). The floor is below the account's because hardware binding, not
  the KDF, is the main defence. **Calibration**: at passcode setup the client times one derivation `T` at
  `m = 64 MiB, t = 3` and stores `m = 64 MiB, t = min(64, max(3, ⌈3 · 250 ms / T⌉))`, so an unlock costs at least
  250 ms.

### Lockbox

The DDK wrapped under each factor that unlocks one device, `40 + 188·n` bytes:

| Offset | Size | Field |
|---|---|---|
| 0 | 5 | `PL`, type `L` (0x4C), `format_version` 1, `suite` 1 |
| 5 | 1 | `count` n of slots, 1..8 |
| 6 | 2 | reserved, zero |
| 8 | 16 | `device_id` |
| 24 | 16 | `key_id` of the DDK |
| 40 | 188·n | slots |

| Slot offset | Size | Field |
|---|---|---|
| 0 | 1 | `factor`: 1 keystore key `KS_dev` (level L1), 2 passcode (`KEK_pass`), 3 biometric keystore key `KS_bio`, 4 local recovery code (`KEK_rec`), 5 account (its AMK) |
| 1 | 1 | `binding`: 1 when `KEK_pass` includes `HW`, else 0 |
| 2 | 16 | `user_id` of the account |
| 18 | 26 | the device parameters of `KEK_pass` |
| 44 | 144 | PLW of the DDK under the factor's key: wrapped type 12, context `user_id ‖ device_id ‖ Z(16) ‖ 0` |

* `binding`, `user_id` and the parameters apply to the passcode, the account and the passcode respectively, and are
  zero in every other slot. A keystore factor's key is the 32 bytes its keystore key releases or computes; `KEK_rec` is
  `HKDF(recovery code entropy, …/kek/recovery)`.
* Readers check `count` and the reserved bytes (`bad_header`), the length (`bad_length`), then every slot: a known
  factor, zero fields that do not apply, at most one slot per factor (per account for factor 5), and a PLW header of
  type `W`, version 1, suite 1, wrapped type 12, zero reserved bytes and `wrapped_key_id` equal to `key_id`
  (`bad_header`); then the passcode's parameters against the device policy (`kdf_params_rejected`). Opening a slot
  opens its PLW: a wrong passcode or key fails the commitment (`commitment_mismatch`), a lockbox moved to another
  device or a slot moved to another account fails authentication (`auth_failed`).
* Writers replace the lockbox as a whole, keeping or adding slots: changing the passcode re-wraps the DDK and touches
  no data. Deleting the lockbox makes the store unreadable (crypto-erase).

### Keystore file

Where no platform keystore runs (a Linux desktop without a Secret Service, ADR-0154), the keystore keys (`KS_dev`,
`KS_bg`, 32 random bytes each) are kept in the store's `keystore` file: the 26 bytes of the device parameters, then a
PLB of content kind 11 under `KEK_pass` of the user's passphrase without `HW`, whose plaintext is the JSON object
`{name: base64(key)}`. It composes vectored parts only (PLB, `KEK_pass`) and has no vectors of its own; a wrong
passphrase fails the commitment (`commitment_mismatch`).

### Sealed journal entries

What the app records while locked (backup progress, server acknowledgements, items shared in) without any secret, 72
bytes plus the plaintext:

| Offset | Size | Field |
|---|---|---|
| 0 | 5 | `PL`, type `J` (0x4A), `format_version` 1, `suite` 1 |
| 5 | 3 | reserved, zero |
| 8 | 16 | `recipient_key_id = pk_id(inbox public key)` |
| 24 | 32 | `enc`, the ephemeral X25519 public key |
| 56 | … | sealed plaintext and tag |

HPKE (RFC 9180) base mode, single shot, with KEM DHKEM(X25519, HKDF-SHA256) `0x0020`, KDF HKDF-SHA256 `0x0001` and
AEAD ChaCha20-Poly1305 `0x0003`; `info = …/journal`, `aad = bytes0..56)`. The inbox key pair is
`DeriveKeyPair(InboxKey)` (RFC 9180 §7.1.3): its public key is kept where locked work can read it, its private key
exists only while the app is unlocked. Readers check the length (at least 72) and reserved bytes, then
`recipient_key_id` (`wrong_recipient`), then decrypt (`auth_failed`, also for an `enc` that gives a zero shared
secret). Each entry stands alone: the app merges them idempotently, so order and duplicates do not matter.

## Threat-model mapping

Every key wrap, chunk, membership list, public key and local file is authenticated; the vectors in the last column
show each attack being rejected. Threat numbers are the rows of [06 §2 (3 is the actively malicious
server) and of 21 §11 (19–23, local data).
`tools/tests/test_crypto.sh` fails if a wrapped type, object type, log or public key is missing here or a cited vector
does not exist.

| Item | Kind | Authenticated by | Threats | Rejection vectors |
|---|---|---|---|---|
| `AMK` | key wrap | PLW (commitment, AEAD over header and context with user and generation); PLH to a device named by `add_device` | 3, 4, 5 | `plw-wrong-key`, `plw-tag-tampered`, `wrap-not-in-log` |
| `LibraryKey` | key wrap | PLW under the AMK; PLH to a partner named by the library log | 3, 6 | `plw-wrong-key`, `wrap-not-in-log` |
| `AlbumKey` | key wrap | PLW under the AMK; back-link PLW named by `new_epoch`; PLH named by `add_member` or `new_epoch` | 3, 6, 7 | `plw-wrong-epoch`, `plh-wrong-recipient`, `plh-wrong-context`, `wrap-not-in-log` |
| `VaultKey` | key wrap | PLW under the AMK only; never shared | 3 | `plw-wrong-key` |
| `FileKey` | key wrap | PLW under the container key with file, container and epoch in the context; drop-key PLH labelled as an anonymous upload | 3, 6 | `plw-moved-to-another-file`, `plw-wrong-epoch`, `plw-type-swapped` |
| `RenditionKey` | key wrap | PLW under a LinkKey or GrantSessionKey with link or grant, file and content kind in the context | 10, 11, 12 | `plw-moved-to-another-file`, `plw-wrong-type` |
| `LinkSecret` | key wrap | PLW under the album or library key with the link id in the context | 3 | `plw-wrong-type`, `plw-bad-key-id` |
| `SigningKey` | key wrap | PLW under the AMK | 3 | `plw-wrong-key` |
| `DecryptionKey` | key wrap | PLW under the AMK or AlbumKey | 3, 13 | `plw-wrong-key`, `plw-unknown-type` |
| `GrantSessionKey` | key wrap | PLH to a worker key from a signed grant offer, named by the owner's grant statement | 12 | `plh-enc-tampered`, `plh-header-tampered` |
| `OutputKey` | key wrap | PLW under the grant's ReturnKey | 12 | `plw-tag-tampered` |
| `DeviceDataKey` | key wrap | PLW in a lockbox slot, with the device and account in the context | 3, 9, 19, 21 | `lockbox-wrong-passcode`, `lockbox-other-device` |
| PLB chunk | chunk | AEAD per chunk; nonce carries the index and the final flag; header is the AAD; commitment | 2, 3, 6, 11 | `plb-truncated`, `plb-reordered`, `plb-extended`, `plb-ciphertext-tampered`, `plb-header-tampered`, `plb-wrong-key`, `plb-wrong-kind` |
| PLX chunk | chunk | as PLB; type `X` only with kind manifest | 10, 11 | `plx-as-blob`, `plb-commitment-tampered` |
| `identity` log | log | hash chain, strict Ed25519 by the current signing key, checkpoints | 3 | `identity-bad-prev-hash`, `identity-seq-gap`, `identity-bad-signature`, `identity-wrong-signer`, `identity-rollback` |
| `album` log | log | hash chain, admin signatures with pinned keys, epoch rules, checkpoints | 3, 6, 7 | `membership-stranger`, `membership-add-by-contributor`, `membership-other-log`, `membership-add-before-rotation`, `membership-epoch-skip`, `membership-epoch-misses-member`, `membership-epoch-includes-removed`, `membership-remove-owner`, `membership-rollback`, `membership-fork` |
| `library` log | log | as the album log | 3, 6, 7 | `membership-stranger`, `membership-add-by-contributor` |
| `statement` | log | signature by a member who may upload at the named log head and at the reader's head, outside a pending rotation | 3, 6, 7 | `upload-by-viewer`, `upload-by-removed-member`, `upload-backdated-by-removed-member`, `upload-during-pending-rotation`, `upload-wrong-epoch`, `upload-unknown-head` |
| identity signing key | public key | self-signed genesis, pinned on first use, safety number, rotations signed by the old key, strict verification | 3 | `identity-weak-key`, `identity-non-canonical-s`, `identity-wrong-signer`, `identity-old-key-after-rotation`, `identity-rotate-to-undefined-suite` |
| identity encryption key | public key | `genesis` or `rotate_encryption_key` signed by the signing key; `recipient_key_id` in every PLH | 3, 13 | `identity-bad-signature`, `plh-wrong-recipient` |
| device encryption key | public key | `add_device` signed by the identity key | 3 | `identity-wrong-signer` |
| member signing key | public key | pinned by `add_member` or `update_member_key` to a key of the member's identity log, never back to a replaced one | 3 | `membership-substituted-key`, `membership-old-owner-key`, `membership-key-rollback` |
| drop key | public key | `set_drop_key` signed by an admin | 3 | `membership-stranger` |
| grant worker key | public key | grant offer signed by the instance key the client pinned | 12 | `identity-bad-signature` |
| instance signing key | public key | pinned on first use and shown to the administrator; statements verified strictly | 3 | `identity-non-canonical-s` |
| OPAQUE server key | public key | bound into the OPAQUE envelope at registration | 1, 3 | `opaque-substituted-server-key` |
| inbox key | public key | derived from the DDK on the device; its key id in every journal entry | 19 | `journal-wrong-recipient` |
| lockbox | local | every slot a PLW; slot fields and the passcode's parameters checked before use | 19, 20, 21 | `lockbox-wrong-passcode`, `lockbox-other-device`, `lockbox-other-account`, `lockbox-weak-params`, `lockbox-key-id-mismatch` |
| journal entry | local | HPKE to the inbox key; the header is the AAD | 19 | `journal-wrong-recipient`, `journal-ciphertext-tampered`, `journal-enc-tampered`, `journal-zero-shared-secret` |
| recovery phrase | encoding | not authenticated: its checksum byte catches a mistyped or missing word before the KEK it gives fails the AMK's PLW | 17 | `recovery-bad-checksum`, `recovery-unknown-word`, `recovery-non-ascii-letter`, `recovery-23-words` |

Not authenticated, by design: who uploaded through a collect link (anonymous; labelled), and sizes, counts and timing
(threat 2; Padmé reduces size leakage).

## Known-answer vectors

`kernel/testvectors/crypto/` holds one JSON file per construction: `plb`, `plw`, `plh`, `pls`, `kdf`, `opaque`,
`lockbox`, `journal` and `recovery`.
Each lists valid cases with every input and the expected bytes, and invalid cases with the error a reader MUST report;
an invalid case gives its input in full or as its `base` valid case with fields overridden and `mutations` applied in
order: `set [offset, hex]` overwrites, `flip offset` XORs 1, `truncate n` keeps n bytes, `swap [a, b, n]` exchanges two
ranges and `repeat [offset, n]` appends a copy of a range. Invalid log entries follow the first `prefix` valid entries
of their log. Large plaintexts are `plaintext_length` bytes with byte `i = i mod 251`, pinned by `envelope_sha256`.

They are generated by `tools/cryptoref/`, a stdlib-only Python reference that first checks every primitive against
its published vectors (`standards.json`: RFC 8439, the XChaCha draft, RFC 5869, RFC 7748, RFC 8032, RFC 9106, the
X-Wing and HPKE-PQ drafts, RFC 9180, RFC 9496, RFC 9497, RFC 9807, BIP-39). `python3 tools/cryptoref/vectors.py` rewrites
them and `--check`, run by the gate, fails unless the committed files are exactly what it generates and every case
passes.
Argon2id at its real sizes takes minutes in Python, so those two outputs are pinned in `vectors.py` and recomputed
only with `--slow`. The kernel runs every file natively and in WASM (M0-40, M6-01, `kernel/tests/vectors.rs`).

## Owned elsewhere

Within the registries above, later tasks add, each with its own vectors: recovery-kit shares (M6-03); grant offers,
grant and audit statements (M6-10); suite 2 of PLS before the ML-DSA migration.
