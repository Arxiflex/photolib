import 'dart:math';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/jank.dart';

void main() {
  // Measures each attempt's shares in turn against a 1 % budget: expects the
  // attempt that counts, its shares and the attempts made, and the attempts
  // each rest came after.
  Future<void> expectRun(
    List<Jank> shares,
    (int, Jank, int) counted,
    List<int> restsAfter,
  ) async {
    final rests = <int>[];
    var made = 0;
    final got = await leastJanky(
      (attempt) async {
        expect(attempt, made++);
        return (attempt, shares[attempt]);
      },
      budget: 1,
      rest: (_) async => rests.add(made),
    );
    expect(got, counted);
    expect(rests, restsAfter);
  }

  test('a sample within its budget is measured once, with no rest', () async {
    await expectRun([(janky: 0.9, idle: 0)], (0, (janky: 0.9, idle: 0), 1), []);
  });

  test('less what an idle isolate missed, exactly at the budget, it passes '
      'as perf.py checks it', () async {
    const jank = (janky: 1.18, idle: 0.18);
    await expectRun([jank], (0, jank, 1), []);
  });

  test('over its budget, it is measured again after a rest until an attempt '
      'is within it', () async {
    await expectRun(
      [
        (janky: 1.5, idle: 0.2),
        (janky: 1.2, idle: 0.1),
        (janky: 0.95, idle: 0),
        (janky: 0, idle: 0),
      ],
      (2, (janky: 0.95, idle: 0), 3),
      [1, 2],
    );
  });

  test('the budget never rises to what an idle isolate missed', () async {
    const busy = (janky: 6.0, idle: 3.5);
    await expectRun(List.filled(5, busy), (0, busy, 5), [1, 2, 3, 4]);
  });

  test('five attempts at most: the least janky less the idle share counts, '
      'the first of equals', () async {
    await expectRun(
      [
        (janky: 3, idle: 0),
        (janky: 4, idle: 2.5),
        (janky: 2.2, idle: 0),
        (janky: 1.6, idle: 0.05),
        (janky: 1.6, idle: 0.1),
        (janky: 0, idle: 0),
      ],
      (1, (janky: 4, idle: 2.5), 5),
      [1, 2, 3, 4],
    );
  });

  test('each rest is told the shares of the attempt just measured', () async {
    const shares = [
      (janky: 2.0, idle: 0.0),
      (janky: 3.0, idle: 0.5),
      (janky: 0.5, idle: 0.0),
    ];
    final told = <Jank>[];
    await leastJanky(
      (attempt) async => (attempt, shares[attempt]),
      budget: 1,
      rest: (last) async => told.add(last),
    );
    expect(told, shares.take(2));
  });

  test('a share charged is never below 0 and in cents', () {
    expect(charged((janky: 0.3, idle: 0.8)), 0);
    expect(charged((janky: 1.18, idle: 0.18)), 1);
    expect(charged((janky: 1.004, idle: 0.001)), 1);
  });

  test('the share of late frames, in %', () {
    expect(lateShare([10.0, 20.0, 15.0, 30.0], (ms) => ms > 16.7), 50);
  });

  test('no frame drawn is no share: it fails saying so', () {
    expect(
      () => lateShare(<double>[], (ms) => ms > 16.7),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'no frame drawn'),
      ),
    );
  });

  // The fastest of up to three timings against a 100 ms budget: expects the
  // one that counts and the samples measured.
  Future<void> expectBest(List<double> ms, double counted, int measured) async {
    var made = 0;
    final got = await bestOf(
      3,
      (sample) async {
        expect(sample, made);
        return ms[made++];
      },
      min,
      (best) => best <= 100,
    );
    expect((got, made), (counted, measured));
  }

  test('a timing within its budget is measured once', () async {
    await expectBest([100, 20], 100, 1);
  });

  test(
    'over its budget, it is measured again until one is within it',
    () async {
      await expectBest([130, 90, 10], 90, 2);
    },
  );

  test('three timings at most, the best of them counting', () async {
    await expectBest([300, 200, 250, 10], 200, 3);
  });

  test('the frames drawn from a start to an end, by their vsync', () {
    FrameTiming at(int vsync) => FrameTiming(
      vsyncStart: vsync,
      buildStart: vsync + 1,
      buildFinish: vsync + 2,
      rasterStart: vsync + 3,
      rasterFinish: vsync + 4,
      rasterFinishWallTime: vsync + 4,
    );
    final frames = [
      for (final t in [99, 100, 150, 200, 201]) at(t),
    ];
    expect(framesWithin(frames, 100, 200), frames.sublist(1, 4));
  });
}
