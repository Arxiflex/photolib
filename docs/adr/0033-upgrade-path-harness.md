# ADR-0033 — Upgrade-path harness: a fixture per schema version, recorded resolutions, a weekly large run

* **Status**: Accepted — 2026-10-16. The owner confirmed both choices M0-16 made: a fixture per migration on `main`
  and a weekly `upgrade-large`
  (photolib-design#318).
* **Requirements**: R-REL-2, NFR-REL-2. **Design**:
  migrations §2.5.

## Context

The design asks for a CI job that, for every released schema version, restores a fixture database, runs the current
migrations and checks invariants, on every pull request touching migrations and nightly with a large synthetic
database. ADR-0028 makes every migration on `main` released. CI runs neither on pull requests nor, but for the smoke
test (photolib-design#294), more than weekly (photolib-design#283), so the gate is the only check before a merge.

## Decision

* **A fixture per migration**, `server/migrations/fixtures/<migration>.sql`: SQL that fills a database built by the
  migrations up to it, with rows in every table, then a drift section (duplicate hashes, orphans, manual indexes,
  stray settings). It is written with the migration, released with it and, like it, never edited
  (`tools/migrations.sh`).
* **Recorded resolutions are the "before"**: `<migration>.resolved` holds what every album, asset and link URL and
  each user's share definitions resolved to when the fixture was made. After the upgrade they must resolve the same.
  The harness also rejects a new broken reference and any difference from a fresh install's schema.
* **In the gate on every pull request**, `cargo test` of `photolib-db`, clean, drifted and with a thousand synthlib
  assets; **weekly** (`upgrade-large`) with a million, not nightly.
* Decryptability, sync cursors and API contract tests join the harness with the code that defines them.

## Consequences

* A migration that changes a share, drops a reference or behaves differently on old data fails before it merges.
* Every migration costs a fixture; copying the previous one keeps that small.
* A slow migration is found within a week of its merge, not a night.
* The synthetic library loads through the baseline's columns; a migration that drops one must adapt the loader.

## Options considered

* **One fixture per tagged release**: there are no tags yet, and migrations released between tags would go untested.
* **`pg_dump` files as fixtures**: tied to the dumping client's version (`\restrict`, new `SET`s) and unreadable in
  review.
* **Resolving "before" with today's code**: impossible once the schema changes; the recording keeps the release's
  answer.
* **Nightly**: against photolib-design#283.
