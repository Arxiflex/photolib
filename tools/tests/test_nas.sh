#!/usr/bin/env bash
# The NAS catalogs' entries (deploy/nas): check_nas.py, through `docker compose config` (no daemon).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool docker
docker compose version >/dev/null 2>&1 || { echo "FAIL: the docker compose plugin is required" >&2; exit 1; }
python3 "$REPO_ROOT/tools/tests/check_nas.py"
