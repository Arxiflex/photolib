#!/usr/bin/env bash
# AGENTS.md and tools/README.md, which most items add to, merge as a union of lines (.gitattributes,
# photolib-design#546): two branches' additions both land without a conflict. A union of two edits of one line keeps
# both versions, which check_union.py fails on.
# shellcheck disable=SC2016 # sed scripts are literal
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
require_tool python3
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

FILES=(AGENTS.md tools/README.md)
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null "$@"; }
mkdir -p "$REPO/tools"
for file in .gitattributes "${FILES[@]}"; do cp "$REPO_ROOT/$file" "$REPO/$file"; done
g init -q -b main && g add -A && g commit -qm base

# branch <name> <sed script>: a branch off main that edits both files with the script.
branch() {
  g checkout -q -b "$1" main
  for file in "${FILES[@]}"; do sed -i "$2" "$REPO/$file"; done
  g commit -qam "$1"
}

FIRST='A paragraph that the first branch appends, long enough to be a real note.'
SECOND='Another note, which a second branch appends to the same place at the same time.'
branch ours "\$a\\\n$FIRST"
branch theirs "\$a\\\n$SECOND"
if g rebase -q ours >/dev/null 2>&1; then
  ok "two branches that each append a paragraph to ${FILES[*]} rebase onto each other without a conflict"
  # The blank line both add lands once, so the two paragraphs join: whole, the rebased one last.
  for file in "${FILES[@]}"; do
    [[ $(tail -n 3 "$REPO/$file") == $'\n'"$FIRST"$'\n'"$SECOND" ]] && ok "$file ends with both, rebased one last" ||
      fail "$file does not end with both paragraphs: $(tail -n 4 "$REPO/$file")"
  done
  check "a union of two additions passes check_union.py" python3 "$REPO_ROOT/tools/tests/check_union.py" \
    "${FILES[@]/#/$REPO/}"
else
  fail "two branches that append to ${FILES[*]} conflict: $(g status --short | head -5)"
  g rebase --abort
fi

branch one '3s/$/ One branch ends this line so./'
branch two '3s/$/ Another branch ends it otherwise./'
g rebase -q one >/dev/null 2>&1 || fail "two edits of one line conflict instead of merging as a union"
capture python3 "$REPO_ROOT/tools/tests/check_union.py" "${FILES[@]/#/$REPO/}"
expect_result "check_union.py fails on both versions of a line that a union of two edits leaves" failure \
  "$REPO/AGENTS.md:3 and 4" "$REPO/tools/README.md:3 and 4"

cd "$REPO_ROOT" || exit 1
check "${FILES[*]} hold no line twice, in two versions" python3 tools/tests/check_union.py "${FILES[@]}"

# One section per area, in a stable order, so that items' notes land in different places (a new area: here too).
AREAS='The quality gate|CI|Crypto formats|Layout|Documentation|Development environment|Kernel|Android|Photo editor|'\
'Local database|Lint|Tests|On-device ML|API clients|Background work|Logging and diagnostics|Thumbnails|Photo viewer|'\
'Downloads|Desktop integration|Video editing|iOS: PhotoKit and backup|Server (Rust)|Deployment|Folders and albums|'\
'Commits|Merging|Safety'
[[ $(sed -n 's/^## //p' AGENTS.md | paste -sd '|') == "$AREAS" ]] && ok "AGENTS.md has a section per area, in order" ||
  fail "AGENTS.md's sections are not one per area in this order: $AREAS"
assert_prose AGENTS.md 'new lines at the end of its area.s section[^.]*new area[^.]*before .Commits' \
  "AGENTS.md says where an item adds its notes"
assert_prose AGENTS.md 'never re-wrap or move lines[^.]*union of lines' "AGENTS.md says why lines stay where they are"
finish
