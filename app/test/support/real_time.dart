import 'package:flutter_test/flutter_test.dart';

/// Waits in real time until [done], as `tester.pumpUntil` (`pump_app.dart`)
/// does between frames; in a widget test, inside `runAsync`. Fails once its
/// own waits add up to [within], which a stopped process (SIGSTOP) does not
/// run out.
Future<void> realUntil(
  bool Function() done, {
  Duration within = const Duration(minutes: 2),
}) async {
  const step = Duration(milliseconds: 10);
  for (var waited = Duration.zero; !done(); waited += step) {
    if (waited > within) fail('not done after $within');
    await Future<void>.delayed(step);
  }
}
