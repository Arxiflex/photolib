# ADR-0040 — Timeline image pipeline: platform decoders hand pixels over natively, Flutter's codecs on the web

* **Status**: Accepted — 2026-10-17 (roadmap M0-30). The owner kept the decision for the design's reasons rather than
  the spike's numbers: OS thumbnail caches return pixels, Flutter's codecs read no HEIC or RAW on the desktops, and
  thumbnails share the viewer's decoder stack; he set the conditions, defaults and checks below
  (photolib-design#335).
  On the web he kept [ADR-0056](0056-web-support-tiers.md)'s decodes in a worker on tiers 2 and 3, the choice per
  browser engine below staying available
  (photolib-design#534).
* **Requirements**: R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §3.4,
  research §2.4–2.5.

## Context

The timeline decodes thumbnails at display size off the UI thread, and M0-30 had to choose how: native decoders
handing pixels to Flutter, or Flutter's codecs. The [timeline spike report](../dev/timeline-spike.md) measured three
pipelines behind one `ThumbnailSource` over a 1M-asset library on Linux, Chrome (dart2js, dart2wasm) and Firefox:
Flutter's codecs on the encoded JPEG (*codec*), RGBA pixels built with `ImageDescriptor.raw` (*raw*, the Flutter side
of a native handoff) and, on the web, `createImageBitmap` (*bitmap*).

No pipeline won on every measure. The machine had no GPU and was shared (load average 20–43 on 16 threads), so
software raster dominated frame times and their ranking changed from run to run; a slower pipeline even gains there,
as flat placeholders rasterise faster than images. Natively, *raw* and *codec* stayed within each other's spread on
every measure: handing over decoded pixels costs about what decoding the JPEG does. In Chrome, *codec* decoded the
most per second in every run. In Firefox, where Flutter decodes through an `<img>` element (`ImageDecoder` only on
Blink), *codec* took about four times as long as *bitmap* to fill the screen after a jump, while *bitmap* dragged at
about three to four times *codec*'s frame time.

## Decision

We will decode thumbnails at their tier (128, 256, 512 or 1024 px) off the UI thread behind one `ThumbnailSource`:

* on native targets, with the platform's thumbnailers and decoders (docs/10 §3.4 T3 and T4) on native threads, which
  write RGBA or BGRA pixels into a native buffer that Dart copies once into an `ImmutableBuffer` and builds with
  `ImageDescriptor.raw`;
* on the web, with Flutter's codecs (`instantiateImageCodecWithSize` on the encoded bytes), which decode with the
  browser's `ImageDecoder` on Chromium and through an `<img>` element elsewhere (since
  [ADR-0056](0056-web-support-tiers.md), elsewhere with `createImageBitmap` in ADR-0107's worker).

Cells paint the resulting `ui.Image`s, one leaf per row, from a byte-bounded LRU. With the owner's conditions:

* The native side hands over upright sRGB pixels, converting Display P3 and Adobe RGB and rotating where WIC and
  ImageIO do not, as `bgra8888` where the platform's pixels are BGRA. It caches only encoded thumbnails natively;
  decoded pixels live once, in T1. M1-09's code comes with golden pixel tests of rotated, P3 and CMYK sources.
* Defaults come from the design, not from tuning: as many decodes at once as native decoder pools have threads, cores
  − 1 natively and four on the web, and T1 by RAM (docs/10 §3.4): a 32nd of it, 128–256 MiB on phones and up to
  512 MiB elsewhere.
* The web may choose its thumbnail source per browser engine if Firefox's fill after a jump stays slow on hardware
  with a GPU.

## Consequences

* Natively, OS thumbnail caches (T3) and the platform's HEIC and RAW decoders serve the grid with no encode and decode
  round trip; each platform needs its decoder pool and buffer handoff (M1-09), for which the benchmark's *raw* source
  stands in.
* The web needs no decoder of its own but ADR-0107's worker, on tiers 2 and 3 (ADR-0056).
* Android draws a thumbnail that is not 8-bit sRGB into one (`ThumbnailChannel.kt`); `loadThumbnail` already rotates
  it. iOS draws PhotoKit's upright into sRGB BGRA, CoreGraphics' own order (`ThumbnailChannel.swift`), which
  `ImageDescriptor.raw` takes as `bgra8888`. Flutter's codecs, the desktops' last resort (ADR-0107), apply the EXIF
  orientation and decode CMYK, and keep nothing; libvips' tiles reach the disk cache upright: `pipeline_test.dart`
  checks the corpus' orientations through both and from the disk cache, its CMYK JPEG and a Display P3 PNG and JPEG
  through Flutter's codecs, and BGRA pixels. libvips converts CMYK through its own fallback profile and keeps P3's
  values as they are, which these goldens do not hold it to yet. A P3 test on a phone needs the device lab.
* NFR-PERF-1's frame budgets and NFR-PERF-3's thumbnail times are unverified, not failed, until a machine with a GPU
  in the test phase, and on phones, macOS, Windows and Safari (M0-27). The gate checks what a CPU can: O(1) jumps
  (`buckets_test.dart`, `layout_test.dart`), the layout's time and decode throughput (`budgets_test.dart`) and frame
  build times (`tools/perf`, which counts build alone without a GPU). Firefox's slow fill after a jump is the first
  thing to measure again; moving the web to `createImageBitmap` changes one `ThumbnailSource`.
* Test builds, built with `--dart-define=PHOTOLIB_FLAGS=diagnostics`, have *Timeline benchmark* under Settings'
  diagnostics: it runs the benchmark's scenarios over a generated library the size of the spike's on the tester's
  hardware and copies its JSON, so the test phase produces the numbers. Release builds leave the flag off.
* Read literally where the answer leaves room: the cache sized by RAM is T1, the one docs/10 §3.4 sizes so (T2 keeps
  its 1 GiB); a test build is one with the diagnostics flag; the JSON is exported to the clipboard.

## Options considered

* **Flutter's codecs natively**: no faster, yet OS thumbnailers return pixels that would have to be encoded again,
  and Flutter's codecs do not read HEIC or RAW on the desktops.
* **`createImageBitmap` on the web**: fills Firefox's screen after a jump sooner, but dragged three to four times as
  slowly there and decoded less per second than *codec* in Chrome.
* **Raw pixels on the web**: needs a decoder in WebAssembly or a worker that does not exist, and moves 21 times the
  bytes of the JPEG.
* **A `Texture` per cell**: an external compositing layer per cell (research §2.4, technique 17).
