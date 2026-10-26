# ADR-0116 — Web video posters: the browser's player off the DOM, kept sealed in the store

* **Status**: Accepted — 2026-10-20. The owner kept both decisions of photolib-design#433 as made, the off-DOM
  `<video>` without WebCodecs and posters alone sealed in the store
  (photolib-design#453).
* **Requirements**: R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §3.4, §4.2, §7,
  docs/08 §4.1, [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md),
  [ADR-0090](0090-local-store-cipher-and-passcode-binding.md).

## Context

ADR-0107 gave browsers a decoder for images and none for videos, and no disk tier, so every video in a web library
showed only a mark. Docs/10 §4.2 asks that posters come from the stack that plays the video, which in a browser is
its own player; docs/08 §4.1 that a poster skip a fade from black; the issue that posters survive a reload, that a
video the browser cannot play say so with its duration, and that long or broken files never hold the tile queue.
ADR-0107 kept no web disk cache because thumbnails of local files must not lie in browser storage in the clear; the
store's vault seals objects for that ([ADR-0057](0057-encrypted-local-store.md)), and ADR-0090 measured it fast
enough for thumbnails.

## Decision

* **The browser's player**: `browserPoster` (`photolib_data/browser.dart`) opens the file in an off-DOM `<video>`,
  seeks to a tenth of its length, at most 10 s, as the server does, then by half seconds for up to 3 s while the frame
  is near black (mean luma under 32), and draws the frame through `createImageBitmap` with its short side at the
  tier into an `OffscreenCanvas`, encoded as JPEG. The browser decodes off the page's thread; the page waits for the
  sought frame (`requestVideoFrameCallback`), as Chrome presents it after `seeked`. A video whose picture the browser
  cannot open or decode (`error`, or no width) is unplayable, with the duration its container gave.
* **No WebCodecs `VideoDecoder` for now**: it needs a demuxer per container (MP4, MOV, WebM), a new dependency or
  parser, and could show a poster for a video the player then cannot play; the `<video>` path is that player.
* **A disk tier in the store**: `VaultCache` keeps each tile a PLB envelope under the cache key in the vault's
  IndexedDB store, 64 MiB at most, the least recently used evicted first; its list of keys and sizes is an object too,
  written a second after a change. Browsers keep only posters there: image tiles still decode from the file, cheaply,
  each visit. A poster's entry starts with its duration, so a reload shows both without a decode. Its JPEG, fresh or
  kept, becomes an image as [ADR-0056](0056-web-support-tiers.md) has thumbnails decode: through Flutter's codec on
  Chromium, WebCodecs' `ImageDecoder` there, elsewhere with `createImageBitmap` in ADR-0107's worker.
* **Cells**: a video cell shows its duration at its bottom end; an unplayable one shows `videocam_off` and *Can't
  play in this browser*, said to screen readers too, never an empty cell.
* **Bounds**: at most two video decodes run at once, and each stops after 10 s or when its cell no longer wants it,
  so photos keep the other slots.

## Consequences

* Posters appear exactly where the player plays the video: HEVC in Chrome on Linux or ProRes anywhere shows the mark.
* A video with no stream the browser can open, and no audio, has no duration on the web until browsers extract
  metadata (ADR-0082's gap).
* Logout or erase removes the posters with the store; a lost list only orphans envelopes until then.
* The data package's browser test draws posters of corpus videos that the pinned FFmpeg makes, and Firefox decodes
  their H.264 and AAC on Linux with that release's libraries (`tools/check.sh`).

## Options considered

* **WebCodecs behind a demuxer (mp4box.js, a WebM parser)**: off the main thread entirely, but two new dependencies
  or parsers of untrusted files, and a second stack beside playback.
* **A plaintext cache in OPFS or Cache Storage**: thumbnails of local files in the clear, which ADR-0107 refused.
* **Durations from the replica**: browsers extract no metadata yet, so web cells would show none.
