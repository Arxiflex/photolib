#!/usr/bin/env bash
# The desktop thumbnail decoders and macOS folder bookmarks (M1-26, ADR-0107; ADR-0071 as the owner answered it in
# photolib-design#371 and #593). The gate compiles no Swift or C++, so the channels are checked as text against the
# Dart that calls them; the smoke tests build and run them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

MAC=app/macos/Runner
WIN=app/windows/runner
DART=app/lib/features/library/timeline/platform_thumbnails.dart
FOLDERS=app/lib/features/folders/folders.dart
DOWNLOAD=app/lib/features/download/download_io.dart

# --- the thumbnail channel: every method the Dart side calls, on both desktops
assert_matches "$DART" "'org.photolib/thumbnails'" "the Dart side asks for thumbnails"
for method in $(grep -oE "invoke(List)?Method(<[^(]*>)?\('[a-z]+'" "$DART" | cut -d"'" -f2 | sort -u); do
  assert_matches "$MAC/ThumbnailChannel.swift" "case \"$method\"" "macOS answers $method"
  assert_matches "$WIN/thumbnail_channel.cpp" "\"$method\"" "Windows answers $method"
done
assert_matches "$DART" "'refused' =>" "the Dart side passes a refused file to the next decoder"
assert_prose "$DART" "'cancelled' \\|\\| 'unreadable-url' =>" "and turns a cancelled request or an unreadable URL into a cause"
assert_patterns assert_matches "$MAC/ThumbnailChannel.swift" \
  '"org.photolib/thumbnails"' "macOS opens the thumbnail channel" \
  'CGImageSourceCreateThumbnailAtIndex' "decodes stills with ImageIO at the tier" \
  'kCGImageSourceCreateThumbnailWithTransform: true' "upright" \
  'QLThumbnailGenerator' "asks QuickLook for the rest" \
  'AVAssetImageGenerator' "takes videos' poster frames from AVFoundation" \
  'appliesPreferredTrackTransform = true' "upright" \
  'OperationQueue' "off the main thread" \
  'code: "refused"' "refuses what none of them reads" \
  '\(error as NSError\?\)' "naming AVFoundation's error by domain and code" \
  'code: "cancelled"' "says a request was cancelled" \
  'code: "unreadable-url"' "and that a URL is no file's"
check "$MAC/ThumbnailChannel.swift: never answers a load with nil" \
  bash -c "! grep -Eq 'return (result|reply)\(nil\)' '$REPO_ROOT/$MAC/ThumbnailChannel.swift'"
assert_patterns assert_matches "$WIN/thumbnail_channel.cpp" \
  '"org.photolib/thumbnails"' "Windows opens the thumbnail channel" \
  'IShellItemImageFactory' "asks the shell's thumbnail handlers, Media Foundation's for videos" \
  'CreateDecoderFromFilename' "decodes with WIC" \
  'System.Photo.Orientation' "upright" \
  'TrySubmitThreadpoolCallback' "off the platform thread" \
  'Error\("refused"' "refuses what neither reads" \
  'Error\("cancelled"' "says a request was cancelled" \
  'Error\("unreadable-url"' "and that a URL is no file's"

# --- macOS folder bookmarks
for method in $(grep -oE "invoke(List)?Method(<[^(]*>)?\('[a-z]+'" "$FOLDERS" | cut -d"'" -f2 | sort -u); do
  assert_matches "$MAC/FolderAccess.swift" "case \"$method\"" "FolderAccess answers $method"
done
assert_matches "$FOLDERS" "'org.photolib/folders'" "the Dart side asks for folder access"
assert_prose "$DOWNLOAD" "'org.photolib/folders'[^;]*invokeMethod\('reveal'" "the Dart side reveals files in Finder"
assert_prose "$MAC/FolderAccess.swift" 'case "reveal":[^}]*activateFileViewerSelecting' \
  "FolderAccess reveals them, as the sandbox allows"
assert_matches "$MAC/FolderAccess.swift" 'securityScopeAllowOnlyReadAccess' \
  "bookmarks keep folders read-only, though downloads may write where the user chose"
assert_patterns assert_matches "$MAC/FolderAccess.swift" \
  '"org.photolib/folders"' "opens the folder channel" \
  'bookmarkData\(' "keeps a bookmark of each picked folder" \
  '\.withSecurityScope' "security-scoped" \
  'startAccessingSecurityScopedResource' "opens it again" \
  'bookmarkDataIsStale' "renews stale bookmarks"
assert_prose "$MAC/MainFlutterWindow.swift" 'let folders = FolderAccess\(\).*FlutterViewController\(\)' \
  "resolves the bookmarks before the engine starts the app's Dart"
assert_matches "$MAC/FolderAccess.swift" 'UserDefaults\.standard' "keeps bookmarks on this device, never in the replica"
assert_prose app/lib/features/desktop/file_drag.dart 'addPickedFolder' "a dropped folder gets a bookmark as a picked one"
for entitlements in "$MAC"/DebugProfile.entitlements "$MAC"/Release.entitlements; do
  for key in app-sandbox files.bookmarks.app-scope; do
    assert_prose "$entitlements" "<key>com\\.apple\\.security\\.$key</key>[[:space:]]*<true/>" "grants $key"
  done
done
ADR=docs/adr/0071-desktop-folders-in-the-app.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner answered [^*]*photolib-design#371' \
  "ADR-0071 is Accepted, recording the owner's answer (#371)"
assert_matches docs/adr/README.md '\(0071-desktop-folders-in-the-app\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0071 as Accepted"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — [^*]*The owner kept read-write for the save dialog[^*]*#593' \
  "ADR-0071 records that the owner kept read-write for the save dialog (#593)"
! cat "$ADR" <(grep -F '](0071-' docs/adr/README.md) | grep -qi 'asked again' &&
  ok "nothing asks the owner about ADR-0071 again" || fail "ADR-0071 or its index row still asks the owner again"
assert_patterns assert_prose "$ADR" \
  'com\.apple\.security\.files\.bookmarks\.app-scope' "keeps a security-scoped bookmark of each folder" \
  'never in the synced replica' "keeps bookmarks on the device" \
  'recreated from the resolved URL' "renews a stale bookmark" \
  'leaves the folder offline' "leaves an unresolved folder offline" \
  'dropped' "bookmarks a dropped folder too" \
  'M10-04 packages a sandboxed, notarised DMG' "packages the sandboxed app"


# --- registered and compiled
sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' app/macos/Runner.xcodeproj/project.pbxproj)
for class in ThumbnailChannel FolderAccess; do
  [[ $sources == *"/* $class.swift in Sources */"* ]] && ok "the macOS app compiles $class.swift" ||
    fail "$class.swift is in no Sources phase"
done
assert_matches "$MAC/MainFlutterWindow.swift" 'ThumbnailChannel\.register\(' "macOS registers ThumbnailChannel"
assert_matches "$MAC/MainFlutterWindow.swift" 'folders\.register\(' "macOS registers FolderAccess"
assert_matches "$WIN/CMakeLists.txt" '"thumbnail_channel.cpp"' "the Windows app compiles thumbnail_channel.cpp"
assert_matches "$WIN/CMakeLists.txt" 'windowscodecs.lib' "and links WIC"
assert_matches "$WIN/flutter_window.cpp" 'RegisterThumbnailChannel\(' "Windows registers the channel"

finish
