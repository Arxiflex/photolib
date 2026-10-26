#!/usr/bin/env bash
# Runs promtool from the Prometheus release that deploy/observability/compose.yaml deploys, downloaded once into the
# per-user tools cache by tools/fetch_release.sh, which checks the pinned SHA-256.
#
#   tools/promtool.sh test rules deploy/observability/alerts.test.yml
set -euo pipefail

VERSION=3.15.0
declare -A SHA256=(
  [linux-amd64]=2a542df32eac02ee17b9d844fb2aa1de00dafa5476579ba8a3ba862e9d572ea0
  [linux-arm64]=f1f90ec08e849d494ca66c611470afc50192f0355f1a61c33f2cbde02d067823
  [darwin-amd64]=2d79e744c2d7e505db936fbc898e05abc74fcb6e437c25befd26e9c9f00aa58b
  [darwin-arm64]=920df4d17e78b3b0175af144eb318b0c74d1cf7b1d1251b326966f0e81977260
)

ARCH=$(uname -m)
ARCH=${ARCH/x86_64/amd64}
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')-${ARCH/aarch64/arm64}
PINNED=${SHA256[$PLATFORM]:-}
if [[ -z $PINNED ]]; then
  echo "Prometheus $VERSION has no pinned release for $PLATFORM" >&2
  exit 1
fi

# Outside the checkout, which may be on a noexec mount where promtool cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
NAME=prometheus-$VERSION.$PLATFORM
if [[ ! -x $CACHE/$NAME/promtool ]]; then
  (umask 077 && mkdir -p "$CACHE")
  if [[ ! -O $CACHE ]]; then
    echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  bash "$(dirname "${BASH_SOURCE[0]}")/fetch_release.sh" \
    "https://github.com/prometheus/prometheus/releases/download/v$VERSION/$NAME.tar.gz" "$PINNED" "$CACHE" \
    "$NAME/promtool"
fi
exec "$CACHE/$NAME/promtool" "$@"
