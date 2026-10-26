# ADR-0030 — i18n and accessibility scaffolding: lints, pseudo-locales, self-hosted web fonts

* **Status**: Accepted — 2026-10-16. The owner answered the provisional choices of the i18n and accessibility
  scaffolding (M0-22) in
  photolib-design#308:
  translations live in this repository, with tests that each is complete, instead of on Weblate. The answer does not
  mention the fonts, file sizes or pseudo-locales, which stand as below. On 2026-10-17 the owner answered
  photolib-design#331:
  every translation stays complete, the app launches at once in 20 machine-translated languages, Arabic among them,
  and the ARB keys stay sorted.
* **Requirements**: F-13, NFR-I18N-1, NFR-A11Y-1. **Design**:
  i18n and accessibility,
  client app §7.6.

## Context

The design makes an untranslatable string impossible through CI rules: no UI string literals, directional layout only,
`en-XA` and `ar-XB` pseudo-locales in golden tests. It also asks for 200 % text without clipping, Material
accessibility checks, Weblate, and a web app that fetches no font from a third-party CDN. Flutter's web engine fetches
CanvasKit, Roboto and Noto fallback fonts from Google by default, and gen-l10n needs an `ar` base file for `ar_XB`.

## Decision

* **Lints in `flutter test`.** `app/tool/i18n_lint.dart` lexes `lib/` and rejects a literal with letters where the UI
  shows it (a `…Text` widget, `label:`, `tooltip:`, `title:` and the like) and physical directions (`left:`,
  `EdgeInsets.fromLTRB`, `Alignment.centerRight`, a fixed `TextDirection`). `// i18n-ok: <reason>` excuses a line.
* **Pseudo-locales as ARB files.** `app/tool/pseudo_locales.dart` generates `app_en_XA.arb` (accented, 40 % longer, in
  brackets) and `app_ar_XB.arb` (right-to-left marks; the analyzer rejects the override characters Android uses), and a
  test keeps them current. The Arabic `app_ar.arb` is also the base gen-l10n needs for `ar_XB`. The `pseudoLocales`
  flag adds the two pseudo-locales to `launchLocales`.
* **Page checks.** Every page has a golden in both pseudo-locales (test font, so they match on any platform) and passes
  Material's tap target, label and contrast guidelines. At 200 % text no visible text is clipped or off screen at
  phone, tablet and desktop widths, measured with Roboto.
* **Self-hosted web fonts.** The app bundles Roboto Regular and Medium (Apache-2.0, from the Flutter SDK) as its
  `Roboto` family, so the engine never downloads its default font, and `web/flutter_bootstrap.js` loads CanvasKit from
  the build and fallback fonts from `fonts/` on the app's origin. The gate builds the web app and fails when headless
  Chrome sees a request to another origin.
* **Translations in the repository.** A translation is an `app/lib/l10n/app_<locale>.arb` file changed by pull request,
  with no translation platform or other dependency ([translations page](../dev/translations.md)). Beside English,
  `launchLocales` offers es, fr, de, it, pt (Brazilian), ru, uk, pl, nl, tr, ar, he, hi, ja, ko, zh (Simplified),
  zh-Hant, id, vi and sv: machine translations that ship, which native speakers review in the test phase.
  `app/test/l10n_test.dart` fails when a translation lacks a message of `app_en.arb` or keeps one it no longer has,
  changes its placeholders or select cases, or lacks a plural case its language needs (six in Arabic, four in Russian,
  Ukrainian and Polish); when an ARB file's keys are not sorted; and when the app offers a locale without its file or a
  file without its locale. So the pull request that adds or changes a string translates it into every launched
  language, and English stands in for no string, unlike
  design 17 §3:
  gen-l10n's fallback is only a runtime safety net. Every other user-facing text surface (server emails and errors,
  the viewer, store listings) follows the same rule as it is built, each with its own completeness test; admin and
  developer docs stay English.
* **File sizes** use powers of 1000 (kB, MB), as Android and Apple show them.

## Consequences

* A string in a position the lint does not know (a custom widget's parameter with another name) slips through until
  the name is added.
* Roboto now also renders the app on Android and Linux (the bundled copy replaces the system's), and every build
  carries 340 KB of fonts.
* Nothing serves `fonts/` yet: on the web, scripts Roboto lacks (CJK, Arabic, Hebrew, Devanagari) show boxes until
  photolibd serves the Noto fallbacks with the web client (M2-25), so the web app's ar, he, hi, ja, ko and zh users
  see boxes until then. Nothing is fetched from Google meanwhile.
* The gate's `dart` part needs Chrome and spends about 35 s building the web app.
* A new string needs all 20 translations in the same pull request. The test cannot see a translation that a reworded
  English string left stale, nor a wrong one: users read machine translations until native speakers review them.

## Options considered

* **An analyzer plugin** (`custom_lint` or the analysis server's plugins): squiggles in the IDE, but a new dependency and
  plugin runtime; the lexer runs where the root-isolate lint already does.
* **Pseudo-locales only in tests**: the generated classes cannot be wrapped without generating more code.
* **`--no-web-resources-cdn` alone**: bundles Roboto in release builds but not in `flutter run`, whose text breaks once
  the fallbacks point at the app's origin.
* **Mirroring the Noto fallbacks into the build now**: hundreds of files fetched from Google at build time, for a web
  client that photolibd will serve.
* **Weblate**, hosted on its free plan for free software as design 17 §3 names, or self-hosted: a service and accounts
  outside the repository, which the owner declined.
* **Completeness only for launched languages, or a report of missing strings** (gen-l10n's
  `untranslated-messages-file`) instead of a failing test: a tail of untranslated strings, which the owner declined.
* **Reviewing a language before it launches**, with an empty Arabic base for `ar_XB` until then: the owner chose to
  ship the machine translations and review them in the test phase.
