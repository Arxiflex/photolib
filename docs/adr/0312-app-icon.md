# ADR-0312 — The app icon on every platform, written from the design's export set

* **Status**: **Proposed** — owner to confirm. Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: photolib-design#721. **Design**:
  brand and its
  `icon/` export set.

## Context

The app shipped Flutter's template icon everywhere. The owner chose *peak and reflection* (2026-10-22); the design
repository holds its masters and an export per platform. The brand README asks for the Android foreground at the 100 %
geometry, believing the sun inside the r = 33 dp safe circle; its centre is 33.9 dp from the middle and its radius
9.5 dp, so a round mask (r = 36 dp) cuts off about a third of it, which the study's *In context* row (the whole 112 %
tile in a circle) does not show.

## Decision

* `app/tool/icons.py <photolib-design>/docs/brand/icon` writes every platform's icon files from the design's exports:
  ImageMagick downscales the largest export a platform has (the 1024 px masters for iOS and macOS), never upscales,
  strips metadata, so a rerun writes the same bytes. Nobody edits them by hand; `tools/tests/check_icons.py` checks
  every size each platform lists and fails on any Flutter template icon under `app/`.
* Android takes the design's three 100 % layers as exported, with the clipped sun on round masks, until the owner
  says otherwise.
* The web's maskable icons are the full-bleed tile files; the manifest's splash is the tile's `#EEF3FF`, its theme the
  app's seed colour; the favicon's 16–48 px come from the 512 px export, as the design's ICO upscales its 16 px, with
  the SVG beside it.
* The Play listing's 512 px icon lives in the Triple-T listing (`play/listings/en-US/graphics/icon/`, a 32-bit PNG as
  Google asks), so the listing and F-Droid's carry it (ADR-0249).
* Linux packages install the hicolor set (48–512 px and scalable); the window shows the bundle's 256 px icon where no
  desktop entry names it; the MSIX logo is that tile too.

## Consequences

A change of the mark is a new export in the design repository and one run of `icons.py`. The Android foreground may
need a smaller export from the design; nothing else changes then.

## Options considered

* **The Android foreground as the study shows it** (the 112 % glyph at two thirds, whole within the safe circle):
  matches the *In context* row, but redraws the brand's Android geometry against the design's explicit export.
* **`flutter_launcher_icons`**: a dependency and a config with copies of the exports for the same downscales.
* **Rendering every size from the SVGs** (`rsvg-convert`): the issue names the 1024 px masters for iOS and macOS.
* **Vector drawables for the Android layers**: the themed icon's cut-outs need masks a VectorDrawable lacks.
