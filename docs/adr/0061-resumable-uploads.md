# ADR-0061 — Resumable uploads: the IETF protocol on `/upload`, acknowledged after a verified write

* **Status**: Accepted — 2026-10-16. The owner confirmed all three choices M2-07 made: expiry a day after the last
  append, complete uploads under the library's `uploads/`, and the `Photolib-Library` and `Photolib-Hash` headers
  (photolib-design#345,
  which calls this ADR-0042, its number before renumbering).
* **Requirements**: R-MODE-2, NFR-REL-1. **Design**: 05 §6, §8, 16 §2,
  server stack §5.1, [ADR-0022](0022-object-store-backends.md) points 1 and 3.

## Context

Backups must pass reverse proxies and CDNs that cap a request (Cloudflare: 100 MB), survive network loss and never
acknowledge bytes the server could lose. The design picks the IETF resumable upload draft, which iOS speaks natively,
with BLAKE3 verified by the server, quotas, local staging and expiry, but leaves the wire details, where a complete
upload goes before ingest exists and how long uploads live to the implementation (M2-07).

## Decision

1. **Protocol.** photolibd implements draft-ietf-httpbis-resumable-upload-13 (interop version 10) on `/upload`:
   `OPTIONS` announces `Upload-Limit: max-append-size=33554432, max-age=86400`, `POST` creates an upload (content may
   come along, iOS sends the whole file), `HEAD` reports `Upload-Offset`, `PATCH` appends
   (`application/partial-upload`; `409` with the offset on a mismatch) and `DELETE` cancels an incomplete upload. The
   `Location` is relative (`upload/<id>`), so a server behind a path prefix works. No `104` interim responses: hyper
   cannot send them, so clients create with `Upload-Complete: ?0` first, as the draft's careful strategy does. Errors
   are photolibd's Connect errors (a code and a reason), with the draft's headers.
2. **Photolib's fields.** Creation names the library in `Photolib-Library` and the BLAKE3 of the bytes, lowercase
   hex, in `Photolib-Hash` (the draft has no digest; `Repr-Digest` has no BLAKE3). The length (`Upload-Length`, or the
   content of a complete creation) is reserved against the owner's quota at once: assets' `file_size_total` plus the
   lengths of their uploads; over it the creation gets `413` with `Upload-Limit: max-size=<what is left>` and
   `quota.exceeded`. Ingest deletes the upload when it records the asset, so nothing counts twice.
3. **Who.** Uploading needs a signed-in account that may contribute to the library; afterwards only the uploader
   reaches the upload, and only while they still may contribute (`photolib_authz::Resource::Upload`), so a demoted
   member cannot complete one. Anyone else's upload is `404`.
4. **Staging.** Bytes go to `<work_dir>/uploads/<id>` (local, ADR-0021), hashed as they arrive, and are fsynced and
   counted in the database before an append is acknowledged; bytes past the recorded offset are cut off by the next
   request. A request that breaks keeps what arrived; a new request to the same upload stops one in flight, which
   keeps what arrived first (draft §4.6). After a restart the hash is read again from the staged file.
5. **Acknowledgement.** The append that completes an upload is answered (`200`, `Upload-Complete: ?1`, the upload id,
   length and BLAKE3) only once the bytes have the announced hash and the journal (ADR-0041) has written them to the
   library's store (`libraries.store`, default `local`) under `libraries/<library>/uploads/<id>`: fsynced and renamed
   on a filesystem, a PUT verified by HEAD on an object store. A hash mismatch ends the upload (`400`,
   `upload.hash_mismatch`, `Upload-Complete: ?1`); a failed write answers `5xx` with `Upload-Complete: ?0`, and the
   client completes again from the staged copy. The staged copy stays for ingest to read (ADR-0022 point 4).
6. **Expiry.** An incomplete upload expires a day after its last append (design 05 §8); the API role deletes expired
   uploads and staged files without an upload every 15 minutes.
7. **Client.** The Dart client (`photolib_api`, every target) creates, then appends at most 8 MiB per request,
   resumes from `HEAD` after a broken or hung (two minutes) connection, a proxy's page, a `409` or a passing server
   error, up to five times in a row without progress (the offset `HEAD` reports moving, as the part of a cut append
   the server kept moves it), and halves its appends after a proxy's `413`, down to 64 KiB.
8. **Tests.** The server tests pin the wire exchange; one sends a large video through a 100 MB cap with a connection
   cut and one left hanging: 300 MB in the gate, 10 GB in the weekly `upload-large` job.

## Consequences

* ✅ Uploads pass Cloudflare's and nginx's default caps, resume after network loss and are acknowledged only once
  durable.
* ⚠️ Completed uploads stay under `uploads/` with their staged copy until ingest (M2-08) records them and moves them
  to their template path (M2-11); an upload that is never committed is kept until then.
* ⚠️ Staging is per process: several `api` replicas need sticky routing per upload until a shared staging exists.
* ⚠️ On a filesystem store, completing copies the staged file once; adopting it by a link is later work.
* ⚠️ Without `104` responses iOS cannot resume an upload whose creation request carried the file and broke; the app
  creates first. The iOS upload extension expects `104` too: a phone test decides whether `/upload` must send it
  (ADR-0049).

## Options considered

* **tus 1.0**: no native iOS support; an adapter can sit on the same staging later.
* **Presigned S3 multipart**: the server cannot verify plaintext before acknowledging, and the bucket must be
  reachable with CORS (ADR-0022 point 5).
* **Acknowledging after the staged fsync only**: the staging directory is scratch, and ADR-0022 requires a verified
  PUT on an object store.
* **Persisting BLAKE3 chaining values per 8 MiB** (server stack §5.3): no re-read after a restart, but more state;
  the hash stays in memory until restarts show it matters.
* **A week to expire** (server stack §5.9): design 05 says a day, and an active upload's day restarts with every
  append.
