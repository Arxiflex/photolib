# ADR-0114 — Tiles at once: no deferral, stand-ins from the kernel's embedded previews, a ThumbHash per item

* **Status**: Accepted — 2026-10-20. The owner kept both decisions of M1-27 as made, half the decodes while the user
  scrolls and its latency budgets checked on desktops
  (photolib-design#471).
* **Requirements**: R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §3.3–§3.5,
  docs/08 §2.1, [ADR-0070](0070-thumbnail-caches.md), [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md).

## Context

The owner's rule of 2026-10-18: a cell that scrolls into view shows its photo at once; grey cells that fill in later
"look silly". ADR-0107 left desktops decoding a screen ahead, only once a fling slowed (`recommendDeferredLoading`),
nothing while the scrubber was held, and warming the disk cache one tile at a time. No
item had a ThumbHash, so a cell without a tile was a flat colour, and the T2.5 tier of docs/10 §3.4 (a file's embedded
preview) did not exist.

## Decision

We will never let a decode wait for the scroll, and never paint an empty cell where anything better is at hand:

* **Queue** (`Thumbnails`): no fling threshold and no deferred loading; the cells on screen come first, the newest
  requests first (those of one frame from the top), then two screens ahead in the scroll direction and one behind (two
  screens either side are built). A decode whose cell leaves the screen is cancelled at once and waits until the cell
  is back; tiles the disk cache has are read beside the decodes (cores − 1 on desktops, ADR-0040), eight per decode
  slot, as the rows of a frame want them. While the user scrolls, a drag-select's own scroll included, half the decodes
  run: they go on at any speed, and the frames keep their budget.
  The memory cache keeps at least three screens of images whatever its byte limit.
* **Scrubber**: cached tiles show during the drag; decodes pause only while the thumb moves a screen within 100 ms
  (about one decode), and start once it slows or is held.
* **Stand-ins**: until its own tier arrives, a cell shows another tier in memory, else a smaller one from the disk
  cache, else the file's embedded preview, scaled; the tile replaces it in one frame. `ReadMetadata` returns the span
  of the smallest JPEG a file holds as a picture of itself (EXIF IFD1, a TIFF-based RAW's preview IFD, RAF's JPEG, a
  HEIF `thmb` item coded as JPEG) without asking for its bytes; the desktop app reads at most 4 MiB of it on two
  workers of a `WorkerPool` and decodes it with Flutter's codecs.
* **ThumbHash**: `local_asset.thumbhash` (schema 8), listed by `timeline_item`, painted by every cell that has one.
  The warm-up computes it from the tile it warms (a 32 px copy) and keeps it in batches of 256.
* **Warm-up**: after a folder scan, on the cores but one, newest first, at the tier cells use, yielding while the
  timeline is busy or scrolled; the library shows its progress. At start it warms the items of folders not being
  scanned that have no ThumbHash: those indexed before schema 8, and those with no tile, tried again.
* **Debug log**: each tile's stages (queue, cache, embedded, decode, upload) at debug level.

## Consequences

* A folder after its warm-up scrolls from the disk cache at any speed; cold, cells show their EXIF thumbnail within
  tens of milliseconds. `app/benchmark/perf_test.dart` measures both (`tile-latency`, `folder-open`, `folder-scroll`).
* `tile-latency` and the tiles of `folder-open` are checked on `desktop` targets and printed on `headless`, whose GPU is
  emulated and whose cores are shared, as `thumbnail-tile`'s (ADR-0107); blank frames and first-frame ThumbHashes on
  both.
* The warm-up's ThumbHash writes refresh the timeline's snapshot once per batch.
* HEVC- or AV1-coded HEIF thumbnails are not covered: they need a decoder of their own; CR3's are (ADR-0247).
  Phones' items get no ThumbHash yet: their thumbnails come from the OS, with no warm-up (M1-08).
* Tiles now decode while scrolling fast, which costs CPU then: the timeline halves its decodes while the user
  scrolls, so that its own isolates leave the UI thread its frames; the warm-up, which yields while scrolling, takes
  the cores but one.
* ⚠️ docs/10 §3.3 must say that while the scrubber is dragged cells show the tiles in memory and on disk, and
  decodes pause only while the thumb moves a screen within 100 ms (not "ThumbHash only").
* ⚠️ docs/10 §3.4 must say that desktop folder items get their ThumbHash from the warm-up's tile (T0).
* ⚠️ docs/10 §3.5 must say that the queue looks two screens ahead in the scroll direction and one behind, and that
  desktops warm a folder after its scan and at start (not ±3 screens at rest).
* ⚠️ docs/19 §3 must list M1-27's budgets: `folder-open` (no cell of a cold open's first screen without a ThumbHash
  in its first frame, its tiles within 300 ms at p95), `tile-latency` (a tile from the disk cache within 10 ms, an
  embedded preview within 30 ms, the exact tier within 80 ms, at 1 and 3 screens a second and in a fling) and the
  blank frames of `folder-scroll` (no visible cell without an image for more than a frame after the warm-up).

## Options considered

* **Keep the fling threshold**: what made cells grey; the owner rejected it.
* **All the cores but one while scrolling too** (docs/10 §3.4's decoder pools): the decode isolates share the app's
  CPU with its UI thread, and frames suffered most on a loaded machine.
* **ThumbHashes in a table of their own**: fewer timeline refreshes, but a join in every page and one more device
  table; the batches keep the refreshes rare.
* **ThumbHashes from metadata extraction's embedded previews**: only files with a preview would get one; the warm-up
  has a tile of every item.
* **The kernel decoding the preview**: the kernel decodes no pixels (ADR-0004); a span keeps it a parser.
* **A kernel method of its own**: a second read of the same headers; `ReadMetadata` already gathers them and its
  corpus tests cover the new field.
