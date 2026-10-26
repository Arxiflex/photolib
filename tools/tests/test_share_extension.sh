#!/usr/bin/env bash
# The iOS share extension, "Save to Photolib" (M1-19, ADR-0143). Nothing here compiles Swift, so the extension, the
# Runner's inbox channel and the Xcode project are checked as text against the Dart that drains the inbox; the iOS
# smoke test saves an inbox entry into the simulator's library.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

IOS=app/ios
EXTENSION=$IOS/ShareExtension
SHARE=$EXTENSION/ShareViewController.swift
INBOX=$IOS/Runner/ShareInbox.swift
DART=app/lib/core/share_inbox.dart
PROJECT=$IOS/Runner.xcodeproj/project.pbxproj
ADR=docs/adr/0143-ios-share-inbox.md

# --- the decision as the owner kept it (photolib-design#503): into the Photos library, the App Group registered later
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20 \(photolib-design#68\)\. The owner kept [^*]*#503' \
  "is Accepted, recording the owner's answers (#503)"
assert_matches docs/adr/README.md '\(0143-ios-share-inbox\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20' \
  "the index lists ADR-0143 as Accepted"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted [^*]*ranked Alternate, never the default[^*]*photolib-design#551' \
  "records that Files offers the app, never as the default (#551)"
assert_prose "$ADR" 'registered with Apple in the test phase, before the first device build' \
  "says when the App Group is registered"

# --- the extension: photos and videos in, a manifest last, no Flutter engine
assert_patterns assert_matches "$EXTENSION/Info.plist" \
  '<string>com\.apple\.share-services</string>' "is a share extension" \
  'NSExtensionActivationSupportsImageWithMaxCount' "offers itself for photos" \
  'NSExtensionActivationSupportsMovieWithMaxCount' "and for videos" \
  '<string>\$\(PRODUCT_MODULE_NAME\)\.ShareViewController</string>' "runs ShareViewController" \
  '<string>\$\(FLUTTER_BUILD_NUMBER\)</string>' "carries the app's build number"
assert_patterns assert_matches "$SHARE" \
  'UTType\.movie' "takes videos" \
  'UTType\.image' "takes photos" \
  'loadFileRepresentation' "copies files rather than loading them into its little memory" \
  'containerURL\(forSecurityApplicationGroupIdentifier' "into the App Group's container" \
  'completeRequest' "and hands the share sheet back"
assert_prose "$SHARE" 'await copy\(provider.*"manifest\.json"' "writes an entry's manifest after its files"
[[ -f $SHARE ]] && ! grep -q 'import Flutter' "$SHARE" && ok "$SHARE runs without Flutter" ||
  fail "$SHARE is missing or starts a Flutter engine"

# --- one App Group, one inbox, one manifest format
group=$(sed -n 's/.*<string>\(group\.[^<]*\)<\/string>.*/\1/p' "$IOS/Runner/Runner.entitlements")
[[ $group ]] && ok "the app is in an App Group" || fail "Runner.entitlements names no App Group"
for file in "$EXTENSION/ShareExtension.entitlements" "$SHARE" "$INBOX"; do
  assert_matches "$file" "${group:-no group}" "names the app's App Group"
done
[[ $group == "group.$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);/\1/p' "$PROJECT" | sort | head -1)" ]] &&
  ok "the App Group is the app's placeholder identifier's, renamed with it" ||
  fail "the App Group $group is not group.<the app's bundle identifier>"
for file in "$SHARE" "$INBOX"; do
  assert_matches "$file" '"Inbox"' "uses the inbox folder"
done
for key in items file kind; do
  for file in "$SHARE" "$INBOX"; do assert_matches "$file" "\"$key\"" "writes the manifest's $key"; done
  assert_matches "$DART" "\[?'$key'\]" "the Dart side reads the manifest's $key"
done
for kind in photo video; do
  assert_matches "$SHARE" "\"$kind\"" "marks a $kind"
  assert_matches "$INBOX" "\"$kind\"|\\.$kind" "saves a $kind as one"
done

# --- the app saves an entry into the Photos library
assert_matches "$DART" "'org\.photolib/inbox'" "the Dart side uses org.photolib/inbox"
assert_patterns assert_matches "$INBOX" \
  '"org\.photolib/inbox"' "answers org.photolib/inbox" \
  'case "folder"' "names the inbox folder" \
  'case "save"' "saves an entry" \
  'PHAssetCreationRequest' "as new Photos assets" \
  'performChanges' "in one change" \
  'code: "denied"' "says when Photos refuses access, which the library shows" \
  'case "allow"' "asks for access to add to Photos" \
  'requestAuthorization\(for: \.addOnly\)' "as the system asks it" \
  'openSettingsURLString' "or in Settings once it no longer asks"
assert_matches "$DART" "PlatformException\(code: 'denied'\)" "the Dart side counts what waits for access"
assert_matches "$IOS/Runner/AppDelegate.swift" 'ShareInbox\.register\(' "registers ShareInbox"

# --- Open in Photolib, from Files or another app: the Runner adds the file to the inbox as the extension does
plist=$(tr -d '\n\t' <"$IOS/Runner/Info.plist")
[[ $plist == *'<key>CFBundleDocumentTypes</key>'*'<string>public.image</string>'*'<string>public.movie</string>'* ]] &&
  ok "the app opens photos and videos (CFBundleDocumentTypes)" || fail "Info.plist declares no photo and video types"
[[ $plist == *'<key>LSHandlerRank</key><string>Alternate</string>'* ]] && ok "without claiming them from Photos" ||
  fail "the document types must rank Alternate"
[[ $plist == *'<key>LSSupportsOpeningDocumentsInPlace</key><false/>'* ]] && ok "and gets a copy of each" ||
  fail "LSSupportsOpeningDocumentsInPlace must be false: the inbox moves the file it gets"
assert_patterns assert_matches "$INBOX" \
  'FlutterSceneLifeCycleDelegate' "hears the scene's events" \
  'addSceneDelegate' "registered with the scene" \
  'willConnectTo' "a file that starts the app" \
  'openURLContexts' "or opens in it" \
  '"manifest\.json"' "writes the entry's manifest" \
  'invokeMethod\("changed"' "and tells the app"
assert_prose "$INBOX" 'moveItem.*"manifest\.json"' "moves an entry's files before its manifest"
assert_matches "$DART" "'changed'" "the app drains the inbox when the Runner adds to it"
assert_matches app/lib/main.dart 'shareInboxProvider' "the app drains the inbox from its start"
assert_prose "$IOS/Runner/Info.plist" '<key>NSPhotoLibraryAddUsageDescription</key>[[:space:]]*<string>[^<]+</string>' \
  "says why it adds to the Photos library"
assert_prose app/integration_test/app_test.dart 'drainInbox\(inbox, const ShareInboxChannel\(\)\.save\).*TargetPlatform\.iOS' \
  "the iOS smoke test saves an inbox entry into the simulator's library"

# --- built and embedded by the Xcode project
section() { sed -n "/Begin $1 section/,/End $1 section/p" "$PROJECT"; }
target=$(section PBXNativeTarget | sed -n '/\/\* ShareExtension \*\/ = {/,/};/p')
[[ $target == *'productType = "com.apple.product-type.app-extension"'* ]] && ok "ShareExtension is an app extension" ||
  fail "the project has no ShareExtension app extension target"
[[ $(section PBXSourcesBuildPhase) == *"/* ShareViewController.swift in Sources */"* ]] &&
  ok "the extension compiles ShareViewController.swift" || fail "ShareViewController.swift is in no Sources phase"
[[ $(section PBXSourcesBuildPhase) == *"/* ShareInbox.swift in Sources */"* ]] && ok "the app compiles ShareInbox.swift" ||
  fail "ShareInbox.swift is in no Sources phase"
embed=$(section PBXCopyFilesBuildPhase | sed -n '/Embed Foundation Extensions \*\/ = {/,/};/p')
[[ $embed == *"dstSubfolderSpec = 13;"* && $embed == *"ShareExtension.appex in Embed Foundation Extensions"* ]] &&
  ok "the app embeds the extension" || fail "no Embed Foundation Extensions phase embeds ShareExtension.appex"
# Flutter's own build phases come after the embedding, or Xcode finds a cycle (docs.flutter.dev, iOS app extensions).
phases=$(section PBXNativeTarget | sed -n '/\/\* Runner \*\/ = {/,/};/p' | grep -oE 'Embed Foundation Extensions|Run Script')
[[ $(head -n 1 <<<"$phases") == "Embed Foundation Extensions" ]] && ok "the app embeds the extension before Run Script" ||
  fail "Embed Foundation Extensions must come before Run Script: $phases"
[[ $(section PBXNativeTarget | sed -n '/\/\* Runner \*\/ = {/,/};/p') == *"/* PBXTargetDependency */"* ]] &&
  ok "the app depends on the extension" || fail "Runner does not depend on ShareExtension"
for entitlements in Runner/Runner.entitlements ShareExtension/ShareExtension.entitlements; do
  [[ $(grep -c "CODE_SIGN_ENTITLEMENTS = $entitlements;" "$PROJECT") == 3 ]] &&
    ok "every configuration signs with $entitlements" || fail "not every configuration signs with $entitlements"
done
targets=$(grep -oE 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;' "$PROJECT" | sort -u)
[[ $(wc -l <<<"$targets") == 1 ]] && ok "the app and the extension deploy to the same iOS" || fail "deployment targets: $targets"

finish
