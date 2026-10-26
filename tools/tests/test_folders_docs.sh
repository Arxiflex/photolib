#!/usr/bin/env bash
# The folders view and local albums (ADR-0217, M1-15) as the owner kept them (photolib-design#705): local albums owned
# by the nil UUID, per-device views in the vault, the start screen and tab, folder deletes into the platform's trash
# (on Linux first, every desktop since M1-16's deletion service), and portable file names.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0217-folders-view-and-local-albums.md
FOLDERS=app/lib/features/folders
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#705[^*]*ADR-0245' \
  "is Accepted, recording the owner's answer (#705) and M1-16's folder delete"
assert_matches docs/adr/README.md \
  '\(0217-folders-view-and-local-albums\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0217 as Accepted"
# 1. The nil UUID owns a device's albums.
assert_matches app/packages/photolib_data/lib/src/albums.dart '^final Uint8List localOwner = Uint8List\(16\);$' \
  "local albums are the nil UUID's"
# 2. Order, pins, views and recent targets are the vault's sealed 'folders' object.
assert_matches "$FOLDERS/views.dart" "return VaultText\\(\\(\\) => vault, 'folders'\\);" "views live in the vault"
# 3. The start screen and the tab folders and albums open on.
assert_prose app/lib/features/settings/settings.dart 'enum StartScreen \{[^}]* timeline, [^}]* folders, [^}]* favourites, \}' \
  "the start screens"
assert_matches app/lib/features/settings/settings.dart "albumsFirst \\? '/collections/albums' : '/collections/folders'" \
  "the tab folders and albums open on"
# 4. A folder is deleted into the platform's trash through the deletion service, on every desktop.
assert_matches "$FOLDERS/file_dialogs.dart" 'if \(sure == true && context\.mounted\) await moveToTrash\(context, ref, ids\);' \
  "Delete folder moves its items to the trash"
assert_matches "$FOLDERS/items_page.dart" "bool get files => !kIsWeb && folder\\?\\.source == 'folder';" \
  "every desktop's folder offers it"
grep -q 'On Linux \*Delete folder\*' docs/user/README.md && fail "the user guide offers Delete folder on Linux only" ||
  ok "the user guide offers Delete folder on every computer"
grep -q binProvider AGENTS.md && fail "AGENTS.md names binProvider, which M1-16 replaced" ||
  ok "AGENTS.md names no provider that is gone"
# 5. Portable names: at most 255 UTF-8 bytes, none of / \ : * ? " < > | or control characters, not . or ..
check "$FOLDERS/rename.dart: the characters no platform takes" \
  grep -qF -- "final _forbidden = RegExp(r'[/\\\\:*?\"<>|\\u0000-\\u001f]');" "$FOLDERS/rename.dart"
assert_prose "$FOLDERS/rename.dart" "!const \\{'', '\\.', '\\.\\.'\\}\\.contains\\(name\\)" "not empty, . or .."
assert_matches "$FOLDERS/rename.dart" ': utf8\.encode\(name\)\.length > 255$' "at most 255 UTF-8 bytes"

finish
