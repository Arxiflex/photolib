/// Builds the kernel from this checkout, for the tests of the packages in app/packages, and measures on the fastest
/// cores: benchmarks measure the code, not the machine, so other processes on a shared machine must not count
/// (docs/dev/kernel-go-no-go.md).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

/// Builds kernel/ffi in release mode, as apps get it, with cargo and returns the shared library that cargo reports.
/// Call it in a suite's `main`, where no timeout runs: on a loaded machine
/// cargo may build for minutes.
String buildKernel() {
  // package:test runs each test, setUpAll and tearDownAll in a zone that
  // holds its invoker under this key.
  if (Zone.current[#test.invoker] != null) {
    throw StateError(
      'buildKernel() runs in a test, whose timeout cargo may outlast: '
      'call it in main',
    );
  }
  final build = Process.runSync(
    'cargo',
    [
      'build',
      '--locked',
      '--release',
      '-p',
      'photolib-kernel-ffi',
      '--message-format=json',
    ],
    workingDirectory: Directory.current.uri
        .resolve('../../../kernel/')
        .toFilePath(),
  );
  if (build.exitCode != 0) {
    throw StateError('cargo build failed:\n${build.stderr}');
  }
  for (final line in LineSplitter.split(build.stdout as String)) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['reason'] == 'compiler-artifact' &&
        message['target']['name'] == 'photolib_kernel_ffi') {
      return (message['filenames'] as List).cast<String>().firstWhere(
        (file) => ['.so', '.dylib', '.dll'].any(file.endsWith),
      );
    }
  }
  throw StateError('cargo reported no photolib_kernel_ffi library');
}

/// Microseconds of the calling thread's CPU time on Linux (`CLOCK_THREAD_CPUTIME_ID`), else null.
int Function()? threadClock() {
  if (!Platform.isLinux) return null;
  final now = calloc<_Timespec>();
  final read = DynamicLibrary.process()
      .lookupFunction<
        Int Function(Int, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)
      >('clock_gettime', isLeaf: true);
  return () {
    if (read(3, now) != 0) throw StateError('clock_gettime failed');
    return now.ref.seconds * 1000000 + now.ref.nanoseconds ~/ 1000;
  };
}

final class _Timespec extends Struct {
  @Long()
  external int seconds;
  @Long()
  external int nanoseconds;
}

/// On Linux, pins process [root] and every process it started, all their threads, to the fastest cores it may use.
void pinToFastestCores(int root) {
  if (!Platform.isLinux) return;
  final allowed = [
    for (final range in RegExp(
      r'Cpus_allowed_list:\s*(\S+)',
    ).firstMatch(File('/proc/$root/status').readAsStringSync())![1]!.split(','))
      for (
        var cpu = int.parse(range.split('-').first);
        cpu <= int.parse(range.split('-').last);
        cpu++
      )
        cpu,
  ];
  final speed = {for (final cpu in allowed) cpu: _topSpeed(cpu)};
  final top = speed.values.reduce(max);
  final fastest = [
    for (final cpu in allowed)
      if (speed[cpu] == top) cpu,
  ];
  if (fastest.length == allowed.length) return;
  for (final process in _family(root)) {
    final pin = Process.runSync('taskset', [
      '-a',
      '-p',
      '-c',
      fastest.join(','),
      '$process',
    ]);
    if (pin.exitCode != 0 && File('/proc/$process/stat').existsSync()) {
      throw StateError('taskset failed: ${pin.stderr}');
    }
  }
}

int _topSpeed(int cpu) {
  final file = File('/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq');
  return file.existsSync() ? int.parse(file.readAsStringSync().trim()) : 0;
}

/// [root] and its descendants.
List<int> _family(int root) {
  final parents = <int, int>{};
  for (final entry in Directory('/proc').listSync()) {
    final process = int.tryParse(entry.path.split('/').last);
    if (process == null) continue;
    try {
      final stat = File('/proc/$process/stat').readAsStringSync();
      parents[process] = int.parse(
        stat.substring(stat.lastIndexOf(')') + 2).split(' ')[1],
      );
    } on FileSystemException {
      // It ended.
    }
  }
  final family = [root];
  for (var i = 0; i < family.length; i++) {
    family.addAll([
      for (final MapEntry(:key, :value) in parents.entries)
        if (value == family[i]) key,
    ]);
  }
  return family;
}
