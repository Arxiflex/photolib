#!/usr/bin/env bash
# CI and supply-chain policy (issue #4): the licence allow-list, the workflows, the gitleaks allowlist and Renovate.
# The workflows cannot run here, so this pins what they must contain.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

# --- cargo-deny: only permissive licences and our own AGPL-3.0-only are allowed, and the gate points cargo-deny at this file
assert_file deny.toml
assert_matches deny.toml '^\[licenses\]' "has a licence policy"
for licence in MIT Apache-2.0 BSD-3-Clause; do
  assert_matches deny.toml "^  \"$licence\"," "allows $licence"
done
if grep -v '^  "AGPL-3.0-only",' deny.toml | grep -Eqi '"[^"]*(GPL|SSPL|BUSL|Commons-Clause|proprietary)[^"]*"'; then
  fail "deny.toml lists a copyleft or non-free licence other than our own"
else
  ok "deny.toml lists no copyleft or non-free licence other than our own"
fi
if grep -Eq '^\[licenses\.private\]' deny.toml; then
  fail "deny.toml exempts first-party crates from the licence check; they declare AGPL-3.0-only (ADR-0013)"
else
  ok "deny.toml checks first-party crates too"
fi
assert_matches deny.toml '^unknown-registry = "deny"' "denies unknown registries"
assert_matches deny.toml '^unknown-git = "deny"' "denies unknown git sources"
assert_matches tools/check.sh 'cargo deny --locked --config "\$ROOT/deny.toml" check' "the gate runs cargo-deny with it"

# --- a RustSec advisory warns in every gate's log and fails none (owner, 2026-10-24, photolib-design#799)
grep -Eq '^[[:space:]]*ignore[[:space:]]*=' deny.toml && fail "deny.toml ignores an advisory; the gate warns instead" ||
  ok "deny.toml ignores no advisory"
assert_patterns assert_prose docs/dev/supply-chain.md \
  'advisor[^.]*never fail[^.]*owner, 2026-10-24' "says advisories warn, never fail, and since when" \
  'WARN advisories: <id> <crate> <version> in <workspace>' "names the warning" \
  'reviewed from the[^.]*log' "says how a finding is reviewed"
assert_prose docs/adr/0058-supply-chain-baseline.md 'Amended — 2026-10-24[^*]*photolib-design#799' \
  "ADR-0058 records the owner's amendment of its advisory audit"

# --- one pipeline, on the merge queue's branches only (check_ci.py pins the workflows themselves)
assert_prose tools/README.md 'Only .\.github/workflows/ci\.yml. runs, on the branches Mergify.s merge queue pushes' \
  "tools/README.md says ci.yml, on the merge queue's branches, is the one pipeline"

# --- the owner deferred #283's provisional choices (photolib-design#304), so they stand
assert_prose docs/adr/0026-kernel-prebuilt-libraries.md \
  '\* \*\*Status\*\*: Accepted — 2026-10-15\.[^*]*by hand on the tag[^*]*deferred[^*]*photolib-design#304' \
  "ADR-0026 is Accepted: publishing from a run started by hand on the tag stands (photolib-design#304)"

# --- the workflows, Renovate and the gitleaks allowlist (assertions in check_ci.py)
require_tool python3
python3 "$REPO_ROOT/tools/tests/check_ci.py" || fail "check_ci.py reported failures"

finish
