#!/usr/bin/env bash
# Downloads a release tarball (gzip or xz) or zip (a Python wheel too), refuses it unless it matches the pinned SHA-256,
# and extracts the files asked for (in a zip, unzip's patterns too); any other download is an executable, saved as the
# one file asked for.
#
#   tools/fetch_release.sh <url> <sha256> <directory> <file>...
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "usage: tools/fetch_release.sh <url> <sha256> <directory> <file>..." >&2
  exit 2
fi
URL=$1 PINNED=$2 DIR=$3
if ! command -v curl >/dev/null 2>&1; then
  echo "'curl' is required to download $URL" >&2
  exit 1
fi
TARBALL=$(mktemp)
trap 'rm -f "$TARBALL"' EXIT
# shellcheck source=retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/retry.sh"
download "$URL" "$TARBALL" "$PINNED" || { echo "$URL failed, or does not match the pinned SHA-256 $PINNED" >&2; exit 1; }
mkdir -p "$DIR"
# Extracted beside the files, then renamed into place: a gate fetching the same file at once never runs half of it.
STAGE=$(mktemp -d "$DIR/.fetch.XXXXXX")
trap 'rm -rf "$TARBALL" "$STAGE"' EXIT
case $URL in
  *.tar.gz | *.tgz | *.tar.xz) tar -xf "$TARBALL" -C "$STAGE" "${@:4}" ;;
  *.zip | *.whl) unzip -q -o "$TARBALL" "${@:4}" -d "$STAGE" ;;
  *) install -m 755 "$TARBALL" "$STAGE/$4" ;;
esac
# What was extracted, patterns (unzip's) expanded, and the first file last: callers test for it to fetch again.
(cd "$STAGE" && find . ! -type d ! -path "./$4" -print0 && find . ! -type d -path "./$4" -print0) |
  while IFS= read -r -d '' file; do
    mkdir -p "$(dirname "$DIR/$file")"
    mv -f "$STAGE/$file" "$DIR/$file"
  done
