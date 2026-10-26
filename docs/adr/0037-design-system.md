# ADR-0037 — Design system and interaction primitives: Material 3 plus our gestures, commands and motion

* **Status**: Accepted — 2026-10-16. The owner confirmed all three choices M0-25 made: the design system in
  `app/lib/ui/`, Ctrl/Cmd+K for the palette and Ctrl/Cmd+, for the settings, and no page transitions under reduce
  motion
  (photolib-design#329).
* **Requirements**: R-APP-4, R-APP-5, NFR-A11Y-1; catalogue rows DSK-04, I18N-10, I18N-11, I18N-14, I18N-16.
  **Design**: client app §1.2, §3.2, §3.6,
  i18n and accessibility §5,
  UX patterns 1, 7 and 11.

## Context

The design fixes the gestures (pinch snaps to density levels around the item under the fingers, long press then drag
selects with edge auto-scroll, a swipe down dismisses at about 15 % of the height or on a flick), `/` and `?` as keys,
instant transitions under reduce motion, and a `photolib_ui` package. It leaves open where the code lives, the other
shortcuts, how a gesture's alternative is offered (WCAG 2.5.1 asks for a single-pointer way to do every multi-pointer
or path gesture), and how high contrast is themed.

## Decision

* **Material 3 is the component library.** `appTheme` themes its buttons, chips, menus and sheets; we write only what
  it lacks: `SelectionBar`, `MediaGrid`, `SwipeToDismiss` and `Commands`. The design system stays in `app/lib/ui/`
  until a second app needs it, then moves to `packages/photolib_ui`.
* **Themes.** Light, dark and, when the system asks, high contrast: the same seed at Material's highest contrast level.
* **Motion.** `Motion` holds the durations (150 and 300 ms) and the standard easing; under the system's reduce motion
  they are zero and pages appear without a transition.
* **Commands.** Every action is a labelled `Command` with an optional shortcut, so the shortcut sheet (`?`) and the
  command palette (Ctrl+K, Cmd+K on Apple systems) list what the keys do. `/` opens Search and Ctrl/Cmd+, the
  settings. While a text field has focus only shortcuts with Ctrl, Cmd or Alt run.
* **Gestures.** A pinch snaps to the level nearest by ratio; the page owns the column count. Auto-scroll starts half a
  cell from an edge and reaches one screen per second at the edge. A swipe dismisses downwards only (upwards is kept
  for the info panel, pattern 12), past 15 % of the height or above 700 px/s.
* **Alternatives (I18N-16).** Zoom buttons with Ctrl/Cmd+= and Ctrl/Cmd+-; while selecting, a tap or Space toggles an
  item and a screen reader's long press selects; Escape, a close button and a screen reader's dismiss close a swiped
  page; collections reorder with buttons (M0-21).
* **Component gallery.** `app/lib/gallery.dart`, a second entry point, shows every component; its goldens cover light
  and dark in `en-XA` and `ar-XB`, with the accessibility guidelines and 200 % text.

## Consequences

* Material upgrades restyle the app for free, and the app looks like Material on iOS and desktop too.
* A page that shows a `MediaGrid` must also offer the zoom buttons and commands; the gallery shows how.
* Under reduce motion, iOS loses the animated back swipe; the back button remains.
* At 200 % text a selection count shrinks to fit the bar rather than being cut short.

## Options considered

* **A `photolib_ui` package now**: a second manifest, licence check and string catalogue for one consumer.
* **Selection and gesture packages** (`drag_select_grid_view` and the like): built on `GridView`, which the timeline
  rejects, and without the alternatives above.
* **`Shortcuts` and `Actions` per command**: an intent class per action and nothing to list in a shortcut sheet.
* **Ctrl+1…3 for the tabs**: browsers reserve them; the palette reaches the tabs instead.
