# ADR-0022 — Object-store backends for managed data

* **Status**: **Proposed** — owner to confirm.
* **Requirements**: R-MODE-2, R-REL-1, NFR-PORT-1; feature `LIB-12`. **Design**: 07
  §3, §6, §8, 08 §4.5, §5.4, §8.1,
  15 §6. Extends ADR-0009.

## Context

ADR-0009 routes storage through `BlobStore` (own filesystem driver, OpenDAL for object stores). It leaves open which data
may live in a bucket, how stores are configured, and how filesystem-shaped rules work without a filesystem: atomic
rename on upload commit, sandboxed workers reading local files, `sendfile` serving, re-hash scrubbing and trash.

Evidence: Immich declined other backends ([D1683](https://github.com/immich-app/immich/discussions/1683), 210↑) and now
lists six refactors it needs first ([D23745](https://github.com/immich-app/immich/discussions/23745)). Lychee took five
years. FUSE/rclone mounts render blank tiles ([HG#116](https://github.com/xemle/home-gallery/issues/116)). Ente's
presigned URLs, which must be publicly reachable and need CORS, are its largest self-hosting complaint (147 threads,
analysis).
The development store, Garage ([ADR-0018](0018-dev-s3-store.md)), has no object versioning or object lock.

## Decision

1. **Scope.** Any managed data may live on an object store: standard and private originals, edit material, manifests,
   derived renditions, stored HLS rungs and database dumps. External libraries stay POSIX (local, NFS, SMB) in 1.0.
   Upload staging, job scratch and the HLS segment cache are always local. S3-compatible storage is the supported
   object backend in 1.0; other OpenDAL backends join when they pass the same conformance suite (point 7).
2. **Stores and placement.** The YAML server configuration ([ADR-0021][adr21]) names stores; `local`, the data
   directory, always exists. Secrets come from `PHOTOLIB_*` variables, e.g. `PHOTOLIB_STORES__B2__SECRET_ACCESS_KEY`.

   ```yaml
   stores:
     b2:
       kind: s3
       endpoint: https://s3.eu-central-003.backblazeb2.com
       bucket: photolib
       prefix: home/          # optional
       access_key_id: 0035c…
   placement:
     libraries: b2            # new managed libraries
     derived: local
     backups: local
   ```

   Every store keeps the layout of 07 §3 under its root or prefix. An object store
   holds `.photolib/store.json` with the instance id and its store id, checked against the database like the
   instance marker. A missing or mismatching marker, or a non-empty prefix without one, makes the store `offline`:
   its libraries change nothing and the rest of the server runs, so a wrong bucket or endpoint never looks like mass
   deletion or adopts a stranger's data. A library records its store at creation; only the explicit re-layout job
   moves it to another store (copy, verify BLAKE3, switch in one transaction, delete the source after a 7-day grace).
3. **Writes.** Uploads are staged in `work_dir` on local disk (ADR-0021 refuses a network filesystem there). On an
   object store, step 2 of the intent log is: reserve the key in the database (unique per store) → one PUT up to
   64 MiB, multipart above → the BLAKE3 hash and
   size stored as object metadata → a HEAD verifies both. An object is all or nothing and a multipart upload is
   invisible until completed, so this replaces write-fsync-rename. Keys are never overwritten, and an upload is
   acknowledged only after the verified write.
   * *Recovery* HEADs the reserved key: complete and matching → finish the intent; missing → write again from staging,
     or roll back if staging is gone (the client was never acknowledged and resends). Multipart uploads older than
     24 h under the store's prefix are aborted.
   * *Moves* (re-layout, store moves) are copy → verify → switch → delete.
   * *Deletes* happen only when trash is emptied or its retention ends, through the intent log. Nothing relies on
     bucket versioning or object lock; a bucket that has them works unchanged.
   * *Orphans*: objects with no row and no open intent are reported, never deleted on inference.
4. **Reads for processing.** Sandboxed children never get network access or store credentials. `BlobStore::local(key)`
   returns the file itself on a filesystem store. On an object store it downloads into the job's scratch directory,
   hashing on the way, and the child gets that file; a mismatch fails the job and records an integrity finding.
   A job reads its input once. Ingest uses the staged upload while it exists, so new uploads are never downloaded
   back. Jobs wait for scratch space through the resource governor. HLS sessions keep their source in a local cache
   that shares the segment cache's budget.
5. **Serving.** Object-store media is streamed through the API with Range passed on, under the same authorisation and
   headers as local files. No media URL points at the store, so nothing depends on its reachability or CORS, and the
   server's uplink carries the same bytes it would for local files. Presigned redirects for originals and video
   (opt-in, after an HTTPS and CORS check, with client fallback to the API) wait for the large-deployment work that
   also brings presigned uploads (03 §10).
6. **Integrity.** On an object store the routine scrub cycle checks every original's presence, size and stored hash
   with HEAD requests and lists the prefix for orphans; neither downloads content. A full re-hash is opt-in per store
   with a monthly egress budget: re-hashing 2 TB every 90 days downloads about 8 TB a year, about $700 at AWS's
   $0.09/GB. Every full read (processing, proxied downloads) verifies the hash.
7. **Conformance.** One `BlobStore` suite runs against the filesystem driver and Garage in CI: put, get, head and
   delete, range reads, multipart with abort, object metadata, server-side copy, prefix listing, read-after-write,
   crash injection at every intent step, and a black-holed endpoint that must time out. The S3 driver uses only the
   core object API (ADR-0018).

## Consequences

* ✅ One code path and one test suite cover local and object storage; nothing assumes a path on disk.
* ✅ A wrong config, a crash or a hung endpoint changes nothing: offline stores, intent recovery and timeouts.
* ⚠️ Object-store deployments still need local disk for staging, scratch and the segment cache, sized to concurrent
  uploads and jobs rather than to the library.
* ⚠️ Derived data stays local by default: a timeline loads hundreds of thumbnails and each object-store request costs
  tens of milliseconds. Put it on S3 only when several `api` nodes share it.
* ⚠️ Without a full re-hash, bit-rot on S3 is caught on read or by the provider, not by the scrubber.
* ⚠️ Originals in a bucket are not a backup; a second copy (bucket replication, rclone to another provider) stays the
  admin's job. Until at-rest encryption of standard libraries (`PRIV-31`) exists, the provider can read standard
  originals; private libraries hold only ciphertext.
* ⚠️ Signed S3 requests fail when the server clock is more than 15 minutes off; `photolibd doctor` compares it with the
  store's `Date` header.
* Work: M0-18 (driver, markers, `local()`, conformance), M2-07 (staging), M2-09 (serving), M2-11 (placement, store
  moves), M2-26 (deletes), M2-31 (dumps, recovery from a store), M2-32 (stores in the admin console and doctor),
  M2-33 (scrub), M2-34 (storage guide), M7-01 (source cache).

## Options considered

* **FUSE/rclone mounts instead of a driver**: slow, no atomic rename, hangs and blank tiles.
* **Presigned redirects by default**: Ente's experience; they break on LAN-only endpoints and without CORS, and a long
  video outlives the URL.
* **Content-addressed keys on object stores**: one layout everywhere keeps a bucket readable with plain tools, and
  originals never move implicitly, so template keys cost nothing.
* **Bucket versioning or object lock for trash and immutability**: Garage and many providers lack them.
* **Full re-hash by default**: egress cost.
* **Staging uploads in the bucket**: only useful with presigned uploads, which will stage under `staging/` and commit by
  server-side copy.

[adr21]: 0021-photolibd-startup-contract.md
