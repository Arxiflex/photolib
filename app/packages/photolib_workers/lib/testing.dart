/// Frame budgets: the share of 60 Hz frames that work may cost the isolate waiting for it, beyond what the machine's
/// load costs an idle isolate anyway (design 19, ADR-0098). For tests only.
library;

import 'dart:async';
import 'dart:math';

import 'src/testing/frames_native.dart'
    if (dart.library.js_interop) 'src/testing/frames_web.dart';

export 'src/testing/frames_native.dart'
    if (dart.library.js_interop) 'src/testing/frames_web.dart'
    show countIdleFrames;

/// [missed] of the [total] 60 Hz frames of a span, and the [longest] gap between two frames.
final class Frames {
  const Frames(this.missed, this.total, [this.longest = Duration.zero]);

  final int missed, total;
  final Duration longest;

  double get share => total == 0 ? 0 : missed / total;

  @override
  String toString() =>
      '$missed of $total (${_percent(share)}'
      '${longest > Duration.zero ? ', the longest gap ${longest.inMilliseconds} ms' : ''})';
}

final class FrameBudgetExceeded implements Exception {
  const FrameBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => 'FrameBudgetExceeded: $message';
}

/// Counts the frames this isolate misses while it idles for [idle], then while [work] runs, and prints the
/// [judgeFrames] of each count: from a 1 ms timer, also on an idle isolate (a Web Worker on the web) meanwhile, and in
/// Chrome from animation frames too, or from them alone with [animationOnly]. Over the [budget], it runs the work
/// again, up to [attempts] times in all: a busy machine stalls an idle isolate in bursts, which one idle span cannot
/// foresee.
Future<T> withinFrameBudget<T>(
  Future<T> Function() work, {
  double budget = 0.01,
  Duration idle = const Duration(seconds: 5),
  int attempts = 3,
  bool animationOnly = false,
}) async {
  final meters = {
    if (!animationOnly) 'frames': countTimerFrames,
    'animation frames': ?countAnimationFrames,
  };
  if (meters.isEmpty) throw UnsupportedError('No animation frames here');
  Future<List<Frames>> count(Future<void> Function() span) async {
    final stops = [for (final start in meters.values) start()];
    late final List<Frames> counts;
    await span().whenComplete(
      () => counts = [for (final stop in stops) stop()],
    );
    return counts;
  }

  for (var attempt = 1; ; attempt++) {
    final before = await count(() => Future.delayed(idle));
    final machine = describeMachine();
    final stopIdle = animationOnly ? null : await countIdleFrames();
    Frames? meanwhile;
    late final T result;
    final during = await count(
      () async => result = await work(),
    ).whenComplete(() async => meanwhile = await stopIdle?.call());
    try {
      for (final (i, kind) in meters.keys.indexed) {
        print(
          judgeFrames(
            kind,
            before[i],
            during[i],
            meanwhile: kind == 'frames' ? meanwhile : null,
            budget: budget,
            machine: machine,
          ),
        );
      }
      return result;
    } on FrameBudgetExceeded catch (e) {
      if (attempt == attempts) rethrow;
      print('$e; trying again');
    }
  }
}

/// What [work] adds to the share of [kind] that an idle isolate missed: this one in the [idle] span just before, or
/// another [meanwhile] if more, as a line to print. Throws [FrameBudgetExceeded] when that is more than [budget], by
/// default 1% as for janky frames in design 19 §3. An idle isolate missing more than the budget raises it that far,
/// and the line says so and how busy the [machine] was: there the work's share cannot be told from the machine's.
String judgeFrames(
  String kind,
  Frames idle,
  Frames work, {
  Frames? meanwhile,
  double budget = 0.01,
  required String machine,
}) {
  final floor = max(idle.share, meanwhile?.share ?? 0);
  final added = work.share - floor, allowed = max(budget, floor);
  final busy = floor > budget
      ? ', raised to ${_percent(floor)}, what an idle isolate missed on this busy machine ($machine)'
      : '';
  final verdict =
      '$kind missed: $work working, $idle idle just before'
      '${meanwhile == null ? '' : ', $meanwhile on an idle isolate meanwhile'}'
      '; the work adds ${_percent(added)}, '
      '${added > allowed ? 'over' : 'within'} the budget of ${_percent(budget)}$busy';
  if (added > allowed) throw FrameBudgetExceeded(verdict);
  return verdict;
}

String _percent(double share) => '${(share * 100).toStringAsFixed(1)}%';

/// Starts counting the 60 Hz frames this isolate could not have started on time: one for every full frame interval
/// in which its event loop ran no timer. The returned function stops and returns the count.
Frames Function() countTimerFrames() {
  const frame = 16667;
  final clock = Stopwatch()..start();
  var last = 0, missed = 0, longest = 0;
  void tick() {
    final now = clock.elapsedMicroseconds;
    missed += (now - last) ~/ frame;
    longest = max(longest, now - last);
    last = now;
  }

  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) => tick());
  return () {
    timer.cancel();
    tick();
    return Frames(missed, last ~/ frame, Duration(microseconds: longest));
  };
}
