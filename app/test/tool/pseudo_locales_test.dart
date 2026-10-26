import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/pseudo_locales.dart';

const rlm = '\u200F';

void main() {
  group('en-XA', () {
    test('accents letters and pads by 40 % inside brackets', () {
      expect(pseudo('Done'), '[Ðöñé one]');
      expect(pseudo('Search your library'), '[Šéåŕçĥ ýöûŕ ļîƀŕåŕý one two]');
      expect(pseudo('Hidden (3)!'), '[Ĥîððéñ (3)! one two]');
    });

    test('keeps placeholders and counts them towards the length', () {
      expect(pseudo('Pin {name}'), '[Þîñ {name} one]');
      expect(pseudo('{name}'), '[{name} one]');
    });

    test('accents every case of a plural or select, not its keywords', () {
      expect(
        pseudo('{count, plural, =1{1 photo} other{{count} photos}}'),
        '[{count, plural, =1{1 þĥöţö} other{{count} þĥöţöš}} one two]',
      );
      expect(
        pseudo('Hi {who, select, admin{boss} other{you}}'),
        '[Ĥî {who, select, admin{ƀöšš} other{ýöû}} one]',
      );
    });
  });

  group('ar-XB', () {
    test('marks each run of text right to left, not the placeholders', () {
      expect(pseudo('Pin {name}', rtl: true), '${rlm}Pin $rlm{name}');
      expect(
        pseudo('{n, plural, =1{one} other{{n} many}}', rtl: true),
        '{n, plural, =1{${rlm}one$rlm} other{{n}$rlm many$rlm}}',
      );
    });
  });

  test('a pseudo ARB file has every message and no metadata', () {
    final arb = pseudoArb({
      '@@locale': 'en',
      'done': 'Done',
      '@done': {'description': 'x'},
    }, 'en_XA');
    expect(arb, {'@@locale': 'en_XA', 'done': '[Ðöñé one]'});
  });

  for (final locale in pseudoLocales) {
    test('lib/l10n/app_$locale.arb is up to date', () {
      final template = File('lib/l10n/app_en.arb').readAsStringSync();
      final committed = File('lib/l10n/app_$locale.arb').readAsStringSync();
      expect(
        committed,
        pseudoArbFile(jsonDecode(template) as Map<String, Object?>, locale),
        reason: 'run `dart run tool/pseudo_locales.dart` in app/',
      );
    });
  }
}
