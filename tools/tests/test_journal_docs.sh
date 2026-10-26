#!/usr/bin/env bash
# Journaled file operations (ADR-0041, M0-18; ADR-0037 before renumbering) as the owner confirmed them
# (photolib-design#336): the ADR is Accepted with its three choices, which photolib-storage's tests/journal.rs and
# photolib-server's config tests pin in code.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0041-journaled-file-operations.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#336' \
  "is Accepted, recording the owner's confirmation (#336)"
assert_patterns assert_prose "$ADR" \
  'A planned put is rolled back even when its object is complete' "recovery rolls back a complete planned put" \
  'NFC and NFD spellings are different keys' "keys are stored byte-exact" \
  '`timeout_secs` per object store \(120 s by default\), 120 s on the data directory' "a call times out after 120 s"
assert_matches docs/adr/README.md '\(0041-journaled-file-operations\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0041 as Accepted"
assert_matches docs/admin/configuration.md '^\| `stores\.<name>\.timeout_secs` \| `120` \|' \
  "the admin guide gives the 120 s default"
assert_matches server/crates/photolib-server/src/storage.rs \
  '^pub\(crate\) const LOCAL_TIMEOUT: Duration = Duration::from_secs\(120\);' "the data directory's calls time out after 120 s"

finish
