#!/usr/bin/env bash
# The HEIC and HEVC spike (M1-44, photolib-design#565): every cell without a system decoder with its behaviour on main,
# the options and their cost, libheif-js measured in Chrome on HEIC twins of the corpus (tools/heic/, by hand), the
# licence and patent facts, the dual-encoded renditions, the owner's questions and the tasks each answer opens, and
# ADR-0214 as the owner answered (photolib-design#600): no WASM decoder, no codec pack in any build, placeholders that
# name connected mode or a Mac, no Safari folders, and a full-size universal JPEG by default.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

# plan <corpus path>: the twin tools/heic/twins.py makes of that HEIC record, as JSON.
plan() {
  python3 - "$1" <<'EOF'
import json, sys
sys.path.insert(0, "tools/heic")
import twins
record = json.load(open(f"testdata/corpus/golden/{sys.argv[1]}.json"))
print(json.dumps(twins.plan(record), sort_keys=True, separators=(",", ":")))
EOF
}

expect_plan() {
  local got
  got=$(plan "$1")
  [[ $got == "$2" ]] && ok "twin of $1" || fail "twin of $1: expected $2, got $got"
}
expect_plan stills/iphone.heic \
  '{"clap":null,"depth":8,"grid":true,"height":3024,"mirror":null,"path":"stills/iphone.heic","rotation":null,"shown":[4032,3024],"width":4032}'
expect_plan stills/irot.heic \
  '{"clap":null,"depth":8,"grid":true,"height":3024,"mirror":null,"path":"stills/irot.heic","rotation":3,"shown":[3024,4032],"width":4032}'
expect_plan stills/imir.heic \
  '{"clap":null,"depth":8,"grid":true,"height":3024,"mirror":0,"path":"stills/imir.heic","rotation":null,"shown":[4032,3024],"width":4032}'
expect_plan stills/clap.heic \
  '{"clap":[4000,3000],"depth":8,"grid":true,"height":3024,"mirror":null,"path":"stills/clap.heic","rotation":null,"shown":[4000,3000],"width":4032}'
expect_plan hdr/pq-10bit.heic \
  '{"clap":null,"depth":10,"grid":true,"height":3024,"mirror":null,"path":"hdr/pq-10bit.heic","rotation":null,"shown":[4032,3024],"width":4032}'
expect_plan compound/motion/pixel-motion.heic \
  '{"clap":null,"depth":8,"grid":false,"height":3024,"mirror":null,"path":"compound/motion/pixel-motion.heic","rotation":null,"shown":[4032,3024],"width":4032}'
expect_plan stills/8bit.avif 'null'
twins=$(python3 -c 'import sys; sys.path.insert(0, "tools/heic"); import twins; print(len(twins.plans()))')
heics=$(grep -l '"format": "heic"' -r testdata/corpus/golden | wc -l)
[[ $twins == "$heics" && $heics -gt 0 ]] && ok "a twin for each of the corpus' $heics HEIC records" ||
  fail "twins.plans() has $twins twins for $heics HEIC records"
assert_matches tools/heic/bench.mjs "browser_thumbnails\.dart" "probes with the worker script main runs"

REPORT=docs/dev/heic-without-system-decoder.md
assert_file "$REPORT"
assert_prose docs/dev/README.md '\]\(heic-without-system-decoder\.md\)' "the developer guide links the report"
for cell in 'Chrome and Edge on Linux' 'Firefox, every desktop' 'Safari on macOS' \
  'Chrome and Edge on Windows without the HEVC Video Extension' 'Windows app without the HEVC Video Extension' \
  'Linux app without libheif' 'Android below API 28' 'Android 11 \(API 30\)' 'HEVC video in Chrome on Linux' \
  'HEVC video in Firefox' '10-bit HEVC video' 'HEIC bursts' 'Live Photo stills' 'Apple ProRAW' \
  'Connected mode'; do
  assert_matches "$REPORT" "^\| ${cell}[^|]* \|( [^|]+ \|){4}\$" "has the cell '${cell//\\/}' with its behaviour, options and proposal"
  assert_matches "$REPORT" "^\| ${cell}[^|]* \| (\"[^|]+\"|none[^|]*) \|\$" "has the placeholder text of '${cell//\\/}', or why none"
done
assert_matches "$REPORT" '^\| Chrome [0-9]+ \| [0-9.]+ / [0-9.]+ / [0-9.]+ MB \| [0-9]+ ms \| [0-9]+ ms \| [0-9]+ MB \|$' \
  "has libheif-js' size, cold and second load and memory in Chrome"
