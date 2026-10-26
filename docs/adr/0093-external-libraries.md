# ADR-0093 — External libraries: a job per folder, read in place, hashed last, under the operator's roots

* **Status**: Accepted — 2026-10-21 (roadmap M2-27): the owner kept decision 3's files that are not media as counted
  `library_files` rows, which `external::retype` queues again when type detection changes
  (photolib-design#583); the
  other decisions, not mentioned there, stand as decided, and on 2026-10-23 the owner confirmed the whole ADR as
  Accepted
  (photolib-design#686).
* **Requirements**: R-MODE-3, LIB-03, LIB-07. **Design**:
  storage and libraries §1, §4,
  media pipeline §3.

## Context

The design wants folders an administrator assigns to users, scanned in parallel and resumably (checkpointed by
folder), browsable from metadata and thumbnails long before a 2M-file archive is hashed, and read gently enough to
spare spinning disks and NAS boxes. It leaves open how an administrator names a folder, what the checkpoint is, where
a file's identity lives until it is hashed, and how the reads are limited.

## Decision

1. **Roots.** `AdminService.CreateExternalLibrary` gives an account a read-only library of a folder that lies under one
   of the operator's `external_roots` (none by default) and neither holds nor lies in another library or photolibd's
   data, work or database directory, after resolving symlinks; `root_uri` is its canonical absolute path. Creating one
   starts a scan; `ScanLibrary` starts another. Both are audited.
2. **A job per folder.** A scan is a row of `library_scans` and a keyed `scan` job per folder. In one transaction a
   job lists its folder (never through a symlink), records each new regular file in `library_files` with the identity
   it has until it is hashed (device, inode, size, mtime in ns), queues their ingest in batches of up to 500 that never
   split a name stem (a Live Photo's or RAW+JPEG's files), queues a job per subfolder and lowers the count of folders
   left. The folder is the checkpoint: a restarted server goes on with the jobs still queued. One scan runs per library;
   a rescan ingests only new paths, and changes, moves and disappearances are M2-28's.
3. **Read in place.** A scanned batch is an `ingest` job: each file is opened beneath the root (`openat2`, no
   symlinks) on the root's threads within its timeout and read as an upload is (ADR-0066), then committed with
   `source = 'scan'`, `storage = 'external'` and its path as key, its renditions queued. Files that are not media are
   recorded `unsupported`, not kept as assets, and the `retype` sweep of each later type detection reads them again
   (ADR-0066 (d)); an unreadable file is `failed` with its reason. A timeout fails the job, which retries, so a hung
   NAS changes nothing. The `render` and `transcode` jobs (ADR-0084, ADR-0085) render an external original from a copy
   in their scratch directory before it is hashed, into `local`, never beside it.
4. **Hashed last.** Each batch then queues a `hash` job at priority −10, below every other job, which reads its files
   in 8 MiB chunks, checks each chunk against the recorded identity and leaves a file that changed unhashed for the next
   scan. `worker:io` runs scans and hashes, four at a time per process; a worker leases each type from the head of
   its own queue (`jobs_queued`), so hash jobs are not slowed by the thumbnails queued before them.
5. **Rate limits.** A library's `scan_policy` holds `files_per_second` (folder entries listed and files opened) and
   `bytes_per_second` (bytes read whole, to render or hash), shared by its jobs in a process; unset at creation they
   are 1000 and 64 MiB, 0 is unlimited.

## Consequences

* ✅ 2,000,000 files in 20,000 folders are browsable (an asset each with the kernel's metadata, its owner's to see)
  before any of them is hashed, and a scan cut off by a restart goes on with the folders left and ingests each file
  once (`tests/external.rs`; 3,000 files in the gate, each with its renditions before any hash; 2,000,000 by hand).
  The 2M run predates the renderer, so its thumbnails were queued: on a shared 16-core machine at load 40–110, debug
  build, every folder was listed 75 min and the last asset made 113 min after the scan started; 3.6 GB of database.
  Rendering ran at about 20 photos a second there, so a 2M library's thumbnails take about a day on such a machine.
* ⚠️ Scanned files get no ExifTool dump yet: ExifTool's sandbox reads only its own directory, where an external file
  can be neither linked across filesystems nor copied cheaply (follow-up).
* ✅ `.photolibignore` and the default ignore rules (`@eaDir`, `#recycle`, …) apply to scans
  ([ADR-0259](0259-external-sidecars-and-ignore-rules.md)); changes, moves and missing files are
  [ADR-0257](0257-external-change-detection.md)'s.
* ⚠️ Names that are not UTF-8 and paths over 1024 bytes are skipped with a warning.
* ⚠️ Limits are per process; a split deployment's processes each get the full rate.

## Options considered

* **Any path an administrator types**: an admin's stolen key could turn another user's folder or photolibd's data into
  its own library; the operator's roots bound what the API can expose.
* **One long job per scan with its own progress table**: a job's writes commit at its end (ADR-0034); folders as jobs
  get checkpoints, retries, parallelism and pausing from the queue.
* **Identity in `asset_files`**: files that are not media, or failed, need it too, or every rescan reads them again.
* **Keeping files that are not media as assets, as uploads do**: an archive's text, databases and sidecars would fill
  the timeline; design 08 counts them instead.
* **Hashing in the ingest job**: reading every byte first is what keeps archives unbrowsable for hours.
