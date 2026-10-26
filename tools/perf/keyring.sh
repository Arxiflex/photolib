#!/usr/bin/env bash
# Runs a command where the Linux app opens its store without a passphrase (ADR-0154) on a box without a desktop
# session: in a D-Bus session of its own with a throwaway GNOME Keyring, unlocked. The keyring, the app's data
# (XDG_DATA_HOME) and the runtime files live in a temporary directory, deleted after; the daemon is stopped before.
#
#   tools/perf/keyring.sh <command> [arguments...]
set -euo pipefail

for tool in dbus-run-session gnome-keyring-daemon; do
  command -v "$tool" >/dev/null || {
    echo "'$tool' is required to run the Linux app without a desktop session (Debian: dbus, gnome-keyring)" >&2
    exit 1
  }
done
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
mkdir -m 700 "$home/run"
mkfifo "$home/ready"
# In the foreground the daemon is this session's job, its output not the caller's, and it closes its stdout once it
# owns the Secret Service: a request before that would start another by D-Bus activation, which outlives the session.
# shellcheck disable=SC2016 # expanded by the session's shell
XDG_DATA_HOME=$home XDG_RUNTIME_DIR=$home/run dbus-run-session -- bash -c '
  printf photolib | gnome-keyring-daemon --foreground --unlock --components=secrets \
    >"$XDG_DATA_HOME/ready" 2>"$XDG_DATA_HOME/keyring.log" &
  trap "kill $! && wait $!" EXIT
  cat "$XDG_DATA_HOME/ready" >/dev/null
  kill -0 $! 2>/dev/null || { cat "$XDG_DATA_HOME/keyring.log" >&2; exit 1; }
  "$@"' keyring "$@"
