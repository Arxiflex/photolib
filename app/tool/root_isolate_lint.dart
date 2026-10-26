/// Keeps blocking work off the root isolate, which is the platform main thread
/// on Android and iOS (docs/10-client-app.md §1.5). Everything under `lib/`
/// runs there, so synchronous I/O, `sleep` and native or database imports are
/// rejected; heavy work goes to a worker or the data isolate. A justified
/// exception carries `// root-isolate-ok: <reason>` on its line or the line
/// above.
library;

import 'dart:io';

class Violation {
  const Violation(this.path, this.line, this.rule, this.advice);

  final String path;
  final int line;
  final String rule;
  final String advice;

  @override
  String toString() => '$path:$line: $rule: $advice';
}

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
final _heavy = RegExp(r'^(?:dart:ffi|package:(?:ffi|drift|sqlite3)/)');
final _literal = RegExp(r'''\x27(?:\\.|[^\x27\\])*\x27|"(?:\\.|[^"\\])*"''');
final _comment = RegExp(r'//.*$');
final _syncCall = RegExp(r'\.\w+Sync\b');
final _sleep = RegExp(r'\bsleep\s*\(');
final _exception = RegExp(r'//\s*root-isolate-ok:\s*\S');

List<Violation> lintSource(String path, String source) {
  final lines = source.split('\n');
  final found = <Violation>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_exception.hasMatch(line) ||
        (i > 0 && _exception.hasMatch(lines[i - 1]))) {
      continue;
    }
    void flag(String rule, String advice) =>
        found.add(Violation(path, i + 1, rule, advice));

    final import = _import.firstMatch(line)?.group(1);
    if (import != null) {
      if (_heavy.hasMatch(import)) {
        flag(
          'heavy-import',
          'move $import behind the data isolate or a worker',
        );
      }
      continue;
    }
    final code = line.replaceAll(_literal, "''").replaceAll(_comment, '');
    if (_syncCall.hasMatch(code)) {
      flag('sync-io', 'use the asynchronous call or run it on a worker');
    }
    if (_sleep.hasMatch(code)) {
      flag('sleep', 'await Future.delayed instead of blocking the isolate');
    }
  }
  return found;
}

List<Violation> lintTree(Directory root) => [
  for (final file in root.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart'))
      ...lintSource(file.path, file.readAsStringSync()),
];
