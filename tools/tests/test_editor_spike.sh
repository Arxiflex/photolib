#!/usr/bin/env bash
# The editor rendering spike (M0-36): a pixel-difference and memory report on phone, desktop and web against every
# criterion of design 11 §4.4, and the decision recorded as ADR-0054.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

REPORT=docs/dev/editor-rendering.md
ADR=docs/adr/0054-editor-rendering.md
assert_file "$REPORT"
for platform in Phone Desktop Web; do
  assert_matches "$REPORT" "^\| $platform \|" "has pixel differences and memory for the $platform"
done
for criterion in Parity 'Preview = export' 'Precision stress' Interactivity Memory 'Export time' Web 'Gain maps' Size; do
  assert_matches "$REPORT" "^\| $criterion \|" "measures against the criterion '$criterion'"
done
assert_prose docs/dev/README.md 'editor-rendering\.md' "the developer guide links the report"
assert_matches "$REPORT" '^\| Kernel, tiles on [0-9]+ worker isolates \| [0-9.–]+ \| [0-9.–]+ \| [0-9.–]+ \|' \
  "records the export time with tiles on every core at 12, 50 and 200 MP"
assert_file "$ADR"
assert_matches "$ADR" '^\* \*\*Status\*\*: Accepted \(owner answered, 2026-10-17\)' "is Accepted"
assert_matches docs/adr/README.md '\(0054-editor-rendering\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-17' \
  "the index lists ADR-0054 as Accepted"
assert_patterns assert_prose "$ADR" \
  'We will render the preview with Flutter fragment shaders on every backend and every export with the kernel' \
  "takes A′, the owner's answer" \
  'foreground, background, batch, server, CLI, iOS-extension and gain-map' "names every export" \
  'worker isolates \(web workers on the web\) across all cores' "spreads an export's tiles over every core" \
  'Saving stores the recipe and the version at once' "saves without waiting for the render" \
  'only an explicit export or share waits' "waits only for an explicit export or share" \
  'Apple Photos or MediaStore completes when its render does' "writes edits back once rendered" \
  '50 MP[^.]*10 s[^.]*test phase' "leaves the phone's export time to the test phase" \
  'parity suite[^.]*stays in the gate' "keeps the parity suite in the gate" \
  'GPU export on Impeller \(A\) comes back as an optimi[sz]ation' "keeps A as a later optimisation" \
  'B stays rejected' "keeps B rejected" \
  '\(\.\./dev/editor-rendering\.md\)' "links the report"
assert_prose AGENTS.md 'shaders` render (them|the preview)[^.]*every export' "AGENTS.md says the shaders render only the preview"
assert_prose docs/dev/README.md 'preview with Flutter fragment shaders[^.]*every export' \
  "the developer guide says the shaders render only the preview"

finish
