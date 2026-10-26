#!/usr/bin/env bash
# Runs Playwright's CLI: the one on PATH, else the release pinned below, installed from npm by tools/npm_tool.sh. The web
# part's journey (tools/web_e2e) loads the library from the same install (`--dir` prints where) and fetches its Firefox
# and WebKit with `bash tools/playwright.sh install firefox`.
set -euo pipefail

PLAYWRIGHT_VERSION=1.64.1

here=$(dirname "${BASH_SOURCE[0]}")
if [[ ${1:-} == --dir ]]; then
  bash "$here/npm_tool.sh" playwright "playwright@$PLAYWRIGHT_VERSION" --version >/dev/null
  echo "${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}/playwright-$PLAYWRIGHT_VERSION/node_modules/playwright"
  exit 0
fi
exec bash "$here/npm_tool.sh" playwright "playwright@$PLAYWRIGHT_VERSION" "$@"
