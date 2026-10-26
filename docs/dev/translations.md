# Translations

The app's translations live in this repository and change by pull request, with no translation platform, as the owner
chose in photolib-design#308 and
#331;
[ADR-0030](../adr/0030-i18n-and-accessibility-scaffolding.md) records it.

* `app/lib/l10n/app_en.arb` is the source: every string, with an `@description` for translators. Its keys stay sorted,
  each description after its message, so that parallel pull requests add strings in different places.
* Beside English, the app launches in es, fr, de, it, pt, ru, uk, pl, nl, tr, ar, he, hi, ja, ko, zh, zh_Hant, id, vi
  and sv. gen-l10n needs a base per language: `app_pt.arb` is Brazilian, `app_zh.arb` Simplified. These are machine
  translations that ship; native speakers review them in the test phase.
* A translation is `app/lib/l10n/app_<locale>.arb` with every message of `app_en.arb` in the same order, the same
  placeholders and select cases, and every plural case its language needs (zero, one, two, few, many and other in
  Arabic; one, few, many and other in Russian, Ukrainian and Polish). `app/test/l10n_test.dart` fails on a missing or
  left-over message, another placeholder or select case, a missing plural case or one that stands for several numbers
  without showing the number, unsorted keys, and a locale the app offers without its file or the reverse.
* `app_en_XA.arb` and `app_ar_XB.arb` are generated pseudo-locales, never translated.

## Rules for developers

* Add or change a string in `app_en.arb`, with an `@description`, and in every translation in the same pull request;
  then run `dart run tool/pseudo_locales.dart` and then `flutter gen-l10n` in `app/`. No string waits for a
  translation: gen-l10n's fallback to English is only a runtime safety net. The tests fail on a missing message or a
  stale pseudo-locale, and the gate on generated localizations that `flutter pub get` regenerates differently.
* A new language is a complete `app_<locale>.arb` (its `languageName` the language's own name) and its entry in
  `launchLocales` (`app/lib/l10n/locales.dart`), `locales_config.xml` and `CFBundleLocalizations`, together.
* Every other user-facing text surface follows the same rule as it is built (server emails and errors, the viewer,
  store listings): all launched languages in the same change, each surface with its own completeness test. Admin and
  developer docs stay English.
* iOS's purpose strings (`NS…UsageDescription` of `app/ios/Runner/Info.plist`) live in
  `app/ios/Runner/<language>.lproj/InfoPlist.strings`, the home screen widgets' text in
  `app/ios/WidgetExtension/<language>.lproj/Localizable.strings`, one per launched language and in the Xcode project
  (`app/test/ios_strings_test.dart`).
* String freeze: in the week before a release, `app_en.arb` changes only to fix a string.
* A failure shows as its cause and next step in plain words, the technical detail behind *Details* with copy (OPS-30):
  `ProblemView` or `showProblem` of `app/lib/core/problems.dart`, whose catalogue gives every reason photolibd sends
  (`ApiError`) a `problem…` cause and a `next…` step. `tools/tests/check_errors.py` fails on a reason without them in
  every language, on a message that shows a code, an exception class or a stack frame, and on Dart or TypeScript that
  shows a raw error, unless `// error-ok: <why>` says why.
