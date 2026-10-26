# ADR-0098 — Frame budgets against an idle isolate

* **Status**: **Proposed — owner to confirm** (photolib-design#383).
* **Requirements**: NFR-PERF-1. **Design**: 19 §3, [ADR-0072](0072-device-metadata-extraction.md),
  [ADR-0082](0082-web-folders.md).

## Context

The gate's frame budgets count the 60 Hz frames that the calling isolate misses while work runs elsewhere:
`photolib_workers`' 2 GiB hash in the VM and in Chrome and Firefox, and `photolib_data`'s extraction, PhotoKit index
and browser folder scan. They are meant to catch work on the UI isolate. On the shared gate machine (16 cores, load
average 30–90), an idle isolate misses 0–8% of its frames, and the work raises that for every thread of the process.
On this machine, a 2 GiB pool hash missed 8.0% of the frames, with 0.0% idle just before and 7.7% on an idle isolate
meanwhile. Judged against the idle span just before alone, the work added 1.4–3.0% at load average 75–90 and failed
the gate.

## Decision

We will judge every frame budget with `withinFrameBudget` of `package:photolib_workers/testing.dart`:

* It counts the frames this isolate misses in a 5 s idle span just before the work and while the work runs. For the
  1 ms timer, it also counts the frames an idle isolate of the same process misses meanwhile (a Web Worker on the web).
* The work adds its share minus the larger idle share, and fails when that is over the budget (1% by default).
* When an idle isolate misses more than the budget, the budget rises to that share, because finer differences belong
  to the machine. The verdict says so, with the load average (VM) or the core count (browsers). Work that blocks the
  isolate still fails: a synchronous 16 MiB hash adds 79–97%.
* It tries up to three times, each after an idle span of its own, because load comes in bursts.

## Consequences

* On a busy machine, the gate passes work that runs off the UI isolate and still fails work that blocks it. A small
  regression fails only on a quiet machine, and the log names the raised budget.
* The VM's idle isolate shares the isolate group (`Isolate.spawn`), so the work is not charged for the group's garbage
  collection pauses, which stop every isolate. A Web Worker has a heap of its own.
* Animation frames (Chrome) have only the idle span just before: no worker draws them.
* The perf part's janky budgets time the frames that the work itself draws. An idle app draws none, so they follow
  [ADR-0140](0140-jank-budgets-against-an-idle-isolate.md): retries, and an idle isolate's share subtracted, never a
  raised budget.

## Options considered

* **The idle span just before alone**: failed the gate under load (above).
* **Failing at the budget however busy the machine**: this charges the machine's misses to the work.
* **Skipping the budget on a busy machine**: this misses work that blocks the UI isolate.
* **An idle isolate in another group** (`Isolate.spawnUri`): under `flutter test`, it cannot prepare the child
  isolate.
* **Per-thread CPU time** (`/proc/thread-self/schedstat`): available in the VM only, and isolates move between
  threads.
