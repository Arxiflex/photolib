# ADR-0266 — Backups, restore drills, manifests and PostgreSQL major upgrades

* **Status**: **Proposed — owner to confirm** (photolib-design#109).
* **Requirements**: R-REL-1, R-REL-2, NFR-PORT-1; features `OPS-03`, `OPS-06`, `LIB-17`. **Design**:
  reliability, migrations and operations §2.1, §6, §10, storage and libraries §3, §8,
  ADR-0022 point 1, [ADR-0028](0028-postgresql-migrations.md), [ADR-0041](0041-journaled-file-operations.md).

## Context

Until now only an upgrade dumped the database, the console listed the dumps of the data directory and nothing proved a
dump restores. Design 15 §6 asks for daily dumps kept 14 days on any named store, a daily restore drill whose result
the console shows, a restore from the console, manifests that let `recover --from-storage` rebuild a lost database
without a dump, and major upgrades of the bundled PostgreSQL as a product feature: Immich stayed on PostgreSQL 14 for
years because its users had to do them by hand. The compose bundle runs the official image, which since 18 keeps each
major's cluster in `/var/lib/postgresql/<major>/docker` of the same volume.

## Decision

1. **Scheduled backups.** The `backup` job, queued at `database.backup_cron` (`0 3 * * *`, UTC), runs `pg_dump
   --format=custom` into `work_dir` and puts the dump through the intent log as `backups/backup-<UTC time>.dump` in
   the store `placement.backups` names (`local`, the data directory, by default). It keeps `database.keep_backups`
   (14) scheduled dumps; older ones go by a delete without grace, done by the purge. Pre-upgrade dumps stay in
   `<data_dir>/backups` as before.
2. **Restore drill.** Each backup queues a `restore-drill` job: the newest dump of that store is restored into
   `<database>_drill` on the same PostgreSQL server, migrated to the running release and compared with the schema its
   migrations build, then dropped. It needs the `CREATEDB` privilege, which the bundle's role has. Every backup, drill
   and restore is a row of `backup_runs`; the console shows the newest drill and the newest that passed, `/metrics`
   their times, and `PhotolibRestoreDrillFailing` fires when none passed for 48 hours.
3. **Restore from the console.** `RestoreBackup`, from an administrator's session only, writes
   `<data_dir>/.photolib/restore.json` and stops photolibd; the next start (compose restarts it) restores that dump,
   from an object store through a checked copy, counts the restore into the epoch and migrates it to the release.
   Restoring under a running process would race the jobs' transactions and every cache. `photolibd restore` now
   commits only once `pg_restore` has read the whole dump.
4. **Manifests.** The daily `manifest` job writes `libraries/<id>/.photolib/manifests/<UTC time>.jsonl` for every
   standard managed library into its store, from one snapshot: a header (`manifest` 1, the schema version, the
   library), then one `{"table", "row"}` line per row of the owner, the library, its assets, their files under the
   library's root, the owner's tags, the assets' tags and favourites, and the owner's album folders, albums and their
   items, as PostgreSQL's JSON of them. Each library keeps three. Design 13 wants manifests in the records of
   `photolib.export.v1`, which do not exist yet: when they do, manifests become version 2 and recovery keeps reading
   version 1. Private libraries get none until their devices write encrypted ones.
5. **Recovery from storage.** `photolibd recover --from-storage <store>` takes the instance of the database, else of
   the data directory, else of the store's marker, so a bucket alone rebuilds a server; migrates the database; and
   inserts the rows of the newest manifest of every library in the store that are not there yet, with the columns the
   manifest has, so later columns take their defaults. A reference to a row that is not there becomes NULL, or skips
   its row where it cannot. Files the store lacks are marked `missing`; originals no manifest names are listed. It
   counts as a restore.
6. **PostgreSQL major upgrades.** photolibd copies the database when the one `database.url` names is empty, the data
   directory has an instance marker and `database.upgrade_from` holds that instance: `pg_dump` (its own, the new
   major's) of the old cluster, kept as `<data_dir>/backups/pre-pg<old>-pg<new>-<UTC time>.dump`, restored into the
   new one before the instance check. The old cluster is left as it was, the way back. A release that moves the
   bundle to a new major adds a service of the old image on the same volume and sets
   `PHOTOLIB_DATABASE__UPGRADE_FROM` to it ([releasing](../dev/releasing.md)); the gate runs the upgrade from the
   bundle's major minus one to it with PGDG's builds (`tools/postgres.sh`).

## Consequences

* ✅ A dump that would not restore is found the next morning, not on the day it is needed.
* ✅ A database lost without a dump comes back from its store, with albums, tags and descriptions.
* ✅ A major upgrade is `docker compose pull && docker compose up -d`, and a failure leaves the old cluster untouched.
* ⚠️ A drill needs room for a second copy of the database on its server for a few minutes a day.
* ⚠️ What changed after the newest manifest is lost to recovery, but for its originals, which it lists; ingesting
  them again is follow-up work, as are stacks, versions, faces and shares, which manifests do not hold yet.
* ⚠️ The major upgrade copies the whole database: minutes for a million assets, during which photolibd does not
  serve. Both clusters take disk space until the old one is removed.

## Options considered

* **`pg_upgrade --link`**: fastest, but needs both majors' programs in one container, which no official image has,
  and a failure midway can damage the old cluster.
* **Documented manual dump and restore**: the chore the design rules out.
* **A dump at every shutdown, restored by the new major's container** (Nextcloud AIO): a large database outlasts the
  stop timeout.
* **Restoring the newest scheduled dump into the new major**: loses up to a day.
* **Restoring in the running process**: races its jobs and caches; a restart is the one safe point.
