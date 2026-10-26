# Flaky tests

A flaky test fails on some runs of unchanged code. The gate retries a failing test (`CHECK_RETRIES`, `retry:` in
`dart_test.yaml`, `cargo nextest --retries`), which hides it, so every run below has the retries off. Measured on an
18-core aarch64 machine shared with other work (load average 20 to 45), which is the way to provoke a race.

## The guard

`tools/repeat.sh [-n N] <test file>...` runs the tests of those files N times (10 by default, `REPEAT_N`) with every
retry off (it sets `retry: 0` in the package's `dart_test.yaml` for the run and puts it back) and fails on the first
failure (`-k` counts them all). `--since <rev>` takes the test files a diff adds or changes, `-- <command>` repeats any
command, `--list` prints what would run. `bash tools/check.sh --since <rev>` runs it after its parts, alone
(`CHECK_REPEAT=<n>`, 0 skips it); the full gate has no diff and keeps its retries as the safety net.
`tools/tests/test_repeat.sh` tests it. Two runs in one package at once break each other (a second `flutter test` in the
same directory rebuilds the native assets under the first: one `flutter_tester` died that way while this report was
made), so run one at a time per package.

To find a flake: run the suite with the retries off and in random order (`flutter test --test-randomize-ordering-seed
random`), beside a busy machine, and as a small machine (`taskset -c 0-3`; Dart's `Platform.numberOfProcessors` ignores
it, so a test that depends on the core count needs the count forced, see the first flake).

## Flaky tests found

| Test | Root cause | Red | Fix |
|---|---|---|---|
| `thumbnails_test` "at most two videos decode at once" | `Thumbnails` decodes `cores - 1` at once by default and the test assumed four slots. The gate's runners have four cores, three slots: it saw `[1, 2, 3]` for `[1, 2, 3, 4]` | core count forced to 4: fails with `[1, 2, 3]`, as in the CI logs of three queue runs | the test passes `concurrency: 4` |
| `viewer_page_test` "a slow decode keeps the filmstrip responsive" | the same: with one slot (two cores) the one slow decode held it | forced to 2 cores: fails | the test passes `concurrency: 4` |
| `hdr_raw_test` "a RAW shows its largest embedded preview at once" | the same, for the library page's `Thumbnails`, which the test cannot construct | forced to 2 cores: fails | `Thumbnails.processors` (`@visibleForTesting`) names the cores the default counts; the tests set five |
| `library_page_test` "a thumbnail that fails is logged with its file and cause" | one id counter shared by the tests, and the test expects `/p/1.jpg`: it fails when another test ran first | `--test-randomize-ordering-seed=3979790993` and `=1866084505` | `setUp` resets the counter |

The first three were tagged `flaky` and ran in an advisory lane; the tag is gone from `app/dart_test.yaml`.

## Not flaky, not in scope

* The kernel's `vectors_test` and `web_vectors_test` budget tests (tag renamed from `flaky` to `timing`, still an
  advisory step): they check decrypt throughput (1024 MiB/s) and call latency against budgets. On this machine 8 of 10
  runs miss the decrypt budget (about 1000 MiB/s). That is a performance budget, not an unstable test.
* `store_cost_test` "meets its budgets" is tagged `alone`: a frame/cost budget, perf. The two pure tests of the file
  pass.
* Performance is out of scope: `tools/perf/`, the `budget` step, frame-budget tests tagged `alone`, instruction-count
  benches. None is touched.
* Needing tools this machine lacks, and failing every run, are not flakes: `docker` (compose, devstack, nas,
  observability tests), `gnome-keyring-daemon` (`test_perf`), gitleaks findings (`test_secrets`).

## Candidates that did not reproduce

* `harness_test` stalled once in a local run. Here: 10 runs alone, and inside 4 full suite runs, all pass (its Chrome
  child needs `CHROME_EXECUTABLE`). It spawns `flutter test` in the app directory with no timeout, by design
  (`untimed`); a second `flutter test` in that directory is the one hazard found (above).
* `test_check_sh.sh` failed once in the parallel `check.sh repo`. Here: 10 runs alone under load and 3 runs of
  `check.sh repo` as CI runs it (four cores, four jobs, no retries) pass. It reads `CORES` from the environment (its
  `getconf` stub), so an exported `CORES` fails it: not a CI cause.

