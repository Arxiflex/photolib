#!/usr/bin/env bash
# The runners' diagnostics reach the app's log (ADR-0115): Android, macOS and Windows keep what they log until
# listenToNativeLog (app/lib/core/logging.dart) listens on org.photolib/log, then send each record. The gate compiles
# no Kotlin, Swift or C++, so they are checked as text against the Dart; the smoke tests build and run them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

DART=app/lib/core/logging.dart
KT=app/android/app/src/main/kotlin/org/photolib/photolib
MAC=app/macos/Runner
WIN=app/windows/runner

assert_patterns assert_matches "$DART" \
  "MethodChannel\('org.photolib/log'\)" "the app listens on org.photolib/log" \
  "invokeListMethod<Object\?>\('listen'\)" "takes what was logged before it listened" \
  "final int ms," "reads a record as time, level, logger, message and fields"
assert_matches app/lib/main.dart 'listenToNativeLog\(\)' "the app starts listening at start"

for file in "$KT/NativeLog.kt" "$MAC/NativeLog.swift" "$WIN/native_log.cpp"; do
  assert_patterns assert_matches "$file" \
    '"org.photolib/log"' "opens the log channel" \
    '"listen"' "answers listen with what it kept" \
    'invokeMethod\("log"|InvokeMethod\("log"' "then sends each record as log" \
    '1000' "keeping at most 1000 records until the app listens"
done
assert_patterns assert_matches "$KT/NativeLog.kt" \
  'System.currentTimeMillis\(\), level, logger, message, fields' "Android sends time, level, logger, message, fields"
assert_patterns assert_matches "$MAC/NativeLog.swift" \
  '\[Int\(Date\(\).timeIntervalSince1970 \* 1000\), level, logger, message, fields\]' "macOS sends the same record"
assert_patterns assert_matches "$WIN/native_log.cpp" \
  'EncodableValue\(ms\), EncodableValue\(level\), EncodableValue\(logger\)' "Windows sends the same record"

assert_matches "$KT/PhotolibApplication.kt" 'NativeLog.register\(' "Android registers the log with its one engine"
assert_matches "$KT/ThumbnailChannel.kt" 'NativeLog.log\(' "MediaStore's thumbnail failures, which the channel answers with nil, are logged"
assert_matches "$KT/ViewerChannel.kt" 'NativeLog.log\(' "the viewer channel's failures are logged with their exception"
assert_matches "$MAC/MainFlutterWindow.swift" 'NativeLog.shared.register\(' "macOS registers the log"
assert_matches app/macos/Runner.xcodeproj/project.pbxproj 'NativeLog.swift in Sources' "and builds NativeLog.swift"
assert_patterns assert_matches "$MAC/FolderAccess.swift" \
  '"bookmark does not resolve"' "a bookmark that does not resolve at start is logged with its error" \
  '"folder not readable"' "so is a folder the sandbox does not open" \
  '"stale bookmark renewed"' "a stale bookmark renewed" \
  '"stale bookmark not renewed"' "or not renewed" \
  '"bookmark not made"' "and a folder kept without a bookmark"
check "$MAC/FolderAccess.swift: no bookmark error is dropped with try?" \
  bash -c "! grep -q 'try?' '$REPO_ROOT/$MAC/FolderAccess.swift'"
assert_matches "$WIN/flutter_window.cpp" 'RegisterNativeLog\(' "Windows registers the log"
assert_matches "$WIN/CMakeLists.txt" '"native_log.cpp"' "and builds native_log.cpp"
assert_matches "$WIN/thumbnail_channel.cpp" 'NativeLog\(' "a file no decoder reads is logged with the HRESULTs of both"

finish
