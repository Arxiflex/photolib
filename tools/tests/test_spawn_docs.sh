#!/usr/bin/env bash
# Test children die with the test (ADR-0113) as the owner kept it (photolib-design#464): util-linux's
# `setpriv --pdeathsig` starts them, and the server stays free of `unsafe` (no `pre_exec`).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0113-test-children-die-with-the-test.md
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-20 \(photolib-design#432\)\. The owner kept .setpriv --pdeathsig.[^*]*#464' \
  "is Accepted, recording the owner's answer (#464)"
assert_matches docs/adr/README.md '\(0113-[^)]*\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20\)' \
  "the index lists ADR-0113 as Accepted"
assert_prose server/crates/photolib-spawn/src/lib.rs 'Command::new\(setpriv\); [^;]*\.arg\(format!\("--pdeathsig=' \
  "photolib_spawn starts children under setpriv --pdeathsig"
assert_matches server/Cargo.toml '^unsafe_code = "forbid"$' "the server's workspace forbids unsafe"
if hooks=$(grep -rn 'pre_exec(' server --include=*.rs); then fail "a pre_exec hook: $hooks"; else ok "no pre_exec hook"; fi

finish
