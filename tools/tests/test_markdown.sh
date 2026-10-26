#!/usr/bin/env bash
# Markdown lint (a stdlib subset of markdownlint, so the gate needs no npm): every Markdown file we would commit
# passes mdlint.py, and mdlint.py flags each rule it claims to enforce.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool git
cd "$REPO_ROOT" || exit 1

LINT="$REPO_ROOT/tools/tests/mdlint.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

lint() {
  printf '%s' "$1" >"$TMP/sample.md"
  capture python3 "$LINT" "$TMP/sample.md"
}

flags() {
  local description=$1 rule=$2 text=$3
  lint "$text"
  expect_result "flags $description" failure "$rule"
}

lint $'# Title\n\nText.\n\n## Section\n\n```sh\nls\n```\n\n| a | b |\n|---|---|\n'
expect_result "accepts a clean document" 0
lint "$(printf '# Title\n\n```text\n%0125d\n```\n\n| %0125d |\n\n[%0125d](x)\n' 0 0 0)"
expect_result "accepts long lines in code, tables and unbreakable links" 0

flags "a line over 120 characters" MD013 "$(printf '# Title\n\n%s\n' "$(printf 'word %.0s' {1..40})")"
flags "a heading that skips a level" MD001 $'# Title\n\n### Skipped\n'
flags "a document that does not start with a title" MD041 $'Text first.\n\n# Title\n'
flags "a second top-level heading" MD025 $'# Title\n\n# Another\n'
flags "a heading without a blank line after it" MD022 $'# Title\nText.\n'
flags "a heading without a blank line before it" MD022 $'# Title\n\nText.\n## Section\n'
flags "two blank lines in a row" MD012 $'# Title\n\n\nText.\n'
flags "a code fence without a language" MD040 $'# Title\n\n```\nls\n```\n'
flags "an unclosed code fence" MD031 $'# Title\n\n```sh\nls\n'
flags "a code fence without a blank line before it" MD031 $'# Title\n\nText.\n```sh\nls\n```\n'

# --- the repository's own Markdown, except the PR templates (form bodies, not documents with a title)
files=()
while IFS= read -r -d '' file; do [[ -f $file ]] && files+=("$file"); done \
  < <(git ls-files -z --cached --others --exclude-standard -- '*.md' ':(exclude).github/PULL_REQUEST_TEMPLATE')
if python3 "$LINT" "${files[@]}"; then ok "${#files[@]} Markdown files pass"; else fail "Markdown lint found problems"; fi

finish
