# ADR-0036 — Kernel metadata reader: byte ranges in, merged fields and raw date claims out, fuzzed in and out of the gate

* **Status**: Accepted — 2026-10-17. The owner answered the provisional choices of M1-05 in
  photolib-design#328:
  the ranged reads are confirmed; the gate's fuzzer stays and coverage-guided fuzzing runs beside it on the build
  machine; and a kernel panic must fail one file, never the app.
* **Requirements**: F-06, F-09, R-APP-3. **Design**:
  import §7,
  media pipeline §3.3,
  quality §1.

## Context

M1-05 needs pure-Rust parsers over host-supplied byte ranges for EXIF, XMP and IPTC IIM, tolerant of broken data and
fuzzed continuously. The design fixes what is read (doc 13 §7.1) and that embedded values follow MWG 2.0 (§7.2), but
not how a host hands over byte ranges, which values the reader merges and which it leaves to the resolver, nor how
fuzzing runs when CI never runs on pull requests and the gate builds on stable Rust only (`cargo-fuzz` needs nightly).

## Decision

We will expose one kernel function, `ReadMetadata`, that takes pieces of a file at their offsets and returns, besides
the metadata, the spans it needed but was not given (at most 16, each at most 4 MiB). A host starts with the file's
head, reads what is missing and calls again; following the spans gives the whole-file result. A host that holds the
whole file passes it as one piece; one that reads only forward (PhotoKit's `requestData`, an Android SAF stream)
opens the file again, or exports it to a temporary file, for a span behind it (M1-01, M1-02).

We will merge the non-time fields by MWG 2.0 inside the reader (EXIF first, IIM over XMP only when the IPTC digest no
longer matches, camera boilerplate counted as no description), and return every date as written, unchecked and
unrated, as a `CaptureTime` claim named by its tag. Plausibility, sentinels and zone validity stay with the resolver
(M1-07). Motion-photo video offsets, SEF trailers and video containers stay with M1-06; the reader returns the XMP
markers only.

We will fuzz in the gate: `kernel/tests/fuzz.rs` mutates every corpus file and every vector input, deterministically,
through `cargo test` on stable Rust, with `FUZZ_ROUNDS` and `FUZZ_SEED` for longer runs, and fails a file that makes
the reader hold more than 32 MiB beyond eight times its size. Beside the gate, `tools/kernel/fuzz.sh` runs
coverage-guided `cargo fuzz` (doc 19 §1) in the background on the build machine, as the refactor runs are: libFuzzer
targets in `kernel/fuzz`, a crate outside the kernel's workspace built with nightly Rust, over the same entry points
(`ReadMetadata` whole and in pieces, `ResolveCaptureTime`, the crypto readers), seeded from the corpus and the
vectors, on one core at the lowest priority with its memory capped. Each crash, out-of-memory or timeout is minimized
into `testdata/fuzz/<target>/`, which `fuzz.rs` replays through the same targets in every gate run, and printed for
the driver, which files a bug task for it. OSS-Fuzz follows once the repository is public.

We will keep a kernel panic to the call that panicked. Every C entry point (`kernel/ffi`) catches panics, which
cannot unwind into the app, and the call fails with `CALL_ERROR_CODE_PANIC` (kernel.panic); a stream that panicked
fails every later step the same way. WebAssembly cannot unwind: a panic traps the module, the web binding catches the
trap in JavaScript (`photolib_kernel_guard.js`, as dart2wasm cannot catch one), returns the same error and refuses
further calls on that instance, which the host loads again. The device indexer stores a file the kernel panicked on as
read with nothing read, so that only a change of the file sends it back; with no column to say it failed, the owner is
asked again whether one is wanted. The web indexer, which reads no files yet, must do the same and load the module
again. `PANIC_PROBE`, a method id that only panics, lets each binding test
this. What a catch cannot stop needs limits instead: TIFF IFDs are never walked as a chain (IFD0, its EXIF, GPS and
eight SubIFDs at most, 4,096 entries each), lengths a file declares are read as slices of what the host passed, never
allocated, and a HEIF item holds at most 4,096 extents and 4 MiB.

## Consequences

* Phones and browsers read metadata with the same code and the same ranged reads as the server; a sparse host needs a
  few calls per file, a host that passes 64 KiB usually one.
* Consumers get one value per field and need no MWG logic; sidecar and source-app reconciliation (§7.3) builds on it.
* The gate catches crashes on every change; the coverage-guided fuzzer finds deeper bugs between changes, and its
  finds become gate cases.
* A malformed file costs the app one failed file, not a crash on every indexing pass; on the web, an instance of the
  module and its keyrings, which the app opens again.

## Options considered

* **The host passes the whole file**: simple, but costs a 200 MB read for a motion photo's video
  ([Aves #2125](https://github.com/deckerst/aves/issues/2125)) and breaks streaming hosts.
* **Raw values per source, merged elsewhere**: every consumer would re-implement MWG; rejected for all but dates,
  which the resolver needs as separate claims.
* **`cargo-fuzz` in the gate**: needs a nightly toolchain and a time box whose findings vary between runs, which makes
  the only merge gate flaky.
* **`cargo-fuzz` in the weekly workflow, or OSS-Fuzz now**: the workflows are off to save Actions minutes, and
  OSS-Fuzz needs a public repository.
* **Panics caught by each host, as the server does**: a panic cannot unwind through a C function at all, so the app
  would abort before any host code ran.
