#!/usr/bin/env bash
# tools/repeat.sh repeats a selection of tests N times with every retry off and fails on any failure, and the gate's
# --since runs it for the tests a diff changes. The runners are stubs: the test proves the repetition, the mapping of
# test files to runners, the retry switch and the wiring, not the runners.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
sandbox_tools bash env sed grep sort mkdir cat rm dirname basename git head tr wc seq sleep touch cp cmp tail
require_tool git

new_sandbox tools/repeat.sh
mkdir -p "$SANDBOX/stubs"
REPEAT="$SANDBOX/tools/repeat.sh"
run_repeat() {
  OUT=$(cd "$SANDBOX" && PATH="$SANDBOX/stubs:$BASE_BIN" bash "$REPEAT" "$@" 2>&1)
  # shellcheck disable=SC2034 # read by expect_result
  STATUS=$?
}

# --- the repetition itself
run_repeat -n 3 -- bash -c 'echo run >>count'
expect_result "a passing command passes after the runs asked for" 0 "3 passed, 0 failed of 3 runs"
[[ $(wc -l <"$SANDBOX/count") -eq 3 ]] && ok "-n 3 ran it three times" || fail "-n 3 ran it $(wc -l <"$SANDBOX/count") times"

rm "$SANDBOX/count"
run_repeat -- bash -c 'echo run >>count'
[[ $(wc -l <"$SANDBOX/count") -eq 10 ]] && ok "it repeats ten times by default" || fail "default: $(wc -l <"$SANDBOX/count") runs"

rm "$SANDBOX/count"
OUT=$(cd "$SANDBOX" && REPEAT_N=4 PATH="$SANDBOX/stubs:$BASE_BIN" bash "$REPEAT" -- bash -c 'echo run >>count' 2>&1)
[[ $(wc -l <"$SANDBOX/count") -eq 4 ]] && ok "REPEAT_N sets the default" || fail "REPEAT_N: $(wc -l <"$SANDBOX/count") runs"

# A test that fails one run in five passes the gate on a retry; here the fifth run's failure fails it.
rm "$SANDBOX/count"
FIFTH="echo run >>count; [[ \$(wc -l <count) -ne 5 ]]"
run_repeat -- bash -c "$FIFTH"
expect_result "one failure among ten runs fails the whole" failure "4 passed, 1 failed of 10 runs" "FAIL"
[[ $(wc -l <"$SANDBOX/count") -eq 5 ]] && ok "the first failure stops the repetition" ||
  fail "it ran $(wc -l <"$SANDBOX/count") times"

rm "$SANDBOX/count"
run_repeat -k -- bash -c "$FIFTH"
expect_result "-k keeps going and counts the failures" failure "9 passed, 1 failed of 10 runs"

run_repeat -n 0 -- true
expect_result "-n 0 is a usage error" 2 "positive whole number"
REPEAT_N=x run_repeat -- true
expect_result "REPEAT_N must be a number" 2 "REPEAT_N must be a positive whole number"
run_repeat --nonsense
expect_result "an unknown option is a usage error" 2 "unknown option"

# --- which runner a test file gets
mkdir -p "$SANDBOX/app/test/features" "$SANDBOX/app/packages/data/test" "$SANDBOX/app/packages/web/test" \
  "$SANDBOX/server/crates/store/tests" "$SANDBOX/server/crates/store/src/s3" "$SANDBOX/viewer/test" \
  "$SANDBOX/tools/tests" "$SANDBOX/tools/download"
printf 'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n' >"$SANDBOX/app/pubspec.yaml"
printf 'name: data\nenvironment:\n  sdk: ^3.9.0\n' >"$SANDBOX/app/packages/data/pubspec.yaml"
printf 'name: web\ndependencies:\n  flutter:\n    sdk: flutter\n' >"$SANDBOX/app/packages/web/pubspec.yaml"
printf "@TestOn('browser')\nlibrary;\n" >"$SANDBOX/app/packages/web/test/web_test.dart"
touch "$SANDBOX/app/test/features/a_test.dart" "$SANDBOX/app/test/features/b_test.dart" \
  "$SANDBOX/app/packages/data/test/c_test.dart"
printf '[workspace]\nmembers = ["crates/*"]\n' >"$SANDBOX/server/Cargo.toml"
printf '[package]\nname = "photolib-store"\n' >"$SANDBOX/server/crates/store/Cargo.toml"
touch "$SANDBOX/server/crates/store/tests/conformance.rs"
printf '#[cfg(test)]\nmod tests {}\n' >"$SANDBOX/server/crates/store/src/s3/retry.rs"
printf 'pub fn no_tests() {}\n' >"$SANDBOX/server/crates/store/src/plain.rs"
printf '{}\n' >"$SANDBOX/viewer/package.json"
touch "$SANDBOX/viewer/test/api.test.ts" "$SANDBOX/tools/download/test.mjs" "$SANDBOX/tools/tests/test_x.sh"
printf 'python3 tools/tests/check_y.py\n' >"$SANDBOX/tools/tests/test_y.sh"
touch "$SANDBOX/tools/tests/check_y.py" "$SANDBOX/tools/tests/check_alone.py"

