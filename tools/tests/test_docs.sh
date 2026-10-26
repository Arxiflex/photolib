#!/usr/bin/env bash
# Documentation site (M0-05): the MkDocs config, the section guides and a build that fails on a broken link or anchor.
# The gate builds the real site itself (tools/docs.sh); this test pins what that build cannot know.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

assert_file mkdocs.yml
assert_file tools/docs.sh
assert_file tools/docs-requirements.txt
assert_patterns assert_matches mkdocs.yml \
  '^site_name: Photolib$' "names the site" \
  '^strict: true$' "fails the build on any warning"
assert_matches tools/docs-requirements.txt '^mkdocs==[0-9.]+$' "pins MkDocs"

for section in user admin dev adr; do
  assert_file "docs/$section/README.md"
  assert_matches mkdocs.yml "^  - .*: $section/README\.md$" "has $section/ in the navigation"
done

# --- the design documents and the design's ADRs stay only in the design repository (owner, design#262): no copies
# here. ADR-0013 is this repository's own licence decision (M0-02), not a copy.
[[ -e docs/design ]] && fail "docs/design/ copies the design documents" || ok "the design documents are not copied"
for number in $(seq -f '%04g' 1 12) 0014 0015 0016; do
  compgen -G "docs/adr/$number-*.md" >/dev/null && fail "ADR-$number is copied from the design repository" ||
    ok "ADR-$number is not copied"
done
assert_matches docs/adr/0017-documentation-site.md '^\* \*\*Status\*\*: Accepted' "ADR-0017 is accepted"
# design#286: the owner confirmed that only the copies left; the ADRs recorded here stay here
assert_prose docs/adr/0017-documentation-site.md 'confirmed[^.]*design#286' "cites the owner's confirmation (design#286)"

# --- publishing: this repository's one pipeline (ci.yml) builds the site in the gate's docs part, with the gate's
# command; no workflow deploys it
assert_matches tools/check.sh 'step \. bash tools/docs\.sh' "the gate builds the site with tools/docs.sh"
if grep -lqs 'actions/deploy-pages@' .github/workflows/*.yml; then fail "a workflow deploys the site"; else
  ok "no workflow deploys the site"
fi

# --- strictness: a copy of the site with a broken link or anchor must not build (mkdocs --quiet would hide it)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/tools" "$REPO_ROOT/.cache"
cp -R docs mkdocs.yml "$SANDBOX/"
cp tools/docs.sh tools/docs-requirements.txt "$SANDBOX/tools/"
ln -s "$REPO_ROOT/.cache" "$SANDBOX/.cache"

BUILT=$SANDBOX/built
bash "$SANDBOX/tools/docs.sh" "$BUILT" >/dev/null 2>&1 && ok "the site builds" || fail "the site does not build"

# --- wide tables (the scenario ADRs', the threat model's) scroll in the content column, not past its right edge
page=$BUILT/dev/threat-model/index.html
table_rules=$(grep -o '<link href="[^"]*\.css" rel="stylesheet">' "$page" | cut -d'"' -f2 | while read -r href; do
  tr '\n' ' ' <"$(dirname "$page")/$href"
  echo
done | grep -Eo '(^|[};/])[[:space:]]*table[[:space:]]*\{[^}]*')
if [[ $table_rules =~ display:[[:space:]]*block && $table_rules =~ overflow-x:[[:space:]]*auto ]]; then
  ok "a wide table scrolls sideways inside the content column"
else fail "no stylesheet the threat model's page links makes a table a block that scrolls sideways"; fi

# --- readers' browsers fetch nothing from third parties (ADR-0017): nothing a page loads comes from another host
fetched=$(grep -rEoh --include='*.html' '<(script|img|iframe|source|link)[^>]* (src|href)="(https?:)?//[^"]*"[^>]*>' \
  "$BUILT" | grep -v 'rel="canonical"' | sort -u)
fetched+=$(grep -rEoh --include='*.css' 'url\(["'\'']?(https?:)?//[^)]*\)|@import[^;]*' "$BUILT" | sort -u)
[[ -z $fetched ]] && ok "the site loads nothing from another host" || fail "the site loads from other hosts: $fetched"

# expect_build_fails <description> <markdown line appended to the home page> <text the failure must show>
expect_build_fails() {
  local description=$1 markdown=$2 word=$3 out
  printf '\n%s\n' "$markdown" >>"$SANDBOX/docs/README.md"
  if out=$(bash "$SANDBOX/tools/docs.sh" "$SANDBOX/site" 2>&1); then fail "$description: the build passed"
  elif [[ $out == *"$word"* ]]; then ok "$description"
  else fail "$description: the build failed without mentioning '$word': $out"; fi
  cp "$REPO_ROOT/docs/README.md" "$SANDBOX/docs/README.md"
}

expect_build_fails "a broken link fails the build" "[x](nope.md)" "nope.md"
expect_build_fails "a broken heading anchor fails the build" "[x](user/README.md#nope)" "#nope"

finish
