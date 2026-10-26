import 'dart:async';
import 'dart:math';

import 'package:photolib_log/photolib_log.dart';

import 'spawn_native.dart' if (dart.library.js_interop) 'spawn_web.dart';

const _log = Logger('photolib.workers');

/// A function a worker runs, known to the pool and to its workers by [name]. Its input and output cross to the worker,
/// on the web by `postMessage`: null, bools, numbers, strings, typed data, browser objects such as a `Blob`, and lists
/// and maps of them, which arrive untyped there.
final class Task<I, O> {
  const Task(this.name, this.run);

  final String name;
  final FutureOr<O> Function(I input, TaskContext context) run;

  FutureOr<O> _call(Object? input, TaskContext context) =>
      run(input as I, context);
}

/// What a running task sees of its job.
final class TaskContext {
  TaskContext._(this._send);

  final void Function(Object? message) _send;
  var _cancelled = false;

  /// Reports the share of the work done, from 0 to 1, and throws [JobCancelled] once the job was cancelled: a task
  /// stops at its next report.
  void progress(double done) {
    if (_cancelled) throw const JobCancelled();
    _send(['progress', done]);
  }
}

/// A task's run on the pool.
final class Job<O> {
  Job._(this._pool, this._task, this._input, this.priority);

  final WorkerPool _pool;
  final String _task;
  final Object? _input;
  final Priority priority;
  final _result = Completer<O>();
  final _progress = StreamController<double>.broadcast();
  final _took = Stopwatch();

  Future<O> get result => _result.future;

  /// Removes a waiting job from the queue, or asks a running one to stop; its [result] fails with [JobCancelled].
  void cancel() => _pool._cancel(this);

  /// The progress the task reports, until it ends.
  Stream<double> get progress => _progress.stream;

  void _end(Object? result, [Object? error]) {
    if (_result.isCompleted) return;
    // Whoever cancels a job need not wait for its result.
    if (error is JobCancelled) _result.future.ignore();
    _progress.close();
    // dart2wasm makes every number from JavaScript a double.
    error == null
        ? _result.complete(
            (result is double && result is! O ? result.toInt() : result) as O,
          )
        : _result.completeError(error);
  }
}

/// How soon a job runs: waiting jobs start by priority, then in the order they were submitted.
enum Priority { background, normal, interactive }

/// Why a job failed: the error the task threw, as text.
final class JobFailed implements Exception {
  const JobFailed(this.error);

  final String error;

  @override
  String toString() => 'JobFailed: $error';
}

/// The error of a cancelled job.
final class JobCancelled implements Exception {
  const JobCancelled();
}

/// Runs tasks on worker isolates natively and on Web Workers on the web, never on the calling isolate. The workers
/// know [tasks]; on the web they are the ones compiled into [script], a Web Worker that calls `serveWorker`.
final class WorkerPool {
  WorkerPool(this._tasks, {Uri? script, int? size})
    : _script = script,
      size = size ?? defaultSize();

  final List<Task> _tasks;
  final Uri? _script;

  /// The most workers this pool starts, each when a job finds no idle one.
  final int size;
  final _queue = <Job>[];
  final _workers = <_Worker>[];
  var _closed = false;

  Job<O> run<I, O>(
    Task<I, O> task,
    I input, {
    Priority priority = Priority.normal,
  }) {
    if (_closed) throw StateError('The pool is closed.');
    final job = Job<O>._(this, task.name, input, priority);
    _queue.add(job);
    _dispatch();
    return job;
  }

  void _dispatch() {
    while (_queue.isNotEmpty) {
      var worker = _workers.where((w) => w.job == null).firstOrNull;
      if (worker == null) {
        if (_workers.length == size) return;
        late final _Worker spawned;
        spawned = worker = _Worker(
          spawn(_tasks, _script, (message) => _receive(spawned, message)).then(
            (channel) => channel,
            onError: (Object error) => _died(spawned, '$error'),
          ),
        );
        _workers.add(worker);
        _log.debug(
          'worker started',
          fields: {'workers': _workers.length, 'of': size},
        );
      }
      final job = worker.job = _queue.reduce(
        (a, b) => b.priority.index > a.priority.index ? b : a,
      );
      _queue.remove(job);
      job._took.start();
      _log.debug(
        'job sent',
        fields: {
          'task': job._task,
          'priority': job.priority.name,
          'waiting': _queue.length,
        },
      );
      worker.send([job._task, job._input]);
    }
  }

  void _receive(_Worker worker, Object? message) {
    if (message == null) return _died(worker, 'The worker exited.');
    final job = worker.job!;
    if (message case ['progress', final num done]) {
      if (!job._result.isCompleted) job._progress.add(done.toDouble());
      return;
    }
    worker.job = null;
    final fields = {'task': job._task, 'ms': job._took.elapsedMilliseconds};
    switch (message) {
      case ['done', final result]:
        _log.debug('job done', fields: fields);
        job._end(result);
      case ['failed', final String error]:
        _log.warning('job failed', fields: fields, error: error);
        job._end(null, JobFailed(error));
    }
    _dispatch();
  }

  void _cancel(Job job) {
    if (job._result.isCompleted) return;
    if (!_queue.remove(job)) {
      _workers.firstWhere((w) => w.job == job).send(null);
    }
    job._end(null, const JobCancelled());
  }

  Null _died(_Worker worker, String error) {
    _log.warning(
      'worker died',
      fields: {'task': ?worker.job?._task},
      error: error,
    );
    _workers.remove(worker);
    worker.close();
    worker.job?._end(null, JobFailed(error));
    _dispatch();
  }

  /// Cancels every job and stops the workers.
  void close() {
    _closed = true;
    for (final job in [..._queue, for (final w in _workers) ?w.job]) {
      job._end(null, const JobCancelled());
    }
    for (final worker in _workers) {
      worker.close();
    }
    _queue.clear();
    _workers.clear();
  }
}

/// Cores − 1, and at most 4 on phones (docs/10-client-app.md §1.5).
int poolSize(int cores, {bool phone = false}) =>
    max(1, min(cores - 1, phone ? 4 : cores));

typedef Channel = ({
  void Function(Object? message) send,
  void Function() close,
});

final class _Worker {
  _Worker(this._channel);

  final Future<Channel?> _channel;
  Job? job;

  void send(Object? message) => _channel.then((c) => c?.send(message));
  void close() => _channel.then((c) => c?.close());
}

/// A worker's end of the pool: runs the jobs it is sent, one at a time, and replies through [send].
final class Server {
  Server(List<Task> tasks, this._send)
    : _tasks = {for (final task in tasks) task.name: task};

  final Map<String, Task> _tasks;
  final void Function(Object? message) _send;

  TaskContext? _running;

  /// Runs a job, sent as `[task name, input]`, or cancels the running one, sent as null.
  Future<void> receive(Object? message) async {
    if (message == null) {
      _running?._cancelled = true;
      return;
    }
    final [String name, input] = message as List;
    final context = _running = TaskContext._(_send);
    try {
      _send(['done', await _tasks[name]!._call(input, context)]);
    } catch (error) {
      _send(['failed', '$error']);
    } finally {
      _running = null;
    }
  }
}
