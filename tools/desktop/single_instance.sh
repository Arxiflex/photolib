#!/usr/bin/env bash
# One Photolib over the store (ADR-0206): starts the Linux app <first>, a profile build as a release build seals its
# log, on a display of its own with tools/perf/keyring.sh's session bus and unlocked keyring, then <second>, another
# start of the app, with a photo, and again with a password setup link (ADR-0243). Each must hand it to the first and
# end at once, the first take it as a drop, which its log shows, and stay up. Needs xvfb-run.
#
#   bash tools/desktop/single_instance.sh <first> <second>
set -euo pipefail
(($# == 2)) || { echo "usage: single_instance.sh <first> <second>" >&2; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
touch "$tmp/a.jpg"
# shellcheck disable=SC2016 # the inner shell expands them
bash "$(dirname "${BASH_SOURCE[0]}")/../perf/keyring.sh" xvfb-run -a bash -c '
  fail() { echo "single_instance.sh: $1" >&2; exit 1; }
  # logged <text> <tries>: the first start logged a line with <text>, polled every 0.2 s while it runs, and looked for
  # once more after it ended, as it may log and end between a look and the check.
  logged() {
    for ((i = 0; i < $2; i++)); do
      kill -0 "$first" 2>/dev/null && runs=1 || runs=
      grep -qsF "$1" "$XDG_DATA_HOME/org.photolib.photolib/logs/photolib.log" && return
      [[ $runs ]] || break
      sleep 0.2
    done
    fail "the first start never logged $1"
  }
  "$1" &
  first=$!
  trap "kill $first 2>/dev/null" EXIT
  logged "\"message\":\"starting\"" 600
  timeout 10 "$2" "$3" || fail "the second start did not end at once (exit $?)"
  logged "\"message\":\"dropped\"" 50
  timeout 10 "$2" "$4" || fail "the start with a link did not end at once (exit $?)"
  logged "\"links\":1" 50
  kill -0 "$first" 2>/dev/null || fail "the first start ended"
' single_instance "$1" "$2" "$tmp/a.jpg" \
  "photolib:/password-setup?handle=ann&token=t&server=https%3A%2F%2Fphotos.example.org%2F"
