#!/usr/bin/env bash
# Server ingest (M2-08, ADR-0066) as the owner answered it in photolib-design#366 and #561: files that are no photo or
# video are kept, on four conditions that the server's tests check and the ADR records, and dated by their names; an
# external library's stay counted library_files rows that external::retype queues again (ADR-0093,
# photolib-design#583), and the whole of ADR-0093 is Accepted, as the owner confirmed (photolib-design#686).
# shellcheck disable=SC2016 # patterns match literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0066-server-ingest-pipeline.md
assert_matches "$ADR" '^\* \*\*Status\*\*: Accepted \(owner answered, 2026-10-17\)' "is Accepted"
assert_matches docs/adr/README.md '\(0066-server-ingest-pipeline\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-17' \
  "the index lists ADR-0066 as Accepted"
assert_patterns assert_prose "$ADR" \
  'photolib-design#561' "cites the owner's answer of photolib-design#561" \
  '\(a\) no parser reads their bytes, neither the kernel nor ExifTool' "(a) no parser reads other files' bytes" \
  '`ResolveCaptureTime` dates them from their name and folder alone' "(a) their name and folder alone date them" \
  '\(b\)[^;]*download, `Content-Disposition: attachment` and `application/octet-stream`' "(b) originals only download" \
  '\(c\) they stay out of the timeline, search, memories and sharing' "(c) out of the timeline and sharing" \
  'listed under other files' "(c) listed under other files" \
  '\(d\) each asset records the version of type detection' "(d) assets record the type detection's version" \
  '`retype` sweep[^.]*same asset id[^.]*reconciler' "(d) the sweep makes media of them on the same asset"
assert_matches server/migrations/0019_type_detection.sql 'ADD COLUMN sniff_version' "assets record sniff_version"

ADR=docs/adr/0093-external-libraries.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21[^*]*photolib-design#583' "ADR-0093 is Accepted"
assert_prose "$ADR" '\* \*\*Status\*\*: [^*]*2026-10-23[^*]*whole ADR[^*]*photolib-design#686' \
  "ADR-0093's status records that the owner accepted it whole (#686)"
assert_matches docs/adr/README.md '\(0093-external-libraries\.md\) \| [^|]* \| Accepted \([^|]*whole ADR confirmed' \
  "the index lists ADR-0093 as Accepted whole"
assert_prose "$ADR" 'not media are recorded `unsupported`, not kept as assets, and the `retype` sweep' \
  "files that are not media stay counted rows that the retype sweep reads again"
assert_matches server/crates/photolib-server/src/external.rs '^pub\(crate\) async fn retype\(' "external::retype exists"

finish
