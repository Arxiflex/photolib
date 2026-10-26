# ADR-0210 — Android device folders: an included set by volume and relative path, applied at query time

* **Status**: Accepted — 2026-10-21 (photolib-design#502). The owner kept all four decisions as made: the junk-folder
  defaults, the local-only lists in the replica, the 5-minute reveal and the new-folder notice
  (photolib-design#602).
* **Requirements**: R-APP-4, R-MODE-1, LIB-11. **Design**:
  client app §2, §5.2,
  feature catalogue LIB-11, ING-04.

## Context

Once the gallery permission is granted the MediaStore index (ADR-0045) shows every image and video of every volume:
Screenshots, messaging, browser and app folders, caches. Desktops add and remove folders (M1-25); the phone had no
way to leave a folder out, and folder galleries win reviews on exactly that (LIB-11, "include/exclude editable in
the UI"). The owner wants both starts: everything after the grant, or folders added one by one, reaching the same
state.

## Decision

* **A device folder is `(volume, relative path)`**, a row of the local-only `device_folder` table (replica schema 14):
  MediaStore's volume name and `RELATIVE_PATH`, never a bucket id, so a card's removal, a MediaStore rebuild and a
  reinstall keep it. Each MediaStore item carries its folder's row id in `local_asset.folder` (0 for every other
  source); the indexer adds folders as items arrive. A folder whose items went stays listed, *not present*, with its
  setting, until the user removes it.
* **Two lists, one mode.** Each folder has `excluded` (used while the library shows every folder but the excluded,
  the default) and `chosen` (used while it shows only the chosen); `device_folder_mode` holds the mode. Switching
  modes keeps both lists; a folder that appears later is shown in the first mode and not in the second.
* **A query-time filter, never a rescan.** The views `excluded_folder` (what the mode and lists keep out) and
  `hidden_folder` (that, unless revealed) are the one helper: every query of device items for the user filters
  `folder NOT IN (SELECT id FROM hidden_folder)` on a column the timeline's indexes end in, and
  `app/test/device_queries_test.dart` fails on a query or Dart file that reads device items without it or a stated
  reason (indexers, extraction, sync, the folder settings, an opened item's own folder). A switch is one row; showing
  a folder again loses nothing.
* **Day counts per folder.** `timeline_day (day, folder, count)`, kept by triggers on `local_asset`, makes the
  timeline's bucket query a sum over days and folders: within docs/10 §2's 50 ms at 1M items whatever is excluded,
  where a per-row filter over the index took 150–250 ms. `timeline_added (slot, folder, count)` does the same by date
  added, in quarter hours of UTC, which every time zone's offset is whole (schema 18, photolib-design#603).
* **Defaults.** A new folder starts excluded when the default junk list matches it (gitignore syntax over the
  relative path, any case): app-private and game data (`/Android/data/`, `/Android/obb/`), caches, hidden folders,
  and the album art of audio folders (`/Music/`, `/Podcasts/`, `/Ringtones/` …). Screenshots, messaging and download
  folders start shown. `.nomedia` is never read nor written.
* **Telling the user.** A folder that appears after the first index, junk aside, is *new* until the user answers the
  library's banner ("Screenshots, 312 items, is new": Keep or Exclude) or switches it in Settings.
* **Where the user is.** Settings › Library › Device folders lists every folder (name, path, internal or SD, items,
  newest day), shown and excluded, with a search box and the mode. The timeline's selection, the viewer's info panel
  and search's folder list exclude a folder in one tap, with Undo. "Show excluded folders for 5 minutes" in the
  library's view options reveals them, marked, and reverts on its timer (or, after a restart, by `reveal_until`).
  An item another app opens (`openInFolder`) swipes through its own folder, shown or not, and says so when excluded.
* **Export.** `exportDeviceFolders` / `importDeviceFolders` carry the mode and both lists by volume and path, for
  M1-33's bundle.

Amendments this needs in the design repository:

* docs/10 §5.2 gains *device folders and their included set*: the `device_folder` table, the mode, the query-time
  filter and `timeline_day`; §2's `timeline_entry` "carries its folder key" is `local_asset.folder` here.
* docs/02 LIB-11: device folders on Android, include and exclude editable in the UI, are delivered by M1-37.
* M1-15's default junk lists share this screen: the device's junk list is the defaults above.
* M2-18's backup selection starts from the included folders, the same `device_folder` rows.
* iOS is out of scope: PhotoKit has no folders, its albums are the unit (M1-02, M2-18).

## Consequences

* Every new query over device items must filter on `hidden_folder` or give its reason in the guard test.
* Writes to `local_asset` cost an upsert of `timeline_day` more, about 1 s per 100,000 inserts in SQLite alone, and
  one of `timeline_added`, about 0.3 s more.
* The date-added counts have a row per quarter hour and folder that items came in: 25 ms at 1M items of which the
  newest 100k came one by one, on a loaded machine; a library that only ever grew one item at a time would cost what
  the per-row filter did (1.6 s).
* M1-16's "temporarily show hidden" extends `hidden_folder`; M1-18's open-with and share targets call `openInFolder`.

## Options considered

* **A flag on each item, rewritten on every switch**: 50k row writes and index updates per switch, and the setting
  lives on items a rescan replaces.
* **A per-row filter only**: correct, but the bucket query at 1M took 150–250 ms, over the 50 ms budget.
* **`.nomedia` files**: other apps read them, a card removal or another gallery loses them, and writing to shared
  storage needs permissions the Play build never asks for.
* **Bucket ids**: MediaStore recomputes them from the path's hash, and a card reformatted or reindexed changes them.
