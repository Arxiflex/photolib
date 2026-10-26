# ADR-0056 — Web support tiers and media path: Chromium on WebAssembly, the rest on JavaScript

* **Status**: Accepted — 2026-10-16 (roadmap M0-37). The owner confirmed all four decisions as made
  (photolib-design#357,
  whose questions give this ADR its number before renumbering, ADR-0040). Its thumbnail answer was at odds with
  [ADR-0040](0040-timeline-image-pipeline.md), accepted the next day, which keeps Flutter's codecs on the web unless
  Firefox stays slow with a GPU. On 2026-10-21 the owner kept this ADR's: tiers 2 and 3 decode off the UI thread with
  `createImageBitmap` in [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md)'s worker and hand Flutter the bitmap;
  ADR-0040's choice per browser engine stays available, and M1-43 grows the same worker with WebCodecs for HEIC
  (photolib-design#534).
* **Requirements**: R-APP-1, NFR-PERF-2. **Design**:
  client app §7,
  ADR-0003.

## Context

Design 10 §7 proposed three web tiers and a Content-Security-Policy, and left this spike to validate them in Chromium
on the WASM build and in Firefox and Safari on the JS build, and to check Trusted Types. The
[web media path report](../dev/web-media-path.md) has the measurements in Chrome 155 and Firefox 158; Safari was not
measured. In short: Flutter's loader already serves the builds the tiers assume; the proposed policy breaks the app
until index.html carries a nonce and a `default` Trusted Types policy exists; Flutter decodes thumbnails on the UI
thread outside Chromium; and 4 GiB uploads never sit in memory.

## Decision

* We will support the browsers in the tiers on [Browsers](../user/browsers.md), and keep Flutter's default
  `wasmAllowList`: dart2wasm with single-threaded skwasm on Blink, dart2js with CanvasKit elsewhere, no COOP or COEP.
* photolibd will send the report's [Content-Security-Policy](../dev/web-media-path.md#the-content-security-policy),
  with a fresh nonce per response that it also writes into `index.html`; the app hands it to the engine for its inline
  styles. The policy enforces Trusted Types: Flutter's loader uses its `flutter-js` policy, and
  `app/web/trusted_types.js` defines a `default` policy that admits script URLs from the app's origin only, for
  drift's and the worker pool's workers.
* Thumbnails decode through Flutter's codec on tier 1, which is WebCodecs' `ImageDecoder` there. On tiers 2 and 3 the
  thumbnail pipeline (M1-09) decodes with `createImageBitmap`, in a worker where it can, and hands the bitmap to
  Flutter (`createImageFromImageBitmap`), not with CanvasKit's codecs on the UI thread.
* Uploads read 8 MiB appends with `Blob.slice` in a worker and send the slice itself as the body whenever the bytes go
  up unchanged; only a private library's encryption reads them into memory.
* ADR-0385 adds `blob:` to `connect-src`, for the files a person picks or drops to upload.
* `tools/web_requests.py` checks, on every change, that Chrome and Firefox load their builds under that policy, have
  what their tiers need, and upload 4 GiB within the memory budgets of the report.

## Consequences

* A Chrome or Firefox release that drops a tier's need, a dependency that breaks the policy or a font from a CDN fails
  the gate. Safari's tier is untested until a Mac runs the check.
* photolibd must template `index.html` (the nonce); the other files stay static and their hashes can be published.
* The thumbnail pipeline has two decoders on the web, chosen by tier.
* Encrypting uploads in the browser costs up to 1 GiB of transient memory until a reader that reuses buffers works in
  Chrome; the gate allows 2 GiB.
* Design 10 §7.1 and §7.6 should point to these tiers and this policy instead of their proposals.

## Options considered

* **WebAssembly in Firefox and Safari too** (`wasmAllowList`): Flutter enables skwasm on Blink only, and the JS build
  passes everything the tier needs; not worth an untested renderer.
* **`'unsafe-inline'` styles**: no templating, but injected CSS would run; a nonce costs one substitution.
* **No Trusted Types**: simpler, but both browsers enforce them, and Flutter's loader already complies.
* **Flutter's codec on every tier**: one decoder, but CanvasKit decodes on the UI thread, no faster than
  `createImageBitmap`.
* **Reading every append into memory**: one upload path, but up to 1 GiB of garbage for every upload.
