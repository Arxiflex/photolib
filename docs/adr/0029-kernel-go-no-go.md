# ADR-0029 — Kernel go/no-go: the Rust kernel ships on all targets

* **Status**: Accepted — 2026-10-16 (roadmap M0-14, the gate of ADR-0004). Not wanting Go in the codebase, the owner
  answered "probably rust?"
  (photolib-design#305).
  That is this decision: "go" is ADR-0004's go/no-go, not the Go language, and what ships is the Rust kernel; Photolib
  has no Go code. The owner confirmed this reading
  (photolib-design#317).
* **Requirements**: R-APP-1, R-APP-3, R-PRIV-1, F-09, NFR-PERF-*. **Design**: ADR-0004.

## Context

ADR-0004 made the shared Rust kernel conditional on a spike: build three representative functions for
every target and pass its criteria, else fall back to Dart on the web (if the web fails) or to a pure-Dart client
(if native targets fail). The spike's kernel builds for all 11 native targets and the web (M0-11 to M0-13). The
[go/no-go report](../dev/kernel-go-no-go.md) has its numbers: every measured result, native and in the latest two
Chrome and Firefox with dart2js and dart2wasm, clears its threshold by at least 3×. Phones, the CI-only targets and
Safari were not measured.

## Decision

We will go on all targets with the Rust kernel: native apps link the prebuilt kernel through the C ABI
([ADR-0026](0026-kernel-prebuilt-libraries.md)), and Flutter web (dart2js and dart2wasm) and the viewer load its
WebAssembly module. No Dart implementation of kernel functions is written. The criteria stay enforced:
`tools/kernel/build.py` fails a library over 3 MB, `tools/kernel/wasm.sh` a module over 1 MB brotli, and the
report's benchmark fails the gate (in Chrome) and CI's desktop probes below the speed thresholds.

## Consequences

* No roadmap task changes: the fallbacks are not needed.
* A larger library fails CI on every target; a slower kernel fails it on the desktops and in Chrome.
* Phones remain to be measured on M0-27's devices; EXIF's 250× margin on the desktop makes a miss unlikely, and a
  miss there would be fixed in the kernel, since a Dart parser would not be faster.
* On dart2wasm, bytes in Dart's heap are copied into JavaScript on each call, which halves decrypt throughput; web
  callers should pass bytes they already hold in a JavaScript buffer (a `Blob` or `fetch` result), which costs no copy.

## Options considered

* **Go native, Dart on the web**: the web passes every threshold, so a second implementation would only add the
  divergence risk that ADR-0004 exists to remove.
* **Pure-Dart client**: native targets pass by 5× or more, and post-quantum crypto would be weak in Dart.
