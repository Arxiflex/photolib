#!/usr/bin/env bash
# The Android default-gallery spike (M0-31): the matrix of behaviour × Android version × OEM, the ADR on what is
# supported as the owner confirmed it (photolib-design#332), and the device probe that fills the matrix's open cells.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

MATRIX=docs/dev/android-gallery.md
ADR=docs/adr/0039-android-default-gallery.md

# --- the matrix: a column per Android version from the app's minSdk and per OEM, a row per behaviour of the issue
min_sdk=$(sed -nE 's/^ *minSdk = ([0-9]+)$/\1/p' app/android/app/build.gradle.kts)
header="| Behaviour | 11 (API $min_sdk) | 12 (API 31–32) | 13 (API 33) | 14 (API 34) | 15 (API 35) | 16 (API 36) | 17 (API 37) | Pixel | Samsung | Xiaomi |"
check "$MATRIX: the matrix starts at minSdk $min_sdk and has a column per version and OEM" grep -qxF "$header" "$MATRIX"
rows=$(awk -v h="$header" '$0 == h { on = 1; next } on && !/^\|/ { exit } on && !/^\|---/' "$MATRIX" 2>/dev/null)
for behaviour in '`VIEW`' '`EDIT`' '`PICK`' '`GET_CONTENT`' '`SEND`' '`REVIEW`' '`REVIEW_SECURE`' 'Generation sync' \
  'Trash request' 'Favourite request' 'Delete request' '`MANAGE_MEDIA`' 'Partial access' 'SD cards'; do
  grep -qE "^\| [^|]*$behaviour" <<<"$rows" && ok "$MATRIX: has a row for $behaviour" ||
    fail "$MATRIX: no matrix row for $behaviour"
done
bad=$(awk -F'|' -v n="$(awk -F'|' '{ print NF }' <<<"$header")" 'NF != n' <<<"$rows")
[[ -n $rows && -z $bad ]] && ok "$MATRIX: every row has a cell per column" || fail "$MATRIX: rows with missing cells: $bad"
for camera in 'Pixel Camera' 'Samsung Camera' 'Xiaomi Camera' 'Motorola Camera' 'Aperture' 'Open Camera'; do
  assert_matches "$MATRIX" "^\| $camera" "the hand-off table has a row for $camera"
done
assert_patterns assert_prose "$MATRIX" \
  '2,000 URIs' "records the request size limit of target API 36" \
  'MANAGE_MEDIA[^.]*ACCESS_MEDIA_LOCATION' "records that dialog-free writes also need ACCESS_MEDIA_LOCATION" \
  'READ_MEDIA_VISUAL_USER_SELECTED' "records the partial-access permission" \
  'no MIME type' "records Xiaomi's typeless VIEW" \
  'queryDeletedFiles' "records the deletion feed" \
  'markIsFavoriteStatus' "records dialog-free favourites" \
  'bash tools/android/gallery_probe\.sh' "explains how a device run fills the open cells" \
  '\(\.\./adr/0039-android-default-gallery\.md\)' "links the decision"
assert_prose docs/dev/README.md '\(android-gallery\.md\)' "the developer guide links the matrix"

# --- the decision
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16[^*]*owner confirmed[^*]*photolib-design#332' \
  "is Accepted, recording the owner's confirmation (#332)"
assert_matches docs/adr/README.md '\(0039-android-default-gallery\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0039 as Accepted"
assert_patterns assert_prose "$ADR" \
  '\(\.\./dev/android-gallery\.md\)' "links the matrix" \
  'We will keep API 30' "confirms the API 30 floor that design 10 §1.1 left to this spike" \
  'not promise[^.]*Pixel[^.]*Samsung[^.]*Xiaomi[^.]*Motorola: onboarding names the default camera' \
  "does not promise the stock cameras' review hand-off; onboarding names the default camera" \
  'MANAGE_EXTERNAL_STORAGE' "rules out all-files access"
assert_prose AGENTS.md 'android-gallery\.md.*gallery_probe\.sh' "AGENTS.md names the matrix and the probe"
assert_prose tools/README.md 'android/gallery_probe\.sh' "tools/README.md names the probe"

