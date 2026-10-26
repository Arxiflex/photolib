# ADR-0072 — Device metadata extraction: in the data isolate, resumable through the replica, the platform first

* **Status**: Accepted — 2026-10-17 (roadmap M1-08). The owner kept the extraction state and its isolate and
  superseded the unbundled kernel in
  photolib-design#373:
  the app bundles the kernel that `tools/kernel/build.py` writes (M0-41, photolib-design#378), so extraction runs.
  Its "no `bundle: false`" is the app's: the owner kept the packages' own (photolib-design#698, 2026-10-23).
* **Requirements**: R-MODE-1, R-APP-5. **Design**:
  10 §1.5, §5.2, §13,
  09 §3.4,
  13 §4.8.

## Context

Design 10 has the device indexers write what the platform knows at once and extract the rest in the background, visible
items first, with the kernel resolving the capture time, without jank at 100k items and resuming after a restart. It
leaves open where extraction keeps its progress and runs, in what order, how it reads files, which values win over the
platform's and which device-health gates apply.

## Decision

We will:

* Keep the state in the replica: `local_asset` gains `asset`'s capture-time, location, camera and facet columns, and
  `extracted`, NULL while an item waits. An indexer sets it back to NULL when a file's size or modification time
  changes, and a result is stored only if neither changed while the file was read. A restart resumes from the replica;
  after a crash at most the chunk in flight is read again.
* Read visible items first (`extractFirst`), then the rest newest first by `COALESCE(taken, mtime)`, through a partial
  index of the waiting items. A pass walks that order once: a file that cannot be read waits for the next pass, which
  any change of the index starts, one the kernel panics on (kernel.panic, ADR-0036) is stored as read with nothing
  read, and a call that fails (no kernel) ends the pass.
* Run `MetadataExtractor` in the data isolate, 256 items per transaction, and read the files on a `WorkerPool` of two
  workers (one on a two-core device). The data isolate's writes bound the speed, about 10,000 items a second on a
  16-core desktop, and the workers share the isolate group's heap and pauses: on that machine, loaded twice over, one
  worker per core made the root isolate miss 4–5% of its 60 Hz frames and two at most 0.4%.
* Have each worker read a file as the server's ingest does ([ADR-0066](0066-server-ingest-pipeline.md)): the first
  64 KiB and the spans `ReadMetadata` asks for, at most 64 MiB in 32 rounds, then `ResolveCaptureTime` over the same
  ranges with the file's name and folders. No zone comes from a GPS position or the device's zone journal yet (clients
  have no zone tables, design 13 §4.8), so such times float or stay instants.
* Keep the platform's dimensions, orientation (clockwise degrees, as MediaStore gives it) and duration, filling in only
  what it left NULL; MediaStore's NULLs never erase what extraction filled in.
* Read MediaStore files by path under their volume's directory (`StorageVolume.getDirectory`, recorded in
  `volume_cursor.root`) with `dart:io` on the workers, without a platform call per file.
* Pause the backlog, never visible items, while Android reports a battery under 20% and no charger, battery saver, a
  thermal status above moderate or a battery above 42 °C, asked every minute. Desktops always allow it for now.
* Read with the kernel the app bundles: until a release is pinned ([ADR-0026](0026-kernel-prebuilt-libraries.md)), the
  one `tools/kernel/build.py` writes into `app/build/kernel/` (`hooks.user_defines.photolib_kernel.artifacts`); the
  app sets no `bundle: false`. The packages' own tests keep `bundle: false` (`photolib_kernel`, `photolib_data`,
  `photolib_api`, `photolib_editor`) and load the kernel cargo builds; only the root package's defines count, so none
  reaches the app. A call that fails ends the pass and the items wait.

## Consequences

* A restart, a crash or a changed file costs no bookkeeping beyond one column; the timeline (M1-10) and filters (M1-17)
  read the results from `local_asset`.
* Android redacts GPS unless the app holds `ACCESS_MEDIA_LOCATION` (design 10 §5.3); until it asks, MediaStore items
  have no location.
* Camera movies whose make the kernel does not read (it reads Apple's keys only) get a UTC instant where their clock
  was local.
* Follow-ups: request `ACCESS_MEDIA_LOCATION`; battery and heat on desktops; zones from GPS once clients have zone
  tables; ThumbHash and `timeline_entry` with the timeline; the iOS indexer (M1-02) plugs in with its own reader.

## Options considered

* **A `client_job` row per item** (design 10 §10's job runner, M2-19): a second table of 100k rows to keep in step with
  `local_asset`, where one column is reset in the same write that records the change.
* **Reading through a platform call per file** (content URIs): one round trip per range, and only from isolates that
  can reach the platform, which the workers cannot.
* **A worker per core**, the pool's default: no faster, and it paused the UI isolate.
* **The kernel unbundled until a release is pinned** (`bundle: false`, the provisional choice): no extraction ran.
* **No `bundle: false` in the packages either**: each would need artifacts built for its own tests, which load the
  kernel cargo builds from the checkout.
