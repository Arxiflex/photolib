# Pre-queue check backtest

Would `tools/prequeue.sh` have prevented the red merge-queue runs of 2026-10-25? All 25 queue runs since 05:00 UTC
with a failed job (queue PRs #50 to #92) were replayed on the exact tree CI tested, with **`tools/prequeue.sh` of
`origin/ci/prequeue` b63d614 (1080 lines, sha256 `9e0ba16f...`)**: quick, default, and `--full` on the runs that need
it. The earlier draft (`~/workitem-progress/prequeue.sh.draft`, 410 lines, no `--full`) was replayed first; its
numbers are in the last column of the summary.

## Summary

A run is prevented only if every cause in it is a FAIL, not a warning. A = all 25 red runs. B = without the three runs
whose only causes are apt stalls or perf-instructions (#79, #81, #91), and ignoring those two causes in the others.

| Tier | Seconds (quiet) | Prevented A | Prevented B | Queue min saved A / B | Draft A / B |
|---|---|---|---|---|---|
| quick | 7-23 | 5 / 25 = 20% | 6 / 22 = 27% | 81 / 102 | 4 / 25, 5 / 22 |
| default | 37-56 | 13 / 25 = 52% | 14 / 22 = 64% | 257 / 278 | 10 / 25, 11 / 22 |
| full | 420 (budget) | 14 / 25 = 56% | 15 / 22 = 68% | 270 / 291 | none |

**All tiers are below the 80% target.** `full` is measured on the 7 runs where default fell short (#58, #72, #73, #75,
#77, #78, #87); it adds one run (#58, `native_test`) and one cause (#75's `settings_test`); for the other 18 runs it is
taken equal to default (*inferred*: full contains the default steps). By cause: of 59 causes the default tier flags 39
(35 of 37 code causes, 4 of 6 CI-state causes); it flags none of the 5 timing causes (janky, wall-clock), 8 apt
stalls, 2 perf-instructions or 1 conformance flake, and misses the face-portrait prefetch (#73, #75), `native_test`
and `servers_test`. **False positives are high**: 7 of 12 trees CI accepted FAIL in quick (6 in default), all on the
new `no wall-clock assertion` step (see "False-positive check"). Ranked gaps that would reach 80% and more are under
"Gaps".

## Method and honesty notes

* Tree = `headSha` of the run (Mergify's merge commit); all were fetchable by SHA. `PREQUEUE_BASE` = the dev SHA of
  the queue PR title, `PREQUEUE_NO_FETCH=1`, `PREQUEUE_NO_GH=1` (no PR title, no queued PRs),
  `PREQUEUE_OTHERS=origin/none/*` (today's `origin/wi/*` refs would be anachronistic), a fresh `git worktree` per run
  (cold build dirs, warm sccache/pub cache), `CARGO_HOME`, `RUSTUP_HOME`, `PHOTOLIB_TOOLS_CACHE` exported.
* Shared 18-core aarch64 container. The quick and default replays of all runs ran beside two other chains (seconds
  inflated, up to 10x; the run table shows them, the summary uses a quiet rerun of 8 runs: q50 7/37 s, q58 11/42 s,
  q63 12/42 s, q72 13/42 s, q77 13/42 s, q81 11/41 s, q83 14/56 s, q87 23/44 s). The `--full` runs hit the 420 s
  budget even on a quiet machine (`slow`/`skip` steps, see Gaps).
* Causes come from the job logs (`gh run view --job <id> --log`) and the workers' comments. Apt, timing and flake
  causes are *verified by log only*; "not flagged" is *verified by replay*; test runs in the same tree are *measured*;
  step ideas not run are *inferred*. A cause counts as flagged when a FAIL block of the script names it (regex per
  cause).
* No CI failure today was a number collision or a conflict (Mergify dequeues those): no claim about those steps.
* Excluded: 6 pure supersession cancels (#42, #53, #60, #61, #80, #84), `trial-N` branches, #93 (running). Minutes of
  a run = open time of its queue PR; the two parallel checks after 17:31 are counted separately.

## The red runs

PREV = prevented, part = partly, miss = missed. `FAIL ... miss` = the script fails, but not on CI's cause (mostly the
wall-clock step). Seconds as measured beside other chains (see Method).

| Q | PRs | min | Causes | Quick | Default |
|---|---|---|---|---|---|
| 50 | 49 | 20 | shellcheck baseline fell | FAIL 7s PREV | FAIL 37s PREV |
| 52 | 46 | 19 | cargo fmt; ADR-0116 guard test | FAIL 40s part | FAIL 48s PREV |
| 56 | 47 | 19 | newline, README 61, MD013, device pins | FAIL 36s part | FAIL 68s PREV |
| 57 | 47 | 22 | device_queries pin | pass 44s miss | FAIL 44s PREV |
| 58 | 48 | 13 | wip(, EXE001, Cargo.lock, newline, MD040, native_test | FAIL 11s part | FAIL 42s part |
| 59 | 48 | 16 | MD040, model not prefetched | FAIL 43s PREV | FAIL 45s PREV |
| 62 | 47 | 22 | dart lint 80 cols | pass 18s miss | FAIL 56s PREV |
| 63 | 45 | 23 | subjects, i18n, node dir, spawn buffer | FAIL 12s part | FAIL 42s PREV |
| 64 | 48,44 | 25 | MD013, i18n, device pins (all #44) | FAIL 23s part | FAIL 53s PREV |
| 66 | 44 | 21 | subject 83, dart lint quotes | FAIL 14s part | FAIL 46s PREV |
| 72 | 45 | 21 | SC2174, E501, tools-cache key | FAIL 13s PREV | FAIL 42s PREV |
| 73 | 55 | 7 | face portraits not prefetched | FAIL 17s miss | FAIL 48s miss |
| 74 | 45 | 25 | node dir, spawn buffer, janky | FAIL 20s part | FAIL 47s part |
| 75 | 55 | 22 | prefetch, servers_test, pins, apt | pass 15s miss | FAIL 49s part |
| 76 | 45 | 26 | apt, spawn buffer, janky | FAIL 19s part | FAIL 48s part |
| 77 | 71,67 | 21 | outbound, env vars, ingest-hdr, apt | FAIL 13s part | FAIL 42s part |
| 78 | 71,45,55 | 22 | faces wall-clock, dart lint 80 cols | FAIL 30s miss | FAIL 82s part |
| 79 | 71,67 | 26 | ingest-hdr +12.4%, apt | pass 15s miss | pass 48s miss |
| 81 | 71 | 25 | apt stall only | pass 11s miss | pass 41s miss |
| 83 | 45,55 | 27 | dart lint 80 cols | FAIL 14s miss | FAIL 56s PREV |
| 87 | 45,71,85 | 14 | ruff E501, tools/README 62 lines | FAIL 23s PREV | FAIL 44s PREV |
| 88 | 55 | 10 | ruff E501 check_ci.py:94 | FAIL 16s PREV | FAIL 45s PREV |
| 90 | 45,55,71 | 38 | apt, janky 29% | FAIL 16s miss | FAIL 63s miss |
| 91 | 85 | 22 | apt stall only | FAIL 17s miss | FAIL 46s miss |
| 92 | 45 | ? | conformance flake, janky 47%, apt | FAIL 22s miss | FAIL 46s miss |

## Failure classes: one replay each

Run used = the easiest tree to reconstruct; the other runs of the class are not replayed. Seconds on a quiet machine.

| Class | Run used | Quick | Default | Full | Same class, not replayed |
|---|---|---|---|---|---|
| commit subject, `wip(`; newline, exec bit; MD040 | #58 | FAIL 11 s | FAIL 42 s | FAIL | #56, #59, #63, #66 |
| README line limit; ruff E501 | #87 | FAIL 23 s | FAIL 44 s | FAIL | #56, #88 |
| shellcheck SC2174, baseline | #72 | FAIL 13 s | FAIL 42 s | FAIL | #50 |
| `node --test <dir>`; tools-cache key | #72 | FAIL 13 s | FAIL 42 s | FAIL | #63, #74 |
| `Cargo.lock` path patch | #58 | FAIL 11 s | FAIL 42 s | FAIL | none |
| privacy manifest, env vars | #77 | FAIL 13 s | FAIL 42 s | FAIL | none |
| cargo fmt; ADR-0116 guard test | #52 | FAIL (fmt only) | FAIL | n/a | none |
| dart analyzer lint | #83 | not flagged | FAIL 56 s | n/a | #44, #47, #55, #66 |
| i18n lint, device_queries pins | #63, #57 | not flagged | FAIL 42-44 s | n/a | #56, #64, #75 |
| `native_test` pin | #58 | not flagged | not flagged | FAIL (42 s step) | none |
| `servers_test` / Settings list | #75 | not flagged | not flagged | FAIL (`settings_test`) | none |
| offline model prefetch (ppocr) | #59 | FAIL | FAIL | n/a | #58 |
| offline model prefetch (face portraits) | #73 | not flagged | not flagged | not flagged | #75 |
| spawnSync buffer | #63 | FAIL | FAIL | n/a | #74, #76 |
| wall-clock budget (faces) | #78 | not flagged | not flagged | skipped (budget) | none |
| perf-instructions (`--perf` not run) | #77 | not flagged | not flagged | not flagged | #79 |
| janky budget | #74 | not flagged | not flagged | not flagged | #76, #90, #92 |
| apt stalls; conformance flake | #81, #92 | not flagged | not flagged | not flagged | #75-#77, #79, #90, #91 |

## Examples

Script lines are copied from the replays (paths shortened with `...`); minutes = open time of the queue PR.

### #58 (#48, 13 min, 9 jobs red): six causes, all six seen in full

CI: `Cargo.lock needs to be updated but --locked was passed` (6 jobs), `ae802f4: subject must look like`, `make.py:1:
EXE001`, `no newline`, `0388...md:71: MD040`, `'user_version'][0] is '28' instead of '27'`. Fixed in 20a3457, 2d561a8.

```text
FAIL commitlint (0.3s)
      ae802f4: subject must look like 'type(scope): summary' with type one of feat, fix, docs, ...
FAIL Cargo.lock path patch (0.2s)
      server/Cargo.lock: rs-vips 0.7.0 has no registry source and no crate in this repository
FAIL lint of touched files (0.2s)
      ruff: testdata/ocr/make.py: EXE001: 1, baseline 0
```

Quick 11 s, default 42 s (quiet), with the MD040 and newline FAILs of `repo tests`. Only `--full` runs `dart tests
(touched)` and finds `user_version` (a 42 s step after the 168 s dart ratchet).

### #63 (#45, 23 min): four of four, one by luck

CI: `454ba88: subject is 81 characters`, `upload.dart:72: ui-string`, `Cannot find module '.../web_e2e/test'`, `cargo
build ... photolibd ... failed` (the 1 MB `spawnSync` buffer).

```text
FAIL node --test <dir> (0.3s)
      tools/check.sh:647:    step tools/web_e2e node --test test/
FAIL child output buffers (0.0s)
      tools/web_e2e/setup.mjs runs a child with spawnSync/execSync/execFileSync and sets no maxBuffer
```

Default 42 s; the buffer rule also flags `journey.mjs` and `lib.mjs` (bug 3). Subjects and i18n FAIL as in #58.

### #64 (#48 + #44, 25 min): one PR's faults, two PRs' queue time

CI: `docs/user/README.md:144: MD013 line is 223 characters`, `i18n_lint_test` on the map, `device_queries_test` on
`mapItems`: all #44's; #48 waited without a fault (c6397071067).

```text
FAIL repo tests (43.0s)
      docs/user/README.md:144: MD013 line is 223 characters; the limit is 120
FAIL app guard tests (5.1s)
      Retry: the app has no hard-coded UI string or physical direction
```

Default 53 s: prevented, 25 queue minutes and a cycle of #48.

### #66 (#44, 21 min): subject 83, and a lint in a package

CI: `acfb6d3: subject is 83 characters`, `geo_test.dart:98: avoid_escaping_inner_quotes`.

```text
FAIL dart analyzer vs baseline (11.7s)
      dart app/packages/photolib_data: .../test/geo_test.dart: avoid_escaping_inner_quotes: 2, baseline 0
```

The draft skipped this package (no `.dart_tool`) and passed; b63d614 runs it in a fresh checkout.

### #75 (#55, 22 min): three of four, `--full` needed

CI: `face-photo-armstrong-a is not in .../ml/... egress is blocked`, `servers_test` (4 tests: `Found 0 widgets with
text "The server ended this session"`), `device_queries_test` `extra map key '.../info_facts.dart'`, a `dpkg database
lock`.

```text
FAIL app guard tests (7.8s)
FAIL dart tests (touched) (50.1s)
      <asynchronous suspension>
```

Default flags the pin only. `--full` adds `dart tests (touched)`: `settings_test.dart:97` fails (the longer Settings
list pushes rows off screen, as in `servers_test`) but no test name is printed (bug 5). No tier flags the
face-portrait prefetch: `faces_native_test` passes here (models in the local cache).

### #77 (#71 + #67, 21 min): the other PR's faults

CI: `gainmap.rs contacts ns.adobe.com, but no row of docs/admin/privacy.md`, the HDR test variables (`neither a
setting`), `ingest-hdr: 12.4% more instructions`, apt (3 jobs). #71 had no fault (c6399704133).

```text
FAIL repo tests (36.0s)
      FAIL: neither a setting nor in NOT_SETTINGS of .../photolib-server/src/config.rs: <three HDR test variables>
      FAIL: .../photolib-media/src/gainmap.rs contacts ns.adobe.com, but no row of docs/admin/privacy.md lists it
```

Quick 13 s. perf-instructions (7 min 58 s in CI, opt-in `--perf`) and apt are not catchable.

### #78 (#71 + #45 + #55, 22 min): a wall-clock assert the rule does not see

CI: `faces.rs:290: crew: 5485.266841 ms` on four tries (`assert!(median < 5000.0, ...)`), and
`device_queries_test.dart:67` over 80 columns. Default FAILs on the second only (`lines_longer_than_80_chars: 2,
baseline 0`, 78 s). `no wall-clock assertion` matches `elapsed`/`Stopwatch`, not `median < 5000.0`; `--full`'s `rust
tests under load` is always skipped by the budget.

### #87 (#45 + #71 + #85, 14 min) and #88: a fault of #85 only

CI: `check_ci.py:94: E501 (122 > 120)`, `tools/README.md has 62 lines; want 8 to 60`; #71's worker suspected #45 or
#85 (c6400975267). Replayed heads: #71, #55 (8d0a21c) pass; **#85 (036776c) FAILs**; #45 (fd7b855) only on bug 3.

```text
FAIL repo tests (36.4s)
      FAIL: tools/README.md has 62 lines; want 8 to 60
FAIL lint of touched files (6.3s)
      ruff: tools/tests/check_ci.py: E501: 1, baseline 0
```

#85's own head FAILs quick (8 s) and default (36 s). #87 and #88 lost 24 queue minutes.

## Aggregation

* The 25 red runs cost 503 queue minutes (24 with a closed queue PR) and ~6,000 job minutes. The first red job ended a
  median 9 minutes (3 to 23) into a 22-minute run; the run went on, as `gate` waits for all jobs.
* Method: a prevented run frees its queue PR's open time (the later green run happens either way). Discarded queue PRs
  behind a failure (#53, #60, #61, #80, #84: 22 min) are not counted: the savings are lower bounds.
* Per PR, red / all queue entries: #45 9/9 (open; first queued 10:22), #55 6/8, #71 6/8, #48 3/5, #47 3/4, #44 2/5,
  #67 2/2, #85 2/2, #46 1/3, #49 1/2.
* Worker view (script on each PR head at "ready", base = queue base, draft replay): FAIL for #49, #46, #47 (3 heads),
  #48, #45 (afae67f), #44, #55 (834dd52); PASS for #45 (fd7b855, draft), #71, #55 (8d0a21c); **#85 FAILs alone** (see
  #87).

## False-positive check

b63d614 on 17 trees CI accepted or that merged later (quick / default; the runs under load).

| Tree | Quick | Default | Why |
|---|---|---|---|
| merged heads #49, #47; queue trees #51, #68; dev itself | pass | pass | |
| merged heads #46, #48; queue trees #54, #65, #70; dev~20 | FAIL | FAIL | `no wall-clock assertion` |
| merged head #44 | FAIL | pass | same step (skipped in default: budget) |
| queue tree #43 (base is a root commit, 2,377 files) | FAIL | FAIL | diff --check, ADR 0234 twice, buffers |
| #45 head fd7b855, #85 head | FAIL | FAIL | buffers (#45), README and ruff (#85, true) |
| #71 head, #55 head 8d0a21c | pass | pass | |

* The `no wall-clock assertion` step FAILs on 7 of 12 clean trees: tests that assert `clock.elapsed < 2 s` (#46),
  `fastest.as_secs() < 5` (#48), `build.as_secs_f64() < 10.0` and `worst.as_millis() < 16` (#44): none failed CI, and
  the rule misses the one that did (#78's `median < 5000.0`).
* The `child output buffers` step flags every `spawnSync` without `maxBuffer` in `tools/web_e2e` (#45's head after the
  fix, #91, #92), also those that print a line: a standing FAIL on a PR that is right.
* Queue tree #43: `0234-several-accounts.md` and `0234-integrity-scrubbing-and-backup-watchdog.md` are both on
  `origin/dev` today; no gate test catches the duplicate ADR number.
* Draft script: 11 of 13 clean trees passed; its two FAILs were the #43 root-commit tree and a `pub get` race.

## Gaps and recommendations

Missing steps for b63d614, ranked by runs unlocked per minute (B counts, from the `full` baseline 15 / 22):

| # | Step | Cost | Runs | Proof |
|---|---|---|---|---|
| 1 | CI: put `timeline-scroll-web` janky into `CHECK_ADVISORY` | 0 | #74, #76, #90 | log only |
| 2 | prefetch rule per lane: `face-photo-*` of Dart tests | <1 s | #73, #75 | replay: not flagged |
| 3 | wall-clock rule: match `median < N`, not `elapsed < N` | <1 s | #78 | replay: #78, 7 FPs |
| 4 | order `--full`: touched dart tests and rust tests under load first | 0 | #58 (loaded) | replay: skipped |

With 1-3: 15 + 3 + 2 + 1 = 21 / 22 = 95% of B in `full`. Not catchable: apt stalls (8 runs; CI fix in
`lane/action.yml`: save the `.deb` cache `if: always()`, `timeout 3m`), perf-instructions (7 min 58 s in CI, the whole
`--full` budget; `--perf` is opt-in), the conformance flake (#92).

Time: `full` never finishes inside 420 s here: `dart ratchet (full)` 168-224 s, `clippy ratchet` 55-160 s, `rust tests
(4 cores)` is stopped `slow` on every run, so `rust tests under load` is always skipped. Quick is 7-23 s, default
37-56 s (`repo tests` 35-52 s of it: trim by running the 16 fast ones in default too).

## Script bugs

b63d614 (the draft's bugs 1-7 were fixed or not met again: `pub get` in a package works, `--full`/`--list` exist):

1. Budget not enforced: `--full` on #72 ran 595 s (budget 420), default on #47's head 629 s and on #44's 533 s (budget
   300), under load: steps "stopped" late. The same runs report `skip (the budget ... was used up)` for steps that
   would have failed (the wall-clock step on #44).
2. `no wall-clock assertion` fails clean code (7 of 12 trees) and misses #78 (`median < 5000.0`).
3. `child output buffers` flags `journey.mjs` and `lib.mjs` (children that print a line), so #45's right head FAILs.
4. `models in the prefetch` knows `ppocr-v5-*` (right on #58, #59) but not `face-photo-*` (#73, #75).
5. `dart tests (touched)` prints the last 40 lines: on #75 only `<asynchronous suspension>`; the failing test is not
   named.
6. `fresh clone` repeats `--quick` in a clone, so every quick FAIL is printed twice and `full` fails on clean-code FPs
   twice.
7. `git diff --check` and the number step run over the whole diff: on #43's root-commit base they FAIL on old content.

Not re-tested: the PR title step (`PREQUEUE_NO_GH=1`; the draft's ` (#9999)` suffix made 65 to 67 character titles
FAIL).
