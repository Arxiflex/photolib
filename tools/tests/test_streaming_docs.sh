#!/usr/bin/env bash
# Adaptive streaming (ADR-0246, M7-01) as the owner kept it (photolib-design#708): the saver rung from R1, every R1
# rendered again, streaming for viewers, the position in asset_user_state, 2 sessions and 20 GiB, H.264 for R2.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0246-adaptive-streaming.md
SERVER=server/crates/photolib-server/src
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-23 \(roadmap M7-01\)\. The owner kept [^*]*photolib-design#708' \
  "is Accepted, recording the owner's answer (#708)"
assert_matches docs/adr/README.md \
  '\(0246-adaptive-streaming\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0246 as Accepted"
assert_prose "$SERVER/hls.rs" 'let input = match &video\.stored \{ Some\(r1\) if name != "r2" => r1\.file\.clone\(\)' \
  "1. the saver rung encodes from the stored R1"
assert_prose "$SERVER/video.rs" '-hls_flags single_file' "2. R1's spec is single-file HLS with its index"
assert_prose "$SERVER/media.rs" \
  'can\(&self\.pool, who, Action::View, Resource::Asset\(asset\)\)[^}]*\} let video = hls\.video\(asset\)' \
  "3. whoever may view an asset streams it"
assert_prose "$SERVER/media.rs" 'INSERT INTO asset_user_state \(user_id, asset_id, playback_position_ms\)' \
  "4. PUT /media/<asset>/position keeps the position in asset_user_state"
assert_prose "$SERVER/config.rs" \
  'impl Default for Streaming \{ fn default\(\) -> Self \{ Self \{ sessions: 2, cache_gib: 20, \}' \
  "5. 2 sessions and a 20 GiB cache by default"
assert_prose "$SERVER/hls.rs" 'const CODECS: \[&str; 2\] = \["avc1\.640029", "mp4a\.40\.2"\];' \
  "6. every rung, R2 too, is H.264"

finish
