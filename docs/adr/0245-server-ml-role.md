# ADR-0245 — The server's ML role: ONNX Runtime loaded at run time, golden self-tests per backend, a memory limit

* **Status**: Accepted — 2026-10-23 (roadmap M5-02). The owner kept all three decisions as made: SigLIP 2's fp16
  text tower on the server too, one shared bearer token (`ml.token`) for remote nodes, and 2 GB read as
  2,000,000,000 bytes
  (photolib-design#710).
* **Requirements**: F-01, F-02, NFR-SCALE-2. **Design**: 09 §3.2, §12.3, 03 §3.1.

## Context

Design 09 §3.2 runs the server's models in an `ml` role on `ort`, pinned exactly, on the best execution provider
(EP) of the machine: CUDA, OpenVINO, ROCm, CoreML, else the CPU. Accelerators fail numerically and silently: Immich
served wrong OpenVINO embeddings for months. So each (model, EP) must reproduce the model's golden outputs at
startup or be disabled with an admin warning and a metric, memory must stay bounded (at most 2 GB for the default
profile, flat over a 24 h soak) and a remote node must authenticate. ADR-0050 measured the models on ONNX Runtime
1.31; ADR-0064 made the registry.

Measured here (Linux x64, ONNX Runtime 1.31.0's official CPU build): SigLIP 2's fp32 text tower alone peaks at
1.83 GiB while ONNX Runtime loads it; with the fp32 image tower and glibc's default allocator the default profile
peaked at 2.76 GiB, and with every model unloaded 1.26 GiB stayed resident, kept by glibc's per-thread arenas.

## Decision

* **A crate, `photolib-ml`, on `ort` 2.0.0-rc.14 with `load-dynamic`.** photolibd links no ONNX Runtime: the role
  loads the library `ml.runtime` names (`libonnxruntime.so` by default), the official CPU build or one the
  administrator chose for the machine's accelerators. The build needs no download, and a node gets CUDA or OpenVINO
  by installing that build. The workspace's `rust-version` moves to 1.92, which `ort` needs.
* **Backends in design 09's order: CUDA, OpenVINO, ROCm (ONNX Runtime's MIGraphX provider), CoreML, CPU.** A backend
  exists if the loaded library has its provider; each session names one, with `error_on_failure`, and the CPU without
  an arena. TensorRT, RKNN and Hailo come with accelerator packs later.
* **Golden self-test at every start.** Each registry file the server runs carries a golden: inputs made by code (the
  synthetic picture and tokens of `app/packages/photolib_ml`'s spike) and 1,024 evenly spaced values of its outputs
  on the fp32 model and ONNX Runtime's CPU, the same values as the spike's `golden.json`. The CPU must reach cosine
  ≥ 0.999 to them (design 09 §12.3: a runtime that drifts stops the model), every other backend ≥ 0.99 (§3.2), and
  only once the CPU passed. The first backend that passes runs the file. Each disabled backend is logged, exported as
  `photolib_ml_backend_disabled{node,file,backend}` (alert `PhotolibMlBackendDisabled`) and named in the doctor's
  `ml` check, which the admin console shows. A file without a golden (a bring-your-own model whose manifest has none)
  runs nowhere. Detection models are compared by the cosine of their raw outputs too, until the kernel decodes boxes
  (M5-09) and IoU can be compared.
* **Memory: buckets, one session per file, a limit on resident memory.** Batches have 1, 8 or 32 items (the largest
  that fits, never padded; a model of fixed batch size runs one at a time), runs are one at a time, a file unloads
  after 5 minutes unused, and `ml.memory_mb` (2000 by default) caps the process: a load or a batch must fit its cost,
  measured by the self-test on the CPU, beside the resident memory of now, else the least recently used file unloads
  and the batch shrinks. A process that runs the role restarts itself once with glibc's `MALLOC_ARENA_MAX=2` and
  fixed mmap and trim thresholds of 128 KiB, which return what ONNX Runtime frees (36–61 MiB stay, not 400–650).
* **The server's text tower is the fp16 file** (565 MB; cosine 0.999998 to fp32, ADR-0050), not fp32: the fp32 one
  alone fills the 2 GB. This amends ADR-0050's "fp32 stays the server's CPU format" for the text tower only; M5-04,
  which settles the text tower (an int8 embedding table is about 370 MB), may change it again.
* **Remote nodes report with a token.** `photolibd --role=ml` needs no database; with `ml.server` and `ml.token` it
  sends its self-test to `POST /ml/v1/report` of that API every 5 minutes, over HTTPS (HTTP only on loopback). The API
  takes reports only from the bearer of its own `ml.token` (compared in constant time; without one there is no
  endpoint) and keeps them in memory, warning of a node silent for 15 minutes. The work protocol — claiming jobs,
  fetching renditions by signed URL, returning outputs — joins the same endpoint and token when the first ML job
  arrives (M5-04).

## Consequences

* The default profile — SigLIP 2's fp32 image and fp16 text towers with YuNet and SFace — measured a 1,575 MiB
  (1.65 GB) peak and a flat 1,396–1,397 MiB over 15 minutes and 28 rounds, by `tests/memory.rs` of `photolib-ml`
  (`PHOTOLIB_ML_MODELS=all PHOTOLIB_ML_SOAK_SECS=86400` runs the design's 24 h by hand). The gate runs the face
  models for 20 s. A smaller limit only unloads and shrinks batches more often.
* The gate fetches ONNX Runtime and the face models before it blocks egress; GPU providers are not tested here: they
  need a machine with the GPU and a matching ONNX Runtime build.
* Reports live in the API's memory: behind several API replicas each keeps those it received, and a restart forgets
  them until the next report, 5 minutes later. A table of nodes comes with the work protocol.
* The image (`deploy/Dockerfile`) is Alpine, and ONNX Runtime's official builds need glibc: until the image has a
  glibc variant or a musl build, ML runs on a node installed from the binary.
* One shared token means every node is trusted alike and rotating it touches all of them; mTLS or per-node tokens
  can replace it without changing the protocol.

## Options considered

* **Linking ONNX Runtime at build time (`ort`'s `download-binaries`)**: one CPU build for everyone, fetched by the
  build from pyke's servers; accelerators would need a rebuild.
* **Trusting accelerators, or comparing only at first use**: the failure Immich shipped; a driver update changes the
  outputs without a new model, so the self-test runs at every start.
* **A budget from file sizes, or from the self-test's costs alone**: both underestimated what glibc keeps; the
  resident memory of now is what the limit is about.
* **jemalloc or mimalloc for photolibd**: they would replace only Rust's allocations, not ONNX Runtime's C++ ones,
  unless they override `malloc` for the whole process.
* **mTLS between node and API**: stronger identity per node, but a CA to run; a token over HTTPS matches
  `metrics.token`, and mTLS can come later.
* **The fp32 text tower with a 3 GB limit**: misses design 09's 2 GB on the NAS-class machines it targets.
