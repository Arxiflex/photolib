#!/usr/bin/env bash
# macOS keeps Impeller (ADR-0252) though the pinned engine's back-buffer cache can hand it a surface of the wrong size
# when the app comes back to the foreground (flutter/flutter#185394), until the pin carries flutter/flutter#192522.
# This names the pin and whether it carries the fix, and fails when app/.fvmrc moves until the record below and the
# macOS known issue in the release notes follow it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

# The last pin checked, whether it carries the fix, and where upstream stood then: update all three with app/.fvmrc.
CHECKED=3.47.7 HAS=lacks
UPSTREAM='open, in team-macos review on 2026-10-21'
NOTES=docs/user/release-notes.md ME=tools/tests/test_macos_impeller.sh
SURFACES=engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterSurfaceManager.mm

if grep -q FLTEnableImpeller app/macos/Runner/Info.plist; then
  fail "app/macos/Runner/Info.plist sets FLTEnableImpeller: macOS keeps Impeller (ADR-0252)"
else
  ok "app/macos/Runner/Info.plist leaves Impeller on"
fi
assert_matches docs/adr/0220-macos-skia-until-185394.md '^\* \*\*Status\*\*: Superseded by \[ADR-0252\]' \
  "is superseded by ADR-0252"

# engine <FlutterSurfaceManager.mm>: "carries" once removeSurfaceForSize: or returnSurfaces: reads the size of a surface
# other than the first cached one, as flutter/flutter#192522 does, else "lacks".
engine() {
  local hand keep
  hand=$(sed -n '/^- (.*)removeSurfaceForSize:/,/^}/p' "$1" | grep -v '^ *//' | sed 's/_surfaces\.firstObject\.size//g')
  keep=$(sed -n '/^- (.*)returnSurfaces:/,/^}/p' "$1" | grep -v '^ *//')
  [[ -n $hand && -n $keep ]] || { echo "$1 defines no removeSurfaceForSize: or returnSurfaces:"; return 1; }
  if grep -Eq '\.size([^[:alnum:]_]|$)' <<<"$hand$keep"; then echo carries; else echo lacks; fi
}

# listed <notes>: the release notes list the macOS foreground crash as a known issue, with its workaround.
listed() { tr '\n' ' ' <"$1" | grep -Eqi 'Known issues.*macOS.*flutter/flutter#185394.*quit.*reopen'; }

# track <pin> <release notes> <Flutter root>...: whether the pin carries the fix, read from its engine in the first
# root that has its source, else from the record.
track() {
  local pin=$1 notes=$2 root state='' from=recorded pr=https://github.com/flutter/flutter/pull/192522
  shift 2
  for root; do
    [[ -f $root/$SURFACES ]] || continue
    state=$(engine "$root/$SURFACES") || { echo "$state: read $pr by hand"; return 1; }
    from='its engine shows'
    break
  done
  if [[ $pin != "$CHECKED" ]]; then
    case $state in
      lacks) echo "Flutter $pin still lacks flutter/flutter#192522 (upstream: $UPSTREAM): read $pr, keep the macOS" \
        "known issue in $notes and record $pin and the status in $ME" ;;
      carries) echo "Flutter $pin carries flutter/flutter#192522: run the macOS smoke (hide and show the window 20" \
        "times, a 360° video plays), drop the known issue from $notes and record $pin in $ME" ;;
      *) echo "Flutter $pin may lack flutter/flutter#192522 (upstream: $UPSTREAM; $CHECKED $HAS it): install it" \
        "(/opt/flutter-$pin or fvm install $pin) to read its engine, or read $pr, and record $pin" ;;
    esac
    return 1
  fi
  if [[ -n $state && $state != "$HAS" ]]; then
    echo "Flutter $pin's engine $state flutter/flutter#192522, but $ME says it $HAS it"
    return 1
  fi
  if [[ $HAS == lacks ]] && ! listed "$notes"; then
    echo "$notes must list the macOS foreground crash (flutter/flutter#185394) as a known issue, quit and reopen as" \
      "its workaround, while Flutter $pin lacks flutter/flutter#192522"
    return 1
  fi
  if [[ $HAS == carries ]] && listed "$notes"; then
    echo "Flutter $pin carries flutter/flutter#192522: drop the macOS known issue from $notes"
    return 1
  fi
  echo "Flutter $pin $HAS flutter/flutter#192522 (upstream: $UPSTREAM), as $from"
}

