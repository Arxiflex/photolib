// The app's tests fail on a FlutterError and an error-level log record, and
// in a browser on the page's errors too, proved on fixture.dart and
// web_fixture.dart, which flutter test leaves out of a normal run; main runs
// them (untimed).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_harness/testing.dart';

Future<void> main() async {
  final native = await outcomes([
    'flutter',
    'test',
    '--no-pub',
    'test/harness/fixture.dart',
  ]);
  final browser = await outcomes([
    ...['flutter', 'test', '--no-pub', '--platform', 'chrome'],
    'test/harness/web_fixture.dart',
  ]);

  test('a test fails on what it used to swallow', () {
    expect(native, {
      'clean': ['passed'],
      'FlutterError': [contains('FlutterError: Bad state: a framework error')],
      'FlutterError in a widget test': [contains('Test failed.')],
      'error-level log record': [contains('Error-level log record: {"time"')],
      'error-level log record in a widget test': [
        contains('an error the app logs in a widget test'),
      ],
      'unhandled async error': [contains('an error nobody awaits')],
      'taken': ['passed'],
    });
  });

  test('a browser test fails on what it used to swallow', () {
    expect(browser, {
      'clean': ['passed'],
      'FlutterError': [contains('FlutterError: Bad state: a framework error')],
      'error-level log record': [contains('Error-level log record: {"time"')],
      'console.error': [contains('console.error: an error the page logs')],
      'uncaught error': [contains('Uncaught error in the page')],
      'taken': ['passed'],
    });
  });

  test('the Flutter packages install the harness as the app does', () {
    final config = File('test/flutter_test_config.dart').readAsStringSync();
    for (final package in ['photolib_editor', 'photolib_video']) {
      expect(
        File('packages/$package/test/flutter_test_config.dart')
            .readAsStringSync(),
        config,
        reason: package,
      );
    }
    // Suites in real time with real connections, on a live binding.
    expect(
      File('test/live/flutter_test_config.dart').readAsStringSync(),
      config.replaceFirst('Automated', 'Live'),
      reason: 'test/live',
    );
  });
}
