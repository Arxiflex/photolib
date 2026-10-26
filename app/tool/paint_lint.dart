/// Gives every Paint one purpose (photolib-design#462). A Paint is state: a
/// static one is shared by every painter, and a changed one carries its colour
/// into the next draw that uses it, alpha included, which `drawImageRect`
/// applies as the image's opacity. So no Paint is static, and none changes
/// once made: each purpose has its own.
library;

import 'dart:io';

import 'root_isolate_lint.dart' show Violation;

final _comment = RegExp(r'//[^\n]*');
final _static = RegExp(
  r'\bstatic\s+(?:late\s+)?(?:final\s+|var\s+)?'
  r'(?:Paint\s+\w+\s*[=;]|\w+\s*=\s*Paint\s*\()',
);
final _named = RegExp(r'\b(\w+)\s*=\s*Paint\s*\(|\bPaint\s+(\w+)\s*[=;]');
const _properties =
    'color|shader|blendMode|colorFilter|style|strokeWidth|strokeCap|'
    'strokeJoin|strokeMiterLimit|filterQuality|maskFilter|imageFilter|'
    'isAntiAlias|invertColors';

List<Violation> lintSource(String path, String source) {
  final code = source.replaceAll(_comment, '');
  int line(Match m) => '\n'.allMatches(code.substring(0, m.start)).length + 1;
  final names = {for (final m in _named.allMatches(code)) m[1] ?? m[2]};
  final changed = RegExp(
    '\\b(?:${names.join('|')})\\s*\\.\\.?(?:$_properties)\\s*=(?!=)',
  );
  return [
    for (final m in _static.allMatches(code))
      Violation(path, line(m), 'static-paint', 'give each painter its own'),
    if (names.isNotEmpty)
      for (final m in changed.allMatches(code))
        Violation(path, line(m), 'changed-paint', 'make one for this purpose'),
  ];
}

List<Violation> lintTree(Directory root) => [
  for (final file in root.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart'))
      ...lintSource(file.path, file.readAsStringSync()),
];
