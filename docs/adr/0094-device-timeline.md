# ADR-0094 — The device timeline: a view over the device index, selections as position ranges, date added from the id

* **Status**: **Proposed** — owner to confirm (roadmap M1-10). Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-APP-4, R-APP-5, NFR-PERF-1, NFR-PERF-3. **Design**: docs/10 §2–3,
  [ADR-0070](0070-thumbnail-caches.md), [ADR-0072](0072-device-metadata-extraction.md).

## Context

M1-10 builds the timeline: fixed-geometry segments, densities, the scrubber and multi-select (VIEW-03, VIEW-06,
VIEW-08). docs/10 §2 feeds it from client tables that sync and the indexers keep in step: `timeline_entry` per tile,
`timeline_bucket` per day and `bucket_page` per 512 entries; docs/10 §3.6 stores a selection as sort-key ranges plus
exceptions. In M1 the only source is the device index, `local_asset`; remote assets join with the unified timeline
(M2-24). The design does not say where "date added" comes from for a device item.

## Decision

We will:

* **Read the timeline from `local_asset`** through the view `timeline_item` (replica schema 6): each present item's
  local capture day (`taken_local`, else its platform or file time as a UTC day) and sort key, under an expression
  index on (day, sort key, id). Day counts are a `GROUP BY` over that index, watched; a page is one index seek from
  the start of its day plus an offset within the day.
* **Take date added from the id**: a `local_asset` id is a UUIDv7 minted when the index first sees the item, so its
  time is when this device added it. Schema 6 stores it in `added` and backfills it from existing ids.
* **Hold a selection as ranges of timeline positions**, over the snapshot it was made in: the library keeps that
  snapshot until the selection is cleared, so a position keeps naming the item the user chose.

## Consequences

* Nothing has to keep a second table in step with the device index, and a schema change is one view and two indexes.
* At 1M items the day counts cost a scan of the index (about 140 ms in SQLite 3.46 on a loaded 16-core machine, over
  the 50 ms docs/10 §2 budgets), run in the data isolate after each indexing transaction; a page at the end of a
  50k-item day costs 4 ms. `timeline_bucket` and `bucket_page` arrive with M2-24, maintained with `timeline_entry`.
* Selecting a day or everything is one range, and a drag rebuilds only the rows whose marks change; changes to the
  index wait while something is selected. Bulk actions will resolve positions to ids through the snapshot's pages.
* Date added is per device: an item re-indexed after its row is lost, or seen first on another device, is "added"
  again. Its days follow the device's current UTC offset.
* Unverified here: the budgets on the reference Android phone (M10-02); `perf_test.dart` measures the jump and the
  drag-select on Linux, and thumbnails on a real GPU only.

## Options considered

* **`timeline_entry`, `timeline_bucket` and `bucket_page` now**: triggers or indexer code for a single source, and a
  merge of remote assets that does not exist yet.
* **File times as date added**: a copy or a restore rewrites them, and they say nothing of when the library saw a file.
* **Sort-key ranges plus exceptions**: needed once a selection survives changes to the timeline, which M1 does not need.
