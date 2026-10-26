#!/usr/bin/env bash
# tools/release.sh readies a directory of release files: an SBOM of the lock files, SHA256SUMS over every file and a
# cosign signature of SHA256SUMS. cosign is a stub here; the release job signs keylessly with its GitHub identity, and
# outside CI only a hardware-held key signs, never a person's identity (ADR-0058, photolib-design#367).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

# A fixed date keeps the SBOM, and so SHA256SUMS, the same from one run to the next.
export SOURCE_DATE_EPOCH=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/cosign" <<EOF
#!/bin/bash
echo "cosign \$*" >>"$TMP/calls"
[[ -n \${COSIGN_FAILS:-} ]] && exit 1
while [[ \$# -gt 0 ]]; do [[ \$1 == --bundle ]] && echo signed >"\$2"; shift; done
EOF
chmod +x "$TMP/bin/cosign"

# release <command prefix...>: a fresh dist/ with two libraries, readied by tools/release.sh
release() {
  rm -rf "$TMP/dist" "$TMP/calls"
  mkdir -p "$TMP/dist"
  echo one >"$TMP/dist/linux-x64-libphotolib_kernel_ffi.so"
  echo two >"$TMP/dist/prebuilt.json"
  capture "$@" bash tools/release.sh "$TMP/dist" photolib-kernel 0.1.0 kernel/Cargo.lock
}

# The release job's GitHub OIDC token, which cosign signs keylessly with.
CI=(ACTIONS_ID_TOKEN_REQUEST_URL=https://token.actions.invalid ACTIONS_ID_TOKEN_REQUEST_TOKEN=t)
release env PATH="$TMP/bin:$PATH" "${CI[@]}"
expect_result "a release is readied" 0
python3 - "$TMP/dist/photolib-kernel-0.1.0.cdx.json" <<'PY' && ok "it gets an SBOM of its lock file" || fail "no SBOM"
import json, sys
bom = json.load(open(sys.argv[1]))
assert bom["bomFormat"] == "CycloneDX" and bom["metadata"]["component"]["version"] == "0.1.0"
assert any(c["name"] == "chacha20poly1305" for c in bom["components"])
PY
[[ $(cut -d' ' -f3 "$TMP/dist/SHA256SUMS" 2>/dev/null | tr '\n' ' ') == \
  "linux-x64-libphotolib_kernel_ffi.so photolib-kernel-0.1.0.cdx.json prebuilt.json " ]] &&
  (cd "$TMP/dist" && sha256sum --quiet -c SHA256SUMS) &&
  ok "SHA256SUMS covers every file, the SBOM included" || fail "SHA256SUMS: $(cat "$TMP/dist/SHA256SUMS" 2>&1)"
[[ $(cat "$TMP/calls" 2>/dev/null) == "cosign sign-blob --yes --bundle $TMP/dist/SHA256SUMS.sigstore.json $TMP/dist/SHA256SUMS" &&
  -f $TMP/dist/SHA256SUMS.sigstore.json ]] && ok "cosign signs SHA256SUMS into a Sigstore bundle" ||
  fail "cosign calls: $(cat "$TMP/calls" 2>&1)"

sums=$(cat "$TMP/dist/SHA256SUMS")
capture env PATH="$TMP/bin:$PATH" "${CI[@]}" bash tools/release.sh "$TMP/dist" photolib-kernel 0.1.0 kernel/Cargo.lock
[[ $(cat "$TMP/dist/SHA256SUMS") == "$sums" ]] && ok "a second run signs the same checksums, not its own output" ||
  fail "a second run wrote: $(cat "$TMP/dist/SHA256SUMS")"

release env PATH="$TMP/bin:$PATH" "${CI[@]}" COSIGN_FAILS=1
expect_result "a signature that fails fails the release" failure

release env PATH="$(dirname "$(command -v python3)"):/usr/bin:/bin"
expect_result "without cosign the release fails before it writes anything" failure "'cosign' is required"
[[ ! -e $TMP/dist/SHA256SUMS ]] && ok "nothing was written" || fail "files were written without cosign"

# Outside CI cosign would sign keylessly with whoever logs in, writing their e-mail into Sigstore's public log for good.
release env -u ACTIONS_ID_TOKEN_REQUEST_URL -u COSIGN_KEY PATH="$TMP/bin:$PATH"
expect_result "outside a release job no personal identity signs" failure "never with a personal identity"
[[ ! -e $TMP/dist/SHA256SUMS && ! -e $TMP/calls ]] && ok "nothing was written or signed" ||
  fail "a release was signed without the release job's identity: $(cat "$TMP/calls" 2>&1)"
release env -u ACTIONS_ID_TOKEN_REQUEST_URL PATH="$TMP/bin:$PATH" COSIGN_KEY=cosign.key
expect_result "a key file on disk is no hardware-held key" failure "pkcs11:"
release env -u ACTIONS_ID_TOKEN_REQUEST_URL PATH="$TMP/bin:$PATH" COSIGN_KEY=awskms:///alias/photolib-release
expect_result "a cloud KMS key is no hardware-held key" failure "pkcs11:"
KEY='pkcs11:token=photolib;slot-id=0;object=release?module-path=/usr/lib/libykcs11.so'
release env -u ACTIONS_ID_TOKEN_REQUEST_URL PATH="$TMP/bin:$PATH" COSIGN_KEY="$KEY"
expect_result "outside CI a hardware-held key signs" 0
[[ $(cat "$TMP/calls" 2>/dev/null) == "cosign sign-blob --yes --key $KEY --bundle $TMP/dist/SHA256SUMS.sigstore.json $TMP/dist/SHA256SUMS" ]] &&
  ok "cosign signs with the PKCS#11 key" || fail "cosign calls: $(cat "$TMP/calls" 2>&1)"

assert_prose docs/dev/releasing.md 'tools/release\.sh.*supply-chain\.md#verifying-a-release' \
  "the release checklist signs the release files and verifies the signature"
assert_patterns assert_prose docs/dev/supply-chain.md \
  'never with a personal identity' "says no person's identity signs" \
  'hardware-held key' "names the key a release outside CI is signed with" \
  'App stores sign their own packages' "leaves store packages to the stores" \
  'server images, kernel libraries, the CLI, Linux packages and SBOMs' "lists what cosign signs" \
  'cosign verify-blob --key' "says how to verify a key-signed release"

# --- ADR-0058 as the owner answered it (photolib-design#367), kept again in photolib-design#588
ADR=docs/adr/0058-supply-chain-baseline.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner answered [^*]*photolib-design#367' \
  "ADR-0058 is Accepted with the owner's answers"
assert_patterns assert_prose "$ADR" \
  'Never with a personal identity' "no personal identity signs" \
  'unshare -rn` fails' "records why no network namespace blocks egress" \
  '.outbound: none.' "has the master switch"
assert_prose "$ADR" 'photolib-design#588[^*]*only a .pkcs11:. URI signs outside CI[^*]*.outbound: none. or unset' \
  "records that the owner kept the pkcs11: key and the master switch's values"
assert_matches docs/adr/README.md '\(0058-supply-chain-baseline\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0058 as Accepted"

finish
