# ADR-0128 — Downloads: a stored zip64 streamed to a save dialog, the browser's downloads or the share sheet

* **Status**: Accepted — 2026-10-20 (photolib-design#463). The owner kept every decision and asked that the ADR say
  where the code keeps the last download folder, which the answer took to be the session until settings persist
  (photolib-design#483). Settings have persisted since photolib-design#484 (2026-10-19,
  ahead of M1-38), so the ADR says so. The owner also kept the share cap of
  photolib-design#499:
  500 items, a larger selection refused with the message; and iOS's copies at most the lesser of 2 GiB and 5 % of the
  free space, which docs/10 §6.2 left open
  (photolib-design#537,
  2026-10-21). On 2026-10-23 the owner kept the reading photolib-design#523 took
  (photolib-design#676): the code is unchanged and the last folder is kept with the settings,
  as the Desktops bullet says.
* **Requirements**: R-APP-5. **Design**: docs/10 §7.3, docs/10 §6.2, MIG-15 and SHR-26 of
  docs/02.

## Context

No client let a signed-in user save an item. MIG-15 asks for items and albums as originals or edited versions, a
streamed zip with the original file names; docs/10 §7.3 streams large web downloads through a Service Worker and
warns that Firefox stops one after 30 s; SHR-26's privacy options for the share sheet arrive with M3-14. The M1 app
shows only what is on the device or in a folder: nothing is server-only and no local item has an edit yet.

## Decision

We will download with one action, in the viewer's bar and in every selection bar (`SelectionBar` requires it):

* **One item** saves under its own file name; **several** as one zip named `Photolib <date> <time>.zip`, written as it
  is read: entries stored (photos and videos do not compress), each followed by a data descriptor, always zip64, so
  memory holds a chunk and the central directory whatever the sizes. Names are the items' base names without `/` or
  `\`, `_` for one of dots only, numbered ` (2)` when repeated regardless of case; times are the files' own, clamped to
  1980–2107. **Albums** (`downloadAlbums`, for the album pages' selection bars): one is a zip named after it, several
  one zip with a folder for each, its name made safe and numbered as a file's.
* **Desktops** ask with the platform's save dialog, which opens in the folder chosen last (kept with the settings:
  for the session until settings persisted, now in the vault's sealed `settings` object, ADR-0057, read back at
  start), write the chosen path directly and delete it when the download does not finish; macOS needs
  `files.user-selected.read-write` for this, and its folder bookmarks stay read-only. A file of a folder library
  also has *Show in Finder / Explorer / folder* (`NSWorkspace` from the sandbox, `explorer /select,`, the freedesktop
  `FileManager1` or `xdg-open`).
* **Browsers** use their own downloads: `web/download.js` streams the file through `web/download_sw.js`, a Service
  Worker scoped to `download/` that answers a hidden frame with a stream pulling one chunk at a time, pinged every
  10 s; Firefox, which keeps a failed stream's partial file and stops idle workers after 30 s, gets the file written
  to the origin's private file system first and handed over whole, and deleted on abort.
* **Phones share** instead (Android `ACTION_SEND_MULTIPLE`, iOS `UIActivityViewController` over each asset's current
  version, fetched from iCloud if need be as an explicit export, with the download's progress and a cancel in the
  same snackbar as desktops', its copies at most the lesser of 2 GiB and 5 % of the free space, one share at a time):
  what they show is in their gallery already, so
  *Save to Photos/Gallery* waits for server-only items (M2-24) and SHR-26's options for M3-14.
* **Versions**: when a selected item has an edit, a dialog offers the current version, selected, or the original; the
  selection is read for it only once the replica holds an edit, so until then 100k items are not.
* **Progress and cancel** come from the bytes read, through a snackbar; a cancel stops the item's source at once, even
  while it waits for more, and the destination deletes what it wrote.

## Consequences

* A zip is always zip64; unzippers from before 2001 cannot open it, and macOS's Archive Utility and Windows Explorer
  are yet to be checked on a real 10 GB archive.
* Server-only items need only a `Download` whose bytes come from `Server.get`; an edited version only its `edited`.
* Phones never zip, and share at most 500 items at once, refusing a larger selection with a message, never sharing
  part of it: an intent of more URIs can exceed Android's 1 MB binder limit, and iOS copies each item first.
* Firefox needs disk space for the whole file in the origin's quota before the download starts.

## Options considered

* **Deflate**: little gain on JPEG, HEIC and video, and CPU on every byte.
* **A server-side zip**: needs a server, which M1's items do not have; it stays an option for albums later.
* **`showSaveFilePicker` in Chromium**: no Firefox or Safari, and no download list entry; the Service Worker covers all.
* **A `.part` file renamed when done**: the macOS sandbox grants only the chosen path, not its folder.
* **Save to Photos/Gallery for device items**: they are there already.
