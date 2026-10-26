# ADR-0385 — The web client v1: served by photolibd, driven in the browsers it supports

* **Status**: **Proposed** — owner to confirm. Becomes *Accepted — YYYY-MM-DD*; once accepted, only *Superseded by
  ADR-NNNN* may change it.
* **Requirements**: R-APP-1, NFR-PERF-1, NFR-PERF-2. **Design**:
  client app §7,
  [ADR-0056](0056-web-support-tiers.md), [ADR-0120](0120-client-sync-engine.md),
  [ADR-0128](0128-downloads.md), [ADR-0243](0243-setup-links-open-the-app.md),
  [ADR-0246](0246-adaptive-streaming.md).

## Context

The web app built and passed `tools/web_requests.py`, but photolibd served none of it (its page at `/` was the password
setup link's), and driving the build in Chrome and Firefox against a real photolibd, as a person does, found it could
not be used: the replica did not open, the Connect API answered 405 under the app's routes, the timeline stayed empty
because browsers had no sync, timestamps from sync batches were wrong, there was no file picker, no upload, no server
video, no download of a server photo, and no offline shell. This ADR records the choices made to close those gaps.

## Decision

* **Serving.** `web_root` names a `flutter build web` directory that photolibd serves at `/` in place of the setup
  page. `index.html` gets a fresh nonce per response, and every file of the build carries the same policy
  (`relay::APP_CSP`), because a worker runs under the policy of its script and the response middleware's sandbox for
  other responses would take its origin, and with it Web Locks and OPFS, away. The middleware recognises the policy by
  its shape (`relay::is_own`), so no handler can claim it with a weaker one. Files stream from disk with `ETag` and
  `If-None-Match`, a `.br` or `.gz` beside them for a browser that accepts it, and one byte `Range`; a path without an
  extension is an app route and gets `index.html`; what is not a GET goes on to the API.
* **Policy.** `connect-src` gains `blob:`: the files a person picks or drops are read through their `blob:` URLs
  (`XFile`), which the page itself makes. *Guard changed*: `tools/web_requests.py`, `relay.rs` and
  [web media path](../dev/web-media-path.md) say the same policy, and a test compares the first two.
* **Sync.** A browser's data worker runs `SyncEngine` (never the page's thread, design 10 §1.5) and the app follows the
  server's hints there too. Sync batches are read with sums and division, never shifts: dart2js's bit operations are 32
  bits wide.
* **Upload.** A button over the library picks photos and videos, and a drop on the window takes them; each is hashed
  with BLAKE3 on the page, created as a resumable upload and sent in appends (ADR-0061), one file after another; a
  refusal fails that file alone. The hash runs on a worker (`hash_worker.js`, a pool of `hashUrl` over the file's `blob:`
  URL, in chunks), so the page stays responsive; the upload bar shows the progress.
