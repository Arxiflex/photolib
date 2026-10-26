#!/usr/bin/env bash
# The Flutter app shell (M0-21): one project for the six targets, the two Android flavours, the pinned Flutter
# version, the platform minimums and the integration smoke test that CI runs on every target, as the owner answered
# ADR-0023 (photolib-design#278, #294, #315).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

for key_file in android/app/build.gradle.kts ios/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/project.pbxproj \
  windows/CMakeLists.txt linux/CMakeLists.txt web/index.html pubspec.yaml pubspec.lock lib/main.dart \
  integration_test/app_test.dart test_driver/integration_test.dart l10n.yaml lib/l10n/app_en.arb \
  lib/l10n/app_localizations.dart; do
  assert_file "app/$key_file"
done

assert_matches app/.fvmrc '"flutter": "[0-9]+\.[0-9]+\.[0-9]+"' "pins one exact Flutter version, read by FVM and CI"
for package in flutter_riverpod go_router material_ui; do
  assert_matches app/pubspec.yaml "^  $package:" "depends on $package"
done
assert_prose app/android/app/build.gradle.kts 'productFlavors.*"play".*"libre"' "builds the play and libre flavours"
check "pubspec.lock has no proprietary plugin (the libre scan)" python3 tools/scan_libre.py app/pubspec.lock

# --- platform minimums: the design's (10 §1.1), set by the owner in photolib-design#278
assert_matches app/android/app/build.gradle.kts '^ *minSdk = 30$' "needs Android API 30"
# --- high refresh rate (docs/10 §3.3): iOS ProMotion through Flutter's template key; on Android the app asks for the
# fastest mode itself, as display-mode plugins can lock LTPO panels at 30 Hz. The gate compiles no Kotlin.
assert_prose app/ios/Runner/Info.plist '<key>CADisableMinimumFrameDurationOnPhone</key>[[:space:]]*<true/>' "unlocks ProMotion"
assert_prose app/android/app/src/main/kotlin/org/photolib/photolib/MainActivity.kt \
  'maxByOrNull \{ it\.refreshRate \}.*preferredDisplayModeId' "asks for the highest refresh rate"
# deployment_target <pbxproj> <setting> <version>: every build configuration that sets it says <version>.
deployment_target() {
  local values
  values=$(sed -nE "s/^\s*$2 = (.*);$/\1/p" "app/$1" | sort -u | tr '\n' ' ')
  [[ $values == "$3 " ]] && ok "app/$1: $2 is $3" || fail "app/$1: $2 is '${values:-unset}', not $3"
}
deployment_target ios/Runner.xcodeproj/project.pbxproj IPHONEOS_DEPLOYMENT_TARGET 16.0
deployment_target macos/Runner.xcodeproj/project.pbxproj MACOSX_DEPLOYMENT_TARGET 13.0

# --- documentation: the developer page, the decision record and the folder guides
assert_file docs/dev/flutter.md
assert_patterns assert_prose docs/dev/flutter.md \
  'app/\.fvmrc.*upgrade.*beta' "explains the pin, the upgrade and the beta run" \
  'tools/smoke\.sh[^.]*`smoke` jobs run it on all six[^.]*twice a day on `main`, not on pull requests' \
  "explains the smoke test, which runs twice a day, not on pull requests" \
  'Before checking in a change under `app/`, run it locally[^.]*on every target your machine can run' \
  "asks for a local smoke test before checking in an app change" \
  'root_isolate_lint' "explains the root-isolate lint"
assert_prose docs/dev/README.md '\(flutter\.md\)' "links the Flutter page"
ADR=docs/adr/0023-flutter-app-shell.md
assert_prose $ADR \
  '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner answered [^*]*photolib-design#278[^*]*photolib-design#294[^*]*photolib-design#315' \
  "is Accepted, recording the owner's answers (#278, #294, #315)"
assert_prose $ADR '\*\*Application ID\.\*\*[^*]*owner chooses it later' "keeps the placeholder ID for now"
assert_prose $ADR '\*\*Platform minimums\.\*\*[^*]*API 30[^*]*iOS 16[^*]*macOS 13' "sets the design's platform minimums"
assert_prose $ADR '\*\*Smoke test\.\*\*[^*]*twice a day on `main`, not on pull requests[^*]*locally' \
  "runs the smoke test twice a day, not on pull requests, and locally before check-in"
assert_prose $ADR '\*\*Smoke test\.\*\*[^*]*owner confirmed[^*]*never run by hand' \
  "records the owner's confirmation that the smoke jobs never run by hand (#315)"
assert_matches docs/adr/README.md '\(0023-flutter-app-shell\.md\) \| [^|]* \| Accepted \(owner answered[^|]*photolib-design#315' \
  "the index lists ADR-0023 as Accepted"
