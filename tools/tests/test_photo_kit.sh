#!/usr/bin/env bash
# The iOS PhotoKit indexer (M1-02, ADR-0095). Nothing here compiles Swift, so the channels are checked as text against
# the Dart that calls them; the iOS smoke test runs them on a simulator.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

RUNNER=app/ios/Runner
PHOTO_KIT=$RUNNER/PhotoKitChannel.swift
THUMBNAILS=$RUNNER/ThumbnailChannel.swift

# --- every method and channel the Dart side uses is answered
for channel in org.photolib/photo_kit org.photolib/photo_kit/changes; do
  assert_matches app/lib/core/photo_kit.dart "'$channel'" "the Dart side uses $channel"
  assert_matches "$PHOTO_KIT" "\"$channel\"" "opens $channel"
done
methods=$(grep -oE "_call(<[^(]*>)?\('[a-zA-Z]+'" app/lib/core/photo_kit.dart | cut -d"'" -f2 | sort -u)
[[ $(wc -w <<<"$methods") -ge 8 ]] && ok "the Dart side calls at least 8 methods" || fail "methods: $methods"
for method in $methods; do
  assert_matches "$PHOTO_KIT" "case \"$method\"" "answers $method"
done
assert_prose "$PHOTO_KIT" \
  'localIdentifier.*mediaType.*modificationDate.*creationDate.*pixelWidth.*pixelHeight.*duration.*latitude.*longitude.*mediaSubtypes.*representsBurst.*burstSelectionTypes.*burstIdentifier.*isFavorite.*hasAdjustments' \
  "writes a row's fields in the order photo_kit.dart reads them"
assert_matches app/lib/features/library/timeline/platform_thumbnails.dart "'org.photolib/thumbnails'" \
  "the Dart side asks for thumbnails"
assert_patterns assert_matches "$THUMBNAILS" \
  '"org.photolib/thumbnails"' "answers the thumbnail channel" \
  'case "load"' "loads a thumbnail" \
  'case "cancel"' "cancels one" \
  'PHCachingImageManager' "requests thumbnails from PHCachingImageManager"
assert_prose "$THUMBNAILS" \
  'CGColorSpace\.sRGB.*premultipliedFirst.*byteOrder32Little.*image\.draw' \
  "draws the thumbnail upright into sRGB BGRA, CoreGraphics' own order (ADR-0040)"
assert_prose app/lib/features/library/timeline/platform_thumbnails.dart "isScheme\('ph'\)[^;]*Pixels\.bgra" \
  "the Dart side takes PhotoKit's pixels as BGRA"
for method in video pairedVideo; do
  assert_matches app/lib/features/viewer/video.dart "invokeMethod<String>\\('$method'" "the viewer asks for $method"
  assert_matches "$THUMBNAILS" "case \"$method\"" "answers $method"
done
assert_matches app/lib/features/viewer/video.dart "invokeMethod<double>\\('frameRate'" "the viewer asks a video's frame rate"
assert_patterns assert_matches "$THUMBNAILS" \
  'case "read"' "reads an image's bytes, which an animation needs" \
  'requestImageDataAndOrientation' "from PhotoKit, never from iCloud" \
  'case "frameRate"' "answers frameRate" \
  'nominalFrameRate' "from AVAsset's video track, as extraction never reads PhotoKit's files" \
  '"org.photolib/viewer"' "answers the viewer's channel" \
  'requestAVAsset\(forVideo:' "reads a video in place" \
  'type == \.pairedVideo' "writes a Live Photo's paired video"

# --- what PhotoKit gives and what it must not do
assert_patterns assert_matches "$PHOTO_KIT" \
  'fetchPersistentChanges\(since:' "replays the persistent history" \
  'persistentChangeTokenExpired' "answers an expired token with a full read" \
  'PHPhotoLibraryChangeObserver' "hears changes while the app runs" \
  'cloudIdentifierMappings' "reads cloud identifiers" \
  'includeAllBurstAssets = true' "indexes every frame of a burst" \
  'presentLimitedLibraryPicker' "offers the limited-library picker" \
  'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' "keeps the install id off backups and other phones"
for swift in "$PHOTO_KIT" "$THUMBNAILS"; do
  [[ -f $swift ]] || continue
  grep -q 'isNetworkAccessAllowed = true' "$swift" && fail "$swift lets iCloud download for the index or grid" ||
    ok "$swift never downloads from iCloud"
  grep -q 'includeHiddenAssets = true' "$swift" && fail "$swift shows hidden assets" || ok "$swift leaves hidden assets out"
done
assert_prose "$RUNNER/Info.plist" '<key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>[[:space:]]*<true/>' \
  "the app, not iOS, explains limited access"

# --- the share sheet, where phones download (ADR-0128): an explicit export, so it may fetch from iCloud, with progress
# and a cancel (docs/10 §6.2)
SHARE=$RUNNER/ShareSheet.swift
assert_patterns assert_matches app/lib/features/download/download_action.dart \
  "MethodChannel\('org.photolib/share'\)" "the Dart side shares PhotoKit assets" \
  "invokeMethod<void>\('share'" "in the share sheet" \
  "call.method != 'progress'" "shows the progress of their download" \
  "invokeMethod<void>\('cancel'\)" "and may cancel it"
assert_patterns assert_matches "$SHARE" \
  '"org.photolib/share"' "answers the share channel" \
  'case "share"' "shares assets" \
  'PHAssetResourceManager' "writes each asset's file" \
  'isNetworkAccessAllowed = true' "from iCloud if need be (docs/10 §6.2)" \
  'progressHandler' "hears how far PhotoKit's download is" \
  'invokeMethod\("progress"' "and tells Dart" \
  'case "cancel"' "takes a cancel" \
  'cancelDataRequest' "which stops every request" \
  'code: "cancelled"' "and answers the share as cancelled" \
  'UIActivityViewController' "offers them in the share sheet" \
  'removeItem\(at: folder\)' "and deletes the copies once it closes" \
  'volumeAvailableCapacityForImportantUsageKey' "bounds the copies by the free space" \
  'min\(2 << 30, free / 20\)' "to 2 GiB or 5 % of it, whichever is less (docs/10 §6.2)" \
  'copied \+ Int64\(data\.count\) <= limit' "writes nothing past the bound" \
  'code: "tooLarge"' "and answers a share past it as too large" \
  'removeItem\(at: root\)' "and deletes at start what a share left when the app was killed"
assert_matches app/lib/features/download/download_action.dart "e.code == 'tooLarge'" "the Dart side says a share is too large"

# --- registered with the engine and compiled into the app
sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' app/ios/Runner.xcodeproj/project.pbxproj)
for class in PhotoKitChannel ThumbnailChannel ShareSheet; do
  assert_matches "$RUNNER/AppDelegate.swift" "$class\.register\(" "registers $class"
  [[ $sources == *"/* $class.swift in Sources */"* ]] && ok "the app compiles $class.swift" ||
    fail "$class.swift is in no Sources phase"
done
assert_matches "$RUNNER/AppDelegate.swift" "ViewerChannel\.register\(" "registers ViewerChannel"
assert_matches tools/smoke.sh 'simctl privacy "\$udid" grant photos org\.photolib\.photolib' \
  "the iOS smoke test grants photo access"
assert_prose app/integration_test/app_test.dart 'PhotoKit answers the indexer.*TargetPlatform\.iOS' \
  "the smoke test indexes the simulator's library on iOS"

finish
