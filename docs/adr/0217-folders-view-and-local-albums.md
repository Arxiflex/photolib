# ADR-0217 — Folders view and local albums: where their order, views and files live

* **Status**: Accepted — 2026-10-23. The owner kept all five choices
  (photolib-design#705,
  the provisional choices of photolib-design#63, roadmap M1-15). Since then M1-16's deletion service
  ([ADR-0245](0245-deletion-trash-and-device-state.md)) deletes a folder into the platform's trash on every desktop.
* **Requirements**: F-07, R-MODE-1. **Design**: docs/04 §5, docs/10 §8,
  feature catalogue: VIEW-34, VIEW-37, VIEW-38, MOB-24, MOB-26, LIB-11.

## Context

M1-15 adds the folders view and local albums. Standalone mode keeps albums in the shared schema (docs/04 §11), but
nothing there names an owner before an account exists, the album items' `asset_id` points at `asset` rows that a
standalone device does not have, `album` has no place in a manual order, and folders, their per-folder sort and the
move dialog's recent targets have no table at all. File operations need a bin, which M1-16 designs for every platform.

## Decision

* **Albums**: album folders and albums are rows of `album_folder` and `album` with UUIDv7 ids, `owner_id` the nil UUID
  and no `txid`, so a failed migration keeps them (ADR-0031) and M2's outbox can replay them with their ids. Until an
  account adopts them, an album item's `asset_id` names the `local_asset` row it holds. An album's sort is its
  `sort_mode` (`custom` or `<sort>_<asc|desc>`) and its layout its `layout` (`grid` or `list`); the cover is
  `cover_asset_id`, else the first item.
* **Per-device view state**: each device folder's sort and layout, the manual order and pins of the folders and of each
  album folder's entries, and the recent move targets are a sealed vault object, `folders`, as the settings and the
  collections layout are (ADR-0090). A folder's key is `(source, volume, path)`, so new files and rescans keep it.
* **Start screen**: Settings choose the timeline, the folders and albums, or the favourites, and the tab the folders
  and albums open on.
* **Excluded folders**: the folders view hides the device folders the user keeps out and the default junk list's
  (music and its album art, caches, app-private and hidden folders; `isJunk`,
  [ADR-0210](0210-device-folders.md)) until the user taps "Show excluded folders"; favourites and albums
  leave out the items of hidden folders, as every device-item query does.
* **File operations** run on desktop folder files only: renames in two steps through temporary names, never over a
  file; moves and copies one file at a time on a worker, a copy synced, read back and compared by SHA-256 before it
  takes its name, the original's time kept, a move's original removed only then. A folder is deleted into the
  freedesktop.org trash on Linux; elsewhere the app offers no folder delete until M1-16's deletion service.

## Consequences

* Albums, covers and views work offline today; M2 maps local item ids to assets when it replays them, as
  [ADR-0202](0202-albums-across-custody.md)'s pending entries do by the item's hash, and gives the owner its account's
  id.
* Manual order and pins stay on the device that set them; syncing them is M3-01's (ORG-06), with the album list's sorts.
* Android and iOS get the folders view, albums and views but no file operations or folder delete yet: those need
  MediaStore write requests and PhotoKit changes, which M1-16 and M1-18 bring.

## Options considered

* **A replica table for the per-device state**: a schema change and migration for data no server needs; the vault
  object already seals the other per-device preferences.
* **A `sort_key` on `album`**: a change to the shared schema and the server's that M3-01 makes with the album list's
  sorting; until then a per-device order serves.
* **Folder deletes through the platform's trash on every desktop now**: macOS and Windows need native code that this
  machine cannot build or test; M1-16 owns deletion.