assert_prose AGENTS.md 'app/\.fvmrc.*tools/smoke\.sh.*root_isolate_lint' "AGENTS.md names the pin, smoke test and lint"
assert_prose AGENTS.md \
  'weekly, never on pull requests: [^.]*kernel-\*[^.]*\. Its `smoke` jobs run `bash tools/smoke\.sh.{0,160}twice a day on `main`.{0,120}locally' \
  "AGENTS.md says the costly jobs run weekly, the smoke test twice a day, and to run it locally before check-in"

# --- i18n and accessibility (M0-22): translations live in this repository, as the owner answered (photolib-design#308)
assert_prose docs/dev/translations.md 'pull request.*app_<locale>\.arb.*l10n_test\.dart.*en_XA.*ar_XB.*launchLocales' \
  "keeps translations in the repository, names their test, the pseudo-locales and launching a language"
assert_prose docs/dev/README.md '\(translations\.md\)' "links the translations page"
for doc in docs/dev/translations.md docs/dev/README.md; do
  grep -qi weblate "$doc" && fail "$doc still names Weblate" || ok "$doc names no translation platform"
done
ADR=docs/adr/0030-i18n-and-accessibility-scaffolding.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner answered [^*]*photolib-design#308' \
  "is Accepted, recording the owner's answer (#308)"
assert_prose $ADR '\*\*Translations in the repository\.\*\*[^*]*pull request[^*]*l10n_test\.dart' \
  "keeps translations in the repository, checked by l10n_test.dart"
# the owner's answers to photolib-design#331: 20 machine translations launch at once, Arabic among them, keys sorted
assert_prose $ADR '\* \*\*Status\*\*: Accepted[^*]*photolib-design#331' "records the owner's answers (#331)"
assert_prose $ADR '\*\*Translations in the repository\.\*\*[^*]*machine translations[^*]*test phase' \
  "ships machine translations, reviewed in the test phase"
assert_matches docs/adr/README.md '\(0030-[^)]*\) \| [^|]* \| Accepted \(owner answered[^|]*2026-10-17' \
  "the index records the owner's second answer"
assert_prose docs/dev/translations.md 'sorted.*machine translations[^.]*native speakers[^.]*test phase' \
  "keeps keys sorted, and native speakers review the machine translations in the test phase"
assert_prose docs/dev/translations.md 'server emails[^.]*viewer[^.]*store listings[^.]*completeness test' \
  "applies the rule to every user-facing text surface"
for doc in docs/dev/translations.md docs/dev/flutter.md AGENTS.md $ADR app/lib/l10n/locales.dart; do
  grep -Eqi 'once (it is )?reviewed|reviewed and launched|empty .app_ar\.arb' "$doc" && fail "$doc still waits for a review or an empty app_ar.arb" ||
    ok "$doc launches translations unreviewed, Arabic included"
done
assert_prose tools/README.md 'smoke\.sh.*flutter_upgrade_gate\.py' "tools/README.md names the CI helpers"
assert_prose app/README.md 'go_router.*Riverpod|Riverpod.*go_router' "app/README.md names the app's libraries"

# --- the local database (M0-23)
ADR=docs/adr/0031-local-replica.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner deferred [^*]*photolib-design#309' \
  "is Accepted, recording that the owner deferred the choice (#309)"
assert_prose $ADR 'every table[^*]*synced[^*]*device[^*]*rebuilt[^*]*migration_test' \
  "decides for every table whether a failed migration keeps it"
assert_prose $ADR 'one transaction, so a backup that exists is complete' "writes the backup whole or not at all"
assert_matches docs/adr/README.md '\(0031-local-replica\.md\) \| [^|]* \| Accepted \(owner deferred' \
  "the index lists ADR-0031 as Accepted"
assert_prose docs/dev/flutter.md 'make-migrations.*migration_test.*tools/data/web\.sh.*mergeJournal' \
  "explains schema changes, the probe, web assets and journals"
assert_prose docs/dev/flutter.md 'single_writer_lint' "explains the single-writer check"
assert_prose AGENTS.md 'replica\.drift.*make-migrations.*single_writer_lint.*tools/data/web\.sh' \
  "AGENTS.md names the schema, its migrations, the single-writer lint and the web assets"
assert_prose app/README.md 'packages/photolib_data.*SQLite3MultipleCiphers' "app/README.md names the local replica"
assert_prose tools/README.md 'data/web\.sh.*sqlite3mc\.wasm' "tools/README.md names the replica's web assets"

# --- the design system (M0-25), its three choices confirmed by the owner (photolib-design#329)
ADR=docs/adr/0037-design-system.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#329' \
  "is Accepted, recording the owner's confirmation (#329)"
assert_prose $ADR 'stays in `app/lib/ui/` until a second app needs it' "keeps the design system in app/lib/ui"
[[ -f app/lib/ui/theme.dart && ! -e app/packages/photolib_ui ]] && ok "the design system is app/lib/ui, not a package" ||
  fail "the design system is not app/lib/ui alone"
