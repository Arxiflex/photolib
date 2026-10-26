# ADR-0106 — The photo viewer: tiles within two screens, a region decoder per platform, actions by URI

* **Status**: **Proposed** — owner to confirm (roadmap M1-11). Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-APP-4, R-APP-5. **Design**: docs/10 §4.1, [ADR-0070](0070-thumbnail-caches.md),
  [ADR-0094](0094-device-timeline.md).

## Context

M1-11 builds the photo viewer: tiled deep zoom, swipes with preloading, swipe-to-dismiss, double-tap zoom, a
filmstrip, an info panel, share and delete, keyboard control, copy to the clipboard (MOB-14) and a full metadata
explorer (VIEW-11). Its acceptance is a 200 MP image zooming without running out of memory on a mid-range phone and
an open under 150 ms. docs/10 §4.1 gives the tiling (Aves': tiles of half the viewport's short side, levels halving
the sample size, a coarser level underneath) and the region decoders per platform, but not how much is kept, what
platforms without a region decoder do, or how actions reach the platform. Flutter decodes only whole images.

## Decision

We will:

* **Tile as docs/10 §4.1 says, and keep at most two screens of tiles.** Tiles are squares of half the viewport's short
  side in device pixels at the largest power-of-two sample size that is still as sharp as the screen; they are decoded
  only once zoom passes the screen-size image, two at a time, nearest the centre first. A tile stays while on screen
  at the current sample size; one of another size only until the tiles over it arrive. On a 1080 × 2400 phone a
  200 MP image then needs at most 56 MiB of tiles at any zoom (`deep_zoom_test.dart`), whatever its size.
* **Decode regions with the platform where it can.** On Android, `ViewerChannel.kt` opens one `BitmapRegionDecoder`
  per item, decodes on two threads, applies the EXIF orientation and hands RGBA over the method channel. A desktop file
  goes through Flutter's codecs, which decode whole images: one sample size's image at a time, at most 64 MP and
  16,384 pixels a side, the tiles cut from it on the GPU; a finer zoom gets the finest image within that ceiling.
  Elsewhere (iOS until an ImageIO decoder, the web) the viewer zooms the screen-size image.
* **Load the screen-size image through the thumbnail pipeline** at the viewport's short side in device pixels, in
  steps of 256, with the grid's thumbnail shown until it arrives, for the item and one neighbour each side on phones,
  two on wider windows. Zoom reaches 2 device pixels per image pixel (at least 4×); a double tap zooms 2.5× about the
  tap or back; while zoomed, swipes pan instead of turning the page or closing.
* **Show the info from the device index** (`local_asset`): the capture time to its precision, "why this date?" from
  the resolver's stored source and confidence, camera, coordinates over a map placeholder until maps (M3-15), the
  file, and that it is on this device.
* **Share and copy by the item's URI on Android** (`ACTION_SEND` and `ClipData.newUri` with the MediaStore URI), with
  no plugin; other platforms get them with their integrations (M1-19, M1-20).
* **Leave delete to M1-16**, whose `DeletionService` will be the one path to the platform trash, and the metadata
  explorer to a kernel method that lists every tag (the kernel reads only the fields the product uses).
* **Measure the open** in `app/benchmark/perf_test.dart`: from the tap on a cell to the end of the viewer's first
  frame, against 150 ms on desktops and `headless`; the sharp image, tiles and phones wait for the device lab (M10-02).

## Consequences

* Memory is bounded by the screen, not the image: a 200 MP photo costs what a 20 MP one does once zoomed in.
* A desktop zooms a photo over 64 MP only to the finest sample size within the ceiling, and holds that image
  (≤ 256 MB) while zoomed; iOS and the web show no detail beyond the screen-size image yet.
* Follow-ups: an ImageIO region decoder in `ViewerChannel` for iOS; share and copy on iOS (M1-19) and desktops
  (M1-20); delete through M1-16's `DeletionService`; the metadata explorer (VIEW-11) with a kernel tag listing; server
  tiles and previews for remote items (M2); swiping on from a zoomed photo's edge.

## Options considered

* **Keep every decoded tile in an LRU of fixed size** (Aves): simpler, but its size is a guess per device; tying it to
  what is on screen bounds memory by the viewport.
* **Decode tiles in Dart** (the `image` package): decodes the whole file at full size on every platform.
* **`share_plus`**: copies a file into its cache to share it and takes no MediaStore URI; copying an image needs a
  further plugin per platform.
