#!/usr/bin/env bash
# Prints one phone's section of docs/dev/android-gallery.md over adb (ANDROID_SERIAL picks one of several). Tap the
# camera's thumbnail first, so the log holds its intent.
#   bash tools/android/gallery_probe.sh [package]   (default org.photolib.photolib)
set -euo pipefail

PACKAGE=${1:-org.photolib.photolib}
IMAGE=content://media/external/images/media/1
INTENTS=(
  "VIEW image/jpeg|-a android.intent.action.VIEW -d $IMAGE -t image/jpeg"
  "VIEW video/mp4|-a android.intent.action.VIEW -d content://media/external/video/media/1 -t video/mp4"
  "VIEW content://media, no MIME type|-a android.intent.action.VIEW -d $IMAGE"
  "REVIEW image/jpeg|-a android.provider.action.REVIEW -d $IMAGE -t image/jpeg"
  "legacy REVIEW image/jpeg|-a com.android.camera.action.REVIEW -d $IMAGE -t image/jpeg"
  "REVIEW_SECURE image/jpeg|-a android.provider.action.REVIEW_SECURE -d $IMAGE -t image/jpeg"
  "PICK image/*|-a android.intent.action.PICK -t 'image/*'"
  "GET_CONTENT image/*|-a android.intent.action.GET_CONTENT -c android.intent.category.OPENABLE -t 'image/*'"
  "SEND image/jpeg|-a android.intent.action.SEND -t image/jpeg"
  "SEND_MULTIPLE image/*|-a android.intent.action.SEND_MULTIPLE -t 'image/*'"
  "EDIT image/jpeg|-a android.intent.action.EDIT -d $IMAGE -t image/jpeg"
  "ATTACH_DATA image/jpeg|-a android.intent.action.ATTACH_DATA -d $IMAGE -t image/jpeg"
  "MAIN APP_GALLERY|-a android.intent.action.MAIN -c android.intent.category.APP_GALLERY"
)

device() { adb shell "$@" | tr -d '\r'; }

adb get-state >/dev/null
echo "## $(device getprop ro.product.manufacturer) $(device getprop ro.product.model)," \
  "Android $(device getprop ro.build.version.release) (API $(device getprop ro.build.version.sdk))," \
  "$(device getprop ro.build.display.id)"
echo
echo "Default camera: $(device cmd package resolve-activity --brief -a android.media.action.STILL_IMAGE_CAMERA | tail -1)"
echo
echo "| Intent | Handlers | Default |"
echo "|---|---|---|"
for entry in "${INTENTS[@]}"; do
  intent=${entry#*|}
  handlers=$(device cmd package query-activities --components "$intent" | grep -c / || true)
  echo "| ${entry%%|*} | $handlers | $(device cmd package resolve-activity --brief "$intent" | tail -1) |"
done
echo
echo "MANAGE_MEDIA for $PACKAGE: $(device appops get "$PACKAGE" MANAGE_MEDIA 2>&1 | head -1)"
echo
echo '```text'
device logcat -d -s ActivityTaskManager:I | grep -E 'START u0 .*(REVIEW|dat=content://media)' | tail -5 || true
echo '```'
