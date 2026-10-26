# Web media path report (M0-37)

What the web app's media path does in Chromium on the WASM build and in Firefox on the JS build, measured on
2026-10-16 from commit `cae70a1` with Flutter 3.47.7. The decision is [ADR-0056](../adr/0056-web-support-tiers.md),
and the tiers and known limitations it sets are on [Browsers](../user/browsers.md).

## How it is measured

`python3 tools/web_requests.py app`, in the gate's `dart` part, builds the app with `flutter build web --wasm` (both
builds) and serves it on loopback under [the policy photolibd will send](#the-content-security-policy). Each browser,
headless, opens the probe in `tools/web_probe/`, then the app in `en-XA`, and the gate fails when:

* Chrome does not load `main.dart.wasm` with `skwasm.wasm`, or Firefox `main.dart.js` with `canvaskit.wasm`;
* either page breaks the policy, which is how a request to another origin, such as a font from a CDN, shows;
* the browser lacks a feature its tier needs ([Browsers](../user/browsers.md));
* an upload is not received whole, does not resume after its one failed append, or grows the browser's processes
  (resident memory, sampled every 0.2 s) by more than 256 MiB when it sends slices, 2 GiB when it reads bytes.

The probe measures:

* *features*: what the page and a module worker offer, from `typeof` checks, `ImageDecoder.isTypeSupported`,
  `canPlayType` and `MediaSource.isTypeSupported`;
* *thumbnails*: a 256 px photo-like image as JPEG (21 KB) and WebP (23 KB), decoded one at a time for 0.5 s each by
  `createImageBitmap` in the page and in a worker, by WebCodecs' `ImageDecoder` (Flutter's codec in Chromium) and by
  CanvasKit's `MakeAnimatedImageFromEncoded` (Flutter's codec in other browsers);
* *uploads*: two uploads of a 4 GiB file from a worker in 8 MiB `PATCH` appends, as `Server.upload` in
  `photolib_api` sends them. The server answers the append at 2 GiB once with a reverse proxy's 502 page, and the probe
  resumes from the offset that `HEAD` reports. *Slices* sends each `Blob.slice` as the body; *bytes* reads it into an
  `ArrayBuffer` first, as encrypting it for a private library must.

Machine: Linux x64, Intel Core Ultra 7 356H, 16 threads; Chrome for Testing 155 and Firefox 158, headless, rendering
in software; the page is not cross-origin isolated. Safari was not measured: it needs a Mac. Each result is the range
of three runs of the check, two of them in the gate; the machine is shared with other jobs, so the busiest run is up to
2.5 times slower.

## Results

| Browser | Build | Renderer | First load (bytes) | Gzipped |
|---|---|---|---|---|
| Chrome 155 | dart2wasm | skwasm, single-threaded | 6,442,913 | 2,635,828 |
| Firefox 158 | dart2js | CanvasKit, the full variant | 10,756,505 | 3,996,391 |

The first load is `index.html`, the bootstrap, the build, its renderer and the bundled fonts: `main.dart.wasm` is
2.4 MB and `skwasm.wasm` 3.6 MB, `main.dart.js` 3.0 MB and `canvaskit.wasm` 7.3 MB.

Thumbnails decoded per second:

| Browser | Format | `createImageBitmap` | in a worker | `ImageDecoder` | CanvasKit |
|---|---|---|---|---|---|
| Chrome 155 | JPEG | 747–1,893 | 796–1,914 | 1,662–4,782 | 907–1,536 |
| Chrome 155 | WebP | 337–584 | 313–720 | 487–719 | 450–476 |
| Firefox 158 | JPEG | 1,422–2,414 | 1,346–2,384 | 1,380–2,116 | 1,328–1,442 |
| Firefox 158 | WebP | 520–712 | 484–708 | 485–671 | 441–483 |

Uploads of 4 GiB, each resumed once:

| Browser | Appends | Seconds | Growth (MiB) |
|---|---|---|---|
| Chrome 155 | slices | 2.2–4.1 | 8–9 |
| Chrome 155 | bytes | 14.7–16.8 | 941–996 |
| Firefox 158 | slices | 6.3–12.3 | 0–6 |
| Firefox 158 | bytes | 10.8–16.8 | 818–865 |

Features:

