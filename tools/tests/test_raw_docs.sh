#!/usr/bin/env bash
# The RAW pipeline (ADR-0247, M7-04) as the owner kept it (photolib-design#703): every host shows a RAW as its largest
# embedded JPEG, turned by the RAW's orientation; full decode waits for a libvips with LibRaw in the image.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0247-raw-pipeline.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#703' \
  "is Accepted, recording the owner's answer (#703)"
assert_matches docs/adr/README.md '\(0247-raw-pipeline\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0247 as Accepted"
assert_prose server/crates/photolib-media/src/render.rs 'let preview = raw\.as_deref\(\)\.map\(largest_jpeg\)' \
  "the server renders a RAW from its largest embedded JPEG"
assert_prose app/lib/features/library/timeline/vips.dart 'jpeg = await largestPreview\(path\);' \
  "desktops decode a RAW's largest embedded JPEG"
grep -rqi dcrawload server/crates deploy/Dockerfile && fail "something decodes RAW sensor data before ADR-0247 allows" ||
  ok "no host decodes RAW sensor data yet"

finish
