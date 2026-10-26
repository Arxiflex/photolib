#!/usr/bin/env bash
# Runs a tool pinned by tools/buf.sh or tools/squawk.sh: the one on PATH, else the npm release installed once into a
# per-user cache keyed by its version. An install, or a cached one, that does not start or reports another version
# (a stub a test left in a shared cache) is installed again.
#
#   tools/npm_tool.sh <command> <package>@<version> [arguments...]
set -euo pipefail

NAME=$1 PACKAGE=$2
shift 2
if command -v "$NAME" >/dev/null 2>&1; then
  exec "$NAME" "$@"
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "'$NAME' is required: install $NAME, or npm so that this script can fetch $PACKAGE" >&2
  exit 1
fi

# The cache sits outside the checkout, which may be on a noexec mount where the native binary cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
VERSION=${PACKAGE##*@}
INSTALL=$CACHE/$NAME-$VERSION
BIN=$INSTALL/node_modules/.bin/$NAME

pinned() { # pinned <bin>: it starts and its --version names $VERSION whole (1.2.34 is no 1.2.3)
  local out
  out=$("$1" --version 2>&1) && [[ " $out " == *[!0-9.]"$VERSION"[!0-9.]* ]]
}

if ! pinned "$BIN"; then
  (umask 077 && mkdir -p "$CACHE")
  if [[ ! -O $CACHE ]]; then
    echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  # Each install goes into a directory of its own, published by renaming a link to it over $INSTALL: a gate on a cold
  # cache never deletes or writes into another's install, half-done or running. Downloads fail now and then; npm even
  # exits 0 when it could not fetch the optional platform binary.
  for attempt in 1 2 3; do
    STAGE=$(mktemp -d "$INSTALL.XXXXXX")
    if npm install --prefix "$STAGE" --ignore-scripts --no-audit --no-fund --loglevel=error "$PACKAGE" >&2 &&
      pinned "$STAGE/node_modules/.bin/$NAME"; then
      if pinned "$BIN"; then
        rm -rf "$STAGE" # another gate published one meanwhile
      else
        # An earlier npm_tool.sh installed into $INSTALL itself, which no rename replaces.
        [[ -L $INSTALL || ! -e $INSTALL ]] || rm -rf "$INSTALL"
        ln -s "${STAGE##*/}" "$STAGE.link"
        # rename(2), which replaces a link where mv would move into the directory it names
        node -e 'require("fs").renameSync(process.argv[1], process.argv[2])' "$STAGE.link" "$INSTALL"
      fi
      break
    fi
    rm -rf "$STAGE"
    if ((attempt == 3)); then
      echo "3 installs of $NAME into $INSTALL failed or cannot run $VERSION (a failed download, or a noexec mount?);" \
        "set PHOTOLIB_TOOLS_CACHE to a directory where programs can run" >&2
      exit 1
    fi
  done
fi

exec "$BIN" "$@"
