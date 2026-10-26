# ADR-0246 — Server renditions in the thumbnail pipeline (T5): cached by ETag, pending tiles keep their ThumbHash

* **Status**: **Proposed — owner to confirm** (photolib-design#424).
* **Requirements**: R-APP-5, NFR-PERF-3. **Design**: docs/10 §3.4, docs/08 §4.1, §4.5,
  [ADR-0070](0070-thumbnail-caches.md), [ADR-0032](0032-one-network-stack.md).

## Context

Items of a server library have no file on the device: their tiles are the server's `thumb_s` (short side 256 px) and
`thumb_m` (720 px) WebP renditions, which photolibd serves at `/media/<asset>/<role>` with the file's hash as ETag,
`immutable` when the request names that hash (`?h=`), else `no-cache`, and an empty 404 while a rendition is not
rendered yet or the session may not see it. Sync brings each asset's ThumbHash and its renditions' hashes. The design
leaves open where the tiles are kept, how they are revalidated and what a cell shows while there is none; the
server's SSE hint of docs/08 §4.5 does not exist yet.

## Decision

We will make the server the pipeline's T5 tier, in `ThumbnailPipeline` beside the device's decoders:

* **By tier**: tiers 128 and 256 take `thumb_s`, 512 and 1024 `thumb_m`, decoded at the tier as other tiles are.
* **Through the session**: `mediaProvider` fetches with the signed-in server's network configuration and session,
  once an address has answered as the server's instance, as API calls do (MOB-16).
* **Kept in the disk cache (T2)** under the item's key (asset and current version) and tier, with the response's ETag
  before the tile, within the cache's bound; phones get the desktops' 1 GiB `DiskCache` for these tiles. A tile whose
  ETag is the hash the replica has is current and is read without the network; any other is revalidated with
  `If-None-Match`, and a 304 keeps it.
* **Pending**: a 404, a server out of reach or no session is `Pending`: the cell keeps its ThumbHash, unmarked, and
  `Thumbnails` asks again after 1 s, twice as long each time up to a minute, while the cell wants it. A scroll back to
  the cell asks at once.
* **The replica keeps the ThumbHash** sync brings for assets (schema 22).

## Consequences

* Phones and browsers get a server library's tiles without decoding originals; a warm screen comes from disk.
* Server tiles are sealed under the cache key as every T2 entry is (ADR-0070, docs/21 §3), on phones too.
* A rendition that never comes (a refused asset) is asked for once a minute while shown; the server's SSE hint, when it
  exists, can end the wait sooner.
* Private libraries' renditions (ciphertext, decrypted in a worker) and `preview` for the viewer are still to come.

## Options considered

* **Sealed tiles in the store (`VaultCache`, the web's)**: its list of entries is one object rewritten after each
  change, which at 1 GiB of tiles is megabytes a second while the user scrolls.
* **No disk cache on phones**: less on disk, but every screen fetched again, and the issue asks for T2.
* **Marking a pending tile as failed**: a broken-image mark on every cell of a library still rendering or offline.
* **The URL's hash as the only freshness check** (`?h=` and `immutable`): a tile cached before sync brought its hash
  would never be checked again.
