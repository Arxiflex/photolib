#!/usr/bin/env bash
# tools/android_sdk.sh installs Android SDK packages (the NDK, a system image) and fetches a broken download once more.
# The sdkmanager here is a stub that installs a package by writing its package.xml, as the real one does last, or
# breaks the download the way CI saw: a partial package, a partial download in .temp that a later run resumes, exit 0.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
NDK='ndk;28.2.13676358'
IMAGE='system-images;android-34;default;x86_64'

# new_sdk: an empty SDK with the stub sdkmanager; its first $BROKEN downloads (default 0) break
new_sdk() {
  export ANDROID_HOME=$SANDBOX/sdk-$RANDOM
  mkdir -p "$ANDROID_HOME/cmdline-tools/latest/bin"
  cat >"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" <<'EOF'
#!/bin/bash
echo "sdkmanager $*" >>"$ANDROID_HOME/calls.log"
dir=$ANDROID_HOME/${2//;//}
mkdir -p "$dir" "$ANDROID_HOME/.temp"
if [[ -e $ANDROID_HOME/.temp/download || $(wc -l <"$ANDROID_HOME/calls.log") -le ${BROKEN:-0} ]]; then
  : >"$dir/part"
  : >"$ANDROID_HOME/.temp/download"
  echo "Warning: An error occurred while preparing SDK package: Error on ZipFile unknown archive" >&2
  exit 0
fi
: >"$dir/package.xml"
EOF
  chmod +x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  : >"$ANDROID_HOME/calls.log"
}

installed() { [[ -f $ANDROID_HOME/${1//;//}/package.xml ]]; }
downloads() { wc -l <"$ANDROID_HOME/calls.log"; }
run() { capture bash "$REPO_ROOT/tools/android_sdk.sh" "$@"; }

new_sdk
run "$NDK" "$IMAGE"
[[ $STATUS -eq 0 && $(downloads) -eq 2 ]] && installed "$NDK" && installed "$IMAGE" &&
  ok "installs each package with one download" || fail "install: exit $STATUS, $(downloads) downloads: $OUT"

run "$NDK" "$IMAGE"
[[ $STATUS -eq 0 && $(downloads) -eq 2 ]] &&
  ok "downloads nothing for packages already installed (or restored from a cache)" ||
  fail "installed packages: exit $STATUS, $(downloads) downloads: $OUT"

new_sdk
BROKEN=1 run "$NDK"
[[ $STATUS -eq 0 && $(downloads) -eq 2 && ! -e $ANDROID_HOME/ndk/28.2.13676358/part ]] && installed "$NDK" &&
  ok "fetches a broken download once more, from scratch, though sdkmanager exited 0" ||
  fail "broken download: exit $STATUS, $(downloads) downloads: $OUT"

new_sdk
mkdir -p "$ANDROID_HOME/ndk/28.2.13676358"
: >"$ANDROID_HOME/ndk/28.2.13676358/part"
run "$NDK"
[[ $STATUS -eq 0 && $(downloads) -eq 1 && ! -e $ANDROID_HOME/ndk/28.2.13676358/part ]] && installed "$NDK" &&
  ok "replaces a partial package left by an earlier run" ||
  fail "partial package: exit $STATUS, $(downloads) downloads: $OUT"

new_sdk
BROKEN=2 run "$NDK" "$IMAGE"
expect_result "fails after two broken downloads and names the package" failure "$NDK is not installed"
[[ $(downloads) -eq 2 ]] && ! installed "$IMAGE" && ok "and stops there" ||
  fail "after two broken downloads: $(<"$ANDROID_HOME/calls.log")"

new_sdk
run ''
expect_result "refuses an empty package name" failure usage
[[ -x $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager ]] && ok "and removes nothing" || fail "'' removed the SDK"

ANDROID_HOME='' run "$NDK"
expect_result "fails loudly without ANDROID_HOME" failure ANDROID_HOME

# --- the download policy is documented where contributors and agents look
assert_prose AGENTS.md 'downloaded tool is checked[^.]*fetched once more[^.]*keyed by its version.{0,200}android_sdk\.sh' \
  "AGENTS.md says downloaded tools are checked, fetched once more and cached by version"
assert_prose tools/README.md 'npm_tool\.sh.*android_sdk\.sh' "tools/README.md names npm_tool.sh and android_sdk.sh"

finish
