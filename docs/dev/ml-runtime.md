# On-device ML runtime report (M0-34)

ONNX Runtime with the default models of design 09 §2.1 — SigLIP 2 B/16-256 for search, YuNet and SFace
for faces — measured on 2026-10-16, natively and in browsers, with every output checked against
the CPU's golden values. The decision is [ADR-0050](../adr/0050-on-device-ml-runtime.md).

## How it is measured

* `app/packages/photolib_ml` binds ONNX Runtime's C API with `dart:ffi`; `test/native_test.dart` runs the official
  library of the desktop it is on, `test/web_test.dart` runs onnxruntime-web in browsers. Both feed the inputs of
  `test/spike.dart` — a synthetic picture (waves, a disc and a bar) and the query "a photo of a sailing boat in
  greece" as 64 tokens — and take the cosine of up to 1,024 evenly spaced output values to `test/golden.json`, the
  fp32 models' outputs on Linux x64's CPU. YuNet's are its raw outputs, before decoding.
* A run times creating the session (*load*), the first inference and the median of five more (*run*). Natively each
  row is the fastest of four or five runs with 4 threads, and *RSS* is how much the resident memory of a process of
  its own grows over loading and six inferences. Browsers run once, single-threaded as pages are not cross-origin
  isolated, and their memory is not measured.
* `PHOTOLIB_ML_MODELS=all flutter test` and, with `CHROME_EXECUTABLE=tool/chrome_webgpu.sh` for WebGPU,
  `PHOTOLIB_ML_MODELS=all dart test -p chrome -p firefox -c dart2js test/web_test.dart` in the package reproduce the
  numbers (about 3 GB in `PHOTOLIB_TOOLS_CACHE`); `python3 tools/ml/fetch.py --sizes <name>...` the sizes.

Machine: Linux x64, Intel Core Ultra 7 356H, 16 threads, no GPU; ONNX Runtime 1.31.0, onnxruntime-web 1.30.0, Chrome
for Testing 155 and Firefox 158, headless. Other builds shared the machine, so runs of one model vary by up to 2×.

## Models

| Model | File | Licence | Bytes | gzip |
|---|---|---|---|---|
| yunet | YuNet 2026may (face detection, any input size) | MIT† | 229,738 | 202,059 |
| sface | SFace 2021dec (face embedding, 128-d) | Apache-2.0† | 38,696,353 | 35,912,358 |
| sface-int8 | the same, quantised by OpenCV | Apache-2.0† | 9,896,933 | 7,081,754 |
| siglip2-vision | SigLIP 2 B/16-256 image tower, fp32 (768-d) | Apache-2.0 | 371,992,072 | 345,475,373 |
| siglip2-vision-fp16 | the same, fp16 weights | Apache-2.0 | 186,131,676 | 172,087,038 |
| siglip2-vision-int8 | the same, int8 (dynamic quantisation) | Apache-2.0 | 94,737,653 | 73,054,199 |
| siglip2-text | SigLIP 2 B/16-256 text tower, fp32 (768-d) | Apache-2.0 | 1,129,469,657 | 1,057,930,709 |
| siglip2-text-fp16 | the same, fp16 weights | Apache-2.0 | 564,862,230 | 530,530,086 |
| siglip2-text-int8 | the same, int8 (dynamic quantisation) | Apache-2.0 | 283,438,275 | 175,761,204 |
| ppocr-v5-det | PP-OCRv5 server detector of lines of text (M5-08, any input size) | Apache-2.0 | 88,030,804 | 79,344,932 |
| ppocr-v5-rec-latin | PP-OCRv5 Latin recogniser (504 classes) | Apache-2.0 | 7,862,832 | 7,260,422 |
| ppocr-v5-rec-eslav | PP-OCRv5 East Slavic (Cyrillic) recogniser (519 classes) | Apache-2.0 | 7,870,092 | 7,297,744 |
| ppocr-v5-rec-chinese | PP-OCRv5 Chinese and Japanese recogniser (18,385 classes) | Apache-2.0 | 84,468,836 | 76,172,395 |

The SigLIP 2 files are onnx-community's exports, the face models OpenCV Zoo's. † Trained on data with restrictive or
undisclosed terms (design 09 §2.1).

## ONNX Runtime's size

