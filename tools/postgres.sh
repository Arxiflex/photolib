#!/usr/bin/env bash
# Prints the directory of PostgreSQL <major>'s programs (initdb, pg_ctl, postgres, pg_dump, pg_restore, psql) that the
# major-upgrade test runs (photolib-server's upgrade.rs): PGDG's Ubuntu 24.04 packages pinned below, with the libpq, ICU
# and liburing they load, so that they run on other distributions too, downloaded once into the per-user tools cache,
# checked against their SHA-256 and extracted. Each program there is a wrapper that finds those libraries. Without a
# major it fetches every pinned one, as the gate's prefetch does.
#
#   tools/postgres.sh [<major>]
set -euo pipefail

PGDG=https://apt-archive.postgresql.org/pub/repos/apt/pool/main/p
LIBPQ="$PGDG/postgresql-18/libpq5_18.6-1.pgdg24.04%2B2 b487c5ed2ceb9244c6a9d6ae65818ed6707c3c44a2e14488394ae4194c52c53b f593f74119682ffc9b4b114d63c224ceeefa2795e703bb1c7ed2ddb4bd62afe3
UBUNTU/pool/main/i/icu/libicu74_74.2-1ubuntu3 d29c97a21a3e3254731cfac186e4d4e611e5e67d2c9a0430f6acfbd9acaefa2e 041df33ab32c57287a62ba141890a82512bf092854be455259c8034ab7ae9fbc"
# <url without _<arch>.deb> <SHA-256 amd64> <SHA-256 arm64>, one package a line
declare -A PACKAGES=(
  [17]="$PGDG/postgresql-17/postgresql-17_17.11-1.pgdg24.04%2B2 d5b58058a82a3f344f832aea2cc54badc4f6265c25c960752cb1f5df5d2180ee 4f70a5f9101cab17348f40e4534ea96f9e70b8bb4e44a2b4c8b314e3dee2aca7
$PGDG/postgresql-17/postgresql-client-17_17.11-1.pgdg24.04%2B2 b3b071b67a814a382516d6f6241b529c52f909672457e2f48083acce047b634f 07d62cc509748510bb8e862fbe58d1050e99fb1d457f09036f04253d9995aba7
$LIBPQ"
  [18]="$PGDG/postgresql-18/postgresql-18_18.6-1.pgdg24.04%2B2 c0773357df8769abb70e92722196d9b53422d71c0f29a4f39c834b94276cfa3d d7ad4dbdef31fdf1cc820613a3b4bd5a24d5787d64be16d4a6a94c405aa5f674
$PGDG/postgresql-18/postgresql-client-18_18.6-1.pgdg24.04%2B2 b9d10d99a73bf7aa375be2fe36626c40499cfdf553d0ad174674a88a1b256b43 4786cea6affc7190d97b9686ecaa733c994f6c39f7681f4fe4396e09f0ab1fb7
$LIBPQ
UBUNTU/pool/main/libu/liburing/liburing2_2.5-1build1 c2aef62accee92a06263c3ad4ef46132c13e409b54296c44792a20491830a7b0 eb386221b1c7a1480c0abdbc8ddb989297a362e3768e4fb541df06757b37929d"
)

if [[ $# == 0 ]]; then
  for major in "${!PACKAGES[@]}"; do "$0" "$major" >/dev/null; done
  exit
fi
MAJOR=$1
case $(uname -sm) in
  "Linux x86_64") ARCH=amd64 COLUMN=2 UBUNTU=https://archive.ubuntu.com/ubuntu ;;
  "Linux aarch64") ARCH=arm64 COLUMN=3 UBUNTU=https://ports.ubuntu.com/ubuntu-ports ;;
  *) ARCH= ;;
esac
if [[ -z ${PACKAGES[$MAJOR]:-} || -z $ARCH ]]; then
  echo "usage: tools/postgres.sh <$(echo "${!PACKAGES[@]}" | tr ' ' '|')>, on Linux x86-64 or arm64" >&2
  exit 2
fi
# Outside the checkout, which may be on a noexec mount where PostgreSQL cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
DIR=$CACHE/postgresql-$MAJOR-$(sha256sum <<<"${PACKAGES[$MAJOR]}" | cut -c1-12)
if [[ ! -x $DIR/bin/postgres ]]; then
  if [[ -n ${EGRESS_BLOCKED:-} ]]; then
    echo "PostgreSQL $MAJOR is not in $CACHE, and egress is blocked (tools/offline.sh);" \
      "fetch it first: bash tools/postgres.sh $MAJOR" >&2
    exit 1
  fi
  for tool in curl dpkg-deb; do
    command -v $tool >/dev/null 2>&1 || { echo "'$tool' is required to fetch PostgreSQL $MAJOR" >&2; exit 1; }
  done
  (umask 077 && mkdir -p "$CACHE")
  # Extracted beside the result, then renamed into place: a gate fetching it at once never runs half of it.
  STAGE=$(mktemp -d "$CACHE/.postgresql.XXXXXX")
  trap 'rm -rf "$STAGE"' EXIT
  # shellcheck source=retry.sh
  source "$(dirname "${BASH_SOURCE[0]}")/retry.sh"
  while read -r url amd64 arm64; do
    url=${url/UBUNTU/$UBUNTU}_$ARCH.deb pinned=$amd64
    [[ $COLUMN == 2 ]] || pinned=$arm64
    download "$url" "$STAGE/package.deb" "$pinned" || exit 1
    dpkg-deb -x "$STAGE/package.deb" "$STAGE/root"
  done <<<"${PACKAGES[$MAJOR]}"
  mkdir "$STAGE/bin"
  for tool in initdb pg_ctl postgres pg_dump pg_restore psql; do
    # shellcheck disable=SC2016 # the wrapper expands LD_LIBRARY_PATH and $@ when it runs
    printf '#!/bin/sh\nLD_LIBRARY_PATH="%s"${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} exec "%s" "$@"\n' \
      "$DIR/root/usr/lib/$(uname -m)-linux-gnu" "$DIR/root/usr/lib/postgresql/$MAJOR/bin/$tool" >"$STAGE/bin/$tool"
    chmod 755 "$STAGE/bin/$tool"
  done
  rm -rf "$DIR" "$STAGE/package.deb"
  mv "$STAGE" "$DIR"
fi
echo "$DIR/bin"
