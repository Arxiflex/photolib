# ADR-0226 — Backup: one state machine on the device, the account's upload destination, the device's session

* **Status**: **Proposed** — owner to confirm. M2-18 had to choose where an account's first backup lands, what
  credential backup runs on, what a metered network carries by default, how a stalled backup is noticed, and how far
  the app goes before the platforms' background work (M2-19, M2-20). Becomes *Accepted — YYYY-MM-DD* when the owner
  decides.
* **Requirements**: R-MODE-2, R-REL-1. **Design**: 05 §6, §8, 07 §2,
  10 §5.5, §10, feature catalogue ING-05, ING-06, ING-13, ING-14, ING-25, ING-26,
  [ADR-0061](0061-resumable-uploads.md), [ADR-0065](0065-photolib-upload.md),
  [ADR-0092](0092-per-user-deduplication.md), [ADR-0120](0120-client-sync-engine.md),
  [ADR-0125](0125-sign-in-from-the-app.md).

## Context

Design 05 §6 gives each local item a backup state with reasons and makes the device's own state machine the source of
truth even when the OS transfer queue sends the bytes. Only ADR-0125's interim folder backup drove the replica's
`backup_state`: desktops sent every folder item after each sync, with no selection, conditions or deduplication. Backup
on competitors stops silently when a session expires or a second factor is asked for, burns metered data, and says
"stuck" without a reason.

## Decision

* **Engine**: `BackupEngine` in `photolib_data`, run by `backupReplica` in the data isolate after any sync asked for
  before it. A run gives each new item `discovered`, selects by folder (each folder of the device's items by key; a
  folder the settings do not name waits as `folder_new` until the person answers, once), media type and capture date,
  pauses what the network may not carry (`metered`, `metered_cap`), hashes with BLAKE3 (Dart, on a worker, checked
  against the reference's vectors), links what another item of the device or the server holds (`CheckHashes`), and
  uploads the rest, eight at a time, newest found first, a thousand per batch. An upload's path is written before its
  first byte goes, so a killed app resumes it from the server's offset; a forgotten one starts over once. An item an
  indexer saw change (its hash cleared) goes again. It replaces the interim `FolderBackup`: a desktop still backs up
  after each sync (`syncingProvider`), through this engine.
* **Failures** wait in `failed` with the server's reason code (or `unreadable`, `changed`) and a retry after 1, 2, 4 …
  minutes, a refusal's after 1, 2, 4 … hours, as the owner kept photolib-design#481's hour in photolib-design#719 (the
  owner is asked again which stands), at most a day. A revocation (`signed_out`), an unreachable server (`offline`) or a
  refusal every further item would get (`quota.exceeded`, `library.contribute_denied`, `second_factor.required`) stops
  the run and fails nothing else. Each run is a `backup_run` row: what it uploaded, linked, failed, left pending and why
  it stopped.
* **The account's upload destination** (design 07 §2): an upload created without `Photolib-Library` goes to the
  owner's upload target, else their first standard managed library, else a managed library "Photos" made then on
  `placement.libraries`, one however many first uploads arrive at once (under the lock of the `library-create` job,
  which gives every account that may upload that library too, ADR-0089). A viewer account gets none.
* **Device credential**: backup runs on the device's own session (ADR-0052), which the app renews silently with
  `RotateSession` at a start once fewer than 60 of its 90 days are left (ADR-0125) and, running for weeks, before a
  backup once it has less than 30 days left. Backup never signs in, so a session expiry or a sign-in's second factor
  never reaches it; a revocation signs the app out and the home screen keeps a notice naming the fix until the next
  sign-in, also across restarts.
* **Conditions**: on a metered network (Android's flag, which counts a hotspot and tethering; NetworkManager's on
  Linux, which guesses metered for them) photos up to 50 MB go and videos wait, both choices the person can change;
  roaming, a battery under 20 % off the charger, or charging when required stop the run with that reason.
* **Watchdog**: when items have waited for 24 hours (or 12, 48, 72) since a run last left nothing to send, or since the
  first run, the device raises a notification once until backup completes: Linux through the desktop's notification
  service, Android through `DeviceHealth.kt`. The home screen shows the last complete backup and what waits, and
  while the server is out of reach its last contact, the replica's last sync (ADR-0200 B7). Each run
  that reaches the server reports what its `backup_run` row left pending with `AuthService.ReportBackup`, the server's
  watchdog ([ADR-0234](0234-integrity-scrubbing-and-backup-watchdog.md)); a run stopped by the device or offline does
  not, and a failed report waits for the next run.
* **Scope**: the app backs up in the foreground on desktops and Android, every 15 minutes and on "Back up now"; iOS's
  photos back up through PhotoKit (M2-20), Android's background work is M2-19, the deletion registry M2-36.

## Consequences

* ✅ 10,000 folder items back up to a real photolibd over the app's session into a library made at the first, and a
  backup killed half-way finishes with each file once (`app/test/live/backup_test.dart`); a second device whose
  100,000 items the server holds links them all and its next run touches only what is new.
* ⚠️ Dart BLAKE3 hashes at about 100 to 180 MB/s on one core of the gate machine, well under the Rust crate's.
* ⚠️ A server whose administrator requires a second factor refuses the device's session everything but enrolment, so
  backup stops (`second_factor.required`) until the person enrols one, which the app cannot do yet (M2-05).
* ⚠️ macOS, Windows and iOS read no metered flag and raise no system notification yet: the home screen says it.
* ⚠️ Uploads the server completed but has not ingested are not found by `CheckHashes`, so a second device backing up
  the same files at the same moment uploads them too; the server links them at completion (ADR-0092).

## Options considered

* **An API key for backup** (ADR-0055): independent of the session, but not bound to the device, rate-limited for
  people, and one more secret to revoke.
* **Admitting a session that must enrol a second factor on `/upload`**: backup would never stop, but it weakens the
  enrolment policy of ADR-0088 for a stolen password-only session.
* **The app creating its library through a new RPC**: one more procedure, route and matrix row for what design 07 §2
  already names, the account's upload destination.
* **Hashing in the kernel**: fast, but the kernel's ABI is one call per request and does no I/O; a streaming hash needs
  handles.
* **Pausing every item on a global condition** (charging, roaming): a write per item for a fact about the device.
