#!/usr/bin/env bash
# The photolibd startup contract (ADR-0021, M0-07) as the owner confirmed it (photolib-design#273): the ADR is
# Accepted, and the docs say the configuration is YAML.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0021-photolibd-startup-contract.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner confirmed [^*]*photolib-design#273' \
  "is Accepted, recording the owner's confirmation (#273)"
assert_prose "$ADR" 'serde-saphyr.*rust-version.*1\.89' "records why the MSRV is 1.89"
assert_matches docs/adr/README.md '\(0021-photolibd-startup-contract\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0021 as Accepted"
if grep -Eqi 'not yet confirmed|owner to confirm' docs/admin/configuration.md; then
  fail "docs/admin/configuration.md still calls ADR-0021 unconfirmed"
else ok "docs/admin/configuration.md treats ADR-0021 as decided"; fi
if toml=$(grep -rEn 'TOML (config|template)' docs); then fail "the docs still configure photolibd with TOML: $toml"; else
  ok "no doc configures photolibd with TOML"
fi

finish
