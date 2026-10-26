/// Generates the pseudo-locales of docs/17-i18n-and-accessibility.md §1 from
/// the English ARB file: en-XA (accented, 40 % longer, in brackets) shows
/// truncation and text that bypasses the ARB files, ar-XB (marked right to
/// left, in a right-to-left layout) shows mirroring bugs. The marks are U+200F:
/// the analyzer rejects the override characters Android's ar-XB uses. Run `dart run tool/pseudo_locales.dart` in
/// `app/` after changing `lib/l10n/app_en.arb`.
library;

import 'dart:convert';
import 'dart:io';

const pseudoLocales = ['en_XA', 'ar_XB'];

const _plain = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const _accented = 'åƀçðéƒĝĥîĵķļɱñöþǫŕšţûṽŵẋýžÅƁÇÐÉƑĜĤÎĴĶĻṀÑÖÞǪŔŠŢÛṼŴẊÝŽ';
const _numbers = ['one', 'two', 'three', 'four', 'five', 'six', 'seven'];

String pseudo(String message, {bool rtl = false}) {
  final (body, length) = _Icu(message, rtl).message();
  if (rtl) return body;
  final padding = StringBuffer();
  for (var k = 0; padding.length < (length * 2 + 4) ~/ 5; k++) {
    padding.write(' ${_numbers[k % _numbers.length]}');
  }
  return '[$body$padding]';
}

Map<String, Object?> pseudoArb(Map<String, Object?> template, String locale) =>
    {
      '@@locale': locale,
      for (final MapEntry(:key, :value) in template.entries)
        if (!key.startsWith('@'))
          key: pseudo(value! as String, rtl: locale == 'ar_XB'),
    };

String pseudoArbFile(Map<String, Object?> template, String locale) =>
    '${const JsonEncoder.withIndent('  ').convert(pseudoArb(template, locale))}\n';

void main() {
  final template = File('lib/l10n/app_en.arb').readAsStringSync();
  for (final locale in pseudoLocales) {
    File('lib/l10n/app_$locale.arb').writeAsStringSync(
      pseudoArbFile(jsonDecode(template) as Map<String, Object?>, locale),
    );
  }
}

/// Rewrites the text of an ICU message, leaving placeholders and the
/// keywords of plural and select alone.
class _Icu {
  _Icu(this.s, this.rtl);

  final String s;
  final bool rtl;
  var i = 0;

  /// The message up to an unmatched `}`, and its length as the user sees it.
  (String, int) message() {
    final out = StringBuffer();
    var length = 0;
    while (i < s.length && s[i] != '}') {
      if (s[i] == '{') {
        final (text, n) = argument();
        out.write(text);
        length += n;
        continue;
      }
      final start = i;
      while (i < s.length && s[i] != '{' && s[i] != '}') {
        i++;
      }
      final run = s.substring(start, i);
      out.write(
        rtl
            ? '\u200F$run\u200F'
            : run.split('').map((c) {
                final k = _plain.indexOf(c);
                return k < 0 ? c : _accented[k];
              }).join(),
      );
      length += run.length;
    }
    return (out.toString(), length);
  }

  (String, int) argument() {
    final end = s.indexOf(RegExp('[,}]'), ++i);
    final name = s.substring(i, end).trim();
    i = end + 1;
    if (s[end] == '}') return ('{$name}', name.length);
    final comma = s.indexOf(',', i);
    final type = s.substring(i, comma).trim();
    i = comma + 1;
    final cases = StringBuffer();
    var longest = 0;
    while (true) {
      while (s[i].trim().isEmpty) {
        i++;
      }
      if (s[i] == '}') break;
      final open = s.indexOf('{', i);
      final key = s.substring(i, open).trim();
      i = open + 1;
      final (text, n) = message();
      i++;
      cases.write(' $key{$text}');
      if (n > longest) longest = n;
    }
    i++;
    return ('{$name, $type,$cases}', longest);
  }
}
