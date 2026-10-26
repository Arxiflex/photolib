# ADR-0257 — External libraries: offline roots, moves, missing files under a guard, watches and hints

* **Status**: **Proposed — owner to confirm** (roadmap M2-28).
* **Requirements**: R-MODE-3, R-REL-1; LIB-08, LIB-09, LIB-10, API-11. **Design**:
  storage and libraries §4;
  [ADR-0093](0093-external-libraries.md), [ADR-0042](0042-desktop-folder-sources.md) (the apps' folders),
  [ADR-0201](0201-sources.md) (sources).

## Context

ADR-0093 scans external libraries but only adds; 07 §4 asks for change detection, moves that keep identity, an
offline root that changes nothing, missing files never purged, one glob engine, a guard against mass disappearance
and fast rescans. It leaves open what makes a read-only root "its own", what counts as hidden, how a confirmation is
bound to what it confirms, and how watches, polling and hints share the work. ADR-0201 binds this item: what it
leaves open (the `Source` port, Unicode normalisation, hiding after a grace period) is not built here.

## Decision

1. **Own root.** A scan's root job checks the root: it must list one of the up to 64 names it listed at the last scan
   (`libraries.fingerprint`), or have none recorded, and not be empty while the library has files. Otherwise, or
   when it cannot be opened or listed, the library is `offline` and the scan ends with nothing else changed; the last
   job checks again before hiding anything. Offline libraries are rescanned hourly and come back by themselves.
2. **Missing, never deleted.** A file is missing (`library_files.missing_since`, its asset files `state =
   'missing'`) when a scan did not find it: its folder's listing lacked it, or the scan never reached its folder
   (deleted, excluded, moved out). Folders that cannot be read keep what lies under them; files found after the scan
   began are not judged by it. A file found again is present again. Nothing purges missing files.
3. **One guard.** `guard::Dry` stands for any operation that would delete, trash, hide or purge: more than 1,000
   items or 5 % of its scope waits for the token of its dry run, a BLAKE3 hash of the action, scope, state and count,
   so a token confirms only what was counted. A scan over the guard hides nothing and holds (`library_scans.held`);
   `GetStatus` shows the count, total and token, `ConfirmScan` hides with it (audited `library.hide`) and answers
   any other token with `confirmation.required` and the new dry run. A new scan replaces a held one.
4. **Moves.** A new file with the device, inode, size and time of a known file is that file moved when its old path
   no longer holds it, holds another file, or holds it only in another case (a case-insensitive volume): its row,
   asset and keys move and nothing is read again. Otherwise (a hard link) it is new. A file at its known path with
   the same size and time but another device or inode (a remount) takes its new identity.
5. **Relocation.** `RelocateLibrary` moves a library to a folder checked as a new root is that holds one of its
   fingerprint's names, and scans it there; paths are relative to the root, so only identities change.
6. **One glob engine.** `photolib-ignore` ([ADR-0259](0259-external-sidecars-and-ignore-rules.md)), the rules of
   `photolib upload` and the scanner, is property-tested against a direct reading of gitignore globs and against a
   walk. An exclusion makes what it matches missing at the next scan without reading it, and removing it brings the
   same assets back; a hint reads the ignore files above its folder itself.
7. **Watches and polling.** Each `worker:io` process watches every folder of the libraries that are not offline with
   inotify, shallow folders first, up to half of `max_user_watches` or until the kernel refuses (as ADR-0042), and
   none on network or FUSE file systems. A file closed after writing or moved in, or a new folder, hints its folder
   a second after the last change; lost events start a scan. `libraries.unwatched` counts the folders no watch
   covers and the log names the limit. The `rescan` job, every 15 minutes, scans a library with unwatched folders an
   hour after its last scan and every other a day after.
8. **Hints (API-11).** `HintPaths` takes up to 1,000 paths under the root and queues the folders they name or lie in
   at priority 10, above other work, with their ingest. A hint lists one folder, adds new files and moves, follows new
   subfolders and never hides.
9. **Rates.** `files_per_second` counts a folder listed and each new file, no longer each entry listed: an unchanged
   rescan costs a stat per file at the disk's pace.

## Consequences

* ✅ An unmounted share, an empty or missing mount point or another share mounted in its place changes no asset,
  album item, face, edit or file row; a relocated library keeps them all and reads nothing again (`external/scan.rs`).
* ✅ 20,000 unchanged files in 200 folders rescanned in 9.2 s in a debug build at load 42 on 8 cores, writing no file
  row (`tests/external.rs`, `PHOTOLIB_RESCAN_FILES`); the 2-minute budget for 500,000 files on a disk NAS is not
  measured here.
* ⚠️ A file changed in place keeps its old metadata and no hash; 07 §4's `external_change` version is a follow-up.
* ⚠️ Moves across file systems, where the inode changes, are new assets: matching by hash is a follow-up, with
  ADR-0201's Unicode and case rules.
* ⚠️ Hints are the administrator's (`ManageServer`); owners' desktop clients need a rule of their own. The admin
  console does not show held scans or polled folders yet.
* ⚠️ Missing assets stay in the timeline: hiding them after a grace period is ADR-0201's.

## Options considered

* **A mark on every file a scan sees**: a write per file per rescan, 500,000 for an unchanged tree.
* **A table of every folder**: precise, but a second index of the tree to keep and migrate; the folders a scan
  visited are enough and live only until the next scan.
* **fanotify**: needs `CAP_SYS_ADMIN`; inotify needs nothing and both miss network changes.
* **Hiding what a hint finds gone**: a hint names one folder, outside the guard's view of the library.
* **Tokens stored in the database**: a hash of what was counted needs no table and expires with the state.
