#!/usr/bin/env bash
# Builds the documentation site (default: ./site) with the MkDocs pinned in tools/docs-requirements.txt, installed
# into a cached virtualenv. The gate and the publish workflow both run this, so CI publishes what the gate checked.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REQUIREMENTS=$ROOT/tools/docs-requirements.txt
VENV=$ROOT/.cache/docs-venv
PYTHON=$VENV/bin/python # run through python: the checkout may sit on a noexec mount, where venv scripts cannot start

if ! cmp -s "$REQUIREMENTS" "$VENV/requirements.txt"; then
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$PYTHON" -m pip install --quiet --disable-pip-version-check -r "$REQUIREMENTS"
  cp "$REQUIREMENTS" "$VENV/requirements.txt"
fi

"$PYTHON" -m mkdocs build --config-file "$ROOT/mkdocs.yml" --site-dir "${1:-$ROOT/site}"
