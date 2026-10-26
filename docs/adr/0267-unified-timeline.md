# ADR-0267 — The unified timeline: one tile per photo from two flags that triggers keep

* **Status**: **Proposed** — owner to confirm (roadmap M2-24). Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-MODE-1, R-MODE-2; VIEW-05, LIB-06. **Design**: docs/10 §2, §3.4, §3.6,
  [ADR-0200](0200-device-and-server-copies.md) (rows B1, B5, T1–T3, T9, T11, O1, E1, X1–X5),
  [ADR-0094](0094-device-timeline.md), [ADR-0120](0120-client-sync-engine.md),
  [ADR-0246](0246-server-renditions-tier.md).

## Context

The timeline was a view over the device index (ADR-0094). M2-24 adds the account's synced assets, one tile per photo
with a badge, a filter by backup state and a delete dialog that says what goes where. docs/10 §2 plans a
`timeline_entry` table with `timeline_bucket` and `bucket_page`, which ADR-0094 deferred to this item. Joining each
device item to its asset while counting days leaves the index for every row: 11.5 s for the day counts of 1M device
items and 1M assets, against 0.1 s for the device index alone (SQLite 3.45, in memory).

## Decision

We will:

* **Show a photo once**: a device item and the asset it links (`local_asset.asset_id`, which the backup sets when it
  uploads the item or finds its hash on the server, M2-18) are the device item's tile; of two device copies of one
  asset, the one with the smaller id. An asset that no present device item outside the system trash links is a tile
  of its own when it is a photo or video of a library the account syncs, not trashed, archived or locked. A device item
  whose asset is trashed, archived or locked has no tile (E1).
* **Name three states**: *backed up* when the linked asset is in the replica, in a managed library; *not backed up*
  when it is unlinked, or its asset is in an external library (T11) or not in the replica (deleted forever, not synced
  yet); *cloud only* for an asset's own tile.
* **Keep who shows an asset in two flags** that SQLite triggers recompute in the transaction that changes a link, a
  device item's presence or an asset: `local_asset.tile` and `asset.on_device` (replica schema 27), which on-device ML's
  progress (`ml_count`) counts by too. Partial expression indexes hold every column a day count reads; a page merges the
  device's and the server's index in order (`UNION ALL` with one `ORDER BY`). Day counts add ADR-0210's `timeline_day`,
  or by date added `timeline_added`, which count device tiles only, to a group of the server's index, and group the
  device's index for one backup state. 300k device items and 300k assets count their days in 103 ms and read a page in
  1 ms on the loaded gate machine.
* **Badge two states while signed in**: *Not backed up* (a crossed cloud) and *Cloud only*, nothing for backed up, at
  the bottom start, ADR-0215's corner for a tile's state, past ADR-0210's mark of an excluded folder's item and before
  ADR-0245's marks; the view menu hides them, kept with the settings, and shows one state at a time, which a chip above
  the timeline clears. Without a server nothing is backed up and no tile says so.
* **Show what only the server has** through the pipeline's T5 tier (ADR-0246): the timeline row carries its
  renditions' hashes, so a cached tile shows without the network; the app also syncs on every resume, and forgets
  what the server sent once signed out, as the replica belongs to one account (docs/10 §2).
* **Ask before deleting** while signed in, from the library, a folder's items and the viewer, with the counts and the
  bytes of each group, *Move to trash* (every copy, each into its trash: the device's through `DeletionService`, the
  library's as a `trashed_at` edit of the outbox) and, for backed-up items, *Remove from this device*; on Apple
  devices it says iCloud Photos follows. Signed out nothing else holds the items, and the trash asks nothing as before;
  a computer folder's *Delete folder* says its items leave this device only.

## Consequences

* A synced asset costs one index probe on top of its write; device items no backup has linked cost nothing. Day counts
  still scan the server's index, and the device's for one backup state, over docs/10 §2's 50 ms at 1M as ADR-0094's
  did; `timeline_bucket` stays deferred.
* A device item the backup has not linked shows beside its asset, even with the same hash, until M2-18 links it.
* The library's trash and its review across devices (*Recently deleted*, purges) stay M2-26's and M2-36's.
* Not yet: hiding a library from the timeline (LIB-06; photolibd syncs `library_user_state`, the replica does not keep
  it), partners' photos, private pending tiles, cloud-only videos in the viewer and their info panel.

## Options considered

* **`timeline_entry` and `timeline_bucket` (docs/10 §2)**: counts without scans, but a copy of each tile's day, sort key
  and ThumbHash that extraction and the warm-up would rewrite, on the paths that hold the 100k budgets.
* **A view that joins per row**: no state to keep; 11.5 s for the day counts at 1M.
* **Joining by content hash when reading**: two more probes a row, for what the backup links anyway.
* **Badges in standalone mode**: every tile would say *Not backed up*, which tells the user nothing.
