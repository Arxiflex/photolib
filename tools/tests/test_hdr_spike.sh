#!/usr/bin/env bash
# The HDR spike (M0-39, photolib-design#231): native HDR leaf views on Android 14+, iOS and macOS behind one Flutter
# widget, the probe that measures them, and ADR-0060 with jank, memory and gestures per platform and the go/no-go for
# M1-14. Nothing here builds iOS or macOS, so the wiring of the Swift leaves is checked as text.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0060-hdr-native-leaf-views.md
KOTLIN=app/android/app/src/main/kotlin/org/photolib/photolib

assert_matches app/lib/features/viewer/hdr_leaf.dart "_viewType = 'photolib/hdr'" "the Dart leaf's view type"
for native in $KOTLIN/HdrLeaf.kt app/ios/Runner/HdrLeaf.swift app/macos/Runner/HdrLeaf.swift; do
  assert_patterns assert_matches "$native" \
    '"photolib/hdr"' "registers the same view type" \
    '"support"' "answers the support query" \
    '"rendered"' "reports its first frame" \
    '"failed"' "reports a failure"
done
# --- M1-14: the viewer's leaves open any item's URI, and battery saver shows SDR (docs/10 §4.5)
for native in $KOTLIN/HdrLeaf.kt app/ios/Runner/HdrLeaf.swift app/macos/Runner/HdrLeaf.swift; do
  assert_matches "$native" 'params\["uri"\]' "opens the item's URI"
done
assert_patterns assert_matches $KOTLIN/HdrLeaf.kt \
  'isPowerSaveMode' "battery saver shows SDR" \
  'createSource\(activity\.contentResolver, uri\)' "decodes MediaStore and file URIs"
for apple in app/ios/Runner/HdrLeaf.swift app/macos/Runner/HdrLeaf.swift; do
  assert_matches "$apple" 'isLowPowerModeEnabled' "low power mode shows SDR"
done
assert_matches app/ios/Runner/HdrLeaf.swift 'requestImageDataAndOrientation' "reads a PhotoKit asset's data"
for host in $KOTLIN/MainActivity.kt app/ios/Runner/AppDelegate.swift app/macos/Runner/MainFlutterWindow.swift; do
  assert_matches "$host" 'HdrLeafFactory\.register\(' "registers the leaf with the engine"
done
# Xcode compiles only the files a target's Sources phase lists.
for project in ios macos; do
  pbxproj=app/$project/Runner.xcodeproj/project.pbxproj
  sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' "$pbxproj")
  assert_matches "$pbxproj" 'path = HdrLeaf\.swift; sourceTree = "<group>"' "references Runner/HdrLeaf.swift"
  [[ $sources == *"/* HdrLeaf.swift in Sources */"* ]] && ok "$pbxproj compiles HdrLeaf.swift" ||
    fail "$pbxproj: HdrLeaf.swift is in no Sources phase"
done

assert_file app/integration_test/hdr_probe.dart
assert_matches "$ADR" '^\| Platform \| Jank \| Memory \| Gestures \|' "has a table of jank, memory and gestures"
for platform in 'Android 14\+' iOS macOS Linux; do
  assert_matches "$ADR" "^\| $platform [^|]*\|( [^|]+ \|){3}\$" "has a row for $platform"
done
assert_patterns assert_prose "$ADR" \
  '\*\*(Go|No-go)\*\* for M1-14' "records the go/no-go for M1-14" \
  'app/integration_test/hdr_probe\.dart' "names the probe"
assert_prose docs/dev/flutter.md 'flutter drive --profile.{0,120}integration_test/hdr_probe\.dart' \
  "the Flutter page says how to run the probe"

# --- as the owner answered (photolib-design#347): go now, test and verify on devices later
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17[^*]*photolib-design#347' \
  "is Accepted, recording the owner's answer (#347)"
assert_matches docs/adr/README.md '\(0060-hdr-native-leaf-views\.md\) \| [^|]* \| Accepted \(owner' \
  "the index lists ADR-0060 as Accepted"
assert_patterns assert_prose "$ADR" \
  '\*\*Go\*\* for M1-14, now' "goes for M1-14 now" \
  'merges on the gate, without waiting for the device numbers' "no device number holds M1-14 back" \
  'test phase[^.]*device lab.s \(M10-02\)[^.]*real Ultra HDR' "the test phase runs the probe on devices" \
  'unverified, not failed' "the device rows are unverified until then" \
  'shows SDR until it is fixed' "a platform that drops frames shows SDR until fixed"
check "no device number gates M1-14's merge" bash -c "! grep -qi 'before M1-14 merges' $ADR"
# --- and its reading confirmed (photolib-design#473): M1-14 in its roadmap turn, devices in the test phase
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17[^*]*confirmed on 2026-10-20[^*]*photolib-design#473' \
  "the status records the confirmed reading (#473)"
assert_prose "$ADR" 'As the owner confirmed, \*now\* builds M1-14 in its turn in the roadmap \(after M1-11\)' \
  "M1-14 keeps its place in the roadmap"
assert_matches docs/adr/README.md '\(0060-hdr-native-leaf-views\.md\) \| [^|]* \| Accepted \([^|]*reading confirmed, 2026-10-20' \
  "the index records the confirmation"
assert_prose AGENTS.md 'hdr_probe\.dart[^.]*test phase' "AGENTS.md says the test phase measures the leaf on devices"

# --- ADR-0216 as the owner confirmed it (photolib-design#722): HDR is a facet extraction writes, read again for the
# whole library once (schema 20); Samsung's SEF gain maps stay SDR; the viewer's HDR toggle is on by default.
VIEWER=docs/adr/0216-hdr-and-raw-in-the-viewer.md
assert_prose "$VIEWER" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner confirmed [^*]*photolib-design#722' \
  "ADR-0216 is Accepted, recording the owner's confirmation (#722)"
assert_matches docs/adr/README.md '\(0216-hdr-and-raw-in-the-viewer\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0216 as Accepted"
assert_prose app/packages/photolib_data/lib/src/read_metadata.dart \
  "if \(meta\.gainMap \|\| meta\.dolbyVision \|\| const \{16, 18\}\.contains\(meta\.transfer\)\) 'hdr'" \
  "extraction writes the hdr facet"
assert_prose app/packages/photolib_data/lib/src/replica.dart \
  "_from19To20\(Migrator m, Schema20 schema\) => customStatement\('UPDATE local_asset SET extracted = NULL'\)" \
  "schema 20 reads every file again"
assert_prose "$VIEWER" "Samsung's SEF gain map is no HDR" "SEF gain maps show in SDR"
assert_prose app/lib/features/settings/settings.dart 'this\.hdr = true,' "HDR is on by default"

finish