| Feature | Chrome 155 | Firefox 158 |
|---|---|---|
| WasmGC, WebCodecs video, Trusted Types | yes | yes |
| `ImageDecoder` | JPEG, PNG, WebP, GIF, AVIF, JPEG XL; no HEIC | the same |
| `createImageBitmap` and OPFS sync access in workers | yes | yes |
| Native HLS (`canPlayType`) | `maybe` | no |
| MSE | H.264, VP9, AV1, AAC, Opus; no HEVC | VP9, AV1, AAC, Opus; no H.264 or HEVC |
| `ManagedMediaSource` | no | no |
| OPFS, SharedWorker, Web Locks, `webkitdirectory` | yes | yes |
| File System Access | yes | no |
| WebGPU | yes | no (headless) |

Chrome 154 and Firefox 157, the previous majors, passed the same checks in one run, with similar numbers; their
`ImageDecoder` lacks only JPEG XL.

## Findings

* **Builds.** Flutter 3.47's loader takes the first build a browser can run, and its default `wasmAllowList` allows
  dart2wasm with skwasm on Blink only, so Firefox and Safari get dart2js with CanvasKit, as the tiers assume. Without
  COOP and COEP, skwasm runs single-threaded, and the app runs.
* **CSP.** Design 10 §7.6's policy breaks the app in both browsers: `base-uri 'none'` blocks `index.html`'s `<base>`,
  and the engine's inline `<style>` elements need a nonce, as `style-src` falls back to `default-src 'self'`. Both
  browsers enforce Trusted Types, Firefox 158 included: Flutter's loader brings its `flutter-js` policy, but a plain
  `new Worker(url)`, as drift and the worker pool make, throws without a `default` policy. With the policy below,
  neither browser reports a violation. `index.html` has no inline script, so no bootstrap hash is needed.
* **Thumbnails.** In Chrome, `ImageDecoder`, which Flutter uses there, decodes JPEG 1.8–3.1 times as fast as
  CanvasKit in each run. In other browsers Flutter decodes with CanvasKit, synchronously on the UI thread (about
  0.7 ms per thumbnail in Firefox), although Firefox 158 has `ImageDecoder`; `createImageBitmap` there is 1.0–1.7 times
  as fast in each run and decodes off that thread, also from a worker.
* **Formats.** No browser here decodes HEIC. Chrome 155 and Firefox 158 decode JPEG XL, their previous majors do not,
  and design 08 keeps it out of delivery in 1.0.
* **Video.** Chrome 155 offers native HLS; Firefox has none, and on Linux decodes H.264 only through the system's
  FFmpeg, which this machine lacks. MSE takes VP9 and AV1 in both. Which path plays which video is M0-33's decision
  (photolib-design#40); this probe checks only that MSE exists.
* **Uploads.** 4 GiB arrived whole in both browsers after a failed append. Sending slices grew the browser by at most
  9 MiB. Reading each append first leaves up to 1 GiB of spent buffers before the garbage collector frees them, a
  sawtooth that never holds the file; in a one-off run, reading through a BYOB stream reader into one reused buffer
  kept Firefox at 6 MiB, but not Chrome (879 MiB).
* **Fonts.** Both browsers load the bundled Roboto and the fallback font from the app's origin only, so the policy
  needs no font origin. Nothing serves `fonts/` yet ([Flutter app](flutter.md#checks-specific-to-the-app)).
* **Workers.** The worker pool hashes 2 GiB in Chrome and Firefox on both compilers in the gate's `web` part (M0-24);
  the probe's module worker starts under Trusted Types through the `default` policy.
* **Memory over long sessions.** Within a run, about 5,000 decodes and 8 GiB of uploads per browser, each collection
  brings the browser back to its size. Hours in the app are not measured: it has no timeline or viewer to exercise yet.

## The Content-Security-Policy

photolibd sends the app with this policy, a fresh nonce in place of `<nonce>` in each response and the same nonce in
place of `CSP_NONCE` in `index.html`, which `flutter_bootstrap.js` hands to the engine. `app/web/trusted_types.js`
defines the `default` policy, which admits script URLs from the app's origin only.

```text
default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'nonce-<nonce>'; worker-src 'self' blob:; connect-src 'self' blob:; img-src 'self' blob: data:; media-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; require-trusted-types-for 'script'; trusted-types flutter-js default
```

`connect-src` allows `blob:` because the files a person picks or drops to upload are read through their `blob:` URL
(`XFile`); a `blob:` URL is made by the page itself and never leaves it.
