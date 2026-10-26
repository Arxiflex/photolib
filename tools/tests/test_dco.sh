#!/usr/bin/env bash
# tools/dco.sh requires a Developer Certificate of Origin sign-off on every commit of a branch; the gate's `commits`
# part runs it (test_check_sh.sh).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
cd "$REPO_ROOT" || exit 1

DCO="$REPO_ROOT/tools/dco.sh"
[[ -f $DCO ]] || fail "tools/dco.sh does not exist"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git_in() { git -C "$WORK" -c user.name=Ann -c user.email=ann@example.invalid -c commit.gpgsign=false "$@"; }
# commit <message> [author-email] [committer-email]: an empty commit by Ann, optionally with other emails.
commit() {
  GIT_AUTHOR_NAME=Ann GIT_AUTHOR_EMAIL=${2:-ann@example.invalid} \
    GIT_COMMITTER_NAME=Ann GIT_COMMITTER_EMAIL=${3:-${2:-ann@example.invalid}} \
    git_in commit -q --allow-empty -m "$1"
}
# run_dco <range>: run the checker on the range in the sandbox repository; output in $OUT, exit status in $STATUS
run_dco() {
  OUT=$(cd "$WORK" && bash "$DCO" "$1" 2>&1)
  STATUS=$?
}
# accepts / rejects <description> <range> [exit status]: a rejection is exit 1; exit 2 is a usage or git error
accepts() {
  run_dco "$2"
  if [[ $STATUS -eq 0 ]]; then ok "accepts: $1"; else fail "should accept: $1 -> $OUT"; fi
}
rejects() {
  run_dco "$2"
  if [[ $STATUS -eq ${3:-1} ]]; then ok "rejects: $1"; else fail "should reject with status ${3:-1}: $1 -> $STATUS $OUT"; fi
}

git_in init -q -b main
commit "chore: root"

commit $'feat: signed\n\nSigned-off-by: Ann <ann@example.invalid>'
accepts "a sign-off by the author" HEAD~1..HEAD

commit $'feat: trailers around it\n\nBody.\n\nRefs: example/design#3\nSigned-off-by: Ann <ann@example.invalid>\nCo-authored-by: Bot <bot@example.invalid>'
accepts "a sign-off among other trailers" HEAD~1..HEAD

commit $'feat: rebased\n\nSigned-off-by: Ann <ann@example.invalid>' ann@example.invalid maintainer@example.invalid
accepts "a sign-off by the author after a rebase changed the committer" HEAD~1..HEAD

commit $'feat: merged by a maintainer\n\nSigned-off-by: Maria <Maria@Example.invalid>' ann@example.invalid maria@example.invalid
accepts "a sign-off by the committer, compared without regard to case" HEAD~1..HEAD

commit "feat: unsigned"
bad_sha=$(git_in rev-parse --short HEAD)
rejects "a commit without a sign-off" HEAD~1..HEAD
[[ "$OUT" == *"$bad_sha"* ]] && ok "the unsigned commit is named by its hash" || fail "output does not name $bad_sha: $OUT"
[[ "$OUT" == *"git commit -s"* && "$OUT" == *"DCO"* ]] && ok "the error says how to sign off" || fail "unhelpful error: $OUT"

commit $'feat: someone else\n\nSigned-off-by: Eve <eve@example.invalid>'
rejects "a sign-off by neither the author nor the committer" HEAD~1..HEAD

commit $'feat: no address\n\nSigned-off-by: Ann'
rejects "a sign-off without an email address" HEAD~1..HEAD

commit $'feat: no name\n\nSigned-off-by: <ann@example.invalid>'
rejects "a sign-off without a name" HEAD~1..HEAD

commit $'feat: prose, not a trailer\n\nSigned-off-by: Ann <ann@example.invalid>\n\nMore text after it.'
rejects "a sign-off that is not in the trailer block" HEAD~1..HEAD

commit $'feat: good one\n\nSigned-off-by: Ann <ann@example.invalid>'
commit "feat: last one is bad"
rejects "a range where only an older commit is signed" HEAD~2..HEAD
accepts "a range that stops before the unsigned commit" HEAD~2..HEAD~1

accepts "an empty range" HEAD..HEAD
rejects "an invalid range, instead of passing silently" no-such-ref..HEAD 2
bash "$DCO" >/dev/null 2>&1 && fail "no arguments must be a usage error" || ok "no arguments is a usage error"

git_in checkout -q -b side HEAD~2
commit $'feat: on the side\n\nSigned-off-by: Ann <ann@example.invalid>'
git_in checkout -q main
git_in merge -q --no-ff side -m "integrate the side branch" >/dev/null 2>&1
accepts "a merge commit without a sign-off is skipped" HEAD~1..HEAD

# dependency-update bots (Renovate) cannot certify anything, so their GitHub bot accounts are exempt
commit "chore(deps): update a crate" 29139614+renovate[bot]@users.noreply.github.com
accepts "an unsigned commit by a GitHub bot account" HEAD~1..HEAD
commit "chore: a person pretending" renovate[bot]@example.invalid
rejects "an unsigned commit whose address only looks like a bot's" HEAD~1..HEAD
commit "chore: a person pretending" x@users.noreply.github.com
rejects "an unsigned commit by a user at the GitHub noreply domain" HEAD~1..HEAD

# --- contributors can find out what to do
assert_file DCO
assert_prose DCO 'Developer.s Certificate of Origin 1\.1' "DCO holds the Developer Certificate of Origin 1.1"
assert_patterns assert_prose AGENTS.md \
  'git commit -s' "AGENTS.md shows how to sign off" \
  'tools/dco\.sh origin/dev\.\.HEAD' "AGENTS.md shows how to check sign-offs" \
  'bot accounts? (are|is) exempt' "AGENTS.md says dependency-update bots are exempt"

finish
