# ADR-0254 — On-device ML runner: kernel preprocessing, the ML isolate's golden check and a resumable gated indexer

* **Status**: Accepted (owner answered photolib-design#644, 2026-10-23: each model's own preprocessing, half-float
  vectors on devices).
* **Requirements**: F-01, F-02, R-MODE-1, R-PRIV-1. **Design**: 09 §2.2, §3.3–3.4,
  10 §1.4–1.5, 04 §11 (`local_ml`); builds on [ADR-0050](0050-on-device-ml-runtime.md).

## Context

Roadmap M5-03 runs the registry's models on devices (ADR-0050 chose ONNX Runtime through its C API) so that their
outputs can stand in for the server's: indexing must pause under thermal pressure and resume, and its results must match
the server's embeddings within tolerance. Design 09 leaves open how preprocessing is shared, where an accelerator's
quarantine is kept, what order a backlog runs in and how device results are stored before sync exists.

## Decision

* **Preprocessing is one kernel function**, `METHOD_PREPARE_IMAGE` (`kernel/src/ml.rs`), which prepares an image as
  the model's own processor does: 8-bit RGBA resized with a separable triangle filter (bilinear, widened to the scale
  when shrinking) to the model's square, the whole image as SigLIP 2's does (`google/siglip2-base-patch16-256`: 256 ×
  256, bilinear, no crop, mean and std 0.5), or, for a model whose processor crops, the short side to its size and the
  centred square; each channel scaled to 0–1, less its mean, over its std, laid out planar as float32. Only unfused
  f32 arithmetic in a fixed order, so the server, the C ABI and WebAssembly give the same tensor;
  `kernel/testvectors/ml.json` pins every binding to the Rust build. A request names its size (at most 1024), means,
  stds and whether it crops, the values of the registry entry's `preprocess`.
* **The ML isolate is a `Runner`** (`photolib_ml/lib/runner.dart`): one model on an isolate of its own, run with the
  first execution provider, the CPU last, whose output for the model's golden input reaches cosine 0.99 to the fp32 CPU
  output, the server's. A provider whose output strays is quarantined at once; one that fails to load or run three
  times too, counted before each attempt so a crash counts. The counts are a JSON file per model under a directory the
  caller gives, keyed by the ONNX Runtime version, so an upgrade tries every provider again. `rt_flags` is `onnxruntime
  <version> <provider> <precision>`.
* **The indexer is `MlIndexer`** (`photolib_data/lib/src/ml.dart`): photos the library shows (present, not trashed,
  not in a hidden folder, not videos), favourites first, then the rest, each newest first in the timeline's order, a
  chunk per call and per transaction. Outputs go to `local_ml` (schema 15, a device table that a failed migration keeps)
  keyed by item and `model_id@revision`, with the file's size and mtime it read, as half floats (IEEE 754 binary16,
  little-endian, `halfFloats`), and `rt_flags`; an item that does not decode is kept as failed until its file changes.
  An item waits while it has no row for its file's present version, so a restart or a pause resumes where indexing
  stopped without a cursor of its own.
* **The device's gates are one function**, `backgroundHold`: heat (Android's thermal status above moderate, or the
  battery above 42 °C), then battery saver, then no charger when indexing must charge (the user's "Only while charging",
  off by default), then a battery below 20 % without a charger. While one holds, the indexer stores the chunk under way
  and runs nothing more; it resumes when they let go. Settings shows the hold or how far the model run last has indexed.
* **Parity is tested end to end**: a photo goes through `imageEmbed` (the kernel on the worker pool, then the runner)
  into `local_ml`, and must reach cosine 0.99 to the server's computation of it, the kernel and the fp32 model on the
  CPU: SFace in the gate, SigLIP 2's fp16 vision tower with `PHOTOLIB_ML_MODELS=all` (0.999999 on Linux x64, kept as
  half floats).

## Consequences

* The server's ML role (M5-02) calls the same kernel function, so a device's vectors and the server's start from the
  same tensor; only decoders and execution providers differ, which the golden check bounds.
* What the app still lacked here (bundling, downloads, decoders, background work, the other gates, syncing results)
  [ADR-0278](0278-on-device-ml-in-production.md) builds.
* Vectors are fp16 on devices as on the server (1,536 B at 768-d): the runner's float32 output is converted bit by bit
  in Dart, which has no half-float list, and hand-offs send what `local_ml` keeps. Nothing was stored before, so no
  migration.
* Amendments this needs in the design repository: docs/09 §2.2, each model's own preprocessing (SigLIP 2's whole
  image squashed to its square, a crop only where the model's processor crops) and fp16 vectors on devices.

## Options considered

* **Preprocessing in Dart, checked by vectors**: design 09 §3.1 rejects re-implementations; one Rust function is the
  shared code itself.
* **Bicubic or area resampling**: bicubic overshoots and needs clamping, area averaging aliases when enlarging; the
  triangle filter is exact for flat colour and simple enough to make bit-identical across targets.
* **The short side and a centre crop for every model**, as design 09 §2.2 had it (the provisional choice): it keeps
  proportions, but feeds SigLIP 2, whose processor squashes, inputs unlike its training's and cuts the edges off every
  photo that is not square.
* **float32 on devices** (3,072 B at 768-d), the provisional choice, converted when synced: twice the space for
  precision the server's copy does not keep.
* **Quarantine in the replica**: a crash must be counted before the session loads, outside any transaction, and the
  ML isolate has no replica connection; a small file next to the models does it.
* **A keyset cursor kept in the replica**: rows of `local_ml` already say what is done; a cursor would be a second
  truth to keep in step.
