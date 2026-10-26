# Database migrations

Schema changes are forward-only SQL files in `server/migrations/`, named `NNNN_description.sql`. `photolibd` embeds
them and, at startup, applies the missing ones in one transaction; administrators see [Upgrades and maintenance
mode](../admin/upgrades.md). Rewrites of existing rows are data migrations in Rust. The choices are
[ADR-0028](../adr/0028-postgresql-migrations.md).

## Rules

* **A migration on `main` is released.** Never edit, rename or delete it; fix it with a new migration. The gate
  (`tools/migrations.sh`) compares with `origin/main`, and `photolibd` refuses a database whose applied migration
  differs from the file.
* **Numbers.** Take the next free number. After rebasing onto `main`, run `bash tools/migrations.sh --renumber`: it
  moves your new migrations above main's newest. The gate rejects a number at or below it. Release branches only get
  migrations identical to main's: cherry-pick, never write one there.
* **One transaction.** A migration has no `BEGIN`, `COMMIT` or `CONCURRENTLY`, and changes no database-, role- or
  session-level setting (`ALTER DATABASE`, `ALTER ROLE`, `ALTER SYSTEM`, `SET`; use `SET LOCAL`). The lint in
  `cargo test` rejects them, and so does a check at upgrade time.
* **Expand, migrate, contract.** First add tables and columns that are nullable or have a default; backfill with a data
  migration; switch the code to the new structure; drop the old one in a later release. squawk rejects dropping or
  renaming columns, a NOT NULL column without a default and blocking index builds on existing tables.
* **Rows are never deleted by a migration**: the upgrade fails if a table loses rows other than into quarantine.
* **New tables are synced or server-only.** A table clients replicate gets the `txid` column, the `(scope, txid)`
  index and the `sync_capture` trigger of `0007_change_capture.sql`, and an entry in `photolib_db::sync::ENTITIES`;
  any other table goes on the server-only list in that module's test, which fails on a table in neither.
* **New constraints are pre-scanned.** A UNIQUE, foreign-key or NOT NULL constraint on a table that an earlier
  migration created needs a `Quarantine` data migration in `data::registry()` that selects the violating rows, named
  in the migration as `-- photolib:prescan <id>`. The upgrade runs it to the end right before the migration, in the
  same transaction, and the rows land in `quarantined_rows` as JSON.

## Data migrations

Implement `photolib_db::data::DataMigration`: an `id`, a `description`, an idempotent `batch` that continues after a
cursor, and `remaining`, the count of rows still to do, which also verifies the result. Add it to `data::registry()`.
The scheduler runs it in the background; each batch commits with its cursor in `data_migrations`, and `/readyz` shows
the progress under `upgrading`.

## Tests

Database tests run on a throwaway PostgreSQL cluster that the test process starts and stops
(`photolib_db::testpg::database()` gives each test its own database). They need the PostgreSQL 16+ server and client
programs on `PATH`, in `/usr/lib/postgresql/<major>/bin`, or in the directory `TEST_PG_BIN` names. A migration test
builds its own migration list with `Migration::new` and runs `upgrade`.

## Upgrade-path harness

`cargo test -p photolib-db --test upgrade_path` upgrades a fixture database of every schema version to the newest
([ADR-0033](../adr/0033-upgrade-path-harness.md)). `server/migrations/fixtures/<migration>.sql` fills a database at
that version with rows in every table; after its `-- photolib:drift` line come duplicate hashes, orphans, manual
indexes and stray settings. Each fixture runs clean, drifted and with a synthetic library of `PHOTOLIB_UPGRADE_ASSETS`
assets (1000; a million in the weekly workflow). After photolibd's upgrade and data migrations, album, asset and link
URLs and share definitions must resolve as `<migration>.resolved` recorded, and no broken reference or difference from
a fresh install's schema may appear.

A migration comes with its fixture: copy the newest fixture to `fixtures/<migration>.sql`, add rows for what the
migration adds, run `PHOTOLIB_RECORD_FIXTURES=1 cargo test -p photolib-db --test upgrade_path` in `server/` and review
the `.resolved` it writes. Fixtures on `main` are released like migrations: never edit them.
