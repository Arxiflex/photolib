// Run by harness_test.dart with dart test in browsers: every test but
// 'clean' and 'taken' must fail.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:photolib_harness/photolib_harness.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

Future<void> settle() => Future<void>.delayed(const Duration(seconds: 1));

void main() {
  strict();

  test('clean', settle);

  test('console.error', () {
    web.console.error('an error the page logs'.toJS);
  });

  test('console.error with five arguments', () {
    web.console.callMethodVarArgs<JSAny?>('error'.toJS, [
      for (final word in 'one two three four five'.split(' ')) word.toJS,
    ]);
  });

  test('uncaught error', () async {
    void fail() => throw StateError('an error no zone sees');
    web.window.setTimeout(fail.toJS, 0.toJS);
    await settle();
  });

  test('unhandled rejection', () async {
    (globalContext['Promise'] as JSObject?)?.callMethod<JSAny?>(
      'reject'.toJS,
      'a rejection'.toJS,
    );
    await settle();
  });

  test('taken', () {
    web.console.error('an error the test expects'.toJS);
    expect(takeProblems(), ['console.error: an error the test expects']);
  });
}