PIN=$(sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' app/.fvmrc)
ROOTS=("/opt/flutter-$PIN" "${FVM_CACHE_PATH:-$HOME/fvm}/versions/$PIN")
capture track "$PIN" "$NOTES" "${ROOTS[@]}"
[[ $STATUS -eq 0 ]] && ok "$OUT" || fail "$OUT"

FAKE=$(mktemp -d)
trap 'rm -rf "$FAKE"' EXIT
capture track "$CHECKED" "$NOTES" "$FAKE/none"
expect_result "without the pin's source the record says" 0 "Flutter $CHECKED $HAS flutter/flutter#192522" "as recorded"
capture track 9.9.9 "$NOTES" "$FAKE/none"
expect_result "a moved pin without its source fails with the upstream status" failure \
  "Flutter 9.9.9 may lack flutter/flutter#192522 (upstream: $UPSTREAM;"
printf '# Release notes\n' >"$FAKE/notes.md"
capture track "$CHECKED" "$FAKE/notes.md"
expect_result "release notes without the known issue fail while the pin lacks the fix" failure \
  "must list the macOS foreground crash"
HAS=carries capture track "$CHECKED" "$NOTES"
expect_result "the known issue fails once the pin carries the fix" failure "drop the macOS known issue"

real=
for root in "${ROOTS[@]}"; do [[ -f $root/$SURFACES ]] && real=$root/$SURFACES && break; done
# fake <version> <sed script>: a Flutter root whose FlutterSurfaceManager.mm is the pin's, edited by the script.
fake() {
  mkdir -p "$(dirname "$FAKE/$1/$SURFACES")"
  sed "$2" "$real" >"$FAKE/$1/$SURFACES"
}
if [[ -n $real ]]; then
  fake 3.48.0 ''
  capture track 3.48.0 "$NOTES" "$FAKE/3.48.0"
  expect_result "a moved pin that still lacks the fix fails with the upstream status" failure \
    "Flutter 3.48.0 still lacks flutter/flutter#192522 (upstream: $UPSTREAM)"
  # flutter/flutter#192522: returned surfaces of another size than the cached ones are dropped.
  fake drops-other-sizes '/^- (void)returnSurfaces:/,/@synchronized/ s/@synchronized(self) {/&\
    if (!CGSizeEqualToSize(returnedSurfaces.firstObject.size, _surfaces.firstObject.size)) { return; }/'
  fake hands-out-its-size 's/if (!surface\.isInUse \&\&/& CGSizeEqualToSize(surface.size, size) \&\&/'
  for fixed in drops-other-sizes hands-out-its-size; do
    cmp -s "$real" "$FAKE/$fixed/$SURFACES" && fail "the $fixed fixture no longer edits $real"
    capture track "$fixed" "$NOTES" "$FAKE/$fixed"
    expect_result "a moved pin whose cache $fixed asks for the macOS smoke" failure \
      "Flutter $fixed carries flutter/flutter#192522: run the macOS smoke (hide and show the window 20 times"
    capture track "$CHECKED" "$NOTES" "$FAKE/$fixed"
    expect_result "an engine whose cache $fixed contradicts the record" failure "engine carries flutter/flutter#192522"
  done
  fake renamed 's/removeSurfaceForSize:/takeSurfaceForSize:/'
  capture track renamed "$NOTES" "$FAKE/renamed"
  expect_result "fails when it cannot find the cache's methods" failure "defines no removeSurfaceForSize:"
fi

finish
