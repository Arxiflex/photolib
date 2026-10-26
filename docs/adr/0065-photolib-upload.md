# ADR-0065 — `photolib upload`: a journal on the client for resumable, idempotent bulk uploads

* **Status**: Accepted — 2026-10-17. The owner accepted decisions 1–4 of
  photolib-design#416
  as made and changed the fifth: beyond the key's rate, the CLI backs off exponentially instead of every second.
* **Requirements**: R-MODE-2. **Design**: 05 §6, 13 §2.1, feature catalogue ING-08, ING-10,
  ING-21 and API-02, [ADR-0042](0042-desktop-folder-sources.md), [ADR-0061](0061-resumable-uploads.md).

## Context

Cards, NAS folders and whole libraries of 100,000 files need a command-line upload that survives being killed and
never uploads a file twice. photolibd has resumable uploads (ADR-0061) and API keys (ADR-0055) but no `CheckHashes`
(M2-12) yet, and the design leaves the CLI's state, output and scope open.

## Decision

1. **Command.** The `photolib-cli` crate of the server workspace builds `photolib`. `photolib upload --server <url>
   --library <id> [--state <dir>] [--jobs 8] [--dry-run] [--json] <path>...` signs in with an API key that may
   contribute (ADR-0055) in `PHOTOLIB_TOKEN`, never a flag, which process lists and shell histories would show.
2. **Files.** A file named on the command line is uploaded as it is. Under a folder, the photos and videos the app's
   folder sources index are, minus the defaults and `.photolibignore` rules of ADR-0042 (in any case where the
   volume ignores case), ported to Rust and run against `testdata/photolibignore.json`.
3. **Journal.** `<state>/<library>.jsonl` (`$XDG_STATE_HOME/photolib` unless set) holds one JSON line per change of a
   file's record: path, size, modification time, BLAKE3, the upload's path on the server and whether it is done. One
   process at a time locks it. The upload's path is written before any byte is sent, and `done` once photolibd
   acknowledged the verified and stored upload. A later run therefore skips unchanged files without reading them,
   resumes a pending upload from the server's offset, also at another address of the server, and sends a content once
   per library: a copy waits for the file sending it, then records its upload. Lines reach the operating system at
   once and the disk every second: a crash loses nothing, a power loss at most a second of records, whose files upload
   again.
4. **Recovery.** A lost connection, a proxy's page, a `409` or a passing server error resumes from `HEAD` up to five
   times in a row without progress (the offset `HEAD` reports moving, as the part of a cut append the server kept
   moves it); a proxy's `413` halves the appends, down to 64 KiB, as the apps do (ADR-0061). An
   upload the server forgot (expired) or refused for a changed hash starts over once. Beyond the key's rate
   (`api_key.rate_limited`) a request is tried again without a `HEAD`, as it was refused unread, after a wait that
   doubles from 1 s to a 60 s cap, each in the upper half of its step at random; it never counts as a failure. A
   refusal every further file would get too (no session, no right to contribute, a full quota) or a server gone stops
   the run with status 1.
5. **Output.** Text lines for people; `--json` prints `plan`, `file` (status, BLAKE3 or error), `progress` and
   `summary` events, one JSON object a line. `--dry-run` lists what a run would upload, reading and sending nothing, so
   it counts copies as new.
6. **Server.** photolibd finishes an upload's request when its client goes away, which a killed run made it drop
   between the journal's plan and switch, and creates the uploads of an owner without a quota without locking the owner
   or adding up their files.
7. **Scope.** Archives come with `photolib-import`'s adapters (M4-02, M4-05) in this command: a plain upload of a
   Takeout or iCloud export loses its sidecars' dates and albums (design 13 §2.1, IMP-7). The desktop app backs up its
   folder items through the backup state machine (M2-18) once it signs in (M2-02).

## Consequences

* ✅ 100,000 photos upload 32 at a time in minutes against a local photolibd; a killed run resumes where it stopped, and
  a run with nothing to do takes about a second.
* ⚠️ Changes are noticed by size and modification time, as rsync does by default: an edit that keeps both is missed,
  unless it happens during the upload, when the server's hash check catches it.
* ⚠️ The journal belongs to one machine: another machine, or a lost state directory, uploads again until photolibd
  answers `CheckHashes` (M2-12).
* ⚠️ A run killed between the server creating an upload and the journal recording it leaves an incomplete upload that
  holds quota until it expires a day later.
* ⚠️ Creating an upload still adds up the files of an owner with a quota; a running total would take a migration.
* ⚠️ A file takes two requests or more: at a key's default 600 a minute, 100,000 photos take hours, so a key for bulk
  uploads needs a higher rate.

## Options considered

* **SQLite in the state directory**, as design 13 keeps import runs: a C dependency for a log of one record type.
* **Creating small files' uploads with their content**, as iOS does: half the requests, but a creation that breaks
  leaves no upload to resume and one that holds quota for a day.
* **Asking the server what it has** (`CheckHashes`): not there yet (M2-12); it will complement the journal.
* **Hashing every file on every run**: reads all 100,000 files to find that nothing changed.
