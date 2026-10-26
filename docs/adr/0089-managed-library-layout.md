# ADR-0089 — Managed library layout: a template applied once, per-original moves, delayed deletes

* **Status**: Accepted — 2026-10-23. The owner kept that every account but viewers gets "Photos" from the
  `library-create` job, queued in the account's transaction and every 15 minutes
  (photolib-design#719),
  which names this ADR. M2-11's own choices (layout, re-layout, delayed deletes) were never put to the owner apart:
  they are accepted with it, and the owner is asked to confirm them.
* **Requirements**: R-MODE-2, R-REL-1, NFR-PORT-1. **Design**: storage and libraries §2, §3, §6, §8,
  [ADR-0022](0022-object-store-backends.md) point 2.

## Context

Design 07 lays out a managed library as `originals/<template-path>` beside its marker, and ADR-0022 lets it live on
any store and move to another only through an explicit job: copy, verify BLAKE3, switch, delete the source after a
7-day grace. Uploads still waited under `uploads/<id>` (ADR-0061). Left open: the template's tokens and what a name may
put in a key, when ingest's job transaction can finish a move, whether a library switches stores in one transaction,
and what deletes a source a week later.

## Decision

1. **Layout.** A managed library lives under `libraries/<id>/` of its store: its marker at `.photolib/library.json`,
   written with the row that creates the library, and its originals under `originals/`. `placement.libraries` names
   the store of new libraries (default `local`); a library keeps the store it was created on. Files are referenced by
   `asset_files.id`, which never changes; only its key does.
2. **Template.** `{{year}}`, `{{month}}`, `{{day}}`, `{{hour}}`, `{{minute}}`, `{{second}}`, `{{make}}`, `{{model}}`
   and `{{filename}}`, each optionally `|default:"text"`; default `{{year}}/{{year}}-{{month}}/{{filename}}`. The
   last folder must hold `{{filename}}`. The time is the asset's wall clock, else UTC, else when it was ingested.
   A value never adds a folder (`/` becomes `_`), control and bidirectional characters become `_`, names are trimmed
   and cut to 200 bytes keeping the extension, `.` and `..` become `_`, and empty folders are dropped. A taken key is
   numbered before its extension: `IMG_1 (2).jpg`. This amends ADR-0066 point 7: a name reaches a key only so.
3. **Ingest** renders the template from the asset row it just wrote, copies each upload there in the library's
   current store (server-side within a store), and switches the copies in the job's transaction with the files' rows
   and a delayed delete of the upload. A changed template places only new uploads.
4. **Re-layout** is the `relayout` job (`worker:io`) for a library and a store. It writes the marker there and switches
   the library's store first, so new uploads land there, then moves each original on its own: copy, verify BLAKE3,
   switch every row naming that key in one transaction, and delete the source a week later if it left its store, else
   at the next purge. Originals already in place are skipped, so a stopped run resumes. This narrows ADR-0022's one
   switch transaction to one per original. The old store keeps the library's marker.
5. **Delayed deletes.** A delete intent switched with a due time (`file_intents.due`) keeps its key reserved; the
   `storage-purge` job, which the scheduler queues every 15 minutes, does the due ones under a row lock, and recovery
   and `finish_switched` leave them alone. A put is done once switched: nothing is left to delete.

## Consequences

* ✅ Templates never move files implicitly, and a library stays readable at every step of a move: the tests kill one
  with SIGKILL at each of its steps, from a filesystem to S3 and back.
* ⚠️ A store move holds both copies for a week, and a library spans both stores while it moves.
* The account flow creates libraries: each new account, and each role change, queues the `library-create` job, which
  gives every account but viewers, who never upload, the managed library "Photos" as its upload target with
  `library::create`; the scheduler queues it every 15 minutes too, for accounts that have none.
* ⚠️ No API sets templates or starts re-layouts yet: the admin console ([ADR-0063](0063-admin-console.md)) will call
  `set_template` and `enqueue_relayout`.
* ⚠️ `placement.derived` and `placement.backups` come with their users: renditions still go beside their original
  ([ADR-0085](0085-video-renditions.md)) and dumps to the data directory (M2-31).
* ⚠️ No dry run or undo for re-layouts (M3-10), and no album token: an upload belongs to no album when it is placed.

## Options considered

* **One transaction switching the whole library**: a crash after hours of copying would roll them all back.
* **Moving at ingest with `relocate`**: the job's transaction commits after the handler returns, so only recovery at the
  next start could delete the upload.
* **Deleting a moved source at once**: no grace for readers in flight or for a wrong target store.
* **A purge timer in every process**: the scheduler already ticks, and one more timer is one more manifest row.
* **Content-addressed keys**: ADR-0022 keeps one browsable layout on every store.
