#!/usr/bin/env bash
# The media sandbox (ADR-0024, M0-19) as the owner confirmed it (photolib-design#281): the ADR is Accepted with its
# three choices, and no doc says otherwise.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0024-media-sandbox.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner confirmed [^*]*photolib-design#281' \
  "is Accepted, recording the owner's confirmation (#281)"
assert_prose "$ADR" 'seccomp\*\* is a deny-list answering `EPERM`' "keeps the seccomp deny-list"
assert_prose "$ADR" 'a tool may also read and execute `/usr`, `/bin`, `/lib`, `/lib64`' "lets a tool execute system programs"
assert_prose "$ADR" 'dump above 1 MiB fails with `limit_exceeded`' "fails an oversized metadata dump"
assert_matches docs/adr/README.md '\(0024-media-sandbox\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0024 as Accepted"
if stale=$(grep -rEn 'seccomp allow-list|execve only to start|truncated and flagged|capped at 1 MiB' docs \
  --exclude=0024-media-sandbox.md); then fail "a doc contradicts ADR-0024: $stale"; else
  ok "no doc contradicts ADR-0024"
fi

finish
