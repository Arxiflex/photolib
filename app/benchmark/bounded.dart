// A benchmark test's body bounded in time. A test runner's timeout fails the
// test, as an uncaught error ends it, but leaves its body running into the
// next test, which its later steps then disturb and its errors fail.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs [body] and fails with its error, its first uncaught error or, past
/// [limit], a [TimeoutException], once the body has stopped: from the failure
/// on, a timer it starts throws, so that it unwinds through its `finally`
/// blocks, which release what it holds, and its errors are dropped. A body
/// that has not stopped [grace] after the failure is left behind, a test API
/// call it left in flight closed. Nothing else of its zone changes: what it
/// set up, such as stdout's sink, keeps working.
Future<void> bounded(
  Duration limit,
  Future<void> Function() body, {
  Duration grace = const Duration(minutes: 1),
}) async {
  (Object, StackTrace)? failure;
  var running = true;
  final settled = Completer<void>();
  final ended = Completer<void>();
  void fail(Object error, StackTrace stack) {
    failure ??= (error, stack);
    if (!settled.isCompleted) settled.complete();
  }

  void end([Object? error, StackTrace? stack]) {
    running = false;
    if (error != null) fail(error, stack!);
    if (!settled.isCompleted) settled.complete();
    ended.complete();
  }

  // A timer the body starts, unless it is being stopped.
  T start<T>(T Function() create) => failure != null && running
      ? throw StateError('Stopped: ${failure!.$1}')
      : create();
  final timer = Timer(
    limit,
    () => fail(TimeoutException('Not done', limit), StackTrace.current),
  );
  try {
    await TestAsyncUtils.guard(() async {
      unawaited(
        Zone.current
            .fork(
              specification: ZoneSpecification(
                createTimer: (_, parent, zone, duration, f) =>
                    start(() => parent.createTimer(zone, duration, f)),
                createPeriodicTimer: (_, parent, zone, period, f) =>
                    start(() => parent.createPeriodicTimer(zone, period, f)),
                handleUncaughtError: (_, parent, zone, error, stack) {
                  if (running) {
                    if (failure == null) fail(error, stack);
                  } else {
                    parent.handleUncaughtError(zone, error, stack);
                  }
                },
              ),
            )
            // Listened to in its zone, which its errors do not leave.
            .run(() => body().then((_) => end(), onError: end)),
      );
      await settled.future;
      if (running) await ended.future.timeout(grace, onTimeout: () {});
    });
  } catch (_) {
    // With a failure, also the guard's report of a call left in flight.
    if (failure == null) rethrow;
  } finally {
    timer.cancel();
  }
  if (failure case (final error, final stack)) {
    Error.throwWithStackTrace(error, stack);
  }
}
