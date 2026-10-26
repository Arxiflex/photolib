#!/usr/bin/env bash
# tools/commitlint.sh enforces the Conventional Commits policy from AGENTS.md.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git

LINT="$REPO_ROOT/tools/commitlint.sh"
[[ -f $LINT ]] || fail "tools/commitlint.sh does not exist"

# lint_message <message>: exit status of the linter on a message given on stdin
lint_message() { printf '%s' "$1" | bash "$LINT" --stdin >/dev/null 2>&1; }
lint_output() { printf '%s' "$1" | bash "$LINT" --stdin 2>&1; }

accepts() {
  if lint_message "$2"; then ok "accepts: $1"; else fail "should accept: $1 -> $(lint_output "$2")"; fi
}
rejects() {
  if lint_message "$2"; then fail "should reject: $1"; else ok "rejects: $1"; fi
}

for type in feat fix docs style refactor perf test build ci chore revert; do
  accepts "type $type" "$type: do the thing"
done
accepts "a scope" "fix(server): handle empty uploads"
accepts "a scope with dots, slashes and digits" "build(deps/rust-1.2): bump tokio"
accepts "a breaking-change marker" "feat(kernel)!: change the envelope header"
accepts "a body and trailers" $'feat(app): add the timeline\n\nBecause the gallery needs it.\n\nRefs: example/design#2\n'
accepts "a trailing newline" $'chore: tidy\n'
accepts "a 72-character subject" "feat: $(printf 'x%.0s' $(seq 1 66))"
accepts "a merge commit" "Merge branch 'main' into wi/2-x"

rejects "an empty message" ""
rejects "no type" "add the thing"
rejects "a capitalised type" "Feat: add the thing"
rejects "an unknown type" "feature: add the thing"
rejects "a missing space after the colon" "feat:add the thing"
rejects "an empty description" "feat: "
rejects "an empty scope" "feat(): add the thing"
rejects "an uppercase scope" "feat(Server): add the thing"
rejects "a 73-character subject" "feat: $(printf 'x%.0s' $(seq 1 67))"
rejects "a trailing period" "feat: add the thing."
rejects "a body glued to the subject" $'feat: add the thing\nbody right below'
rejects "a fixup commit" "fixup! feat: add the thing"
rejects "a leading blank line" $'\nfeat: add the thing'

# the error names the rule that was broken
output=$(lint_output "Add the thing")
[[ "$output" == *"Conventional Commits"* ]] && ok "the error explains the policy" || fail "unhelpful error: $output"
output=$(lint_output "feat: $(printf 'x%.0s' $(seq 1 67))")
[[ "$output" == *"72"* ]] && ok "the length error names the limit" || fail "length error does not mention 72: $output"

# --- file mode strips comment lines like git does
msgfile=$(mktemp)
trap 'rm -rf "$msgfile" "${WORK:-}"' EXIT
printf '# comment first\nfix: real subject\n' >"$msgfile"
bash "$LINT" --file "$msgfile" >/dev/null 2>&1 && ok "file mode skips leading comment lines" || fail "file mode rejected a message with a leading comment"
printf 'nonsense\n' >"$msgfile"
bash "$LINT" --file "$msgfile" >/dev/null 2>&1 && fail "file mode accepted nonsense" || ok "file mode rejects nonsense"
bash "$LINT" --file /nonexistent/msg >/dev/null 2>&1 && fail "a missing message file must fail" || ok "a missing message file fails"

# --- range mode lints every commit in a range
WORK=$(mktemp -d)
git_in() { git -C "$WORK" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
git_in init -q -b main
git_in commit -q --allow-empty -m "chore: root"
git_in commit -q --allow-empty -m "feat: a good commit"
git_in commit -q --allow-empty -m "Bad commit message"
git_in commit -q --allow-empty -m "fix: another good one"
bad_sha=$(git_in rev-parse --short HEAD~1)

output=$(cd "$WORK" && bash "$LINT" HEAD~3..HEAD 2>&1)
status=$?
[[ $status -ne 0 ]] && ok "a range with a bad commit fails" || fail "a range with a bad commit passed"
[[ "$output" == *"$bad_sha"* ]] && ok "the bad commit is named by its hash" || fail "output does not name $bad_sha: $output"
[[ "$output" != *"another good one"* ]] && ok "good commits are not reported" || fail "good commits were reported: $output"

(cd "$WORK" && bash "$LINT" HEAD~3..HEAD~2 >/dev/null 2>&1) && ok "a range of good commits passes" || fail "a good range failed"
(cd "$WORK" && bash "$LINT" HEAD..HEAD >/dev/null 2>&1) && ok "an empty range passes" || fail "an empty range failed"
(cd "$WORK" && bash "$LINT" no-such-ref..HEAD >/dev/null 2>&1) && fail "an invalid range must fail, not pass silently" || ok "an invalid range fails"

git_in checkout -q -b side HEAD~3
git_in commit -q --allow-empty -m "feat: on the side"
git_in checkout -q main
git_in merge -q --no-ff side -m "integrate the side branch" >/dev/null 2>&1
(cd "$WORK" && bash "$LINT" HEAD~1..HEAD >/dev/null 2>&1) && ok "merge commits in a range are skipped" || fail "a merge commit failed the range"

bash "$LINT" >/dev/null 2>&1 && fail "no arguments must be a usage error" || ok "no arguments is a usage error"

finish
