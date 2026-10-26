#!/usr/bin/env bash
# Runs buf: the one on PATH, else the release pinned below, installed from npm by tools/npm_tool.sh. The gate and CI
# both go through this, so every run uses the same buf. Bump BUF_VERSION and tools/codegen.sh together.
set -euo pipefail

BUF_VERSION=1.74.0

exec bash "$(dirname "${BASH_SOURCE[0]}")/npm_tool.sh" buf "@bufbuild/buf@$BUF_VERSION" "$@"
