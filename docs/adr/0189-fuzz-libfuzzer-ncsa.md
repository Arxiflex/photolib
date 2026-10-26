# ADR-0189 — libFuzzer's NCSA licence is allowed in the fuzz workspace only

* **Status**: Accepted — 2026-10-21. The owner kept the crate-scoped exception and the unchanged global allow-list
  (photolib-design#558,
  photolib-design#555).
* **Requirements**: R-SEC-1. **Design**: [ADR-0013](0013-licence.md#dependency-licences),
  [ADR-0036](0036-kernel-metadata-reader.md).

## Context

`cargo deny --locked --config deny.toml check` must pass in every Cargo workspace (photolib-design#555). In
`kernel/fuzz`, the cargo-fuzz workspace `tools/kernel/fuzz.sh` runs on the build machine (ADR-0036), it fails on
licences: `libfuzzer-sys` is `(MIT OR Apache-2.0) AND NCSA`, NCSA being the licence of the LLVM libFuzzer sources it
builds. NCSA is permissive (OSI approved, BSD-like) but not on ADR-0013's allow-list. The gate never checked this
workspace, so the finding went unseen.

## Decision

We will allow NCSA for the crate `libfuzzer-sys` alone, as a `[licenses] exceptions` entry of `deny.toml`. The global
allow-list stays as ADR-0013 lists it, so no shipped crate may use NCSA.

## Consequences

Every Cargo workspace passes `cargo deny` against the one `deny.toml`. Fuzz binaries are never distributed, so the
exception reaches nothing a user receives. Should another crate under NCSA be wanted, adding it to the allow-list is
a reviewed change of its own.

## Options considered

* NCSA on the global allow-list: permissive, but it would admit it into shipped code without a review of its own.
* A second `deny.toml` for `kernel/fuzz`: two policies to keep in step, and the issue asks for the one file.
* Leaving `kernel/fuzz` failing: the acceptance criterion asks for every workspace.
