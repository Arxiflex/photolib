# ADR-0053 — Change capture: tombstone keys and scopes, a purge horizon, and how the watermark lag is measured

* **Status**: Accepted — 2026-10-16 (roadmap M2-13): the owner confirmed all four decisions
  (photolib-design#361).
  `/metrics` exports the lag measured here instead of ADR-0046's age of the oldest open transaction, as the owner
  confirmed again on 2026-10-21
  (photolib-design#569);
  the metrics listener became [ADR-0046](0046-observability.md)'s `metrics.token` on the one port, still unset by
  default.
* **Requirements**: R-REL-1, NFR-PERF-5. **Design**:
  sync §2, §8,
  observability,
  ADR-0007.

## Context

ADR-0007 fixes the technique: a `txid xid8` set by trigger, tombstones on delete, reads below
`pg_snapshot_xmin(pg_current_snapshot())`, a watermark-lag metric with an alert at five minutes and a retention of 90
days. It leaves open what a tombstone's key and scope are for tables with composite keys, how a client learns that it
missed purged tombstones, and what "lag" measures. [ADR-0046](0046-observability.md) exports the lag at `/metrics`,
with an example alert at five minutes.

## Decision

* **Capture** (`server/migrations/0007_change_capture.sql`): every table a client replicates gets `txid xid8 NOT NULL`,
  an index `(scope, txid)` and one `sync_capture` trigger whose arguments are the scope column and the key columns;
  `photolib_db::sync::ENTITIES` mirrors them and a test fails on any table that is neither captured nor listed as
  server-only (`jobs`, `job_pauses`, `audit_events`, `uploads`, `api_keys`, `instance_settings`, the blob-store
  tables, the instance marker and the bookkeeping tables).
* **Tombstones** are `(entity, key jsonb, scope, txid, deleted_at)`, at most one per key: inserting a key again removes
  its tombstone, and an update that changes a key leaves one for the old key. The scope is the column the table's
  stream filters by: the user for account rows and memberships, the owner for libraries, albums and organisation, the
  library for assets, the asset for what hangs off an asset, the album for album items and links, the partner for
  partner shares, none for the shared vocabularies (`places`, `ml_labels`). The stream RPC (M2-14) may re-scope a
  table by replacing its trigger.
* **Order**: `(txid, key::text COLLATE "C")`, so ties inside one transaction page the same way under any database
  collation.
* **Retention**: the scheduler deletes tombstones older than 90 days once a day and raises `tombstone_horizon` to the
  newest purged txid. A cursor at or below it may have missed a deletion and must start over from a snapshot
  (`RESET_REQUIRED`, M2-14).
* **Lag** is how long changes that ended above the watermark have waited for it. The scheduler samples the watermark
  and `pg_snapshot_xmax` every 15 seconds; the lag runs from the first sample that saw a transaction end above the
  current watermark. It needs no access to other sessions and is exact to within one sample. A long transaction that
  delays nothing (no later transaction has ended) shows no lag.
* **Export and alert**: the scheduler's process exports its lag as `photolib_sync_watermark_lag_seconds` (`NaN` while
  the watermark cannot be read), on which ADR-0046's example alert fires past five minutes; the scheduler logs a
  warning then too, whether or not anything scrapes, and a notice when sync catches up.

## Consequences

* Readers cannot skip a row whatever order transactions commit in; a long transaction only delays them.
* Only a process with the scheduler role exports the lag, which trails the real wait by up to two samples (30 s).
* Every insert and update of a synced table runs a PL/pgSQL trigger: about 12 µs per row (100,000 tag inserts took
  2.4 s instead of 1.2 s), and `txid` updates are never HOT.
* The `users_audit` trigger of [ADR-0035](0035-accounts-and-first-run.md) compares rows without `txid`, which every
  write changes.
* A restore into another PostgreSQL cluster brings txids from that cluster's counter; the epoch change (M2-14) and the
  restore work (M2-31) must make clients start over and rebase or reset `txid`.
* The indexes are built in the upgrade transaction, which blocks writes; no release predates this migration, so the
  tables are empty wherever it runs.

## Options considered

* **The age of the oldest transaction holding an xid** (`pg_stat_activity.xact_start`): hides other roles' sessions
  without `pg_read_all_stats`, and counts a transaction that delays nothing.
* **Keys as text or one tombstone per delete**: text loses the column names composite keys need, and duplicate
  tombstones let a delete and a re-insert of one key in one transaction arrive in either order.
* **Time-based reset only** (device offline longer than the retention): needs every reader to be a device that
  records its last sync; the horizon is exact for any cursor.
