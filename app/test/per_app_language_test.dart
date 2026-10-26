// Android 13+, iOS and macOS list an app's languages in their per-app language
// setting from what it declares: Android's locale config, Apple's
// CFBundleLocalizations.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/l10n/locales.dart';

import 'ios_strings_test.dart' show lproj;

List<String?> names(String text, String pattern) => [
  for (final m in RegExp(pattern).allMatches(text)) m[1],
];

void main() {
  final tags = [for (final locale in launchLocales) lproj(locale)];

  test('Android 13+ offers the launch languages', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:localeConfig="@xml/locales_config"'),
    );
    expect(
      names(
        File('android/app/src/main/res/xml/locales_config.xml')
            .readAsStringSync(),
        '<locale android:name="([^"]+)"',
      ),
      tags,
    );
  });

  for (final os in ['ios', 'macos']) {
    test('$os offers the launch languages', () {
      final plist = File('$os/Runner/Info.plist').readAsStringSync();
      expect(
        names(
          RegExp(
                r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
                dotAll: true,
              ).firstMatch(plist)?[1] ??
              '',
          '<string>([^<]+)</string>',
        ),
        tags,
      );
    });
  }
}
