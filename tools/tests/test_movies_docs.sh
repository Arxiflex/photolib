#!/usr/bin/env bash
# Movies, motion photos and Live Photos (ADR-0044, M1-06; ADR-0041 before renumbering) as the owner confirmed them
# (photolib-design#339): the ADR is Accepted with its five provisional choices, and the code and corpus keep them.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0044-kernel-movies-motion-and-live-photos.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#339' \
  "is Accepted, recording the owner's confirmation (#339)"
assert_patterns assert_prose "$ADR" \
  "have hosts pass the file's size" "hosts pass the file's size" \
  'read only for Samsung cameras' "the SEF trailer is read for Samsung cameras only" \
  "return \`mvhd\`'s creation time without an offset, and none for 0" "mvhd times carry no offset, 0 none" \
  'equal identifiers first, else the same folder and name up to the first dot, a clip of at most 4 s within 2 s, the closest first, never two different identifiers' \
  "Live Photos pair as decided" \
  'amend the corpus [^.]*in `tools/corpus`: the spherical videos. records get their `pano`, and `video/dv\.avi` is written at the 720×576' \
  "the corpus records were amended"
assert_matches docs/adr/README.md '\(0044-kernel-movies-motion-and-live-photos\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0044 as Accepted"
assert_patterns assert_prose proto/photolib/kernel/v1/metadata.proto \
  'uint64 size = 2;' "ReadMetadataRequest takes the file's size" \
  'It needs the request.s size' "a motion video needs the size"
assert_matches kernel/src/metadata.rs 'let samsung = response\.make\.eq_ignore_ascii_case\("samsung"\);' \
  "the SEF trailer is read for make samsung only"
assert_patterns assert_prose kernel/src/live_photo.rs \
  'const CLIP_MS: u64 = 4000;' "clips of at most 4000 ms pair by name" \
  'const APART_MS: u64 = 2000;' "capture instants at most 2000 ms apart pair by name" \
  'file\.split\(.\..\)\.next\(\)[^;]*; format!\("\{folder\}/\{stem\}"\)\.to_lowercase\(\)' \
  "names match by folder and up to the first dot, case-insensitively"
assert_patterns assert_prose kernel/src/metadata/movie.rs \
  'created = field\(4, clock\)\.filter\(\|&c\| c != 0\);' "a zero mvhd makes no claim" \
  'claim\("quicktime:CreateDate", &clock\(seconds\), None, None\)' "an mvhd claim has no offset"
assert_patterns assert_matches tools/corpus/catalog_compound.py \
  'maker = dict\(make="RICOH", [^)]*meta_extra=\{"pano": sphere\}\)' "the spherical videos' records have their pano" \
  '"pano": \{\*\*sphere, "projection": "cubemap"\}' "the cubemap video's record has its pano"
assert_matches tools/corpus/catalog_video.py 'other\("video/dv\.avi", containers\.avi\(seed="dv", width=720, height=576' \
  "dv.avi is written at the 720x576 its record states"

finish
