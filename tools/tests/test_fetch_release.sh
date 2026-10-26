#!/usr/bin/env bash
# tools/fetch_release.sh downloads a release tarball, refuses it unless it matches the pinned SHA-256, and extracts one
# file. The downloads here are file:// URLs, so the test needs no network.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool curl
# the retries of tools/retry.sh, short: a file:// URL that is missing is retried by curl too
export RETRY_COUNT=1 RETRY_DELAY=1

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir "$SANDBOX/release"
printf '#!/bin/sh\necho plugin\n' >"$SANDBOX/release/tool"
chmod +x "$SANDBOX/release/tool"
echo notice >"$SANDBOX/release/LICENSE"
tar -czf "$SANDBOX/tool.tar.gz" -C "$SANDBOX/release" tool LICENSE
URL=file://$SANDBOX/tool.tar.gz
SUM=$(sha256sum <"$SANDBOX/tool.tar.gz")
SUM=${SUM%% *}

fetch() {
  OUT=$(bash "$REPO_ROOT/tools/fetch_release.sh" "$@" 2>&1)
  STATUS=$?
}

fetch "$URL" "$SUM" "$SANDBOX/good" tool
[[ $STATUS -eq 0 && $("$SANDBOX/good/tool") == plugin && ! -e $SANDBOX/good/LICENSE ]] &&
  ok "a tarball with the pinned SHA-256 yields the one file asked for" || fail "good tarball: exit $STATUS: $OUT"

tar -cJf "$SANDBOX/tool.tar.xz" -C "$SANDBOX/release" tool LICENSE
XZ_SUM=$(sha256sum <"$SANDBOX/tool.tar.xz")
fetch "file://$SANDBOX/tool.tar.xz" "${XZ_SUM%% *}" "$SANDBOX/xz" tool LICENSE
[[ $STATUS -eq 0 && $("$SANDBOX/xz/tool") == plugin && -f $SANDBOX/xz/LICENSE ]] &&
  ok "an xz tarball yields every file asked for" || fail "xz tarball with two files: exit $STATUS: $OUT"

(cd "$SANDBOX/release" && python3 -m zipfile -c "$SANDBOX/tool.whl" tool LICENSE)
ZIP_SUM=$(sha256sum <"$SANDBOX/tool.whl")
fetch "file://$SANDBOX/tool.whl" "${ZIP_SUM%% *}" "$SANDBOX/zip" tool
[[ $STATUS -eq 0 && $("$SANDBOX/zip/tool") == plugin && ! -e $SANDBOX/zip/LICENSE ]] &&
  ok "a zip or a Python wheel yields the file asked for, executable" || fail "zip: exit $STATUS: $OUT"

# A wheel's binary and its data directory, the second asked for as unzip's pattern (as tools/lint/tool.sh's clang-tidy)
mkdir -p "$SANDBOX/wheel/pkg/data/bin" "$SANDBOX/wheel/pkg/data/lib/clang/22/include"
cp "$SANDBOX/release/tool" "$SANDBOX/wheel/pkg/data/bin/"
echo header >"$SANDBOX/wheel/pkg/data/lib/clang/22/include/stddef.h"
(cd "$SANDBOX/wheel" && python3 -m zipfile -c "$SANDBOX/data.whl" pkg)
WHEEL=("file://$SANDBOX/data.whl" "$(sha256sum <"$SANDBOX/data.whl" | cut -d' ' -f1)")
fetch "${WHEEL[@]}" "$SANDBOX/patterns" pkg/data/bin/tool 'pkg/data/lib/*'
[[ $STATUS -eq 0 && $("$SANDBOX/patterns/pkg/data/bin/tool") == plugin &&
  $(cat "$SANDBOX/patterns/pkg/data/lib/clang/22/include/stddef.h") == header ]] &&
  ok "a pattern yields every file it matches" || fail "pattern: exit $STATUS: $OUT"
# A move that fails midway, as on a full disk: the first file asked for, which callers test for, must not be there.
mkdir "$SANDBOX/full"
printf '#!/bin/bash\n[[ $* != *stddef.h* ]] && exec "%s" "$@"\nexit 1\n' "$(command -v mv)" >"$SANDBOX/full/mv"
chmod +x "$SANDBOX/full/mv"
PATH=$SANDBOX/full:$PATH fetch "${WHEEL[@]}" "$SANDBOX/half" pkg/data/bin/tool 'pkg/data/lib/*'
[[ $STATUS -ne 0 && ! -e $SANDBOX/half/pkg/data/bin/tool ]] &&
  ok "a fetch that fails midway leaves no first file, so its caller fetches again" || fail "half: exit $STATUS: $OUT"

