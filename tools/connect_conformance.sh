#!/usr/bin/env bash
# Runs the official Connect conformance suite (github.com/connectrpc/conformance, pinned below) against the server
# crate in <dir>, for the subset its connect-conformance.yaml declares. The runner is downloaded once into the
# per-user tools cache by tools/fetch_release.sh, which checks the pinned SHA-256.
#
#   tools/connect_conformance.sh server/crates/photolib-conformance
set -euo pipefail

VERSION=v1.0.6
declare -A SHA256=(
  [Linux-x86_64]=803a9ed1778583f9b98f44b4b77ab06897d1027183ef2064de32a0fb7d688ab0
  [Darwin-x86_64]=0920c4612593301fd7cfdee6256bfaf3232dc5e21aeda1a9b2e6bcc6be806458
  [Darwin-arm64]=b736e0ea69447ed663ba9298894faa75b0ff6dbd5e0c9acb63bedde46b1f7d8a
)

if [[ $# -ne 1 || ! -f $1/connect-conformance.yaml ]]; then
  echo "usage: tools/connect_conformance.sh <crate directory holding connect-conformance.yaml>" >&2
  exit 2
fi
DIR=$1
PLATFORM=$(uname -s)-$(uname -m)
PINNED=${SHA256[$PLATFORM]:-}
if [[ -z $PINNED ]]; then
  echo "the Connect conformance runner $VERSION has no release for $PLATFORM" >&2
  exit 1
fi

# Outside the checkout, which may be on a noexec mount where the runner cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
RUNNER=$CACHE/connectconformance-$VERSION/connectconformance
if [[ ! -x $RUNNER ]]; then
  (umask 077 && mkdir -p "$CACHE")
  if [[ ! -O $CACHE ]]; then
    echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  bash "$(dirname "${BASH_SOURCE[0]}")/fetch_release.sh" \
    "https://github.com/connectrpc/conformance/releases/download/$VERSION/connectconformance-$VERSION-$PLATFORM.tar.gz" \
    "$PINNED" "${RUNNER%/*}" connectconformance
fi

SERVER=$(cargo build --locked --quiet --manifest-path "$DIR/Cargo.toml" --bins --message-format=json |
  sed -n 's/.*"executable":"\([^"]*\)".*/\1/p' | tail -1)

# The runner's HTTP trace (request> and response< lines) of every case that fails, when this release has --trace: a
# case that fails once in a run (a timing case) is then diagnosable from the log of its final attempt.
TRACE=()
if "$RUNNER" --help 2>&1 | grep -q -- '--trace'; then TRACE=(--trace); fi
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
STATUS=0
"$RUNNER" --mode server --conf "$DIR/connect-conformance.yaml" ${TRACE[@]+"${TRACE[@]}"} -- "$SERVER" 2>&1 |
  tee "$LOG" || STATUS=${PIPESTATUS[0]}
if ((STATUS != 0)); then
  # Each failure starts with a `FAILED:` banner and the case's full name; its error and trace lines follow it.
  FAILED=$(sed -n 's/^[[:space:]]*FAILED:[[:space:]]*//p' "$LOG")
  echo "connect_conformance.sh: the runner exited $STATUS; failed cases: $(grep -c . <<<"$FAILED")" >&2
  [[ -z $FAILED ]] || echo "  ${FAILED//$'\n'/$'\n'  }" >&2
  exit "$STATUS"
fi
