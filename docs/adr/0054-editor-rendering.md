# ADR-0054 — Editor rendering: Flutter shaders for the preview, the kernel's CPU renderer for every export

* **Status**: Accepted (owner answered, 2026-10-17) in
  photolib-design#365
  (roadmap M0-36; decides the design's ADR-0014 and open decision 12): the owner chose A′ instead of the spike's
  provisional A on Impeller.
* **Requirements**: F-10, F-05. **Design**: 11 §4, ADR-0014.

## Context

ADR-0014 left the renderer open between Flutter fragment shaders with a CPU reference renderer in the
kernel (A) and a Rust/wgpu engine (B), with a fixed decision rule: everything passes → A; parity passes but precision,
memory or export time fails → A′ (shaders for the preview, every export on the CPU); parity or interactivity fails → B.
The [spike report](../dev/editor-rendering.md) has the numbers. Measured here, without a phone or a GPU: the shaders
match the reference within mean ΔE2000 0.072 and p99 1.07 on every renderer (flutter_tester, the Linux embedder on
Impeller and on Skia, Chrome on CanvasKit and Skwasm); a tiled export at 12–200 MP matches its preview within mean
0.27, p99 0.80; no stress card bands; the CPU renderer adds 56–61 KB per native library. A 200 MP export stays at
81 MiB above the baseline on Impeller and 17 MiB in the kernel, but grows by 5.4 MiB per tile on Skia, which frees
uploaded tiles too late. A wgpu probe of the point adjustments alone is 7.4–7.8 MB per ABI. Frame times and the phones
remain unmeasured.

## Decision

We will render the preview with Flutter fragment shaders on every backend and every export with the kernel's CPU
reference renderer (`METHOD_DEVELOP`): foreground, background, batch, server, CLI, iOS-extension and gain-map exports
alike, their tiles spread over worker isolates (web workers on the web) across all cores. The kernel's renderer is the
specification: each operation is written there and in GLSL, and the parity suite holds them together.

* **One export path, no routing by backend.** The kernel is pure Rust with a portable libm, so a version renders
  identically on phones, desktops, the web, the server and the CLI, as design 11 principle 9 requires, while shader
  output depends on the GPU driver and the Flutter version. It needs 17 MiB at 200 MP against 81 MiB on Impeller and
  1 GiB on Skia, and it can be measured without the device lab, which comes only with the test phase.
* **Saving stores the recipe and the version at once**; the version's full render runs in the background, so only an
  explicit export or share waits for it. An edit written back to Apple Photos or MediaStore completes when its render
  does.

## Consequences

* The shaders follow the spike's rules: one pass for every point operation and the LUT, 16-bit values in two 8-bit
  channels between passes and in LUT atlases, opaque input, a shader per pass disposed after it renders, and a guide
  computed once from the proxy that the preview and every tile share.
* The parity suite (shaders against the kernel, preview = export) stays in the gate, in flutter_tester and Chrome; a
  Flutter upgrade or an operation that changes one implementation without the other fails it.
* The probe records the export time with tiles across all cores at 12, 50 and 200 MP on this machine (the report);
  the 50 MP ≤ 10 s target on the reference phone is checked in the test phase. Memory grows with the workers: at
  200 MP, 188–222 MiB above the baseline on 4 (a phone's pool) and 680–723 MiB on 16.
* If the test phase shows phone exports too slow, the GPU export on Impeller (A) comes back as an optimization behind
  the same parity suite; recipes and versions do not change.
* Gain maps are edited only by the kernel; writing them into Ultra HDR and HEIC containers is M8-07.
* The edit recipe of design 11 §2.2 stands as sketched; M8-01 writes it and replaces `METHOD_DEVELOP`'s spike messages.

## Options considered

* **A, shaders for the preview and the foreground export on Impeller, the kernel elsewhere** (the spike's provisional
  choice): GPU exports on phones, but two export paths routed by backend, pixels that depend on the driver and the
  Flutter version, and 81 MiB at 200 MP.
* **B, a Rust/wgpu engine**: B stays rejected. As exact (f32), but its library alone is 7.4–7.8 MB per ABI against
  ADR-0004's 3 MB, and it needs five texture interops.
