#!/usr/bin/env bash
# Writes what the replica needs in a browser: bash tools/data/web.sh <out-dir>. sqlite3mc.wasm is SQLite3MultipleCiphers
# for the web from the release of the sqlite3 package that app/packages/photolib_data resolves from its committed
# pubspec.lock (a stale one fails), downloaded once into a per-user cache and checked against the hash that package
# publishes; drift_worker.js, data_worker.js, metadata_worker.js and hash_worker.js are the drift worker, the data worker that reads
# folders' metadata and the workers it runs the kernel's module on, compiled from photolib_data/web/. Needs dart and
# curl, and network on the first run.
set -euo pipefail

out=${1:?usage: web.sh <out-dir>}
package=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../app/packages/photolib_data" && pwd)
[[ -f $package/.dart_tool/package_config.json ]] || (cd "$package" && dart pub get --enforce-lockfile >&2)
sqlite3=$(sed -n '/"name": "sqlite3",/{n;s|.*"file://\(.*\)",|\1|p;}' "$package/.dart_tool/package_config.json")
hashes=$sqlite3/lib/src/hook/asset_hashes.dart
tag=$(sed -n "s/^const String? releaseTag = '\(.*\)';/\1/p" "$hashes")
want=$(sed -n "s/^  'sqlite3mc.wasm': '\([0-9a-f]*\)',/\1/p" "$hashes")
[[ -n $tag && -n $want ]] || { echo "web.sh: no sqlite3mc.wasm release or hash in $hashes" >&2; exit 1; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
root=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
mkdir -p -m 700 "$root"
if [[ -L $root || ! -O $root ]]; then
  echo "web.sh: $root is not a private directory of this user; set PHOTOLIB_TOOLS_CACHE to one" >&2
  exit 1
fi
cache=$root/sqlite3mc-$tag.wasm
if [[ ! -f $cache || $(sha256 "$cache") != "$want" ]]; then
  url=https://github.com/simolus3/sqlite3.dart/releases/download/$tag/sqlite3mc.wasm
  # Into a file of its own, which a gate downloading at the same time cannot overwrite.
  part=$(mktemp "$cache.XXXXXX")
  trap 'rm -f "$part"' EXIT
  # shellcheck source=../retry.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../retry.sh"
  download "$url" "$part" "$want" || {
    echo "web.sh: the downloaded sqlite3mc.wasm of $tag does not have the sha256 $want that the package publishes" >&2
    exit 1
  }
  chmod 644 "$part"
  mv "$part" "$cache"
fi
mkdir -p "$out"
cp "$cache" "$out/sqlite3mc.wasm"
dart compile js -O4 --no-source-maps -o "$out/drift_worker.js" "$package/web/drift_worker.dart" >&2
for worker in data_worker metadata_worker hash_worker; do
  dart compile js -O4 --no-source-maps -o "$out/$worker.js" "$package/web/$worker.dart" >&2
done
rm -f "$out"/{drift,data,metadata,hash}_worker.js.deps
