import 'package:photolib_workers/testing.dart';
import 'package:test/test.dart';

void main() {
  String judge(
    Frames idle,
    Frames work, {
    Frames? meanwhile,
    double budget = 0.01,
  }) => judgeFrames(
    'frames',
    idle,
    work,
    meanwhile: meanwhile,
    budget: budget,
    machine: 'load average 45.1 on 16 cores',
  );
  final over = throwsA(isA<FrameBudgetExceeded>());

  test('the work may add up to the budget to what an idle span misses', () {
    const gap = Duration(milliseconds: 120);
    expect(
      judge(const Frames(3, 600), const Frames(15, 1000, gap)),
      'frames missed: 15 of 1000 (1.5%, the longest gap 120 ms) working, 3 of '
      '600 (0.5%) idle just before; the work adds 1.0%, within the budget of '
      '1.0%',
    );
    expect(() => judge(const Frames(3, 600), const Frames(16, 1000)), over);
    expect(
      judge(const Frames(3, 600), const Frames(155, 1000), budget: 0.15),
      endsWith('the work adds 15.0%, within the budget of 15.0%'),
    );
    expect(
      judge(const Frames(0, 0), const Frames(0, 0)),
      contains('adds 0.0%'),
    );
  });

  test('or to what an idle isolate misses meanwhile, if that is more', () {
    expect(
      judge(
        const Frames(3, 600),
        const Frames(18, 1000),
        meanwhile: const Frames(8, 1000),
      ),
      'frames missed: 18 of 1000 (1.8%) working, 3 of 600 (0.5%) idle just '
      'before, 8 of 1000 (0.8%) on an idle isolate meanwhile; the work adds '
      '1.0%, within the budget of 1.0%',
    );
    expect(
      () => judge(
        const Frames(3, 600),
        const Frames(19, 1000),
        meanwhile: const Frames(8, 1000),
      ),
      over,
    );
    expect(
      judge(
        const Frames(6, 600),
        const Frames(20, 1000),
        meanwhile: const Frames(2, 1000),
      ),
      contains('the work adds 1.0%'),
    );
  });

  test('a machine too busy for the budget is named, not blamed on the work', () {
    final busy = endsWith(
      'within the budget of 1.0%, raised to 4.7%, what an idle isolate missed '
      'on this busy machine (load average 45.1 on 16 cores)',
    );
    expect(judge(const Frames(28, 600), const Frames(93, 1000)), busy);
    expect(
      judge(
        const Frames(3, 600),
        const Frames(93, 1000),
        meanwhile: const Frames(47, 1000),
      ),
      busy,
    );
    expect(() => judge(const Frames(28, 600), const Frames(94, 1000)), over);
  });

  test('work that blocks the isolate is over the budget on a busy machine', () {
    expect(
      () => judge(const Frames(28, 600), const Frames(700, 1000)),
      throwsA(
        isA<FrameBudgetExceeded>().having(
          (e) => '$e',
          'message',
          contains(
            'the work adds 65.3%, over the budget of 1.0%, raised to 4.7%, '
            'what an idle isolate missed on this busy machine',
          ),
        ),
      ),
    );
  });

  test(
    'an idle isolate misses none of the frames that block this one',
    () async {
      final idle = await countIdleFrames();
      final here = countTimerFrames();
      final clock = Stopwatch()..start();
      while (clock.elapsedMilliseconds < 300) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final blocked = here(), meanwhile = await idle();
      expect(blocked.missed, greaterThanOrEqualTo(17));
      expect(meanwhile.total, greaterThanOrEqualTo(blocked.total));
      expect(meanwhile.missed, lessThan(blocked.missed ~/ 2));
    },
  );

  test('work gets three tries, each after an idle span of its own', () async {
    var calls = 0;
    Future<int> blocking(int times, {int attempts = 3}) => withinFrameBudget(
      () async {
        final clock = Stopwatch()..start();
        while (calls < times && clock.elapsedMilliseconds < 200) {}
        return ++calls;
      },
      idle: const Duration(milliseconds: 100),
      attempts: attempts,
    );

    expect(await blocking(2), 3);
    calls = 0;
    await expectLater(blocking(3), over);
    expect(calls, 3);
    calls = 0;
    await expectLater(blocking(1, attempts: 1), over);
    expect(calls, 1);
  });

  test('the VM has no animation frames to judge', () {
    expect(
      withinFrameBudget(() async {}, animationOnly: true),
      throwsUnsupportedError,
    );
  });
}
