/// Runs test suites, as the harness's own tests and the packages' tests of
/// their harness do on fixtures that fail on purpose.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test_api/hooks.dart' show TestFailure;

/// Throws in a test, `setUpAll` or `tearDownAll`: [what] runs a toolchain
/// that may wait minutes on locks other checkouts share (the Flutter SDK's
/// startup lock, a browser slot, cargo's), longer than their timeouts; a
/// suite's `main` runs with none.
void untimed(String what) {
  // package:test runs each in a zone that holds its invoker under this key.
  if (Zone.current[#test.invoker] != null) {
    throw StateError('$what runs under a test timeout: call it in main');
  }
}

/// How each run of each test of the suite that [command] runs ended, by test
/// name: 'passed', or its errors. Call it in `main` ([untimed]).
Future<Map<String, List<String>>> outcomes(List<String> command) async {
  untimed(command.join(' '));
  final run = await Process.run(
    command.first,
    [...command.skip(1), '--reporter=json'],
    environment: const {'MOZ_HEADLESS': '1'},
  );
  final tests = <int, (String, List<String>)>{};
  final hidden = <int>{};
  for (final line in LineSplitter.split('${run.stdout}')) {
    if (!line.startsWith('{')) continue;
    switch (jsonDecode(line)) {
      case {
        'type': 'testStart',
        'test': {'id': final int id, 'name': final String name},
      }:
        tests[id] = (name, []);
      case {'type': 'error', 'testID': final int id, 'error': final String e}:
        tests[id]?.$2.add(e);
      case {'type': 'testDone', 'testID': final int id, 'hidden': true}:
        hidden.add(id);
    }
  }
  final outcomes = <String, List<String>>{};
  for (final MapEntry(key: id, value: (name, errors)) in tests.entries) {
    if (hidden.contains(id) && errors.isEmpty) continue;
    (outcomes[name] ??= []).add(errors.isEmpty ? 'passed' : errors.join('\n'));
  }
  if (outcomes.isEmpty) {
    throw TestFailure('${command.join(' ')}:\n${run.stdout}${run.stderr}');
  }
  return outcomes;
}
