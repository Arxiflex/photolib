// Run by harness_test.dart with flutter test, under the
// flutter_test_config.dart next to it: 'hung' must time out.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('stopped past its timeout', () async {
    // As the merge train stops other runs (SIGSTOP) while it measures time.
    await Process.start('sh', [
      '-c',
      'sleep 0.5; kill -STOP $pid; sleep 4; kill -CONT $pid',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(seconds: 5));
  }, timeout: const Timeout(Duration(seconds: 3)));

  test(
    'hung',
    () => Completer<void>().future,
    timeout: const Timeout(Duration(seconds: 1)),
  );
}
