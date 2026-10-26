# ADR-0252 — A device's upload repairs a damaged file; external libraries are scrubbed for bit-rot

* **Status**: Accepted (owner answered photolib-design#646, 2026-10-23: both decisions kept). Follows up
  photolib-design#605, M2-33.
* **Requirements**: NFR-REL-1; feature `LIB-15`. **Design**:
  07 §4, §8,
  [ADR-0234](0234-integrity-scrubbing-and-backup-watchdog.md), [ADR-0092](0092-per-user-deduplication.md).

## Context

ADR-0234 left repair by hand: dedup linked an upload of a damaged file's bytes to that file, and `CheckHashes` told
devices it was held, so "put it back from a device" meant copying the file into the store. It also left external
libraries unscrubbed, as their owners may change them, though bit-rot of a NAS archive is what LIB-15 is for.

## Decision

1. **A damaged file holds nothing.** A file with an open finding (any kind but `orphan`) does not count for dedup or
   `CheckHashes`, so a device's backup sends its bytes again.
2. **The upload puts it back.** Completing an upload into its owner's own standard library writes its verified bytes,
   through the journal, for each such file of the owner's in a store: at its key when the object is gone, else at the
   first free numbered key beside it, the file's rows moved there in the transaction that queues the damaged object's
   delayed delete. The findings are resolved and the upload is linked; nothing is ingested again. External libraries
   are never written: their damaged files are not repaired, and the upload is stored as usual.
3. **External libraries are one more store, `external`,** scrubbed at the same pace and read whole at each library's
   byte rate. Bytes without their hash while the file keeps the size, modification time and inode it was hashed with
   are a `content` finding (bit-rot), as is a file that cannot be read; a file written or gone since is left to
   rescans (M2-28), and a library that cannot be opened is skipped. A finding names its library
   (`integrity_findings.library_id`), as paths repeat across libraries; the console shows the file's full path.
4. **A finding that nothing names is resolved** at the end of its store's next cycle: a deleted file needs no repair.

## Consequences

* ✅ "A device still has it" is an action: the next backup of the photo repairs it, with no download of the store.
* ✅ Bit-rot of external archives is found within one cycle, without false findings for edits, moves or deletions.
* ⚠️ A file put back beside its damaged object keeps the numbered key until a re-layout moves it.
* ⚠️ `photolib upload` skips what its journal sent before, so the CLI repairs only with a new journal.
* ⚠️ An external file restored by hand keeps its finding until a rescan records its new identity (M2-28).

## Options considered

* **Overwriting the damaged object in place**: no journal step can roll a failed overwrite back to the old bytes.
* **Ingesting the upload as a new asset**: two assets, the damaged one still in every album that holds it.
* **Scrubbing external files only by size and modification time**: bit-rot changes neither.
