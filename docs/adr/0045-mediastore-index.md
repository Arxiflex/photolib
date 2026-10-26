# ADR-0045 — MediaStore index: identity, re-scans and the install id

* **Status**: **Proposed — owner to confirm** (roadmap M1-01).
* **Requirements**: R-MODE-1, R-APP-4. **Design**: 10 §5.2 and §5.3, [ADR-0039](0039-android-default-gallery.md).

## Context

Design 10 §5.2 indexes Android's MediaStore by generations and names an item by `(volume, _ID)`, `GENERATION_ADDED`,
size and mtime, with a hash cache invalidated when the install id changes. It leaves open when an id stops naming the
same item, how deletions (which have no generation) are found within the 1 s delta budget, where the install id
lives and what invalidating means.

## Decision

* **Identity**: within one MediaStore version, `(volume, _ID, GENERATION_ADDED)` names an item. A full scan matches the
  rest by file (relative path, name, size, mtime), so a card MediaStore indexed again keeps its rows. After a new
  `getVersion` or a generation that went back (a rebuilt database), ids are freed and every row is matched by file.
  A change of size or mtime drops the row's hash and matched asset.
* **Re-scans**: a volume is read in full when it is new or comes back, after a new version or a generation that went
  back, and on every sync with partial access, as a selection grows by items of any generation. Otherwise only the
  items changed since the stored generation are read, then the counts are compared, and on a difference the ids are
  diffed inside SQLite. Unmounted volumes leave their items offline; no access leaves the index alone.
* **Install id**: a random id in `noBackupFilesDir`, which backups and device transfers leave out. When the stored one
  differs, the MediaStore index is dropped with its hashes, matches and backup states, and rebuilt.
* **Where it runs**: on an isolate of its own, as a client of the data isolate, reading MediaStore on a background
  task queue.

## Consequences

* Restored app data never pairs an id with another photo; it costs a cold index and hashing again, also after a
  reinstall on the same phone.
* With partial access, items the user deselects leave the index with their hashes.
* `queryDeletedFiles` (API 37.1, or S extension 23) is not used yet: id diffs run on every Android version, at the cost
  of reading all ids when counts differ.

## Options considered

* **Clearing only the hashes on a new install id**: rows, matches and backup states of the old phone's ids would
  survive and point at other photos.
* **The install id in the replica**: the replica is what a backup restores.
* **`ANDROID_ID`**: would spare a reinstall on the same phone a cold index, but it is a device identifier, where the
  design asks for an install id.
* **Diffing ids on every sync**: reading 100,000 ids back cost 300 ms of the 1 s delta on a desktop.
* **Ignoring volumes that are not mounted**: their items would be deleted and come back as new ones.
