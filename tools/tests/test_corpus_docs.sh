#!/usr/bin/env bash
# The media corpus (ADR-0020, M0-28) as the owner answered photolib-design#287: Pillow confirmed, the other choices
# left to the implementer, so all five stand and the ADR records them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0020-in-tree-synthetic-media-corpus.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-15[^*]*photolib-design#287[^*]*confirmed Pillow[^*]*left the rest' \
  "is Accepted, recording the owner's answers on #287"
assert_prose "$ADR" 'Motion JPEG video \(AVI and QuickTime\) decodes' "decodes only Motion JPEG video"
assert_prose "$ADR" 'drawn at 160×120' "draws small rasters at 160×120"
assert_prose "$ADR" 'pinned Pillow \(installed from PyPI' "decodes with a pinned Pillow from PyPI"
assert_prose "$ADR" 'token probability tables of RFC 6386' "keeps the RFC 6386 VP8 tables"
assert_prose "$ADR" 'JPEG XL and ProRAW DNGs decode only through their previews' "decodes JPEG XL and ProRAW via previews"
assert_matches docs/adr/README.md '\(0020-in-tree-synthetic-media-corpus\.md\) \| [^|]* \| Accepted \(owner confirmed[^|]*#287' \
  "the index lists ADR-0020 as Accepted with the #287 answers"

finish
