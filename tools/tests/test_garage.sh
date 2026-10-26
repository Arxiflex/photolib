#!/usr/bin/env bash
# tools/garage.sh downloads the pinned Garage once into the tools cache, and the gate's prefetch runs it before egress
# is blocked: a download that fails now and then (garagehq.deuxfleurs.fr answered 503 in queue run 40232538815, and
# every storage test then failed on "egress is blocked") is fetched again before the script fails.
# shellcheck disable=SC2016 # stubs are literal scripts
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sandbox_tools bash env mkdir rm mv chmod cat dirname mktemp id
PINNED=ae49f8de4aaee6b5ca305f7cbdccc8cd8a29b2804aac074649f18bfb83d0a2b6

# garage_sandbox <failures>: curl fails (22, as -f does on an HTTP 503) that many times, then writes a file.
garage_sandbox() {
  new_sandbox tools/garage.sh
  CACHE=$SANDBOX/cache
  printf '#!/bin/bash\ncase $1 in -s) echo Linux ;; -m) echo x86_64 ;; esac\n' >"$SANDBOX/stubs/uname"
  printf '#!/bin/bash\necho %s -\n' "$PINNED" >"$SANDBOX/stubs/sha256sum"
  printf '#!/bin/bash\necho "sleep $*" >>%q\n' "$SANDBOX/calls.log" >"$SANDBOX/stubs/sleep"
  cat >"$SANDBOX/stubs/curl" <<STUB
#!/bin/bash
echo "curl \$*" >>"$SANDBOX/calls.log"
n=\$(cat "$SANDBOX/seen" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$SANDBOX/seen"
((n < $1)) && { echo "curl: (22) The requested URL returned error: 503" >&2; exit 22; }
while [[ \$1 != -o ]]; do shift; done
echo garage >"\$2"
STUB
  chmod +x "$SANDBOX"/stubs/*
}
run_garage() {
  PHOTOLIB_TOOLS_CACHE=$CACHE PATH="$SANDBOX/stubs:$BASE_BIN" capture bash "$SANDBOX/tools/garage.sh"
}
downloads() { grep -c '^curl ' "$SANDBOX/calls.log"; }

garage_sandbox 0
run_garage
expect_result "a download that works runs once" 0 "$CACHE/garage-v2.4.1/garage"
[[ $(downloads) == 1 ]] && ok "it downloaded once" || fail "it downloaded $(downloads) times"

garage_sandbox 2
run_garage
expect_result "a download that fails twice (HTTP 503) is fetched again and works" 0 "$CACHE/garage-v2.4.1/garage"
[[ $(downloads) == 3 ]] && ok "it downloaded three times" || fail "it downloaded $(downloads) times, not 3"
[[ -x $CACHE/garage-v2.4.1/garage ]] && ok "the binary is in the cache" || fail "no executable in the cache"

garage_sandbox 99
run_garage
expect_result "a download that always fails fails the script, naming the download" failure "503" "Garage v2.4.1"
[[ $(downloads) == 4 ]] && ok "it gave up after four downloads" || fail "it downloaded $(downloads) times, not 4"

garage_sandbox 99
EGRESS_BLOCKED=1 run_garage
expect_result "under a blocked egress it downloads nothing and says how to fetch" failure "egress is blocked"
[[ $(downloads) == 0 ]] && ok "no download under tools/offline.sh" || fail "it downloaded under a blocked egress"

finish
