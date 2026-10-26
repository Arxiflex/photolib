#!/usr/bin/env bash
# Readies a directory of release files for publishing (NFR-SEC-2): writes a CycloneDX SBOM of the lock files the
# release is built from, SHA256SUMS over every file, and SHA256SUMS.sigstore.json, a cosign signature of SHA256SUMS.
# In a release job cosign signs keylessly with the workflow's GitHub identity; elsewhere only with the hardware-held key
# COSIGN_KEY names (a pkcs11: URI), never a person's identity (ADR-0058). docs/dev/supply-chain.md verifies both.
#
#   [COSIGN_KEY=pkcs11:...] tools/release.sh <directory> <name> <version> <lock file>...
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: tools/release.sh <directory> <name> <version> <lock file>..." >&2
  exit 2
fi
DIR=$1 NAME=$2 VERSION=$3
shift 3
if ! command -v cosign >/dev/null 2>&1; then
  echo "tools/release.sh: 'cosign' is required to sign the release" >&2
  exit 1
fi
if [[ -n ${ACTIONS_ID_TOKEN_REQUEST_URL:-} ]]; then
  key=()
elif [[ ${COSIGN_KEY:-} == pkcs11:* ]]; then
  key=(--key "$COSIGN_KEY")
else
  echo "tools/release.sh: outside the release job, sign with a hardware-held key: set COSIGN_KEY to its pkcs11: URI." \
    "cosign would sign keylessly with whoever logs in, never with a personal identity" >&2
  exit 1
fi
rm -f "$DIR/SHA256SUMS" "$DIR/SHA256SUMS.sigstore.json"
python3 "$(dirname "${BASH_SOURCE[0]}")/sbom.py" "$NAME" "$VERSION" "$@" >"$DIR/$NAME-$VERSION.cdx.json"
sums=$(cd "$DIR" && find . -maxdepth 1 -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum)
echo "$sums" >"$DIR/SHA256SUMS"
cosign sign-blob --yes "${key[@]}" --bundle "$DIR/SHA256SUMS.sigstore.json" "$DIR/SHA256SUMS"