for twin in stills/iphone.heic stills/10bit.heic stills/irot.heic stills/imir.heic stills/clap.heic \
  compound/motion/pixel-motion.heic; do
  assert_matches "$REPORT" "^\| \`$twin\` \| [0-9.]+ MB \| [0-9]+ × [0-9]+ \| [0-9]+ ms \| ([0-9]+ ms|none) \| [0-9]+ MB \| (yes|no[^|]*) \|\$" \
    "has the decode time, memory and orientation of the twin of $twin"
done
assert_patterns assert_prose "$REPORT" \
  'libheif[^.]{0,80}LGPL-3\.0' "gives libheif's licence" \
  'libde265[^.]{0,80}LGPL-3\.0' "gives libde265's licence" \
  'Access Advance[^|]{0,400}\]\(https://' "has the Access Advance facts with a source" \
  'Via LA[^|]{0,400}\]\(https://' "has the Via LA facts with a source" \
  'Velos Media' "names Velos Media" \
  'free to end users' "states the AVC terms for free internet video" \
  '<picture>' "dual encoding: stills choose with <picture>" \
  '<source type' "dual encoding: by <source type>" \
  'MediaSource\.isTypeSupported' "dual encoding: videos choose with MediaSource.isTypeSupported" \
  '\(\.\./adr/0214-heic-and-hevc-without-a-system-decoder\.md\)' "links the ADR"
assert_matches "$REPORT" '^\| Source \| Primary \| Fallback \| Chosen by \|$' "has the rendition pair per source format"
for asked in 'WASM fallback on the web|Kept: no' 'Desktop codec plugin|Changed: no' 'Safari folders|Kept: no' \
  "Quality of the universal rendition|Changed: \`high\`"; do
  question=${asked%%|*} answer=${asked#*|}
  assert_matches "$REPORT" "^\| ${question}[^|]* \| (Yes|No|\`standard\`)[^|]* \|( [^|]+ \|){2} ${answer}[^|]* \|\$" \
    "asks '$question' with a lean, and has the owner's answer"
done
for cell in 'Windows app without the HEVC Video Extension' 'Linux app without libheif'; do
  assert_matches "$REPORT" "^\| ${cell}[^|]* \| \"[^\"|]*Photolib server[^\"|]*a Mac[^\"|]*\" \|\$" \
    "the placeholder of '$cell' names connected mode or a Mac"
  if grep -Eiq "^\| ${cell}[^|]* \| \"[^|]*(install|libheif|Store)" "$REPORT"; then
    fail "the placeholder of '$cell' still names a codec to install"
  else ok "the placeholder of '$cell' names no codec to install"; fi
done
assert_matches "$REPORT" '^size = "(XS|S|M|L)"$' "writes the tasks the answers open as sized roadmap entries"
entry() { sed -n "/^key = \"$1\"\$/,/^acceptance = /p" "$REPORT"; }
[[ -z $(entry M1-48) ]] && ok "opens no desktop codec pack (M1-48 dropped)" ||
  fail "the report still opens M1-48, the codec pack"
[[ $(entry M1-49) == *'title = "'*'connected mode or a Mac'* ]] &&
  ok "M1-49's placeholders name connected mode or a Mac" ||
  fail "M1-49's title does not name connected mode or a Mac"
[[ $(entry M2-49) == *'priority = "P1"'*'high'*'by default'* ]] && ok "M2-49, high by default, is P1" ||
  fail "M2-49 is not P1 with high by default"

ADR=docs/adr/0214-heic-and-hevc-without-a-system-decoder.md
assert_file "$ADR"
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-21 \(roadmap M1-44\)\. The owner [^*]*photolib-design#600' \
  "is Accepted, recording the owner's answers (#600)" \
  'We will ' "records the decision" \
  'no codec pack in any build: nothing HEVC-licensed ships on a client' "no desktop codec pack (question 2)" \
  'names connected mode or a Mac, never a codec to install' "placeholders name connected mode or a Mac (question 2)" \
  '.high. by default: a full-size JPEG at the original.s resolution, jpegli q≈92-95 with the Ultra HDR gain map' \
  "the universal rendition is high by default (question 4)" \
  '\(\.\./dev/heic-without-system-decoder\.md\)' "links the report"
assert_matches docs/adr/README.md \
  '\(0214-heic-and-hevc-without-a-system-decoder\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-21; [^)]+\) \|$' \
  "the index lists ADR-0214 as Accepted"
assert_prose AGENTS.md 'the cell.s placeholder names the way out, in the apps connected mode or a Mac, not a codec;' \
  "AGENTS.md: the apps' placeholders name no codec to install"

finish
