// iOS shows the purpose strings of Info.plist when it asks for access, in the
// device's language: each launched language has them in its InfoPlist.strings,
// and the home screen widgets' text in WidgetExtension's Localizable.strings.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Locale;
import 'package:photolib/l10n/locales.dart';

/// Apple's folder for [locale]: `zh` is Simplified Chinese, `pt` Brazilian.
String lproj(Locale locale) => switch (locale.toLanguageTag()) {
  'zh' => 'zh-Hans',
  'pt' => 'pt-BR',
  final tag => tag,
};

Map<String, String> entries(String text, RegExp entry) => {
  for (final m in entry.allMatches(text)) m[1]!: m[2]!,
};

void main() {
  final english = entries(
    File('ios/Runner/Info.plist').readAsStringSync(),
    RegExp(r'<key>(NS\w+UsageDescription)</key>\s*<string>([^<]+)</string>'),
  );
  final project = File('ios/Runner.xcodeproj/project.pbxproj')
      .readAsStringSync();
  final regions = RegExp(r'knownRegions = \(([^)]*)\)')
      .firstMatch(project)![1]!
      .split(',')
      .map((r) => r.trim().replaceAll('"', ''));

  test('Info.plist says why Photolib reads and adds to Photos', () {
    expect(
      english.keys,
      containsAll([
        'NSPhotoLibraryUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
      ]),
    );
  });

  for (final locale in launchLocales) {
    test('iOS asks in ${lproj(locale)}', () {
      final file = File('ios/Runner/${lproj(locale)}.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
      final translated = entries(
        file.readAsStringSync(),
        RegExp(r'^"(\w+)" = "((?:[^"\\]|\\.)+)";$', multiLine: true),
      );
      expect(translated.keys, unorderedEquals(english.keys));
      for (final MapEntry(:key, :value) in translated.entries) {
        expect(
          value,
          locale.languageCode == 'en' ? english[key] : isNot(english[key]),
          reason: key,
        );
      }
      expect(
        project,
        contains(
          RegExp('path = "?${RegExp.escape(file.path.substring(11))}"?;'),
        ),
      );
      expect(regions, contains(lproj(locale)));
    });
  }

  test('the app bundles them', () {
    final runner = RegExp(
      r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{[^}]*\}',
    ).firstMatch(project)![0]!;
    expect(runner, contains('/* InfoPlist.strings in Resources */'));
  });

  group("the widgets' text", () {
    final widgets = RegExp(
      r'(?:Text|configurationDisplayName|description)\("([^"]+)"\)',
    ).allMatches(File('ios/WidgetExtension/Widgets.swift').readAsStringSync());
    final english = {for (final m in widgets) m[1]!};

    test('is in the widgets', () => expect(english, hasLength(4)));

    for (final locale in launchLocales) {
      test('is in ${lproj(locale)}', () {
        final file = File(
          'ios/WidgetExtension/${lproj(locale)}.lproj/Localizable.strings',
        );
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        final translated = entries(
          file.readAsStringSync(),
          RegExp(r'^"([^"]+)" = "((?:[^"\\]|\\.)+)";$', multiLine: true),
        );
        expect(translated.keys, unorderedEquals(english));
        for (final MapEntry(:key, :value) in translated.entries) {
          expect(
            value,
            locale.languageCode == 'en' ? key : isNot(key),
            reason: key,
          );
        }
        expect(
          project,
          contains(
            RegExp('path = "?${RegExp.escape(file.path.substring(20))}"?;'),
          ),
        );
      });
    }

    test('the widget extension bundles it', () {
      final target = RegExp(
        r'/\* WidgetExtension \*/ = \{[^}]*buildPhases = \([^)]*'
        r'(\w{24}) /\* Resources \*/',
      ).firstMatch(project)![1]!;
      expect(
        RegExp('$target /\\* Resources \\*/ = \\{[^}]*\\}')
            .firstMatch(project)![0],
        contains('/* Localizable.strings in Resources */'),
      );
    });
  });
}
