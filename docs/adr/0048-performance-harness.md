# ADR-0048 — Performance harness: budgets and instruction counts in the gate, timings on reference machines

* **Status**: Accepted — 2026-10-17. The owner answered the provisional choices of M0-27 in
  photolib-design#344: every gate keeps failing missed budgets, with frames on the
  `headless` target, and no reference machine or dashboard is chosen before the test phase. The owner added a
  regression check that does not depend on timing: instruction counts of the hot paths against the base, with their
  table in the pull request. On 2026-10-20 the owner accepted as made that a `perf-accept:` line may be in the pull
  request's description or a commit message, and that the gate writes the table to `$PERF_REPORT` for the driver to
  paste (photolib-design#449).
* **Requirements**: NFR-PERF-1, NFR-PERF-2, NFR-PERF-4. **Design**: 19 §3, 10 §3.7, §13.

## Context

Design 19 §3 makes the performance budgets CI gates, publishes the results per commit to a dashboard and fails a
regression over 10%. Design 10 §13 runs performance on physical devices only. Here the gate is the only check before
a merge; it runs on shared Linux machines and, after check-in, on GitHub runners, neither with a GPU, and the costly
workflows run rarely (photolib-design#294). On the 16-core gate machine at a load of 14 to 24, two runs of the same
commit differed 2.5× in raster time per frame (one-day-50k: 3.9 ms and 10.6 ms at the median) and a scrub took 53 ms
in one run and 129 ms in the next.

## Decision

We will encode every budget of 19 §3 in `tools/perf/budgets.json`, pinned to the design by a test: each one names
what measures it or the roadmap item that will. `tools/perf/run.sh` measures what the machine can, and the gate's
`perf` part runs it, failing any missed budget or missing measurement.

On Linux without a display the app runs under Xvfb as the `headless` target, whose frames count the UI thread only:
its raster thread is a software GPU. A scrub takes the fastest of three tries, as other load only adds time.

The 10% rule applies to CPU instructions, which Callgrind counts the same however loaded the machine is. The hot
paths of the kernel and the server have benchmarks (`benches/instructions.rs`, on `tools/perf/harness.rs`), each
counted on its second run so that what setup left in the allocator does not move the count. The `perf` part runs
`tools/perf/instructions.sh`: it counts them on the branch and on its merge base with `origin/main` and fails a
benchmark with more than 10% more instructions, unless a `perf-accept: <reason>` line in the pull request says why:
in its description (`$PR_BODY`) or in one of its commit messages, as an agent's pull request has its description
written only after the gate. The gate prints the base-against-branch table and writes it to `$PERF_REPORT`, for the
pull request's description; no history is stored. valgrind is in the gate machine's toolchain directory and in CI.

Timed regressions (frames, seeks, cold start) get the 10% rule only on a quiet reference machine, from the test
phase: with a history (`PERF_HISTORY`, outside the repository) it records results per commit, fails a regression over
10% against the median of its last five, and renders the dashboard, one static HTML page per machine. None is chosen
yet.

## Consequences

* Every gate run measures the server, the seven pathological fixtures and the cold start, about 9 minutes, and
  counts the instructions of the branch and its base; the base's benchmarks are rebuilt whenever it moves (about
  4 minutes on the loaded gate machine). The gate job installs the Linux desktop toolchain, Xvfb and valgrind.
* A slower hot path fails the gate even within its budget, and an intended one carries its reason into the history.
  Instruction counts miss what a CPU does not count: I/O, the GPU, cache misses and contention; those wait for the
  reference machine.
* Frame budgets on real GPUs, phones (M10-02) and the web (M2-25) wait for those machines and items.

## Options considered

* **The 10% rule on timings in every gate**: fails at random on shared machines, as measured above.
* **A history in the repository or a hosted dashboard** (a benchmark service, or a workflow pushing results to GitHub
  Pages): parallel pull requests would conflict on a history file, and a service or new workflow needs an ADR and the
  owner; GitHub runners are as noisy as the gate's machines. Each pull request carries its own table instead.
* **iai-callgrind** for the instruction counts: a dependency and a runner binary of the same version to install, for
  what a 40-line harness and Callgrind's `--toggle-collect` do.
