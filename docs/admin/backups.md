# Backups and recovery

photolibd backs up its database every day, checks every backup by restoring it, restores one from the admin console,
and writes manifests from which `photolibd recover --from-storage` rebuilds a database lost without a backup. Your
originals are yours to [back up](#backing-up-the-originals). The choices are
[ADR-0266](../adr/0266-backups-restore-drills-manifests-postgresql-upgrades.md).

## Scheduled backups

At `database.backup_cron` (03:00 UTC) a `backup` job dumps the database (`pg_dump` custom format) to
`backups/backup-<UTC time>.dump` in the store `placement.backups` names: `<data_dir>/backups`, `0700`, by default, or
an object store. The newest `database.keep_backups` (14) stay. A dump holds every row, password records included:
keep it as private as the database. *Back up now* in the console's overview queues one at once.

## Restore drills

Each backup is followed by a drill: the newest dump of that store is restored into a scratch database,
`<database>_drill` on the same PostgreSQL server, migrated to the running release, compared with the schema the release
builds, then dropped. The role needs `CREATEDB` (`ALTER ROLE photolib CREATEDB`; the compose bundle's role has it) and
the server room for a second copy for a few minutes. The console's overview shows the last verified restore and why
the last drill failed, if it did; `photolib_restore_drill_last_success_timestamp_seconds` and the
`PhotolibRestoreDrillFailing` alert ([monitoring](monitoring.md)) say the same.

## Restoring a backup

*Restore* beside a backup in the console's overview, from an administrator's session, stops photolibd. At its next
start, which the compose bundle's restart policy makes at once (start it yourself otherwise), photolibd replaces the
whole database with the backup, migrates it to the running release and carries on. What changed since the backup is
lost, and every device syncs from scratch. On a deployment of several processes, stop the others first. The overview
says when a restore failed; the database is then unchanged. `photolibd restore <dump>` does the same by hand
([upgrades](upgrades.md#restoring-a-dump)).

## Manifests and recovery from storage

Every day the `manifest` job writes `.photolib/manifests/<UTC time>.jsonl` in the root of every managed library (not
private ones yet), in its store: the account, the library, its photos and videos with their titles, descriptions,
ratings and files, the account's tags, favourites, album folders and albums with their items and text blocks, as JSON
Lines. The newest three stay.

When the database is lost and no backup is left, point photolibd at an empty database and run

```sh
photolibd --config photolib.yaml recover --from-storage local   # or the name of an object store
```

It takes the instance from the data directory or, on a new server, from the store's marker; migrates the database;
and rebuilds every library of that store from its newest manifest, printing what it inserted of each table, the files
the store lacks (marked missing) and the originals no manifest names, which arrived after it. Rows that exist stay, so
it can run again. Then start photolibd: it renders every thumbnail again. Accounts come back without passwords:
`photolibd admin password-setup <handle>` makes a link for each. Devices sync from scratch.

## Backing up the originals

Keep three copies of the originals, on two kinds of storage, one of them elsewhere (3-2-1), each with history, so that
a deletion or ransomware does not reach every copy. Back up the data directory with restic or borg after the 03:00
UTC dump, which it then holds too, skipping `tmp/`, and never `postgres/`, whose files a running cluster keeps
changing:

```sh
restic -r sftp:backup.example.org:/photolib init                       # once
restic -r sftp:backup.example.org:/photolib backup data --exclude data/tmp
restic -r sftp:backup.example.org:/photolib forget --keep-daily 7 --keep-weekly 8 --keep-monthly 24 --prune
```

Copy a bucket to another provider with `rclone copy --metadata b2:photolib offsite:photolib-copy`, which never
deletes on the copy; give the copy's bucket versioning or object lock, which Photolib's own bucket does not need
([a bucket is not a backup](storage.md#a-bucket-is-not-a-backup)). Private libraries are ciphertext, safe in any
cloud. Restore a file now and then: a backup nobody restored is a hope.

## The admin-succession kit

The kit lets someone else run or rebuild the server when you cannot. Make it when you install, keep it sealed, away
from the backups, and update it when one of its parts changes:

1. **A second administrator.** Make a second person an administrator (*Accounts* › *Edit* in the console, which asks
   for one while the server has only one), and walk them through this kit once.
2. **Sealed secrets**, printed or on an encrypted stick in a sealed envelope, or in a password manager's emergency
   access: `keys/opaque.key` (`base64 keys/opaque.key` prints it), without which no password signs in; `.env` and
   `compose.override.yaml`, which hold the database password and the stores' keys; the restic or borg repository's
   password; and how to log in to the host, the DNS record and the storage provider. Never keep the OPAQUE key with
   the database dumps: with both, someone could test password guesses offline.
3. **Where the backups are**: the host and the path of the data directory, the backup repository, the bucket and its
   copy, with their providers and who pays them.
4. **The recovery runbook**: [replace a failed node](runbooks.md#replace-a-failed-node), or
   [recover from storage](runbooks.md#recover-from-storage) when no dump is left.
