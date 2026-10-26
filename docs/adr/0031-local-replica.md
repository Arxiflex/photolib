# ADR-0031 — Local replica: schema conventions and the pre-migration backup

* **Status**: Accepted — 2026-10-16. The owner deferred this choice of M0-23 and asked for the best one after weighing
  the options
  (photolib-design#309).
  Weighed against the options below, the provisional decision stands, with two guarantees added: every table is
  classified when it is added, and a backup is written whole or not at all.
* **Requirements**: R-MODE-1, R-REL-2. **Design**:
  client app §2,
  domain model §11,
  migrations §3.

## Context

The design fixes the engine (drift on SQLite3MultipleCiphers on all six targets), the single writer and a backup of
local-only data before every client migration. It leaves open how rows are typed, which data counts as local-only,
and where the backup lives so that it works in browsers and stays encrypted once M0-41 keys the engine (ADR-0015).

## Decision

* **Schema conventions** (`app/packages/photolib_data/lib/src/replica.drift`): `STRICT` tables; IDs are UUIDv7 as
  16-byte blobs, times UTC milliseconds; enumerations are text without `CHECK` constraints, so a value added by a newer
  server never fails a sync batch. Every synced row carries `txid`, the server change that last wrote it, `NULL` while
  the row exists only on this device. Per-field HLCs arrive with the sync engine (M2-15) as a migration.
* **Local-only data** is what neither the server nor a cheap rescan gives back: the device tables (`local_asset`,
  `backup_state`, `outbox`, `ext_journal_cursor`: hashes, upload state, selections, unsent changes) and the synced rows
  whose `txid` is `NULL`, such as a standalone library. Edits of confirmed rows survive as their outbox mutations;
  device settings live in `accounts.db`, outside the replica. Sync cursors are rebuilt: a rebuilt replica syncs from
  scratch. Every table is classified when it is added, as synced (it has `txid`), device (`deviceTables`) or rebuilt
  (`sync_cursor`), and `test/migration_test.dart` fails on a table that is not exactly one of them.
* **Backup**: before migrating, that data is copied into a SQLite database next to the replica,
  `replica.before-v<N>-<UTC time>`, opened through the same engine, so it works in browsers (OPFS or IndexedDB, tested
  in Chrome and Firefox) and is encrypted like the replica. It is written in one transaction, so a backup that exists
  is complete; when it cannot be written, nothing is migrated. The migration runs in one transaction. When it fails,
  the replica is dropped, recreated at the current schema and the local-only rows are restored (the columns both
  schemas share), again in one transaction; when that fails too, the replica stays untouched at its old version and
  opening it reports the error. A replica newer than the app is refused, never migrated down. Backups are kept.
* **SQLite3MultipleCiphers binaries** are not committed: the `sqlite3` package's build hook downloads its prebuilt
  native libraries and checks their hashes, and `tools/data/web.sh` does the same for `sqlite3mc.wasm`.

## Consequences

* A failed migration never loses what only the device has, and never leaves a half-migrated replica.
* Migrations must keep the local-only tables restorable by column name; a new `NOT NULL` column needs a default.
* Backups accumulate, one per migration; pruning them is follow-up work.
* A table's local-only rows pass through memory at once; the copy must be paged before device indexes or
  standalone libraries of 100,000 assets ship (follow-up).
* Builds need network access once per `sqlite3` release, like any pub package.

## Options considered

* **Only the device tables**: loses standalone libraries and local albums the server has not confirmed.
* **Every table not known to be rebuildable**: a forgotten cache such as the timeline would be copied whole on every
  migration. Classifying every table in a test catches that mistake and the opposite one.
* **No backup, relying on the migration's transaction**: rolls back a migration that throws, not one that commits
  wrong data.
* **Local-only data in a database of its own**: the outbox and the rows it changes must commit together.
* **Rebuilding instead of migrating**: every schema change would sync a million assets again.
* **Migrating a copy and swapping it in**: copies the whole database every time, and browsers cannot rename one.
* **A JSON file**: plaintext at rest, against ADR-0015, and no file system in browsers.
* **`VACUUM INTO` a copy of the whole database**: hundreds of megabytes at a million assets, for data the server has.
* **Backup tables inside the replica**: lost with the file when that is what broke.
* **Deleting the file to rebuild it**: not atomic; a crash between the delete and the restore loses the data.
