import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/feature_flags.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/locales.dart';

import '../tool/pseudo_locales.dart' as pseudo;
import 'support/pump_app.dart';

Map<String, Object?> read(File arb) =>
    jsonDecode(arb.readAsStringSync()) as Map<String, Object?>;

Set<String> messages(File arb) => {
  for (final MapEntry(:key, :value) in read(arb).entries)
    if (!key.startsWith('@') && value is String && value.isNotEmpty) key,
};

final arbs = Directory('lib/l10n')
    .listSync()
    .whereType<File>()
    .where((file) => file.path.endsWith('.arb'));

typedef Argument = ({String name, String? type, Map<String, String> cases});

/// Every argument of an ICU [message], nested ones too, with the text of each
/// case of a plural or select.
List<Argument> arguments(String message) {
  final found = <Argument>[];
  var i = 0;
  late String Function() text;
  void argument() {
    final end = message.indexOf(RegExp('[,}]'), ++i);
    final name = message.substring(i, end).trim();
    i = end + 1;
    if (message[end] == '}') {
      found.add((name: name, type: null, cases: {}));
      return;
    }
    final comma = message.indexOf(',', i);
    final type = message.substring(i, comma).trim();
    final cases = <String, String>{};
    for (i = comma + 1; ; i++) {
      while (message[i].trim().isEmpty) {
        i++;
      }
      if (message[i] == '}') break;
      final open = message.indexOf('{', i);
      final key = message.substring(i, open).trim();
      i = open + 1;
      cases[key] = text();
    }
    i++;
    found.add((name: name, type: type, cases: cases));
  }

  text = () {
    final start = i;
    while (i < message.length && message[i] != '}') {
      if (message[i] == '{') {
        argument();
      } else {
        i++;
      }
    }
    return message.substring(start, i);
  };
  text();
  return found;
}

/// The plural case gen-l10n's code shows for [count]: `Intl.pluralLogic`
/// takes `=0`, `=1` and `=2` as zero, one and two, and prefers a [given] one
/// of them for exactly 0, 1 and 2 over [locale]'s grammar.
String pluralCase(int count, String locale, Set<String> given) {
  const exact = ['zero', 'one', 'two'];
  if (count < 3 && given.contains(exact[count])) return exact[count];
  return Intl.pluralLogic(
    count,
    locale: locale,
    zero: 'zero',
    one: 'one',
    two: 'two',
    few: 'few',
    many: 'many',
    other: 'other',
    useExplicitNumberCases: false,
  );
}

