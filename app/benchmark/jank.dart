// The rules that measure the app's samples: a janky one over its budget
// again, up to five attempts in all, the least janky counting (ADR-0140); a
// timing over its budget again, the best counting; the frames drawn meanwhile.
import 'dart:math';
import 'dart:ui' show FramePhase, FrameTiming;

/// A janky share and the share of 60 Hz frames an idle isolate of the app
/// missed meanwhile, in %.
typedef Jank = ({double janky, double idle});

/// [value] rounded to cents, as results are recorded.
double cents(double value) => (value * 100).round() / 100;

/// The share [jank] is charged: janky less idle, never below 0, as
/// tools/perf/perf.py checks it.
double charged(Jank jank) =>
    cents(max(0, cents(jank.janky) - cents(jank.idle)));

/// Measures a sample, and while the least charged so far is over [budget],
/// measures it again after a [rest], told the attempt just measured, five
/// attempts at most. Returns the least charged sample, the first of equals,
/// its [Jank] and the attempts made.
Future<(T, Jank, int)> leastJanky<T>(
  Future<(T, Jank)> Function(int attempt) measure, {
  required double budget,
  required Future<void> Function(Jank last) rest,
}) async {
  var least = await measure(0);
  var last = least;
  var attempts = 1;
  while (attempts < 5 && charged(least.$2) > budget) {
    await rest(last.$2);
    last = await measure(attempts++);
    if (charged(last.$2) < charged(least.$2)) least = last;
  }
  return (least.$1, least.$2, attempts);
}

/// The share in % of [frames] that [late] says missed their budget; none
/// drawn is a failed sample, not a share.
double lateShare<T>(List<T> frames, bool Function(T frame) late) {
  if (frames.isEmpty) throw StateError('no frame drawn');
  return 100 * frames.where(late).length / frames.length;
}

/// The best by [best] of up to [most] samples, the next measured only while
/// the best so far is not [within] its budget: other load only makes a sample
/// worse (ADR-0212).
Future<T> bestOf<T>(
  int most,
  Future<T> Function(int sample) measure,
  T Function(T, T) best,
  bool Function(T best) within,
) async {
  var kept = await measure(0);
  for (var i = 1; i < most && !within(kept); i++) {
    kept = best(kept, await measure(i));
  }
  return kept;
}

/// The [frames] whose vsync started from [start] to [end], in µs of the
/// timeline's clock (`Timeline.now`).
List<FrameTiming> framesWithin(List<FrameTiming> frames, int start, int end) =>
    [
      for (final f in frames)
        if (f.timestampInMicroseconds(FramePhase.vsyncStart) case final t
            when t >= start && t <= end)
          f,
    ];
