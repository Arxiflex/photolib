# ADR-0216 — HDR and RAW in the viewer: a facet the kernel decides, the leaf for the item shown, RAWs' largest preview

* **Status**: Accepted — 2026-10-23. The owner confirmed it as recorded (roadmap M1-14, photolib-design#61): HDR
  decided at extraction with the whole library read again once, Samsung's SEF gain maps in SDR and the HDR toggle on
  by default
  (photolib-design#722).
* **Requirements**: R-APP-5, VIEW-20. **Design**:
  08 §2.1, §5.7,
  10 §4.1, §4.5,
  [ADR-0060](0060-hdr-native-leaf-views.md), [ADR-0114](0114-tiles-at-once.md), [ADR-0247](0247-raw-pipeline.md).

## Context

ADR-0060 built the native HDR leaf and left the viewer to M1-14. The viewer must know which items are HDR before it
creates a leaf, as the leaf is what stutters; nothing recorded that yet: the kernel read PQ, HLG and Dolby Vision but
no gain map. ADR-0247 shows a RAW as its largest embedded JPEG, but only once the decoders before it (the OS's RAW
decoders on macOS and Windows) have answered.

## Decision

* **HDR is a facet.** `ReadMetadata` says whether a still carries a gain map that platform decoders apply (Ultra
  HDR's `hdrgm:Version`, ISO 21496-1's JPEG APP2 or HEIF `tmap` item, Apple's HEIF auxiliary image); extraction
  writes the facet `hdr` for those and for PQ, HLG and Dolby Vision files. Schema 20 reads every file again.
  Samsung's SEF gain map is no HDR: no platform decoder applies it (the server converts it, 08 §2.1).
* **The leaf is the item shown's.** On Android, iOS and macOS a still with the facet gets its `HdrLeaf` once the
  viewer has grown to the screen and the 150 ms dwell has passed, never a neighbour's; a page turn drops it at once.
  An HDR video plays in `video_player`'s platform view (ExoPlayer on a `SurfaceView`, `AVPlayerLayer`) on Android and
  iOS screens with headroom, under its poster until it has played a frame; macOS plays it in a texture, in SDR.
* **SDR on request.** The viewer's toggle (`Settings.hdr`, on by default) shows HDR items in SDR, the next ones too;
  battery saver and low power mode do so as the leaves answer `sdr` to `support`.
* **RAWs show their largest embedded JPEG at once** (`ReadMetadataResponse.largest_preview`, turned as ADR-0247 says)
  at the screen's tier, beside the decode, which replaces it only when larger.

## Consequences

* Each HDR item creates its own leaf: docs/10 §4.5's single recycled view is left to the device measurements of the
  test phase (ADR-0060), which say whether recycling is needed.
* A whole library is read again once after the upgrade, in the background, as extraction always runs.
* PhotoKit assets are not extracted: on iOS only those PhotoKit marks HDR (its `hdr` subtype) get the leaf.
* Apple's JPEG gain maps (an MPF image with Apple's auxiliary type) are not found yet: their marker is in the second
  image's XMP, which the kernel does not read.
* The web shows SDR; docs/10 §4.5's `<img>` leaf on Chromium and Safari is not built.

## Options considered

* **Asking the platform per item** (`Bitmap.hasGainmap()`, ImageIO's auxiliary data) when it opens: a decode before
  the dwell, on every item, where the facet costs nothing.
* **The prototype's native video players in the leaf**: a second player beside the viewer's, without its controls.
* **Showing the embedded preview of every file first**: a JPEG's EXIF thumbnail is smaller than the grid's tile
  already shown, so only RAWs gain.
