# ADR-0390 — HDR handling: tone mapping for videos and stills, gain maps in JPEG derivatives, an HDR HLS variant

* **Status**: **Proposed — owner to confirm** (roadmap M7-03).
* **Requirements**: R-APP-5, F-12. **Design**:
  media pipeline §2.1, §5.6,
  editing and video §5,
  [ADR-0085](0085-video-renditions.md), [ADR-0216](0216-hdr-and-raw-in-the-viewer.md),
  [ADR-0246](0246-adaptive-streaming.md).

## Context

ADR-0085 tone-mapped HDR videos with Hable's curve at 100 nits "until libplacebo", and every other HDR path was open:
a video whose file leaves its primaries or matrix unsaid failed to render ("no path between colorspaces"), greys came
out dull, PQ and HLG stills (AVIF, HEIC) rendered as their own code values, libvips dropped every gain map, Apple's
JPEG gain maps were not found, no player could get an HDR video as HDR from the ladder, and the web viewer showed HDR
stills in SDR. The design documents the item cites are not in this repository; this ADR takes the most conservative
reading of each.

## Decision

1. **Videos: libplacebo where it runs, else a zimg chain tuned to match it** (`video::Ffmpeg::conversion`,
   `tone::Tone::filter`). libplacebo's BT.2390 on a Vulkan device (a GPU, or llvmpipe on a CPU) is used when one
   inside the media sandbox reads a known grey back as grey; this is asked once per process. Its 4:2:0 output is not
   read back right on every device, so it converts to 8-bit RGB and FFmpeg's scaler makes the 4:2:0 picture. The
   fallback is zimg to linear light with 203 nits (BT.2408 reference white) as 1.0, BT.709 primaries, FFmpeg's Mobius
   curve with its knee at 0.3 and error-diffusion dither. A sweep of curves and white levels against libplacebo on the
   reference clips chose them (mean ΔE 2.8 for PQ, 3.4 for HLG, greys under 2). `tone_mapping: auto|zimg|placebo`
   picks; `placebo` fails a render where no device works, saying why. The sandbox gives a Vulkan render 8 GiB of
   address space and 4 GiB of file size (a software driver keeps its images in memory files, which `ftruncate` checks
   against `RLIMIT_FSIZE`), and a zimg render of HDR 6 GiB (a 4K clip's poster failed at 3 GiB on 16 cores). Landlock
   lets no GPU's device file in, so the Vulkan device inside the sandbox is always a software one, which converts a
   4K video 8 times slower than zimg (15 s against 1.9 s for 10 s of 4K, 39 s against 6.6 s on 2 cores): `auto` uses
   libplacebo for a video's posters and sprites, a few frames, and zimg for R1 and the ladder's rungs, a stream;
   `placebo` uses it for both.
2. **What a file says of its colours.** The probe keeps the transfer, primaries, matrix and range. Dolby Vision's
   signal compatibility decides when the transfer is unsaid: 8.1 and 7.6 are PQ, 8.4 is HLG, 8.2 is SDR, profile 5
   (IPT-PQ-c2) is **refused** (`Unsupported`): no filter here undoes it without its RPU, and a green and purple poster
   is worse than none. What a file leaves out is taken as BT.2020, limited range, and the transfer is always said, as
   files that name HDR only in a Dolby Vision record leave FFmpeg's frames without one.
3. **Stills.** A 10-bit AVIF or HEIC whose nclx says PQ or HLG is converted once, at the largest output, in
   `photolib_media::hdr`: linear light, BT.2020 or P3 to BT.709, Mobius at the picture's own peak on the brightest
   channel (hue kept), sRGB. It stays within a mean ΔE of 4.3 of the video path.
4. **Gain maps in derivatives.** `photolib_media::gainmap` and `heif` find a map in Ultra HDR and ISO 21496-1 JPEGs
   (the Multi-Picture index, read without the picture), in Apple's JPEGs (a second picture named in its XMP, its
   strength in `HDRGainMapHeadroom` or the primary's maker note), in HEIC and AVIF files (a `tmap` item's second input,
   which Samsung and libavif write; an auxiliary image of Apple's type, strength from the maker note by Apple's
   documented formula, an absent tag 48 as 0). The map's coded image leaves as a HEIF file of its own, which libheif
   decodes; it is scaled and turned with the preview, Apple's Rec.709-coded luminance is recoded to the linear gain
   Ultra HDR readers apply, and the JPEG `preview` is written as an Ultra HDR file: a fresh XMP directory, the ISO
   21496-1 metadata, a new index. Nothing of the source's XMP travels, and a map with foreign namespaces, a base
   picture that is the brighter one (libavif's `seine_hdr_*`), or one that does not decode is left out. WebP
   thumbnails cannot carry a map and stay SDR. libultrahdr decodes the previews of real Apple, Samsung and libavif
   files. The kernel's `hdr` facet now finds Apple's JPEG maps (the gap ADR-0216 lists).
5. **HDR originals to HDR clients.** `GET master.m3u8?hdr=1` adds a variant beside the SDR rungs, `VIDEO-RANGE=PQ|HLG`
   and the original's own codec string (`hvc1.2.4.L…`, `av01.0.…`): its pictures are copied once, by one sandboxed
   FFmpeg, into fMP4 pieces cut at the original's key frames (sound as AAC-LC), in the segment cache, and served as
   byte ranges as R1 is. Players on HDR displays (AVPlayer, ExoPlayer, hls.js with MSE) choose it. SDR clients, the data
   saver, SDR videos, Dolby Vision profile 5 and codecs HLS does not carry as they are never see it. It needs `view`
   access: the original is never sent as a download. A copy that takes more than 10 s is left out of the playlist
   while it goes on.
6. **Web leaf.** Where the browser's display has HDR headroom (`(dynamic-range: high)`) the viewer shows an HDR still
   of a browser folder in an `<img>` of its own bytes under the SDR frame, which Chrome decodes with its gain map;
   Flutter keeps every gesture. A file the browser cannot show (HEIC) stays the SDR frame's. Native leaves are those of
   ADR-0060.
7. **Generator versions.** Video renditions and image renditions move to generator version 2, so every library renders
   again once.
8. **Proof.** `server/crates/photolib-server/tests/hdr.rs` measures reference clips of known light: grey, black,
   mid-grey, reference white, peak and primaries, for HDR10 and HLG, untagged, Dolby Vision 8.1 and 8.4, stills, and
   libplacebo against zimg; its ignored test writes the visual review's sheets ([report](../dev/hdr.md)).

## Consequences

* ✅ Reference HDR clips and stills render neutral and not washed out; untagged files render at all.
* ⚠️ Every video and image renders again once after the upgrade (generator version 2), as ADR-0246's did.
* ⚠️ Dolby Vision profile 5 gets no poster or proxy until an RPU-aware path is verified on a real file.
* ⚠️ HDR10+ dynamic metadata is ignored: the mapping is static, from the picture's own signal.
* ⚠️ The HDR copy lives in the segment cache (`streaming.cache_gib`), so a 2-hour 4K HDR original needs room there; a
  copy that does not fit is made again when asked.
* ⚠️ JPEG XL and PNG (cICP) HDR stills are not tone-mapped yet; a gain map of a JPEG XL is not kept.
* ⚠️ Firefox has no File System Access, so no still reaches its viewer from a folder (ADR-0056): the web leaf runs in
  Chromium. Safari is not run here.
* ⚠️ No client plays server videos yet (M2-24, M2-25, M3-13): the HDR variant is proved against the server and hls.js,
  and the web leaf against a browser folder.

## Evidence

* Reference sheets (`assets/0390/sheet-*.jpg`, 1,280 px): each clip's frame as a player without tone mapping shows it,
  as zimg converts it and as libplacebo does: HDR10, HLG, both with their colours unsaid, Dolby Vision 8.1 and 8.4.
* `viewer-hdr-img-chrome-desktop.jpg`, `viewer-hdr-img-chrome-mobile-emulation.jpg` (a Pixel 7: touch, device pixel
  ratio 2.625, CPU slowed 4 times, 1.5 MB/s), `viewer-sdr-display-chrome-desktop.jpg`, `grid-chrome-mobile-emulation.jpg`:
  the web build under photolibd's CSP, three JPEGs with gain maps in a folder (the server's preview of a real
  iPhone's HEIC, libavif's Apple JPEG, the corpus' Ultra HDR file); the HDR button shows, and with the display
  answering `(dynamic-range: high)` one `<img>` of 2,160 px holds the file (headless Chromium has no HDR display, so
  the picture it paints is SDR, as without the leaf). `gain-map-of-a-real-iphone-preview.jpg`: that preview and its
  gain map, upright and aligned.
* Timings of 10 s of 4K HDR10, `cargo test -p photolib-server --test hdr 4k -- --ignored --nocapture`: zimg 1.5 s
  (poster), 1.6 s (sprites), 1.9 s (R1); libplacebo on llvmpipe 2.8, 2.6 and 14.9 s; on 2 cores (`taskset -c 0,1`) zimg
  2.6, 3.3 and 6.6 s, libplacebo 4.9, 3.4 and 39 s.

## Options considered

* **A stored HDR rendition**: duplicates every HDR original in the store for what a copy in the cache does.
* **Serving the original with `Action::View`**: lets a viewer download what only a downloader may.
* **libplacebo only**: needs a Vulkan device; the zimg chain keeps CPU-only servers right.
* **Computing a gain map for PQ stills**: a JPEG cannot hold PQ, but inventing a map is not preserving one.
