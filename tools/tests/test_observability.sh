#!/usr/bin/env bash
# The monitoring bundle (deploy/observability): compose wiring, Grafana provisioning, the dashboard and the alert rules
# with their unit tests; the checks live in check_observability.py.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool curl
require_tool docker
docker compose version >/dev/null 2>&1 || { echo "FAIL: the docker compose plugin is required" >&2; exit 1; }

python3 "$REPO_ROOT/tools/tests/check_observability.py"
