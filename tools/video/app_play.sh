#!/usr/bin/env bash
# Plays every corpus video and motion photo with the app's players on this desktop (app/integration_test/
# playback_probe.dart), each as a twin FFmpeg makes (tools/video/ffmpeg.sh): libmpv on Linux, under xvfb-run without a
# display. The gate's dart part runs it on Linux; macOS and Windows run it by hand.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bin=$(bash "$root/tools/video/ffmpeg.sh")
arch=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
case $(uname -s) in Linux) device=linux ;; Darwin) device=macos ;; *) device=windows arch=x64 ;; esac
display=()
[[ $device == linux && -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && display=(xvfb-run -a)
cd "$root/app"
# Until a kernel release is pinned the app bundles the kernel it builds (ADR-0057).
"$(command -v python3 || command -v python)" ../tools/kernel/build.py --out build/kernel "$device-$arch"
${display[@]+"${display[@]}"} flutter test integration_test/playback_probe.dart -d "$device" \
  --dart-define=PLAYBACK_CORPUS="$root/testdata/corpus" --dart-define=PLAYBACK_FFMPEG="$bin"
