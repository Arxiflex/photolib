#!/usr/bin/env bash
# The licence and contribution model (ADR-0013, work item M0-02): the LICENSE file, the ADR that decides the
# consequences (app stores, FFmpeg builds, dependency allow-list, model weights) and the documents that state it.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0013-licence.md

# --- LICENSE is the FSF text of the AGPL, unmodified
FSF_SHA256=8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef
[[ -f LICENSE && $(sha256sum LICENSE | cut -d' ' -f1) == "$FSF_SHA256" ]] &&
  ok "LICENSE is byte for byte the FSF agpl-3.0 text" || fail "LICENSE is missing or differs from the FSF agpl-3.0 text ($FSF_SHA256)"

# --- the ADR decides, the owner accepted it (photolib-design#265) and kept it (#275) after the conflicting answer in #263
assert_file "$ADR"
assert_patterns assert_matches "$ADR" \
  '^# ADR-0013' "is ADR-0013" \
  '^\* \*\*Status\*\*: Accepted — 2026-10-15' "is Accepted on the date the owner confirmed it"
assert_patterns assert_prose "$ADR" \
  'photolib-design#265' "links the owner's confirmation" \
  'photolib-design#263[^.]*"[^"]*assume it is closed' "quotes the owner's answer in #263" \
  'photolib-design#275[^.]*"[^"]*keep license' \
    "quotes the owner's answer in #275 that keeps the licence"
grep -q 'asked again' "$ADR" && fail "$ADR still says the owner is asked again" || ok "$ADR: the #263 conflict is settled"
for section in Context Decision Consequences "Options considered"; do assert_matches "$ADR" "^## $section" "has a $section section"; done
assert_patterns assert_prose "$ADR" \
  'AGPL-3\.0-only for all first-party code' "licenses the first-party code under AGPL-3.0-only" \
  'Developer Certificate of Origin' "adopts the DCO" \
  'no CLA' "needs no contributor licence agreement" \
  'tools/dco\.sh' "says what enforces the DCO" \
  '## .*App stores' "has an App stores section" \
  'App Store[^.]*(permission|exception)' "says what Apple's store needs" \
  'additional permission' "chooses an additional permission for store builds" \
  'no (app-)?store (build|submission|release)[^.]*until' "blocks store releases until it is in place" \
  '## .*FFmpeg' "has an FFmpeg section" \
  'apps?[^.|]*\| *LGPL|LGPL[^.|]*apps?' "allows only LGPL builds in the apps" \
  'server[^.]*GPL[^.]*separate (executable|process)' "allows GPL builds on the server as a separate executable" \
  'never[^.]*--enable-nonfree' "forbids non-free builds" \
  '## .*[Dd]ependenc' "has a dependency licences section" \
  'deny\.toml' "points to deny.toml as the allow-list" \
  'tools/dart_licenses\.py' "names the Dart check" \
  'GPL-2\.0-only[^.]*incompatible' "explains why GPL-2.0-only is out" \
  '## .*[Mm]odel weights' "has a model weights section" \
  'non-commercial[^.]*never[^.]*(bundled|downloaded)[^.]*default' "never downloads non-commercial weights by default" \
  'bring-your-own' "offers restricted weights as bring-your-own" \
  'unknown or missing licence' "treats weights without a clear licence as restricted" \
  'CI rejects' "has CI reject default registry entries outside the safe classes"

# --- libFuzzer's NCSA licence, for kernel/fuzz alone, as the owner kept it (ADR-0189, photolib-design#558)
FUZZ_ADR=docs/adr/0189-fuzz-libfuzzer-ncsa.md
assert_prose "$FUZZ_ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21\.[^*]*photolib-design#558' "ADR-0189 is Accepted (#558)"
assert_matches docs/adr/README.md '\(0189-fuzz-libfuzzer-ncsa\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0189 as Accepted"
assert_matches deny.toml '^exceptions = \[\{ crate = "libfuzzer-sys", allow = \["NCSA"\] \}\]$' \
  "deny.toml allows NCSA for libfuzzer-sys alone"
check "the global allow-list has no NCSA" bash -c "! sed -n '/^allow = \[/,/^\]/p' deny.toml | grep -q NCSA"
assert_prose "$ADR" 'libfuzzer-sys[^.]*NCSA[^.]*\(\[ADR-0189\]\(0189-fuzz-libfuzzer-ncsa\.md\)\)' \
  "ADR-0013 points at ADR-0189 as decided"

# --- the documents that state it agree
assert_patterns assert_prose README.md \
  '\]\(LICENSE\)' "README links LICENSE" \
  'AGPL-3\.0-only' "README states the licence"
for doc in README.md AGENTS.md; do
  tr '\n' ' ' <"$doc" | grep -Eqi 'ADR-0013.{0,80}(owner to confirm|still has to confirm)' &&
    fail "$doc still says the owner has to confirm ADR-0013" || ok "$doc: the licence is decided"
done
assert_patterns assert_prose AGENTS.md \
  'AGPL-3\.0-only' "AGENTS.md states the licence contributions are made under" \
  'no CLA' "AGENTS.md says there is no CLA" \
  'deny\.toml' "AGENTS.md mentions the dependency allow-list" \
  '\]\(docs/adr/0013-licence\.md\)' "AGENTS.md links the ADR"
assert_prose docs/adr/README.md '0013-licence\.md[^|]*\| Licence and contribution model \| Accepted \|' \
  "the ADR index lists ADR-0013 as accepted"
PENDING='(ADR-0013|AGPL)[^|]{0,80}(owner to confirm|still has to confirm|owner decision)|owner to confirm[^|]{0,20}AGPL'
PENDING+='|ADR-0013 (is decided|selects)|after ADR-0013|wait for the licence decision'
pending=$(git ls-files '*.md' | while IFS= read -r doc; do tr '\n' ' ' <"$doc" | grep -Eqi -- "$PENDING" && echo "$doc"; done)
[[ -z $pending ]] && ok "no document calls the licence decision pending" ||
  fail "these documents still call the licence decision pending:" $pending

finish
