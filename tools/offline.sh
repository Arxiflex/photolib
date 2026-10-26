#!/usr/bin/env bash
# Runs a test suite with egress blocked (OPS-25, design 06 §10): tools/offline.c, preloaded into every process of the
# suite, refuses connections to anything but loopback. The gate runs the product's test suites through this.
#
#   tools/offline.sh <command> [argument...]
set -euo pipefail

fail() {
  echo "tools/offline.sh: $*" >&2
  exit 1
}

[[ $(uname) == Linux ]] || fail "blocking egress needs Linux, where tools/offline.c is preloaded"
command -v cc >/dev/null 2>&1 || fail "'cc' is required to build tools/offline.c"
SOURCE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/offline.c
# Outside the checkout, which may be on a noexec mount from where no library can be preloaded.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
LIBRARY=$CACHE/offline-$(sha256sum <"$SOURCE" | cut -c1-16).so
if [[ ! -f $LIBRARY ]]; then
  (umask 077 && mkdir -p "$CACHE")
  [[ -O $CACHE ]] || fail "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own"
  cc -shared -fPIC -O2 -Wall -Werror -o "$LIBRARY.$$" "$SOURCE" -ldl
  mv "$LIBRARY.$$" "$LIBRARY"
fi
export LD_PRELOAD=$LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}
# Fetchers of pinned tools and models download nothing then: they name what is missing and the command that fetches it.
# Not a PHOTOLIB_ name: photolibd reads every PHOTOLIB_ variable as a setting.
export EGRESS_BLOCKED=1
# A library the loader cannot map is skipped with a warning, which would leave egress open: prove that it blocks.
probe=$(timeout 5 bash -c ': >/dev/tcp/192.0.2.1/9' 2>&1 || true)
[[ $probe == *"offline: blocked 192.0.2.1 port 9"* ]] ||
  fail "$LIBRARY does not block egress (is $CACHE on a noexec mount? set PHOTOLIB_TOOLS_CACHE): $probe"
exec "$@"
