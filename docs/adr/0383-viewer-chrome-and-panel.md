# ADR-0383 — The viewer's chrome, cues and information panel: the open choices of the owner's prototype

* **Status**: **Proposed — owner to confirm** (roadmap M1-60, photolib-design#794).
* **Requirements**: R-APP-4, R-APP-5. **Design**: 10 §4.6, prototype, VIEW-40 to VIEW-44.

## Context

M1-60 builds the viewer the owner's review of 2026-10-23 settled in its prototype: a fixed-slot bar folded into `⋮`, a
filmstrip of its own, hover arrows, cues for video and 360° items, a grouped information panel and a native-feeling
open. Design 10 §4.6 lists four open questions with the prototype's leans, and the build met a few more choices the
design does not settle.

## Decision

We will build the leans and record the rest:

1. **Autoplay** of a video as it is shown is a setting (Settings › Viewing), off; a slideshow and auto-next still play.
2. **The hide delays** of a playing video's controls are fixed, 1.5 s after the pointer stops and 0.3 s after it leaves.
3. **People** shows nothing while face recognition is off, no prompt to turn it on.
4. **The Tags heading** stays; Albums and Tags show even when empty, but Tags only where tags are kept (M3-03).
5. **Keys**: `F` toggles the filmstrip, as §4.6 says; favourite moves from `F` (docs/17 §5) to `L`.
6. **A sphere opens rotatable** and never pages by a swipe or an edge tap; the 360° view mode of ADR-0146 and
   photolib-design#556 goes, the revisit photolib-design#658 left for later. The little planet and the fisheye are on
   a long press of the compass dial and on `P` and `O`; the device's motion and the compass lock are buttons above the
   dial; HDR and a motion photo's video are buttons at the picture's other corner and keys (`H`, `M`); HDR is also a
   switch in Settings.
7. **Video controls** hold play, the time, the scrubber, mute, captions and the speeds 1×, 1.5×, 2× and 0.5×; frame
   steps keep their keys (`,` `.`) and loop its setting until M7-06 brings them back as buttons.
8. **The information panel** follows the app's light or dark theme while the stage stays black; below 760 dp its sheet
   opens at its peek (a quarter of the height), so the photo's middle stays in view.
9. **The map agreement** is kept per device with the other settings; until M1-55's mini-map lands, the agreed slot
   shows a placeholder and loads nothing.
10. **Sections without data**: the lens and exposure line waits for extraction to read them; description, people,
    tags and versions come from `InfoFacts`, empty until M3-03, M3-04, M5-10 and M8-08 keep them; albums and backups
    read the device's own.

## Consequences

The bar never shifts between items, the photo never moves with the chrome, and every cue is a picture rather than a
word. Each choice above is one setting, constant or line to change. The four open questions stay open for the owner;
favourite on `L` contradicts docs/17 §5 until the design says which key wins.

## Options considered

* Autoplay on by default, as Google Photos does on phones: rejected by the prototype's lean (a click plays).
* Keeping the 360° view mode: rejected by §4.6 ("opens already rotatable, with no extra tap").
* Folding the item-type commands into `⋮`: rejected, as the menu would change from item to item.
* A full-height sheet: it hides the photo the info describes.
