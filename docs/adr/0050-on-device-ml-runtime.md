# ADR-0050 — On-device ML runtime: ONNX Runtime through its C API, fp16 models, accelerators behind a golden check

* **Status**: Accepted — 2026-10-16 (roadmap M0-34). The owner confirmed all three choices: the C API binding, fp16
  weights and the accelerator policy
  (photolib-design#343).
* **Requirements**: F-01, F-02, R-PRIV-1, NFR-PRIV-1. **Design**: 09 §2–3, §12,
  10 §1.

## Context

Design 09 runs the same models, with the same pre- and post-processing, on the server, the devices and the web, and
leaves this spike the client binding (09 §3.1: a thin binding of ONNX Runtime's official packages,
`flutter_onnxruntime`, or Ente's Rust `ort` over FFI), the precision devices run and the accelerators they may use.
Accelerators that silently return wrong outputs are the known failure: Immich served wrong OpenVINO embeddings for
months and re-clustered named people away.

The [spike report](../dev/ml-runtime.md) ran SigLIP 2 B/16-256, YuNet and SFace on ONNX Runtime 1.31.0 on Linux x64
and onnxruntime-web 1.30.0 in Chrome and Firefox. fp32 and fp16 weights reproduce the CPU's golden outputs on the CPU,
wasm and WebGPU (cosine ≥ 0.999998), though WebGPU runs fp16 only with `shader-f16`. The published int8 exports miss
design 09's 0.99 (0.916–0.924 image, 0.972–0.973 text, 0.957 SFace); int8 for the text tower's embedding table alone
keeps 0.999. ONNX Runtime is 34 MB on arm64 Android (13 MB compressed) and 27 MB of wasm (6.6 MB gzip).
`flutter_onnxruntime` 1.9.0 copies every tensor through a method channel and pins ONNX Runtime 1.28.0 on Android.
Phones, Apple platforms, Windows and real GPUs could not be measured here.

## Decision

* **Runtime: ONNX Runtime everywhere**, from its official packages pinned by version and SHA-256: the Maven AAR on
  Android, the `onnxruntime-c` xcframework on iOS, the release archives on macOS, Windows and Linux, and
  onnxruntime-web on the web. The server's `ort` (design 09 §3.2) wraps the same version.
* **Binding: a thin `dart:ffi` binding of ONNX Runtime's C API** (`app/packages/photolib_ml`, option (a)). It
  reaches every function through the table that `OrtGetApiBase` returns, works on any isolate and hands ONNX Runtime
  tensors in native memory, so an input filled on one isolate runs on another without a copy. On the web the same
  API binds onnxruntime-web with `dart:js_interop`, single-threaded, loaded only when needed.
* **Model format: ONNX, fp16 weights with fp32 inputs and outputs on devices.** fp32 is the reference the golden
  outputs come from, and stays the server's CPU format. An int8 model is used only where it passes the golden check;
  stock dynamic quantisation does not.
* **Accelerator policy: the CPU always works; an accelerator must first prove itself.** A session names exactly one
  execution provider and fails when the runtime lacks it, never falling back silently. Before a model first runs on
  an accelerator (CoreML, XNNPACK, QNN, DirectML, WebGPU) on a device, and again after any runtime or driver change,
  it runs the manifest's golden input and must reach cosine ≥ 0.99 to the fp32 CPU output (embeddings); a mismatch or
  three failures to run quarantine that provider for that model, and the CPU runs it. A runtime upgrade must
  reproduce the CPU goldens at 0.999. Every output records the provider and precision (`rt_flags`). NNAPI is not
  used; Android accelerators are enabled per device class only after M0-27's device lab measures them.

## Consequences

* The binding, the golden check and the browser runs are in the gate: `flutter test` in `photolib_ml` checks the CPU
  and `bash tools/check.sh web` wasm and WebGPU, against the same `golden.json`.
* The full ONNX Runtime takes 13 MB of a 30 MB per-ABI APK budget (open decision 14). Before it ships (M5-03), a
  build reduced to the pinned models' operators must bring it down; that build is new CI work.
* iOS has only a static xcframework: it links into the app and Dart finds it with `DynamicLibrary.process()`, so only
  `OrtGetApiBase` must survive dead-stripping. The build hook that bundles the other targets' libraries, as
  [ADR-0026](0026-kernel-prebuilt-libraries.md) does for the kernel, is M5-03's.
* fp16 downloads are 186 MB (image) and 565 MB (text), above design 09's 283 MB int8 text tower; an int8 embedding
  table with fp16 elsewhere, about 370 MB, is M5-04's to build and check. fp16 runs 1.1–1.2× slower than fp32 on this
  x86 CPU and on WebGPU only with `shader-f16`; M5-03 decides with real GPUs whether GPUs without it get fp32 files.
* Still unmeasured: latency, memory, energy and heat on phones; CoreML, XNNPACK, QNN, DirectML; WebGPU on real GPUs;
  Safari. The same tests run on any desktop, and phones need M0-27's device lab.

## Options considered

* **`flutter_onnxruntime`** (b): copies every tensor through a method channel, ties inference to the platform thread
  and follows its own ONNX Runtime pin.
* **Rust `ort` over FFI** (c), as Ente does: shares code with the server, but adds a second native build per target and
  a release-candidate crate over what is already a stable C API; the kernel must stay free of C (ADR-0004).
* **int8 by default**: halves the downloads, but the available exports fail the golden check by a wide margin.
* **ORT format with minimal builds now**: the smallest binaries, but a second model format before any model ships;
  the operator-reduced build above keeps ONNX.
* **LiteRT or platform frameworks (Core ML, ML Kit)**: no single format across the six targets and the server, so
  vectors would not be comparable.
