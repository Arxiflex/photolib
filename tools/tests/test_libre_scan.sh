#!/usr/bin/env bash
# The proprietary-dependency scan of the libre (F-Droid) Android flavour: tools/scan_libre.py fails on Google Play
# Services, Firebase, ML Kit, Play billing/core and Huawei services in dependency listings and built APKs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

SCAN="$REPO_ROOT/tools/scan_libre.py"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

scan() {
  capture python3 "$SCAN" "$@"
}

passes() {
  local description=$1
  shift
  scan "$@"
  expect_result "accepts $description" 0
}

flags() {
  local description=$1 needle=$2
  shift 2
  scan "$@"
  expect_result "flags $description" 1 "$needle"
}

# gradle <coordinate>: a Gradle dependency tree that holds the coordinate next to free dependencies.
gradle() {
  printf 'releaseRuntimeClasspath\n+--- androidx.core:core:1.13.1\n+--- org.jetbrains.kotlin:kotlin-stdlib:2.0.0\n+--- com.google.guava:guava:33.0.0\n+--- com.google.protobuf:protobuf-javalite:4.26.1\n\\--- %s\n' "$1" >"$TMP/deps.txt"
}

# apk <entry> <content>: an APK (a zip) with one entry besides a clean classes.dex.
apk() {
  python3 - "$TMP/app.apk" "$1" "$2" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("classes.dex", b"dex\n035\0Landroidx/core/Foo;\0Lcom/google/common/collect/Lists;\0")
    z.writestr(sys.argv[2], sys.argv[3])
PY
}

gradle "androidx.appcompat:appcompat:1.7.0"
passes "a dependency tree without proprietary components (Guava and protobuf are Google but free)" "$TMP/deps.txt"
for coordinate in com.google.android.gms:play-services-base:18.0.0 com.google.firebase:firebase-messaging:24.0.0 \
  com.google.mlkit:text-recognition:16.0.0 com.google.android.play:core:1.10.3 com.android.billingclient:billing:7.0.0 \
  com.huawei.hms:push:6.0.0; do
  gradle "$coordinate"
  flags "$coordinate in a dependency tree" "${coordinate%%:*}" "$TMP/deps.txt"
done

printf 'packages:\n  async:\n    dependency: transitive\n  sqlite3:\n    dependency: direct main\n' >"$TMP/pubspec.lock"
passes "a pubspec.lock without proprietary plugins" "$TMP/pubspec.lock"
for plugin in firebase_core google_mlkit_text_recognition google_maps_flutter google_sign_in in_app_purchase_android; do
  printf 'packages:\n  async:\n    dependency: transitive\n  %s:\n    dependency: direct main\n' "$plugin" >"$TMP/pubspec.lock"
  flags "the $plugin plugin in pubspec.lock" "$plugin" "$TMP/pubspec.lock"
done

apk "res/raw/ok.txt" "nothing to see"
passes "an APK without proprietary classes or resources" "$TMP/app.apk"
apk "classes2.dex" $'Lcom/google/android/gms/common/api/Api;\0'
flags "a Play Services class in a dex file" "com/google/android/gms" "$TMP/app.apk"
apk "META-INF/com/google/firebase/firebase-core.version" "1.0"
flags "a Firebase resource in an APK" "com/google/firebase" "$TMP/app.apk"

scan
expect_result "needs at least one file" 2
scan "$TMP/missing.txt"
expect_result "a missing file is an error, not a pass" 2

finish
