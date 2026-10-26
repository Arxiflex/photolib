#!/usr/bin/env bash
# Prints the directory holding the ffmpeg and ffprobe that the video tests run. On Linux x86-64 that is the LGPL
# build pinned below (no libx264 or libx265, like the apps' FFmpeg of ADR-0013), fetched once into the per-user tools
# cache and checked against its SHA-256; elsewhere the ffmpeg and ffprobe on PATH, refused when built with
# `--enable-gpl` (Homebrew's is) so that the tests see only the apps' encoders. With `--libs`, the directory of
# the same release's shared libraries that headless Firefox decodes H.264 and AAC with on Linux, which has no decoder
# of its own; elsewhere nothing.
set -euo pipefail

# A month's last build, which BtbN keeps for two years.
RELEASE=autobuild-2026-09-30-13-08
BUILD=ffmpeg-n8.1.3-9-g29e619e767-linux64-lgpl-8.1
SHA256=dfa863a00ca81f1bdf58a372b18cff4820f0017e55de32778de8ecd8ed92a02e
SHARED=ffmpeg-n8.1.3-9-g29e619e767-linux64-lgpl-shared-8.1
SHARED_SHA256=d4d7b6936f492c0b866b1cb4a29a1bbae09d6a064b4ec4eb90c95bed7969535a

if [[ ${1:-} == --libs && $(uname -sm) != "Linux x86_64" ]]; then
  exit 0
fi
if [[ $(uname -sm) != "Linux x86_64" ]]; then
  if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
    echo "ffmpeg.sh: no FFmpeg is pinned for $(uname -sm); put ffmpeg and ffprobe on PATH" >&2
    exit 1
  fi
  if [[ $(ffmpeg -hide_banner -version) == *--enable-gpl* ]]; then
    echo "ffmpeg.sh: the ffmpeg on PATH is built with --enable-gpl (x264, x265); the tests need an LGPL build" >&2
    exit 1
  fi
  dirname "$(command -v ffmpeg)"
  exit 0
fi

cache=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
FETCH="bash tools/video/ffmpeg.sh${1:+ $1}"
# fetch <build> <sha256> <file>...: the files of a release, once.
fetch() {
  local build=$1 sha256=$2 file missing=0
  shift 2
  for file in "$@"; do [[ -e $cache/$build/$file ]] || missing=1; done
  ((missing)) || return 0
  if [[ -n ${EGRESS_BLOCKED:-} ]]; then
    echo "ffmpeg.sh: $build is not in $cache, and egress is blocked (tools/offline.sh); fetch it first: $FETCH" >&2
    exit 1
  fi
  (umask 077 && mkdir -p "$cache")
  if [[ ! -O $cache ]]; then
    echo "ffmpeg.sh: $cache is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
    exit 1
  fi
  bash "$(dirname "${BASH_SOURCE[0]}")/../fetch_release.sh" \
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/$RELEASE/$build.tar.xz" "$sha256" "$cache" \
    "${@/#/$build/}"
}
if [[ ${1:-} == --libs ]]; then
  fetch "$SHARED" "$SHARED_SHA256" lib/libavcodec.so.62 lib/libavcodec.so.62.28.103 lib/libavutil.so.60 \
    lib/libavutil.so.60.26.103 lib/libswresample.so.6 lib/libswresample.so.6.3.103
  echo "$cache/$SHARED/lib"
  exit 0
fi
fetch "$BUILD" "$SHA256" bin/ffmpeg bin/ffprobe
echo "$cache/$BUILD/bin"