assert_prose $ADR 'palette \(Ctrl\+K, Cmd\+K on Apple systems\)[^*]*`/` opens Search and Ctrl/Cmd\+, the settings' \
  "opens the palette on Ctrl/Cmd+K, Search on / and the settings on Ctrl/Cmd+,"
assert_prose docs/user/README.md '`\?` lists[^.]*Ctrl\+K \(Cmd\+K on a Mac\)[^.]*`/` opens Search and Ctrl\+, \(Cmd\+,\)' \
  "the user guide gives the same keys"
assert_prose $ADR 'reduce motion they are zero and pages appear without a transition' \
  "shows pages without a transition under reduce motion"
assert_prose $ADR 'Under reduce motion, iOS loses the animated back swipe; the back button remains' \
  "accepts losing iOS's animated back swipe under reduce motion"
assert_matches docs/adr/README.md '\(0037-design-system\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0037 as Accepted"

# --- what the viewer reads of a MediaStore item through its channel, as an animation does
VIEWER=app/android/app/src/main/kotlin/org/photolib/photolib/ViewerChannel.kt
assert_patterns assert_matches "$VIEWER" \
  '"read" ->' "reads an item's bytes for the viewer" \
  'openInputStream' "through the content resolver"

# --- metadata extraction (M1-08): the owner kept its state and isolate and has the app bundle the kernel
# tools/kernel/build.py writes (photolib-design#373); test/core/replica_test.dart proves that extraction runs on it
ADR=docs/adr/0072-device-metadata-extraction.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-17 [^*]*photolib-design#373' \
  "is Accepted, recording the owner's answers (#373)"
assert_prose $ADR 'the app sets no .bundle: false.' "reads with the kernel the app bundles"
assert_prose $ADR '\* \*\*Status\*\*: Accepted[^*]*photolib-design#698' "records the owner's answer on the packages (#698)"
assert_prose $ADR 'packages. own tests keep .bundle: false.[^.]*only the root package.s defines count' \
  "the packages' own tests keep bundle: false, which never reaches the app"
for package in photolib_kernel photolib_data photolib_api photolib_editor; do
  assert_prose "app/packages/$package/pubspec.yaml" 'photolib_kernel:[[:space:]]+bundle: false' \
    "its own tests load the kernel cargo builds"
done
assert_matches docs/adr/README.md '\(0072-device-metadata-extraction\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0072 as Accepted"
assert_prose app/pubspec.yaml 'photolib_kernel:[[:space:]]+artifacts: build/kernel/' \
  "the app bundles the kernel in build/kernel"
grep -q 'bundle: false' app/pubspec.yaml && fail "app/pubspec.yaml leaves the kernel unbundled" ||
  ok "app/pubspec.yaml leaves no kernel unbundled"

# --- the encrypted local store (M0-41): the owner kept both of its answers on Linux without a keyring (#691)
ADR=docs/adr/0057-encrypted-local-store.md
assert_prose $ADR '\* \*\*Status\*\*: Accepted — 2026-10-17 [^*]*kept both[^*]*photolib-design#691' \
  "records the owner's answer (#691)"
assert_prose $ADR 'stays shut, the keyrings named[^.]*while a Secret Service that holds its keys is away[^.]*ADR-0154.s passphrase' \
  "a store whose keys a Secret Service holds stays shut without it; one made without uses the passphrase"
check "ADR-0057 asks the owner nothing more" bash -c "! grep -q 'asked again' $ADR"

# --- the name users see beside the icon is Photolib, not the template's project name (assert_matches ignores case)
named() { grep -qF -- "$2" "app/$1" && ok "app/$1: $3" || fail "app/$1: $3 (no '$2')"; }
named android/app/src/main/AndroidManifest.xml 'android:label="Photolib"' "Android's launcher label"
named web/manifest.json '"name": "Photolib"' "the installed web app's name"
named web/manifest.json '"short_name": "Photolib"' "and its short name"
named web/index.html '<title>Photolib</title>' "the page's title"
named web/index.html 'apple-mobile-web-app-title" content="Photolib"' "iOS's home screen name"
named linux/runner/my_application.cc 'gtk_header_bar_set_title(header_bar, "Photolib")' "the Linux window's header bar"
named linux/runner/my_application.cc 'gtk_window_set_title(window, "Photolib")' "and title bar"
named windows/runner/file_drag.h 'kWindowTitle[] = L"Photolib"' "the Windows window's title"
named windows/runner/main.cpp 'window.Create(kWindowTitle,' "which the window is made with"
[[ $(grep -cF 'FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle)' app/windows/runner/file_drag.cpp) == 2 ]] &&
  ok "and a later start finds it by" || fail "a later start does not find the window by kWindowTitle"
named windows/runner/Runner.rc 'VALUE "FileDescription", "Photolib"' "Windows' file description"
named windows/runner/Runner.rc 'VALUE "ProductName", "Photolib"' "and product name"

finish
