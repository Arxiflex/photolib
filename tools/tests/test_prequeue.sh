#!/usr/bin/env bash
# tools/prequeue.sh, the checks that failed the merge queue: it passes a clean checkout, fails on a commit, a markdown
# line, a lock entry and a shell line that break the gate's rules, and lists the steps of each tier. Offline, in a
# scratch worktree of HEAD, and asserting no time.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
cd "$REPO_ROOT" || exit 1

WORK=$(mktemp -d)
trap 'git worktree remove --force "$WORK/tree" >/dev/null 2>&1; rm -rf "$WORK"' EXIT
git worktree add -q --detach "$WORK/tree" HEAD || { fail "cannot add a worktree of HEAD"; finish; }
BASE=$(git -C "$WORK/tree" rev-parse HEAD)

# prequeue <args...>: the script of this checkout in the scratch tree, offline, with a short list of repo tests
prequeue() {
  (cd "$WORK/tree" && PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 PREQUEUE_BASE=$BASE PREQUEUE_OTHERS='' \
    PREQUEUE_FAST_TESTS="layout markdown ci" bash "$REPO_ROOT/tools/prequeue.sh" "$@")
}

# --- a clean checkout passes (nothing differs from the base)
capture prequeue --quick
expect_result "--quick passes a checkout that differs from its base by nothing" 0 "prequeue: PASS (quick,"

# --- a commit with everything wrong in it fails, each step by name
mkdir -p "$WORK/tree/docs/dev" "$WORK/tree/tools"
{ printf '# Bad\n\n'; printf 'word %.0s' {1..26}; printf '\n'; } >"$WORK/tree/docs/dev/prequeue-bad.md"
# shellcheck disable=SC2016 # the shell line written is data, not for this shell to expand
printf '%s\n' '#!/usr/bin/env bash' 'mkdir -pm 700 "$1"' >"$WORK/tree/tools/prequeue-bad.sh"
printf '\n[[package]]\nname = "rs-vips"\nversion = "0.7.0"\n' >>"$WORK/tree/server/Cargo.lock"
# a Dart test that loads a model the gate's prefetch lacks; a Rust test that reads the clock; one ADR number twice
mkdir -p "$WORK/tree/app/packages/photolib_ml/test" "$WORK/tree/server/crates/x/tests"
printf '%s\n' "const model = 'ppocr-v5-det';" >"$WORK/tree/app/packages/photolib_ml/test/zz_test.dart"
printf '%s\n' 'fn t() { assert!(median < 5000.0); }' >"$WORK/tree/server/crates/x/tests/budget_test.rs"
printf '# A\n' >"$WORK/tree/docs/adr/9999-first.md"
printf '# B\n' >"$WORK/tree/docs/adr/9999-second.md"
git -C "$WORK/tree" add -A
git -C "$WORK/tree" -c user.name=t -c user.email=t@example.com commit -qm 'wip(x): y'
capture prequeue --quick
expect_result "--quick fails when a commit, a markdown line, a lock entry and a shell line break the rules" failure \
  "FAIL commitlint" "FAIL repo tests" "FAIL Cargo.lock path patch" "FAIL lint of touched files" \
  "FAIL models in the prefetch" "FAIL numbers taken twice" "warn test and URL smells" "prequeue: FAIL (quick," \
  "do not queue"

# --- a budget that is used up stops the run and says what did not run
BUDGETED=$(cd "$WORK/tree" && PREQUEUE_BUDGET=2 PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 PREQUEUE_BASE=$BASE PREQUEUE_OTHERS='' \
  bash "$REPO_ROOT/tools/prequeue.sh" --full 2>&1)
[[ $BUDGETED == *"the budget of 2s was used up"* || $BUDGETED == *"stopped: over the budget of 2s"* ]] &&
  ok "a used-up budget is reported as slow or skip" || fail "a budget of 2 s left no slow or skip line: $BUDGETED"
[[ $BUDGETED == *"== not run:"* ]] && ok "the steps not run are listed" || fail "no list of the steps not run"

# --- a run that cut a step ends INCOMPLETE with its own exit status, never PASS
INCOMPLETE=$(cd "$WORK/tree" && PREQUEUE_ONLY='repo tests' PREQUEUE_BUDGET=1 PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 \
  PREQUEUE_BASE=$BASE PREQUEUE_OTHERS='' bash "$REPO_ROOT/tools/prequeue.sh" --full 2>&1)
STATUS=$?
[[ $INCOMPLETE == *"prequeue: INCOMPLETE (1 step not run)"* && $STATUS -eq 3 ]] &&
  ok "a cut step ends the run INCOMPLETE, exit 3" || fail "a cut step: exit $STATUS: $INCOMPLETE"

