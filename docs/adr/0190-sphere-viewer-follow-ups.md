# ADR-0190 — Sphere viewer: packed filter input, a tile pyramid, cylinders and a fisheye lens

* **Status**: Accepted — 2026-10-23. The owner kept all three decisions of photolib-design#557: the 512 px tile
  pyramid over 2×1 or 4×2 textures, fisheye as a lens beside GPano's cylindrical projection, and captions from a
  sidecar only
  (photolib-design#681).
  Only *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-APP-5. **Design**: docs/10 §4.4, docs/08 §7,
  [ADR-0146](0146-panoramas-and-360-video.md).

## Context

ADR-0146's viewer left gaps: the shader filter's input, the viewport's pixels, held the part of the frame in view as
one rectangle, so near a pole and on a cubemap it was softer than the frame; panoramas past 8,192 pixels were
downscaled, where design 08 §7 asks for an on-demand 512 px tile pyramid and design 10 §4.4 for 2×1 or 4×2 textures;
design 08 §7's one shader names cylindrical and fisheye, which it did not draw.

## Decision

We will:

* **Pack the filter's input** (`SpherePacking`): the cells in view of 8 rows (a cubemap's 12 across, a panorama's
  fewer towards the poles), each in a slot of the viewport's pixels, slot 0 the whole eye, found by the shader in a
  16 × 8 map; a view the one rectangle holds at least as sharply keeps it.
* **Tile, not split**: a photo sphere whose view needs more than its loaded picture decodes the 512 px tiles in view at
  the coarsest sample that still puts a texel on each pixel, through the item's regions, each drawn as a crop of its
  own over the picture; this serves design 10 §4.4's 2×1 and 4×2 textures as well, at any size.
* **Read GPano's `cylindrical`** as an input projection, its height on the sphere from the full panorama's shape, and
  **offer fisheye as a lens** ('Fisheye', 'o', as 'e' edits): equidistant, up to 200°, libmpv's `v360` fisheye
  output. GPano names no fisheye picture to project.
* **Align compass lock with GPano's `PoseHeadingDegrees`** and **pad a cropped 360° video** (Spherical Video V2
  bounds) to its full panorama for `v360`, which takes no crop.
* **Show captions from a sidecar** `.vtt` or `.srt` of the video's name, beside its file or in its browser folder;
  embedded tracks stay M7-06's (I18N-15), and libmpv loads no sidecar itself, so captions show once.

## Consequences

* The filter lays a player's view out once per slot: dozens of draws of one texture, which Android and Apple must
  confirm on devices; Linux's pixel-buffer textures draw once a frame, so its probe feeds the filter a picture.
* Tiles decode one at a time and go when out of view; panning back decodes them again.
* `tools/smoke.sh` holds android, ios, macos and windows to the 360° golden frames with twins made on the host.

## Options considered

* **2×1 or 4×2 textures of the whole original**: a 16K panorama would still need 128 MP in memory; the pyramid needs
  what is in view.
* **A fisheye input projection**: no metadata the kernel reads declares one, nor its field of view.
* **Uniform arrays for the cell map**: Skia's runtime effects (the web, the VM's tests) index arrays by constants only.
