# ADR-0232 — Browsers read their folders' metadata in a data worker, a second client of the drift worker

* **Status**: **Proposed — owner to confirm** (roadmap M1-42).
* **Requirements**: R-MODE-1, R-APP-5, F-09. **Design**: 10 §1.5,
  10 §5.2,
  [ADR-0072](0072-device-metadata-extraction.md), [ADR-0082](0082-web-folders.md).

## Context

A Chrome folder library had no capture times, projections or facets: only native data isolates ran the
`MetadataExtractor`. Running it on the page, with only the kernel on pool workers, cost the page 4–6 % of its 60 Hz
frames on 10,000 files: finding 256 file handles left gaps of up to 0.1 s, and each chunk's queue query and batch
of 256 updates took 20–40 ms. Design 10 §1.5 gives browsers a data worker beside the drift worker.

## Decision

We will:

* Run the same `MetadataExtractor` and `Extract` as natively in the replica's data worker (`data_worker.js`), which
  the page starts with `extractMetadata` and steers with `extractFirst` and `reportDeviceHealth`, and stops before the
  replica closes, once the chunk being read is stored.
* Make it a second client of the replica's drift worker over a port the page hands both; the page relays table
  updates between its own client and the drift worker, so each side's queries see the other's writes.
* Read each file in a Web Worker of the workers package (`metadata_worker.js`, two of them): the kernel's module
  reads byte ranges of the `File` the data worker found through the folder's handle, and returns its responses, which
  the data worker turns into the row's values with the code native extraction uses.
* Forward the data worker's log to the page, under the page's policy.

## Consequences

* A folder's items get the desktops' capture times, projections, crops, stereo modes and facets; the browser test
  compares every corpus file with the native kernel's reading. 10,000 files take 9–27 s in Chrome here and cost the
  page no frames but an occasional pause of its own (about 0.3 s once, which the frame budget's second try passes).
* `tools/data/web.sh` compiles three workers; the data worker starts only when `extractMetadata` asks.
* Sync can move into the same data worker later; until then `syncReplica` refuses in browsers.

## Options considered

* **The extractor on the page, the kernel on pool workers**: the frame cost above.
* **The extractor inside the drift worker**: no relay, but the database worker would carry the replica's queries, the
  folders' handles and a pool, and every database the store opens would load them.
* **Nested only, no pool**: the data worker could call the kernel itself, one file at a time beside its queries.
