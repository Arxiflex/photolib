#!/usr/bin/env bash
# The server's ML role (ADR-0245, M5-02) as the owner kept it (photolib-design#710): the fp16 SigLIP 2 text tower on
# the server too, one shared bearer token for remote nodes, and 2 GB as 2,000,000,000 bytes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0245-server-ml-role.md
SERVER=server/crates/photolib-server/src
REGISTRY=server/crates/photolib-models/registry.json
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-23 \(roadmap M5-02\)\. The owner kept [^*]*photolib-design#710' \
  "is Accepted, recording the owner's answer (#710)"
assert_matches docs/adr/README.md '\(0245-server-ml-role\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0245 (the ML role) as Accepted"
assert_matches "$REGISTRY" '"name": "text_model_fp16\.onnx", [^]]*"targets": \["server",' \
  "1. the server runs SigLIP 2's fp16 text tower"
check "$REGISTRY: 1. and no fp32 text tower" bash -c "! grep -q '\"text_model\.onnx\"' $REGISTRY"
assert_prose "$SERVER/config.rs" \
  'impl Ml \{ fn problems[^}]*self\.token\.as_ref\(\)\.is_some_and\(\|token\| token\.expose\(\)\.len\(\) < 32\)' \
  "2. ml.token has at least 32 characters"
assert_prose "$SERVER/ml.rs" 'route_layer\(middleware::from_fn_with_state\(token, crate::metrics::bearer\)\)' \
  "2. /ml/v1 takes the bearer of ml.token, as /metrics takes metrics.token's"
assert_prose "$SERVER/config.rs" 'impl Default for Ml \{[^}]* memory_mb: 2000,' "3. ml.memory_mb is 2000 by default"
assert_matches server/crates/photolib-ml/src/lib.rs '^pub const MEMORY: u64 = 2_000_000_000;' \
  "3. the default profile stays under 2,000,000,000 bytes"

finish
