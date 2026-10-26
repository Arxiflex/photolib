import 'dart:io';

import 'package:photolib_harness/photolib_harness.dart';
import 'package:test/test.dart';

void main() {
  test('thawed runs a body again only when the process was stopped during '
      'it, three runs at most', () async {
    // As the merge train stops other runs (SIGSTOP) while it measures time.
    Future<void> stop() => Process.run('sh', [
      '-c',
      'sleep 0.2; kill -STOP $pid; sleep 1.5; kill -CONT $pid',
    ]);
    var runs = 0;
    Future<int> run({required int stopped, bool throws = false}) async {
      if (++runs <= stopped) await stop();
      if (throws && runs <= stopped) throw StateError('timed out');
      return runs;
    }

    Future<int> thaw(int stopped, {bool throws = false, bool? again}) {
      runs = 0;
      return thawed(
        () => run(stopped: stopped, throws: throws),
        again: again == null ? null : (_) => again,
      );
    }

    expect(await thaw(1, again: true), 2);
    expect(await thaw(1, again: false), 1);
    expect(await thaw(1), 1);
    expect(await thaw(0, again: true), 1);
    expect(await thaw(5, again: true), 3);
    expect(await thaw(1, throws: true), 2);
    await expectLater(thaw(5, throws: true), throwsStateError);
    expect(runs, 3);
  });
}
