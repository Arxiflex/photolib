# ADR-0019 — Protobuf toolchain: pinned local plugins, checked-in generated code, breaking baseline

* **Status**: Accepted — 2026-10-15 (roadmap M0-06). The owner confirmed all four decisions as made
  (photolib-design#266).
* **Requirements**: R-APP-3, R-REL-2, NFR-REL-3. **Design**: 16 §7.

## Context

ADR-0005 makes Protocol Buffers the single IDL and names `buf` for linting,
breaking-change detection and generation. It leaves open where the generated code lives, where the plugins come from,
what `buf breaking` compares with before a release exists, and how a machine that lacks `buf` runs the gate. M0-06 has
to settle them, because every later package (the server crate, the Dart package, the viewer) consumes the output.

## Decision

* **Generated code is checked in**, at the consumers' `gen` directories: `server/crates/photolib-proto/src/gen`,
  `app/packages/photolib_api/lib/src/gen` and `viewer/src/gen`. It carries no manifest until its package arrives, so the
  Rust, Dart and Node gate parts are not triggered early. The `codegen` job of the PR build regenerates it and fails on
  any difference.
* **Plugins run locally at pinned versions**, installed by `tools/codegen.sh install`: `protoc-gen-buffa` and
  `protoc-gen-connect-rust` for the server (since M0-08, because the `connectrpc` crate is built on buffa),
  `protoc-gen-prost` for the kernel, `protoc_plugin` (Dart) and `@bufbuild/protoc-gen-es`. We do not use remote
  plugins on the Buf Schema Registry: that would send our schema to a third-party service and make generation depend
  on its availability.
* **`buf` itself is pinned** in `tools/buf.sh`, which runs the `buf` on `PATH` or else installs the pinned release from
  npm into a per-user cache. The gate's `proto` part therefore works on a clean machine that has Node, as the dev
  container does, and CI and developers run the same version.
* **`buf breaking` compares with the last release tag** (`v*`), as the design says, and with `origin/dev` until the
  first tag exists. Rules: `WIRE_JSON`, so a change that breaks the binary or the JSON encoding fails, and deleting a
  field without reserving its number and name fails too.
* The style guide is [a page of the developer guide](../dev/protobuf-style-guide.md).

## Consequences

* A change to a `.proto` file has to come with its regenerated code, which makes the effect on the three languages
  visible in the same review. Generated files add noise to diffs, but they carry `@generated` or "do not edit" headers.
* Until the first release tag, any incompatible change to a published message is rejected, including one made while
  the schema is still young. A deliberate reset is a reviewed edit of `proto_breaking.sh`, or the first tag.
* Bumping `buf` or a plugin is one pinned version plus a regeneration, in one change. Renovate does not see these pins
  yet; a custom manager for them is follow-up work.
* The Rust crate must treat the generated files as opaque (`#[rustfmt::skip]`), and the Dart package must keep
  `dart format` and `flutter analyze` away from them or accept their headers; the packages decide when they arrive.
* The `codegen` job needs Rust, Dart and Node, which is why it is a job of its own rather than a part of the gate.
* The pinned tools come from the npm, crates.io and pub.dev registries, and only when a developer or CI installs them,
  as `tools/docs.sh` does for MkDocs. The product itself gains no outbound dependency.

## Options considered

* **Generate in CI only and do not commit.** Smaller diffs, but a clone cannot build the server or the app without the
  whole toolchain, and nobody sees the generated change in review. Rejected; commit-and-diff keeps both.
* **Remote plugins on the BSR (`buf.build/...`).** Nothing to install, but an outbound dependency on a third party that
  would need its own ADR, and a risk to reproducibility. Rejected.
* **No baseline until the first tag.** The check would silently pass for the whole pre-release period, so the first
  breaking change would slip in unnoticed. Rejected in favour of `origin/dev`.
* **Require `buf` on `PATH`, as the gate did for the other toolchains.** Simple, but the gate fails on every machine that
  has not installed it, including the automated one that runs the work items. The bootstrap keeps a missing toolchain
  a loud failure only when neither `buf` nor Node exists.
