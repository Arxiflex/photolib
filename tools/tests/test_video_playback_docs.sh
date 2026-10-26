#!/usr/bin/env bash
# Video and motion-photo playback (ADR-0112) as the owner kept it (photolib-design#492): libmpv through media_kit under
# MpvPlayers on desktops, no prebuilt libmpv (Windows waits for M1-39's build), motion clips copied into the cache.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0112-video-and-motion-photo-playback.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner kept [^*]*photolib-design#492' \
  "is Accepted, recording the owner's answers (#492)"
assert_matches docs/adr/README.md '\(0112-[^)]*\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20' \
  "the index lists ADR-0112 as Accepted"
assert_prose "$ADR" 'Windows gets no libmpv until M1-39 builds an LGPL one from pinned source' \
  "Windows waits for M1-39's LGPL libmpv"
assert_matches app/lib/main.dart 'Platform\.isLinux \|\| Platform\.isWindows\) MpvPlayers\.register\(\)' \
  "Linux and Windows play through MpvPlayers"
if libs=$(grep -n 'media_kit_libs' app/pubspec.yaml app/pubspec.lock); then fail "a prebuilt libmpv: $libs"; else
  ok "no media_kit_libs_* package fetches a prebuilt libmpv"
fi
assert_prose app/lib/features/viewer/video.dart 'motionClipProvider =.*part\.writeAsBytes\(await file\.read\(length\)\)' \
  "a motion photo's video plays from a copy of its span"

finish
