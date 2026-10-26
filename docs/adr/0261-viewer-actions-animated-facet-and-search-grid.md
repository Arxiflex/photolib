# ADR-0261 — Rotate, map and set-as in the viewer, animated images by facet, search results as the library's

* **Status**: Accepted — 2026-10-23. The owner kept all three choices
  (photolib-design#707,
  the provisional choices of photolib-design#607): Rotate turns the view only, no map on the web and Set as on Android
  alone, and each platform's own maps links.
* **Requirements**: R-APP-5, R-COMP-1. **Design**:
  client app §4, §5.1,
  feature catalogue VIEW-36, VIEW-39, FMT-13, EDP-02,
  [ADR-0086](0086-local-search-v0.md), [ADR-0208](0208-viewer-ergonomics-and-kept-state.md).

## Context

M1-32's composable bar names rotate, map and set-as, which no item had; animated WebP, APNG and AVIF went unbadged,
and phones played no animation, as only a GIF's type and a file's bytes told; search results were placeholders that
opened nothing and forgot their scroll position.

## Decision

We will:

* rotate the photo shown a quarter clockwise per tap (or `R`), per item until the viewer closes, without writing the
  file: saving a rotation is an edit, M1-22's (EDP-02);
* open a located item's place in the platform's maps app by URI: `geo:` on Android and Linux, Apple Maps' `maps://`
  on iOS and macOS, `bingmaps:` on Windows; none on the web, where only a web map service could show it;
* set a MediaStore photo as a wallpaper or contact photo through Android's `ATTACH_DATA` chooser; iOS's share sheet
  offers *Use as Wallpaper* already, and desktops have no such action yet;
* append each new action to `ViewerAction`, so the default bar has it and a bar the user arranged has it in its menu;
  M1-15's move, M1-16's delete, M1-22's edit and M1-23's slideshow join it the same way;
* record an `animated` facet: extraction from a file's first 64 KiB (a GIF's second frame or looping extension, or a
  GIF cut off before either; VP8X's animation flag; an APNG's `acTL` of frames before its image data; an AVIF's
  `avis` brand), PhotoKit from an asset's playback style; schema 19 shows the facets in `timeline_item` and reads
  every GIF, WebP, PNG and AVIF and PhotoKit's library again. A tile is badged as the facets say, a GIF until they
  exist (this replaces ADR-0208's badge by type). The viewer reads an animated MediaStore or PhotoKit item whole
  through its channel, never from iCloud;
* page search results as the viewer reads them, each cell the item's thumbnail with its name on a scrim, and keep the
  row at the top sealed in the vault (`searchTop`) while the search finds as many items, as the library's is.

## Consequences

A rotation is gone when the viewer closes; the viewer's Edit saves one as a copy (ADR-0331). Extraction reads every
PNG again once, screenshots included, in the background. A `geo:` URI on a Linux desktop without a maps app opens
nothing.

## Options considered

* **Rotate by writing EXIF orientation**: writes the user's files before the editor and its undo exist, and MediaStore
  files need a write request per item.
* **A web map in the viewer**: an outbound service, which needs its own ADR and privacy-manifest row.
* **Set as on desktops** (GNOME's `picture-uri`, `SystemParametersInfo`, `NSWorkspace.setDesktopImageURL`): three
  native paths for an action the issue drew from Android galleries.
* **Badge every GIF, PNG and WebP**: most are still: screenshots, stickers.
