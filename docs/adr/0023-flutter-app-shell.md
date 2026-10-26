# ADR-0023 — Flutter app shell: libraries, application ID, version pin and platform minimums

* **Status**: Accepted — 2026-10-15. The owner answered the provisional choices of the app shell (M0-21) in
  photolib-design#278:
  the libraries, layout, flags and CI devices are confirmed, the application ID and the Flutter pin are deferred ("will
  be chosen later", "I do not know") and stay as below, the platform minimums are the design's, and the smoke test
  leaves pull requests. In
  photolib-design#294
  the owner chose to run it twice a day, and every other run locally before checking in, and confirmed in
  photolib-design#315
  that this leaves no manual run.

## Context

The app shell is the first code in `app/` (client app design).
It fixes choices that are costly to change later and that the design leaves open or the owner has not yet taken.

## Decision

* **Libraries.** `go_router` for navigation, `flutter_riverpod` 3 for state and dependency injection, `material_ui`
  (the Material library split out of the Flutter framework) for widgets, and `gen-l10n` for strings. Generated
  localisation files are committed so a fresh clone builds without a generation step.
* **Application ID.** `org.photolib.photolib` on Android, iOS and macOS, a placeholder: the owner chooses it later
  ("does not matter now"), before the first store upload. The alternative is `io.github.arxiflex.photolib`,
  which needs no domain. The ID cannot change after the first store release.
* **Flutter pin.** `app/.fvmrc` names one exact version and is read by FVM, the CI composite action and the gate.
  Renovate's FVM manager is disabled, so a version moves only through a pull request that passes the
  `flutter-upgrade` job: every gate of the template ticked (design §12). A weekly workflow runs the beta channel.
* **Layout.** Window size classes at 600 and 840 logical pixels: a bottom bar when compact, a rail when medium, an
  extended rail when expanded; page content is at most 640 wide. Library, Collections and Search are stable tabs;
  Settings is a fourth destination.
* **State.** Settings and the collection layout (pin, hide, reorder; VIEW-34) are in memory; they persist with the
  local database (M0-23). Feature flags are compile-time (`--dart-define=PHOTOLIB_FLAGS=a,-b`) with no remote config
  and no network call.
* **Smoke test.** One `integration_test` runs on all six targets in the weekly workflow's `smoke` jobs: Linux, web,
  an Android emulator (API 34, x86_64), the first available iPhone simulator, macOS and Windows. They run twice a day
  on `main`, not on pull requests, after merges or by hand, to save Actions minutes; photolib-design#283 had moved
  them to the weekly run, where the other costly jobs stay. Every other run is local: before checking in a change
  under `app/`, the contributor runs `bash tools/smoke.sh` in good faith on every target their machine can run. The
  owner confirmed that "all other should happen running it locally" means the smoke jobs never run by hand
  (photolib-design#315).
* **Platform minimums.** Android API 30 (`minSdk`), iOS 16 and macOS 13 (the Xcode deployment targets), as design 10
  §1.1 proposes: MediaStore generations and trash requests arrive in API 30, `fetchPersistentChanges(since:)` in iOS 16
  and macOS 13. Windows, Linux and the web have no build setting for a minimum; design 10 §1.1 lists their floors.

## Consequences

* A Flutter upgrade is deliberate and slower than a dependency bump; the two-week beta soak and the device gates are
  the price of not shipping a regression in panorama, video or HDR rendering. Gates that need a device lab or the
  performance harness are ticked by a person until M0-27, M0-26 and M1-13/M1-14 automate them.
* Changing the application ID after release breaks update paths, so confirm it before the first store upload.
* Android 10, iOS 15, macOS 12 and older cannot install the app; supporting them would need a second sync path.
* A target that stops building or launching on a platform the contributor could not run locally is found by the next
  scheduled run, up to 12 hours after the merge, which may cover several merges.
* Committed generated files add review noise; `flutter gen-l10n` keeps them reproducible.

## Options considered

* **`auto_route`, Navigator 2 by hand**: more code than `go_router` for the same deep-link and redirect needs.
* **`bloc`, `provider`**: Riverpod gives compile-safe overrides for tests and no `BuildContext` dependency in
  repositories.
* **Pin in `pubspec.yaml` `environment: flutter`**: only a range, and the SDK constraint cannot select an install.
* **Renovate bumping `.fvmrc`**: opens upgrades without the gates; rejected.
* **Remote feature flags**: a third-party service, which needs its own ADR.
* **Smoke test after each merge to `main`, by hand, nightly, weekly or on release tags only**: the owner chose
  twice a day (photolib-design#294) and no manual run (photolib-design#315).
* **Flutter's own floors** (API 24, iOS 15, macOS 12): the owner chose the design's minimums.
