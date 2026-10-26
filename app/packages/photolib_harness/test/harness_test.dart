// The harness fails what it should, proved on the fixtures in test/fixtures/,
// which flutter test leaves out of a normal run; main runs them (untimed).

import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_harness/testing.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final strict = await outcomes([
    'flutter',
    'test',
    '--no-pub',
    'test/fixtures/strict.dart',
  ]);
  final timeout = await outcomes([
    'flutter',
    'test',
    '--no-pub',
    'test/fixtures/timeout.dart',
  ]);
  final browser = await outcomes([
    'dart',
    'test',
    ...'-p chrome -p firefox -c dart2js -c dart2wasm'.split(' '),
    'test/fixtures/browser.dart',
  ]);

  test('a test fails on an unhandled async error and a reported problem, '
      'unless it takes the problem, and so does a problem of setUpAll or '
      'tearDownAll', () {
    expect(strict, {
      'clean': ['passed'],
      'unhandled async error': [contains('an error nobody awaits')],
      'error after the test': [contains('an error once it is over')],
      'reported problem': [contains('a problem nobody took')],
      'taken': ['passed'],
      'setUpAll then a test': [contains('a problem of setUpAll')],
      'tearDownAll after a test': ['passed'],
      '(tearDownAll)': [contains('a problem of tearDownAll')],
    });
  });

  test("a test's timeout counts no time its process was stopped", () {
    expect(timeout, {
      'stopped past its timeout': ['passed'],
      'hung': [contains('Test timed out after 1 seconds.')],
    });
  });

  test('a browser test fails on an uncaught error, an unhandled rejection or '
      'console.error in the page, unless it takes the problem', () {
    final runs = hasLength(4);
    expect(browser, {
      'clean': allOf(runs, everyElement('passed')),
      'console.error': allOf(
        runs,
        everyElement(contains('console.error: an error the page logs')),
      ),
      'console.error with five arguments': allOf(
        runs,
        everyElement(contains('console.error: one two three four five')),
      ),
      'uncaught error': allOf(
        runs,
        everyElement(contains('Uncaught error in the page')),
      ),
      'unhandled rejection': allOf(
        runs,
        everyElement(contains('Unhandled rejection in the page: a rejection')),
      ),
      'taken': allOf(runs, everyElement('passed')),
    });
  });

  test('a nested run refuses to start under a timeout', () {
    expect(() => outcomes(['true']), throwsStateError);
  });

  test('a printer reports the error-level log records it prints', () {
    final printed = <String?>[];
    final print = reportingErrorLogs((message, {wrapWidth}) {
      printed.add(message);
    });
    const lines = [
      '{"level":"error","message":"m"}',
      '{"level":"warning","message":"error"}',
      'error: {"level":"error"}',
      '{"level":"error"',
      '[{"level":"error"}]',
    ];
    lines.forEach(print);
    expect(printed, lines);
    expect(takeProblems(), [
      'Error-level log record: {"level":"error","message":"m"}',
    ]);
  });
}
