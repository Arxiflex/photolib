# ADR-0020 — The media test corpus starts as a generated, in-tree synthetic corpus of decodable files

* **Status**: Accepted — 2026-10-15, owner decision on photolib-design#267 (roadmap M0-28),
  with one change: the payloads must be decodable, not grey placeholders. On the choices that change made
  (photolib-design#287)
  the owner confirmed Pillow in the gate and left the rest to the implementer, so they stand as written below.
* **Requirements**: R-APP-5, F-09, FMT-21. **Design**: 19, 08, 13 §4.

## Context

The roadmap describes the corpus as licence-clean real files in a separate Git LFS repository. A work item cannot
create that repository, no real photo may be committed (AGENTS.md), and every fixture must be redistributable under
the project licence (ADR-0013), which real captures from many devices make a per-file question. A corpus whose
images all render as the same grey leaves nothing to test for thumbnails, previews, orientation or HDR, and nothing
to see in review.

## Decision

We will generate the corpus from stdlib-only Python (`tools/corpus/`) and commit the output under `testdata/corpus/`:
files with real structure and metadata, plus a golden record each (`golden.schema.json`). Records carry
`origin: synthetic`; `origin: real` is reserved for the LFS corpus, which can be added later without a schema change.

Every still image is decodable and shows a distinct picture: colour bars under a black band with the case name, on
a 16-pixel grid, so it compresses to almost nothing and a flip or rotation is visible; rasters whose case is not about
their size are drawn at 160×120 so the name fits, with the record and EXIF to match. The generator encodes it
itself, in integer arithmetic, so the output stays byte-for-byte deterministic and `build.py --check` stays:

* JPEG (baseline, progressive, YCCK, MPF and Ultra HDR secondaries, gain and depth maps), PNG and APNG, GIF, BMP,
  WebP (VP8, VP8L, alpha, animation), TIFF, BigTIFF, DNG, PSD and PSB, and SVG decode.
* Camera RAW files embed a decodable JPEG preview; their sensor data is a placeholder (a greyscale picture in the
  TIFF-based ones, which a TIFF reader decodes). The JPEG XL and ProRAW DNGs decode only through their previews, as
  their raw data is what the case is about.
* Motion JPEG video (AVI and QuickTime) decodes. HEIC, AVIF, JPEG XL and video in other codecs keep placeholder
  payloads, as no stdlib encoder for them is reasonable; their records' `notes` say so.
* Files whose quirk is broken data (truncated, garbage, wrong extension) stay broken exactly as the quirk requires.

The gate proves it: `tools/tests/corpus_decode.py` decodes every file meant to be decodable with a pinned Pillow
(installed from PyPI into a cache once, like the documentation's MkDocs) and checks its size against the record.

## Consequences

* Small (under 10 MB), deterministic, reviewable, and free of licence and privacy questions; CI checks it with the
  gate. Thumbnail, preview, orientation and HDR gain-map code can be tested on real pixels.
* The VP8 encoder carries the token probability tables of RFC 6386, which every VP8 implementation shares.
* Expected capture times are the author's reading of the design documents, and the pictures are synthetic: real
  captures remain needed for codec and device-quirk coverage, through the LFS corpus of the "Both" option below.
* If the corpus moves to an LFS repository: move `testdata/corpus/files/` there and keep the schema, validator and
  generator as the contract and the source of the structural cases.

## Options considered

* **Separate Git LFS repository of real captures only**, as the roadmap says: needs a repository and per-file licence
  provenance that a work item cannot provide, and its expected values could not be checked by the gate here.
* **Both**: synthetic structural cases here, real captures in LFS later. This ADR is its first half.
* **Structure only, grey placeholder payloads** (the first version of this ADR): rejected by the owner.
