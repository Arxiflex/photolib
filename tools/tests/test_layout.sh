#!/usr/bin/env bash
# Repository layout (design docs: 03-architecture §9): the agreed top-level folders exist, each with a short
# architecture README, and nothing else sits at the top level.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
cd "$REPO_ROOT" || exit 1

FOLDERS=(proto kernel server app viewer deploy docs tools testdata)
MAX_README_LINES=60

for folder in "${FOLDERS[@]}"; do
  readme="$folder/README.md"
  assert_file "$readme"
  [[ -f $readme ]] || continue
  first_line=$(head -n1 "$readme")
  [[ "$first_line" == "# "* ]] && ok "$readme starts with a title" || fail "$readme must start with a '# ' title"
  assert_patterns assert_matches "$readme" \
    '^## Architecture$' "has an Architecture section" \
    '^## Contents$' "has a Contents section" \
    "^## Design$" "has a Design section"
  if sed -n '/^## Design$/,$p' "$readme" | grep -q '^\* '; then
    ok "$readme names the design document it implements"
  else
    fail "$readme names no design document under Design"
  fi
  lines=$(wc -l <"$readme")
  if [[ $lines -le $MAX_README_LINES && $lines -ge 8 ]]; then ok "$readme is short ($lines lines)"; else
    fail "$readme has $lines lines; want 8 to $MAX_README_LINES"
  fi
done

# --- nothing else at the top level: any unexpected directory would be an undecided layout change
unexpected=$(git ls-files -z --cached --others --exclude-standard | tr '\0' '\n' | grep / | cut -d/ -f1 | sort -u |
  grep -vxF -e .github "${FOLDERS[@]/#/-e}" || true)
if [[ -z $unexpected ]]; then ok "only the agreed top-level folders exist"; else
  fail "unexpected top-level folders: $(echo "$unexpected" | tr '\n' ' ')"
fi

# --- the root README maps every folder
for folder in "${FOLDERS[@]}"; do
  assert_matches README.md "\]\(${folder}/" "links to $folder/"
done

# --- the conventions file for agents exists and names the gate
assert_file AGENTS.md
assert_matches AGENTS.md 'bash tools/check\.sh' "documents the quality gate command"

finish
