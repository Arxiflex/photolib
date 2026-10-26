# ADR-0247 — RAW pipeline: the largest embedded JPEG, turned as the RAW is, everywhere; LibRaw once libvips has it

* **Status**: Accepted — 2026-10-23. The owner kept the decision
  (photolib-design#703,
  the provisional choice of photolib-design#187, roadmap M7-04): the largest embedded JPEG everywhere, LibRaw once the
  server's libvips has it.
* **Requirements**: R-APP-5, R-COMP-3. **Design**:
  media pipeline §2.1, §3.4, §4.2,
  [ADR-0084](0084-image-renditions.md), [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md).

## Context

Nothing in Photolib decodes camera sensor data: the kernel has no codecs, the apps use the OS's. The design shows a
RAW through its embedded preview first and through LibRaw (libvips' `dcrawload`) where the preview is poor. The
server already rendered a RAW's largest embedded JPEG with the RAW's orientation (ADR-0084), but the kernel read
nothing of a CR3, so a portrait CR3 rendered on its side; the desktops' libvips decoder read a TIFF-based RAW's IFD0,
which is sensor data or a thumbnail (the corpus' greyscale stubs showed grey), and refused ORF, RW2, RAF and CR3; a
cell's embedded stand-in ignored the file's orientation. `dcrawload` is in no libvips the server builds against:
Ubuntu 24.04 has 8.15, and Alpine 3.24's 8.18, which the image installs, is built without LibRaw.

## Decision

1. **Every host shows a RAW as its largest embedded JPEG, turned once by the RAW's orientation**, whatever the JPEG
   says itself: the server's renditions as before; on desktops the kernel's `largest_preview` (ReadMetadata), given
   the RAW's orientation as its only EXIF tag and made a tile by libvips, after the OS's decoders (ImageIO on macOS,
   WIC's Raw Image Extension on Windows) and never libvips' TIFF loader. A RAW without a JPEG is unsupported.
2. **Embedded stand-ins** (the smallest JPEG, T2.5) carry the file's orientation the same way, so they paint upright.
3. **The kernel reads CR3**: IFD0, EXIF and GPS from CMT1, CMT2 and CMT4, the size from the first track and the JPEGs
   of THMB and PRVW (`FILE_FORMAT_CR3`), so every host knows its orientation, time and previews.
4. **Which files are RAW**: the server sniffs magic bytes (a signature, DNGVersion or the maker); a desktop takes the
   extensions its folder scan admits (`rawExtensions`).
5. **Colour**: a preview is the camera's own rendering; it is colour-managed as any JPEG is (ADR-0084: its ICC profile,
   else sRGB).
6. **Full decode is deferred** until the server's libvips has `dcrawload` with LibRaw: then the renderer decodes the
   sensor data where the largest JPEG is smaller than the largest rendition and the sensor is larger. Until then a
   RAW's renditions are no larger than its preview.
7. **RAW + JPEG pairs** keep the camera's JPEG as the original shown (ADR-0066); the RAW is `original_alt`.

## Consequences

* ✅ Every RAW of the corpus shows upright and in colour on the server and the desktops
  (`tests/renditions.rs`, `vips_test.dart`); its stubs now carry real orientations and their formats' signatures.
* ✅ CR3s get their capture time, camera and orientation from the kernel on every host, not only from ExifTool.
* ⚠️ A RAW whose previews are all small (older Sony, Panasonic and Adobe-converted DNGs, about 1,600 px) gets no
  sharper preview than that until LibRaw is in the image; ProRAW's JPEG XL tiles are never decoded.
* ⚠️ Previews in Adobe RGB without a profile (a camera set to Adobe RGB) show as sRGB, slightly flat.
* ⚠️ Previews the kernel does not locate (Olympus' and Pentax' maker-note previews, Panasonic's `JpgFromRaw`) leave a
  desktop with the smaller ones it finds; the server scans the whole file and finds them.
* ⚠️ Not done here: the web's standalone folders and Android show RAWs through their own decoders, unchanged.

## Options considered

* **Build libvips with LibRaw into the image now**: the image would build libvips from source instead of Alpine's
  package, and no test here could run it (no libvips on this machine has `dcrawload`).
* **A pure-Rust RAW decoder (rawler) in the media sandbox**: memory-safe, but LGPL, a second RAW engine beside the
  design's LibRaw, and a colour pipeline of our own to keep.
* **libvips' TIFF loader on TIFF-based RAWs** (before): it shows sensor data or a thumbnail, never the preview.
