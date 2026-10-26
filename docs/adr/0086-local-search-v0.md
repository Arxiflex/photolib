# ADR-0086 — Local search v0: filters and file names over the replica, compiled in Dart

* **Status**: **Proposed — owner to confirm** (roadmap M1-17).
* **Requirements**: F-06. **Design**:
  09 §4.1–4.3,
  10 §2, §13.

## Context

The standalone app ships filters and file-name search first (design 09 §4.3), within 100 ms on a 100k library
(design 10 §13). Design 09 §4.1 puts filter compilation in the kernel, beside the query parser of M5-06, and lexical
search on kernel tokens in FTS5; neither exists yet. Device items live in `local_asset` (ADR-0072), which has no lens,
no screenshot facet and, for folder files, no MIME type; local albums arrive with M1-15.

## Decision

We will:

* Compile a `LocalQuery` (words, capture days, facets, folder, camera) into a drift predicate in `photolib_data`, run
  where the replica is, until M5-06's kernel compiler replaces it with the same semantics.
* Match each word as a substring of the file's name or folders, case-insensitive for ASCII, `*` and `?` as wildcards.
* Take the day of `taken_local`, else of the platform's time (`taken`, else `mtime`) in the device's zone.
* Derive facets at query time: video by MIME type, else by extension; screenshots by "screenshot" or "screen shot" in
  the name or folders; panoramas and motion photos from extraction's `facets`.
* Treat a folder as itself and its subfolders, a range of `(volume, path)`; device albums are MediaStore folders.
* Count and window the results in one pass: a materialized CTE of the hits' ids and sort keys, no new index. On a
  16-core Linux desktop loaded twice over, 19 combinations over 100k items take 12–62 ms (the fastest of seven runs)
  through the data isolate, the replica encrypted by the vault.

## Consequences

* No schema change; M5-06 replaces the compiler and M5's tokeniser the word match without touching the UI.
* Non-ASCII names match in their own case only; screenshots named in another language are missed until PhotoKit's
  subtype (M1-02) or a stored facet.
* Follow-ups: lens once the kernel reads it; local albums (M1-15); thumbnails in the result cells (M1-09); bulk actions
  (M1-16); budgets on phones (device lab).

## Options considered

* **The kernel compiler now**: the parser and compiler are M5-06's, larger than this item.
* **FTS5 over file names**: a new table and triggers for tokens the kernel does not define yet.
* **An index on the sort key**: makes broad queries cheaper but rare-match ones a random walk of the table.
* **A window function for the count**: drift writes its frame out with `EXCLUDE NO OTHERS`, which SQLite runs in
  quadratic time.
