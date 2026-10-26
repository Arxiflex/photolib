#!/usr/bin/env bash
# ONNX Runtime's operator-reduced Android build (ADR-0050, tools/ml/ort_android.sh) keeps only the operators of
# tools/ml/ort-ops.config, which tools/ml/ort_ops.py writes from the models devices run: the registry's files for
# Android, by their pins in tools/ml/artefacts.json. Its --check fails when the config misses an operator of one of them
# in the tools cache: the gate's prefetched YuNet and SFace, and SigLIP 2's towers only once fetched (186 MB and more).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3

# A sandbox of one Android model, written as ONNX's protobuf: Relu, an If whose branch adds, and a contrib operator.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/tools/ml" "$SANDBOX/server/crates/photolib-models"
cp "$REPO_ROOT/tools/ml/fetch.py" "$REPO_ROOT/tools/ml/ort_ops.py" "$SANDBOX/tools/ml/"
python3 - "$SANDBOX/tiny.onnx" <<'EOF'
import sys


def varint(n):
    out = b""
    while n > 0x7F:
        out, n = out + bytes([n & 0x7F | 0x80]), n >> 7
    return out + bytes([n])


def field(number, value):
    if isinstance(value, int):
        return varint(number << 3) + varint(value)
    value = value.encode() if isinstance(value, str) else value
    return varint(number << 3 | 2) + varint(len(value)) + value


def node(op, domain="", attribute=b""):
    return field(4, op) + field(7, domain) + (field(5, attribute) if attribute else b"")


branch = field(1, node("Add"))
graph = (field(5, bytes(4096)) + field(1, node("Relu"))
         + field(1, node("If", attribute=field(1, "then_branch") + field(20, 5) + field(6, branch)))
         + field(1, node("FusedConv", "com.microsoft")))
model = field(1, 8) + field(8, field(2, 13)) + field(8, field(1, "com.microsoft") + field(2, 1)) + field(7, graph)
open(sys.argv[1], "wb").write(model)
EOF
sum=$(sha256sum <"$SANDBOX/tiny.onnx" | cut -c-64)
echo "{\"tiny\": {\"url\": \"file://$SANDBOX/tiny.onnx\", \"sha256\": \"$sum\"}}" >"$SANDBOX/tools/ml/artefacts.json"
cat >"$SANDBOX/server/crates/photolib-models/registry.json" <<EOF
[{"id": "tiny", "files": [{"name": "tiny.onnx", "sha256": "$sum", "targets": ["server", "android", "linux"]},
                          {"name": "big.onnx", "sha256": "$(printf '0%.0s' {1..64})", "targets": ["server"]}]}]
EOF
ops() { capture env PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" python3 "$SANDBOX/tools/ml/ort_ops.py" "$@"; }

ops --check
expect_result "--check with no device model in the cache fails rather than checking nothing" failure \
  "python3 tools/ml/fetch.py tiny"

ops
expect_result "the config is written from the Android models, fetched first" 0
config=$(grep -v '^#' "$SANDBOX/tools/ml/ort-ops.config")
[[ $config == $'ai.onnx;13;Add,If,Relu\ncom.microsoft;1;FusedConv' ]] &&
  ok "it lists each domain's operators at the model's opset, those of nested graphs too" || fail "config: $config"

ops --check
expect_result "--check passes on the config written from the same models" 0 "tiny"

sed -i 's/;Add,/;/' "$SANDBOX/tools/ml/ort-ops.config"
ops --check
expect_result "--check fails on a config that misses an operator, naming it" failure "ai.onnx;13;Add"

# The committed config against the real device models in the tools cache, YuNet and SFace fetched first.
python3 "$REPO_ROOT/tools/ml/fetch.py" yunet sface >/dev/null || fail "python3 tools/ml/fetch.py yunet sface"
capture python3 "$REPO_ROOT/tools/ml/ort_ops.py" --check
expect_result "tools/ml/ort-ops.config holds every operator of the device models in the tools cache" 0 yunet sface
echo "$OUT"

finish
