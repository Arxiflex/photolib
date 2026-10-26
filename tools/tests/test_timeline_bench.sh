#!/usr/bin/env bash
# The timeline spike (M0-30): tools/timeline_bench.py builds and runs the app's benchmark on one target, by hand. This
# checks the day buckets it derives from a synthetic library's assets.csv, that the report has a row for every target,
# frame-time percentiles where it was measured, and the ADR that chose the image pipeline, as the owner accepted it
# (photolib-design#335).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

# buckets <taken_local...>: the JSON timeline_bench.py derives from assets with these capture times.
buckets() {
  python3 - "$@" <<'EOF'
import json, sys
sys.path.insert(0, "tools")
import timeline_bench
print(json.dumps(timeline_bench.buckets({"taken_local": t} for t in sys.argv[1:]), separators=(",", ":")))
EOF
}

got=$(buckets 2024-05-03T10:00:00 "" 1999-01-01T00:00:00 2024-05-03T23:59:59.999 2025-12-31T08:00:00 "")
expected='{"days":[20251231,20240503,19990101,0],"counts":[1,2,1,2]}'
[[ $got == "$expected" ]] && ok "buckets: days newest first, undated last" ||
  fail "buckets: expected $expected, got $got"
[[ $(buckets) == '{"days":[],"counts":[]}' ]] && ok "buckets: an empty library has none" ||
  fail "buckets: an empty library gave $(buckets)"

REPORT=docs/dev/timeline-spike.md
ADR=docs/adr/0040-timeline-image-pipeline.md
for target in Android iPhone macOS Windows Safari; do
  assert_matches "$REPORT" "^\| $target[^|]* \|" "has a row for $target"
done
for target in 'Linux \| AOT' 'Chrome [0-9]+ \| dart2js' 'Chrome [0-9]+ \| dart2wasm' 'Firefox [0-9]+ \| dart2js'; do
  assert_matches "$REPORT" "^\| $target \| (codec|raw|bitmap) \| [0-9.]+ / [0-9.]+ / [0-9.]+ \|" \
    "has frame-time percentiles for $target"
done
assert_prose "$REPORT" '\(\.\./adr/0040-timeline-image-pipeline\.md\)' "links the ADR"
assert_prose docs/dev/README.md 'timeline-spike\.md' "the developer guide links the report"
assert_prose "$ADR" 'We will decode thumbnails' "records the chosen image pipeline"
assert_prose "$ADR" '\(\.\./dev/timeline-spike\.md\)' "links the report"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17 [^*]*photolib-design#335' \
  "is Accepted, recording the owner's answer (#335)"
assert_patterns assert_prose "$ADR" \
  'upright sRGB pixels[^.]*Display P3 and Adobe RGB[^.]*`bgra8888`' "the native side hands over upright sRGB" \
  'only encoded thumbnails natively[^.]*once, in T1' "decoded pixels live once, in T1" \
  'golden pixel tests of rotated, P3 and CMYK sources' "golden pixel tests are a condition" \
  'cores − 1 natively and four on the web' "decoders follow the design" \
  'T1 by RAM' "T1 is sized by RAM" \
  'unverified, not failed' "frame and thumbnail budgets are unverified" \
  'per browser engine' "the web may choose its source per engine" \
  'PHOTOLIB_FLAGS=diagnostics`[^.]*Timeline benchmark[^.]*JSON' "test builds run the benchmark and copy its JSON"
assert_matches docs/adr/README.md '\(0040-timeline-image-pipeline\.md\) \| [^|]* \| Accepted \(owner' \
  "the index lists ADR-0040 as Accepted"
check "the report has no unmet budget, only unverified ones" \
  bash -c "! grep -q 'not met' $REPORT && grep -q '| unverified' $REPORT"

finish
