# ADR-0042 — Desktop folder sources: identity by file id, offline drives, shared ignore rules

* **Status**: Accepted — 2026-10-16. The owner answered M1-03's provisional choices in
  photolib-design#337:
  an empty root of a folder with items stays offline, and the poll and reconcile periods stand (confirmed). For the
  ignore rules, case-sensitive because the server runs on Linux, the owner asked that the server can run anywhere, on
  Linux out of the box; read literally for this choice, they now match case as the folder's volume does. On
  2026-10-17 the owner confirmed the reading, probed per scan, and kept Linux and containers as the server's platforms
  (photolib-design#374).
* **Requirements**: R-MODE-1. **Design**: 10 §8.1,
  07 §4.

## Context

On desktops the user adds folders, some on drives that come and go or on network shares. An item's albums and
favourites hang on its `local_asset` row, so a rename, a move or an unplugged drive must never give it a new row or
drop it. The design names the means (file ids, `.photolibignore`, watchers with polling) but not the rules.

## Decision

We will:

* Keep a folder file's identity in its `local_asset` row (`source_id` is the row's own id). A scan matches a file to
  the row with its path and file id; else to a row with its file id, size and modification time whose path no longer
  holds it (a rename or move); else to the row of its path (a save that writes a new file, a remount that renumbers
  files). File ids are device and inode on Linux and macOS, volume serial and file index on Windows.
* Never delete an item in a scan: a vanished file turns `missing`, and a folder whose root is missing, unreadable or
  empty while it has items turns `offline` with its items, changing nothing else. Only removing the folder deletes
  its rows.
* Read `.photolibignore` in gitignore syntax over the defaults of 07 §4, matching names in any case where the folder's
  volume does (by default on Windows and macOS, and on FAT and exFAT drives anywhere), in exact case elsewhere (by
  default on Linux), and pin the rules as cases in `testdata/photolibignore.json`, which the server's external
  libraries run too. Like git's probe for `core.ignorecase`, but writing nothing, a scan finds the volume
  case-insensitive when the root's first name that has a case, in another case, is the same file; with no such name,
  it takes the platform's default.
* Watch from the data isolate with `dart:io`: the tree on macOS and Windows, one watch per directory on Linux up to
  half of `max_user_watches`. Network shares (by mount type, `MNT_LOCAL` or `GetDriveTypeW`), drives away and failed
  or excess watches fall back to a full scan every minute; every folder is reconciled hourly. Full scans record the
  last directory they finished and resume after it.

## Consequences

* Renames, moves and remounts keep albums and favourites without hashing files; a file moved and edited at once, or
  moved across volumes, becomes a new item until the content hash (M1-08) can match it.
* Emptying a folder on purpose shows its items as offline rather than missing.
* Network shares cost a `stat` per file a minute while the app runs.
* A root whose first name with a case has a hard link in another case reads as case-insensitive.

## Options considered

* Identity by path only: a renamed folder loses its albums. By content hash first: reads every file before the
  library is browsable.
* A marker file on each drive (07 §4 does so for server roots): writes to the user's folders, impossible on read-only
  media.
* `package:watcher`: one more dependency for the same `dart:io` watches, and no per-directory limit on Linux.
* Ignore rules case-sensitive everywhere (the provisional choice): on a case-insensitive volume `*.JPG` keeps `a.jpg`,
  the same name to the file system, wherever the app or server runs. Case by platform: wrong for FAT and exFAT drives
  on Linux and for case-sensitive APFS.
