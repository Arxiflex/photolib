# ADR-0092 — Per-user deduplication: `CheckHashes` and links at upload completion, over the owner's own libraries

* **Status**: Accepted — 2026-10-23 (roadmap M2-12): asked whether ADR-0200's proposal 6 changes point 2, the owner
  kept it as it stands
  (photolib-design#668):
  an upload whose bytes only a read-only external library holds is linked, not stored again.
* **Requirements**: R-REL-1. **Design**:
  07 §7,
  03 §4.1,
  05 §5, §8,
  06 §9,
  16 §3.

## Context

The design links exact duplicates within a user's libraries instead of storing them twice, external libraries
included; devices ask `CheckHashes` before uploading; dedup across users is never offered, as it would confirm other
people's files. It leaves open where the server catches a duplicate uploaded anyway, which copies count, and how
`CheckHashes` is authorised and bounded.

## Decision

1. **Only the owner's own libraries count** (`libraries.owner_id`), so a hash says nothing about another account,
   nor about libraries shared with the user. Uploads into a library someone else owns are never linked.
2. **A file is held** by an `original`, `original_alt` or `live_motion` file with its BLAKE3 that is `present`, of an
   asset out of the trash, in a library `online` or `scanning` (`dedup::HELD`, index `asset_files_content_hash`).
   Missing, offline and trashed copies do not count: such a backup is stored again rather than linked to bytes that
   may be gone.
3. **`SyncService.CheckHashes`** takes up to 1000 hashes of 32 bytes and answers, in their order, the earliest asset
   holding each (lowest UUIDv7), or an empty id. Its rule is the new `Rule::Account(View)`: an account, or its key
   with the view scope; rows also pass `scope`. Devices link to the asset instead of uploading, and re-verify their
   backups with it after an epoch change.
4. **At upload completion**, once the bytes have their hash (ADR-0061 point 5), an upload into a standard library that
   its uploader owns is linked when the owner's libraries hold the file, or a complete upload of theirs that ingest
   has yet to record does: it is acknowledged as usual and forgotten with its staged copy; nothing is written, queued
   or counted against the quota. For such an upload, ADR-0061's verified write is the copy already stored.
5. **Private libraries** are never linked by the server: their uploads are ciphertext. Their keyed dedup tokens are
   what private assets will record and `CheckHashes` will find (M6-04).

## Consequences

* A photo already in the user's NAS library, or sent by two of their devices, is stored once.
* ⚠️ Two identical uploads completing at the same moment are both stored, and so is an upload that an external
  library's scan hashes later; duplicate review (M5-14) shows them.
* ⚠️ A linked upload is gone at once, as after ingest: devices find the asset with `CheckHashes`.
* ⚠️ A backup linked to an external library depends on it: once the file goes missing, `CheckHashes` stops finding
  it and the device uploads it again.
* ⚠️ Groups are not considered: a Live Photo whose still is held already leaves its video to become an asset of its
  own until `CommitAsset` commits parts together (M2-21).
* ADR-0038's route rules gain `Account(action)` next to `Anyone` and `Server(action)`.

## Options considered

* **Deduplicating in ingest**: sees groups, but writes the bytes first and must delete them through the journal after
  the job commits; the device learns nothing more.
* **Answering the creation from the announced hash**: saves the transfer but acknowledges bytes never received;
  `CheckHashes` does that before the upload.
* **Counting trashed, missing or offline copies**: would link a backup to bytes about to be purged or out of reach.
* **Single-instance storage across users** (LIB-21, won't do): confirms other users' files.
