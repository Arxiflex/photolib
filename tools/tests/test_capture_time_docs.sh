#!/usr/bin/env bash
# The capture-time resolver (ADR-0051, M1-07) as the owner answered it (photolib-design#346, #377): the compiled
# registry confirmed, the confidence rules deferred, zones made robust with the host's default zone, and a GPS zone
# that disagrees with a measured offset shows its wall clock, for review.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0051-capture-time-resolver.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16, refined 2026-10-17\. [^*]*photolib-design#346[^*]*registry is confirmed [^*]*deferred[^*]*#377' \
  "is Accepted, recording the owner's answers (#346, #377)"
assert_patterns assert_prose "$ADR" \
  'compile the registry into the kernel' "the registry is compiled into the kernel" \
  'Agreeing claims combine by noisy-OR' "the confidence rules stand" \
  'a default zone the host chose' "the host passes a default zone" \
  'Measured offsets come before the GPS zone' "measured offsets come before the GPS zone" \
  'the wall clock shown is the GPS zone.s \(.GPS_ZONE.\)[^.]*flagged .NEEDS_REVIEW. and .ZONE_MISMATCH.' \
  "a GPS zone that disagrees with a measured offset shows its wall clock, for review" \
  'A zero delta[^.]*one clock read twice[^.]*: it counts only where the first zone the host gave agrees' \
  "a zero delta yields to the host's zone" \
  '`DEFAULT_ZONE`, an assumption[^.]*`ASSUMED_ZONE`' "the default zone is an assumption, flagged when it shapes the wall clock"
assert_matches docs/adr/README.md '\(0051-capture-time-resolver\.md\) \| [^|]* \| Accepted \(owner confirmed the registry' \
  "the index lists ADR-0051 as Accepted"
assert_patterns assert_prose proto/photolib/kernel/v1/capture_time.proto \
  'TimeZone default_zone = 10;' "the request takes the default zone" \
  'ZONE_SOURCE_DEFAULT_ZONE = 6;' "a default zone is reported as assumed" \
  'CAPTURE_TIME_FLAG_ASSUMED_ZONE = 4;' "a wall clock from the default zone is flagged" \
  'CAPTURE_TIME_FLAG_ZONE_MISMATCH = 5;' "a measured offset the GPS zone disagrees with is flagged"

finish
