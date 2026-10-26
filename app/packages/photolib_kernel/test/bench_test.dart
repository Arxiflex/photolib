// bench.dart's sampling on work of a known length, a spin on the clock: a thread held up by other work on the machine
// must not slow the measure, and slower work must.
import 'package:test/test.dart';

import 'bench.dart';

final clock = Stopwatch()..start();

void spin(int us) {
  for (
    final end = clock.elapsedMicroseconds + us;
    clock.elapsedMicroseconds < end;
  ) {}
}

void main() {
  test('a descheduled sample does not slow the measure', () {
    // Ten microseconds of work, held up for half of every 20 ms as a thread is on a loaded machine.
    final measured = seconds(until: (_) => true, () {
      spin(10);
      final phase = clock.elapsedMicroseconds % 20000;
      if (phase >= 10000) spin(20000 - phase);
    });
    expect(measured * 1e6, closeTo(10, 1));
  });

  test('work that takes twice as long measures twice as long', () {
    expect(seconds(() => spin(20), until: (_) => true) * 1e6, closeTo(20, 2));
  });
}
