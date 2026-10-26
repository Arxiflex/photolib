#!/usr/bin/env bash
# The Helm chart (deploy/helm/photolib), rendered and linted by the pinned Helm (tools/helm.sh); check_helm.py.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool curl
python3 "$REPO_ROOT/tools/tests/check_helm.py"
