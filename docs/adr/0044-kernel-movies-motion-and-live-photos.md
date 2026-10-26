# ADR-0044 — Kernel movies, motion photos and Live Photos: the host's file size, verified videos, a pairing call

* **Status**: Accepted — 2026-10-16. The owner confirmed all five choices M1-06 made: the host's file size, SEF
  trailers for Samsung cameras only, the Live Photo pairing, `mvhd` times without an offset and the amended corpus
  (photolib-design#339,
  which calls this ADR-0041, its number before renumbering).
* **Requirements**: R-APP-5, F-09. **Design**:
  media pipeline §3.3, §3.4, §7,
  import research §4.7, §4.8.

## Context

M1-06 extends `ReadMetadata` ([ADR-0036](0036-kernel-metadata-reader.md)) to ISOBMFF, QuickTime and AVI movies,
locates motion photos' videos and pairs Live Photos. The design fixes the signals, but not how the reader finds what
lies at the end of a file it sees in pieces, what a zone-less `mvhd` time is, nor where Live Photo pairing runs and
on which names and times.

## Decision

We will have hosts pass the file's size with its pieces. A motion photo's video is located from the end (Container
`Item:Length`, `MicroVideoOffset`), in HEIF's `mpvd` box or in Samsung's SEF trailer, which is read only for Samsung
cameras so that other JPEGs need no read of their tail; a place counts only once an `ftyp` box starts there.

We will return `mvhd`'s creation time without an offset, and none for 0: the resolver decides by make whether it is
UTC. Codecs use the corpus's names; HDR is the H.273 transfer number and a Dolby Vision flag.

We will pair Live Photos in a kernel call, `PairLivePhotos`, over paths, content identifiers, durations and capture
instants that the host takes from the resolver: equal identifiers first, else the same folder and name up to the
first dot, a clip of at most 4 s within 2 s, the closest first, never two different identifiers.

We will amend the corpus where the reader proved it wrong, in `tools/corpus`: the spherical videos' records get
their `pano`, and `video/dv.avi` is written at the 720×576 its record states.

## Consequences

* A host that knows only the head still gets every result in a few calls; one that omits the size gets no video.
* Stale markers, recompressed Takeout files and stripped videos yield no video instead of a broken player.
* Every client and the server pair alike; late arrivals (design doc 08 §3.4) stay with the host.

## Options considered

* **Scan the file for `ftyp`**: finds stale offsets' videos, but costs a whole-file read
  ([Aves #2125](https://github.com/deckerst/aves/issues/2125)).
* **Read every JPEG's tail for SEF**: one more call per JPEG; Samsung's motion photos carry its make.
* **Pair by file stem only**: `PXL_….MP.mp4` and `PXL_….jpg` differ in stem; the first dot covers both.