* **Video.** The viewer asks photolibd to sign the server's URLs (`POST /media/<asset>/<role>`), so no session header is
  needed. It plays the adaptive ladder (ADR-0246): Safari on Apple systems natively, every other browser with Media
  Source Extensions through hls.js 1.7.3 (Apache-2.0, pinned and fetched by `tools/hls/web.sh`, loaded from the app's
  own origin on the first video, never a third party's). A browser without MSE plays the progressive H.264 proxy.
* **Download.** A server asset downloads its original under its original file name or, once edited and when the person
  picks it, the current version (ADR-0391, which item 8 brought); several download as the streamed zip. The app only
  streams the bytes through `web/download.js`: into the file in Chromium, staged in OPFS in Firefox, held in memory in
  Safari.
* **Offline.** `offline_sw.js` keeps what the app loaded and serves it when the network does not answer; data, media,
  uploads, hints and downloads never pass through it. With the manifest, Chrome reports the app installable.
* **The server's address.** *Add a server* offers the address the app was served from.
* **Proof.** `tools/web_e2e` drives the journey in headless Chrome and Firefox, and on a throttled phone in Chrome's
  device emulation, against a real photolibd, in the gate's `web` part; it uses Playwright (Apache-2.0), pinned.

## Consequences

* The web part needs Playwright's Firefox (fetched once) and an FFmpeg that encodes H.264.
* hls.js is a script to ship and keep current; it makes no request but to photolibd's own `/media` paths.
* A video plays only where the browser decodes H.264 (Firefox on Linux needs the system's FFmpeg libraries, as
  [Browsers](../user/browsers.md) says).
* Safari is not run here: it needs a Mac; the web part runs the same tests there when `-p safari` is available.

## Evidence

`node tools/web_e2e/run.mjs` passes every step in Chromium, Firefox and WebKit (Linux, Playwright 1.64.1, headless, the
app's JS and WASM builds as each browser takes them) and on a Pixel 7 emulation in Chrome throttled to four times slower
CPU and a 1.6 Mbit/s network. The pictures (`assets/0385/`, 1280 px at most, taken by that run: Chrome for Testing 156,
Firefox 158 on photolibd serving the build with three photos and a 4 s H.264 clip uploaded in the browser):

* `timeline-chrome-desktop.jpg`, `timeline-firefox-desktop.jpg`: the timeline as the browsers' replicas show it after
  the uploads, with the upload bar over it.
* `viewer-chrome-desktop.jpg`, `video-chrome-desktop.jpg`: the viewer with its filmstrip, and the clip playing from the
  signed H.264 proxy (the burnt-in time is 2.433 s).
* `timeline-chrome-phone-emulation.jpg`, `viewer-chrome-phone-emulation.jpg`: the same on the phone emulation.

### Frame budget

`python3 tools/timeline_bench.py chrome --wasm` (1M library, 1280x824, dart2wasm, headless Chrome for Testing 156, the
codec pipeline the web build uses) on this ARM machine, which has no GPU (`/dev/dri` is absent), so both renderers are
software GL. `timeline-scroll-web` (`tools/perf/budgets.json`, `--check` in the gate's web part) holds the drag and fling
to under 1 % janky frames.

| Renderer | drag | fling | jump | scrub |
|---|---|---|---|---|
| SwiftShader (Chrome's default headless) | 59.9 fps, 0.4 % janky | 60.0 fps, 0.3 % | 10.8 % | 1.1 % |
| ANGLE Vulkan on Mesa lavapipe (`--use-angle=vulkan`, renderer `llvmpipe`, a GPU-like path) | 59.8 fps, 0.2 % | 60.0 fps, 0.0 % | 11.1 % | 0.0 % |

The gate measures it as ADR-0140 does the app's: `--check` builds once and runs the browser up to three times, keeping the
least janky; each run also times an idle page of the same loaded view, whose missed frames perf.py takes off (no credit
if that page missed more than 10 %, which means the machine cannot measure), and the load average is recorded with
the result. The limit stays 1 %.

A jump (a leap of the whole library, every tile new) misses in both: decoding thumbnails, not drawing, takes the time
(p99 78 ms); it is not in the budget. A real GPU and Safari are the device lab's (M10-02).

### Edited versions

The item asks for edited versions in the downloads only if the edit-recipe model exists. Item 8 landed in `dev` while this
was reviewed (ADR-0391, `serverDownloadOf` reads the replica and the server's `edit_export`), so the web app uses it and
adds nothing of its own: the journey downloads a photo and a zip from a browser through that path.

## Options considered

* **Embedding the build in photolibd's binary**: one file to deploy, but a rebuild of the server for every app change,
  and nothing to precompress; `web_root` can be added to the image's build later.
* **`'unsafe-inline'` or a blob-free upload path**: reading `File` objects through JavaScript interop would keep
  `connect-src 'self'`, at the cost of every platform's picker code differing.
* **The progressive proxy alone**: no script, but no adaptation on a slow network; hls.js is loaded only when a video
  opens.
