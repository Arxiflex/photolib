#!/usr/bin/env bash
# tools/smoke.sh runs the integration smoke test (app/integration_test) on one of the six targets. The Flutter and
# platform tools are stubs here; the real run on every target is the twice-daily smoke job.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
for tool in flutter chromedriver xcrun python3 cc adb; do
  cat >"$TMP/bin/$tool" <<'STUB'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$CALLS"
case "$(basename "$0")" in
  flutter)
    # The 360° probe reads the twins' server, which starts in the background: it waits for it, as the real one must.
    if [[ $* == *SPHERE_TWINS* ]]; then
      for _ in {1..100}; do grep -qF 'python3 -m http.server' "$CALLS" && break; sleep 0.1; done
    fi
    echo "in $(basename "$PWD") ${XDND:+XDND=$XDND}" >>"$CALLS"; exit "${FLUTTER_EXIT:-0}" ;;
  chromedriver)
    # Like the real one with --port=0: it reports the free port it picked once it listens there, a moment later.
    [[ -z ${CHROMEDRIVER_EXIT:-} ]] || exit "$CHROMEDRIVER_EXIT"
    echo "Starting ChromeDriver 155.0 on port ${1#--port=}"
    sleep 0.5
    port=$((RANDOM + 10000))
    echo "chromedriver listening on $port" >>"$CALLS"
    echo "ChromeDriver was started successfully on port $port."
    exec sleep 30 ;;
  python3) echo "in $(basename "$PWD")" >>"$CALLS" ;;
  xcrun) if [[ $2 == list ]]; then printf '== Devices ==\n-- iOS 18.2 --\n    iPad (A16) (AAAAAAAA-1111-2222-3333-444444444444) (Shutdown)\n    iPhone 16 (1A2B3C4D-1111-2222-3333-444455556666) (Shutdown)\n'; fi ;;
esac
STUB
  chmod +x "$TMP/bin/$tool"
done
printf '#!/usr/bin/env bash\necho "xvfb-run $*" >>"$CALLS"\nshift\nexec "$@"\n' >"$TMP/bin/xvfb-run"
printf '#!/usr/bin/env bash\necho "dbus-run-session $*" >>"$CALLS"\nshift\nexec "$@"\n' >"$TMP/bin/dbus-run-session"
printf '#!/usr/bin/env bash\necho "gnome-keyring-daemon $* <$(cat)>" >>"$CALLS"\n' >"$TMP/bin/gnome-keyring-daemon"
chmod +x "$TMP/bin/xvfb-run" "$TMP/bin/dbus-run-session" "$TMP/bin/gnome-keyring-daemon"

# A copy of the script in a checkout whose tools/data/web.sh and tools/kernel/wasm.sh only log.
mkdir -p "$TMP/repo/tools/data" "$TMP/repo/tools/kernel" "$TMP/repo/app"
cp tools/smoke.sh "$TMP/repo/tools/"
printf '#!/usr/bin/env bash\necho "web.sh $* in $(basename "$PWD")" >>"$CALLS"\n' >"$TMP/repo/tools/data/web.sh"
printf '#!/usr/bin/env bash\necho "wasm.sh $* in $(basename "$PWD")" >>"$CALLS"\n' >"$TMP/repo/tools/kernel/wasm.sh"
# shellcheck disable=SC2016 # the stub expands $* when it runs
printf '#!/usr/bin/env bash\necho "package.sh $* in $(basename "$PWD")" >>"$CALLS"\n' >"$TMP/repo/tools/package.sh"

# smoke <args...>: status in $STATUS, every tool call in $LOG.
smoke() {
  export CALLS="$TMP/calls"
  : >"$CALLS"
  PATH="$TMP/bin:$PATH" bash "$TMP/repo/tools/smoke.sh" "$@" >"$TMP/out" 2>&1
  STATUS=$?
  LOG=$(<"$CALLS")
}

calls() {
  local target=$1 expected=$2
  smoke "$target"
  [[ $STATUS -eq 0 && $LOG == *"$expected"* ]] && ok "$target runs: $expected" \
    || fail "$target does not run '$expected' (exit $STATUS): $LOG $(<"$TMP/out")"
}

calls linux "xvfb-run -a flutter test integration_test -d linux"
calls macos "flutter test integration_test -d macos"
calls windows "flutter test integration_test -d windows"
# Each desktop then builds its package, unsigned (ADR-0154).
for target in linux:appimage macos:dmg windows:msix; do
  calls "${target%%:*}" "package.sh ${target#*:} in app"
  [[ $LOG == *"flutter test"*"package.sh"* ]] && ok "${target%%:*} packages after its smoke test" ||
    fail "${target%%:*} does not package after its smoke test: $LOG"
done
calls android "flutter test integration_test --flavor play -d emulator-5554"
calls web "flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d web-server --browser-name=chrome --headless"
calls web "chromedriver --port=0"
[[ $LOG == *"chromedriver listening"*"flutter drive"* ]] && ok "web waits until chromedriver listens before it drives" ||
  fail "web drives before chromedriver listens: $LOG"
