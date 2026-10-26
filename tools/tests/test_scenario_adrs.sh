#!/usr/bin/env bash
# The scenario ADRs (M2-45: ADR-0200, M2-46: ADR-0201, M3-22: ADR-0202), as check_scenario_adrs.py reads them:
# competitors compared with sources, the invariants, over 120 scenarios from named dimensions, each row complete and
# checked against the invariants, every row in a numbered proposal for the owner, the design changes after sign-off,
# and once the owner answered, Accepted with the answers' caveats, a proposal left open still to confirm.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

CHECK=tools/tests/check_scenario_adrs.py
capture python3 "$CHECK"
expect_result "the scenario ADRs are complete" 0

# ADR-0200's proposal 6 leaves ADR-0092 as it is, which the owner kept (photolib-design#668).
DEDUP=docs/adr/0092-per-user-deduplication.md
assert_prose "$DEDUP" '\* \*\*Status\*\*: Accepted — 2026-10-23[^*]*photolib-design#668' \
  "ADR-0092 is Accepted, as the owner kept it (#668)"
assert_matches docs/adr/README.md '\(0092-per-user-deduplication\.md\) \| [^|]* \| Accepted' \
  "the index lists ADR-0092 as Accepted"

# the check itself must notice a raw placeholder, a row no proposal covers and a row checked against no invariant
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/docs" && cp -R docs/adr "$SANDBOX/docs/adr"
sed -i -E '/^## Proposals for sign-off/,/^## /s/\(rows? [^)]*\)//' "$SANDBOX/docs/adr/0200-device-and-server-copies.md"
sed -i -E '0,/^\| B1 \|/s/^(\| B1 \|.*\| )I[0-9 ,I]+ \|$/\1— |/' "$SANDBOX/docs/adr/0200-device-and-server-copies.md"
sed -i 's/verified on .home server.\./verified on <server>./' "$SANDBOX/docs/adr/0200-device-and-server-copies.md"
sed -i 's/open, owner to confirm/accepted/' "$SANDBOX/docs/adr/0201-sources.md"
capture python3 "$CHECK" "$SANDBOX"
expect_result "a placeholder Markdown would swallow is reported" failure "has raw tags ['<server>']"
expect_result "a row in no proposal is reported" failure "0200-device-and-server-copies.md: rows in no proposal"
expect_result "a row checked against no invariant is reported" failure \
  "0200-device-and-server-copies.md row B1 is checked against no or unknown invariants"
expect_result "a proposal the owner left open, marked accepted, is reported" failure \
  "0201-sources.md's proposal 6 stays open, owner to confirm"

finish
