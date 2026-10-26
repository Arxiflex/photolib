#!/usr/bin/env bash
# The client sync engine (ADR-0120) as the owner kept it (photolib-design#460): a reset or a restore drops what a stream
# delivered, then fetches it again, as design 05 §3 and §8 say. A partner share shows the owner's own libraries only
# (ADR-0155, kept in photolib-design#539), on photolibd and on the device alike.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0120-client-sync-engine.md
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-20 \(roadmap M2-15\)\. The owner kept drop, then refetch[^*]*#460' \
  "is Accepted, recording the owner's answer (#460)"
assert_matches docs/adr/README.md '\(0120-[^)]*\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20\)' \
  "the index lists ADR-0120 as Accepted"
assert_prose app/packages/photolib_data/lib/src/sync.dart \
  'Drops what \[stream\] delivered and its cursor, so that it syncs again from (/// )?scratch\. Future<void> _drop\(' \
  "SyncEngine drops a reset stream's rows"
assert_prose app/packages/photolib_data/test/sync_test.dart \
  "'a stream the server resets syncs again from scratch, without what the server no longer has'" \
  "a test syncs a reset stream again from scratch"

ADR=docs/adr/0155-partner-shares-own-libraries.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21 \(photolib-design#509\)\. The owner kept [^*]*#539' \
  "is Accepted, recording the owner's answer (#539)"
assert_matches docs/adr/README.md '\(0155-[^)]*\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-21\) \|$' \
  "the index lists ADR-0155 as Accepted"
assert_prose server/crates/photolib-authz/src/lib.rs \
  'const PARTNER: &str = "[^"]*JOIN libraries l ON l\.id = a\.library_id AND l\.owner_id = a\.owner_id' \
  "photolibd's partner path reads the owner's own libraries only"
assert_prose app/packages/photolib_data/lib/src/sync.dart \
  "JOIN partner_library l [^;]*AND l\.library_id = a\.library_id" \
  "the device keeps a partner's asset only in a library the partner's stream sent"

finish
