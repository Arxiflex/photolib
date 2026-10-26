#!/usr/bin/env bash
# ADR index (M0-05): every ADR is listed in docs/adr/README.md with the status its own file states, and the template
# follows the layout ADR-0001 prescribes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

# index_problems <adr-dir>: one line per ADR that the index omits or lists with another status.
index_problems() {
  local dir=$1 file name row status shown
  [[ -f $dir/README.md ]] || { echo "missing $dir/README.md"; return; }
  compgen -G "$dir/[0-9][0-9][0-9][0-9]-*.md" >/dev/null || { echo "no ADRs in $dir"; return; }
  for file in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
    name=${file##*/}
    row=$(grep -F "]($name)" "$dir/README.md" | head -1)
    if [[ -z $row ]]; then echo "$name is not in the index"; continue; fi
    status=$(sed -nE 's/^\* \*\*Status\*\*: \**([A-Za-z]+).*/\1/p' "$file" | head -1)
    read -r shown _ <<<"$(cut -d'|' -f4 <<<"$row" | tr -cd 'A-Za-z ')"
    [[ -n $status && ${status,,} == "${shown,,}" ]] || echo "$name: the file says '$status', the index says '$shown'"
  done
}

problems=$(index_problems docs/adr)
if [[ -z $problems ]]; then ok "every ADR is in the index with the status its file states"; else fail "$problems"; fi

# the check itself must notice an omitted ADR and a wrong status
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cp -R docs/adr "$SANDBOX/omitted" && sed -i '/(0017-/d' "$SANDBOX/omitted/README.md"
cp -R docs/adr "$SANDBOX/wrong" && sed -i '/(0017-/s/Accepted/Proposed/' "$SANDBOX/wrong/README.md"
[[ $(index_problems "$SANDBOX/omitted") == *"0017-documentation-site.md is not in the index"* ]] &&
  ok "an omitted ADR is reported" || fail "an ADR missing from the index is not reported"
[[ $(index_problems "$SANDBOX/wrong") == *"0017-"*"the index says 'Proposed'"* ]] && ok "a wrong status is reported" ||
  fail "an index status that differs from the file is not reported"

# dangling <root>: each ADR the docs and AGENTS.md of <root> cite that is neither the design repository's (0001 to 0016)
# nor a file of <root>/docs/adr.
dangling() {
  local root=$1 ref
  grep -rhoE 'ADR-[0-9]{4}' --include='*.md' "$root/docs" "$root/AGENTS.md" | sort -u | while read -r ref; do
    ((10#${ref#ADR-} <= 16)) || compgen -G "$root/docs/adr/${ref#ADR-}-*.md" >/dev/null || echo "$ref"
  done
}

cited=$(dangling .)
if [[ -z $cited ]]; then ok "every ADR the docs cite exists"; else fail "the docs cite ADRs that do not exist: $cited"; fi
mkdir -p "$SANDBOX/cites/docs"
cp -R docs/adr "$SANDBOX/cites/docs/" && printf 'Mitigated (ADR-0999); see ADR-0005.\n' >"$SANDBOX/cites/AGENTS.md"
[[ $(dangling "$SANDBOX/cites") == ADR-0999 ]] && ok "a citation of a missing ADR is reported" ||
  fail "a citation of a missing ADR is not reported"

# --- the template carries the layout of ADR-0001
assert_file docs/adr/template.md
assert_patterns assert_matches docs/adr/template.md \
  '^# ADR-NNNN — ' "has the title line" \
  '^\* \*\*Status\*\*: ' "has a status line" \
  '^\* \*\*Requirements\*\*: ' "has a requirements line"
for heading in Context Decision Consequences "Options considered"; do
  assert_matches docs/adr/template.md "^## $heading\$" "has a '$heading' section"
done
assert_matches docs/adr/README.md '\]\(template\.md\)' "the index links the template"

finish
