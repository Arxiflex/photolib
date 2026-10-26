#!/usr/bin/env bash
# Panoramas and 360° video (M1-13, ADR-0146) as the owner answered photolib-design#556: one shader and no native
# renderers, and a sphere that pages like any other item until a button enters its 360° view; as kept in
# photolib-design#658, keys page there too and its other commands work outside it. The owner's review of 2026-10-23
# replaced that view (docs/10 §4.6, ADR-0383): a sphere now opens rotatable. Its follow-ups (ADR-0190) as the owner
# kept them (photolib-design#681): a 512 px tile pyramid, fisheye as a lens, sidecar captions only.
# shellcheck disable=SC2016 # patterns match literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0146-panoramas-and-360-video.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-21\.[^*]*photolib-design#556' \
  "is Accepted, recording the owner's answers (#556)"
assert_prose "$ADR" '\* \*\*Status\*\*: [^*]*2026-10-23[^*]*photolib-design#658' \
  "records that the owner kept both readings of that answer (#658)"
assert_matches docs/adr/README.md \
  '\(0146-panoramas-and-360-video\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-21 and 2026-10-23\)' \
  "the index lists ADR-0146 as Accepted, with both answers"
assert_patterns assert_prose "$ADR" \
  'test phase[^.]*poles[^.]*cubemaps' "the test phase shows where the filter falls short" \
  'pages like any other item until a button enters its 360° view' "a sphere pages until its 360° view" \
  '360° view[^.]*drags turn it and the pager is locked' "where drags turn it and the pager is locked" \
  'Keys and the filmstrip still turn the page[^.]*for now: the viewer.s interface is revisited later' \
  "keys and the filmstrip page out of the 360° view, for now (#658)" \
  '\(little planet, gyroscope, zoom keys\) work in or out of it' "its other commands work outside its 360° view" \
  'Previous and Next buttons' "names the buttons the owner dropped"

ADR=docs/adr/0190-sphere-viewer-follow-ups.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#681' \
  "ADR-0190 is Accepted, as the owner kept its three decisions (#681)"
assert_matches docs/adr/README.md '\(0190-sphere-viewer-follow-ups\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0190 as Accepted"
assert_patterns assert_prose "$ADR" \
  'decodes the 512 px tiles in view at the coarsest sample' "large panoramas decode a 512 px tile pyramid" \
  'offer fisheye as a lens\*\* \(.Fisheye., .o., as .e. edits\): equidistant, up to 200°' \
  "fisheye is a lens on o, not a projection" \
  'Read GPano.s `cylindrical`\*\* as an input projection' "cylindrical is the new input projection" \
  'beside its file or in its browser folder; embedded tracks stay M7-06.s[^.]*libmpv loads no sidecar itself' \
  "captions come from a sidecar only, shown once"
assert_matches app/lib/features/viewer/mpv.dart "setProperty\('sub-auto', 'no'\)" "libmpv loads no sidecar itself"
assert_prose AGENTS.md 'A sphere opens rotatable \(ADR-0383\)[^.]*the pager is locked' "AGENTS.md says how a sphere pages"

# M1-41 as the owner kept it in photolib-design#662: 30 fps on the gate, libmpv's defaults on every renderer.
assert_patterns assert_prose docs/adr/0146-panoramas-and-360-video.md \
  '.sphere-video. holds it to 30 fps on the GPU-less gate' "the budget is M1-41's 30 fps" \
  'No libmpv option depends on the GL renderer[^.]*defaults[^(]*\(owner, 2026-10-23, photolib-design#662' \
  "a software renderer keeps libmpv's defaults, as the owner kept (#662)"
! grep -rEq "GL_RENDERER|llvmpipe|softpipe|swrast|'(zimg-[a-z]+|profile)'" app/lib/features/viewer &&
  ok "the viewer sets no libmpv option by renderer" || fail "the viewer sets a libmpv option by renderer (#662)"

finish
