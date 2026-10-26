#!/usr/bin/env bash
# Contributor files (issue #2: README, AGENTS.md, conventional-commits policy).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

for file in README.md AGENTS.md; do assert_file "$file"; done

assert_patterns assert_prose README.md \
  '^# Photolib' "titled Photolib" \
  'pre-alpha|not yet usable|early development' "is honest about the project stage" \
  'bash tools/check\.sh' "shows how to run the quality gate" \
  '\]\(AGENTS\.md#commits\)' "links the commit conventions" \
  'design repository' "mentions the design repository" \
  'licen[cs]ed under[^.]*AGPL-3\.0-only' "states the licence"

assert_patterns assert_prose AGENTS.md \
  '## Commits' "has a Commits section" \
  'Conventional Commits' "adopts Conventional Commits" \
  'type\(scope\): summary' "shows the commit subject shape" \
  'tools/commitlint\.sh' "names the commit message checker" \
  'BREAKING CHANGE' "explains how breaking changes are marked" \
  'bash tools/check\.sh' "tells contributors to run the quality gate" \
  '## Merging' "has a Merging section" \
  'auto-merge once[^.]*`bash tools/check\.sh`[^.]*passes' "merges once the gate passes" \
  'no human review' "needs no human review" \
  'Developer Certificate of Origin' "states the contribution terms"

# CI runs the same gate on the merge queue's branches, every job through the lane action (check_ci.py pins the rest)
assert_prose .github/actions/lane/action.yml 'bash tools/check\.sh' "runs the quality gate"
assert_prose AGENTS.md 'never push to `main`' "tells agents not to push to main"

finish