void main() {
  test('every ARB file keeps its messages sorted, each description after '
      'its message', () {
    for (final arb in arbs) {
      final keys = read(arb).keys.toList();
      final names = keys.where((key) => !key.startsWith('@')).toList()..sort();
      expect(keys, [
        '@@locale',
        for (final name in names) ...[
          name,
          if (keys.contains('@$name')) '@$name',
        ],
      ], reason: '${arb.path} is out of order');
    }
  });

  test('every translation has every message of app_en.arb and no other', () {
    final english = messages(File('lib/l10n/app_en.arb'));
    for (final arb in arbs) {
      final translated = messages(arb);
      expect(
        english.difference(translated),
        isEmpty,
        reason: '${arb.path} lacks these messages',
      );
      expect(
        translated.difference(english),
        isEmpty,
        reason: '${arb.path} has messages app_en.arb lacks',
      );
    }
  });

  test('every translation keeps the placeholders and select cases of '
      'app_en.arb and has the plural cases its language needs', () {
    final english = read(File('lib/l10n/app_en.arb'));
    final counts = [for (var n = 0; n <= 200; n++) n, 1000000, 2000000];
    for (final arb in arbs) {
      final translation = read(arb);
      final locale = translation['@@locale']! as String;
      if (pseudo.pseudoLocales.contains(locale)) continue;
      for (final MapEntry(:key, :value) in translation.entries) {
        if (key.startsWith('@')) continue;
        final where = '${arb.path}: $key';
        final englishArguments = arguments(english[key]! as String);
        final source = {
          for (final argument in englishArguments)
            if (argument.type != null) argument.name: argument,
        };
        final found = arguments(value! as String);
        expect(
          found.map((argument) => argument.name).toSet(),
          englishArguments.map((argument) => argument.name).toSet(),
          reason: '$where has other placeholders than English',
        );
        for (final (:name, :type, :cases) in found) {
          if (type == null) continue;
          expect(type, source[name]?.type, reason: '$where: $name');
          if (type == 'select') {
            expect(
              cases.keys,
              unorderedEquals(source[name]!.cases.keys),
              reason: '$where: $name',
            );
            continue;
          }
          final given = {
            for (final MapEntry(:key, :value) in cases.entries)
              const {'=0': 'zero', '=1': 'one', '=2': 'two'}[key] ?? key: value,
          };
          final shown = <String, Set<int>>{};
          for (final count in counts) {
            shown
                .putIfAbsent(
                  pluralCase(count, locale, given.keys.toSet()),
                  () => {},
                )
                .add(count);
          }
          expect(
            given.keys,
            containsAll({
              ...shown.keys,
              'other',
              if (source[name]!.cases.containsKey('=0')) 'zero',
            }),
            reason: '$where lacks plural cases',
          );
          for (final MapEntry(key: plural, value: numbers) in shown.entries) {
            if (numbers.length < 2) continue;
            expect(
              given[plural],
              contains('{$name}'),
              reason: '$where: $plural stands for ${numbers.take(3)}…',
            );
          }
        }
      }
    }
  });

  test('the app offers English, its 20 translations and nothing else', () {
    expect(
      AppLocalizations.supportedLocales,
      unorderedEquals([...launchLocales, ...pseudoLocales]),
    );
    expect(
      launchLocales.map((locale) => locale.toLanguageTag()),
      'en es fr de it pt ru uk pl nl tr ar he hi ja ko zh zh-Hant id vi sv'
          .split(' '),
    );
  });

  testWidgets('the app strings load beside the Material ones', (tester) async {
    late AppLocalizations strings;
    late MaterialLocalizations material;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            strings = AppLocalizations.of(context);
            material = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(strings.appTitle, 'Photolib');
    expect(strings.hiddenCollections(2), 'Hidden (2)');
    expect(material.okButtonLabel, 'OK');
  });

  TextDirection direction(WidgetTester tester) =>
      Directionality.of(tester.element(find.byType(NavigationBar)));

  testWidgets('a device in Arabic gets Arabic, right to left', (tester) async {
    await pumpApp(tester, locales: const [Locale('ar')]);
    final arabic = read(File('lib/l10n/app_ar.arb'));
    expect(find.text(arabic['tabLibrary']! as String), findsOneWidget);
    expect(direction(tester), TextDirection.rtl);
  });

  testWidgets('a device in a language without a translation gets English, '
      'left to right', (tester) async {
    await pumpApp(tester, locales: const [Locale('fi')]);
    expect(find.text('Library'), findsOneWidget);
    expect(direction(tester), TextDirection.ltr);
  });

  group('with the pseudoLocales flag', () {
    final flag = featureFlagsProvider.overrideWithValue(
      FeatureFlags.parse('pseudoLocales'),
    );

    testWidgets('en-XA shows accented, longer text', (tester) async {
      await pumpApp(
        tester,
        locales: const [Locale('en', 'XA')],
        overrides: [flag],
      );
      expect(find.text('[Ļîƀŕåŕý one]'), findsOneWidget);
    });

    testWidgets('ar-XB lays the app out right to left', (tester) async {
      await pumpApp(
        tester,
        locales: const [Locale('ar', 'XB')],
        overrides: [flag],
      );
      expect(find.text('\u200FLibrary\u200F'), findsOneWidget);
      expect(direction(tester), TextDirection.rtl);
    });
  });
}
