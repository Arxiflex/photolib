#!/usr/bin/env bash
# The iOS home screen widgets (docs/10 §6.4, ADR-0153). Nothing here compiles Swift, so the widget extension and the
# Xcode project are checked as text against the snapshot the app writes (app/lib/core/widget_snapshot.dart).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

IOS=app/ios
EXTENSION=$IOS/WidgetExtension
WIDGETS=$EXTENSION/Widgets.swift
DART=app/lib/core/widget_snapshot.dart
PROJECT=$IOS/Runner.xcodeproj/project.pbxproj

# --- a WidgetKit extension without Flutter, which reads only the App Group's Widgets/
assert_matches "$EXTENSION/Info.plist" '<string>com\.apple\.widgetkit-extension</string>' "is a WidgetKit extension"
assert_matches "$EXTENSION/Info.plist" '<string>\$\(FLUTTER_BUILD_NUMBER\)</string>' "carries the app's build number"
assert_patterns assert_matches "$WIDGETS" \
  '@main' "is the extension's entry point" \
  'WidgetBundle' "bundles the widgets" \
  'TimelineProvider' "with a timeline" \
  'policy: \.after\(' "renewed when the day changes" \
  'containerURL\(forSecurityApplicationGroupIdentifier: "group\.org\.photolib\.photolib"\)' "in the App Group" \
  '"Widgets"' "reads its Widgets/ folder" \
  '"snapshot\.json"' "and the snapshot there"
[[ -f $WIDGETS ]] && ! grep -qE '^import (Flutter|SQLite)' "$WIDGETS" && ok "$WIDGETS runs without Flutter or SQLite" ||
  fail "$WIDGETS is missing, or imports Flutter or SQLite"
assert_matches "$EXTENSION/WidgetExtension.entitlements" 'group\.org\.photolib\.photolib' "is in the app's App Group"
# What the Dart writes is what the Swift reads.
for key in version date onThisDay year image; do
  assert_matches "$DART" "'$key'" "the app writes the snapshot's $key"
  assert_matches "$WIDGETS" "let $key:" "the widget reads it"
done
assert_matches "$DART" "'version': 1," "the app writes version 1"
assert_matches "$WIDGETS" 'version == 1' "the widget reads version 1 only"

# --- the app has WidgetKit reload the widgets after it writes
assert_matches "$DART" 'reloadWidgets\(\)' "the app asks for a reload after writing"
assert_matches app/lib/core/share_inbox.dart "invokeMethod\('reloadWidgets'\)" "through the App Group's channel"
assert_patterns assert_matches "$IOS/Runner/ShareInbox.swift" \
  'case "reloadWidgets"' "which the Runner answers" \
  'WidgetCenter\.shared\.reloadAllTimelines\(\)' "by reloading every widget's timeline"

# --- built and embedded by the Xcode project
section() { sed -n "/Begin $1 section/,/End $1 section/p" "$PROJECT"; }
target=$(section PBXNativeTarget | sed -n '/\/\* WidgetExtension \*\/ = {/,/};/p')
[[ $target == *'productType = "com.apple.product-type.app-extension"'* ]] && ok "WidgetExtension is an app extension" ||
  fail "the project has no WidgetExtension app extension target"
sources=$(section PBXSourcesBuildPhase)
[[ $sources == *"/* Widgets.swift in Sources */"* ]] && ok "the extension compiles Widgets.swift" ||
  fail "Widgets.swift is in no Sources phase"
embed=$(section PBXCopyFilesBuildPhase | sed -n '/Embed Foundation Extensions \*\/ = {/,/};/p')
[[ $embed == *"WidgetExtension.appex in Embed Foundation Extensions"* ]] && ok "the app embeds the extension" ||
  fail "Embed Foundation Extensions does not embed WidgetExtension.appex"
runner=$(section PBXNativeTarget | sed -n '/\/\* Runner \*\/ = {/,/};/p')
[[ $(grep -c 'PBXTargetDependency' <<<"$runner") == 2 ]] && ok "the app depends on both extensions" ||
  fail "Runner does not depend on the share and the widget extension: $runner"
[[ $(section PBXProject) == *"/* WidgetExtension */,"* ]] && ok "the project lists the target" ||
  fail "the project's targets lack WidgetExtension"
for setting in 'CODE_SIGN_ENTITLEMENTS = WidgetExtension/WidgetExtension.entitlements;' \
  'PRODUCT_BUNDLE_IDENTIFIER = org.photolib.photolib.WidgetExtension;'; do
  [[ $(grep -cF "$setting" "$PROJECT") == 3 ]] && ok "every configuration sets $setting" ||
    fail "not every configuration sets $setting"
done

# --- the decision as the owner kept it (photolib-design#551): 512 px PNGs of on this day, at start and on hide
ADR=docs/adr/0153-ios-widget-snapshot.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21 \(photolib-design#504\)\. The owner kept [^*]*#551' \
  "is Accepted, recording the owner's answer (#551)"
assert_matches docs/adr/README.md '\(0153-[^)]*\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-21\) \|$' \
  "the index lists ADR-0153 as Accepted"
assert_patterns assert_matches "$DART" \
  'pipeline\.load\(item, 512, ' "renders each image at 512 px" \
  '^  unawaited\(write\(\)\);$' "writes the snapshot at start" \
  'AppLifecycleListener\(onHide: write\.call\)' "and whenever the app leaves the screen"
assert_matches app/packages/photolib_data/lib/src/search.dart '^  int years = 6,$' "on this day spans 6 earlier years"

finish
