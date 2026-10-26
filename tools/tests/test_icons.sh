#!/usr/bin/env bash
# The app icon on every platform (ADR-0312): check_icons.py.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
python3 "$REPO_ROOT/tools/tests/check_icons.py" || fail "check_icons.py reported failures"
finish
