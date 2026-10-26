#!/usr/bin/env bash
# Web video posters (ADR-0116) as the owner kept them (photolib-design#453): the browser's own <video>, no WebCodecs
# decoder, and posters sealed in the vault's 64 MiB cache.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0116-web-video-posters.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner kept both decisions [^*]*photolib-design#453' \
  "is Accepted, recording the owner's answer (#453)"
assert_matches docs/adr/README.md '\(0116-web-video-posters\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20\)' \
  "the index lists ADR-0116 as Accepted"
assert_prose app/packages/photolib_data/lib/src/browser_posters.dart 'web\.HTMLVideoElement\(\)' \
  "posters come from an off-DOM <video>"
assert_prose app/packages/photolib_data/lib/src/vault_cache.dart 'open\(Vault vault, \{int maxBytes = 64 << 20\}\)' \
  "the vault's cache holds 64 MiB"
# Posters need no WebCodecs; only the thumbnail worker's HEIF stills use it (ADR-0387), which needs no demuxer.
if decoders=$(grep -rn 'VideoDecoder' app/lib app/packages/*/lib | grep -v '^app/lib/features/library/timeline/browser_thumbnails\.dart:'); then
  fail "a WebCodecs decoder: $decoders"; else
  ok "no WebCodecs VideoDecoder but the HEIF stills' in the thumbnail worker"
fi
assert_prose app/lib/features/library/timeline/browser_thumbnails.dart 'isConfigSupported' \
  "the thumbnail worker asks WebCodecs before it decodes a HEIF still"


finish
