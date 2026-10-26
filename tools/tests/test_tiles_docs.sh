#!/usr/bin/env bash
# Tiles at once (ADR-0114, M1-27): the ADR states what the design documents it departs from must say instead, which
# the design repository takes over (photolib-design#472), and the code keeps it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0114-tiles-at-once.md
assert_patterns assert_prose "$ADR" \
  '⚠️ docs/10 §3\.3 must say [^*]*cells show the tiles in memory and on disk[^*]*a screen within 100 ms' \
  "docs/10 §3.3: no 'ThumbHash only while dragging'" \
  '⚠️ docs/10 §3\.4 must say that desktop folder items get their ThumbHash from the warm-up.s tile' \
  "docs/10 §3.4: where desktop ThumbHashes come from" \
  '⚠️ docs/10 §3\.5 must say [^*]*two screens ahead [^*]*one behind[^*]*after its scan and at start' \
  "docs/10 §3.5: the window, and the warm-up instead of ±3 screens at rest" \
  '⚠️ docs/19 §3 must list M1-27.s budgets: .folder-open. [^*]*.tile-latency. [^*]*blank frames of .folder-scroll.' \
  "docs/19 §3: the M1-27 budgets"
assert_prose app/lib/features/library/timeline/thumbnails.dart 'if \(ahead > 2 \* screen \|\| behind > screen\)' \
  "the queue's window is two screens ahead and one behind"
assert_prose app/lib/features/library/timeline/scrubber.dart '_decode = Duration\(milliseconds: 100\)' \
  "the scrubber pauses decodes over a screen within 100 ms"

# --- as the owner answered (photolib-design#471): both decisions kept
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner kept both decisions [^*]*photolib-design#471' \
  "is Accepted, recording the owner's answer (#471)" \
  '.tile-latency. and the tiles of .folder-open. are checked on .desktop. targets and printed on .headless.[^.]*blank frames and [^.]*ThumbHashes on both' \
  "says where M1-27's budgets are checked"
assert_matches docs/adr/README.md '\(0114-tiles-at-once\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20\)' \
  "the index lists ADR-0114 as Accepted"
assert_prose app/lib/features/library/timeline/thumbnails.dart \
  'slots = _scrolling \? \(concurrency \+ 1\) ~/ 2 : concurrency' \
  "half the decode slots while the user scrolls, all of them otherwise"
assert_prose app/benchmark/perf_test.dart "const timed = _target != 'headless';" "headless prints the tile latencies only"
finish
