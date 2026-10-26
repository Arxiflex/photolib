import 'dart:async';

import 'package:test_api/hooks.dart' show TestHandle;

/// Starts the running test's timeout again whenever the process was stopped
/// (SIGSTOP) meanwhile, as the merge train stops other runs for up to 25
/// minutes while it measures time.
Timer sparingStops() {
  final test = TestHandle.current;
  // A pending piece of work that completes is what restarts a timeout.
  return _Stops(() => test.markPending().complete())._timer;
}

/// Runs [body] again, three runs at most, while the process was stopped
/// during it and it threw or [again] holds of what it returned, as tools/tests'
/// `thawed` does: for code that counts wall time, as a client's timeout does.
Future<T> thawed<T>(
  Future<T> Function() body, {
  bool Function(T result)? again,
}) async {
  for (var run = 1; ; run++) {
    var stopped = false;
    final stops = _Stops(() => stopped = true);
    final T result;
    try {
      result = await body();
    } on Object {
      stops._end();
      if (run < 3 && stopped) continue;
      rethrow;
    }
    stops._end();
    if (run < 3 && stopped && (again?.call(result) ?? false)) continue;
    return result;
  }
}

/// Calls [_stopped] after each stop: a clock looks every 100 ms, and a gap of
/// over a second between two looks is a stop.
class _Stops {
  new(this._stopped) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _look());
  }

  final void Function() _stopped;
  final _clock = Stopwatch()..start();
  Duration _last = Duration.zero;
  late final Timer _timer;

  void _look() {
    final now = _clock.elapsed;
    if (now - _last > const Duration(seconds: 1)) _stopped();
    _last = now;
  }

  /// Stops looking, after a last look for a stop since the last tick.
  void _end() {
    _timer.cancel();
    _look();
  }
}
