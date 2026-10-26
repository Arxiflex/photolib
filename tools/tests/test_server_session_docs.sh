#!/usr/bin/env bash
# The server and its session in the store (ADR-0209) as the owner kept it (photolib-design#598): the vault's class B
# `server` object on every platform, with the one-time move out of the keystore.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0209-server-session-in-the-store.md
SERVERS=app/lib/features/servers/servers.dart
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-21 \(photolib-design#568\)\. The owner kept [^*]*photolib-design#598' \
  "is Accepted, recording the owner's answer (#598)"
assert_matches docs/adr/README.md \
  '\(0209-server-session-in-the-store\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-21\)' \
  "the index lists ADR-0209 as Accepted"
assert_prose "$SERVERS" \
  "_Moved\( const KeystoreEntry\('server'\), VaultText\(\(\) => vault, 'server', KeyClass\.b\), \)" \
  "the store is the vault's class B 'server' object, taking over the keystore entry"
assert_prose "$SERVERS" 'await _to\.write\(held\); await _from\.write\(null\);' "the move deletes the keystore entry"
assert_matches docs/dev/threat-model.md \
  '^\| T4 \|.*its server and session are sealed objects of its store \(.*ADR-0209\)' \
  "threat model T4 keeps the session sealed in the store"
assert_matches docs/dev/threat-model.md '^\| T15 \|.*sessions kept sealed in the device.s store \(ADR-0209\)' \
  "threat model T15 keeps the session sealed in the store"

finish
