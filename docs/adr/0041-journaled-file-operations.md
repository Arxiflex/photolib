# ADR-0041 — Journaled file operations and the blob-store drivers

* **Status**: Accepted — 2026-10-16. The owner confirmed all three choices M0-18 made: rolling back complete planned
  puts, byte-exact keys and the 120 s call timeout
  (photolib-design#336,
  which calls this ADR-0037, its number before renumbering).
* **Requirements**: R-REL-1, NFR-REL-1. **Design**: 07 §6, [ADR-0022](0022-object-store-backends.md)
  points 3 and 7.

## Context

Design 07 §6 and ADR-0022 outline the intent log. Building it (M0-18) left open what recovery does with an operation
whose caller never recorded its rows, how several processes share recovery, which keys a store accepts and how a call
is bounded in time.

## Decision

1. **The caller switches.** A put, move or delete is *planned* (its key reserved by a unique index over open intents),
   its bytes written and verified, *switched* in the caller's transaction together with the caller's rows, then
   finished (the replaced object deleted). Recovery rolls back every planned intent and completes every switched one.
   A planned put is rolled back even when its object is complete: the client was never acknowledged and resends. This
   narrows ADR-0022's "complete and matching → finish the intent" until the upload pipeline (M2-07) can finish rows.
2. **Only what carries the intent's hash is deleted.** Rollback deletes an object only when its size and stored BLAKE3
   hash are the intent's, so a file a user put there is never touched. A move checks the copy against the caller's
   hash. The filesystem keeps the hash in the `user.photolib.blake3` xattr, S3 as `blake3` and `size` object metadata.
3. **Recovery per process.** Each process holds a PostgreSQL advisory lock that its intents name (`owner`). Recovery,
   at every start, takes over only intents whose lock is free, so the processes of a split deployment never roll back
   each other's running operations. It also aborts uploads older than a day.
4. **Keys are never normalised.** A key is a relative path of names (no empty, `.` or `..` name, no NUL, names up to
   255 bytes, 1024 in all); NFC and NFD spellings are different keys. The S3 driver refuses keys that start or end with
   whitespace, which OpenDAL trims, and lists with `encoding-type=url` through its own signed requests.
5. **Every call is bounded.** Each store runs its calls on its own runtime (2 workers, at most 16 blocking threads)
   with a per-call timeout: `timeout_secs` per object store (120 s by default), 120 s on the data directory.
6. **Tests.** The storage tests run the Garage release ADR-0018 pins (`tools/garage.sh`, checked against SHA-256s
   taken when it was pinned) and kill a child process with SIGKILL at every step of every operation.

## Consequences

* ✅ After a crash every object has its rows or is gone; the crash tests prove it on both drivers.
* ⚠️ A complete upload interrupted before its rows were written is deleted, and the client sends it again.
* ⚠️ A key with leading or trailing whitespace cannot live on an object store; a store move (M2-11) must rename it.
* ⚠️ On a filesystem without user xattrs files carry no hash: rollback leaves their objects for the scrub (M2-33).
* ⚠️ The first storage test run needs network to fetch Garage.

## Options considered

* **Recovery callbacks that finish planned puts**: nothing calls the journal yet; M2-07 adds one if it needs it.
* **Leases that expire instead of advisory locks**: a slow but live process would lose its operations.
* **Normalising names to NFC or folding case**: renames users' files and breaks round trips with other tools.
* **Raw S3 requests for everything**: ADR-0022 chose OpenDAL; only listing and multipart management bypass it.
