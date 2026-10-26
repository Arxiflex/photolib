# Format coverage

What photolibd shows of the media corpus (`testdata/corpus/`), the M7-05 criterion "format corpus coverage ≥ 98 % with
documented exceptions": **all 330 supported files are covered, and no file is an exception.** A file is covered when
it is sniffed and read as its golden record says (`ingest/sniff.rs`, `kernel/tests/corpus.rs`, the ingest tests) and

* an image renders its thumbnails and preview upright, showing its picture:
  `every_corpus_image_renders_upright_but_the_documented_exceptions` in `server/crates/photolib-server/tests/renditions.rs`,
  which fails on a file that does not render and is not listed below, on a listed one that renders, and below 98 %;
* a video gets its poster, sprites and a rendition that plays everywhere: `tests/video.rs`, which allows no exception;
* special media carry the facets their quirks call for, from what the kernel reads (`kernel/tests/corpus.rs`, the
  ingest tests): `spatial` for spatial photos and videos, shown in 2D; `portrait_depth` for a depth map or portrait
  matte, kept in the original; `slow_motion`, and `time_lapse`, which only a kernel vector has.

The six unsupported files (SVG, PDF, EPS, Ogg audio, an unknown type) are not media in 1.0: they are listed under Other
files, never rendered (docs/08 §2.1).

## How the server shows each format

| Format | Renderer (in the sandbox) |
|---|---|
| JPEG, PNG, GIF, WebP; APNG and animated GIF and WebP by their first frame | libvips |
| TIFF and BigTIFF, page 0 of a multipage one; 16-bit, and float (0 to 1) scaled to 8 bits | libvips |
| BMP | the image crate |
| PSD and PSB: the composite, never the layers; bitmap, grey, duotone and multichannel (as grey), indexed, RGB and CMYK, 1 to 32 bits, raw or RLE | `photolib-media`'s `raster` |
| HEIC, AVIF (8 to 12-bit, HDR), and spatial HEIC by its primary view | libheif |
| JPEG XL, codestream or container | libjxl |
| RAW and DNG | their largest embedded JPEG |
| Videos, 360° and spatial ones as 2D | FFmpeg ([ADR-0085](../adr/0085-video-renditions.md)) |

## Placeholders and their twins

The corpus' HEIC, AVIF, JPEG XL and video payloads are placeholders, as no stdlib encoder for them is reasonable
([ADR-0020](../adr/0020-in-tree-synthetic-media-corpus.md)), so these files render as twins the pinned FFmpeg
(`tools/video/ffmpeg.sh`) codes: the record's container, codec, bit depth, HDR transfer, HEIF `irot`, `imir`, `clap` and
grid, at a quarter of the record's size when it is over a megapixel. The twins leave out what FFmpeg cannot make:
HEIC is 8-bit (kvazaar has no 10-bit), auxiliary images (alpha, depth, gain maps), the second view of a stereo pair and
an `mpvd` video are absent, and a recompressed JPEG XL has no `jbrd` box.

## Exceptions

| Corpus file | Why |
|---|---|

## Not covered by the corpus

* PSD composites in Lab, or ZIP-coded, are unsupported; a PSD saved without Maximize Compatibility shows the blank
  composite Photoshop writes.
* APNG, AVIF sequences and animated JPEG XL get no `anim` rendition yet: they show their first frame.
* Insta360 and GoPro dual-fisheye footage is not dewarped (docs/08 §2.2).
* The client apps' own decoders per platform (docs/08 §2's matrix) are verified on Linux and in browsers by the app's
  tests, elsewhere by the smoke runs and devices.
