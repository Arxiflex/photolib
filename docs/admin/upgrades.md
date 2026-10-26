# Upgrades and maintenance mode

`photolibd` needs PostgreSQL 16 or newer (18 is recommended). For the dump before an upgrade and for restores it also
needs the PostgreSQL client programs `pg_dump`, `pg_restore` and `psql`, of the server's major version or newer, on
`PATH` or in `database.bin_dir`. The choices behind this page are [ADR-0028](../adr/0028-postgresql-migrations.md).

## Release channels

The [compose bundle](install.md) runs the image `PHOTOLIB_VERSION` in `.env` names: `stable`, the releases; `beta`,
each release candidate, at least a week before it becomes stable; `nightly`, every merge to `main`, for testing; or a
version such as `1.4.2`, which never moves. The NAS entries, the Helm chart and the deb each install one version. To
try a release candidate, set `PHOTOLIB_VERSION=beta` and upgrade as [installing](install.md#upgrade) shows. No release
starts on a database a newer one migrated, so going back to `stable` before the candidate is released means
[restoring the pre-upgrade dump](#restoring-a-dump) and losing what changed since: try candidates on a copy when the
library matters.

## At startup

After the [instance check](configuration.md#instance-marker) and before it listens, `photolibd` compares the database
schema with the migrations it was built with. One process migrates at a time; the others wait for it.

| The database is | `photolibd` |
|---|---|
| current | starts |
| older | dumps it, applies every missing migration in one transaction, checks that no table lost rows and that no database or role setting changed, and starts |
| newer: `photolibd` was downgraded | refuses to start, and says to start the newer release or restore the dump taken before the upgrade |
| migrated with an edited or unknown migration | refuses to start |
| on PostgreSQL 15 or older | refuses to start |

A refusal exits with code 1 and leaves the database untouched.

`photolibd migrate` does the same and exits, 0 once the schema is current and 1 with the reason when the upgrade is
refused or fails; it never listens. Kubernetes runs it as the Helm chart's pre-upgrade job, before new pods start.

## The dump before an upgrade

Before it changes a database that already has a schema, `photolibd` writes
`<data_dir>/backups/pre-<from>-<to>-<UTC time>.dump` (`pg_dump` custom format) and keeps the newest `keep_dumps`
(default 3). Dumps hold every row, so the directory is `0700` and each dump `0600`. If the dump fails, nothing is
changed and startup stops. `database.pre_upgrade_dump: false` skips it.

## Maintenance mode

If a migration fails, the whole upgrade is rolled back and the schema stays as it was. `photolibd` keeps running with
only its listener: `/healthz` answers `200`, and `/readyz` answers `503` with a `schema` check that says what failed
and how to go back, for example:

```text
maintenance: the upgrade failed and was rolled back, so the schema is unchanged: ... Fix the cause and restart
photolibd; to go back to the previous release, stop photolibd, run
`photolibd restore /data/backups/pre-0003-0004-20261015T201042Z.dump` and start that release
```

## Restoring a dump

`photolibd --config photolib.yaml restore [DUMP]` replaces the schema and the data with a dump, by default the newest
pre-upgrade dump in `<data_dir>/backups`, in one transaction: if anything fails, nothing changes. Stop `photolibd`
first, and afterwards start the release that wrote the dump. A restore counts into the instance's epoch, in
`<data_dir>/.photolib/instance.json`: devices then sync from scratch and check their backups again. The admin console
restores the [scheduled backups](backups.md) too.

## PostgreSQL major upgrades

A release that moves the [compose bundle](install.md) to a new PostgreSQL major keeps the previous major's cluster
beside the new, empty one, and sets `database.upgrade_from` to it. At its first start photolibd copies the database
over: when the database `database.url` names is empty, the data directory has an instance marker and
`database.upgrade_from` holds that instance, it dumps the old cluster to
`<data_dir>/backups/pre-pg<old>-pg<new>-<UTC time>.dump` and restores that into the new one, then starts as usual.
`docker compose pull && docker compose up -d` is the whole upgrade. The old cluster is left as it was: to go back,
start the previous release. Once the new one runs, delete `postgres/<old major>`. An unreachable `upgrade_from`, or
one that holds another instance, stops photolibd with a message saying so; a first start ignores it. Running
PostgreSQL yourself, set `database.upgrade_from` the same way, or upgrade the cluster as you always do
([ADR-0266](../adr/0266-backups-restore-drills-manifests-postgresql-upgrades.md)).

## Checking the schema

`photolibd --config photolib.yaml doctor schema` compares the database with the schema its migrations build. It prints
`the schema has no drift` and exits with 0, or lists `missing: ...` and `unexpected: ...` lines (tables, columns,
constraints, indexes) and exits with 1. A change made by hand is drift.

## Data migrations

Rewrites of existing rows, such as backfills, run in the background in the process with the `scheduler` role, in
batches that survive restarts. While any is unfinished, `/readyz` lists it under `upgrading` with its state and
progress; readiness does not depend on it.
