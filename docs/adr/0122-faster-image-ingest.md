# ADR-0122 — Faster image ingest: reused renderer memory, sequential JPEG decoding

* **Status**: Accepted — 2026-10-20. The owner took none of the four options below that would change what a rendition
  holds, add a dependency or change the budget's fixture, so renditions stay as they are
  (photolib-design#479).
* **Requirements**: NFR-PERF-4. **Design**: 08 §4.1, §9, 19 §3; [ADR-0084](0084-image-renditions.md).

## Context

`ingest-throughput` (12 MP JPEGs: the kernel's metadata, `thumb_s`, `thumb_m`, ThumbHash) measured 21.4 photos/s/core
on a quiet machine, close to its budget, and 19.3 to 21 in the merge train under load. The owner asked for a faster
ingest path that changes nothing a rendition holds, the ThumbHash included (design 08 §4.1); whatever trades rendition
quality, adds a dependency or changes the budget's fixture is the owner's to choose. Per photo, on a P-core of the gate
machine (an Intel Core Ultra 7 356H), in CPU time: decoding at ¼ 28.4 ms (libjpeg-turbo alone takes as long; under
Callgrind its scanline decoding is 61 % of all instructions, Huffman decoding 45 %), `thumb_m`'s WebP 8.4 ms (libwebp
alone 7.7 ms at its fastest method), its resize 2.8 ms, `thumb_s`'s resize and WebP 1.2 and 1.6 ms, the ThumbHash
1.3 ms (its DCT 0.6 % of the instructions), the JPEG header with its EXIF and the kernel's metadata 0.06 ms each.
photolibd's pooled renderer child also faulted in about 1,100 fresh pages per photo: glibc maps a block over its
dynamic threshold anew and trims the heap above twice that, so libvips' buffers were zeroed again for every photo. With
random access libvips holds a JPEG decoded whole before resizing it.

## Decision

We will:

1. **Reuse the renderer's memory.** The renderer frees a mapped 32 MiB block once, which raises glibc's mmap threshold
   to 32 MiB and its trim threshold to 64 MiB (mallopt(3)), as `GLIBC_TUNABLES` would; `unsafe` and so `mallopt` are
   forbidden, and the child's environment is cleared. A warm pooled renderer then faults in a few dozen pages a photo.
2. **Decode JPEGs sequentially**, top to bottom into the first resize, so no decoded copy is held: a 12 MP photo's
   preview peaks 17 MB lower.

Every rendition stays byte for byte as it was: `thumb_s`, `thumb_m`, `preview` and the ThumbHash of 27 images (the
benchmark's photos, the corpus' JPEGs, PNGs, WebPs and TIFF, a Display P3 and a CMYK JPEG, seven RAWs' previews).

## Consequences

Base and branch measured interleaved on the gate machine under the same load (load averages 55 to 86 from other
agents), in photos/s/core:

| | before | after |
|---|---|---|
| The budget's benchmark, thumbnails, calibrated (ADR-0121) | 20.9, 21.6, 21.0 | 20.5, 20.6, 20.9 |
| the same with the preview | 6.7 to 6.9 | 8.6 to 8.9 |
| photolibd's pooled renderer, thumbnails (the child's CPU time) | 19.2, 19.6, 20.0 | 20.1, 20.4, 20.8 |
| the same with the preview | 6.7, 7.4 | 8.4, 8.7 |

* The benchmark renders in its own process, whose glibc thresholds the photos it makes beforehand have raised already,
  and decodes at ¼ as fast either way (32.5 ms with the first resize, both): it shows neither change. Nothing else it
  measures could be made faster without changing a rendition: decoding and `thumb_m`'s WebP, 36 of its ~44 ms, run as
  fast as libjpeg-turbo and libwebp alone.
* Loaded, the benchmark still meets 19: with `stress-ng --cpu 8` (half the cores) 21.8 and 22.2 calibrated (21.4 and
  22.0 raw); with `--stream 8`, which saturates memory bandwidth, 20.3 and 21.1 (19.4 and 20.0 raw). The base measured
  22.3 and 21.9, and 21.2 and 21.3, between them.
* Not taken, as the owner answered, each with its gain on this machine:
  * the ThumbHash from the smallest rendition averaged in square boxes to at most 32 × 32 in Rust instead of a
    Lanczos3 resize to at most 100 × 100: 1.1 ms a photo, the benchmark 21.0 to 21.9 against 20.5 to 20.9
    interleaved; its placeholders decode 1.5 to 7 levels of 255 apart from today's on average;
  * a Linear kernel for `thumb_m`'s last 4 % of shrink: 0.7 ms, at 2.3 dB less PSNR against a full-size Lanczos3
    reference (47.5 → 45.2 dB, before WebP);
  * a SIMD resampler (`fast_image_resize`) for both thumbnails: 1.6 ms net, a new dependency;
  * a fixture as phones write JPEGs, with 4:2:0 chroma: libvips writes the benchmark's photos at 4:4:4, as it turns
    subsampling off from quality 90; at 4:2:0 a photo renders 25 % faster. This changes what the budget measures:
    the 4:2:0 fixture is worth revisiting, with its baseline, when the budgets are recalibrated on reference machines
    (M10-02).
* `tests/renditions.rs` holds both memory properties against a pooled child (its page faults per photo, its peak while
  making a preview).

## Options considered

* **Decoding from a buffer read once** instead of libvips' mapped file: 1.5 to 2 ms slower.
* **libvips' reducing gap** (a box shrink before Lanczos3) for `thumb_s`: 4 ms slower in libvips 8.16; **Lanczos2**:
  no faster, as libvips' horizontal reduce works in groups of four taps.
* **WebP presets and options** at the fastest method: within 3 %; **zune-jpeg**: no faster than libjpeg-turbo and
  without DCT scaling.
* **Reading the JPEG header once**: 0.06 ms. **`glibc.malloc.arena_max=1`**: fewer faults while a child warms up, but
  only through the environment.
