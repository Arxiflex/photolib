#!/usr/bin/env bash
# Encrypted playback (M0-33, ADR-0059) as the owner answered it in photolib-design#363: end to end on the device, the
# loopback relay on every native desktop, no AES-128 HLS, and the seek benchmark only when playback code changes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0059-encrypted-media-playback.md
assert_matches "$ADR" '^\* \*\*Status\*\*: Accepted \(owner answered, 2026-10-17\)' "is Accepted"
assert_matches docs/adr/README.md '\(0059-encrypted-media-playback\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-17' \
  "the index lists ADR-0059 as Accepted"
assert_patterns assert_prose "$ADR" \
  '^.*## How it works' "explains how private playback works" \
  'encrypts[^.]*64 KiB chunks[^.]*server stores only ciphertext' "the server stores only ciphertext" \
  'In private mode, media is decrypted only on the device, and decrypted bytes never leave it' \
  "records the owner's invariant" \
  'casting[^.]*asks the user first' "casting asks the user before decrypted bytes leave the device" \
  'Casting private videos is decided with casting \(M11-03\)' "leaves casting to M11-03" \
  'No AES-128 HLS' "builds no AES-128 HLS" \
  'Windows and Linux use it' "keeps the loopback relay on Windows and Linux" \
  'only when the diff touches playback code' "runs the benchmark only when playback code changes" \
  'without a diff to tell[^.]*it runs[^.]*photolib-design#560' "runs it without a base to diff, as the owner kept (#560)"
assert_prose docs/adr/README.md '\(0059-encrypted-media-playback\.md\) \| [^|]* \| [^|]*unless a diff provably touches no' \
  "the index says the benchmark runs unless a diff provably touches no playback code"
assert_prose docs/dev/threat-model.md 'decrypted only on the device[^|]*ADR-0059' "the threat model holds the invariant"
for doc in AGENTS.md docs/dev/encrypted-playback.md docs/dev/README.md; do
  assert_prose "$doc" 'bench\.mjs[^.]*when[^.]*playback code' "the benchmark runs when playback code changes"
done

finish