# --- selected crates with no test (a proto-only branch) are no failure: nextest is told --no-tests=pass
mkdir -p "$WORK/stub"
# shellcheck disable=SC2016 # the stub logs its own arguments
printf '%s\n' '#!/bin/sh' 'echo "$@" >>"$CARGO_LOG"' >"$WORK/stub/cargo"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$WORK/stub/cargo-nextest"
chmod +x "$WORK/stub/cargo" "$WORK/stub/cargo-nextest"
printf '// a change\n' >"$WORK/tree/tools/synthlib/src/zz_prequeue.rs"
printf '// a change in a workspace of its own\n' >"$WORK/tree/kernel/fuzz/zz_prequeue.rs"
git -C "$WORK/tree" add -A
git -C "$WORK/tree" -c user.name=t -c user.email=t@example.com commit -qm 'wip(x): z'
if command -v taskset >/dev/null 2>&1 && command -v cc >/dev/null 2>&1; then
  export CARGO_LOG="$WORK/cargo.log"
  : >"$CARGO_LOG"
  STUBBED=$(cd "$WORK/tree" && PATH="$WORK/stub:$PATH" PREQUEUE_ONLY='rust tests (4 cores)' PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 \
    PREQUEUE_BASE=$BASE PREQUEUE_OTHERS='' bash "$REPO_ROOT/tools/prequeue.sh" --full 2>&1)
  grep -q -- '--no-tests=pass' "$CARGO_LOG" && ok "nextest runs the selected crates with --no-tests=pass" ||
    fail "no --no-tests=pass in the cargo calls: $(cat "$CARGO_LOG"): $STUBBED"
  grep -q 'kernel-fuzz' "$CARGO_LOG" && fail "a crate of a workspace of its own (kernel/fuzz) is selected: $(cat "$CARGO_LOG")" ||
    ok "a crate in a workspace of its own is left out of the selection"
fi

# --- every lint under app/test/tool/ runs as a guard (found by glob: a new one joins by itself)
mkdir -p "$WORK/tree/app/test/tool" "$WORK/tree/app/lib" "$WORK/tree/app/.dart_tool" "$WORK/tree/app/build/kernel"
printf '{}\n' >"$WORK/tree/app/.dart_tool/package_config.json"
printf '{}\n' >"$WORK/tree/app/build/kernel/prebuilt.json"
printf '// a new lint\n' >"$WORK/tree/app/test/tool/zz_new_lint_test.dart"
printf '// an app file\n' >"$WORK/tree/app/lib/zz_prequeue.dart"
git -C "$WORK/tree" add -f -A
git -C "$WORK/tree" -c user.name=t -c user.email=t@example.com commit -qm 'wip(x): app'
# shellcheck disable=SC2016 # the stub logs its own arguments
printf '%s\n' '#!/bin/sh' 'echo "$@" >>"$FLUTTER_LOG"' >"$WORK/stub/flutter"
chmod +x "$WORK/stub/flutter"
export FLUTTER_LOG="$WORK/flutter.log"
: >"$FLUTTER_LOG"
(cd "$WORK/tree" && PATH="$WORK/stub:$PATH" PREQUEUE_ONLY='app guard tests' PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 \
  PREQUEUE_BASE=$BASE PREQUEUE_OTHERS='' bash "$REPO_ROOT/tools/prequeue.sh" >/dev/null 2>&1)
for guard in root_isolate_lint_test.dart single_writer_lint_test.dart paint_lint_test.dart deletion_lint_test.dart \
  zz_new_lint_test.dart; do
  grep -q "test/tool/$guard" "$FLUTTER_LOG" && ok "the app guard tests run $guard" ||
    fail "the app guard tests leave out $guard: $(cat "$FLUTTER_LOG")"
done

# --- a branch behind its base is run merged with it, as the queue's tree is: two additions that pass alone and not together
git worktree add -q --detach "$WORK/tree2" "$BASE" || fail "cannot add a second worktree"
T2="git -C $WORK/tree2 -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null"
$T2 switch -q --detach "$BASE"
sed -i '/^Run before every commit\./i A note which the base adds at this place, long enough to be a real line, from the second side.' \
  "$WORK/tree2/AGENTS.md"
$T2 commit -q -am 'docs(x): base side'
SIDE=$($T2 rev-parse HEAD)
$T2 switch -q --detach "$BASE"
sed -i '/^Run before every commit\./i A note which the branch adds at this place, long enough to be a real line, from the first side.' \
  "$WORK/tree2/AGENTS.md"
$T2 commit -q -am 'docs(x): branch side'
MERGED=$(cd "$WORK/tree2" && PREQUEUE_ONLY='merged with' PREQUEUE_FAST_TESTS=merge_union PREQUEUE_NO_FETCH=1 PREQUEUE_NO_GH=1 \
  PREQUEUE_BASE=$SIDE PREQUEUE_OTHERS='' bash "$REPO_ROOT/tools/prequeue.sh" --full 2>&1)
STATUS=$?
[[ $STATUS -eq 1 && $MERGED == *"FAIL merged with"* && $MERGED == *"do not queue"* ]] &&
  ok "a branch whose merge with its base fails a test is a FAIL" || fail "the merge with the base: exit $STATUS: $MERGED"
git worktree remove --force "$WORK/tree2" >/dev/null 2>&1

# --- --list prints the steps of each tier and runs nothing
capture prequeue --list --quick
expect_result "--list --quick lists the quick steps" 0 "commitlint" "catches:"
capture prequeue --list
expect_result "--list lists the default steps" 0 "dart analyzer vs baseline" "cargo check" "cargo machete" "cargo deny" \
  "migrations" "dart licences" "node licences"
capture prequeue --list --full
expect_result "--list --full lists the full steps" 0 "fresh clone" "combined with queued PRs" "clippy ratchet" "merged with"
[[ $OUT != *"perf instructions"* ]] && ok "--full does not list the opt-in perf step" || fail "--full lists perf without --perf"
capture prequeue --list --full --perf
expect_result "--list --full --perf lists the perf step" 0 "perf instructions"
capture prequeue --list --quick
[[ $OUT != *"fresh clone"* && $OUT != *"dart analyzer"* ]] && ok "--quick lists no default or full step" ||
  fail "--quick lists steps of a larger tier"
capture prequeue --nonsense
expect_result "an unknown flag is a usage error" failure "usage: tools/prequeue.sh"

finish