| Target | Package | Library | Bytes | gzip |
|---|---|---|---|---|
| android-arm64 | onnxruntime-android 1.31.0 (AAR) | `jni/arm64-v8a/libonnxruntime.so` | 34,208,680 | 12,863,219 |
| android-arm | the same | `jni/armeabi-v7a/libonnxruntime.so` | 24,182,012 | 11,622,675 |
| android-x64 | the same | `jni/x86_64/libonnxruntime.so` | 40,827,944 | 14,934,208 |
| ios-arm64 | onnxruntime-c 1.30.0 (CocoaPods, static) | `onnxruntime.framework/onnxruntime` | 48,039,496 | 12,081,678 |
| macos-arm64 | onnxruntime-osx-arm64 1.31.0 | `libonnxruntime.1.31.0.dylib` | 44,830,288 | 12,524,281 |
| windows-x64 | onnxruntime-win-x64 1.31.0 | `onnxruntime.dll` | 17,253,176 | 6,308,414 |
| linux-x64 | onnxruntime-linux-x64 1.31.0 | `libonnxruntime.so.1.31.0` | 29,345,384 | 11,112,796 |
| linux-arm64 | onnxruntime-linux-aarch64 1.31.0 | `libonnxruntime.so.1.31.0` | 25,266,408 | 10,067,228 |
| web (WebGPU and CPU) | onnxruntime-web 1.30.0 | `ort.webgpu.bundle.min.mjs`, `ort-wasm-simd-threaded.asyncify.wasm` | 26,899,646 | 6,615,923 |
| web (CPU only) | the same | `ort.wasm.bundle.min.mjs`, `ort-wasm-simd-threaded.wasm` | 14,312,951 | 3,677,344 |

The Android libraries pass `tools/page_size.py` (16 KB pages). iOS's 1.31.0 pod was not yet published, and its static
archive is an upper bound on what linking adds to an app. The Linux library has only the CPU execution provider:
asking it for XNNPACK, WebGPU, CoreML, QNN or OpenVINO fails with "not supported in this build".

Apps bundle these libraries through `photolib_ml`'s build hook (`hook/build.dart`): it takes the archive
`tools/ml/artefacts.json` pins from the directory `hooks.user_defines.photolib_ml.runtime` names, else downloads it,
checks its SHA-256 and extracts the target's library; iOS links the xcframework instead, and 1.31.0 has no Intel Mac
build. `bash tools/ml/ort_android.sh`, outside the gate, builds the Android libraries with only the operators of
`tools/ml/ort-ops.config`, which `python3 tools/ml/ort_ops.py` writes from the registry's Android models; their sizes
are not measured yet.

## Linux x64

The CPU execution provider, 4 threads:

| Model | Load (ms) | First (ms) | Run (ms) | RSS (MB) | Cosine |
|---|---|---|---|---|---|
| yunet | 9 | 11 | 4.5 | 54 | 1.000000 |
| sface | 58 | 13 | 9.3 | 62 | 1.000000 |
| sface-int8 | 26 | 12 | 9.0 | 38 | 0.957401 |
| siglip2-vision | 697 | 153 | 116.9 | 666 | 1.000000 |
| siglip2-vision-fp16 | 408 | 135 | 128.3 | 494 | 0.999998 |
| siglip2-vision-int8 | 116 | 56 | 43.7 | 206 | 0.916186 |
| siglip2-text | 1,743 | 35 | 32.9 | 1,372 | 1.000000 |
| siglip2-text-fp16 | 960 | 42 | 38.0 | 824 | 1.000000 |
| siglip2-text-int8 | 357 | 20 | 14.8 | 361 | 0.973365 |

PP-OCRv5 (M5-08) was measured later, on Linux arm64 (the CPU provider, 4 threads, ONNX Runtime 1.31.0 for aarch64) and
not on the machine above: the detector on a 64 × 64 picture, each recogniser on 48 × 48. The goldens are the fp32
models' own outputs; a real line is longer (`docs/adr/0388-ocr-and-text-search.md`; the Latin, Cyrillic and CJK
pictures of `testdata/ocr/` read in 0.3–0.5 s each through the whole pipeline on this host).

| Model | Load (ms) | First (ms) | Run (ms) | RSS (MB) | Cosine |
|---|---|---|---|---|---|
| ppocr-v5-det | 80 | 11 | 8.3 | 184 | 1.000000 |
| ppocr-v5-rec-latin | 35 | 2 | 1.7 | 1 | 1.000000 |
| ppocr-v5-rec-eslav | 35 | 2 | 1.6 | 0 | 1.000000 |
| ppocr-v5-rec-chinese | 63 | 7 | 7.3 | 162 | 1.000000 |

## Browsers

Single-threaded wasm in Chrome 155 and Firefox 158, and WebGPU in Chrome 155 on SwiftShader, its CPU implementation
of a GPU (`--enable-unsafe-webgpu`, no `shader-f16`): its times say nothing about real GPUs, its cosines test the
WebGPU kernels. All with dart2js; the face models' times with dart2wasm were within the runs' spread.

