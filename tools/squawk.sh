#!/usr/bin/env bash
# Runs squawk, the PostgreSQL migration linter: the one on PATH, else the release pinned below, installed from npm by
# tools/npm_tool.sh. tools/migrations.sh goes through this, so the gate and CI use the same squawk.
set -euo pipefail

SQUAWK_VERSION=2.70.0

exec bash "$(dirname "${BASH_SOURCE[0]}")/npm_tool.sh" squawk "squawk-cli@$SQUAWK_VERSION" "$@"
