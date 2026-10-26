// Run by harness_test.dart with flutter test in Chrome, under
// test/flutter_test_config.dart: every test but 'clean' and 'taken' must fail.
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:web/web.dart' as web;

void main() {
  final logger = ProviderContainer().read(loggerProvider);

  testWidgets('clean', (tester) async {
    await tester.pumpWidget(const SizedBox());
  });

  test('FlutterError', () {
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('a framework error')),
    );
  });

  test('error-level log record', () {
    logger.error('an error the app logs');
  });

  test('console.error', () {
    web.console.error('an error the page logs'.toJS);
  });

  test('uncaught error', () async {
    void fail() => throw StateError('an error no zone sees');
    web.window.setTimeout(fail.toJS, 0.toJS);
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  test('taken', () {
    web.console.error('an error the test expects'.toJS);
    expect(takeProblems(), ['console.error: an error the test expects']);
  });
}
