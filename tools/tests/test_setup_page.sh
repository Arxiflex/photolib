#!/usr/bin/env bash
# The page a password setup link opens (ADR-0243): its script hands the link to the app and speaks every language the
# apps launch in. The ADR and T79 record the owner's answers (photolib-design#610).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1
require_tool node

if output=$(node --test server/crates/photolib-server/src/relay/setup_test.js 2>&1); then
  ok "the setup link's page passes its tests"
else
  echo "$output" >&2
  fail "the setup link's page fails its tests"
fi

ADR=docs/adr/0243-setup-links-open-the-app.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21\. The owner confirmed [^*]*photolib-design#610' \
  "is Accepted, recording the owner's confirmation (#610)"
assert_matches docs/adr/README.md '\(0243-setup-links-open-the-app\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0243 as Accepted"
assert_matches docs/dev/threat-model.md '^\| T79 \|.*Residual, which the owner accepted' "T79's residual risk is the owner's"
finish
