# ADR-0091 — Sync RPC: generic typed rows, streams of tables, a JSON cursor and an epoch counted in the data directory

* **Status**: **Proposed — owner to confirm** (roadmap M2-14).
* **Requirements**: R-MODE-2, NFR-PERF-5. **Design**:
  sync §3, §4, §8,
  API §3,
  ADR-0007.

## Context

Design 05 fixes the streams, the newest-first snapshot that hands over to the log at a watermark, `TimelineSummary`,
`RESET_REQUIRED` and epochs; [ADR-0053](0053-change-capture.md) the change capture underneath and
[ADR-0038](0038-authorization-policy.md) the one authorization path. It leaves open how rows travel, what a cursor
holds, which tables make up a stream, what an epoch is made of and what a timeline day is.

## Decision

* **Service**: `photolib.api.v1.SyncService` (beside ADR-0092's `CheckHashes`) with the server stream `Sync` and
  `GetTimelineSummary`, behind `Rule::Account(View)` (an account, or its key with `view`); clients feature-detect
  `sync.stream.v1`. A call names its streams with their cursors (at most 1,000) and ends once each has caught up; hints
  on `/events` tell a device in the foreground when to call again (ADR-0225).
* **Rows** (`photolib.sync.v1`): a batch groups rows by table as column names once and `Value`s per row; uuids, text,
  dates, JSON and arrays are text, times milliseconds since the epoch. The columns come from the catalogue, so a
  migration's column syncs without code, minus those no client may have: server paths and settings, storage keys,
  link secrets, `raw_metadata` and face embeddings. A deletion carries the key columns only.
* **Streams** are tables with SQL that picks their rows and tombstones (`rpc/sync.rs`). A table whose capture scope is
  the stream's (`assets/{library}` by library) keeps rows outside the caller's `scope` as deletions, so a member loses
  what becomes locked, or trashed unless they may delete it; a table of what the caller may see (`libraries`,
  `albums`) keeps only those. What hangs off a sent row (files, versions, custom values; an album item's asset) travels
  in the same batch, and each row still passes `scope`, asked for a page of ids at once. The caller's own rows
  (`asset_user_state`, …) are theirs whatever they point at. `partner/{owner}` holds the owner's own libraries' assets
  in the share's window, and private libraries whole.
* **Cursor**: opaque bytes, JSON of the epoch, the last `(txid, key)` read per table and, during a snapshot, its
  watermark and position. An empty cursor starts the stream: its assets newest first (undated last, on the new
  `assets_newest` index) with what hangs off them, then every table in the log from the snapshot's watermark; the other
  tables of a stream read their log from the start.
* **Statuses**: `RESET_REQUIRED` for a cursor of another epoch, unreadable, at or below the tombstone horizon, or past
  the database's newest transaction (restored elsewhere); `FORBIDDEN` for a stream that is unknown or not the caller's.
  A device that sees a membership or share change opens the stream it governs again from scratch (a backfill).
* **Epoch**: `<instance id>.<restores>`, the counter in the data directory's instance marker (a restored database
  cannot take it back), raised by `photolibd restore`.
* **Timeline summary**: per library the caller may view, standard and not hidden from its timeline, the assets it
  may view that are not archived, locked or trashed, counted per local capture day (`taken_local`, else the UTC day of
  `taken_utc`), newest first, undated last.
* **Compression**: zstd and gzip as the client accepts them, for messages of 1 KiB and more.

## Consequences

* 100k assets with a file each sync in 4 to 6 s through the Connect stack in a release build at load 80 to 100 on 16
  cores (5.8 MB of zstd), one change in 7 to 22 ms (`tests/sync.rs`, run by `tools/perf/run.sh`); with stale planner
  statistics, right after a bulk import, the snapshot takes about twice as long until autovacuum analyses the tables.
* Clients map rows by column name and must ignore unknown tables, columns and enum values.
* Tables with an `asset_id` got a `txid` index and tombstones one on `(entity, txid)`: every write updates one more
  index.
* A removal tells a member the id of a row it may no longer see; ids are UUIDv7, so its creation time too. An album's
  cover and a memory's items are ids too: a device shows one only if its replica holds the asset (as `Cover` and
  `Memory` in `photolib_authz::can`), which no stream sends to whom may not view it.
* Shared-vocabulary tables (`places`, `ml_labels`), tag assignments, face constraints and stacks join their streams
  later; the cursor starts a table it does not name from scratch.

## Options considered

* **A message per entity**: typed fields, but a projection to keep in step with the schema in Rust, Dart and the
  proto, for some forty tables; the replica already maps columns by name.
* **JSON rows**: one line of SQL, but times and bytes lose their type and every key repeats per row.
* **Epoch as a random value in the database**: a restore brings the old value back with the dump.
* **A cursor of one txid per stream**: tables of a stream read in one ordered union; the per-table cursor lets a table
  join a stream later and keeps each read on its own index.
