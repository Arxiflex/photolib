// Run by harness_test.dart with flutter test, under the
// flutter_test_config.dart next to it: every test but 'clean', 'taken' and
// 'tearDownAll after a test' must fail, and the suite's tearDownAll.
import 'dart:async';

import 'package:photolib_harness/photolib_harness.dart';
import 'package:test/test.dart';

import 'flutter_test_config.dart';

void main() {
  test('clean', () {});

  test('unhandled async error', () {
    unawaited(Future<void>.error(StateError('an error nobody awaits')));
  });

  test('error after the test', () {
    Timer(Duration.zero, () => throw StateError('an error once it is over'));
  });

  test('reported problem', () => problem('a problem nobody took'));

  test('taken', () {
    problem('a problem the test expects');
    expect(takeProblems(), ['a problem the test expects']);
  });

  group('setUpAll', () {
    setUpAll(() => problem('a problem of setUpAll'));
    test('then a test', () {});
  });

  group('tearDownAll', () {
    tearDownAll(() => problem('a problem of tearDownAll'));
    test('after a test', () {});
  });
}
