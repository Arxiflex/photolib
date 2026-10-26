#!/usr/bin/env bash
# The iOS backup spike's probe (docs/dev/ios-backup-spike.md): runs app/ios/RunnerTests/PhotoKitProbe.swift on an
# iPhone simulator seeded to 100k assets, or on a phone's own library, uploading to a sink on this Mac, and prints the
# report's rows. Needs macOS with Xcode and Flutter. A phone needs signing (`-- DEVELOPMENT_TEAM=<team>
# -allowProvisioningUpdates`), "Allow Full Access" when asked, and the Mac on its local network.
set -euo pipefail

usage="usage: photokit_probe.sh [--device <udid>] [--seed <assets>] [--out <dir>] [-- <xcodebuild args>]"
device='' seed='' out=${TMPDIR:-/tmp}/photokit-probe port=${PROBE_PORT:-8765}
while [[ $# -gt 0 ]]; do
  case $1 in
    --device) device=$2; shift 2 ;;
    --seed) seed=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --) shift; break ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
if [[ -n $device && -n $seed ]]; then
  echo "photokit_probe.sh: --seed is for simulators, never a phone's library" >&2
  exit 2
fi
[[ $(uname -s) == Darwin ]] || { echo "photokit_probe.sh: needs macOS with Xcode" >&2; exit 2; }

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
mkdir -p "$out"
rm -f "$out/sink.jsonl"
if [[ -z $device ]]; then
  bundle=$(sed -nE 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = ([^;]*);$/\1/p' \
    app/ios/Runner.xcodeproj/project.pbxproj | grep -v RunnerTests | head -n 1)
  device=$(xcrun simctl list devices available | sed -n 's/^ *iPhone.* (\([0-9A-F-]\{36\}\)) (.*/\1/p' | head -n 1)
  xcrun simctl bootstatus "$device" -b
  xcrun simctl privacy "$device" grant photos "$bundle"
  seed=${seed:-100000} sink=http://localhost:$port build=(--simulator)
else
  seed=0 sink=http://$(scutil --get LocalHostName).local:$port build=()
fi

python3 tools/ios/probe.py sink "$port" "$out/sink.jsonl" &
sink_pid=$!
trap 'kill "$sink_pid" 2>/dev/null || true' EXIT
(cd app && flutter build ios --config-only --debug ${build[@]+"${build[@]}"})
for _ in {1..50}; do curl -s -o /dev/null "http://localhost:$port/" && break; sleep 0.1; done
TEST_RUNNER_PROBE_RUN=1 TEST_RUNNER_PROBE_SEED=$seed TEST_RUNNER_PROBE_SINK=$sink \
  xcodebuild test -workspace app/ios/Runner.xcworkspace -scheme Runner -destination "id=$device" \
  -only-testing:RunnerTests/PhotoKitProbe "$@" | tee "$out/xcodebuild.log"
sed -n 's/.*PROBE \({.*}\).*/\1/p' "$out/xcodebuild.log" >"$out/probe.jsonl"
python3 tools/ios/probe.py table "$out/probe.jsonl" "$out/sink.jsonl"
