#!/usr/bin/env bash
# The on-device ML runtime spike (M0-34): ONNX Runtime's size on every target, every pinned model's numbers natively
# and in browsers against design 09's parity rule, and the decision recorded as ADR-0050, which the owner confirmed
# (photolib-design#343); on-device ML in production (ADR-0278) and the registry as the apps' trust anchor (ADR-0064),
# as the owner kept them (photolib-design#689).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

REPORT=docs/dev/ml-runtime.md
ADR=docs/adr/0050-on-device-ml-runtime.md
for target in android-arm64 android-arm android-x64 ios-arm64 macos-arm64 windows-x64 linux-x64 linux-arm64 web; do
  assert_matches "$REPORT" "^\| $target( \(.*\))? \|" "has the runtime's size on $target"
done
for model in $(python3 -c 'import json; print(*(n for n, a in json.load(open("tools/ml/artefacts.json")).items() if "files" not in a and "fixture" not in a))'); do
  [[ $(grep -c "^| $model |" "$REPORT") -ge 3 ]] && ok "has the size, the Linux and the browser numbers of $model" ||
    fail "$REPORT lacks a size, Linux or browser row for $model"
done
for measure in 'Load \(ms\)' 'Run \(ms\)' 'RSS \(MB\)' 'Cosine' 'Chrome 155' 'Firefox 158' 'WebGPU' 'energy' 'heat'; do
  assert_prose "$REPORT" "$measure" "reports $measure"
done
assert_prose docs/dev/README.md 'ml-runtime\.md' "the developer guide links the report"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16[^*]*owner confirmed[^*]*photolib-design#343' \
  "is Accepted, recording the owner's confirmation (#343)"
assert_matches docs/adr/README.md '\(0050-on-device-ml-runtime\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0050 as Accepted"
assert_patterns assert_prose "$ADR" \
  'Runtime: ONNX Runtime everywhere' "decides the runtime" \
  'Binding: a thin `dart:ffi` binding of ONNX Runtime.s C API\*\*[^*]*onnxruntime-web with `dart:js_interop`' \
  "decides the client binding: the C API natively, onnxruntime-web on the web" \
  'Model format: ONNX, fp16 weights with fp32 inputs and outputs on devices\.\*\*[^*]*fp32 is the reference[^*]*int8 model is used only where it passes the golden check' \
  "decides the precision: fp16 on devices, fp32 the reference, int8 only past the golden check" \
  'Accelerator policy: the CPU always works; an accelerator must first prove itself\.\*\*[^*]*never falling back silently[^*]*cosine ≥ 0\.99[^*]*three failures to run quarantine[^*]*NNAPI is not used' \
  "decides the accelerator policy: a golden check, quarantine, no silent fallback, no NNAPI" \
  '\(\.\./dev/ml-runtime\.md\)' "links the report"

ADR=docs/adr/0278-on-device-ml-in-production.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#689' \
  "ADR-0278 is Accepted, as the owner kept its six decisions (#689)"
assert_matches docs/adr/README.md '\(0278-on-device-ml-in-production\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0278 as Accepted"
assert_patterns assert_prose "$ADR" \
  'The registry compiled into the app is the trust anchor, as ADR-0064 has it for photolibd; no manifest signature' \
  "1: no signature until a key exists" \
  'Lite mode is a device reporting under 3\.5 × 10⁹ bytes of RAM' "2: lite mode below 3.5e9 bytes" \
  'New captures are the photos the device index added in the last 24 hours[^.]*two at a time' \
  "3: phones index the last 24 hours' captures in the foreground, two at a time" \
  'Desktops index everything in the foreground' "3: desktops index everything in the foreground" \
  'Battery threshold \(10, 20, 30 or 50 %, 20 by default\)' "4: the battery thresholds" \
  'Connected apps download only from their photolibd[^.]*and wait when it lacks the model' \
  "5: a connected app never falls back to the mirror" \
  'the registry.s first image embedding, until libraries have their own' "6: the registry's first model is active"
assert_matches app/lib/core/device_health.dart '< 3500000000;' "lite mode's constant"
assert_matches app/packages/photolib_data/lib/src/ml.dart 'Duration\(hours: 24\)' "new captures' window"
assert_matches app/lib/features/settings/indexing.dart '\{10, 20, 30, 50, settings\.indexBattery\}' \
  "the thresholds offered"
assert_matches server/crates/photolib-server/src/uploads.rs 'find\(\|m\| m\.task == Task::ImageTextEmbedding\)' \
  "the hand-off's active model is the registry's first image-text embedding"

ADR=docs/adr/0064-model-registry-and-licence-gate.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23 [^*]*kept no signed manifest[^*]*photolib-design#689' \
  "ADR-0064 is Accepted, as the owner kept its trust anchor (#689)"
assert_matches docs/adr/README.md '\(0064-model-registry-and-licence-gate\.md\) \| [^|]* \| Accepted \(owner kept' \
  "the index lists ADR-0064 as Accepted"

finish
