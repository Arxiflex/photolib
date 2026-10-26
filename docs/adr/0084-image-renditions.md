# ADR-0084 — Image renditions: libvips in the media sandbox, versioned specs, media through the API

* **Status**: **Proposed — owner to confirm** (roadmap M2-09).
* **Requirements**: R-APP-5, NFR-PERF-4, PRIV-19, LIB-19. **Design**:
  media pipeline §1, §4, §8, §9,
  [ADR-0022](0022-object-store-backends.md), [ADR-0024](0024-media-sandbox.md).

## Context

Ingest (ADR-0066) commits images and queues a `render` job for each rendition the reconciler finds missing, but nothing
renders, stores or serves them. The design fixes the rendition set, metadata-free and colour-managed output, versioned
render specs and serving through the API; it leaves open how libvips runs without `unsafe` in the server, how one
decode makes every size, which libvips the server needs, how specs are identified and replaced, how signed URLs work,
and what the 19 photos/s/core budget counts (docs/19 §3 says thumbnails and metadata, docs/08 §9 adds the preview).

## Decision

1. **Renderer.** The built-in tool of `photolibd media-child` (ADR-0024) also renders, with libvips ≥ 8.15 through the
   `rs-vips` bindings, which call operations by name and so work on every 8.x. libvips starts inside the sandbox with
   one thread and no operation cache; the child may read its input directory and the system libraries, and write its
   output directory. The loader is the one for the MIME type ingest sniffed (JPEG, PNG, WebP, GIF, TIFF, HEIC and AVIF
   through libheif, JPEG XL); libvips never picks one, so ImageMagick, PDF and SVG never run. A RAW shows its largest
   embedded JPEG that libjpeg decodes, with the RAW's orientation. The pixel limit is checked on the header.
2. **One decode.** A request names every rendition to make of one image; JPEG decodes at ½, ¼ or ⅛ when the largest
   still fits, each rendition is resized from the one before it, EXIF orientation is applied once, and the smallest
   gives the ThumbHash (stored in `assets.thumbhash`). The `render` job makes all of an asset's missing renditions at
   once; its other jobs, which wait on an advisory lock, then find them made.
3. **Output.** `thumb_s` (short side 256) and `thumb_m` (720) are WebP q70/q75 at libwebp's fastest effort, sRGB without
   a profile; `preview` is JPEG q85 with a long side of 2,160 px (8,192 for photo spheres), Display P3 with its profile
   when the source's profile is wider than sRGB (red primary X above 0.46), and WebP when the image has alpha. Nothing
   else is kept: no EXIF, XMP, IPTC or GPS.
4. **Specs.** A spec is the rendition's role, generator, generator version, size, format, quality and colour; its id is
   16 bytes of the BLAKE3 hash of its JSON. The built-in profile wants every spec of every image; the scheduler's
   reconciler queues what is missing, so a changed spec renders again. A rendition records its spec, size, source hash
   and version; it is written to `derived/<library>/<last two hex digits of the asset>/<asset>/<file>` on the `local`
   store through the journal, and the job's transaction replaces the rows of older specs. Job handlers hear of their
   commit (`Handler::committed`), after which the journal finishes what the job switched and deletes replaced files.
5. **Serving.** `GET /media/{asset}/{role}` streams a file from whichever store holds it, through the API in 1 MiB
   reads, with HTTP Range, `ETag` (its BLAKE3) and `Cache-Control: private` (`max-age=31536000, immutable` when the
   request names the hash in `?h=`). Renditions need `View`, other files `Download`, through `photolib_authz::can`, with
   a session, an API key or a signed URL. `POST` on the same path returns a URL valid for an hour:
   `?t=` carries the expiry, the account and 16 bytes of an HMAC-SHA256 over them, the asset and the role, keyed from
   the server key; the account and its access are checked again on each fetch. A refusal, a malformed path or a missing
   file is an empty 404 with `Cache-Control: private, no-store`.
6. **Throughput** is measured as docs/19 §3 states it: metadata, `thumb_s`, `thumb_m` and ThumbHash of a 12 MP JPEG,
   in CPU time per core on the fastest cores (`tools/perf/run.sh`).

## Consequences

* ✅ Every rendition is upright, colour-managed and metadata-free; spec changes heal themselves through the reconciler,
  and object-store media looks exactly like local media to clients.
* ⚠️ Building the server needs libvips (`libvips-dev`); HEIC needs libheif's HEVC plugin (`libheif-plugin-libde265`).
  Debian's and Ubuntu's libvips also carry loaders for ImageMagick and PDF: the explicit loaders keep them unused,
  and a server image should still leave them out.
* ⚠️ With an eager preview a 12 MP JPEG costs about three times its thumbnails (6–8 against 20–21 photos/s/core on the
  shared gate machine), since the preview needs the full decode; design 08 §9 counts the preview in its 19.
* ⚠️ Not built yet: `preview: on_demand`, a `RENDITION_PENDING` reason and the interactive lane on a miss, terminal
  failures keyed by source and decoder versions (an undecodable image is retried at each reconciliation), tone-mapped
  and gain-map HDR, LibRaw (libvips 8.17's `dcrawload`), animated renditions, deep-zoom tiles and video posters (M2-10).
* ⚠️ A signed URL keeps working for its hour after the API key that made it is revoked; a proxy that logs query
  strings logs it.

## Options considered

* **The `vips` command line per rendition**: no bindings to build, but about 60 ms to start and a decode per size.
* **`libvips-rust-bindings`**: generated for one minor version; its defaults pass options another version rejects.
* **A pure Rust image stack**: memory-safe, but no HEIC, AVIF or JPEG XL decoders of production quality.
* **Presigned store URLs** instead of streaming: ADR-0022 point 5.
* **Content-addressed rendition keys**: a rendition made again with the same bytes would reuse a key, which the
  journal never overwrites.
