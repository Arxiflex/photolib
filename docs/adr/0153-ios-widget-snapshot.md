# ADR-0153 — Home screen widgets read a pre-rendered snapshot in the App Group

* **Status**: Accepted — 2026-10-21 (photolib-design#504). The owner kept the decision: `Widgets/snapshot.json` and
  512 px PNGs of on this day in the App Group, written at start and when the app leaves the screen
  (photolib-design#551).
* **Requirements**: R-APP-4. **Design**: docs/10 §6.4.

## Context

docs/10 §6.4 has WidgetKit widgets (memories, on this day, backup status) read pre-rendered images and JSON that the
app writes to the App Group, never the replica: a widget extension has about 30 MB, no Flutter engine, no kernel and
no keys. M1 has no memories (M5) and no backup (M2); it has the device index.

## Decision

We will have the app keep `Widgets/` in the App Group `group.org.photolib.photolib` current
(`app/lib/core/widget_snapshot.dart`), at start and whenever the app leaves the screen:

* `snapshot.json`: `{"version": 1, "date": "YYYY-MM-DD", "onThisDay": [{"year", "image"}]}`. On this day is the
  newest device item of each of the last 6 earlier years taken on that month and day, newest year first.
* Each image is a PNG at most 512 px on its short side, from the thumbnail pipeline, named by the item's version, so
  it is rendered once; an item without one is left out.
* Every file is written under a temporary name and renamed, `snapshot.json` last; files it no longer names go.

The widget extension (`app/ios/WidgetExtension`, WidgetKit, no Flutter) decodes nothing but these PNGs. Its first
widget is *On this day*: each year of the snapshot of today's date for an hour, newest first, round again until
midnight, when its timeline ends; without today's snapshot it asks to open Photolib. After a write that changed
`snapshot.json`, the app has `WidgetCenter` reload every timeline (`reloadWidgets` of `org.photolib/inbox`). New
content (memories, backup status) adds keys and widgets; a change to an existing key raises `version`.

## Consequences

* Widgets show device photos without the replica, its keys or a Flutter engine.
* The snapshot holds thumbnails of device photos outside the vault, as Photos holds the photos themselves; it never
  holds an item of a server library. The app passcode (M1-24) must empty it while the app is locked.
* Until the app runs on a day, the widget shows no photos that day: the snapshot is of one date.

## Options considered

* **Widgets reading the replica**: needs its page key in the extension, and a second SQLite writer's locks.
* **JPEGs rendered by PhotoKit in Swift**: smaller files, but iOS-only and outside the thumbnail pipeline; Android's
  widgets can read the same snapshot.
