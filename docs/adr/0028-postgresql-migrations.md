# ADR-0028 — PostgreSQL migrations: one transaction per upgrade, released means merged, restore from the CLI

* **Status**: Accepted — 2026-10-15. The owner confirmed the four choices the migration framework (M0-15) made:
  released means merged, a CLI restore, 3 kept dumps and database tests that need PostgreSQL
  (photolib-design#299).
* **Requirements**: R-REL-1, R-REL-2, NFR-REL-2. **Design**: 15, 04.

## Context

Design document 15 fixes the rules: forward-only migrations with checksums, one migrator under an advisory lock, a
refused downgrade, a pre-upgrade dump, all migrations of an upgrade in one transaction, maintenance mode with a way
back, data migrations for row rewrites. It leaves open the tool, where the bookkeeping lives, what "released" means
before there are releases, how long dumps are kept, and how the way back is offered before an admin UI exists.

## Decision

* **Our own migrator** in `photolib-db`, not `sqlx::migrate!`: sqlx commits each migration separately, and the
  design needs every migration of an upgrade, the pre-scans and the invariant checks in one transaction. Migrations
  are `server/migrations/NNNN_description.sql`, embedded at build time, recorded with their SHA-256 in
  `schema_migrations`. `data_migrations`, `quarantined_rows` and `schema_migrations` are created by the framework
  itself, so it needs nothing from a migration to start.
* **Released means merged to `main`.** The gate compares `server/migrations/` with `origin/main`: a merged migration
  is never edited, renamed or deleted, a new one is numbered above main's newest, and release branches carry only
  migrations identical to main's. `tools/migrations.sh --renumber` assigns numbers after a rebase, which is what the
  merge queue (or the driver's rebase) runs.
* **Invariants** checked before the commit: no table loses rows except into quarantine, and no database- or
  role-level setting changes. A new UNIQUE, foreign-key or NOT NULL constraint on an existing table names a
  quarantining data migration (`-- photolib:prescan <id>`) that runs to the end right before it.
* **The pre-upgrade dump** is `pg_dump --format=custom` into `<data_dir>/backups`; the newest 3 are kept
  (`database.keep_dumps`). A failing dump stops the upgrade. The client programs come from `PATH` or
  `database.bin_dir`, and the password reaches them through `PGPASSWORD`.
* **Maintenance mode and the way back** are a readiness check that names the command `photolibd restore <dump>`. The
  restore drops the schema's objects and loads the dump in one `psql` transaction. It is a CLI command, not an HTTP
  endpoint, because nothing authenticates an administrator yet; the one-click button belongs to the admin UI.
* **squawk** (pinned, fetched from npm like buf) lints migrations in the gate, without the rules that fight this
  design (64-bit integers everywhere; lock and statement timeouts, since an upgrade runs before anything is served).
* **Database tests** run on a throwaway PostgreSQL cluster that the test process starts (`photolib_db::testpg`), so
  `cargo test` needs the PostgreSQL 16+ programs and fails without them instead of skipping.

## Consequences

* ✅ One failed upgrade leaves the schema exactly as it was, and the server says how to go back.
* ✅ The same rules hold in CI (lint, git comparison) and at startup (checksums, invariants).
* ⚠️ A large upgrade holds its locks until it commits, and the row-count invariant counts every table; both are
  acceptable while upgrades run before serving, and need revisiting for rolling multi-node upgrades.
* ⚠️ Indexes on large existing tables need a post-migration job (`CREATE INDEX CONCURRENTLY`), which arrives with
  the job system (M0-17).
* ⚠️ `cargo test` and the dev container need the PostgreSQL server programs.

## Options considered

* **sqlx's migrator, refinery, Diesel migrations**: per-migration transactions and no hook for pre-scans or
  invariants.
* **Released means tagged**: a migration merged after the last tag could still be edited on `main` while nightly
  builds have applied it.
* **An HTTP restore endpoint**: unauthenticated until accounts exist, and a restore is destructive.
* **Keeping every dump**: a 1M-asset library dumps to gigabytes per upgrade; scheduled backups (14 days) are a
  separate feature.
