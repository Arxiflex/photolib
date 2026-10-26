import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'pump_app.dart';

void main() {
  testWidgets('pumpUntil gives work that needs real time as long as it takes, '
      'and fails on what never comes', (tester) async {
    var done = false;
    // Longer than a count of short waits gave a loaded machine's disk.
    unawaited(
      Isolate.run(() => sleep(const Duration(seconds: 3)))
          .then((_) => done = true),
    );
    await tester.pumpUntil(() => done);
    expect(done, isTrue);
    await expectLater(
      tester.pumpUntil(() => false, within: const Duration(milliseconds: 100)),
      throwsA(isA<TestFailure>()),
    );
  });
}
