# ADR-0107 — Desktop and web thumbnail decoders: the platform first, libvips beside the app, the browser in a worker

* **Status**: **Proposed** — owner to confirm (roadmap M1-26). Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §3.4, §7.2, §8.1,
  docs/08 §2.3, §8, [ADR-0070](0070-thumbnail-caches.md).

## Context

M1-09 (ADR-0070) left desktops decoding every original with Flutter's codecs, four at a time, then reading each tile
back from the GPU and encoding it in Dart for the disk cache; the web had no decoder at all. Flutter's codecs know no
HEIC, AVIF, JPEG XL or RAW, and a decode that failed or hung left its cell grey for good. M1-26 asks for the T4 tier
of docs/10 §3.4 — the platform's decoder at tile size, "the kernel's libvips" as the fallback, browser decoding, a
warm-up after a scan — and for picked folders to stay readable in the macOS sandbox. The kernel has no C dependencies
and decodes no pixels (ADR-0004, docs/08 §2.3), and open decision 7 leans to an optional, user-installed codec plugin
for HEIC on Windows and Linux.

## Decision

We will make T4 a list of decoders in `ThumbnailPipeline`, each taking what the one before refused (`NoThumbnail`),
whose tiles reach the disk cache as handed over (RGBA encoded on an isolate), never read back from an image:

* **macOS**: ImageIO's `CGImageSourceCreateThumbnailAtIndex`, QuickLook for what it cannot read, and
  `AVAssetImageGenerator`'s first frame of a video (`ThumbnailChannel.swift`); **Windows**: the shell's
  `IShellItemImageFactory` (its cache, WIC, Media Foundation's video frames), then WIC (`thumbnail_channel.cpp`).
  Both run on cores − 1 threads and answer the existing `org.photolib/thumbnails` channel with RGBA at the tier.
* **libvips, not the kernel**: the fallback on every desktop is libvips loaded with `dart:ffi` from the system (Linux)
  or beside the app (macOS `Frameworks/`, Windows next to the executable), started once per process and called on an
  isolate. Only the JPEG, PNG, WebP, GIF, TIFF, HEIF and JPEG XL loaders run, a header over 300 MP is refused before
  decoding, and libvips' cache and threads are off. Without libvips, Flutter's codecs remain the last resort and keep
  nothing.
* **Linux**: the freedesktop cache, then a video's first frame from libmpv, which plays it (design 10 §4.2's one
  stack, `mpv_posters.dart`), else from the `ffmpeg` on `PATH` (files only), then libvips.
* **Web**: a worker made from a `blob:` URL decodes a browser folder's file with WebCodecs' `ImageDecoder`, else
  `createImageBitmap`, resized there, and outside Chromium every encoded tile ([ADR-0056](0056-web-support-tiers.md));
  the bitmap becomes a `ui.Image` without a copy. The web keeps no disk cache
  (but for video posters, [ADR-0116](0116-web-video-posters.md)).
* **Failures**: a failed decode marks its cell (a video or a broken-image mark, said to screen readers), is logged with
  its file and error and retried once when its row is next shown; every decode times out of its slot after 10 s.
* **Warm-up**: when a folder's scan ends, its items are decoded into the disk cache one at a time, newest first, at
  the tier the timeline last used, paused while cells in view wait or the timeline is scrubbed or flung.
* **macOS folders**: each picked folder keeps a read-only security-scoped bookmark in the user defaults, resolved
  before the engine starts; a folder whose bookmark no longer resolves is offered to be picked again.

## Consequences

* HEIC, AVIF, JPEG XL and RAW (its embedded JPEG, ADR-0247) show on Linux wherever libvips 8.15+ with libheif and
  libjxl is installed, and on macOS and Windows through the OS; anything else shows a marked placeholder, never an
  empty cell.
* libvips parses untrusted files inside the app process, where docs/08 §8.1's sandbox does not reach: the loader
  allow-list and pixel limit are the controls (threat model, *Desktop thumbnail decoders*). Moving it to a sandboxed
  helper process is the next step if the corpus fuzzing finds crashes.
* Bundling libvips (and its HEVC decoder, a patent question) with the macOS and Windows apps is packaging (M10-04) and
  open decision 7; until then it is used where the user installed it. RAW beyond TIFF-based formats waits for libvips
  8.17's LibRaw loader or the kernel's embedded previews (M7-04).
* The gate compiles no Swift or C++: `tools/tests/test_desktop_thumbnails.sh` checks the channels as text and the
  smoke tests build them. The T4 budget is checked on `desktop` targets only; `headless` prints it.

## Options considered

* **libvips in the kernel**: breaks ADR-0004's pure-Rust kernel and its six-target build, and puts C decoders in the
  phones' and the web's kernel too.
* **A bundled codec pack (libheif, libde265, dav1d, libjxl, LibRaw) of our own**: more native code to build and keep
  patched than one library the server already depends on.
* **Flutter's codecs with a CPU read-back off the raster thread**: still no HEIC, AVIF, JPEG XL or RAW.
* **Decoding in Dart (`package:image`)**: far slower than a native decoder, and no HEIC.
* **A web disk cache in Cache Storage or OPFS**: thumbnails of local files in browser storage, which the private
  libraries forbid (docs/10 §7.5); a browser folder's tiles are decoded again on each visit instead.
