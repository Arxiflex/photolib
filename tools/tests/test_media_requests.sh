#!/usr/bin/env bash
# The platform halves of the DeletionService and of favourites (M1-16, ADR-0245). Nothing here compiles Kotlin or
# Swift, so the runners are checked as text against the Dart that calls them over org.photolib/media_requests.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ANDROID=app/android/app/src/main/kotlin/org/photolib/photolib
KOTLIN=$ANDROID/MediaRequests.kt
IOS=app/ios/Runner/MediaRequests.swift
MACOS=app/macos/Runner/MediaRequests.swift

# --- every method each Dart side calls is answered
check_methods() { # <dart> <runner> <how the runner names a method>
  local methods
  methods=$(grep -oE "(invokeMethod|invokeListMethod|_request)(<[^(]*>)?\('[a-zA-Z]+'" "$1" | cut -d"'" -f2 | sort -u)
  [[ -n $methods ]] && ok "$1 calls methods of org.photolib/media_requests" || fail "$1 calls none"
  for method in $methods; do
    assert_matches "$2" "${3//%s/$method}" "answers $method"
  done
}
for runner in "$KOTLIN" "$IOS" "$MACOS"; do
  assert_matches "$runner" '"org\.photolib/media_requests"' "opens org.photolib/media_requests"
done
check_methods app/lib/core/media_store.dart "$KOTLIN" '"%s" ->'
check_methods app/lib/core/photo_kit.dart "$IOS" 'case "%s"'
check_methods app/lib/core/deletion.dart "$MACOS" 'case "%s"'

# --- each platform's trash, one request a batch
assert_patterns assert_matches "$KOTLIN" \
  'createTrashRequest\(resolver, uris, value\)' "trashes and restores through MediaStore's trash" \
  'createDeleteRequest\(resolver, uris\)' "deletes for good with one request" \
  'createFavoriteRequest\(resolver, uris, value\)' "mirrors favourites to IS_FAVORITE" \
  'MediaStore\.canManageMedia' "knows when MANAGE_MEDIA spares the dialog" \
  'DATE_EXPIRES' "reads when the system empties its trash" \
  'RESULT_OK' "takes the user's answer"
assert_matches app/lib/core/media_store.dart '_batch = 2000' "asks at most 2,000 URIs a request (ADR-0039)"
assert_matches app/android/app/src/main/AndroidManifest.xml 'android.permission.MANAGE_MEDIA' "declares MANAGE_MEDIA"
assert_patterns assert_matches "$ANDROID/MainActivity.kt" \
  'MediaRequests\(this' "the activity opens MediaRequests" \
  'requests\?\.onActivityResult' "and hands it the user's answers"
assert_patterns assert_matches "$IOS" \
  'PHAssetChangeRequest\.deleteAssets' "deletes into Recently Deleted, which Photos confirms once" \
  'isFavorite = value' "writes favourites to Photos" \
  'performChanges' "in one change request"
assert_patterns assert_matches "$MACOS" \
  'trashItem\(at:' "moves files to the Trash" \
  'resultingItemURL' "keeping where each went" \
  'moveItem\(at:' "and moves them back"

# --- compiled into each app
assert_matches app/ios/Runner/AppDelegate.swift 'MediaRequests\.register' "the iOS app registers MediaRequests"
assert_matches app/macos/Runner/MainFlutterWindow.swift 'MediaRequests\.register' "the macOS app registers MediaRequests"
for app in ios macos; do
  sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' "app/$app/Runner.xcodeproj/project.pbxproj")
  [[ $sources == *"/* MediaRequests.swift in Sources */"* ]] && ok "the $app app compiles MediaRequests.swift" ||
    fail "$app: MediaRequests.swift is in no Sources phase"
done

finish