| Model | Chrome 155 wasm: Run (ms) | Cosine | Firefox 158 wasm: Run (ms) | Cosine | Chrome 155 WebGPU: Run (ms) | Cosine |
|---|---|---|---|---|---|---|
| yunet | 44.9 | 1.000000 | 37 | 1.000000 | 4,176 | 1.000000 |
| sface | 39 | 1.000000 | 41 | 1.000000 | 2,845 | 1.000000 |
| sface-int8 | 226 | 0.957401 | 158 | 0.957401 | 1,130 | 0.957401 |
| siglip2-vision | 1,185 | 1.000000 | 1,172 | 1.000000 | 26,633 | 1.000000 |
| siglip2-vision-fp16 | 1,182 | 0.999998 | 1,203 | 0.999998 | fails: no `shader-f16` | — |
| siglip2-vision-int8 | 620 | 0.918151 | 745 | 0.918151 | 12,321 | 0.924209 |
| siglip2-text | 295 | 1.000000 | 288 | 1.000000 | 10,916 | 1.000000 |
| siglip2-text-fp16 | 313 | 1.000000 | 291 | 1.000000 | fails: no `shader-f16` | — |
| siglip2-text-int8 | 153 | 0.973161 | 168 | 0.973161 | 936 | 0.971781 |
| ppocr-v5-det | 49.8 | 1.000000 | 781 | 1.000000 | fails: no adapter | — |
| ppocr-v5-rec-latin | 7.4 | 1.000000 | 101 | 1.000000 | fails: no adapter | — |
| ppocr-v5-rec-eslav | 7.3 | 1.000000 | 101 | 1.000000 | fails: no adapter | — |
| ppocr-v5-rec-chinese | 43.8 | 1.000000 | 701 | 1.000000 | fails: no adapter | — |

The PP-OCRv5 rows are Chromium 131 and Firefox 132 (Playwright's builds) on the Linux arm64 host, dart2js, wasm only:
neither had a WebGPU adapter there.

Loading took 0.3–0.7 s for the face models and 0.9–8 s for SigLIP 2, the fp32 text tower included. An fp16 model
fails on WebGPU without `shader-f16` ("Program Cast requires f16 but the device does not support it"), and without
an adapter at all (Chrome without the flag, Firefox) a WebGPU session fails too: neither falls back to wasm. One of
two runs of the fp32 text tower on WebGPU lost the device while reading its output back; the other passed.

## Parity

* **fp32 reproduces the CPU everywhere**: cosine ≥ 0.999999 on wasm in both browsers and on WebGPU.
* **fp16 weights pass**: 0.999998 for the image tower, 0.9999998 for the text tower, on the CPU and on wasm; on
  WebGPU they need an adapter with `shader-f16`, which SwiftShader lacks.
* **The published int8 exports fail** design 09's bar of 0.99: 0.916–0.924 for the image tower, 0.972–0.973 for
  the text tower, 0.957 for SFace. Re-quantising the fp32 models with ONNX Runtime 1.31's `quantize_dynamic`, int8
  weights per channel, gave 0.918, 0.971 and 0.982; quantising only the text tower's embedding table (its `Gather`;
  197M of its 282M parameters) gave 0.99897 at 539 MB with the rest in fp32. These were one-off Python runs, not in
  the gate.
* **int8 is not even faster everywhere**: on single-threaded wasm, int8 SFace takes 4–6× as long as fp32.

## Against design 09

| Design figure | Result |
|---|---|
| Text tower ≤ 100 ms on 4 x86 cores (§4.5, int8) | 33 ms in fp32 and 38 ms in fp16 on 4 threads; int8 is not needed for speed |
| Image tower 75 ms on an i9 (research §11.4) | 117 ms in fp32, 128 ms in fp16 on 4 threads |
| Cosine ≥ 0.99 to the fp32 CPU reference per execution provider (§3.2) | fp32 and fp16 pass on the CPU, wasm and WebGPU; int8 fails |
| Runtime upgrades reproduce the goldens at 0.999 (§12.3) | the gate checks it on every run |
| Search, faces and OCR download 450–550 MB (§12.2) | 790 MB in fp16 without OCR: image 186, text 565, SFace 39, YuNet 0.2 |
| ≥ 1 photo/s on a mid-range phone while charging (§13) | unmeasured; on this desktop a photo with two faces takes about 140 ms |
| 30 MB per ABI for the APK (open decision 14) | the full ONNX Runtime takes 12.9 MB of it, compressed |

## Not measured here

| What | Why | How |
|---|---|---|
| Android and iOS: latency, memory, energy and heat | no phone, and no KVM for an emulator | M0-27's device lab: the native test as an integration test, with batterystats and the thermal status on Android and Xcode's energy gauge on iOS over ten minutes of indexing |
| macOS, Windows, Linux arm64 | no such machine | `flutter test` in `photolib_ml` picks the pinned library for the machine |
| CoreML, XNNPACK, NNAPI, QNN, DirectML | not in the Linux package; no hardware | the device lab, with the golden check per provider |
| WebGPU on real GPUs, fp16 shaders | no GPU; SwiftShader has no `shader-f16` | a desktop with a GPU |
| Safari | not Linux | `bash tools/check.sh web` adds it on macOS |
| Browser memory | `measureUserAgentSpecificMemory` needs cross-origin isolation | — |
