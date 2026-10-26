#!/usr/bin/env bash
# Writes hls.js, which plays photolibd's HLS ladder in the browsers that have no HLS of their own (every one but Safari),
# and its licence: bash tools/hls/web.sh <out-dir>. The release is pinned below by the integrity npm publishes for it
# (a stale cache or a corrupt download fails), downloaded once into a per-user cache. It loads only when a video plays
# (app/lib/features/viewer/mpv_web.dart), never at the app's start, and asks for nothing but the server's own URLs.
# Needs curl, python3 and tar, and network on the first run.
set -euo pipefail

out=${1:?usage: web.sh <out-dir>}
VERSION=1.7.3
INTEGRITY=sha512-MsPlx6yVW4Qv4C7mEVou4/gk/5cN2dVxOTnrNjPSmyH2f0Ln+/UkG10Ax1PE6OvrmTVPKgQYozTtBaPOuCzq7A==

integrity() { python3 -c 'import base64, hashlib, sys; print("sha512-" + base64.b64encode(hashlib.sha512(open(sys.argv[1], "rb").read()).digest()).decode())' "$1"; }
root=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
(umask 077 && mkdir -p "$root")
if [[ -L $root || ! -O $root ]]; then
  echo "web.sh: $root is not a private directory of this user; set PHOTOLIB_TOOLS_CACHE to one" >&2
  exit 1
fi
cache=$root/hls.js-$VERSION.tgz
# shellcheck source=../retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/../retry.sh"
if [[ ! -f $cache || $(integrity "$cache") != "$INTEGRITY" ]]; then
  # Into a file of its own, which a gate downloading at the same time cannot overwrite.
  part=$(mktemp "$cache.XXXXXX")
  trap 'rm -f "$part"' EXIT
  for attempt in 1 2; do
    retry 3 curl -fsSL --retry "${RETRY_COUNT:-6}" --retry-all-errors --connect-timeout 20 --max-time "${RETRY_TIMEOUT:-600}" \
      -o "$part" "https://registry.npmjs.org/hls.js/-/hls.js-$VERSION.tgz" &&
      [[ $(integrity "$part") == "$INTEGRITY" ]] && break
    if ((attempt == 2)); then
      echo "web.sh: the downloaded hls.js $VERSION does not have the integrity $INTEGRITY that npm publishes" >&2
      exit 1
    fi
  done
  chmod 644 "$part"
  mv "$part" "$cache"
fi
mkdir -p "$out"
tar -xzOf "$cache" package/dist/hls.min.js >"$out/hls.min.js"
tar -xzOf "$cache" package/LICENSE >"$out/hls.LICENSE.txt"
