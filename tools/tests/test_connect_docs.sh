#!/usr/bin/env bash
# Connect RPC (ADR-0027, M0-08) as the owner confirmed it (photolib-design#293): the ADR is Accepted with both choices.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0027-connect-rpc.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner confirmed [^*]*photolib-design#293' \
  "is Accepted, recording the owner's confirmation (#293)"
assert_prose "$ADR" 'generated with buffa and connect-rust\*\* instead of prost, which the kernel keeps' \
  "serves Connect with connectrpc on buffa, the kernel keeping prost"
assert_prose "$ADR" 'The epoch is the instance id' "uses the instance id as the epoch"
assert_prose "$ADR" 'the instance id is public; a UUIDv7' "accepts that GetServerInfo exposes the instance id"
assert_matches docs/adr/README.md '\(0027-connect-rpc\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0027 as Accepted"

finish
