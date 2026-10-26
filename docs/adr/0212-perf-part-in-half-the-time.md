# ADR-0212 — The perf part in half the time: setup beside the server, a timing again only over budget

* **Status**: Accepted — 2026-10-21. The owner confirmed both decisions
  (photolib-design#608,
  the provisional choices of photolib-design#545): the full fixture set runs on every train round, which never skips
  the perf part, and a timing is measured again only while it is over budget, the best of the samples taken counting.
* **Requirements**: NFR-PERF-1. **Design**: 19 §3. Amends [ADR-0048](0048-performance-harness.md)'s
  "fastest of three" and extends [ADR-0140](0140-jank-budgets-against-an-idle-isolate.md)'s retries to timings.

## Context

The merge train runs `tools/perf/run.sh` on every round, with every other run frozen: 21 min median on 2026-10-20,
15–16 min on the quiet rounds since. A profile of a quiet round (2026-10-21 03:12) and of runs on this machine
([performance](../dev/performance.md#run-time)) found the time in waits and repeats that measure nothing:

* 2 s before and after each sampled action, flushing frame timings that a profile build reports every 100 ms;
* every scrub counted the 1M assets' days anew (89 s of the 1M fixture's 168 s here);
* fixed repeats whose best counts: three passes per viewer open, month and video set, five 360° windows, though the
  first is within budget nearly always;
* the idle CPU scanned its 100k-file folder beside the app over 1M assets, seven times slower than first: the app
  refreshed its timeline at each directory the scan committed (photolib-design#609);
* the server's benchmarks, their release builds and the app's preparation ran one after another, and the app's
  benchmarks were compiled anew each run, as a define held the run's temporary directory.

## Decision

We will:

* **Measure a timing again only while it is over its budget**, up to the samples its `how` names, the best counting
  (`bestOf` in `app/benchmark/jank.dart`): viewer opens and scrubs (three), 360° windows (five), as ADR-0140 now
  retries video passes. Pass or fail is that of the fixed count: the best of the samples taken is within budget
  exactly when the best of all would be.
* **Keep the frames whose vsync falls within the action**, after 0.5 s of rest, waiting 0.5 s for the last timings.
* **Reuse the timeline's day counts** for a scrub's fresh pages, as nothing changes them.
* **Scan the idle CPU's folder before its fixture loads**; the measurement starts as before, 5 s after the app's
  cells show.
* **Run the server's benchmarks and the 360° clip's encoding beside the app's idle CPU**: ingest counts CPU time
  calibrated against the load (ADR-0121), sync is far within its budget, memory is no time, and the idle CPU is its
  own process's CPU time. The app's frame-timed benchmarks and its cold start run alone after them.
* **Keep the app's builds alike from run to run**: the fixtures reach the apps in `PERF_FIXTURES` from the
  environment, so Flutter reuses an unchanged app's build; cargo already reuses the release builds.
* **Say where the time goes**: `run.sh` ends with each step's time, `perf.py watch` prints each test's.
* **Keep the full set of fixtures every round** (the owner's rule): it fits the half without a split. The split the
  issue asks to weigh is in the [run time](../dev/performance.md#run-time) table, for a nightly run if rounds grow.

## Consequences

* A round measures every budget in about half the time; the train's three quiet rounds confirm the figure.
* A recorded timing is the best of the samples taken, often one: on a reference machine's history it varies a little
  more than the best of three did.
* A server benchmark that fails is reported after the idle CPU, with its log.

## Options considered

* **A smaller fixture set on the train, the full one nightly**: the 1M fixture alone costs about a minute of the app's
  benchmarks and a third of the idle CPU; not needed for the half, and the owner's rule is the full set.
* **Running the app's builds beside its idle CPU** (copying the bundle it runs from): saves up to a minute more when
  the app changed, at the cost of a launcher per desktop.
* **Fewer samples always**: faster, but a busy round would fail a budget a second sample passes.
* **Skipping on `headless` the folder's scrolls that only time tiles** (its cold 1x, 3x and fling and its warm fling,
  about 40 s): ADR-0114, as the owner accepted it, has `headless` print those latencies.
