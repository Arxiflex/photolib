#!/usr/bin/env bash
# Debug diagnostics (ADR-0115) as the owner answered (photolib-design#475): the macOS app keeps read-write on the files
# the user picks, and a release build's log is sealed at rest under the vault, plaintext only in debug and profile builds.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0115-debug-diagnostics.md
MODEL=docs/dev/threat-model.md
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner kept [^*]*read-write[^*]*sealed at rest[^*]*photolib-design#475' \
  "is Accepted, recording the owner's answer (#475)" \
  'Seal what a release build keeps.{0,200}PLB envelope under the class C key of the vault.s object .log.' \
  "a release build's log is PLB envelopes under the vault's class C key" \
  'in browsers each record of .photolib/log..s .sealed. store is such an envelope' "and each browser record one" \
  'Debug and profile builds keep (it|the log) in the clear' "debug and profile builds stay plaintext"
assert_matches docs/adr/README.md '\(0115-debug-diagnostics\.md\) \| [^|]* \| Accepted \([^|]*sealed[^|]*2026-10-20\)' \
  "the index lists ADR-0115 as Accepted"
if plain=$(grep -niE 'log on (a|the) device is plaintext' "$ADR" "$MODEL"); then fail "still plaintext: $plain"; else
  ok "no document calls the device's log plaintext"
fi
assert_prose "$MODEL" '\| T70 \|[^|]*\|[^|]*\|[^|]*\|[^|]*\|[^|]*seal the log at rest under the vault' \
  "T70: a release build's log is sealed at rest"
assert_prose "$MODEL" '\| T70 \|[^|]*\|[^|]*\|[^|]*\|[^|]*\|[^|]*\|[^|]*app/test/core/log_native_test\.dart' \
  "T70 cites the sealed log's test"
assert_prose app/lib/core/providers.dart 'ref\.read\(releaseBuildProvider\) \? vaultSeal\(' \
  "release builds seal the log store"
for build in DebugProfile Release; do
  assert_prose "app/macos/Runner/$build.entitlements" '<key>com\.apple\.security\.files\.user-selected\.read-write</key>' \
    "macOS keeps read-write on the files the user picks"
done
assert_prose AGENTS.md 'release builds seal it under the vault' "AGENTS.md says the release log is sealed"
assert_prose docs/user/README.md 'Released versions [^.]*keep the log encrypted on the device' \
  "the user guide says a released version's log is encrypted"

finish
