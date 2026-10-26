#!/usr/bin/env bash
# The error catalogue (OPS-30, photolib-design#470): every reason photolibd sends has a cause and a next step in
# every language, and no user-facing text shows a bare code, an exception class or a stack frame.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

CHECK="$REPO_ROOT/tools/tests/check_errors.py"
capture python3 "$CHECK"
expect_result "the repository's catalogue is complete" 0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"

# fixture: a server with one reason sent directly and one through a helper, its catalogue and two languages
fixture() {
  rm -rf "$R"
  mkdir -p "$R/server/crates/s/src" "$R/app/lib/core" "$R/app/lib/l10n" "$R/viewer/src"
  cat >"$R/server/crates/s/src/a.rs" <<'EOF'
fn gone() -> ApiError { ApiError::new(ErrorCode::NotFound, "user.not_found") }
fn precondition(reason: &'static str) -> ConnectError {
    ApiError::new(ErrorCode::FailedPrecondition, reason).into()
}
fn busy() -> ConnectError { precondition("library.scanning") }
EOF
  cat >"$R/app/lib/core/problems.dart" <<'EOF'
final reasons = {
  'user.not_found': (s) => (s.problemGone, s.nextRefresh),
  'library.scanning': (s) =>
      (s.problemScanning, s.nextWait),
};
EOF
  for locale in en de en_XA; do
    printf '{"problemGone": "It is gone", "nextRefresh": "Refresh", "problemScanning": "Scanning", "nextWait": "Wait"}' \
      >"$R/app/lib/l10n/app_$locale.arb"
  done
  echo "Text(s.title);" >"$R/app/lib/page.dart"
  echo "out.textContent = label;" >"$R/viewer/src/page.ts"
}
verdict() { capture python3 "$CHECK" "$R"; }

fixture
verdict
expect_result "reasons sent directly and through a helper, each with a cause and next step everywhere, pass" 0

fixture
echo 'fn x() -> ApiError { ApiError::new(ErrorCode::Unavailable, "store.unavailable") }' >>"$R/server/crates/s/src/a.rs"
verdict
expect_result "a reason without an entry fails" failure \
  "server/crates/s/src/a.rs sends store.unavailable, which app/lib/core/problems.dart has no cause and next step for"

fixture
sed -i 's/precondition("library.scanning")/precondition("library.busy")/' "$R/server/crates/s/src/a.rs"
verdict
expect_result "a reason sent through a helper is found, and a stale entry fails" failure \
  "app/lib/core/problems.dart: library.scanning is no reason photolibd sends"

fixture
printf '{"problemGone": "Weg", "nextRefresh": "", "problemScanning": "Scan", "nextWait": "Warte"}' >"$R/app/lib/l10n/app_de.arb"
verdict
expect_result "a next step missing in a language fails; the pseudo-locales are made from English" failure \
  "app_de.arb: no nextRefresh, the next step of user.not_found"

for value in "Failed: user.not_found" "permission_denied" "SocketException: refused" "error 117" "Fehler 117" \
  "at Server.call (server.dart:12)" "HTTP 502"; do
  fixture
  printf '{"problemGone": "%s", "nextRefresh": "Refresh", "problemScanning": "Scanning", "nextWait": "Wait"}' \
    "$value" >"$R/app/lib/l10n/app_de.arb"
  verdict
  expect_result "a message that shows '$value' fails" failure "app_de.arb problemGone: shows"
done

fixture
printf '{"problemGone": "Not found at photos.example.org: 100 MB over the limit", "nextRefresh": "Refresh", "problemScanning": "Scanning", "nextWait": "Wait"}' \
  >"$R/app/lib/l10n/app_de.arb"
verdict
expect_result "addresses, sizes and plain words pass" 0

for line in "Text('\$error');" "Text(error.toString());" "SnackBar(content: Text('Failed: \${e.message}'));" \
  "ListTile(title: Text(s.x), subtitle: Text('\$error'));"; do
  fixture
  printf '%s\n' "$line" >"$R/app/lib/page.dart"
  verdict
  expect_result "Dart that shows a raw error ($line) fails" failure "app/lib/page.dart:1: shows a raw error"
done

fixture
printf '%s\n' "Tooltip(message: switch (error) {" "  _ => '\$error', // error-ok: the cause, behind a long press" "});" \
  "_log.warning('failed', fields: {'cause': '\$error'});" "throw StateError('\$error');" \
  "reply.send(error is OrtException ? error.message : '\$error');" >"$R/app/lib/page.dart"
verdict
expect_result "a raw error said to be on purpose, in a log, in an exception or sent to an isolate passes" 0

fixture
# shellcheck disable=SC2016 # the TypeScript under test, literally
echo 'status.textContent = `Failed: ${error}`;' >"$R/viewer/src/page.ts"
verdict
expect_result "TypeScript that shows a raw error fails" failure "viewer/src/page.ts:1: shows a raw error"

finish
