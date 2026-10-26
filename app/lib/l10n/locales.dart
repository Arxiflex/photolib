import 'package:material_ui/material_ui.dart';

/// The translations offered to users: all of them, as each is complete (`pt`
/// is Brazilian Portuguese, `zh` Simplified Chinese). English comes first, for
/// devices in any other language.
const launchLocales = [
  Locale('en'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('it'),
  Locale('pt'),
  Locale('ru'),
  Locale('uk'),
  Locale('pl'),
  Locale('nl'),
  Locale('tr'),
  Locale('ar'),
  Locale('he'),
  Locale('hi'),
  Locale('ja'),
  Locale('ko'),
  Locale('zh'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('id'),
  Locale('vi'),
  Locale('sv'),
];

/// The pseudo-locales of layout tests, offered when the `pseudoLocales` flag
/// is on.
const pseudoLocales = [Locale('en', 'XA'), Locale('ar', 'XB')];
