import 'package:crypto/crypto.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_workers/photolib_workers.dart';
import 'package:photolib_workers/testing.dart';
import 'package:test/test.dart';

import 'platform_vm.dart' if (dart.library.js_interop) 'platform_web.dart';
import 'tasks.dart';

/// The pool's behaviour, the same in the VM (pool_test.dart) and in browsers (web_test.dart).
void poolTests(WorkerPool Function({int? size}) newPool) {
  late WorkerPool pool;
  setUp(() => pool = newPool());
  tearDown(() => pool.close());

  WorkerPool single() {
    final pool = newPool(size: 1);
    addTearDown(pool.close);
    return pool;
  }

  test('returns the result, ints as ints and doubles as doubles', () async {
    expect(await pool.run(echo, 'hello').result, 'hello');
    expect(await pool.run(wait, 2).result, isA<int>());
    expect(await pool.run(half, 4).result, isA<double>());
  });

  test('streams the progress the task reports, then the result', () async {
    final job = pool.run(count, 4);
    expect(await job.progress.toList(), [0.25, 0.5, 0.75, 1]);
    expect(await job.result, 4);
  });

  test('runs waiting jobs by priority, then in order', () async {
    final pool = single();
    final done = <String>[];
    void run(String name, Priority priority) =>
        pool.run(echo, name, priority: priority).result.then(done.add);
    final busy = pool.run(wait, 50).result;
    run('background', Priority.background);
    run('normal 1', Priority.normal);
    run('interactive', Priority.interactive);
    run('normal 2', Priority.normal);
    await busy;
    await pool.run(wait, 0, priority: Priority.background).result;
    expect(done, ['interactive', 'normal 1', 'normal 2', 'background']);
  });

  test(
    'a cancelled waiting job fails with JobCancelled and never runs',
    () async {
      final pool = single();
      pool.run(wait, 10);
      final job = pool.run(wait, 3600000)..cancel();
      await expectLater(job.result, throwsA(isA<JobCancelled>()));
      expect(await pool.run(echo, 'next').result, 'next');
    },
  );

  test('a cancelled running job stops at its next progress report', () async {
    final pool = single();
    final job = pool.run(spin, null);
    await job.progress.first;
    job.cancel();
    await expectLater(job.result, throwsA(isA<JobCancelled>()));
    expect(await pool.run(echo, 'next').result, 'next');
  });

  test('a task that throws fails its job with the error', () async {
    await expectLater(
      pool.run(raise, 'boom').result,
      throwsA(
        isA<JobFailed>().having((e) => e.error, 'error', contains('boom')),
      ),
    );
    expect(await pool.run(echo, 'next').result, 'next');
  });

  test('a worker that dies fails its job and is replaced', () async {
    final pool = single();
    await expectLater(pool.run(crash, null).result, throwsA(isA<JobFailed>()));
    expect(await pool.run(echo, 'next').result, 'next');
    expect(takeProblems(), [contains('worker error')]);
  });

  test('logs workers starting and dying, and each job sent and done', () async {
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    final pool = single();
    expect(await pool.run(echo, 'a').result, 'a');
    await expectLater(pool.run(crash, null).result, throwsA(isA<JobFailed>()));
    final logged = [
      for (final r in heard)
        if (r.logger == 'photolib.workers') r,
    ];
    expect(
      logged.map((r) => r.message),
      containsAllInOrder([
        'worker started',
        'job sent',
        'job done',
        'job sent',
        'worker died',
      ]),
    );
    expect(logged[1].fields, containsPair('task', 'echo'));
    expect(logged.last.error, isNotNull);
    expect(takeProblems(), [contains('worker error')]);
  });

  test('closing cancels every job and refuses new ones', () async {
    final pool = single();
    final running = pool.run(spin, null);
    final waiting = pool.run(echo, 'never');
    await running.progress.first;
    pool.close();
    for (final job in [running, waiting]) {
      await expectLater(job.result, throwsA(isA<JobCancelled>()));
    }
    expect(() => pool.run(echo, 'late'), throwsStateError);
  });

  test(
    'hashing a 2 GiB file adds at most 1% to the 60 Hz frames an idle isolate misses',
    () async {
      final file = await zeroFile(2 << 30);
      late Future<List<double>> progress;
      final hash = await withinFrameBudget(() {
        final job = pool.run(sha256File, file);
        progress = job.progress.toList();
        return job.result;
      });
      expect(
        hash,
        'a7c744c13cc101ed66c29f672f92455547889cc586ce6d44fe76ae824958ea51',
      );
      expect(await progress, hasLength(256));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('hashing on this isolate instead is over the budget', () async {
    final file = await zeroFile(16 << 20);
    await expectLater(
      withinFrameBudget(
        () => sha256.bind(chunks(file, 8 << 20)).single,
        idle: const Duration(seconds: 1),
      ),
      throwsA(isA<FrameBudgetExceeded>()),
    );
  });
}
