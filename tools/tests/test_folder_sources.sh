#!/usr/bin/env bash
# Desktop folder sources (ADR-0042, M1-03) as the owner answered them (photolib-design#337): an empty root of a folder
# with items is offline, and folders are polled every minute and reconciled hourly (confirmed); ignore rules match
# case as the folder's volume does, so that the server can run anywhere (answered differently), a reading the owner
# confirmed (photolib-design#374).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0042-desktop-folder-sources.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner [^*]*photolib-design#337' \
  "is Accepted, recording the owner's answers (#337)"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted[^*]*owner confirmed the reading[^*]*photolib-design#374' \
  "records the owner's confirmation of the case rule (#374)"
assert_patterns assert_prose "$ADR" \
  'root is missing, unreadable or empty while it has items turns `offline`' "an empty root with items is offline" \
  'matching names in any case where the folder.s volume does' "ignore rules match case as the volume does" \
  'full scan every minute; every folder is reconciled hourly' "polls every minute and reconciles hourly"
assert_matches docs/adr/README.md '\(0042-desktop-folder-sources\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0042 as Accepted"
assert_matches testdata/photolibignore.json '"caseSensitive": false' "the ignore cases pin a case-insensitive volume"
WATCHER=app/packages/photolib_data/lib/src/folder_watcher.dart
assert_matches $WATCHER 'this\.poll = const Duration\(minutes: 1\)' "polls every minute by default"
assert_matches $WATCHER 'this\.reconcile = const Duration\(hours: 1\)' "reconciles hourly by default"

finish
