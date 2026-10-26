# ADR-0121 — Throughput budgets calibrated against a reference measured beside them

* **Status**: Accepted — 2026-10-20. The owner kept both decisions of photolib-design#451 as made, the reference
  beside each sample and no calibration of the app's wall-clock budgets by it
  (photolib-design#477). Read literally, the answer keeps what this ADR decided:
  [ADR-0140](0140-jank-budgets-against-an-idle-isolate.md), accepted on its own answer, since checks the janky shares
  against an idle isolate. On 2026-10-23 the owner kept the reading photolib-design#520 took
  (photolib-design#672):
  only this ADR records that answer, and [ADR-0098](0098-frame-budgets-against-an-idle-isolate.md), which it cited as
  an alternative, stays Proposed for its own question (photolib-design#383).
* **Requirements**: NFR-PERF-4. **Design**: 19 §3, 08 §9.

## Context

The merge train's check runs at priority, but the agents beside it still share its cores' caches, the memory bandwidth
and the package's power budget. `ingest-throughput`, CPU time of the fastest of three to ten rounds per photo, measured
21.4 photos/s/core on a quiet machine and 19.1 to 21.4 in the train's 32 runs of 2026-10-17 and 18, failing 9 of them
for items that never touched ingest. On the gate machine (16 cores, an Intel Core Ultra 7 356H) the same commit
measured 17.3 to 22.2 raw at load averages of 27 to 60: memory-bandwidth load (stress-ng `--stream` on every core)
slows it most, CPU-bound load (`--cpu`, `--matrix`) not at all.

## Decision

We will check a CPU-time throughput budget against a calibration measured in the same run. Before each sample the
benchmark runs a fixed reference on the same cores: for ingest, it hashes a seventh 12 MP JPEG with BLAKE3 and decodes
it at 1/4 to the mean of its pixels, the decode that is most of ingest's CPU time, allocating little so that no
allocator setting moves it. The budget is checked against the raw rate × the fastest reference of the run / `quiet`,
never less than the raw rate. `quiet` (`calibration` in `tools/perf/budgets.json`) is the reference's CPU time on the
reference machine at its quietest: the fastest seen under any load there, 29.2 ms, as a quieter machine is only faster.
So a quiet machine gets no credit and fails exactly where the raw check does. `perf.py` prints the calibrated figure,
the raw one and the load average. The benchmark's photos are made from fixed seeds, so runs compare.

The app's frame and latency budgets (cold start, scrub-to-month, timeline, folder and drag-select jank) stay as they
are: they are wall-clock, and what makes a frame late on a loaded machine is waiting for a core, which a reference's
CPU time does not see. The train's check passed all of them in 27 loaded rounds in a row from 2026-10-18 00:26 and in
58 of its 60 since 2026-10-16: drag-select's and folder-scroll's cold jank missed 1 % once each (1.11 %, 1.18 %); the
agents' own gates, at nice 19, miss them often, and the driver leaves those to the train.

## Consequences

* Under load the calibrated ingest figure moved ±4 % where the raw one moved ±10 %. Memory-bandwidth saturation slows
  ingest more than the reference: with `--stream` on every core the calibrated figure is about 5 % under the quiet
  one, and 7–10 % under the rate alone on a machine at a load of 50–60, where the calibration gave back about half of
  what the load took. A real slowdown still shows:
  `a_10_percent_slower_ingest_fails_the_calibrated_budget_on_a_saturated_machine` in `tests/renditions.rs`, run by
  hand as it saturates every core, fails a 10 % slower ingest path; it judges what the calibration gives back of the
  load, not whether the unchanged path meets the budget saturated, which is the machine's.
* `quiet` belongs to one machine. On another reference machine, set it to the fastest reference the benchmark prints
  there; a slower machine then gets credit for being slower, and a faster one none.
* Another throughput budget calibrates the same way, with a reference of its own kind of work.

## Options considered

* **A wider margin in the budget**: hides a real regression of that size on a quiet machine.
* **Hardware cycle counters** (`perf_event_open`): they discount a lower clock but not cache or memory contention, and
  containers, VMs and macOS often lack them.
* **The reference's ratio of wall to CPU time**: measures waiting for a core, which CPU time already excludes.
* **Ingest itself as the reference** (a frozen copy of the render path): it would move with every library and
  allocator change the real path makes, and doubles the benchmark's time.
