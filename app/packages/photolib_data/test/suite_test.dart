// The suite's own rules, read off its VM tests as dart format lays them out:
// a test runs from `test(` to the `)` at its indentation.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

final _files = <String, String>{
  for (final file in Directory(
    'test',
  ).listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('_test.dart'))
      if (file.readAsStringSync() case final source
          when !source.contains(
            RegExp(r"^@TestOn\('browser'\)", multiLine: true),
          ))
        file.path: source,
};

/// Each match of [pattern] in [source], with its place as `path:line`.
Iterable<(String, Match)> _find(String path, String source, RegExp pattern) =>
    pattern
        .allMatches(source)
        .map(
          (m) => (
            '$path:${'\n'.allMatches(source.substring(0, m.start)).length + 1}',
            m,
          ),
        );

void main() {
  test(
    'a test that measures time or works through a hundred thousand items runs '
    'alone, after the rest of the gate: beside it a loaded machine fails it',
    () {
      expect([
        for (final MapEntry(key: path, value: source) in _files.entries)
          if (!source.contains(
            RegExp(r"^@Tags\(\['alone'\]\)", multiLine: true),
          ))
            for (final (at, test) in _find(
              path,
              source,
              RegExp(
                r'^( *)test\(.*\n(?:(?:\1 .*)?\n)*(?:\1[)}].*\n)?',
                multiLine: true,
              ),
            ))
              if (RegExp(
                    r'Stopwatch\(|withinFrameBudget\(|\d{3},\d{3}\b',
                  ).hasMatch(test[0]!) &&
                  !RegExp(r"tags: \[?'alone'").hasMatch(test[0]!))
                at,
      ], isEmpty);
    },
  );

  test("no test's timeout is shorter than dart_test.yaml's: a loaded machine's "
      'disk stalls the vault for longer', () {
    final factor = RegExp(
      r'^timeout: (\d+)x$',
      multiLine: true,
    ).firstMatch(File('dart_test.yaml').readAsStringSync())![1]!;
    expect([
      for (final MapEntry(key: path, value: source) in _files.entries)
        for (final (at, timeout) in _find(
          path,
          source,
          RegExp(r'Timeout\(Duration\((seconds|minutes): (\d+)\)'),
        ))
          if (int.parse(timeout[2]!) * (timeout[1] == 'minutes' ? 60 : 1) <
              int.parse(factor) * 30)
            at,
    ], isEmpty);
  });
}
