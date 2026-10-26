# ADR-0140 — Jank budgets against an idle isolate, retries, and reruns of what failed

* **Status**: Accepted — 2026-10-20. The owner changed the provisional decision
  (photolib-design#533):
  retries, the idle share subtracted only, never a raised budget.
* **Requirements**: NFR-PERF-1, M1-10. **Design**: 19 §3. Amends what
  [ADR-0121](0121-calibrated-throughput-budgets.md) left as it was: the app's janky budgets were not calibrated.

## Context

The app's janky budgets (`timeline-scroll`, `drag-select-5k`, `folder-scroll`) count the frames whose build or raster
takes longer than the display's frame. On the shared gate machine a frame is also late when its thread waits for a
core: the merge train missed them about one round in thirty (folder-scroll `cold_janky` 1.18 %, drag-select 1.11 %).
The gate then ran `tools/perf/run.sh` again whole, so a rerun forced by one budget could fail on another (2026-10-19
02:13: ingest-throughput, then folder-scroll on the rerun).

## Decision

* A janky sample over its budget is measured again, up to five attempts in all, each after 5 s of rest as
  `withinFrameBudget` does (ADR-0098), and the least janky counts (`app/benchmark/jank.dart`); drag-select's drags
  are its attempts, video-swipe's passes through eight videos too (its first_frame the fastest of them).
  Folder-scroll's cold sample starts each attempt over an empty disk cache, video-swipe's over a set of videos not
  yet shown. A sample within its budget is measured once.
* Beside each sample the app counts the 60 Hz frames an idle isolate of the app misses meanwhile (`countIdleFrames`).
  The figure checked, and the one "least janky" goes by, is the janky share less that share, never below 0, against
  the unchanged budget (1 %), which never rises to the idle share. `perf.py` prints the raw share, the idle one and the
  attempts.
* A sample that passes only on a retry or on the idle credit is marked in the history (`passed_on`), which the
  dashboard shows.
* A failure never fails more than what failed: run.sh writes the series that failed or are missing to `$PERF_FAILED`
  (the gate sets it), and the gate's rerun measures and checks those alone (their server benchmark, the app's tests of
  their fixtures with `PERF_TESTS`, or the cold start) while the other series' results stand. The gate never reruns the
  whole perf part or the whole check for a jank miss.

## Consequences

* On a quiet machine an idle isolate misses nothing and the first attempt passes: the budgets cost and fail as before.
  The train's misses, marginal and rare, pass on a retry.
* On a machine loaded throughout, the app is charged only what it adds, against 1 %: a regression cannot hide behind
  the idle share.
* A miss costs up to four more samples, each after its rest, before the gate reruns that series alone.
* The idle isolate is in the app's isolate group: a garbage collection pause that stops every isolate is not charged
  to the app's frames, as in ADR-0098.

## Options considered

* **Raising the budget to the idle share as well** (the provisional decision, ADR-0098's rule): a sample passed at
  twice the idle share, up to about 16 % raw jank on the gate machine, which hides a real regression behind a 1 %
  budget. ADR-0098 keeps its raise: its budgets guard blocking work that adds 79–97 %, where the margin is harmless.
* **A wider budget**: hides a real 1 % regression on a quiet machine.
* **The CPU-time reference of ADR-0121**: a frame is late for want of a core, which CPU time does not see.
* **Rerunning everything, checking only what failed**: correct, but the whole benchmark takes minutes more per rerun.
