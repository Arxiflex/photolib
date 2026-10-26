#!/usr/bin/env bash
# Sidecars and ignore rules of external libraries (ADR-0259, M2-29; ADR-0229 before renumbering) as the owner kept them
# (photolib-design#715): no Takeout JSON before its importer, flat keywords dropped against every node of the asset's
# keyword trees, and keywords as tags for every asset ingest makes, uploads too.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0259-external-sidecars-and-ignore-rules.md
INGEST=server/crates/photolib-server/src/ingest
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-23 \(roadmap M2-29\)\. The owner kept [^*]*photolib-design#715' \
  "is Accepted, recording the owner's answer (#715)"
assert_matches docs/adr/README.md \
  '\(0259-external-sidecars-and-ignore-rules\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0259 as Accepted"
assert_prose "$INGEST.rs" \
  'fn names\(name: &str\) -> Option<&str> \{ [^}]*\(extension\.eq_ignore_ascii_case\("xmp"\) && !base\.is_empty\(\)\)' \
  "1. only XMP files are sidecars"
check "1. no scan reads a Takeout's JSON before its importer (M4-02)" \
  bash -c "! grep -rqiE 'photoTakenTime|supplemental-metadata|takeout' server/crates/photolib-server/src"
assert_prose "$INGEST/commit.rs" \
  'let named = \|keyword: &String\| metadata\.keyword_paths\.iter\(\)'\
'\.any\(\|path\| path\.nodes\.contains\(keyword\)\);' \
  "2. a flat keyword that names any node of the asset's trees is dropped"
assert_prose "$INGEST/commit.rs" \
  '\.execute\(&mut \*tx\) \.await\?; tags\(tx, upload\.owner, id, metadata\)\.await\?; if retyped' \
  "3. every asset ingest commits, uploads too, gets its keywords as tags"
assert_matches "$INGEST.rs" '^    async fn an_uploads_keywords_become_its_owners_tags\(\)' \
  "3. a test proves it for uploads"

finish
