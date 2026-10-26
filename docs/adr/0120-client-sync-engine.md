# ADR-0120 — Client sync engine: reachability garbage collection, drop-and-refetch resets, epochs on cursors

* **Status**: Accepted — 2026-10-20 (roadmap M2-15). The owner kept drop, then refetch after a reset or a restore,
  as design 05 §3 and §8 say: the brief gap after a restore is rare and honest
  (photolib-design#460).
* **Requirements**: R-MODE-1, R-MODE-2. **Design**:
  sync §3, §4, §8,
  client app §1.5, §2,
  [ADR-0091](0091-sync-rpc.md).

## Context

[ADR-0091](0091-sync-rpc.md) streams rows by table and column name, per stream with an opaque cursor. Design 05 asks
the device to apply each batch in one transaction, open streams as memberships and shares appear (backfills), collect
what no visibility path reaches, and, after a restore, re-sync and re-verify its backups. It leaves open how the replica
knows what a stream delivered, what a reset drops, where the epoch is kept and what "upload again" means before the
backup pipeline (M2-18) exists. Design 10 §1.5 puts sync in the data isolate, whose garbage collections pause the UI's
isolate too: they share an isolate group.

## Decision

* **Engine**: `SyncEngine` in `photolib_data`, run by `syncReplica` in the data isolate on its own connection, one run
  at a time, with a server that has `sync.stream.v1`; it tells the replica's other clients what it wrote. Browsers
  have no data worker yet, so `syncReplica` refuses there.
* **Streams**: `account`, `libraries`, `albums`, `tags`, `people`, then `assets/{library}` and `faces/{library}` per
  library, `album_items/{album}` per album membership (`album_member`, schema 7) and `partner/{owner}` per partner
  share (`partner_share`). A run calls until no stream it follows is without a cursor (at most ten calls).
* **Apply**: each batch in one transaction with its cursor and the server's epoch (`sync_cursor.epoch`); rows map by
  name onto the replica's tables, take its column types (uuids to 16 bytes, arrays comma-separated, a NULL its NOT NULL
  column's zero value), and unknown tables and columns are ignored. Batches are read from their bytes, never built as
  messages, and applied without crossing drift's isolate channel: a batch of a thousand assets is some 60,000 values,
  which every garbage collection of the app copies while they are alive.
* **Compression**: `Server.sync` accepts gzip, which dart:io decodes natively and browsers through
  `DecompressionStream`; not zstd, which dart:io cannot decode without a new dependency. A message may hold, and a
  compressed one inflate to, 64 MiB; a longer one is refused before its bytes are kept.
* **Garbage collection by reachability**, not by recording which stream sent each row: an asset stays while its library
  is the account's, a shared album shows it or a partner's share does, as photolibd's does (ADR-0155): in a library of
  the partner's own, taken within its window or, private, shown whole. The replica keeps the libraries a partner's
  stream sends assets of, whole those it sends undated ones of, as private libraries have no dates the server can read
  (`partner_library`, schema 11), which a changed share forgets as it starts the stream again. Deleting an asset takes
  its files, versions and faces (trigger `asset_deleted`). A stream whose library, membership or share is gone closes,
  its cursor dropped. Losing a membership deletes the shared library or album, as the stream of libraries or albums
  sends no deletion of what the account no longer sees.
* **Resets, refusals and backfills drop, then fetch again**: `RESET_REQUIRED`, `FORBIDDEN` and a changed membership or
  share delete what the stream delivered and its cursor; reset and backfilled streams sync again from scratch in the
  same run, refused ones not until the next.
* **Epoch change**: cursors of another epoch mean a restore. In one transaction the engine deletes every synced row
  and cursor, retries the outbox now and marks every `backed_up` and `linked` item `reason = 'reverify'`; then
  `CheckHashes` re-verifies them a thousand at a time. What the server still holds keeps its state and links to the
  asset it names; the rest becomes `selected` with `reason = 'server_restored'`, which the backup pipeline uploads.
  The engine reads the epoch before each call and after the last, the tenth included, and at a call's first reset
  before it drops anything: a restore during a run resets every stream, and is found in that run.
* **Endpoint pin**: `Server` compares the instance id before the epoch's restore count, so a restored server is still
  the pinned instance.

## Consequences

* A million assets with an original each sync in 1.5 to 2.5 minutes on the gate machine at load average 50 to 70, the
  test's isolate missing within the frame budget of ADR-0098 (`test/sync_budget_test.dart`); before batches were read
  from their bytes and written on the data isolate's connection, garbage collections paused the UI's isolate for about
  30% of the frames. ADR-0098's idle isolate shares those pauses, so the gate does not charge them: phones in release
  builds remain to be measured.
* A restore or a reset re-downloads what it drops, and the UI shows the gap until it is back; keeping the rows until
  their replacements arrive needs a mark per row.
* Deletion intent (M2-36) must keep registry items out of the re-uploads; until the pipeline (M2-18) runs, they wait
  as `selected`.

## Options considered

* **A membership row per stream and synced row**: exact, but a second row per asset, a million at 1M.
* **Mark and sweep on reset**: no gap in the UI, but a generation column on every synced table.
* **Keeping a partner's undated assets while the share lasts**: no table, but it kept what photolibd does not send,
  once another way to it had brought it.
* **Decoding batches with the generated messages through drift's client**: the simplest code; it cost the UI's isolate
  about a third of its frames during a large sync.
* **A separate epoch table**: one more table; every cursor already belongs to one epoch.
