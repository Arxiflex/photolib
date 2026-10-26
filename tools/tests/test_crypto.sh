#!/usr/bin/env bash
# Crypto suite v1 (M0-10): the stdlib reference implementation matches the published vectors of every primitive, the
# committed known-answer vectors are exactly what it generates, every invalid vector is rejected with its stated
# error, and the specification's threat-model mapping covers every key wrap, chunk, log and public key. ADR-0025 is
# Accepted as the owner confirmed it (photolib-design#289), and the kernel's key exports as the owner confirmed them
# (photolib-design#341).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

VECTORS=(python3 tools/cryptoref/vectors.py --check)
check "the reference matches the published vectors and regenerates kernel/testvectors/crypto exactly" "${VECTORS[@]}"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# rejects <description> <expected output> <vectors.py arguments...>: the check fails and says why
rejects() {
  local description=$1 want=$2 out
  shift 2
  out=$("${VECTORS[@]}" "$@" 2>&1)
  if [[ $? -ne 0 && $out == *"$want"* ]]; then ok "the check notices $description"; else
    fail "the check does not notice $description: $out"
  fi
}

cp -R kernel/testvectors/crypto "$SANDBOX/vectors"
sed -i 's/"error": "commitment_mismatch"/"error": "auth_failed"/' "$SANDBOX/vectors/plw.json"
rejects "a changed expected error" "plw-wrong-key: rejected with commitment_mismatch, want auth_failed" \
  --dir "$SANDBOX/vectors"

sed '/^| `VaultKey` | key wrap |/d' docs/dev/crypto-v1.md >"$SANDBOX/no-row.md"
rejects "a wrapped type missing from the threat-model mapping" "no key wrap row for VaultKey" \
  --spec "$SANDBOX/no-row.md"

sed 's/`plh-wrong-recipient`/`plh-made-up`/' docs/dev/crypto-v1.md >"$SANDBOX/made-up.md"
rejects "a mapping row citing a vector that does not exist" "cites unknown vector plh-made-up" \
  --spec "$SANDBOX/made-up.md"

# --- ADR-0025: Accepted, with its seven decisions kept
ADR=docs/adr/0025-crypto-suite-v1-specification.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-15 [^*]*confirmed [^*]*photolib-design#289' \
  "is Accepted, recording the owner's confirmation (#289)"
assert_prose docs/dev/crypto-v1.md '\*\*Status\*\*: Accepted — 2026-10-15 \(\[ADR-0025\]' "the spec is Accepted too"
assert_prose "$ADR" 'xwing-kem-11.*`x-wing` with the `hpke` crate; `libcrux` is the fallback' "keeps X-Wing draft 11"
assert_prose "$ADR" 'Signed bodies are fixed binary layouts' "keeps fixed binary signed bodies"
assert_prose "$ADR" \
  '128 MiB to 2 GiB, 3 to 64 passes and one lane;.* 256 MiB × 3 .* 128 MiB × 6.* 64 MiB × 3 with the link id as salt' \
  "keeps the Argon2id policy and presets"
assert_prose "$ADR" "uses the account's Argon2id parameters as its KSF.*KEK stays independent of .export_key" \
  "keeps OPAQUE's Argon2id KSF"
assert_prose "$ADR" 'An upload counts only while its uploader may still upload.*re-signs what the album keeps' \
  "keeps uploads valid only while the uploader may upload"
assert_prose "$ADR" 'Passwords are NFC-normalised UTF-8' "keeps NFC passwords"
assert_prose "$ADR" 'Blob chunks use ChaCha20-Poly1305 under a per-object HKDF subkey.*XChaCha20 seals the wraps' \
  "keeps ChaCha20-Poly1305 chunks and XChaCha20 wraps"
if stale=$(grep -rEn 'until M0-10' docs kernel/README.md kernel/src); then fail "still provisional: $stale"; else
  ok "nothing waits for M0-10 any more"
fi

# --- The kernel's crypto API (M6-01): the two decisions the owner confirmed in photolib-design#341
assert_prose kernel/README.md \
  "but OPAQUE's session and export keys; nothing exports LinkSecret or LinkAuth until M6-09 \(both confirmed in \
photolib-design#341\)" "records both confirmed decisions"
assert_prose proto/photolib/kernel/v1/opaque.proto \
  'message OpaqueClientResponse \{ bytes message = 1; bytes session_key = 2; bytes export_key = 3; \}' \
  "OpaqueLogin returns the session and export keys"
assert_prose proto/photolib/kernel/v1/opaque.proto \
  'message OpaqueServerResponse \{ bytes message = 1; bytes session_key = 2; \}' \
  "OpaqueServerLogin returns the session key"
assert_prose proto/photolib/kernel/v1/keys.proto \
  'message LinkKeysResponse \{ uint32 key = 1; bytes key_id = 2; bytes verifier = 3; \}' \
  "LinkKeys returns a handle and the verifier, never LinkSecret or LinkAuth"

finish
