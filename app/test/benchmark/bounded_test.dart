import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../benchmark/bounded.dart';

void main() {
  const limit = Duration(milliseconds: 50);
  // What [body] bounded by [limit] fails with, awaited before any expect, as
  // it holds the test API's guard meanwhile.
  Future<Object?> failure(Future<void> Function() body) => bounded(
    limit,
    body,
    grace: limit,
  ).then((_) => null, onError: (Object e) => e);
  var steps = 0;
  setUp(() => steps = 0);
  Future<void> stepping() async {
    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      steps++;
    }
  }

  Future<void> expectNoMoreSteps() async {
    final at = steps;
    await Future<void>.delayed(limit * 3);
    expect(steps, at);
  }

  test('a body within its limit ends as it would, with its error', () async {
    var ran = false;
    expect(await failure(() async => ran = true), isNull);
    expect(ran, isTrue);
    expect(await failure(() async => throw StateError('body')), isStateError);
  });

  test('what its stopped body set up keeps working, as stdout first written '
      'to there would', () async {
    final events = StreamController<int>();
    final got = <int>[];
    final failed = await failure(() {
      events.stream.listen((e) => Timer.run(() => got.add(e)));
      return stepping();
    });
    expect(failed, isA<TimeoutException>());
    events.add(1);
    await Future<void>.delayed(limit);
    expect(got, [1]);
  });

  test('an uncaught error of its body fails it at once, and nothing of the '
      'body runs any more', () async {
    final failed = await failure(() {
      unawaited(Future<void>.error(StateError('uncaught')));
      return stepping();
    });
    expect(failed, isStateError);
    await expectNoMoreSteps();
  });

  test('past its limit it fails with a timeout, and nothing of its body runs '
      'any more', () async {
    expect(await failure(stepping), isA<TimeoutException>());
    await expectNoMoreSteps();
  });

  test(
    'an error its body would raise past its limit reaches no test',
    () async {
      final failed = await failure(() async {
        Timer(limit * 2, () => throw StateError('past the limit'));
        await Completer<void>().future;
      });
      expect(failed, isA<TimeoutException>());
      await Future<void>.delayed(limit * 3);
    },
  );

  test(
    'a test API call in flight at its limit leaves the next one free',
    () async {
      final failed = await failure(
        () => TestAsyncUtils.guard(() => Completer<void>().future),
      );
      expect(failed, isA<TimeoutException>());
      await TestAsyncUtils.guard(() async {});
    },
  );
}
