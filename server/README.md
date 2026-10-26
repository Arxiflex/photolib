# server/

The Rust workspace behind `photolibd`: one binary with roles (`api`, `scheduler`, `worker:<class>`, `ml` and the default
`all`), backed by PostgreSQL only, plus the `photolib` CLI (ADR-0065; `tests/upload.rs` runs it against photolibd).

## Architecture

* Crates under `crates/`: `photolib-kernel` (shared with the clients), `photolib-proto` (generated), `photolib-db`
  (sqlx, schema and data migrations), `photolib-authz` (the single authorization path), `photolib-jobs`,
  `photolib-storage` (journaled blob stores), `photolib-media` (sandboxed worker protocol), `photolib-ml`,
  `photolib-sync`, `photolib-import`, `photolib-export`, `photolib-server` (axum app, roles) and `photolib-cli`.
* Every versioned artefact (database, storage layout, crypto, wire schemas, sync) gets a migration and an upgrade test.
* Untrusted media is never parsed in the API process; workers run sandboxed without network access.

## Contents

* `Cargo.toml`: the crates below; `rust-version` 1.92 (`ort`), edition 2024, AGPL-3.0-only, no `unsafe`, Linux only.
* `migrations/`: SQL, squawk's `.squawk.toml` and the upgrade fixtures of `fixtures/` ([rules, upgrade-path harness and
  PostgreSQL 16+ test tools](../docs/dev/migrations.md)); `cd server && cargo test` runs all tests.
* `crates/photolib-db`: `migrate` (embeds `migrations/`, one transaction under an advisory lock, refuses downgrades and
  edits, checks invariants), `dump` (pre-upgrade dump, retention, restore), `data` (data migrations, `Quarantine`),
  `lint`, `doctor` (schema drift), `testpg` (test clusters), `cluster` (`database.cluster`), `sync` (ADR-0053).
* `crates/photolib-authz` ([ADR-0038](../docs/adr/0038-authorization-policy.md)): `can` and `scope`; `tests/matrix.rs`.
* `crates/photolib-jobs` ([ADR-0034](../docs/adr/0034-job-queue.md)): the queue, `Worker`, `scheduler`, `reconcile`.
* `crates/photolib-storage`: blob stores (`fs`, `s3`), markers and the intent log ([ADR-0041](../docs/adr/0041-journaled-file-operations.md)).
* `crates/photolib-models`: `registry.json`, its licence `gate` and `Store` for `photolibd models` and `/models` ([ADR-0064](../docs/adr/0064-model-registry-and-licence-gate.md)).
* `crates/photolib-ml` ([ADR-0245](../docs/adr/0245-server-ml-role.md)): `ort`, the golden `self_test`, the `Pool`.
* `crates/photolib-media` is the media sandbox ([ADR-0024](../docs/adr/0024-media-sandbox.md)): `child` (what the hidden
  `photolibd media-child` runs: rlimits, Landlock, seccomp, then the tool, the header `probe` or `render`: libvips, and
  `raster` for BMP and PSD), `Worker` (starts, kills, restarts and recycles children) and `ExifTool`.
* `crates/photolib-proto` wraps what `tools/codegen.sh` generates from `proto/`: buffa messages (binary and proto3
  JSON) in `src/gen/buffa`, Connect service traits in `src/gen/connect` (clients behind feature `client`).
* `crates/photolib-conformance`: photolibd's Connect stack under the official suite's subset (`connect-conformance.yaml`).
* `crates/photolib-server` builds `photolibd`; its modules sit behind ports or pure functions, so tests need no server:
  * `config` (YAML plus `PHOTOLIB_*`, validated), `role`, `secret` (never prints), `proxy` (trusted proxies, HTTPS sign-ins).
  * `instance` (the marker check, the epoch) and `mounts` (the NFS/SMB/FUSE refusal); `prepare` in `run` runs them.
  * `http` (health, readiness, request ids, graceful serving), `metrics` (`/metrics`), `logging` (stderr, OTLP, tail).
  * `rpc`, the `api` role's Connect API: `authz` (`ROUTES`, each procedure's rule), `events`, `GetServerInfo` (versions,
    `CAPABILITIES`, epoch), `errors` (`ApiError`; no prose, no gRPC), `deprecation`, `users`, `auth`, `keys`, `admin`, `sync`.
  * `accounts`: users (ADR-0035); `auth`: OPAQUE, key file, lockout (ADR-0052); `keys` (ADR-0055); `oidc` (ADR-0087);
    `webauthn`, `totp`, `relay` (`/passkey`; `/`, setup links, ADR-0243): 2nd factors (ADR-0088, `tests/passkeys.rs`).
  * `jobs` (the `JobQueue` port running the roles, `PgJobs`, the drain), `db` (the `Database` port), `pg` (its adapter),
    `run` (start, stop), `storage` (stores, recovery), `sync` (watermark lag, purges), `testing` (fakes), `ml`.
  * `upgrade` (maintenance, migrations, `migrate`, `restore`, PG majors), `doctor`, `backup`, `manifest`, `policy` (ADR-0240).
  * `uploads` (`/upload`, ADR-0061), `dedup` (ADR-0092), `ingest` (`worker:cpu`, assets as clients read them, ADR-0066),
    `library` (ADR-0089), `external` (ADR-0093), `video` (ADR-0085), `hls` (ADR-0246), `scrub`, `render`, `media` ([ADR-0084](../docs/adr/0084-image-renditions.md)).
* `crates/photolib-server/tests/photolibd.rs` runs the binary: exit codes, messages, SIGTERM, first sign-in, refused
  downgrades. `tests/contract.rs`, `uploads.rs`, `serving.rs` and `sync.rs` (100k-asset budget) pin the wire; `lints.rs`
  proves `clippy.toml` rejects Connect error prose; `video.rs` renders every corpus video (`tools/video/ffmpeg.sh`).
* `tests/media.rs` runs hostile stand-ins in the sandbox (reads, sockets, signals, crashes, hangs, floods, limits; needs
  Landlock, Linux 5.13), `tests/renditions.rs` every corpus image; ExifTool with `TEST_EXIFTOOL=<path> cargo test -- --ignored`.

The administrator-facing description is [Configuring photolibd](../docs/admin/configuration.md) and [Upgrades and
maintenance](../docs/admin/upgrades.md); the choices are [ADR-0021](../docs/adr/0021-photolibd-startup-contract.md),
[ADR-0028](../docs/adr/0028-postgresql-migrations.md) and, for the API, [ADR-0027](../docs/adr/0027-connect-rpc.md).

## Design

* Architecture
* Reliability, migrations and operations
