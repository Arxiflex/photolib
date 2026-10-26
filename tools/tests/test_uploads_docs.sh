#!/usr/bin/env bash
# Resumable uploads (ADR-0061, M2-07; ADR-0042 before renumbering) as the owner confirmed them (photolib-design#345):
# the ADR is Accepted with its three choices, which server/crates/photolib-server/tests/uploads.rs pins on the wire.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0061-resumable-uploads.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#345' \
  "is Accepted, recording the owner's confirmation (#345)"
assert_patterns assert_prose "$ADR" \
  'expires a day after its last append' "an incomplete upload expires a day after its last append" \
  'under `libraries/<library>/uploads/<id>`' "a complete upload waits in its library's store under uploads/" \
  '`Photolib-Library` and the BLAKE3 of the bytes, lowercase hex, in `Photolib-Hash`' \
  "creation names the library and the BLAKE3 in headers"
assert_matches docs/adr/README.md '\(0061-resumable-uploads\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0061 as Accepted"
assert_matches docs/admin/configuration.md 'An upload with no new bytes for a day' "administrators are told uploads expire after a day"

finish
