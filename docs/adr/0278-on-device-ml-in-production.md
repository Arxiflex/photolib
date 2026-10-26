# ADR-0278 — On-device ML in production: models from the user's server, gated indexing, results handed off

* **Status**: Accepted — 2026-10-23. The owner kept all six decisions: no manifest signature until a signing key
  exists, lite mode below 3.5 × 10⁹ bytes, new captures as the last 24 hours' in the foreground two at a time, battery
  thresholds of 10, 20, 30 or 50 %, no mirror for a connected app whose server lacks the model, and the registry's
  first image-text embedding as the active model
  (photolib-design#689).
* **Requirements**: F-01, F-02, R-MODE-1, R-PRIV-1, NFR-PRIV-1. **Design**: 09 §2.2–2.3, §3.2–3.4, §12,
  10 §1.5; follows [ADR-0254](0254-on-device-ml-runner.md), [ADR-0050](0050-on-device-ml-runtime.md) and
  [ADR-0064](0064-model-registry-and-licence-gate.md).

## Context

ADR-0254 built the runner, the kernel's preprocessing and a resumable indexer, but devices indexed nothing: no model
reached them, no runtime was bundled, nothing started the indexer, iOS and macOS reported no health, design 09 §3.4's
other gates were missing, failures were kept but not shown, and results stayed on the device
(photolib-design#645).

## Decision

* **The registry says what devices run.** An embedding model records its `preprocess` (size, means, stds) and `dim`;
  every file a device runs carries a `golden` in M5-02's format (the synthetic picture's fill and the fp32 CPU sample).
  Apps compile in a copy (`photolib_ml/lib/src/registry.g.dart`, `dart run tool/registry.dart`), held to the server's
  by a test, which also serves standalone apps.
* **Models arrive after consent.** Settings' *Search on this device* names the model's size and the host it comes
  from. Connected apps download only from their photolibd (`GET /models/{id@revision}/{file}`, ranges, a session or an
  API key; `photolibd models fetch` installs the files devices run too) and wait when it lacks the model; standalone
  apps use the registry's mirrors. Downloads wait for an unmetered network unless *Download over mobile data* is on,
  resume from a `.part` file and are kept only when their size and SHA-256 are the registry's. The registry compiled
  into the app is the trust anchor, as ADR-0064 has it for photolibd; no manifest signature exists yet.
* **ONNX Runtime is bundled** by `photolib_ml`'s build hook from the archives `tools/ml/artefacts.json` pins, checked
  by SHA-256 (ADR-0050); iOS links the static xcframework. The operator-reduced Android build is
  `tools/ml/ort_android.sh` over `tools/ml/ort-ops.config`, run outside the gate.
* **The data isolate indexes.** `startMl` sends it an `MlSetup`: the runner on the bundled runtime, `prepareImage` on
  its worker pool beside metadata extraction, and the platform's decoder to upright 8-bit sRGB RGBA whose short side is
  at most 720 px (thumb_m): libvips on desktops, `ImageDecoder` on Android, PhotoKit on iOS, through `org.photolib/ml`.
* **The gates are the user's to move, but heat.** Battery threshold (10, 20, 30 or 50 %, 20 by default), *Also in power
  saving mode*, *Only while charging*; heat always holds. The user scrolling or editing holds the next chunk until 5 s
  after the last interaction (`reportInteraction`, at most once a second); an upload batch holds it (`reportUploads`,
  for the backup engine to call). Lite mode is a device reporting under 3.5 × 10⁹ bytes of RAM, as a 4 GB phone
  reports about 3.7 × 10⁹.
* **Phones index new captures in the foreground, their backlog in the background.** New captures are the photos the
  device index added in the last 24 hours, first in the order new → favourites → last 12 months → rest, two at a time.
  The backlog runs in WorkManager (charging, battery not low) or `BGProcessingTask` (external power), on the
  process's one engine (design 10 §1.5): Android's engine now lives in `PhotolibApplication`, which WorkManager starts
  headless; iOS runs it when the app's engine is alive. Lite mode schedules no backlog. Desktops index everything in
  the foreground.
* **Failures are visible and retried.** A photo that does not decode is kept as `unreadable by <decoder>`
  (`vips 8.15.1`, `android <version>`), read again once another decoder runs, and listed in Settings with why; a new
  model revision reads everything again.
* **Results travel.** An upload hands off its vector for the active model (the registry's first image embedding, until
  libraries have their own) as `photolib-ml-*` headers, half floats; photolibd keeps it in `asset_embeddings` for a
  standard library after the dimension, finiteness, norm and `rt_flags` checks, the first vector winning. A private
  library's file gets a `meta_ml` section instead: the vector as half floats with its model and `rt_flags`, sealed
  padded under the file's EmbedKey (PLB content kind 5, `sealMlSection`). `local_ml` keeps half floats too.

## Consequences

* Indexing runs on every native target once the user agrees, and its parity with the server is ADR-0254's.
* Not yet: the server's 1 % spot-check of handed-off vectors (M5-04's embedding jobs), private uploads that carry the
  sealed section (M6-04), the backup engine that calls `reportUploads` and hands vectors off, iOS's headless engine at
  a background launch, a project mirror and a signed manifest, and a measured reduced Android runtime.
* Native code (Kotlin, Swift) is checked as text by `tools/tests/test_ml_native.sh`; devices verify it in the test
  phase.

## Options considered

* **A second engine for background work** (`workmanager`'s dispatcher): design 10 §1.5 forbids it, a second writer.
* **Falling back to the mirror when the user's server lacks the model**: NFR-PRIV-1 has connected apps reach only
  their server.
* **A decoder version column in `local_ml`**: a schema migration for what the failure text already says.
* **Lite mode at exactly 4 × 10⁹ bytes**: every 4 GB phone would be lite, as each reports less.
