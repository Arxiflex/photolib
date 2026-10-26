# ADR-0070 — Thumbnail caches: a self-healing disk cache, ThumbHash meshes, platform thumbnailers first

* **Status**: Accepted — 2026-10-17 (roadmap M1-09). The owner answered
  photolib-design#379
  with two changes: the kernel alone encodes ThumbHashes, and T2 is sealed now rather than later.
* **Requirements**: R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §3.4–3.5, docs/21 §3,
  [ADR-0040](0040-timeline-image-pipeline.md).

## Context

ADR-0040 chose how the timeline decodes; M1-09 builds the tiers around it: ThumbHash placeholders (T0), decoded images
(T1), a disk cache of encoded thumbnails that is bounded and rebuilds its index after corruption (T2), the platform's
thumbnailers (T3) and the originals (T4), with prefetch and cancellation. The design leaves the cache's layout, how a
cell paints a ThumbHash and where ThumbHash code lives to the implementation. docs/16 puts ThumbHash in the kernel, but
the app links no kernel yet (`prebuilt.json` pins no library) and the kernel is asynchronous on the web, while T0 must
paint in the frame that shows the cell.

## Decision

We will build the tiers in `app/lib/features/library/timeline/` behind `ThumbnailPipeline`:

* **T2** is `DiskCache`: one file per item, content version and tier, a magic and a PLB envelope under the cache key
  (docs/21 §3) bound to its name, and an index, `thumb_cache_index`, that is a journal of checksummed records
  compacted as it grows. The vault's tile cipher seals and opens the envelopes on an isolate that holds only the cache
  key (`Vault.tileCipher`), which it drops when the vault locks; a locked store's entry is a miss, a damaged, foreign
  or plaintext one (the magic `PLT2` of builds before) is dropped when read. Opening keeps the
  journal's valid prefix and reconciles it with the directory on an isolate: unknown files are adopted as the least
  recently used, strays and lost files dropped; a damaged entry is dropped when read. The bound, 1 GiB by default,
  counts the index, and the least recently used entries go first. Decoded originals are written back as JPEG (PNG
  when transparent), encoded with `package:image` on an isolate.
* **T0**: only the kernel encodes ThumbHashes (`EncodeThumbHash`, for the server's renditions and the desktops'
  warm-up), and Dart only decodes them (`ThumbHash`), so that a cell paints its hash in the frame that shows it; both
  run the reference implementation's vectors in `testdata/thumbhash.json`. A row paints each cell's hash as a 7 × 7
  vertex mesh in one `drawVertices` call, so it needs no image decode.
* **T3** comes before T4 and is not written back, as the OS keeps it: `loadThumbnail` on Android (`ThumbnailChannel.kt`,
  cores − 1 threads, pixels through the method channel) and the freedesktop.org cache on Linux. **T4** decodes file
  originals with Flutter's codecs on desktops.
* **The queue** starts the visible cells, then a screen ahead and half a screen behind, nothing while the scroll
  physics recommend deferred loading, and cancels a running request no cell wants; memory pressure clears T1.

## Consequences

* The cache survives any damage to its directory at the cost of entries, and the gate proves it by damaging the index
  at random (`disk_cache_test.dart`).
* No thumbnail is at rest in plaintext but the OS's own caches T3 reads; the plaintext entries of earlier builds go
  as they are read, their bytes counted until then. Android hands pixels over through the channel rather than by
  address, which changes behind `mediaStoreThumbnail`.
* Still to come: PhotoKit (M1-02), `QLThumbnailGenerator` and `IShellItemImageFactory`, HEIC and RAW on Windows and
  Linux (open decision 7), video frames on desktops, server renditions (T5) and with them the web's decoders of
  [ADR-0056](0056-web-support-tiers.md), purging an item's entries when it is deleted, and warming T2 ±3 screens at
  rest.
* Unverified: NFR-PERF-1 on the reference devices (M0-27, M10-02).

## Options considered

* **An index in SQLite**: a second database writer beside the replica's data isolate, and its own corruption to heal.
* **The directory alone as the index**: every start would `stat` every entry to order them.
* **Engine-encoded PNG for T2**: no dependency, but five to ten times the bytes of a JPEG.
* **ThumbHash only in the kernel**: no synchronous call on the web, so T0 would miss the cell's first frame.
* **ThumbHash in Dart too** (the provisional choice): a second encoder to keep identical to the server's.
* **Plaintext T2 until later** (the provisional choice): against PRIV-33, which allows no plaintext store.
* **Opening T2 on the calling isolate**, as browsers' `VaultCache` does: the decryption would share the UI isolate's
  frames.
* **Decoding each hash to a small image**: an asynchronous decode per cell, so the first frame would show a flat colour.
