# ADR-0066 — Server ingest: the clients' kernel calls over ranges, a job per committed upload, metadata as data

* **Status**: Accepted (owner answered, 2026-10-17) in
  photolib-design#366
  (roadmap M2-08): points 1, 2 and 7 stand as decided, and point 3 with the owner's four conditions. Applying them,
  the owner answered in
  photolib-design#561
  (2026-10-21): (c)'s sharing stands, and (a) reads no bytes but dates such a file by its name.
* **Requirements**: R-MODE-2, F-09, R-REL-1. **Design**:
  media pipeline §3, §8,
  import §4.

## Context

A complete upload (ADR-0061) waits in its library's store with nothing recording it. The design fixes the steps that
make it an asset (sniff, identify, metadata, group, resolve, commit, render, enrich) and requires the server's metadata
to be the clients' and every file's text to stay data. It leaves open what starts ingest before `CommitAsset`
(M2-21), how a server that reads files in ranges resolves capture times the kernel took from a contiguous head, who
reads a movie's QuickTime dates, what becomes of unsupported files, and how ExifTool is confined per user.

## Decision

1. **Trigger.** Completing an upload of a standard library queues an `ingest` job in the same transaction; a private
   library's upload is never read. Creation may name the file's path below its source's root in `Photolib-Path`
   (percent-encoded UTF-8; empty, `.` and `..` names, backslashes, control characters and bidirectional overrides are
   refused). The job takes a batch of uploads, so that `CommitAsset` can commit several parts at once.
2. **Extraction.** A `worker:cpu` process calls the kernel through its byte ABI as the apps do: `ReadMetadata` over
   the first 64 KiB and the spans it asks for (at most 64 MiB in 32 rounds), then `ResolveCaptureTime` over the same
   ranges, which the kernel now accepts instead of a head. A movie's own dates are claims in the kernel: the keys'
   creation date, and `mvhd` in UTC unless a camera maker wrote it; a host claim of the same source replaces them.
   A kernel panic fails one file. The server has no zone table yet, so GPS-only times float as on clients without one.
3. **Formats** are named by magic bytes (`ingest::sniff`), never by the name. Files that are not photos or videos (Ogg
   audio, PDF, EPS, SVG, unknown bytes) are kept as assets without a media kind, never dropped (principle 1), never
   rendered, on the owner's four conditions:
   * (a) no parser reads their bytes, neither the kernel nor ExifTool, so they have no metadata; `ResolveCaptureTime`
     dates them from their name and folder alone (no ranges), and the storage template takes the upload's date only
     when the name gives none;
   * (b) `/media` sends their originals only as a download, `Content-Disposition: attachment` and
     `application/octet-stream`;
   * (c) they stay out of the timeline, search, memories and sharing: `photolib_authz` keeps them out of albums,
     partner shares, links, covers, memories, search hits and map pins, and `GetTimelineSummary` counts none, so only
     their library's owner and members reach them, listed under other files;
   * (d) each asset records the version of type detection that checked it (`sniff_version`, `sniff::VERSION`). A
     release that teaches `sniff` a format bumps it, and the `retype` sweep the scheduler queues once per version
     checks again the standard libraries' assets with no media kind from an older version: one that is media now
     gets its metadata, capture time and media kind on the same asset id, what a user wrote kept, and renders through
     the reconciler; any other is dated by its name as in (a).
4. **Groups**, per batch: a Live Photo's still and video (the kernel's `PairLivePhotos`), and a RAW with the camera's
   JPEG or HEIC of the same folder, name up to the first dot, camera and second are one asset (`original` with
   `live_motion` or `original_alt`). A motion photo's video is a `motion_extracted` file: its original's key with a
   `byte_offset`, size and BLAKE3. Burst members stay assets with the facet `burst_member` and their `burst_id`.
5. **Commit**, in the job's transaction: the asset with the kernel's fields, its files, version v0 as the current one,
   the deletion of its uploads, and the derivatives the render profile wants (`reconcile::assets`).
6. **ExifTool** dumps each photo's or video's original into `raw_metadata`: one sandboxed process per running job,
   reading only its own directory, where ingest hard-links the file under a random name. A failure, or a dump over
   ADR-0024's 1 MiB, costs the dump only.
7. **Hostile text.** Names, EXIF, XMP and dumps are stored verbatim as data, and no name reaches a command line, nor a
   storage key but as a name the storage template cleans (ADR-0089). Every photolibd response says
   `X-Content-Type-Options: nosniff` and `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; sandbox`,
   so no browser renders one.

## Consequences

* The corpus ingests with exactly the fields a client's kernel extracts, and its Live Photo and RAW+JPEG pairs and
  motion photos group as its golden records say.
* ⚠️ Until M2-21, each upload is its own batch: a Live Photo or RAW+JPEG pair sent as two uploads is two assets.
* ⚠️ RAW+JPEG pairing runs on the server only; standalone clients need it in the kernel with vectors (follow-up).
* ⚠️ Name-family bursts, camera auxiliary files, lens pairs and edited variants are not grouped yet (M3-06, M2-27).
* ⚠️ A page served later (the viewer, link previews) needs its own CSP and must encode the text it shows.
* The app lists other files under Collections › Other files, the replica's assets without a media kind, and on
  desktops and in browsers downloads each from `/media`; ⚠️ phones cannot save one yet.
* An external library records them as unsupported `library_files`, not as assets (ADR-0093); the first `retype` job
  of each version queues their ingest again.

## Options considered

* **Ingest in the API process**: parses untrusted media where the sessions are (design 08 §8).
* **A contiguous head for the resolver**: a movie's `moov` or a HEIC's EXIF can sit gigabytes in; ranges cost no read.
* **QuickTime dates mapped by each host**: every client would repeat the make rule, and would drift.
* **Refusing unsupported uploads**: the bytes are verified and acknowledged already, and a backup drops nothing.
* **One ExifTool reading the work directory**: a compromised ExifTool could read other users' staged uploads.
