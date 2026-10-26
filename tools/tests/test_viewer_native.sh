#!/usr/bin/env bash
# The viewer's and shares' native side (VIEW-39, M1-32): the gate compiles no Kotlin or Swift, so the window's
# brightness, an animation's bytes, a place opened in maps and a photo set as something on org.photolib/viewer are
# checked as text against the Dart that asks for them, and so is the date of a file iOS copies to share. ADR-0208
# records the owner's answers (photolib-design#606).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

KOTLIN=app/android/app/src/main/kotlin/org/photolib/photolib/ViewerChannel.kt
SWIFT=app/ios/Runner/ThumbnailChannel.swift
for method in brightness setBrightness; do
  assert_matches app/lib/features/viewer/screen.dart "invokeMethod<[a-z]+>\\('$method'" "the viewer asks for $method"
  assert_matches "$KOTLIN" "\"$method\" ->" "Android answers $method"
  assert_matches "$SWIFT" "case \"$method\"" "iOS answers $method"
done
assert_matches app/lib/features/viewer/mpv.dart "invokeMethod<Uint8List>\\('read'" "the viewer reads an animation's bytes"
assert_prose "$KOTLIN" '"read" -> \{ background \{' "Android reads a MediaStore item's bytes off the main thread"
assert_prose "$SWIFT" 'case "read":.*isNetworkAccessAllowed = false.*requestImageDataAndOrientation' \
  "iOS reads a PhotoKit asset's bytes, never from iCloud"
assert_matches app/lib/features/viewer/handoff.dart "invokeMethod<void>\\('view'" "the viewer opens a place in maps"
assert_prose "$KOTLIN" '"view" ->.*ACTION_VIEW' "Android opens a place in the maps app"
assert_prose "$KOTLIN" '"setAs" ->.*ACTION_ATTACH_DATA.*FLAG_GRANT_READ_URI_PERMISSION' "Android offers a photo to set as"
assert_prose "$SWIFT" 'call.method == "view".*UIApplication.shared.open' "iOS opens a place in Maps"
assert_prose app/macos/Runner/FolderAccess.swift 'case "view":.*NSWorkspace.shared.open' "macOS opens a place in Maps"
assert_matches "$KOTLIN" 'screenBrightness = .*BRIGHTNESS_OVERRIDE_NONE' "Android gives the brightness back to the system"
assert_prose "$SWIFT" 'UIScreen\.main\.brightness = saved' "iOS gives back the brightness it changed, which it keeps"
assert_prose app/ios/Runner/ShareSheet.swift 'modificationDate: taken' "a shared copy is dated when it was taken"

ADR=docs/adr/0208-viewer-ergonomics-and-kept-state.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21\. The owner answered [^*]*photolib-design#606' \
  "is Accepted, recording the owner's answers (#606)"
assert_prose "$ADR" 'videos with a sound track pause other audio[^.]*; a silent one plays over it' \
  "says that a video with sound pauses other audio and a silent one plays over it"
assert_matches docs/adr/README.md '\(0208-viewer-ergonomics-and-kept-state\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0208 as Accepted"

# ADR-0261 as the owner kept it (photolib-design#707): Rotate turns the view only, Map opens each platform's own maps
# app and none on the web, Set as is Android's alone.
ADR=docs/adr/0261-viewer-actions-animated-facet-and-search-grid.md
VIEWER=app/lib/features/viewer
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#707' \
  "is Accepted, recording the owner's answer (#707)"
assert_prose "$ADR" 'A rotation is gone when the viewer closes; the viewer.s Edit saves one as a copy \(ADR-0331\)\.' \
  "says that a rotation is saved through the editor, which M1-22 brought"
assert_matches docs/adr/README.md \
  '\(0261-viewer-actions-animated-facet-and-search-grid\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0261 as Accepted"
assert_prose "$VIEWER/viewer_page.dart" \
  'ViewerAction\.rotate: Command\( strings\.viewerRotate, \(\) => setState\( \(\) => _turns\.update\(' \
  "Rotate turns the view, writing nothing"
assert_prose "$VIEWER/handoff.dart" \
  "TargetPlatform\\.macOS => 'maps://[^']*', TargetPlatform\\.windows => 'bingmaps:[^']*', _ => 'geo:" \
  "Map opens maps:// on Apple, bingmaps: on Windows, geo: elsewhere"
assert_matches app/lib/features/viewer/toolbar.dart 'ViewerAction\.copy \|\| ViewerAction\.setAs => android,' \
  "Set as is offered on Android only"
assert_matches app/lib/features/viewer/toolbar.dart 'ViewerAction\.map => !kIsWeb,' "Map is offered but on the web"

finish
