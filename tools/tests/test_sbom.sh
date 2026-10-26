#!/usr/bin/env bash
# tools/sbom.py writes a CycloneDX SBOM of the third-party packages a lock file pins, each with its package URL and
# pinned hash; releases attach it (tools/release.sh).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/rust" "$TMP/dart" "$TMP/node"
cat >"$TMP/rust/Cargo.lock" <<'EOF'
version = 4

[[package]]
name = "aead"
version = "0.6.1"
source = "registry+https://github.com/rust-lang/crates.io-index"
checksum = "1973cfbc1a2daf9cf550e74e1f088c28e7f7d8c1e1418fb6c9dc5184b7e84c99"

[[package]]
name = "photolib-kernel"
version = "0.1.0"
EOF
cat >"$TMP/dart/pubspec.lock" <<'EOF'
packages:
  args:
    dependency: transitive
    description:
      name: args
      sha256: d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04
      url: "https://pub.dev"
    source: hosted
    version: "2.7.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  photolib_api:
    dependency: "direct main"
    description:
      path: "packages/photolib_api"
      relative: true
    source: path
    version: "0.1.0"
sdks:
  dart: ">=3.13.5 <4.0.0"
EOF
cat >"$TMP/node/package-lock.json" <<'EOF'
{"lockfileVersion": 3, "packages": {
  "": {"name": "photolib-viewer"},
  "node_modules/@bufbuild/protobuf": {"version": "2.16.0", "integrity": "sha512-FWa0sPlqYGJgpTs6OxBRcL/AW4JT0OIO+W1ajerluoTVh8CV0B7XM1qsNCRgnkSCkRCgOICKHRQlY17jrsm0+Q=="},
  "node_modules/a/node_modules/b": {"version": "1.0.0", "integrity": "sha1-qUqcRFCqt2oPXPWYTbP4JJPXMzc="},
  "packages/local": {"name": "local", "link": true}
}}
EOF

# components <lock file>: "purl algorithm:hash" per component of its SBOM
components() {
  SOURCE_DATE_EPOCH=0 python3 tools/sbom.py photolib 1.2.3 "$1" | python3 -c '
import json, sys
for c in json.load(sys.stdin)["components"]:
    print(c["purl"], " ".join(f"{h['"'alg'"']}:{h['"'content'"']}" for h in c.get("hashes", [])))'
}

[[ $(components "$TMP/rust/Cargo.lock") == "pkg:cargo/aead@0.6.1 SHA-256:1973cfbc1a2daf9cf550e74e1f088c28e7f7d8c1e1418fb6c9dc5184b7e84c99" ]] &&
  ok "Cargo.lock: registry crates with their checksum; workspace crates are ours" ||
  fail "Cargo.lock components: $(components "$TMP/rust/Cargo.lock")"
[[ $(components "$TMP/dart/pubspec.lock") == "pkg:pub/args@2.7.0 SHA-256:d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04" ]] &&
  ok "pubspec.lock: hosted packages with their archive hash; SDK and path packages are not third-party" ||
  fail "pubspec.lock components: $(components "$TMP/dart/pubspec.lock")"
[[ $(components "$TMP/node/package-lock.json") == "pkg:npm/%40bufbuild/protobuf@2.16.0 SHA-512:1566b4b0f96a606260a53b3a3b105170bfc05b8253d0e20ef96d5a8deae5ba84d587c095d01ed7335aac3424609e44829110a038808a1d1425635ee3aec9b4f9
pkg:npm/b@1.0.0 SHA-1:a94a9c4450aab76a0f5cf5984db3f82493d73337" ]] &&
  ok "package-lock.json: scoped and nested packages with their integrity hash; links are ours" ||
  fail "package-lock.json components: $(components "$TMP/node/package-lock.json")"

capture env SOURCE_DATE_EPOCH=0 python3 tools/sbom.py photolib-kernel 0.1.0 "$TMP/rust/Cargo.lock" "$TMP/node/package-lock.json"
first=$OUT
expect_result "several lock files make one SBOM" 0
python3 - "$first" <<'PY' && ok "it is a CycloneDX 1.6 document about the release, dated by SOURCE_DATE_EPOCH" || fail "bad document: $first"
import json, sys
bom = json.loads(sys.argv[1])
assert bom["bomFormat"] == "CycloneDX" and bom["specVersion"] == "1.6" and bom["version"] == 1, bom
assert bom["serialNumber"].startswith("urn:uuid:"), bom["serialNumber"]
meta = bom["metadata"]
assert meta["timestamp"] == "1970-01-01T00:00:00Z", meta
assert meta["component"] == {"type": "application", "bom-ref": "pkg:generic/photolib-kernel@0.1.0",
                             "name": "photolib-kernel", "version": "0.1.0",
                             "licenses": [{"license": {"id": "AGPL-3.0-only"}}]}, meta["component"]
refs = [c["bom-ref"] for c in bom["components"]]
assert len(refs) == 3 and refs == sorted(refs) and all(c["type"] == "library" for c in bom["components"]), refs
PY
capture env SOURCE_DATE_EPOCH=0 python3 tools/sbom.py photolib-kernel 0.1.0 "$TMP/rust/Cargo.lock" "$TMP/node/package-lock.json"
[[ $OUT == "$first" ]] && ok "the SBOM is reproducible" || fail "two runs differ"

capture python3 tools/sbom.py photolib 1.2.3 README.md
expect_result "a file that is not a lock file is refused" 2 "README.md"

# A package from anything but the default registry would get that registry's package URL, or none: refused.
mkdir -p "$TMP/other"
printf '[[package]]\nname = "forked"\nversion = "1.0.0"\nsource = "git+https://example.org/forked#abc"\n' \
  >"$TMP/other/Cargo.lock"
printf 'packages:\n  mirrored:\n    description:\n      url: "https://pub.example.org"\n    source: hosted\n' \
  >"$TMP/other/pubspec.lock"
echo '{"packages": {"node_modules/c": {"version": "1", "resolved": "git+ssh://git@example.org/c.git"}}}' \
  >"$TMP/other/package-lock.json"
for refused in "Cargo.lock forked" "pubspec.lock mirrored" "package-lock.json node_modules/c"; do
  capture python3 tools/sbom.py photolib 1.2.3 "$TMP/other/${refused% *}"
  expect_result "${refused% *}: a package from another source is refused" 2 "${refused#* } comes from"
done

# Every lock file in the repository: one component per third-party package it pins.
while IFS= read -r lock; do
  case $lock in
    *Cargo.lock) want=$(grep -c '^source = ' "$lock") ;;
    *pubspec.lock) want=$(grep -c '^    source: hosted' "$lock") ;;
    *) want=$(grep -c '"node_modules/' "$lock") ;;
  esac
  got=$(components "$lock" | grep -c .)
  [[ $got -eq $want ]] && ok "$lock: $got components" || fail "$lock: $got components, the lock file pins $want packages"
done < <(git ls-files '*Cargo.lock' '*pubspec.lock' '*package-lock.json')

finish
