# Editor rendering spike report (ADR-0014)

The spike of roadmap M0-36 against the pass criteria of design 11 §4.4, measured on 2026-10-16. The
decision is [ADR-0054](../adr/0054-editor-rendering.md).

## What was built

* **CPU reference renderer** (`kernel/src/develop.rs`, `METHOD_DEVELOP`): white balance, exposure, clarity, saturation,
  an S-curve and a 16-bit 3D LUT, after lossless quarter turns and crops; a whole image or one tile of it. Clarity
  compares each pixel with a *guide*: the mean log2 luminance of at most 64 cells on the long side, blurred, computed
  once from the proxy and shared by the preview and every export tile, so tiles need no halo. Native and WebAssembly
  builds give the same pixels (`kernel/testvectors/develop.json`).
* **Ultra HDR gain maps** in the same call: geometry-only edits move the map bit for bit; tonal edits rebuild the HDR
  rendition, apply the adjustments and recompute the map and its headroom (ISO 21496-1 metadata).
* **Fragment shaders** (`app/packages/photolib_editor/shaders`): every adjustment and the LUT in one pass
  (`develop.frag`, the LUT as a 2D atlas with manual trilinear interpolation) and the guide in three passes
  (`guide.frag`, `blur.frag`, 16-bit values in two 8-bit channels). `ShaderRenderer` renders a preview or 1024² tiles of
  a full-resolution export.
* **The probe** (`lib/testing.dart`): synthetic cards, CIEDE2000, the parity set, tiled exports and frame times; the gate
  runs it in flutter_tester and in Chrome.
* **Option B in miniature**: a one-off Rust/wgpu 30.0.1 probe (the point adjustments as a WGSL compute shader), not kept.

## How it is measured

* **Parity**: three cards — a 384×256 landscape with ±4 codes of grain, a dark 1024×16 gradient and a 32×512
  underexposed sky — times 16 recipes: each adjustment at both extremes, a 33³ film LUT, everything at once and the
  precision stress (+2 EV, contrast 1, clarity 0.8). Each shader render is compared with the kernel's; *band* is the
  largest step between neighbouring pixels against the reference's.
* **Export**: the landscape at 12, 50 and 200 MP (4032×3024, 8160×6120, 16320×12240) in 1024² tiles with every
  adjustment, box-filtered in linear light to its proxy (½, ¼, ⅛) and compared with the preview of that proxy. Memory
  is the resident set (native), or the JavaScript heap plus the renderer's WebAssembly memory (web), above the baseline
  after the preview, sampled after each tile. *Time* is rendering and reading back the tiles, without the probe's own
  work.
