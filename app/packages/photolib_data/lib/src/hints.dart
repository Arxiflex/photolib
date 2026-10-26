import 'dart:async';

import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_log/photolib_log.dart';

const _log = Logger('photolib.sync');

/// Follows the hints that [hints] opens a channel for (`Server.hints`, design
/// 05 §9, ADR-0225) until [stop] completes. Each hint runs [sync], the first
/// of every channel included, as the streams may have advanced while it was
/// closed: one run at a time, the hints that arrive meanwhile folded into one
/// more. A run after which [streams] gives others opens the channel again with
/// them; a lost or refused channel opens again after [backoff], doubled up to
/// [maxBackoff] and reset by a hint. A failed run waits for the next hint; a
/// revoked session ends following with its error.
Future<void> followHints(
  Stream<List<String>> Function(Iterable<String> streams) hints, {
  required Future<Set<String>> Function() streams,
  required Future<void> Function() sync,
  required Future<void> stop,
  Duration backoff = const Duration(seconds: 1),
  Duration maxBackoff = const Duration(minutes: 1),
  Future<void> Function(Duration delay) wait = Future<void>.delayed,
}) async {
  var (stopped, delay) = (false, backoff);
  unawaited(stop.whenComplete(() => stopped = true));
  while (!stopped) {
    final followed = await streams();
    // Completes with whether the channel opens again at once.
    final ended = Completer<bool>();
    void end(Object result) {
      if (ended.isCompleted) return;
      result is bool ? ended.complete(result) : ended.completeError(result);
    }

    var (pending, running, draining) = (false, false, Future<void>.value());
    Future<void> drain() async {
      running = true;
      while (pending && !ended.isCompleted) {
        pending = false;
        try {
          await sync();
          final now = await streams();
          if (now.length != followed.length || !now.containsAll(followed)) {
            end(true);
          }
        } on Exception catch (error) {
          error is CallError && error.logsOut
              ? end(error)
              : _log.warning('sync failed', error: error);
        }
      }
      running = false;
    }

    final channel = hints(followed).listen(
      (_) {
        delay = backoff;
        pending = true;
        if (!running) draining = drain();
      },
      onError: end,
      onDone: () => end(false),
    );
    unawaited(stop.whenComplete(() => end(false)));
    var again = false;
    try {
      again = await ended.future;
    } on CallError catch (error) {
      if (error.logsOut) rethrow;
      _log.log(
        LogLevel.info,
        'hints lost',
        fields: {'retry_ms': delay.inMilliseconds},
        error: error,
      );
    } finally {
      await channel.cancel();
      await draining;
    }
    if (again || stopped) continue;
    await Future.any([wait(delay), stop]);
    delay = delay * 2 > maxBackoff ? maxBackoff : delay * 2;
  }
}
