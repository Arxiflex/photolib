#!/usr/bin/env bash
# The kernel's web build (M0-13): tools/kernel/budget.mjs holds it to 1 MB brotli (ADR-0004), counting every file
# a browser fetches; the `web` part of the gate runs its vectors in browsers (test_check_sh.sh).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool node
require_tool python3

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# random <file> <bytes>: data that brotli cannot shrink.
random() { python3 -c 'import os, sys; open(sys.argv[1], "wb").write(os.urandom(int(sys.argv[2])))' "$1" "$2"; }
budget() { node "$REPO_ROOT/tools/kernel/budget.mjs" "$@" >"$WORK/out" 2>&1; }

random "$WORK/a.wasm" 600000
random "$WORK/b.js" 600000
head -c 2000000 /dev/zero >"$WORK/zeros.wasm"

check "600 kB that brotli cannot shrink is within the budget" budget "$WORK/a.wasm"
if budget "$WORK/a.wasm" "$WORK/b.js"; then fail "1.2 MB over two files passed the budget"; else ok "the files count together: 1.2 MB over two fails"; fi
check "the failure says by how much" grep -q 'over budget by' "$WORK/out"
check "2 MB that compresses well is within the budget: it is the brotli size that counts" budget "$WORK/zeros.wasm"
check "wasm.sh checks the budget of what it builds" grep -q 'budget\.mjs.*photolib_kernel_wasm\.js.*_bg\.wasm' \
  "$REPO_ROOT/tools/kernel/wasm.sh"

finish