## Detection runs (retries off)

| Suite | Runs | Result |
|---|---|---|
| App, whole (`flutter test -j 4`, random order) | 3 | `library_page_test` (order) twice; the rest environment (no Chrome or LGPL ffmpeg on `PATH`, `photolibd` build) |
| App, whole, after the fixes (`-j 8`, random order, live and harness tests included) | 4 | 0 failures |
| App as 2, 4 and 8 cores (core count forced) | 1 each | 2: the three tagged tests; 4: `thumbnails_test`; 8: none |
| Dart packages, VM (api, data, editor, harness, kernel, log, ml, video, workers; not `alone`, `timing`) | 3 each | 0 failures |
| Dart in Chrome, dart2js and dart2wasm (`web_test.dart` of api, workers; data, ml, editor; the app's log and sphere) | 3 to 5 each | 0 failures |
| Rust kernel (`nextest --retries 0`, 88 tests) | 6 (3 on four cores) | 0 failures |
| Rust server (664 tests, 9 `#[ignore]`d) | 3 | 0 failures (304 to 370 s) |
| Rust server passkeys (ignored, Chrome and Node) | 10 | 0 failures |
| Rust `tools/synthlib` (17 tests) | 3 | 0 failures |
| Node `viewer` (`npm test`) | 20 | 0 failures |
| `tools/tests/test_*.sh` four at a time | 3 rounds | only the environment failures above |
| `check.sh repo`, four cores, four jobs | 3 | only the environment failures above |
| CI history (`gh run list`, 32 runs of the queue) | all | the three failed `dart-app` jobs: `thumbnails_test` `[1, 2, 3]` (and the repo's own lint tests on map code, not flakes); every passed run's advisory lane failed on the same tests |

## After the fixes (10 consecutive runs)

| Selection | Command | Result |
|---|---|---|
| the four tests' files, alone | `tools/repeat.sh -n 10 app/test/features/library/timeline/thumbnails_test.dart app/test/features/viewer/viewer_page_test.dart app/test/features/viewer/hdr_raw_test.dart app/test/features/library/library_page_test.dart` | 10 passed |
| the three core-count tests, machine forced to 2 cores | the same with the default core count forced to 2 | 10 passed |
| their suites (`app/test/features/library` and `viewer`, 100 files), beside other work | `tools/repeat.sh -n 10 <those files>` | 10 passed |
| the whole app suite under load, random order | `flutter test -j 8 --test-randomize-ordering-seed random` | 4 passed |

## Status of every test that was tagged `flaky`, reported flaky, or hidden by a retry

| Test | Status | Evidence |
|---|---|---|
| `thumbnails_test` "at most two videos decode at once" | healed | red with 4 cores forced; 10/10 alone, 10/10 in its suite, 4/4 whole suite |
| `viewer_page_test` "a slow decode keeps the filmstrip responsive" | healed | red with 2 cores forced; same loops |
| `hdr_raw_test` "a RAW shows its largest embedded preview" | healed | red with 2 cores forced; same loops |
| `library_page_test` "a thumbnail that fails is logged" | healed | red with two shuffle seeds; 10/10 |
| `harness_test` (stalled once in a full run) | not reproduced, not flaky here | 10/10 alone, 4 whole-suite runs at `-j 8`, 3 earlier at `-j 4`, Chrome child included |
| `store_cost_test` (failed once at `-j 4`) | not a flake: its budget test is tagged `alone` (perf, out of scope); the two pure tests of the file pass | the package passes 3/3 with `alone` excluded |
| `test_check_sh.sh` (failed once in the parallel `check.sh repo`) | not reproduced | 10/10 alone under load 8 to 45; `check.sh repo` as CI (4 cores, 4 jobs, no retries) 3/3 |
| kernel `vectors_test`, `web_vectors_test` | perf budgets, not unstable (tag now `timing`) | 8 of 10 runs miss the decrypt budget on this aarch64 machine, every time on CI's runners |
| everything else the retries could hide | none found | every suite above ran with retries off, 3 to 20 times |

## Out of scope

Performance: `tools/perf/`, the `budget` step, frame-budget tests tagged `alone`, and instruction-count benches.
