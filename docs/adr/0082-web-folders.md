# ADR-0082 — Web folders: File System Access handles in IndexedDB, size and time for identity, scans on the page

* **Status**: **Proposed — owner to confirm**
* **Requirements**: R-MODE-1. **Design**: 10 §7.1,
  [ADR-0042](0042-desktop-folder-sources.md), [ADR-0056](0056-web-support-tiers.md).

## Context

On Chromium the user may open a local folder as a standalone library through File System Access; other browsers
lack it. The design says to reuse the desktop's indexer, but a browser gives no paths, no file ids, no change events
and no isolates, and its access to a folder ends with the page unless the user lets it last.

## Decision

We will:

* Offer *Add folder* where `showDirectoryPicker` exists (Chrome and Edge on computers) and, in other browsers, say in
  the empty library that this browser cannot keep a folder, naming Chrome, Edge and the desktop app.
* Keep each picked directory handle in IndexedDB (`photolib/folders`, which crypto-erase deletes with the other
  databases) under its `media_source.root`: the folder's name, numbered (`Photos (2)`) when a folder there has it.
  A folder inside, around or equal to one in the library is refused, as on desktops, through `resolve()`.
* Scan through the desktop's `FolderIndexer`, with the file system behind a `FolderFiles` port. A browser file's id is
  its size and modification time, which a rename or move keeps; the indexer's rule (that id, size and time, at a path
  that no longer holds it) still tells a move from a copy.
* Match ignore rules in the case the computer's default file system does (Windows and macOS ignore it), not probed
  as desktops probe the volume: the probe would list a large folder once more.
* Scan every folder on the page when the replica opens, when a folder is added and when the page is shown again;
  never on a timer. A folder the browser no longer lets the app read turns offline with its items; *Allow access*
  in Settings asks again (`requestPermission`), where Chromium can offer to allow it on every visit.
* Keep the page rendering while it scans: a directory's writes go in batches of 100 rows, and a listing yields every
  8 ms.
* Stop the scan under way before its next directory when the replica closes, as a quit does, and close only then;
  the worker rolls back what its client left open before it closes the database (photolib-design#491,
  photolib-design#511).

## Consequences

* The same reconciliation, ignore rules, offline handling and tests serve desktops and browsers.
* Two files of the same size and time can trade items when both move at once; a file edited and moved at once
  becomes a new item until content hashes (M1-08) match it.
* Changes made while the page is open appear when it is shown again or reloaded.
* Browsers read a folder's metadata in the replica's data worker ([ADR-0232](0232-web-metadata-data-worker.md)), as
  [ADR-0072](0072-device-metadata-extraction.md) does on isolates.
* Indexing 10,000 images on the page takes about 3 s in Chrome here, missing 2–11 % of the animation frames in hitches
  of 0.1–0.4 s (Chrome enumerating the directory, collecting garbage), stretched to 0.5 s on a loaded machine; before
  the batches, 13–19 % and a freeze of 0.5 s. Moving the scan to a worker would need the replica there too.
* The handles are the one local store not under the device data key ([ADR-0057](0057-encrypted-local-store.md)): the
  browser stores them as it serialises them, the folder's path included. A handle grants nothing without permission,
  and survives removing its folder until the next pick prunes it.

## Options considered

* **Path as the id**: simpler, but every rename makes a new item and loses its albums.
* **`getUniqueId()`**: not standard and not shipped in every Chromium.
* **A rescan timer**: a full scan of a large folder every interval while the tab is merely open; the page being shown
  again is when the user can have changed the folder.
* **`webkitdirectory` everywhere**: a one-off import, not a library that stays in step; tier 2 keeps it as a later
  feature.
