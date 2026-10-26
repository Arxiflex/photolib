#!/usr/bin/env bash
# The upgrade-path harness (M0-16): making upgrade fixtures is part of the release checklist, and the docs say how;
# ADR-0033's two choices are the ones the owner confirmed (photolib-design#318).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ADR=docs/adr/0033-upgrade-path-harness.md
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#318' \
  "is Accepted, recording the owner's confirmation (#318)" \
  '\*\*A fixture per migration\*\*' "keeps a fixture per migration on main, not per tagged release" \
  '\*\*weekly\*\* \(`upgrade-large`\) with a million, not nightly' "keeps the million-asset run weekly"
assert_matches docs/adr/README.md '\(0033-upgrade-path-harness\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0033 as Accepted"

RECORD='PHOTOLIB_RECORD_FIXTURES=1 cargo test -p photolib-db --test upgrade_path'
assert_patterns assert_prose docs/dev/releasing.md \
  '^# Releasing' "is the release checklist" \
  'upgrade fixture of every schema version' "requires an upgrade fixture of every schema version the release ships" \
  "$RECORD" "names the command that records a fixture" \
  'upgrade-large' "runs the million-asset upgrade on the release commit"
assert_prose docs/dev/README.md '\]\(releasing\.md\)' "the developer guide links the release checklist"
assert_patterns assert_prose docs/dev/migrations.md \
  'server/migrations/fixtures/' "says where the fixtures live" \
  'duplicate hashes, orphans, manual indexes and stray settings' "describes the drifted fixtures" \
  'URLs and share definitions .*resolve' "says URLs and shares must resolve as recorded" \
  "$RECORD" "says how to record a new fixture"
assert_prose AGENTS.md 'migration comes with its upgrade fixture' "tells agents that a migration needs its fixture"

finish
