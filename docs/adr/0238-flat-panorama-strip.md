# ADR-0238 — Flat panoramas open as a strip the viewer's height, known from their metadata

* **Status**: Accepted (owner answered photolib-design#640, 2026-10-22: metadata only). Follows up photolib-design#589.
* **Requirements**: R-APP-5. **Design**: client app §4.4, media pipeline §7,
  [ADR-0146](0146-panoramas-and-360-video.md).

## Context

Design 10 §4.4 says flat phone panoramas get a pannable strip, and that panoramas are detected from metadata only,
never from the aspect ratio (owner, 2026-10-20). Design 08 §7 also counts Pixel `PANO` names and an aspect ratio of
2:1 or more without GPano as flat panoramas. The viewer fitted every flat photo, so a 6:1 panorama showed as a thin
band across the screen.

## Decision

We will open a photo whose row has the `panorama` facet and no projection the viewer shows (PhotoKit's panoramas, GPano
that says not to show it as a sphere or a projection the viewer does not draw) at the height of the viewer, centred,
where it is wider than the viewer at that height. Drags pan it instead of turning the page, as when zoomed; its
Previous and Next buttons turn it, as a sphere's do; pinches, double taps and the keys zoom it as any photo, and once
zoomed so it stays. Until then it follows the viewer's height as the filmstrip, the info and the window change it. A
photo without that facet fits, whatever its shape: the corpus' `PANO_20190101_120000.jpg`, 6:1 without GPano, fits.

## Consequences

* No guess from the shape or the name: a wide photo without the metadata opens fitted, as design 10 asks.
* Insta360's dual fisheyes, whose GPano projection extraction drops, open as strips too: flat, at full height.
* Design 08 §7's table needs the name and shape signals removed, an amendment in the design repository.

## Options considered

* **Design 08 §7's signals too** (Pixel `PANO` names, 2:1 or wider without GPano): catches phone panoramas that carry
  no metadata, but guesses from the shape, which the owner ruled out on 2026-10-20; a 2:1 or 20:9 phone photo would
  open zoomed on a phone.
* **A "view as strip" command**: a projection-like command on flat items, which M1-40 removed.