port=$(sed -n 's/^chromedriver listening on //p' <<<"$LOG")
[[ $LOG == *"flutter drive "*" --driver-port=$port"$'\n'* ]] && ok "web drives through the port chromedriver picked" ||
  fail "web does not drive through chromedriver's port $port: $LOG"
calls web "web.sh web in app"
[[ $LOG == *"web.sh web"*"flutter drive"* ]] && ok "web writes the replica's assets into app/web before building" ||
  fail "web does not write the replica's assets before building: $LOG"
calls ios "xcrun simctl bootstatus 1A2B3C4D-1111-2222-3333-444455556666 -b"
calls ios "flutter test integration_test -d 1A2B3C4D-1111-2222-3333-444455556666"
calls ios "xcrun simctl privacy 1A2B3C4D-1111-2222-3333-444455556666 grant photos org.photolib.photolib"
calls ios "xcrun simctl addmedia 1A2B3C4D-1111-2222-3333-444455556666 ../testdata/seed/travel/harbour.jpg"
[[ $LOG == *"addmedia"*"flutter test"* ]] && ok "ios fills the simulator's library before the smoke test" ||
  fail "ios does not fill the simulator's library before the smoke test: $LOG"

smoke linux
[[ $LOG == *"in app"* ]] && ok "the test runs inside app/" || fail "the test does not run inside app/: $LOG"

# Until a kernel release is pinned, each target builds the kernel its build hook bundles (ADR-0057).
arch=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
for target in linux:linux-$arch macos:macos-$arch windows:windows-x64 android:android-x64 ios:ios-sim-$arch; do
  calls "${target%%:*}" "python3 ../tools/kernel/build.py --out build/kernel ${target#*:}"
  [[ $LOG == *"build/kernel"*"flutter "* ]] && ok "${target%%:*} builds the kernel before the app" ||
    fail "${target%%:*} does not build the kernel before the app: $LOG"
done
calls web "wasm.sh web/kernel in app"
[[ $LOG == *"wasm.sh"*"flutter drive"* ]] && ok "web builds the kernel's module before the app" ||
  fail "web does not build the kernel's module before the app: $LOG"
calls linux "gnome-keyring-daemon --unlock --components=secrets"
[[ $LOG == *"dbus-run-session"*"gnome-keyring-daemon"*"xvfb-run"* ]] &&
  ok "linux runs with an unlocked Secret Service on its own session bus" ||
  fail "linux does not run with a Secret Service: $LOG"

# The drag-and-drop test's other X11 client, built before the app (ADR-0144).
calls linux "cc -O2 -o build/xdnd ../tools/desktop/xdnd.c -lX11 -ldl"
[[ $LOG == *"cc "*"flutter test"*"XDND=$TMP/repo/app/build/xdnd"* ]] &&
  ok "linux hands the drag-and-drop test its other X11 client" || fail "linux does not build tools/desktop/xdnd.c: $LOG"

smoke ios
[[ $LOG != *AAAAAAAA* ]] && ok "ios picks an iPhone simulator" || fail "ios picked the iPad: $LOG"

FLUTTER_EXIT=1 smoke linux
[[ $STATUS -ne 0 ]] && ok "a failing smoke test fails the script" || fail "a failing smoke test passed"

FLUTTER_EXIT=1 smoke web
[[ $STATUS -ne 0 ]] && ok "a failing web smoke test fails the script" || fail "a failing web smoke test passed"

CHROMEDRIVER_EXIT=1 smoke web
[[ $STATUS -ne 0 && $LOG != *"flutter drive"* ]] && ok "web fails without driving when chromedriver does not start" ||
  fail "web went on without chromedriver (exit $STATUS): $LOG"

# The 360° golden-frame test on the targets where FFmpeg does not run: the twins and goldens are made here and served
# to the target, an emulator's localhost reaching here through adb reverse.
probe="flutter test integration_test/playback_probe.dart --plain-name every corpus 360° video plays projected"
probe+=" --dart-define=SPHERE_TWINS=http://127.0.0.1:8360"
for target in "android:--flavor play -d emulator-5554" "ios:-d 1A2B3C4D-1111-2222-3333-444455556666" \
  "macos:-d macos" "windows:-d windows"; do
  calls "${target%%:*}" "$probe ${target#*:}"
  # The server starts in the background, so its line comes whenever it does.
  [[ $LOG == *"flutter test test/features/viewer/sphere_golden_test.dart"*"$probe"* &&
    $LOG == *"python3 -m http.server 8360 --bind 127.0.0.1 --directory "* ]] &&
    ok "${target%%:*} makes the twins and goldens here and serves them before the probe" ||
    fail "${target%%:*} does not serve the twins and goldens it made: $LOG"
done
calls android "adb reverse tcp:8360 tcp:8360"
smoke linux
[[ $LOG != *"SPHERE_TWINS"* ]] && ok "linux makes its twins itself (tools/video/app_play.sh)" ||
  fail "linux was served twins: $LOG"

smoke
[[ $STATUS -eq 2 && $(<"$TMP/out") == *"usage"* ]] && ok "no target is a usage error" || fail "no target: exit $STATUS"
smoke solaris
[[ $STATUS -eq 2 && $(<"$TMP/out") == *"solaris"* ]] && ok "an unknown target is a usage error naming it" \
  || fail "unknown target: exit $STATUS"

finish
