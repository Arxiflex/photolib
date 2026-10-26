#!/usr/bin/env bash
# tools/desktop/single_instance.sh (ADR-0206): a second start of the Linux app hands the running one a photo, then a
# photolib: link, and ends, and the first takes each as a drop and stays up. The apps are stand-ins here that log as
# the app does; package.sh runs it on a profile build and the AppImage's release build.
# shellcheck disable=SC2016 # the stand-ins expand their own $variables when they run
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# A display, a session bus of its own and an unlocked keyring on it: the stand-ins need none.
for tool in xvfb-run dbus-run-session; do
  printf '#!/usr/bin/env bash\necho "%s $1" >>"$CALLS"\nshift; [[ $1 == -- ]] && shift\nexec "$@"\n' "$tool" \
    >"$TMP/bin/$tool"
done
printf '#!/usr/bin/env bash\necho "gnome-keyring-daemon $* <$(cat)>" >>"$CALLS"\nexec sleep 60 >&-\n' \
  >"$TMP/bin/gnome-keyring-daemon"
# A miss of the first start's log takes a second, in which a first start that ends logs and ends: the poll must look
# once more before it says the first never logged (photolib-design#659: it did so on a loaded machine).
printf '#!/usr/bin/env bash\n%q "$@" && exit\n%s\nexit 1\n' "$(command -v grep)" \
  '[[ -z ${MISSED:-} || -e $MISSED ]] || { touch "$MISSED"; sleep 1; }' >"$TMP/bin/grep"
chmod +x "$TMP/bin/"*
# app [file|link]: the first start logs that it starts, then waits; a later one hands over its argument, as $SECOND
# says.
cat >"$TMP/bin/app" <<'APP'
#!/usr/bin/env bash
log=$XDG_DATA_HOME/org.photolib.photolib/logs/photolib.log
mkdir -p "$(dirname "$log")"
if (($# == 0)); then
  [[ ${FIRST:-} == ends ]] && until [[ -e $MISSED ]]; do sleep 0.05; done
  echo '{"logger":"photolib.app","message":"starting"}' >>"$log"
  [[ ${FIRST:-} == ends ]] && exit 0
  exec sleep 60
fi
# paths: as the runners did, it hands over only files.
case ${SECOND:-hands}:$1 in
  hands:photolib:/password-setup\?*token=*) echo '{"message":"dropped","fields":{"links":1}}' >>"$log" ;;
  hands:/* | paths:/*) [[ -f $1 ]] && echo '{"message":"dropped","fields":{"links":0}}' >>"$log" ;;
  stays:*) exec sleep 60 ;;
esac
APP
chmod +x "$TMP/bin/app"

run() {
  export CALLS=$TMP/calls
  : >"$CALLS"
  capture env PATH="$TMP/bin:$PATH" bash tools/desktop/single_instance.sh "$@"
}

run
expect_result "it needs the two starts" 2 "usage: single_instance.sh <first> <second>"

run "$TMP/bin/app" "$TMP/bin/app"
expect_result "a second start that hands the first a photo and a link passes" 0
keyring='gnome-keyring-daemon --foreground --unlock --components=secrets <photolib>'
[[ $(<"$CALLS") == $'dbus-run-session --\n'"$keyring"$'\nxvfb-run -a' ]] &&
  ok "on a display and a session bus of their own, with an unlocked keyring" ||
  fail "not on a display and a bus of their own with a keyring: $(<"$CALLS")"

SECOND=stays run "$TMP/bin/app" "$TMP/bin/app"
expect_result "a second start that stays up fails" failure "the second start did not end at once"

SECOND=drops run "$TMP/bin/app" "$TMP/bin/app"
expect_result "a photo the first never takes fails" failure 'the first start never logged "message":"dropped"'

SECOND=paths run "$TMP/bin/app" "$TMP/bin/app"
expect_result "a link the first never takes fails" failure 'the first start never logged "links":1'

FIRST=ends MISSED=$TMP/missed run "$TMP/bin/app" "$TMP/bin/app"
expect_result "a first start that ends fails" failure "the first start ended"

finish
