/// Enforces two rules of docs/17-i18n-and-accessibility.md §1 on `lib/`: no
/// user-facing string literal (text goes in `lib/l10n/app_en.arb`), and only
/// directional layout (start and end, never left and right). A justified
/// exception carries `// i18n-ok: <reason>` on its line or the line above.
library;

import 'dart:io';

import 'root_isolate_lint.dart' show Violation;

// The source before a literal that shows it to the user: the first argument of
// a `…Text` widget or a text-bearing named argument, up to the literal itself.
final _uiPosition = RegExp(
  r'(?:\b(?:[A-Z]\w*)?Text\s*\(|\b(?:label|labelText|hintText|helperText|errorText'
  r'|counterText|prefixText|suffixText|semanticLabel|semanticsLabel|tooltip'
  r'|message|title|text|hint)\s*:)[^,;(){}\[\]]*$',
);
final _letter = RegExp(r'\p{L}', unicode: true);
final _physical = RegExp(
  r'[(,]\s*(?:left|right|topLeft|topRight|bottomLeft|bottomRight)\s*:'
  r'|\bEdgeInsets\.fromLTRB\b|\b(?:Alignment|FractionalOffset)\.\w+(?:Left|Right)\b'
  r'|\bTextAlign\.(?:left|right)\b|\bTextDirection\.(?:ltr|rtl)\b',
);
final _exception = RegExp(r'//\s*i18n-ok:\s*\S');

List<Violation> lintSource(String path, String source) {
  final lexed = _Lexer(source)..code();
  final masked = String.fromCharCodes(lexed.masked);
  final lines = source.split('\n');
  final found = <Violation>[];
  void flag(int offset, String rule, String advice) {
    final line = '\n'.allMatches(source.substring(0, offset)).length;
    if (_exception.hasMatch(lines[line]) ||
        (line > 0 && _exception.hasMatch(lines[line - 1]))) {
      return;
    }
    found.add(Violation(path, line + 1, rule, advice));
  }

  for (final (:start, :text) in lexed.literals) {
    final before = masked.substring(start < 300 ? 0 : start - 300, start);
    if (_letter.hasMatch(text) && _uiPosition.hasMatch(before)) {
      flag(start, 'ui-string', 'add it to lib/l10n/app_en.arb');
    }
  }
  for (final match in _physical.allMatches(masked)) {
    flag(match.start, 'directional', 'use start/end or the …Directional form');
  }
  found.sort((a, b) => a.line.compareTo(b.line));
  return found;
}

List<Violation> lintTree(Directory root) => [
  for (final file in root.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart'))
      ...lintSource(file.path, file.readAsStringSync()),
];

/// Finds the string literals of Dart source, with their interpolations left
/// out, and masks comments and literals with spaces.
class _Lexer {
  _Lexer(this.src) : masked = src.codeUnits.toList();

  final String src;
  final List<int> masked;
  final literals = <({int start, String text})>[];
  var i = 0;

  static final _identifier = RegExp(r'[\w$]');

  void blank(int from, int to) {
    for (var k = from; k < to && k < src.length; k++) {
      if (masked[k] != 0x0a) masked[k] = 0x20;
    }
  }

  /// Code up to the end, or up to the `}` closing an interpolation.
  void code({bool nested = false}) {
    var depth = 0;
    while (i < src.length) {
      final c = src[i];
      if (src.startsWith('//', i)) {
        final end = src.indexOf('\n', i);
        blank(i, i = end < 0 ? src.length : end);
      } else if (src.startsWith('/*', i)) {
        final start = i;
        var comments = 0;
        do {
          if (src.startsWith('/*', i)) {
            comments++;
            i += 2;
          } else if (src.startsWith('*/', i)) {
            comments--;
            i += 2;
          } else {
            i++;
          }
        } while (comments > 0 && i < src.length);
        blank(start, i);
      } else if (c == "'" || c == '"' || _rawStart()) {
        string();
      } else if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        if (nested && depth == 0) return;
        depth--;
        i++;
      } else {
        i++;
      }
    }
  }

  bool _rawStart() =>
      src[i] == 'r' &&
      i + 1 < src.length &&
      (src[i + 1] == "'" || src[i + 1] == '"') &&
      (i == 0 || !_identifier.hasMatch(src[i - 1]));

  void string() {
    final start = i;
    final raw = src[i] == 'r';
    if (raw) i++;
    final quote = src.startsWith("'''", i) || src.startsWith('"""', i)
        ? src.substring(i, i + 3)
        : src[i];
    i += quote.length;
    final text = StringBuffer();
    while (i < src.length && !src.startsWith(quote, i)) {
      final c = src[i];
      if (quote.length == 1 && c == '\n') break;
      if (!raw && c == r'\') {
        i += 2;
      } else if (!raw && src.startsWith(r'${', i)) {
        i += 2;
        code(nested: true);
        i++;
      } else if (!raw && c == r'$') {
        i++;
        while (i < src.length && _identifier.hasMatch(src[i])) {
          i++;
        }
      } else {
        text.write(c);
        i++;
      }
    }
    i += quote.length;
    literals.add((start: start, text: text.toString()));
    blank(start, i);
  }
}
