// Run by harness_test.dart with flutter test, under
// test/flutter_test_config.dart: every test but 'clean' and 'taken' must fail.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib_harness/photolib_harness.dart';

void main() {
  final container = ProviderContainer();
  final logger = container.read(loggerProvider);

  testWidgets('clean', (tester) async {
    await tester.pumpWidget(const SizedBox());
    logger.warning('a warning');
  });

  test('FlutterError', () {
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('a framework error')),
    );
  });

  testWidgets('FlutterError in a widget test', (tester) async {
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('a widget error')),
    );
  });

  test('error-level log record', () {
    logger.error('an error the app logs');
  });

  testWidgets('error-level log record in a widget test', (tester) async {
    logger.error('an error the app logs in a widget test');
  });

  test('unhandled async error', () {
    unawaited(Future<void>.error(StateError('an error nobody awaits')));
  });

  test('taken', () {
    logger.error('an error the test expects');
    expect(takeProblems(), [contains('an error the test expects')]);
  });
}
