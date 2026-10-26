#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

probe() (
  STATUS=$1 OUT=$2 FAILURES=0
  shift 2
  expect_result fixture "$@"
  finish
)

check "result assertions accept matching status and every literal fragment" probe 2 'first * last' 2 first '*' last
check "result assertions accept any nonzero failure" probe 2 error failure error
for actual in 0 1; do
  if probe "$actual" error 2 >/dev/null 2>&1; then
    fail "result assertion accepted status $actual instead of 2"
  else
    ok "result assertions reject status $actual instead of 2"
  fi
done
if probe 0 error failure >/dev/null 2>&1; then fail "failure assertion accepted success"; else
  ok "failure assertions reject success"
fi
if probe 1 'first last' 1 first missing last >/dev/null 2>&1; then fail "missing fragment passed"; else
  ok "result assertions reject a missing fragment"
fi
capture bash -c 'echo output; echo error >&2; exit 3'
expect_result "capture keeps stdout, stderr and status" 3 output error

pattern_probe() (
  FAILURES=0
  assert_patterns "$@"
  finish
)

for assertion in assert_matches assert_prose; do
  capture pattern_probe "$assertion" tools/tests/lib.sh \
    'FAILURES=0' "counter" 'ok\(\)' "reporter"
  expect_result "$assertion tables run every matching pattern" 0 \
    "ok: tools/tests/lib.sh: counter" "ok: tools/tests/lib.sh: reporter"
  capture pattern_probe "$assertion" tools/tests/lib.sh \
    'not-a-test-helper' "missing" 'FAILURES=0' "counter" 'also-not-a-test-helper' "missing again"
  expect_result "$assertion tables report every failure and keep checking" 1 \
    "FAIL: tools/tests/lib.sh: missing" "ok: tools/tests/lib.sh: counter" \
    "FAIL: tools/tests/lib.sh: missing again" "2 assertion(s) failed"
done

# A sandbox's commit runs none of the caller's git hooks, wherever core.hooksPath points (a global setting, an agent's
# session): its own commit lint refused test_check_sh.sh's deliberately bad commits.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir "$SANDBOX/hooks" "$SANDBOX/repo"
printf '#!/bin/sh\nexit 1\n' >"$SANDBOX/hooks/commit-msg"
chmod +x "$SANDBOX/hooks/commit-msg"
git -C "$SANDBOX/repo" init -q
capture env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$SANDBOX/hooks" bash -c \
  "source '$REPO_ROOT/tools/tests/lib.sh' && git -C '$SANDBOX/repo' -c user.name=T -c user.email=t@example.org \
   commit -q --allow-empty -m 'not conventional' && echo committed"
expect_result "a sandbox's commit runs none of the caller's git hooks" 0 committed
finish
