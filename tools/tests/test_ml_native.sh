#!/usr/bin/env bash
# On-device ML's native side (ADR-0254, design 09 §3.4): the device's state on org.photolib/device_health, PhotoKit's
# and MediaStore's pixels on org.photolib/ml, and the indexing backlog in WorkManager or a BGProcessingTask, which ask
# the process's one engine (docs/10 §1.5) for it on the same channel. The gate compiles no Kotlin or Swift, so they
# are checked as text against the Dart that answers them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

KT=app/android/app/src/main/kotlin/org/photolib/photolib
IOS=app/ios/Runner/MlChannel.swift
MAC=app/macos/Runner/MainFlutterWindow.swift
DART=app/lib/core/ml.dart

assert_matches app/lib/core/device_health.dart "invokeMapMethod(<[^(]*>)?\\('state'\\)" "the app asks for the state"
for method in decode schedule cancel; do
  assert_matches "$DART" "invoke[A-Za-z]*Method(<[^(]*>)?\\('$method'" "the app asks for $method"
  assert_matches "$KT/MlChannel.kt" "\"$method\" ->" "Android answers $method"
  assert_matches "$IOS" "case \"$method\"" "iOS answers $method"
done
assert_matches "$DART" 'setMethodCallHandler' "the app answers the runners"
for method in background stop; do
  assert_matches "$DART" "case '$method'" "the app answers $method"
  assert_prose "$KT/MlChannel.kt" "invokeMethod\\( ?\"$method\"" "Android asks for $method"
  assert_matches "$IOS" "invokeMethod\\(\"$method\"" "iOS asks for $method"
done

for key in battery charging powerSaving thermal temperature memory metered; do
  assert_matches "$KT/DeviceHealth.kt" "\"$key\" to" "Android sends $key"
  assert_matches "$IOS" "\"$key\":" "iOS sends $key"
  assert_matches "$MAC" "\"$key\":" "macOS sends $key"
done
for file in "$KT/DeviceHealth.kt" "$IOS" "$MAC"; do
  assert_matches "$file" '"org.photolib/device_health"' "opens org.photolib/device_health"
done
for file in "$IOS" "$MAC"; do
  assert_matches "$file" '\.fair: (return )?2' "thermal state fair is Android's moderate"
  assert_matches "$file" 'isExpensive \|\| .*isConstrained' "an expensive or constrained network is metered"
done
assert_patterns assert_matches "$KT/DeviceHealth.kt" \
  'totalMem' "Android's memory is the device's" \
  'isActiveNetworkMetered' "and metered the active network's"
assert_matches app/android/app/src/main/AndroidManifest.xml 'android.permission.ACCESS_NETWORK_STATE' \
  "Android may read the network's state"

assert_patterns assert_matches "$KT/MlChannel.kt" \
  'ImageDecoder.ALLOCATOR_SOFTWARE' "Android decodes into memory it reads" \
  'ColorSpace.Named.SRGB' "in sRGB" \
  'setRequiresCharging\(true\)' "runs the backlog while charging" \
  'setRequiresBatteryNotLow\(true\)' "with a battery not low" \
  'WORK = "photolib-ml"' "as one unique work" \
  'enqueue\(context, ExistingWorkPolicy.KEEP\)' "kept while it waits or runs" \
  'PhotolibApplication.engine\(applicationContext\)' "on the process's one engine"
assert_matches app/android/app/build.gradle.kts '"androidx.work:work-runtime-ktx:[0-9.]+"' "WorkManager is a dependency"
assert_matches app/android/app/src/main/AndroidManifest.xml 'android:name=".PhotolibApplication"' \
  "the application hosts the engine"
assert_patterns assert_matches "$KT/PhotolibApplication.kt" \
  'FlutterEngineCache' "keeps it past every activity" \
  'DeviceHealth.register\(' "with the device's state" \
  'MlChannel\(' "and the ML channel"
assert_patterns assert_matches "$KT/MainActivity.kt" \
  'PhotolibApplication.engine\(context\)' "the activity shows that engine" \
  'shouldDestroyEngineWithHost\(\) = false' "and leaves it running"
check "Android makes no engine but in PhotolibApplication.kt" \
  bash -c "! grep -lE '\\bFlutterEngine(Group)?\\s*\\(' $KT/*.kt | grep -v '/PhotolibApplication.kt$'"

assert_patterns assert_matches "$IOS" \
  'isNetworkAccessAllowed = false' "iOS indexes without downloading from iCloud" \
  'CGColorSpace\.sRGB' "in sRGB" \
  'requiresExternalPower = true' "runs the backlog on external power" \
  'guard let channel = MlChannel.channel' "on the app's engine, when there is one" \
  'setTaskCompleted\(success: more != nil\)' "and completes the task with its answer"
assert_matches app/ios/Runner/AppDelegate.swift 'MlBackground\.registerTask\(\)' "the task is registered at launch"
assert_matches app/ios/Runner/AppDelegate.swift 'MlChannel\.register\(' "the app's engine has the ML channel"
assert_prose app/ios/Runner/Info.plist \
  '<key>BGTaskSchedulerPermittedIdentifiers</key>[[:space:]]*<array>[[:space:]]*<string>org.photolib.ml</string>' \
  "iOS permits the task"
assert_prose app/ios/Runner/Info.plist '<key>UIBackgroundModes</key>[[:space:]]*<array>[[:space:]]*<string>processing' \
  "in the processing background mode"
sources=$(sed -n '/Begin PBXSourcesBuildPhase/,/End PBXSourcesBuildPhase/p' app/ios/Runner.xcodeproj/project.pbxproj)
for file in MlChannel NativeLog; do
  [[ $sources == *"/* $file.swift in Sources */"* ]] && ok "iOS builds $file.swift" ||
    fail "iOS does not build $file.swift"
done
check "iOS makes no engine of its own" bash -c "! grep -qE '\\bFlutterEngine(Group)?\\s*\\(' app/ios/Runner/*.swift"
assert_patterns assert_matches "$MAC" \
  '"org.photolib/ml"' "macOS answers the ML channel" \
  'case "schedule", "cancel"' "and indexes in the foreground only"
check "no engine runs another entry point" \
  bash -c "! grep -rqI 'mlBackground' app/lib app/android/app/src app/ios/Runner app/macos/Runner"

finish
