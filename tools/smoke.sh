#!/usr/bin/env bash
# Runs the integration smoke test (app/integration_test) on one target: bash tools/smoke.sh <target>
# Targets: linux web android ios macos windows. The weekly workflow runs every target; the runner prepares the rest
# (display server, emulator, simulator). Locally, `bash tools/smoke.sh linux` needs xvfb-run and the Linux toolchain;
# web writes the replica's sqlite3mc.wasm and drift worker into app/web first (tools/data/web.sh); linux builds
# tools/desktop/xdnd.c (cc, libX11) for the drag-and-drop test. Until a kernel release is pinned, each target first
# builds the kernel the app bundles (ADR-0057), which needs Rust; linux runs on a session bus of its own with an
# unlocked Secret Service (dbus-run-session, gnome-keyring), the store's keystore. Each desktop then builds its package
# (tools/package.sh): an AppImage it starts, a DMG, an MSIX. android, ios, macos and windows then hold the corpus' 360°
# videos to their golden frames (app/integration_test/playback_probe.dart), served from here, as FFmpeg makes them.
set -euo pipefail

target=${1:-}
cd "$(dirname "${BASH_SOURCE[0]}")/../app"
smoke=(flutter test integration_test)
arch=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
kernel() { "$(command -v python3 || command -v python)" ../tools/kernel/build.py --out build/kernel "$@"; }
# spheres <device arguments...>: the 360° golden-frame test where FFmpeg does not run: the twins and goldens are made
# here (test/features/viewer/sphere_golden_test.dart) and served on port 8360, which an emulator reaches by adb reverse.
spheres() {
  local twins server status=0
  twins=$(mktemp -d)
  "$(command -v python3 || command -v python)" -m http.server 8360 --bind 127.0.0.1 --directory "$twins" \
    >/dev/null 2>&1 &
  server=$!
  SPHERE_TWINS_OUT=$twins flutter test test/features/viewer/sphere_golden_test.dart
  [[ $target != android ]] || adb reverse tcp:8360 tcp:8360
  flutter test integration_test/playback_probe.dart --plain-name 'every corpus 360° video plays projected' \
    --dart-define=SPHERE_TWINS=http://127.0.0.1:8360 "$@" || status=$?
  kill "$server" 2>/dev/null || true
  rm -rf "$twins"
  return "$status"
}

case "$target" in
  linux)
    kernel "linux-$arch"
    # The other X11 client of the drag-and-drop test, a file manager's windows (ADR-0144).
    mkdir -p build
    cc -O2 -o build/xdnd ../tools/desktop/xdnd.c -lX11 -ldl
    # shellcheck disable=SC2016
    XDND=$PWD/build/xdnd dbus-run-session -- bash -c 'printf photolib | gnome-keyring-daemon --unlock --components=secrets >/dev/null &&
      exec "$@"' keyring xvfb-run -a "${smoke[@]}" -d linux
    bash ../tools/package.sh appimage
    ;;
  macos) kernel "macos-$arch" && "${smoke[@]}" -d macos && spheres -d macos && bash ../tools/package.sh dmg ;;
  windows) kernel windows-x64 && "${smoke[@]}" -d windows && spheres -d windows && bash ../tools/package.sh msix ;;
  android)
    ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}} kernel android-x64
    "${smoke[@]}" --flavor play -d emulator-5554
    spheres --flavor play -d emulator-5554
    ;;
  ios)
    kernel "ios-sim-$arch"
    udid=$(xcrun simctl list devices available | sed -n 's/^ *iPhone.* (\([0-9A-F-]\{36\}\)) (.*/\1/p' | head -n 1)
    xcrun simctl bootstatus "$udid" -b
    # The PhotoKit test indexes the simulator's library, which then holds a photo at least.
    xcrun simctl privacy "$udid" grant photos org.photolib.photolib
    xcrun simctl addmedia "$udid" ../testdata/seed/travel/harbour.jpg
    "${smoke[@]}" -d "$udid"
    spheres -d "$udid"
    ;;
  web)
    bash ../tools/data/web.sh web
    bash ../tools/kernel/wasm.sh web/kernel
    # Port 0: chromedriver binds a free port and reports it once it listens; flutter drive does not wait for it.
    log=$(mktemp)
    chromedriver --port=0 >"$log" &
    driver=$!
    trap 'cat "$log"; rm -f "$log"; kill "$driver"' EXIT
    for _ in {1..300}; do
      port=$(sed -n 's/.*started successfully on port \([0-9][0-9]*\).*/\1/p' "$log")
      [[ -z $port ]] && kill -0 "$driver" 2>/dev/null || break
      sleep 0.1
    done
    [[ $port ]] || { echo "smoke.sh: chromedriver is not listening" >&2; exit 1; }
    flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
      -d web-server --browser-name=chrome --headless --driver-port="$port"
    ;;
  "") echo "usage: smoke.sh <linux|web|android|ios|macos|windows>" >&2; exit 2 ;;
  *) echo "smoke.sh: unknown target '$target'; usage: smoke.sh <linux|web|android|ios|macos|windows>" >&2; exit 2 ;;
esac
