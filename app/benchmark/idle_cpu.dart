// The idle CPU budget of tools/perf/budgets.json (M1-20), which
// tools/perf/run.sh runs with `flutter run --profile`: the whole app, under
// the binding it ships with (a test binding draws frames all the time), over
// the timeline fixtures of $PERF_FIXTURES that the budget names, each its
// device index, and a folder of 100k files, which the data isolate watches.
// The folder is scanned into each replica before its fixture loads and the
// app starts, as the budget is the CPU at rest. From 5 s after the app's
// visible cells show their thumbnails, the process's CPU time over 20 s, and
// that of a reconcile scan of the folder spread over the hour between two
// (FolderWatcher), as a share of one core, is printed as `result: <json>`; an
// error, as a result that names it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/app.dart';
import 'package:photolib/core/kernel.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;

import 'fixtures.dart';

const _fixtures = {'1m', 'near-duplicates-100k'};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scratch = Directory.systemTemp.createTempSync('photolib-idle');
  // An error the run cannot recover from, such as a fixture's replica that
  // cannot open or a fixture that hangs, ends it: an app left open stalls
  // tools/perf/run.sh, which learns of it from the result, as flutter run
  // exits 0 whatever the app does.
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    stderr.writeln('idle_cpu.dart: $error\n$stack');
    _report({'error': 'idle_cpu.dart failed: $error'});
    try {
      scratch.deleteSync(recursive: true);
    } finally {
      exit(1);
    }
  };
  final vault = Vault(
    location: '${scratch.path}/store',
    keystore: MemoryKeystore(),
    files: storeFiles('${scratch.path}/store'),
    keyring: await loadKernel(),
  );
  await vault.unlock();
  final originals = writeOriginals('${scratch.path}/originals');
  final folder = _folder('${scratch.path}/folder');
  for (final dir in Directory(
    Platform.environment['PERF_FIXTURES']!,
  ).listSync().whereType<Directory>()) {
    final fixture = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (!_fixtures.contains(fixture)) continue;
    await _measure(
      vault,
      fixture,
      dir,
      originals.path,
      folder,
    ).timeout(const Duration(minutes: 8));
  }
  await vault.lock();
  scratch.deleteSync(recursive: true);
  exit(0);
}

/// Prints the idle CPU of the app over [fixture], in a replica of [vault],
/// with [folder] in its library.
Future<void> _measure(
  Vault vault,
  String fixture,
  Directory dir,
  String originals,
  String folder,
) async {
  final db = await vault.openReplica(name: fixture);
  await addFolder(db, folder);
  final scanned = await _scanned(db, folder);
  await loadFixture(db, dir, originals);
  runApp(
    ProviderScope(
      overrides: [
        // This machine's keyring, if any, stays out of it.
        vaultProvider.overrideWith((ref) async => vault),
        replicaProvider.overrideWith((ref) async => db),
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(originals: true),
        ),
      ],
      child: const PhotolibApp(),
    ),
  );
  if (scanned && await _settled()) {
    await Future<void>.delayed(const Duration(seconds: 5));
    final cpu = _cpuTime();
    final watch = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 20));
    final idle = (_cpuTime() - cpu) / watch.elapsedMicroseconds;
    final watches = _watches();
    final before = _cpuTime();
    await FolderIndexer(db).scan(folder);
    final reconcile = _cpuTime() - before;
    final value = 100 * (idle + reconcile / Duration.microsecondsPerHour);
    _report({
      'metric': 'cpu',
      'target': const String.fromEnvironment('PERF_TARGET'),
      'fixture': fixture,
      'value': (value * 100).round() / 100,
      'watches': watches,
      'reconcile_ms': reconcile ~/ 1000,
    });
  } else {
    _report({
      'error': scanned
          ? '$fixture never showed its thumbnails'
          : 'the folder was never scanned in $fixture',
    });
  }
  runApp(const SizedBox());
  // Its watcher stops, and the next fixture is watched by its own alone.
  await removeFolder(db, folder);
  for (var i = 0; i < 100 && Platform.isLinux && _watches() > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await db.close();
}

/// 100,000 empty photos in folders of 100, from 1990: after every fixture's.
String _folder(String path) {
  final old = DateTime(1990);
  for (var d = 0; d < 1000; d++) {
    final dir = Directory('$path/$d')..createSync(recursive: true);
    for (var f = 0; f < 100; f++) {
      File('${dir.path}/$f.jpg')
        ..createSync()
        ..setLastModifiedSync(old);
    }
  }
  return path;
}

/// Whether the data isolate's watcher scanned the folder [root] within
/// five minutes.
Future<bool> _scanned(Replica db, String root) async {
  for (var i = 0; i < 300; i++) {
    final folder = await (db.select(
      db.mediaSource,
    )..where((s) => s.root.equals(root))).getSingleOrNull();
    if (folder?.state == 'online') return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// The directories inotify watches for this process on Linux; elsewhere the
/// one recursive watch of the folder.
int _watches() {
  if (!Platform.isLinux) return 1;
  var watches = 0;
  for (final fd in Directory('/proc/self/fdinfo').listSync()) {
    try {
      watches += File(fd.path)
          .readAsLinesSync()
          .where((line) => line.startsWith('inotify wd:'))
          .length;
    } on FileSystemException {
      // Closed meanwhile.
    }
  }
  return watches;
}

void _report(Map<String, Object> result) =>
    stdout.writeln('result: ${jsonEncode({'budget': 'idle-cpu', ...result})}');

/// Whether the timeline shows every visible cell's thumbnail within a minute.
Future<bool> _settled() async {
  for (var i = 0; i < 600; i++) {
    TimelineViewState? view;
    void visit(Element element) {
      if (element case StatefulElement(:final TimelineViewState state)) {
        view = state;
      } else {
        element.visitChildren(visit);
      }
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    if (view case final view?
        when allShown(view, view.widget.pages, view.widget.thumbnails)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// The CPU time of this process in µs, user and system.
int _cpuTime() {
  if (Platform.isLinux) {
    // utime and stime, the 14th and 15th fields, in ticks of 10 ms.
    final stat = File('/proc/self/stat').readAsStringSync();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    return (int.parse(fields[11]) + int.parse(fields[12])) * 10000;
  }
  if (Platform.isWindows) {
    final ms = Process.runSync('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds',
    ]).stdout;
    return (double.parse('$ms'.trim()) * 1000).round();
  }
  // macOS: [[hh:]mm:]ss.ss
  final time = '${Process.runSync('ps', ['-o', 'time=', '-p', '$pid']).stdout}';
  final seconds = time
      .trim()
      .split(':')
      .fold<double>(0, (sum, part) => sum * 60 + double.parse(part));
  return (seconds * 1e6).round();
}
