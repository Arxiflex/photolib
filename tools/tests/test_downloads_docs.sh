#!/usr/bin/env bash
# Downloads (M1-31, ADR-0128) as the owner answered them (photolib-design#483, #499): phones share, at most 500 items
# at once, refusing a larger selection with a message; zips are stored zip64; Firefox stages in the origin's private
# file system; and the ADR keeps the last folder where the code keeps it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0128-downloads.md
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-20 \(photolib-design#463\)\. The owner kept [^*]*photolib-design#483[^*]*#499' \
  "is Accepted, recording the owner's answers (#483, #499)"
assert_matches docs/adr/README.md \
  '\(0128-downloads\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20; #523.s choice kept, 2026-10-23\)' \
  "the index lists ADR-0128 as Accepted, #523's choice kept"
# #523's choice as the owner kept it (photolib-design#676): the code persists the folder with the settings.
assert_prose "$ADR" '\* \*\*Status\*\*: [^*]*photolib-design#676[^*]*folder [^*]*with the settings' \
  "records that the owner kept the folder with the settings (#676)"
assert_prose app/lib/features/settings/settings.dart "'downloadFolder': downloadFolder" \
  "the settings object holds the download folder"
assert_prose "$ADR" 'for the session until settings persisted[^)]*the vault.s sealed .settings. object' \
  "says where the last folder is kept, as the code keeps it"
assert_prose app/lib/features/settings/settings.dart "VaultText\(\(\) => [^,]*, 'settings'\)" \
  "settings, the folder among them, are the vault's sealed settings object"
assert_prose app/lib/ui/selection_bar.dart 'sharesDownloads \? Icons\.share_outlined' "1: phones share"
assert_prose app/lib/features/download/zip.dart 'u16\(0\) // stored[^;]*u16\(1\) // zip64' "2: entries stored, zip64"
assert_prose app/web/download.js "includes\('Firefox'\) \? staged" "3: Firefox stages the file first"
assert_prose "$ADR" 'share at most 500 items at once, refusing a larger selection' "caps a share at 500 items"
assert_matches app/lib/features/download/download_action.dart '^const shareLimit = 500;$' "shareLimit is 500"
assert_matches app/lib/l10n/app_en.arb '"shareTooMany": "Too many to share at once: select \{count\} or fewer"' \
  "a larger selection is told to select fewer"
assert_matches app/test/features/download/download_action_test.dart "'Too many to share at once: select 500 or fewer'" \
  "a widget test refuses a larger selection"
# --- iOS copies at most the lesser of 2 GiB and 5 % of the free space, as the owner kept it (photolib-design#537);
# test_photo_kit.sh checks ShareSheet.swift's min
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — [^*]*the lesser of 2 GiB and 5 % of the free space[^*]*#537' \
  "records the owner's answer on the copies' bound (#537)"
assert_prose "$ADR" 'its copies at most the lesser of 2 GiB and 5 % of the free space' "decides the lesser"
assert_matches AGENTS.md 'copying at most 2 GiB and at most 5 % of the free space' "AGENTS.md says the lesser"

finish
