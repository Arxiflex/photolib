#!/usr/bin/env bash
# A Flutter bump requires the upgrade checklist, except when introducing the pin.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3 git
cd "$REPO_ROOT" || exit 1

TEMPLATE=.github/PULL_REQUEST_TEMPLATE/flutter-upgrade.md
GATE="$REPO_ROOT/tools/flutter_upgrade_gate.py"
assert_file "$TEMPLATE"
assert_matches "$TEMPLATE" '^- \[ \] .*low-end Android' "the template has the low-end Android device gate"
assert_matches "$TEMPLATE" '^- \[ \] .*panorama.*video.*HDR' "the template has the panorama, video and HDR gate"
assert_matches "$TEMPLATE" '^- \[ \] .*beta' "the template has the beta channel gate"
[[ $(grep -c '^- \[ \] ' "$TEMPLATE") -eq 6 ]] && ok "the template lists the six gates" || fail "the template does not list six gates"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP/repo"
cd "$TMP/repo" || exit 1
git config user.email t@example.com
git config user.name t
mkdir -p app .github/PULL_REQUEST_TEMPLATE
cp "$REPO_ROOT/$TEMPLATE" "$TEMPLATE"
echo one >app/other.txt
git add -A && git commit -qm unpinned
UNPINNED=$(git rev-parse HEAD)
echo '{"flutter": "3.47.7"}' >app/.fvmrc
git add -A && git commit -qm base
BASE=$(git rev-parse HEAD)

echo '{"flutter": "3.47.8"}' >app/.fvmrc
git commit -qam bump
BUMP=$(git rev-parse HEAD)
echo two >app/other.txt
git commit -qam other
OTHER=$(git rev-parse HEAD)

ALL_TICKED=$(sed 's/^- \[ \]/- [x]/' "$TEMPLATE")

gate() {
  PR_BODY=$3 capture python3 "$GATE" "$1" "$2"
}

gate "$BASE" "$BUMP" "$ALL_TICKED"
expect_result "a bump with every gate ticked passes" 0

gate "$BASE" "$BUMP" ""
expect_result "a bump with an empty description fails and names the gates" 1 "3.47.8" "low-end Android"

gate "$BASE" "$BUMP" "$(sed 's/^- \[ \]/- [x]/; /panorama/s/\[x\]/[ ]/' "$TEMPLATE")"
[[ $STATUS -eq 1 && $OUT == *"panorama"* && $OUT != *"low-end Android"* ]] \
  && ok "one unticked gate fails and only that gate is named" || fail "one unticked: exit $STATUS $OUT"

gate "$BASE" "$BUMP" "$(sed 's/^- \[ \]/- [X]/' "$TEMPLATE")"
expect_result "a capital X ticks a gate too" 0

gate "$BASE" "$BUMP" "$(sed 's/^- \[ \]/- [x]/; s/beta/alpha/' "$TEMPLATE")"
expect_result "reworded gates do not count" 1

gate "$BUMP" "$OTHER" ""
expect_result "a change that leaves the pin alone needs no gates" 0 unchanged

gate "$UNPINNED" "$BASE" ""
expect_result "introducing the pin is not an upgrade" 0 "3.47.7"

git checkout -q -b stale "$BASE" && echo three >app/other.txt && git commit -qam stale
gate "$BUMP" "$(git rev-parse HEAD)" ""
expect_result "a branch behind a bump on main needs no gates" 0
git checkout -q -

git rm -q app/.fvmrc && git commit -qm drop
gate "$BUMP" "$(git rev-parse HEAD)" ""
expect_result "removing the pin fails" 1

capture python3 "$GATE"
expect_result "missing arguments are a usage error" 2

finish
