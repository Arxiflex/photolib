#!/usr/bin/env bash
# The privacy manifest (docs/admin/privacy.md) lists every external endpoint and periodic trigger in product code, each
# with a self-hosted alternative, and every run-time path with a kill switch, off by default, a timeout and a
# far-future-date test; `outbound: none` turns them all off (ADR-0058, photolib-design#367).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool git
cd "$REPO_ROOT" || exit 1

CHECK="$REPO_ROOT/tools/tests/check_outbound.py"
capture python3 "$CHECK"
expect_result "the repository's manifest is complete" 0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
RUN='| Connection | Contacts | When | Kill switch | Timeout | Self-hosted alternative | Far-future test | Code |
|---|---|---|---|---|---|---|---|'
BUILD='| Connection | Contacts | Self-hosted alternative | Code |
|---|---|---|---|'
TIMER='| Task | When | Kill switch | Timeout | Far-future test | Code |
|---|---|---|---|---|---|'

# fixture <run-time rows> <build-time rows> [<timer rows>]: a repository with that manifest, a test and a product file
fixture() {
  rm -rf "$TMP/repo"
  mkdir -p "$TMP/repo/docs/admin" "$TMP/repo/app/lib" "$TMP/repo/app/test"
  printf '# Outbound connections\n\n## At run time\n\n%s wins.\n\n%s\n%s\n\n## When building from source\n\n%s\n%s\n' \
    "\`outbound: none\`" "$RUN" "$1" "$BUILD" "$2" >"$TMP/repo/docs/admin/privacy.md"
  printf '\n## On a timer\n\n%s\n%s\n' "$TIMER" "${3:-}" >>"$TMP/repo/docs/admin/privacy.md"
  echo "test('works in 2100', () {});" >"$TMP/repo/app/test/updates_test.dart"
  echo "// See https://dart.dev for the language; http://127.0.0.1:8080 is the proxy." >"$TMP/repo/app/lib/main.dart"
  git -C "$TMP/repo" init -q
}
planned() {
  local name
  for name in "Update check" "Map tiles" "Model download" "Geocoding pack" "Push relay"; do
    echo "| $name | a mirror | opt-in | \`x.y\`, off by default | 10 s | your server | planned | planned in M3-16 |"
  done
}
verdict() {
  capture python3 "$CHECK" "$TMP/repo"
}

fixture "$(planned)" '| Crates | crates.io | a registry mirror | — |'
mkdir -p "$TMP/repo/kernel/src"
echo 'const XMP: &str = "http://ns.adobe.com/xap/1.0/";' >"$TMP/repo/kernel/src/xmp.rs"
mkdir -p "$TMP/repo/server/crates/photolib-media/src"
echo 'const XMP: &[u8] = b"http://ns.adobe.com/xap/1.0/";' >"$TMP/repo/server/crates/photolib-media/src/gainmap.rs"
echo 'let url = format!("http://{}/v1/traces", addr);' >"$TMP/repo/app/lib/traces.rs"
verdict
expect_result \
  "planned paths pass; URLs in comments, on loopback, at a placeholder host, in the pure kernel and as gain map namespaces are not endpoints" 0

fixture "$(planned)" ''
echo "final feed = Uri.parse('https://updates.photolib.example.net/feed');" >"$TMP/repo/app/lib/updates.dart"
echo 'let tiles = "http://tile.openstreetmap.org/{z}";' >"$TMP/repo/app/lib/tiles.rs"
echo 'let store = "endpoint: https://s3.example\n";' >"$TMP/repo/app/lib/store.rs"
verdict
expect_result "an endpoint in product code that the manifest does not list fails" failure \
  "app/lib/tiles.rs contacts tile.openstreetmap.org"
[[ $OUT != *.example* ]] && ok "example domains are not endpoints, even before an escape sequence" ||
  fail "an example domain was reported: $OUT"

fixture "$(planned | sed '1d')
| Update check | the release feed at releases.photolib.app | opt-in, daily | \`updates.check\`, off by default | 10 s | a mirror | \`app/test/updates_test.dart\`: \"works in 2100\" | \`app/lib/updates.dart\` |" ''
printf "final feed = Uri.parse('https://releases.photolib.app/feed');\nTimer.periodic(day, check);\n" \
  >"$TMP/repo/app/lib/updates.dart"
verdict
expect_result "a listed endpoint and trigger with a kill switch, a timeout and a far-future test pass" 0

echo "final stats = Uri.parse('https://stats.photolib.app/');" >>"$TMP/repo/app/lib/updates.dart"
verdict
expect_result "a second endpoint in a listed file fails until its row names the host" failure \
  "app/lib/updates.dart contacts stats.photolib.app, but no row"
sed -i '$d' "$TMP/repo/app/lib/updates.dart"

sed -i 's/works in 2100/works today/' "$TMP/repo/docs/admin/privacy.md"
verdict
expect_result "a far-future test that does not exist fails" failure 'Update check: no test "works today" in app/test/updates_test.dart'

fixture "$(planned)" ''
echo 'tokio::time::interval(Duration::from_secs(60));' >"$TMP/repo/app/lib/purge.rs"
verdict
expect_result "a periodic trigger the manifest does not list fails" failure "app/lib/purge.rs has a periodic trigger"

fixture "$(planned)" ''
mkdir -p "$TMP/repo/app/packages/pool/lib/src/testing"
echo 'Timer.periodic(ms, tick);' >"$TMP/repo/app/packages/pool/lib/testing.dart"
echo "const meter = 'setInterval(tick, 1)';" >"$TMP/repo/app/packages/pool/lib/src/testing/meter.dart"
verdict
expect_result "a timer in a package's lib/testing.dart or lib/src/testing/, for tests only, needs no row" 0

fixture "$(planned)" '' '| Purge | hourly | `roles` | 5 s | `app/test/updates_test.dart`: "works in 2100" | `app/lib/purge.rs` |'
echo 'tokio::time::interval(Duration::from_secs(60));' >"$TMP/repo/app/lib/purge.rs"
verdict
expect_result "a task on a timer with a kill switch, a timeout and a far-future test passes" 0
sed -i 's/| 5 s |/| |/' "$TMP/repo/docs/admin/privacy.md"
verdict
expect_result "a task on a timer without a timeout fails" failure "Purge: no timeout"

fixture "$(planned | sed 's/| .x\.y., off by default |/| |/')" ''
verdict
expect_result "a path without a kill switch fails" failure "Update check: no kill switch"

fixture "$(planned | sed '1s/off by default/on by default/')" ''
verdict
expect_result "a connection on by default fails" failure "Update check: the kill switch must be off by default"

fixture "$(planned)" ''
sed -i '/outbound: none/d' "$TMP/repo/docs/admin/privacy.md"
verdict
expect_result "the manifest must name the master switch" failure "no master switch \`outbound: none\`"

fixture "$(planned | sed '/Push relay/d')" ''
verdict
expect_result "the manifest must cover the push relay" failure "no row for the push relay"

fixture "$(planned | sed 's/planned in M3-16/somewhere/')" ''
verdict
expect_result "a path is either planned in a roadmap item or names its code" failure \
  "Update check: code must be files of this repository, or 'planned …' until then"

finish
