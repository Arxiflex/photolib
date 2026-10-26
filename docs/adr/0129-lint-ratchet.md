# ADR-0129 — Lint rules held by a ratchet

* **Status**: Accepted — 2026-10-20. The owner kept all four decisions of
  photolib-design#487:
  the ten rejected lints, Rust at 120 columns (the reformat happened once, in its own style commit; undoing it would
  reformat the same files again and conflict with every open branch), the tight ratchet that grows only with
  `--grow` and `lint-accept:`, and ShellCheck without SC1091 and SC2015.
* **Requirements**: NFR-PERF-1. **Design**:
  19 — Quality and testing
  §6, photolib-design#448.

## Context

The gate linted with the defaults: nothing limited a file's or a function's length, found unused items or
dependencies, or denied the constructs behind a user's first crashes (an unwrap, an index past the end, an overflow,
a lost error), and Swift, C++, Kotlin, Python, shell and JavaScript were not linted. Turning strict rules on finds
thousands of violations in code that works; fixing them in one change would rewrite the repository.

## Decision

We will lint every language in the gate ([lint rules](../dev/lint.md)) and hold each linter's findings to
`tools/lint/baseline.json`, a count per run, file and rule:

* The gate fails on a count above the baseline and on one below it, so the baseline always equals the code and only
  shrinks; `tools/lint/ratchet.sh --update` refuses to grow it. A new rule or a tool upgrade grows it only with
  `--grow` and a `lint-accept: <reason>` line, which the gate checks against the merge base with `main`.
* Linters are pinned (`tools/lint/tool.sh`): another release finds other things, and counts must match on every
  machine. Rust's crash classes count in shipped code only, judged by a second clippy over `--lib --bins`.
* Rust rejects ten pedantic and nursery lints, each with its reason in the workspace's `Cargo.toml`.
* dart_code_linter, the maintained fork of dart_code_metrics, measures Dart's functions and finds unused code; the
  ratchet measures file length itself.
* clang-tidy compiles the runner of the OS it runs on; the Windows runner needs a Windows machine.
* The strict-casts analyzer errors are findings like any other, as the code still compiles and runs.

## Consequences

New code meets every rule; old code is cleaned by the refactor runs, file by file, and `--top` names the worst files.
Rust's builds print the rustc lints (`missing_docs`, `unreachable_pub`) as warnings until they are burned down. A moved
file starts at zero findings. `rust-toolchain.toml` pins the Rust release, so a new clippy's lints arrive only with
a bump of their own, which cleans or `lint-accept`s them.
Line length 120 reformatted the kernel and the server once.

## Options considered

* Fixing every violation now: weeks of changes to working code, against the issue's "without reformatting the world".
* A baseline of totals per rule: it would let a file get worse while another got better.
* A loose ratchet that only fails on growth: a cleaned file's headroom would let new violations in unseen.
* `cargo udeps`: it needs a nightly toolchain; `cargo machete` reads the sources and runs on stable.
