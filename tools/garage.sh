#!/usr/bin/env bash
# Prints the path of the Garage binary that the storage tests start (photolib_storage::testing): the release that
# ADR-0018 pins for the development stack, downloaded once into the per-user tools cache and checked against the
# SHA-256 pinned below. Garage publishes no checksums; these were taken when the version was pinned.
set -euo pipefail

VERSION=v2.4.1
declare -A SHA256=(
  [x86_64]=ae49f8de4aaee6b5ca305f7cbdccc8cd8a29b2804aac074649f18bfb83d0a2b6
  [aarch64]=004b6081c6e3cccbb80317c69e3c5749fbb3fc889e217cc9b89c215bf0dd7ded
)

ARCH=$(uname -m)
PINNED=${SHA256[$ARCH]:-}
if [[ $(uname -s) != Linux || -z $PINNED ]]; then
  echo "Garage $VERSION has no pinned build for $(uname -s) $ARCH; put a garage $VERSION binary on PATH" >&2
  exit 1
fi

# Outside the checkout, which may be on a noexec mount where Garage cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
GARAGE=$CACHE/garage-$VERSION/garage
if [[ ! -x $GARAGE ]]; then
  if [[ -n ${EGRESS_BLOCKED:-} ]]; then
    echo "Garage $VERSION is not in $CACHE, and egress is blocked (tools/offline.sh);" \
      "fetch it first: bash tools/garage.sh" >&2
    exit 1
  fi
  (umask 077 && mkdir -p "$CACHE")
  if [[ ! -O $CACHE ]]; then
    echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "'curl' is required to download Garage $VERSION" >&2
    exit 1
  fi
  mkdir -p "${GARAGE%/*}"
  DOWNLOAD=$(mktemp "${GARAGE%/*}/download.XXXXXX")
  trap 'rm -f "$DOWNLOAD"' EXIT
  # The host (garagehq.deuxfleurs.fr) answers 503 now and then, and the gate's prefetch runs this once, before egress is
  # blocked: every storage test then fails on "egress is blocked" (queue run 40232538815). Fetched up to four times.
  URL=https://garagehq.deuxfleurs.fr/_releases/$VERSION/$ARCH-unknown-linux-musl/garage
  for attempt in 1 2 3 4; do
    curl -fsSL -o "$DOWNLOAD" "$URL" && break
    if ((attempt == 4)); then
      echo "the Garage $VERSION download failed four times" >&2
      exit 1
    fi
    echo "tools/garage.sh: the Garage $VERSION download failed (attempt $attempt of 4): once more" >&2
    sleep $((attempt * 5))
  done
  actual=$(sha256sum <"$DOWNLOAD")
  if [[ ${actual%% *} != "$PINNED" ]]; then
    echo "the Garage $VERSION download does not match the pinned SHA-256 $PINNED" >&2
    exit 1
  fi
  chmod 755 "$DOWNLOAD"
  mv "$DOWNLOAD" "$GARAGE"
fi
echo "$GARAGE"