* **Export on every core** (`exportOnCores`, ADR-0054's export): each tile goes to one of a `WorkerPool`'s isolates,
  one per hardware thread unless `--dart-define=workers=4` (a phone's pool), which makes it as a region decoder would,
  renders it with the kernel and returns it box-filtered. *Time* is the whole export's wall time, the probe's work
  included; memory includes every isolate.
* **Frames**: a 2 MP proxy, each frame read back, since only that waits for the GPU on every backend: upper bounds.
* **Where**: in the gate, `flutter test` in `app/packages/photolib_editor` (flutter_tester: Skia on the CPU) and
  `bash tools/check.sh web` (Chrome); `--dart-define=megapixels=50` or `200` for larger exports. The Linux embedder
  ran the same probe once from a throwaway app, `xvfb-run flutter test integration_test -d linux`, with Impeller (its
  default) and with `--no-enable-impeller`.
* **Machine**: Intel Core Ultra 7 356H, 16 threads, no GPU: Mesa 25.0.7 llvmpipe and lavapipe (LLVM 19.1.7), Chrome for
  Testing 155 on SwiftShader; Flutter 3.47.7. Every GPU number here is software rendering, and the machine is shared.

## Pixel difference and memory

Parity is the worst case of the 48; preview against export is the same for every renderer, the reference included:
mean 0.26, 0.27 and 0.26, p99 0.75, 0.80 and 0.79 at 12, 50 and 200 MP. That residue is the adjustments'
nonlinearity on the grain, not a renderer error.

| Platform | Renderer | Parity: mean / p99 ΔE2000 | Worst band | Export memory, 12 / 50 / 200 MP (MiB) |
|---|---|---|---|---|
| Phone | Impeller (Vulkan, GLES, Metal) | device lab | device lab | device lab |
| Desktop | flutter_tester (Skia on the CPU) | 0.036 / 1.07 | 0 | 48 / 52 / 54 |
| Desktop | Linux embedder, Impeller GLES (the default) | 0.019 / 0.71 | 0 | 135 / — / 81 |
| Desktop | Linux embedder, Skia GL (`--no-enable-impeller`) | 0.072 / 1.07 | 0 | 95 / 260 / 1,024 |
| Desktop | Kernel through the C ABI | reference | reference | 18 / 14 / 17 |
| Desktop | Kernel, tiles on 16 worker isolates | reference | reference | 407–527 / 615–643 / 680–723 |
| Desktop | Kernel, tiles on 4 worker isolates (a phone's pool) | reference | reference | 221 / 185 / 188–222 |
| Web | Chrome 155, CanvasKit (dartdevc) | 0.007 / 0.42 | 0 | 154 / 567 / — |
| Web | Chrome 155, Skwasm (dart2wasm) | 0.007 / 0.42 | 0 | 61 / 225 / — |
| Web | Kernel in WebAssembly | reference | reference | JS heap only: 0 / 175–304 / — |

*Device lab*: no phone and no emulator (no KVM) here. *—*: not run (browsers export up to ~50 MP, design 11 §4.5) or
not isolated from an earlier export in the same process. The web's JavaScript heap includes the probe's garbage (the
reference path's column), so its numbers are upper bounds.

## Export time

Seconds to render and read back every tile, the kernel in one isolate; with its tiles on worker isolates, the wall
time of the whole export (2026-10-20, a load average of 12–31 on the 16 threads).

| Renderer | 12 MP | 50 MP | 200 MP |
|---|---|---|---|
| flutter_tester (Skia on the CPU) | 5.8–7.5 | 18.1 | 57.5 |
| Linux embedder, Impeller GLES | 1.4 | 3.6 | 14.6–29.8 |
| Linux embedder, Skia GL | 0.4 | 1.6 | 7.8 |
| Chrome, CanvasKit / Skwasm | 1.1 / 1.8–3.5 | 4.9 / 6.6 | — |
| Kernel, C ABI / WebAssembly | 3.3–4.8 / 2.8–5.1 | 11.7 / 10.3–12.0 | 47.0 / — |
| Kernel, tiles on 16 worker isolates | 0.7–1.5 | 3.7–5.9 | 11.4–16.7 |
| Kernel, tiles on 4 worker isolates | 1.0 | 3.8 | 14.1–18.7 |

## Against the criteria

| Criterion | Threshold | Result |
|---|---|---|
| Parity | mean ΔE2000 ≤ 0.5, p99 ≤ 2 | pass on every renderer measured, by 7× and 1.9× at worst (Skia GL); phones unmeasured |
| Preview = export | the same thresholds | pass: mean ≤ 0.27, p99 ≤ 0.80 from 12 to 200 MP |
| Precision stress | steps ≤ 1 code value above the reference | pass: no band higher than the reference's anywhere |
| Interactivity | ≥ 30 fps on 2 MP (mid-range Android), ≥ 60 fps desktop; open ≤ 500 ms | unmeasured on a GPU: software rendering gives 1–22 fps with a readback per frame (Impeller GLES 6.8, Skia GL 22, CanvasKit 7.1, Skwasm 6.2, flutter_tester 0.9) and opens in 73–1,064 ms |
| Memory | 200 MP on a 6 GB phone, ≤ 256 MiB above the baseline | pass on Impeller (81 MiB, flat per tile) and in the kernel (17 MiB in one isolate, 188–222 MiB on a phone's 4 workers); fail on Skia, which frees uploaded tiles too late (5.4 MiB more per tile, 1 GiB at 200 MP); phones unmeasured |
| Export time | 12/50/200 MP, GPU and CPU; 50 MP ≤ 10 s on the reference phone | recorded above: 50 MP in 3.7–5.9 s with the kernel's tiles on every core here; the phone is checked in the test phase |
| Web | parity and interactivity on Chromium (Wasm); Firefox and Safari functional | parity passes on CanvasKit and Skwasm; frames only on SwiftShader; Firefox and Safari not run (`flutter test` drives Chrome only) |
| Gain maps | geometry-only edits keep the map; tonal edits recompute it with the expected headroom | pass in the kernel: a crop and turn moves the map bit for bit; +1 EV raises the headroom from 3 to 3.999 stops and the HDR rendition decodes within 1% |
| Size | CPU renderer ≤ 1 MB per native ABI | pass: +55,776 bytes android-arm64, +60,784 linux-x64, +12,087 brotli for the web |

## Option B: a Rust/wgpu engine

The probe's compute shader, f32 throughout, matched the reference within one code value on at most 66 of 8.0 million
channel values on lavapipe (Vulkan on the CPU) and took 15–38 ms per 2 MP frame. Its release library alone is
7,435,752 bytes for linux-x64 and 7,818,288 for android-arm64: over ADR-0004's 3 MB per ABI before the kernel, the
five texture interops or any other operation. A matches the reference just as closely without it.

## Findings the code follows

* **A shader per pass, disposed after it renders.** Skwasm rasterizes `toImageSync` lazily and reads a shader's
  uniforms then: one blur shader reused for both directions gave clarity a mean ΔE of 0.47 and a p99 of 3.4. A shader
  not disposed keeps its input texture until garbage collection: 839 MiB for a 200 MP export on the Linux embedder.
* **16 bits in two 8-bit channels** for the guide and the LUT: render targets are 8 bits per channel and the web
  engine cannot upload `rgbaFloat32`.
* **Opaque input only**: the web engine premultiplies uploaded pixels, the others do not.
* **Uploaded tiles are freed asynchronously.** In the export probe Impeller's memory stays flat, while Skia's grows by
  5.4 MiB per tile on the Linux embedder and by 5–12 MiB per tile in the browsers. A tight loop of uploads with no
  work in between grows on Impeller too (7 MiB per tile), so the phone run must decode and encode between tiles as an
  export does.
* **No HDR in Flutter**: gain-map images are edited by the kernel.
* **No shaders in `flutter test --platform chrome`**: `test/web_assets.dart` compiles them with the SDK's `impellerc`.

## Open

The phones (M0-27's device lab, the test phase): parity under Impeller on Vulkan, GLES and Metal, frame times, 200 MP
memory and the 50 MP export time; desktops with a GPU; the browsers' export on web workers; Firefox and Safari; the
Ultra HDR container round trip through libultrahdr and ImageIO (M8-07).