BARE_SUM=$(sha256sum <"$SANDBOX/release/tool")
fetch "file://$SANDBOX/release/tool" "${BARE_SUM%% *}" "$SANDBOX/bare" cloudtool
[[ $STATUS -eq 0 && $("$SANDBOX/bare/cloudtool") == plugin ]] &&
  ok "a bare executable is saved as the file asked for" || fail "bare executable: exit $STATUS: $OUT"

fetch "$URL" "${SUM//?/0}" "$SANDBOX/tampered" tool
[[ $STATUS -ne 0 && $OUT == *"SHA-256"* && ! -e $SANDBOX/tampered ]] &&
  ok "a tarball that does not match the pin is refused and nothing is extracted" || fail "wrong checksum: exit $STATUS: $OUT"

# A curl whose first download comes back corrupt, as a flaky mirror's does
mkdir "$SANDBOX/flaky"
cat >"$SANDBOX/flaky/curl" <<EOF
#!/bin/bash
echo "\$*" >>"$SANDBOX/curl.log"
[[ \$(wc -l <"$SANDBOX/curl.log") -gt 1 ]] && exec "$(command -v curl)" "\$@"
while [[ \$1 != -o ]]; do shift; done
echo corrupt >"\$2"
EOF
chmod +x "$SANDBOX/flaky/curl"
PATH=$SANDBOX/flaky:$PATH fetch "$URL" "$SUM" "$SANDBOX/refetched" tool
[[ $STATUS -eq 0 && $("$SANDBOX/refetched/tool") == plugin && $(wc -l <"$SANDBOX/curl.log") -eq 2 ]] &&
  ok "a corrupt download is fetched once more" || fail "corrupt download: exit $STATUS: $OUT"

# A tar or install that has written the file but not returned yet, as a slow one has written half of it: until the
# fetch is done, a second gate that finds the file at its path would run it.
mkdir "$SANDBOX/slow"
for tool in tar install; do
  printf '#!/bin/bash\n"%s" "$@" && touch %s/paused && until [[ -e %s/go ]]; do sleep 0.05; done\n' \
    "$(command -v $tool)" "$SANDBOX" "$SANDBOX" >"$SANDBOX/slow/$tool"
done
chmod +x "$SANDBOX/slow/"*
for case in "$URL $SUM tool" "file://$SANDBOX/release/tool ${BARE_SUM%% *} cloudtool"; do
  read -r url sum file <<<"$case"
  rm -f "$SANDBOX/paused" "$SANDBOX/go"
  PATH=$SANDBOX/slow:$PATH bash "$REPO_ROOT/tools/fetch_release.sh" "$url" "$sum" "$SANDBOX/racing" "$file" &
  until [[ -e $SANDBOX/paused ]]; do sleep 0.05; done
  [[ ! -e $SANDBOX/racing/$file ]] && ok "$file is not at its path while it is being written" ||
    fail "$file is at its path before the fetch is done"
  touch "$SANDBOX/go"
  wait $!
  [[ $? -eq 0 && $("$SANDBOX/racing/$file") == plugin ]] && ok "then $file is there whole" || fail "$file after the fetch"
done
[[ $(ls -A "$SANDBOX/racing") == $'cloudtool\ntool' ]] && ok "and nothing else is left beside the files" ||
  fail "left beside: $(ls -A "$SANDBOX/racing")"

fetch "file://$SANDBOX/missing.tar.gz" "$SUM" "$SANDBOX/missing" tool
[[ $STATUS -ne 0 && ! -e $SANDBOX/missing ]] && ok "a failed download fails" || fail "missing download: exit $STATUS: $OUT"

mkdir "$SANDBOX/no-curl"
for tool in bash mktemp rm; do ln -s "$(command -v "$tool")" "$SANDBOX/no-curl/$tool"; done
OUT=$(PATH=$SANDBOX/no-curl bash "$REPO_ROOT/tools/fetch_release.sh" "$URL" "$SUM" "$SANDBOX/no-curl-out" tool 2>&1)
[[ $? -ne 0 && $OUT == *"'curl' is required"* ]] && ok "without curl it fails loudly" || fail "without curl: $OUT"

finish