run_repeat --list app/test/features/a_test.dart app/test/features/b_test.dart
expect_result "a package's Flutter tests run in one process" 0 \
  $'app\tflutter test --no-pub test/features/a_test.dart test/features/b_test.dart'
run_repeat --list app/packages/data/test/c_test.dart
expect_result "a Dart package without Flutter runs dart test" 0 $'app/packages/data\tdart test test/c_test.dart'
run_repeat --list app/packages/web/test/web_test.dart
expect_result "a browser test runs in Chrome" 0 $'app/packages/web\tflutter test --no-pub --platform chrome'
run_repeat --list server/crates/store/tests/conformance.rs
expect_result "an integration test is its own nextest binary, no retries" 0 \
  $'server/crates/store\tcargo nextest run --retries 0 --no-fail-fast  -p photolib-store --test conformance'
run_repeat --list server/crates/store/src/s3/retry.rs
expect_result "a src file with tests runs its module's tests" 0 "-p photolib-store --lib s3::retry"
run_repeat --list server/crates/store/src/plain.rs
expect_result "a src file without tests runs nothing" 0 "no test to repeat"
run_repeat --list viewer/test/api.test.ts tools/download/test.mjs
expect_result "Node tests run under node --test" 0 $'viewer\tnode --test test/api.test.ts' \
  $'tools/download\tnode --test test.mjs'
run_repeat --list tools/tests/test_x.sh tools/tests/check_y.py
expect_result "a shell test runs itself, a Python helper the shell test that names it" 0 \
  $'.\tbash tools/tests/test_x.sh' $'.\tbash tools/tests/test_y.sh'
run_repeat --list tools/tests/check_alone.py
expect_result "a Python test no shell test names runs itself" 0 $'.\tpython3 tools/tests/check_alone.py'
REPEAT_CARGO_ARGS="--config x" run_repeat --list server/crates/store/tests/conformance.rs
expect_result "REPEAT_CARGO_ARGS go to cargo" 0 "--config x -p photolib-store"
run_repeat --list README.md
expect_result "a file that is no test runs nothing" 0 "no test to repeat"

# --- the retry switch: dart_test.yaml has `retry: 0` for the runs and its text back after, even after a failure
printf 'retry: 3\ntimeout: 4x\n' >"$SANDBOX/app/dart_test.yaml"
cp "$SANDBOX/app/dart_test.yaml" "$SANDBOX/app.yaml.orig"
printf '#!/bin/bash\ngrep "^retry" dart_test.yaml >>"%s/seen"\n[[ -z $%s ]]\n' "$SANDBOX" FAIL >"$SANDBOX/stubs/flutter"
chmod +x "$SANDBOX/stubs/flutter"
: >"$SANDBOX/seen"
run_repeat -n 2 app/test/features/a_test.dart
expect_result "a Flutter test runs" 0 "2 passed, 0 failed of 2 runs"
[[ $(<"$SANDBOX/seen") == $'retry: 0\nretry: 0' ]] && ok "dart_test.yaml has no retry during the runs" ||
  fail "dart_test.yaml during the runs: $(<"$SANDBOX/seen")"
cmp -s "$SANDBOX/app/dart_test.yaml" "$SANDBOX/app.yaml.orig" && ok "and its text back after" ||
  fail "dart_test.yaml after: $(<"$SANDBOX/app/dart_test.yaml")"
FAIL=1 run_repeat app/test/features/a_test.dart
expect_result "a failing Flutter test fails" failure "0 passed, 1 failed of 10 runs"
cmp -s "$SANDBOX/app/dart_test.yaml" "$SANDBOX/app.yaml.orig" && ok "dart_test.yaml is back after a failure" ||
  fail "dart_test.yaml after a failure: $(<"$SANDBOX/app/dart_test.yaml")"

# --- --since: the test files the diff adds or changes
(
  cd "$SANDBOX" || exit 1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q . && git add -A . && git commit -qm base
  git tag base
  echo '// changed' >>app/test/features/a_test.dart
  echo '// changed' >>tools/tests/test_x.sh
  echo '# docs' >README.md
  git add -A . && git commit -qm change
) >/dev/null 2>&1
run_repeat --list --since base
expect_result "--since lists the tests the diff changed, and only those" 0 \
  $'app\tflutter test --no-pub test/features/a_test.dart' $'.\tbash tools/tests/test_x.sh'
[[ $OUT != *b_test* && $OUT != *README* ]] && ok "an untouched test and a doc are left out" || fail "listed too much: $OUT"
run_repeat --list --since HEAD
expect_result "a diff that changes no test repeats nothing" 0 "no test to repeat"

# --- the gate runs it with --since, after the parts, and not otherwise
assert_matches tools/check.sh 'repeat\.sh --since' "check.sh runs tools/repeat.sh --since for an item's own gate"
assert_matches tools/check.sh 'CHECK_REPEAT' "CHECK_REPEAT sets (or, at 0, skips) the repetitions"
assert_matches tools/check.sh "'repo: tools/tests/\* tools/repeat.sh" "a change to the guard runs the repo part"
assert_prose AGENTS.md 'tools/repeat\.sh' "AGENTS.md documents the guard"
assert_prose tools/README.md 'repeat\.sh' "tools/README.md documents the guard"

finish
