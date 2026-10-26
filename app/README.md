# app/

The one Flutter app for Android, iOS, macOS, Windows, Linux and the web. It works standalone (a gallery with no
server) or connected to one or more self-hosted servers.

## Architecture

* Dart owns the UI, state (Riverpod, go_router for navigation), domain repositories, the local replica (drift on
  SQLite), the sync engine, the outbox and the upload orchestrator. Codecs, ML, keystores and background transfer are
  platform plugins.
* The kernel (`app/packages/photolib_kernel`) runs pure functions over FFI on native targets and WASM on the web.
* Packages under `packages/`: `photolib_ui`, `photolib_domain`, `photolib_data`, `photolib_api` (generated from
  `proto/`), `photolib_kernel`, `photolib_ml`, `photolib_workers` and the federated `photolib_platform_*` plugins.
* One data isolate per process owns the database, and sync never runs on the UI isolate.
* Per-target folders: `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`. Their icons are photolib-design's
  `docs/brand/icon/`, written by `python3 tool/icons.py <that dir>` (all but Android's `mipmap-anydpi-v26/` XML).

## Contents

The app shell (M0-21), under `lib/`: `main.dart` and `app.dart` (the app, its error boundary and providers),
`router.dart` (go_router), `core/` (logging, error handling, feature flags, providers), `ui/` (the design system of
M0-25: tokens, themes, motion, commands, selection bar, media grid, swipe to dismiss; the responsive shell),
`gallery.dart` (the component gallery, a second entry point), `features/` (`library`, `collections`, `editor`,
`search`, `settings`, and `viewer`: [the photo viewer](../docs/adr/0106-photo-viewer.md) and [the HDR
leaf](../docs/adr/0060-hdr-native-leaf-views.md), native halves in the runners) and `l10n/` (English strings, the
`en-XA` and `ar-XB` pseudo-locales, generated files committed). `assets/fonts/` bundles Roboto.
`features/library/timeline/` holds the timeline and its [thumbnail pipeline](../docs/adr/0070-thumbnail-caches.md).
`test/` holds the unit and widget tests and the pseudo-locale goldens, `integration_test/` the smoke test that CI runs
on all six targets and the HDR probe (`hdr_probe.dart`), and `tool/` the pseudo-locale generator and the lints that
keep blocking work off the root isolate (`root_isolate_lint.dart`), hard-coded strings and left/right layout out of the
UI (`i18n_lint.dart`) and shared `Paint`s (`paint_lint.dart`). [Flutter](../docs/dev/flutter.md) is pinned in `.fvmrc`.
`packages/photolib_api` holds the code generated from `proto/` and the client over it: `NetworkConfig`, the one
configuration of a server, builds the one HTTP client (dart:io with an explicit `SecurityContext` on native targets,
fetch on the web) that `Server` sends API calls, sync, media and uploads through, and `MediaProxy` serves players on
loopback ([ADR-0032](../docs/adr/0032-one-network-stack.md)).
`packages/photolib_kernel` binds the kernel's C ABI with `dart:ffi` and, in `photolib_kernel_web.dart`, its WASM module
with `dart:js_interop` (same API; `await Kernel.load(url)` loads it lazily); its build hook bundles the prebuilt kernel
its `prebuilt.json` pins (SHA-256 checked), so `flutter build` needs no Rust; its tests run the vectors on both.
`packages/photolib_editor` holds the edits and their copies (`lib/edit.dart`), shaders that match the kernel's CPU
reference renderer and the spike's probe (`lib/testing.dart`, [ADR-0054](../docs/adr/0054-editor-rendering.md)).
`packages/photolib_data` is the local store (M0-23, M0-41): drift on SQLite3MultipleCiphers, schema v12, migrations with
a backup of local-only data, one data isolate per process, all keyed by its `Vault`; `lib/core/replica.dart` opens it,
and `tool/single_writer_lint.dart` keeps it keyed and the only writer. Its `MediaStoreIndexer` (M1-01, ADR-0045) and
`PhotoKitIndexer` (M1-02, [ADR-0095](../docs/adr/0095-photokit-index.md)) keep the device index that
`lib/core/device_library.dart` reads through the runners' `MediaStoreChannel.kt` and `PhotoKitChannel.swift`; its
`MetadataExtractor` reads the files with the kernel as `lib/core/device_health.dart` allows (M1-08, ADR-0072), and
`searchPage` serves Search's filters and file names (M1-17, ADR-0086), and `SyncEngine` syncs it (M2-15, ADR-0120).
`packages/photolib_log` is the logger of every package and isolate ([ADR-0115](../docs/adr/0115-debug-diagnostics.md)).
`packages/photolib_workers` is the worker pool (M0-24): `WorkerPool` runs `Task`s by priority with progress and
cancellation on isolates natively (cores − 1, at most 4 on phones) and on Web Workers on the web, from a script
compiled with `dart compile js` whose `main` calls `serveWorker`; its `testing.dart` holds tests' frame budgets.
`packages/photolib_video` is the video editing spike (M0-35): one planner for an edit decision list and its executors
on FFmpeg, Media3 and AVFoundation ([ADR-0043](../docs/adr/0043-video-editing-engines.md)); the app does not use it yet.
`packages/photolib_ml` is the on-device ML runtime (M0-34): ONNX Runtime's C API through `dart:ffi` on any isolate,
onnxruntime-web on the web, checked against the CPU's goldens ([ADR-0050](../docs/adr/0050-on-device-ml-runtime.md)).

## Design

* Client app
* ADR-0003: Flutter for all clients
