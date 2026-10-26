# ADR-0234 — Integrity scrubbing and the backup watchdog

* **Status**: Accepted — 2026-10-21 (roadmap M2-33). The owner kept all three decisions as made: Prometheus alerts
  until M3-11 sends its own, silence as no `ReportBackup` for `backup_silent_hours`, the pace and the silence in the
  console and the re-hash budget per store in the YAML
  (photolib-design#604).
* **Requirements**: NFR-REL-1; features `LIB-15`, `ING-26`, `OPS-10`. **Design**:
  07 §8,
  ADR-0022
  point 6, 15 §10.

## Context

Every original has a BLAKE3 hash and size from ingest, and reads that do not match become integrity findings, but
nothing looked at what nobody reads: bit-rot on a disk, an object deleted, truncated or replaced in a bucket, an object
no file names. The design asks for a continuous, rate-limited scrub (a store every 90 days by default), on object
stores HEADs and a prefix listing, a full re-hash only opt-in with a monthly egress budget, and findings in the admin
console and metrics. It leaves open how the pace, the budget and orphans work, and how a server learns that a device's
backup has gone silent: devices reported nothing, and the server has no notifications until M3-11.

## Decision

1. **A `scrub` job every 15 minutes** (the scheduler, `worker:io`) scrubs each online store, holding a session lock per
   store so that two runs never overlap. A run checks the store's files in id order from where the last stopped: the
   bytes of a cycle times the time since the last run (at most a day) over `scrub_days`, an instance setting from 1 to
   3650 (90 by default), and at least one file. The files are those of `asset_files` no job can make again (no
   `render_spec`), each object once (no `byte_offset`).
2. **Checks.** Each object is HEADed: gone is `missing`, another size `size`, another stored hash `hash`. On a
   filesystem the routine cycle also reads it: other bytes are `content`. An object store is only HEADed unless
   `stores.<name>.rehash_gib_per_month` turns on the full re-hash, a second cursor that downloads each original and
   stops when the next would pass the calendar month's (UTC) budget, counted in the database. Another error twice is
   `content` (unreadable); a timeout or an offline store ends the run, which the next repeats.
3. **Orphans.** A routine cycle ends by listing `libraries/` of the store: an object outside `.photolib/` that no file,
   pending upload or open intent names, and that a HEAD still finds, is an `orphan`. Nothing is ever deleted or marked.
4. **Findings** are rows of `integrity_findings` with their kind, recorded once while open and resolved when a later
   check finds the object as recorded (`content` only by a read). The admin console's overview lists the open ones,
   newest first, with the asset, its file name and owner and a repair hint: put the file back from a backup or from a
   device that still has it; check an orphan, then delete or keep it. `/metrics` exports
   `photolib_integrity_findings{kind}` and `photolib_scrub_cycle_end_timestamp_seconds{store}`; the alert
   `PhotolibIntegrityFindings` fires on any open finding.
5. **Backup watchdog.** A device reports its backup with `AuthService.ReportBackup(pending_count)`, which the app's
   backup engine (M2-18) calls after each pass; `device_backups` keeps its last report. A device that has not reported
   for `backup_silent_hours`, an instance setting from 1 to 8760 (48 by default), is silent. The overview lists every
   reporting device, the longest silent first, with its last seen time and pending count; `/metrics` exports
   `photolib_device_backup_silent`, `_pending` and `photolib_device_last_seen_timestamp_seconds` per device, and the
   alert `PhotolibDeviceBackupSilent` is the notification, through the administrator's Alertmanager, until the server
   sends its own (M3-11).

## Consequences

* ✅ Bit-rot, lost, truncated, replaced and stray objects are found within one cycle without a download on object
  stores; a re-hash's egress stays within its budget even across restarts.
* ✅ No per-file write: progress is two cursors per store, so the synced `asset_files` rows never change.
* ⚠️ Repair is by hand: an upload of the same bytes links to the damaged file (dedup), so "a device still has it" is a
  hint, not an action yet. External libraries, which their owners may change, are not scrubbed. (Both changed with
  [ADR-0252](0252-repair-from-devices-and-external-scrubs.md).)
* ⚠️ Device names and account handles become label values of `/metrics`, which only the metrics token's bearer reads.
* ⚠️ A device that never reports (the CLI, an app before M2-18) is never silent.
* For M2-18 and M2-24 (the owner, 2026-10-21): the per-item *Not backed up* badge of ADR-0200 and the server's silence
  derive from the same data `ReportBackup` reports, the device's per-item backup state, never two computations.

## Options considered

* **A `verified_at` column per file**: a write per file per cycle, and each would sync to every device.
* **A long job throttled to the pace**: holds a worker slot for days; paced runs every 15 minutes need none.
* **Marking findings in `asset_files.state`**: dedup and serving would then skip the file and a re-upload would make a
  second asset instead of a repair.
* **The silence threshold in `alerts.yml` only**: the console and the alert would disagree; the server decides and
  exports the result.
* **Server e-mail or push now**: belongs to the notification work (M3-11), which can subscribe to the same state.
