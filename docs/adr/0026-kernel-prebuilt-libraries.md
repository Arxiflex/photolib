# ADR-0026 — Kernel prebuilt libraries: Dart build hooks, GitHub releases, pinned SHA-256

* **Status**: Accepted — 2026-10-15. The owner confirmed ("probably ok") how apps get the prebuilt kernel and where it
  is published, as M0-12 decided
  (photolib-design#292).
  Publishing from a run started by hand on the tag, which photolib-design#283 chose once a tag push stopped starting
  CI, stands: the owner deferred it
  (photolib-design#304).
* **Requirements**: R-APP-1, R-APP-3. **Design**: ADR-0004, 10 §1.4, §5.6, 16 §7.

## Context

ADR-0004 has CI publish prebuilt kernel libraries per version so
that Flutter-only contributors need no Rust ("cargokit-style, verified by checksum"). It leaves open how `flutter
build` picks them up, where they are published and what the checksum is checked against. Dart build hooks (native
assets) are on by default in Flutter stable; they bundle a library for every target without per-platform Gradle,
CMake or Xcode glue. Hooks run with a filtered environment (no `CARGO_*` or `RUSTUP_*`), so a hook that runs cargo is fragile.

## Decision

* **Build**: `tools/kernel/build.py` cross-compiles `kernel/ffi` for the 11 native targets (Android arm64, arm and
  x64 with the NDK, linked for 16 KB pages; iOS device and simulator; macOS arm64 and x64; Windows x64; Linux x64 and
  arm64) and writes `prebuilt.json`, the SHA-256 of every library. CI builds them weekly and by hand.
* **Publish**: CI run by hand on a `kernel-v<version>` tag (the version of `kernel/ffi/Cargo.toml`) publishes the
  libraries and a `prebuilt.json` that points at the release, once `flutter build` bundled them on every target.
  Copying that `prebuilt.json` to `app/packages/photolib_kernel/` pins the release for the app.
* **Consume**: the build hook of `app/packages/photolib_kernel` takes the library for the build target, from the pinned
  release or from the directory in `hooks.user_defines.photolib_kernel.artifacts`, and fails the build unless its
  SHA-256 is the pinned one. It never runs cargo. Flutter assembles the per-architecture libraries into the iOS
  frameworks and the universal macOS framework.
* **Binding**: a plain C ABI through `dart:ffi` (`@Native`); no flutter_rust_bridge.

## Consequences

* `flutter build` needs no Rust on any target, offline builds work from a local artifacts directory, and a tampered or
  stale download fails the build.
* A kernel change reaches Flutter-only contributors only after a release is tagged and pinned; kernel developers build
  their own with `tools/kernel/build.py` and point the user-define at it.
* The first release (`kernel-v0.1.0`) must be tagged and pinned before an app build works without that user-define.
* F-Droid builds from source: it runs `tools/kernel/build.py` and uses the user-define (M10-04).

## Options considered

* **cargokit or flutter_rust_bridge**: per-platform build glue and a signing key in CI; the hook does the same job with
  less code and the C ABI needs no generator.
* **Building from source in the hook when cargo exists**: depends on environment variables that hooks do not receive
  and silently mixes local and released libraries.
* **Publishing to a package registry or object store**: GitHub releases already host the project and need no new
  service.
