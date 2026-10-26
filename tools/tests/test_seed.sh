#!/usr/bin/env bash
# Dev seed data (testdata/seed) and its loader (tools/dev/seed.py); the checks live in check_seed.py.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3

python3 "$REPO_ROOT/tools/tests/check_seed.py"
