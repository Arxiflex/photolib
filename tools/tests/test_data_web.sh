#!/usr/bin/env bash
# The replica's web assets (M0-23): tools/data/web.sh takes sqlite3mc.wasm from the release of the sqlite3 package
# that photolib_data resolves and refuses a download whose sha256 is not the one that package publishes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool sha256sum

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# A copy of the script next to a resolved photolib_data whose sqlite3 publishes the hash of "good", and stubs: curl
# serves $SERVE, dart writes the worker.
mkdir -p "$WORK/tools/data" "$WORK/app/packages/photolib_data/.dart_tool" "$WORK/sqlite3/lib/src/hook" "$WORK/bin"
cp "$REPO_ROOT/tools/data/web.sh" "$WORK/tools/data/"
cp "$REPO_ROOT/tools/retry.sh" "$WORK/tools/"
printf '      "name": "sqlite3",\n      "rootUri": "file://%s",\n' "$WORK/sqlite3" \
  >"$WORK/app/packages/photolib_data/.dart_tool/package_config.json"
cat >"$WORK/sqlite3/lib/src/hook/asset_hashes.dart" <<EOF
const String? releaseTag = 'sqlite3-9.9.9';
  'sqlite3mc.wasm': '$(printf good | sha256sum | cut -d' ' -f1)',
EOF
# curl serves the words of $SERVE in turn, the last one from then on
printf '#!/bin/bash\necho "$*" >>"%s/url"\nserve=($SERVE)\nn=$(wc -l <"%s/url")\nprintf "${serve[n-1]:-${serve[-1]}}" >"${@: -2:1}"\n' \
  "$WORK" "$WORK" >"$WORK/bin/curl"
printf '#!/bin/bash\necho worker >"$6"\n' >"$WORK/bin/dart"
chmod +x "$WORK/bin/"*
web() { SERVE=$1 PATH="$WORK/bin:$PATH" PHOTOLIB_TOOLS_CACHE="${CACHE:-$WORK/cache}" timeout 60 bash "$WORK/tools/data/web.sh" "$WORK/out" 2>"$WORK/err"; }

if web evil; then fail "a sqlite3mc.wasm with another hash was accepted"; else
  ok "a sqlite3mc.wasm whose sha256 differs from the published one is refused"
fi
check "the refusal names the hash" grep -q 'sha256' "$WORK/err"
[[ ! -e $WORK/out/sqlite3mc.wasm && -z $(ls "$WORK/cache") ]] && ok "and nothing of it is kept" ||
  fail "a refused download was kept"

rm "$WORK/url"
check "a corrupt download is fetched once more" web "evil good"
check "and only once" test "$(wc -l <"$WORK/url")" -eq 2
check "the published sqlite3mc.wasm is accepted" web good
check "it comes from the package's release" grep -q 'releases/download/sqlite3-9.9.9/sqlite3mc.wasm' "$WORK/url"
check "next to the compiled drift worker" test "$(cat "$WORK/out/sqlite3mc.wasm" "$WORK/out/drift_worker.js")" = \
  "goodworker"
check "and the compiled data and metadata workers" \
  test "$(cat "$WORK/out/"{data,metadata}_worker.js)" = $'worker\nworker'

mkdir "$WORK/planted"
ln -s "$WORK/planted" "$WORK/link"
if CACHE=$WORK/link web good; then fail "a cache directory that is a symlink was used"; else
  ok "a cache directory that is a symlink, which another user could have planted, is refused"
fi
check "the refusal says how to move the cache" grep -q 'PHOTOLIB_TOOLS_CACHE' "$WORK/err"

# Two gates at once: the first one's curl has written half the file when the second downloads, checks and keeps its
# own. Each downloads once, into a file of its own, and both get the published file.
rm -rf "$WORK/cache" "$WORK/url"
cat >"$WORK/bin/curl" <<EOF
#!/bin/bash
echo "\$*" >>"$WORK/url"
exec 3>"\${@: -2:1}"
printf go >&3
if [[ \$(wc -l <"$WORK/url") -eq 1 ]]; then touch "$WORK/paused"; for _ in {1..400}; do [[ -e $WORK/go ]] && break; sleep 0.05; done; fi
printf od >&3
EOF
racing() { PATH="$WORK/bin:$PATH" PHOTOLIB_TOOLS_CACHE=$WORK/cache timeout 60 bash "$WORK/tools/data/web.sh" "$WORK/$1" 2>>"$WORK/err"; }
racing first &
for _ in {1..400}; do [[ -e $WORK/paused ]] && break; sleep 0.05; done
racing second
second=$?
touch "$WORK/go"
wait $!
[[ $? -eq 0 && $second -eq 0 ]] && ok "two gates fetching sqlite3mc.wasm at once both succeed" || fail "$(cat "$WORK/err")"
check "each downloads it once" test "$(wc -l <"$WORK/url")" -eq 2
check "both get the published file" test "$(cat "$WORK/first/sqlite3mc.wasm" "$WORK/second/sqlite3mc.wasm")" = goodgood
check "and only it is cached" test "$(ls -A "$WORK/cache")" = sqlite3mc-sqlite3-9.9.9.wasm

# photolib_data resolves from its committed pubspec.lock: a stale one fails web.sh and stays as it was
# (photolib-design#531).
if command -v dart >/dev/null; then
  stale=$WORK/stale/app/packages/photolib_data
  mkdir -p "$WORK/stale/tools/data"
  cp "$REPO_ROOT/tools/data/web.sh" "$WORK/stale/tools/data/"
  cp "$REPO_ROOT/tools/retry.sh" "$WORK/stale/tools/"
  stale_package "$stale" photolib_data
  stale() {
    ! timeout 60 bash "$WORK/stale/tools/data/web.sh" "$WORK/stale/out" 2>"$WORK/err" && grep -q 'Unable to satisfy' "$WORK/err" &&
      cmp -s "$stale.lock" "$stale/pubspec.lock"
  }
  check "a stale pubspec.lock of photolib_data fails web.sh and is left as it is" stale
else
  echo "skip: dart is not installed; web.sh is not run on a stale pubspec.lock"
fi

finish
