#!/usr/bin/env bash
# ADR-0215 (M1-36, photolib-design#495), as check_tile_marks_adr.py reads it: the survey of 15 galleries' tile marks,
# every cell sourced and every product's grid screenshot beside the ADR, the counted complaints, a proposal whose
# decisions each name an alternative, a reason and a screenshot, the mock-ups, the hand-off task, and that the owner
# accepted it (photolib-design#590).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

CHECK=tools/tests/check_tile_marks_adr.py
ADR=docs/adr/0215-tile-kind-marks.md
capture python3 "$CHECK"
expect_result "ADR-0215 is complete" 0

# the check itself must notice a cell without a source, a missing screenshot and a decision without its alternative
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/docs" && cp -R docs/adr "$SANDBOX/docs/adr"
sed -i -E '0,/^\| Piwigo \|/s/^(\| Piwigo \| [^|]*\| )[^|]*\|/\1no mark |/' "$SANDBOX/$ADR"
rm "$SANDBOX/docs/adr/assets/0215/aves.jpg"
sed -i -E '/^#+ Hide threshold/,/^#+ Setting/s/Alternative/Other option/' "$SANDBOX/$ADR"
capture python3 "$CHECK" "$SANDBOX"
expect_result "a cell without a source is reported" failure "Piwigo: no value or source in ['live or motion']"
expect_result "a missing screenshot is reported" failure "FAIL: assets/0215/aves.jpg exists"
expect_result "a decision without its alternative is reported" failure "the decision 'Hide threshold' lacks"

finish
