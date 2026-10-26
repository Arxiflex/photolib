# ADR-0214 — HEIC and HEVC without a system decoder: name the way out, use the system's codecs, render once

* **Status**: Accepted — 2026-10-21 (roadmap M1-44). The owner kept no WASM decoder and no Safari or Firefox
  folders, ruled out a desktop codec pack in any build and made `high` the universal rendition's default
  (photolib-design#600).
  Only *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-APP-5, R-MODE-1. **Design**: docs/08 §2.1, §2.3, §4, §5.2, §11,
  docs/18 §16, [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md), [ADR-0084](0084-image-renditions.md),
  [ADR-0085](0085-video-renditions.md). **Evidence**: the [spike report](../dev/heic-without-system-decoder.md).

## Context

M1-43 shows HEIC in browsers whose system decodes HEVC. Everywhere else a HEIC photo, and an HEVC video in some of
those places, ends as a marked placeholder in standalone mode: Chrome and Edge on Linux, Windows without the HEVC
Video Extension, the Linux app without libheif's HEVC plugin (Debian and Ubuntu only *suggest* it), Android 11 for
AVIF; Firefox and Safari keep no folder library at all. The report lists every cell with what main does there, run
or read, and measures the one decoder a page could bring: libheif-js decodes a 12 MP iPhone-like HEIC in 1.2-2 s in
Chrome's worker and its 320-pixel `thmb` item in 2-3 ms, for 0.38 MB of brotli and 125 MB of WASM heap. The design
allows only browser codecs on the web (docs/08 §2.3), recommends an optional desktop codec plugin (docs/08 §11 (b),
open decision 7) and closes every connected cell with renditions; the HEVC pools publish no exemption for free
software. The owner's direction (photolib-design#571) is one universal rendition, JPEG or H.264, made by the first
thing that decodes the source, and the original wherever a client decodes it.

## Decision

We will keep to the following, as the owner answered the four questions of the report on 2026-10-21:

* **Web, no WASM HEVC decoder**: a browser without a system HEVC decoder shows the placeholder of its cell, which
  names the way out (the desktop app, a connected server, Chrome or Edge on Windows or a Mac). libheif-js stays
  measured, not shipped; private uploads from such a browser (M6-13) are where it would be revisited. Read
  literally, question 2's answer changes the apps' placeholders only: Chrome and Edge on Windows still name the HEVC
  Video Extensions and Firefox an FFmpeg with HEVC, which the owner kept on 2026-10-23 (photolib-design#652).
* **Desktops, no codec pack in any build: nothing HEVC-licensed ships on a client.** The Linux app decodes through
  the system's libvips and libheif and the Windows app through WIC where they have HEVC, but asks for neither: a HEIC
  that nothing decodes shows a placeholder that names connected mode or a Mac, never a codec to install (M1-49).
* **No folder library in Safari or Firefox**: `webkitdirectory` stays the upload picker of connected mode.
* **The original or one universal rendition**: clients that decode the original open it; the rest open a JPEG or an
  H.264 R1 proxy, made by the first thing that decodes the source (the phone at backup, the server, a Mac). The JPEG
  is `high` by default: a full-size JPEG at the original's resolution, jpegli q≈92-95 with the Ultra HDR gain map, one
  per limited-reach still; `standard` (long side 2160, q≈85, today's `preview`) is the per-library option for small
  disks. Until M2-49 builds `high`, the server makes `standard`. Not AVIF or AV1 (no universal decoder, 6-17 times
  JPEG's encode time here), not WebP beyond thumbnails, not lossless.
* **No conversion on import**: originals stay as they are (docs/08 §1).

## Consequences

* No patent-encumbered decoder ships in the app, the web bundle or the packages: the exposure stays the server
  image's (docs/08 §2.3), and on desktops the codecs a user installed of their own accord.
* Linux and Windows users without those codecs and Chrome-on-Linux users of a folder library see placeholders until
  they use the app, a Mac or a connected server; the texts are in the report, for M1-43 and M1-49.
* A library grows by the full-size JPEG of each limited-reach still, 4.4-6.0 MB per 12 MP HEIC on the twins against
  2.4 MB (≈ 450-600 GB per 100k photos instead of ≈ 35 GB), which the owner accepts. M2-49 becomes P1; when it
  lands the `preview` spec's default changes and the reconciler re-renders every library.
* Connected mode closes every cell with the renditions M2-09 and M2-10 make today; uploads that carry the phone's
  rendition spare a server without HEVC decoders (docs/08 open question 9).
* The kernel read `imir` the opposite way from ISO/IEC 23008-12:2022, which libheif follows; it now reads it as
  libheif does (photolib-design#601).

Amendments this needs in the design repository:

* docs/08 §11 (b) and open decision 7: no optional codec plugin; the placeholders name connected mode or a Mac.
* docs/08 §4.1: the full-size universal JPEG of a limited-reach still is the exception to "no full-size copy is
  stored for HEIC/RAW"; `standard` keeps that line for libraries that choose it.
* The roadmap: no M1-48; M1-49's placeholders name connected mode or a Mac; M2-49 is P1, `high` by default.

## Options considered

* **libheif-js on the web** (option (b)), as Ente's web client ships it: about 1.2-2 s per photo and 125 MB of heap
  in a worker, 3 ms per grid tile from `thmb`; LGPL-3.0 and patent exposure extended to every browser that loads it.
  Not now (question 1); measured, for M6-13 to revisit.
* **FFmpeg's HEVC decoder in WASM**: no HEIF demuxer in a small build, a larger module, the same patents.
* **A codec pack, bundled or as docs/08 §11 (b)'s optional plugin**: more native code to keep patched, and HEVC
  distributed by the project; the owner said no to both (question 2).
* **Placeholders that name the codec to install** (`libheif-plugin-libde265`, RPM Fusion's `libheif-freeworld`, the
  HEVC Video Extensions): the provisional choice; the owner had them name connected mode or a Mac instead.
* **The kernel's embedded preview** (E): an iPhone HEIC's `thmb` item is HEVC too, so it helps only RAW and DNG.
* **Conversion on import**: rewrites originals, breaks hashes, deduplication and signatures, and loses 10-bit, gain
  maps and auxiliary images; formats keep coming.
* **AVIF and AV1 as the primary rendition** (the issue's option (f)): smaller files, but no universal decoder and
  several times the encode time; they stay docs/08's negotiated variants for later.
* **`standard` by default**, the provisional choice: ≈ 35 GB per 100k photos, but a 2160-pixel stand-in where the
  original is full size; it stays the option for small disks.
* **`lossless` (WebP lossless)**: ≈ 1-1.5 TB per 100k photos, HDR lost and nothing gained on a lossy source; not
  offered.
