#!/usr/bin/env bash
# Developer environment files at the repository root: git hooks (.pre-commit-config.yaml) and the dev container
# (.devcontainer.json); the checks live in check_devenv.py. Where pre-commit is installed it also validates the config.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3

python3 "$REPO_ROOT/tools/tests/check_devenv.py" || FAILURES=$((FAILURES + 1))

if command -v pre-commit >/dev/null 2>&1; then
  cd "$REPO_ROOT" || exit 1
  check "pre-commit accepts .pre-commit-config.yaml" pre-commit validate-config .pre-commit-config.yaml
else
  echo "skip: 'pre-commit' is not on PATH, so the hook config was only checked structurally"
fi

finish