# --- the probe, against a stubbed adb
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/adb" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
case "$*" in
  get-state) [[ -z ${STUB_OFFLINE:-} ]] || { echo "error: no devices/emulators found" >&2; exit 1; }; echo device ;;
  "shell getprop ro.product.manufacturer") printf 'Google\r\n' ;;
  "shell getprop ro.product.model") printf 'Pixel 8\r\n' ;;
  "shell getprop ro.build.version.release") printf '16\r\n' ;;
  "shell getprop ro.build.version.sdk") printf '36\r\n' ;;
  "shell getprop ro.build.display.id") printf 'BP2A.250605.031\r\n' ;;
  "shell cmd package query-activities --components -a android.provider.action.REVIEW "*)
    printf 'com.google.android.apps.photos/.ReviewActivity\r\norg.fossify.gallery/.activities.ViewPagerActivity\r\n' ;;
  "shell cmd package query-activities --components "*) printf 'No activities found\r\n' ;;
  "shell cmd package resolve-activity --brief -a android.media.action.STILL_IMAGE_CAMERA")
    printf 'priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\r\n'
    printf 'com.google.android.GoogleCamera/com.android.camera.CameraLauncher\r\n' ;;
  "shell cmd package resolve-activity --brief -a android.provider.action.REVIEW "*)
    printf 'priority=0 preferredOrder=0 match=0x608000 specificIndex=-1 isDefault=false\r\n'
    printf 'android/com.android.internal.app.ResolverActivity\r\n' ;;
  "shell cmd package resolve-activity --brief "*) printf 'No activity found\r\n' ;;
  "shell appops get "*" MANAGE_MEDIA") printf 'MANAGE_MEDIA: allow; time=+2d1h\r\n' ;;
  "shell logcat -d -s ActivityTaskManager:I")
    printf '10-16 09:00:01.000  1000  1200 I ActivityTaskManager: START u0 {act=android.intent.action.MAIN cat=[android.intent.category.HOME] cmp=com.google.android.apps.nexuslauncher/.NexusLauncherActivity} from uid 1000\r\n'
    printf '10-16 09:00:02.000  1000  1200 I ActivityTaskManager: START u0 {act=android.provider.action.REVIEW dat=content://media/... typ=image/jpeg cmp=com.google.android.apps.photos/.ReviewActivity} from uid 10123\r\n' ;;
  *) echo "adb stub: unexpected $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/adb"
export STUB_LOG=$TMP/calls.log
probe() { : >"$STUB_LOG"; capture env PATH="$TMP:$PATH" bash tools/android/gallery_probe.sh "$@"; }

probe
expect_result "the probe prints a device's row" 0 \
  "## Google Pixel 8, Android 16 (API 36), BP2A.250605.031" \
  "Default camera: com.google.android.GoogleCamera/com.android.camera.CameraLauncher" \
  "| REVIEW image/jpeg | 2 | android/com.android.internal.app.ResolverActivity |" \
  "| VIEW content://media, no MIME type | 0 | No activity found |" \
  "MANAGE_MEDIA for org.photolib.photolib: MANAGE_MEDIA: allow; time=+2d1h" \
  "START u0 {act=android.provider.action.REVIEW"
for label in "VIEW image/jpeg" "VIEW video/mp4" "REVIEW_SECURE image/jpeg" "legacy REVIEW image/jpeg" "PICK image/*" \
  "GET_CONTENT image/*" "SEND image/jpeg" "SEND_MULTIPLE image/*" "EDIT image/jpeg" "ATTACH_DATA image/jpeg" \
  "MAIN APP_GALLERY"; do
  [[ $OUT == *"| $label | 0 | No activity found |"* ]] && ok "the probe resolves $label" ||
    fail "the probe has no row for $label: $OUT"
done
[[ $STATUS -eq 0 && $OUT != *$'\r'* && $OUT != *"cat=[android.intent.category.HOME]"* ]] &&
  ok "the probe strips carriage returns and lists only gallery hand-offs" || fail "probe output: $OUT"
grep -qxF "shell cmd package query-activities --components -a android.intent.action.PICK -t 'image/*'" "$STUB_LOG" &&
  ok "the probe quotes MIME wildcards for the device shell" || fail "unquoted wildcard: $(cat "$STUB_LOG")"
probe com.example.gallery
[[ $OUT == *"MANAGE_MEDIA for com.example.gallery: "* ]] && grep -qx 'shell appops get com.example.gallery MANAGE_MEDIA' \
  "$STUB_LOG" && ok "the probe checks MANAGE_MEDIA for the package it is given" || fail "package argument: $OUT"
STUB_OFFLINE=1 probe
expect_result "the probe fails without a device" failure "no devices"

finish
