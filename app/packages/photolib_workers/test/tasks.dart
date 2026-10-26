import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:photolib_workers/photolib_workers.dart';

import 'platform_vm.dart' if (dart.library.js_interop) 'platform_web.dart';

/// The tasks the test workers know, natively and in test/worker.dart.
const tasks = <Task>[echo, half, count, wait, spin, raise, crash, sha256File];

const echo = Task<String, String>('echo', _echo);
String _echo(String input, TaskContext context) => input;

const half = Task<int, double>('half', _half);
double _half(int n, TaskContext context) => n / 2;

/// Waits for its input in milliseconds, then returns it.
const wait = Task<int, int>('wait', _wait);
Future<int> _wait(int ms, TaskContext context) =>
    Future.delayed(Duration(milliseconds: ms), () => ms);

/// Throws its input.
const raise = Task<String, Never>('raise', _raise);
Never _raise(String error, TaskContext context) => throw StateError(error);

/// Kills its worker with an error that no job catches.
const crash = Task<Object?, Never>('crash', _crash);
Future<Never> _crash(Object? _, TaskContext context) {
  Future(() => throw StateError('crash'));
  return Completer<Never>().future;
}

/// Reports no progress every millisecond until it is cancelled.
const spin = Task<Object?, Never>('spin', _spin);
Future<Never> _spin(Object? _, TaskContext context) async {
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    context.progress(0);
  }
}

/// Counts to its input, reporting each step as progress.
const count = Task<int, int>('count', _count);
int _count(int n, TaskContext context) {
  for (var i = 1; i <= n; i++) {
    context.progress(i / n);
  }
  return n;
}

/// The hex SHA-256 of a file (a path natively, a Blob on the web), read 8 MiB at a time, reporting progress.
const sha256File = Task<Object, String>('sha256File', _sha256File);
Future<String> _sha256File(Object file, TaskContext context) async {
  final size = await length(file);
  var done = 0;
  final read = chunks(file, 8 << 20).map((chunk) {
    context.progress((done += chunk.length) / size);
    return chunk;
  });
  return '${await sha256.bind(read).single}';
}
