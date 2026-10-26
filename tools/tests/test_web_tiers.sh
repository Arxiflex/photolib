#!/usr/bin/env bash
# The web's support tiers (M0-37, ADR-0056): the user guide's tier table and known limitations, and the report's CSP,
# name what tools/web_requests.py checks in Chrome and Firefox on every change.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

PAGE=docs/user/browsers.md
REPORT=docs/dev/web-media-path.md
check_py() { python3 -c "import sys; sys.path.insert(0, 'tools'); import web_requests as w; $1"; }

for tier in '1 — first-class' '2 — functional' '3 — basic' 'Unsupported'; do
  assert_matches "$PAGE" "^\| $tier \|" "has the tier '$tier'"
done
assert_prose "$PAGE" '\| 1 — first-class \| [^|]*Chrome[^|]* \| dart2wasm with skwasm \|' \
  "serves Chrome the WASM build"
assert_prose "$PAGE" '\| 2 — functional \| [^|]*Firefox[^|]*Safari[^|]* \| dart2js with CanvasKit \|' \
  "serves Firefox and Safari the JS build"
# Without File System Access tier 2 keeps no folder library (ADR-0214); the page promises a folder import only once the
# app has a webkitdirectory picker (photolib-design#601).
assert_prose "$PAGE" '\| 2 — functional \|( [^|]+ \|){2} [^|]*no folder library' "says tier 2 keeps no folder library"
if ! grep -rq webkitdirectory app/lib app/web && grep -Eqi 'import(ed)? (a folder )?once' "$PAGE"; then
  fail "$PAGE promises a one-off folder import, which the app does not have"
fi
assert_matches "$PAGE" '^## Known limitations$' "has the known limitations"
assert_prose "$PAGE" '## Known limitations( \* [^*]+){5,}' "lists at least five of them"
while IFS= read -r need; do
  assert_prose "$PAGE" "$need" "names $need, which web_requests.py requires of a tier"
done < <(check_py 'print("\n".join(sorted({n for needs in w.NEEDS.values() for n in needs})))')

csp=$(check_py 'print(w.CSP.format(nonce="<nonce>"))')
if grep -qxF -- "$csp" "$REPORT" 2>/dev/null; then ok "$REPORT states the CSP web_requests.py serves"; else
  fail "$REPORT does not state the CSP web_requests.py serves: $csp"
fi
for browser in 'Chrome 155' 'Firefox 158'; do
  assert_matches "$REPORT" "^\| $browser \|" "has results for $browser"
done
assert_matches docs/user/README.md '\]\(browsers\.md\)' "the user guide links the browsers page"
assert_matches docs/dev/README.md '\]\(web-media-path\.md\)' "the developer guide links the report"
assert_matches docs/adr/README.md '\]\(0056-web-support-tiers\.md\)' "the ADR index lists ADR-0056"
# --- ADR-0056 records the decisions as the owner confirmed them (photolib-design#357), and kept its thumbnails
# against ADR-0040's codecs (#534): tiers 2 and 3 decode in the thumbnail worker, and hand Flutter the bitmap
ADR=docs/adr/0056-web-support-tiers.md
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-16 \(roadmap M0-37\)\. The owner confirmed [^*]*photolib-design#357' \
  "is accepted with the owner's answer" \
  'Accepted — 2026-10-16[^*]*\[ADR-0040\][^*]*On 2026-10-21 the owner kept [^*]*worker[^*]*photolib-design#534' \
  "records that the owner kept the worker's decodes over ADR-0040's codecs (#534)"
grep -q 'asked again' "$ADR" && fail "$ADR still says the owner is asked again" || ok "$ADR: #534 is settled"
assert_matches docs/adr/README.md \
  '\(0056-web-support-tiers\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-16; thumbnails 2026-10-21\) \|$' \
  "the index lists ADR-0056 with the thumbnail answer"
assert_prose docs/adr/0040-timeline-image-pipeline.md \
  '\* \*\*Status\*\*: Accepted — 2026-10-17[^*]*photolib-design#534' "ADR-0040 points to the web's answer (#534)"
assert_matches app/lib/features/library/timeline/web_pipeline.dart \
  'decoders: \[browserPosters\(open\), browserThumbnails\(open\)\]' "browser files decode in the thumbnail worker"
assert_matches app/lib/features/library/timeline/browser_thumbnails.dart \
  'ui_web\.browser\.browserEngine == ui_web\.BrowserEngine\.blink' "and encoded tiles too, but on Chromium"

finish
