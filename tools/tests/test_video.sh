#!/usr/bin/env bash
# The video engines spike (M0-35): the pinned LGPL FFmpeg that the executors' tests run.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

SCRIPT=tools/video/ffmpeg.sh
sandbox_tools bash dirname id mkdir
build=$(sed -n 's/^BUILD=//p' "$SCRIPT" 2>/dev/null)

# ffmpeg_sh <uname -sm output>: runs the script with only stubs on PATH and a private tools cache.
ffmpeg_sh() {
  new_sandbox "$SCRIPT"
  printf '#!/bin/bash\necho "%s"\n' "$1" >"$SANDBOX/stubs/uname"
  chmod +x "$SANDBOX/stubs/uname"
  capture env PATH="$SANDBOX/stubs:$BASE_BIN" PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" bash "$SANDBOX/$SCRIPT"
}

ffmpeg_sh "Linux x86_64"
mkdir -p "$SANDBOX/cache/$build/bin" && touch "$SANDBOX/cache/$build/bin/"{ffmpeg,ffprobe} &&
  chmod +x "$SANDBOX/cache/$build/bin/"*
capture env PATH="$SANDBOX/stubs:$BASE_BIN" PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" bash "$SANDBOX/$SCRIPT"
expect_result "on Linux x86-64 the cached LGPL build is used without a download" 0 "$SANDBOX/cache/$build/bin"
assert_matches "$SCRIPT" '^BUILD=ffmpeg-n[0-9.]+-.*-linux64-lgpl-' "pins an LGPL build"
assert_matches "$SCRIPT" '^SHA256=[0-9a-f]{64}$' "pins its SHA-256"

ffmpeg_sh "Darwin arm64"
stub_command "$SANDBOX/stubs/ffmpeg" ffmpeg && stub_command "$SANDBOX/stubs/ffprobe" ffprobe
capture env PATH="$SANDBOX/stubs:$BASE_BIN" bash "$SANDBOX/$SCRIPT"
expect_result "elsewhere the ffmpeg and ffprobe on PATH are used" 0 "$SANDBOX/stubs"
printf '#!/bin/bash\necho "configuration: --enable-gpl --enable-libx264 --enable-libx265"\n' >"$SANDBOX/stubs/ffmpeg"
capture env PATH="$SANDBOX/stubs:$BASE_BIN" bash "$SANDBOX/$SCRIPT"
expect_result "elsewhere a PATH FFmpeg built with --enable-gpl is refused: tests see only the apps' encoders" failure \
  "built with --enable-gpl"

ffmpeg_sh "Darwin arm64"
expect_result "elsewhere, without ffmpeg on PATH, it fails loudly" failure "ffmpeg and ffprobe"

# --libs: the shared libraries headless Firefox decodes H.264 and AAC with on Linux, where it has none of its own.
shared=$(sed -n 's/^SHARED=//p' "$SCRIPT" 2>/dev/null)
ffmpeg_sh "Linux x86_64"
mkdir -p "$SANDBOX/cache/$shared/lib" && (cd "$SANDBOX/cache/$shared/lib" &&
  touch libavcodec.so.62 libavcodec.so.62.28.103 libavutil.so.60 libavutil.so.60.26.103 libswresample.so.6 \
    libswresample.so.6.3.103)
capture env PATH="$SANDBOX/stubs:$BASE_BIN" PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" bash "$SANDBOX/$SCRIPT" --libs
expect_result "--libs prints the cached shared LGPL libraries' directory" 0 "$SANDBOX/cache/$shared/lib"
assert_matches "$SCRIPT" '^SHARED=ffmpeg-n[0-9.]+-.*-linux64-lgpl-shared-' "pins the shared LGPL build"
assert_matches "$SCRIPT" '^SHARED_SHA256=[0-9a-f]{64}$' "pins the shared build's SHA-256"
ffmpeg_sh "Darwin arm64"
capture env PATH="$SANDBOX/stubs:$BASE_BIN" bash "$SANDBOX/$SCRIPT" --libs
[[ $STATUS -eq 0 && -z $OUT ]] && ok "elsewhere --libs prints nothing: the browsers have their own decoders" ||
  fail "elsewhere --libs printed $STATUS: $OUT"

# --- the decision: an engine for every target, from the spike's report, as the owner answered it (#338)
ADR=docs/adr/0043-video-editing-engines.md
REPORT=docs/dev/video-engines.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\.[^*]*photolib-design#338' \
  "is Accepted, recording the owner's answers (#338)"
assert_matches docs/adr/README.md '\(0043-video-editing-engines\.md\) \| [^|]+ \| Accepted \(owner answered' \
  "the index lists ADR-0043 as Accepted"
assert_patterns assert_matches "$ADR" \
  '^\| Android \| Media3 Transformer' "runs Android on Media3" \
  '^\| iOS, macOS \| AVFoundation' "runs Apple platforms on AVFoundation" \
  '^\| Windows \| LGPL FFmpeg \| Media Foundation' "runs Windows on Media Foundation's encoders" \
  '^\| Linux \| LGPL FFmpeg \| VA-API or NVENC, then OpenH264.*Cisco.*then the server or the trusted node' \
  "encodes H.264 on Linux with VA-API or NVENC, then OpenH264, then remotely" \
  '^\| Server, trusted node \| FFmpeg' "runs the server on FFmpeg" \
  '^\| Web \| none in the browser' "runs no executor in the browser"
assert_prose "$ADR" 'never compiled into our build.*FFmpeg starts without it' "never builds OpenH264 in"
assert_prose "$ADR" '1\. a hardware 10-bit HEVC encoder; 2\. the server \(x265\) for standard libraries, the trusted node for private ones; 3\. on Linux, libx265 in an FFmpeg the user installed.*; 4\. 10-bit AV1 only when every device of the library declares AV1 playback; 5\. otherwise tone-mapped SDR, and the user is told' \
  "keeps HDR in the owner's order"
assert_prose "$ADR" 'remuxer in the kernel.*every target' "plans lossless trims as a kernel remuxer on every target"
assert_matches docs/admin/privacy.md '^\| OpenH264 \| Cisco.*ciscobinary\.openh264\.org.*\| planned in M8-09 \|$' \
  "the privacy manifest lists Cisco's OpenH264 download"
assert_matches docs/dev/threat-model.md '^\| T50 \|.*OpenH264' "the threat model covers a tampered OpenH264 download"
assert_prose "$ADR" '\(\.\./dev/video-engines\.md\)' "links the report"
assert_prose docs/dev/README.md '\(video-engines\.md\)' "the developer guide links the report"
for row in FFmpeg Media3 AVFoundation 'Chrome 155' 'Firefox 158'; do
  assert_matches "$REPORT" "^\| $row \|" "has a row for $row"
done
assert_prose "$REPORT" 'testdata/edl.*tools/video/ffmpeg\.sh' "says how to rerun the executors"
assert_prose AGENTS.md 'photolib_video.*tools/video/ffmpeg\.sh' "AGENTS.md names the executors and their FFmpeg"
assert_prose app/README.md 'packages/photolib_video' "app/README.md names the executors"
assert_prose testdata/README.md '`edl/`' "testdata/README.md names the edit decision lists"
assert_prose tools/README.md 'video/ffmpeg\.sh' "tools/README.md names the FFmpeg fetcher"

finish
