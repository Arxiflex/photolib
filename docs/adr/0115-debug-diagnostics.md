# ADR-0115 — Debug diagnostics: one log per isolate, redacted and sealed in release, exported as a bundle

* **Status**: Accepted — 2026-10-20. The owner kept the macOS app's read-write entitlement and had a release build's
  log sealed at rest, as ADR-0057 promises no plaintext database, cache or file of Photolib's
  (photolib-design#475).
* **Requirements**: NFR-PRIV-1. **Design**: 19 §5,
  10.

## Context

Bugs that show only on the owner's machines and browsers (grey thumbnails on macOS and in the web app, folders that
stop loading after a restart) must be caught from logs, as the Linux build box runs neither macOS nor those browsers.
The app had a structured logger that almost nothing called and that reached no file; design 19 §5 asks for a
diagnostic bundle (logs, versions, settings, anonymised library statistics) and no telemetry. The packages and the
isolates they run on (the data isolate, indexing isolates, workers) could not reach the app's logger.

## Decision

We will:

* Move the logger into `app/packages/photolib_log`, pure Dart: named loggers (`photolib.<subsystem>`) send records to
  `Log`, a hub per isolate. Debug and profile builds keep every record with full detail; release builds keep info and
  above, redacted before anyone hears of them: the values of fields named for files, folders, paths, roots,
  directories, names or URIs, and in any other text whatever looks like a path, a URI or a file name.
* Send the data isolate's and indexing isolates' records to the isolate that started them, as JSON lines.
* Send the Android, macOS and Windows runners' records (channel failures, folder bookmarks at start) over
  `org.photolib/log` as `photolib.native.<logger>`: kept, at most 1,000, until the app listens, then one at a time.
* Keep the log natively in `<app support>/logs/photolib.log` and four older files of at most 2 MiB each, and in
  browsers in IndexedDB's `photolib/log` (the newest 20,000 records), which crypto-erase deletes with the store; also
  in memory (1,000 records) for Settings › Diagnostics, and in the console: `debugPrint` in native debug builds, the
  browser's console by level, grouped by logger.
* Seal what a release build keeps, as the store's objects are (ADR-0057): natively each batch of records, appended to
  `photolib.plb` and its four elders, is a PLB envelope under the class C key of the vault's object `log` (from the
  device data key through the cache key), after its length (4 bytes, big-endian); in browsers each record of
  `photolib/log`'s `sealed` store is such an envelope, as `VaultCache`'s tiles are (ADR-0116). A release build deletes
  the plaintext files or records an earlier build left, cuts an envelope a crash left short, and skips one sealed
  under keys the store no longer has. Debug and profile builds keep the log in the clear.
* Export the diagnostic bundle as a zip of the stored log, unsealed and redacted again in release builds, and
  `info.json` (versions of the app, Flutter, the OS or browser and the device; settings; library counts by source,
  type, state and extension, folders by state): the save dialog on desktops, the share sheet on phones, a download in
  browsers.
* Show Diagnostics always in debug builds and, in release builds, behind *Show diagnostics* in Settings (kept with
  every setting in the vault's sealed `settings` object, ADR-0057) or the `diagnostics` build flag.
* Grant the macOS app `com.apple.security.files.user-selected.read-write` instead of read-only, which the save dialog
  needs (ADR-0071 foresaw it for a write feature); the folder bookmarks stay read-only.

## Consequences

* Every package logs without depending on the app; tests listen to `Log.records`.
* A release log or bundle names no file, at the price of losing some useful text (a mime type survives, a URL or a
  dotted method name in an error does not). A release build's log reads only with the vault's keys and goes with
  crypto-erase; the bundle leaves the device in the clear only on the user's export. A debug or profile build's log is
  plaintext and names everything.
* The stored log waits for the vault: records logged before it unlocks wait in memory, and those logged while it is
  locked or when it cannot open are not kept, never written in the clear.
* Statements slower than 50 ms are timed in the data isolate, so the time a client waits for a busy writer is not.
* The app has no video player yet: the viewer logs that it opened a video and shows its poster frame.
* Follow-up: an opt-in crash report endpoint (design 19 §5) remains to be designed.

## Options considered

* A plaintext release log with names redacted (this ADR's first answer): the owner chose sealing, as ADR-0057 leaves no
  plaintext of Photolib's at rest.
* No stored log in release builds (memory only): nothing to export after a restart.
* `package:logging`: hierarchical and standard, but its records carry no structured fields to redact by name.
* Logging only on the root isolate through callbacks into each package: more plumbing for every new subsystem.
* OPFS for the browser's log: append-only files need a rotation of their own and Safari's writable streams are recent;
  IndexedDB deletes by key range in the same transaction.
* Saving to Downloads on macOS (`downloads.read-write`) instead of the save dialog: no choice of place, and a second
  file entitlement.
