// The initial sync's frame budget, its stand-in photolibd in a process of its own (support/photolibd.dart).
// It runs alone (tagged), as a million assets synced beside the suite's other
// tests starve them.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_workers/testing.dart';
import 'package:test/test.dart';

import 'kernel.dart';
import 'support/sync_rows.dart';

/// Assets of the initial sync that the frame budget holds for
/// (docs/10-client-app.md §1.5); fewer while you work.
final int _assets = int.parse(
  Platform.environment['PHOTOLIB_SYNC_ASSETS'] ?? '1000000',
);

void main() {
  final kernel = testKernel();
  test(
    'an initial sync of $_assets assets runs in the data isolate, adding '
    'at most 1% to the 60 Hz frames this isolate misses idle',
    () async {
      final dir = await Directory.systemTemp.createTemp('photolib-sync-');
      addTearDown(() => dir.delete(recursive: true));
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: kernel.keyring,
      );
      await vault.unlock();
      addTearDown(vault.lock);
      final ui = await vault.openReplica();
      final photolibd = await Process.start('dart', [
        'run',
        'test/support/photolibd.dart',
      ]);
      addTearDown(photolibd.kill);
      final lines = StreamIterator(
        photolibd.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      Future<String> next() async => await lines.moveNext()
          ? lines.current
          : throw StateError('photolibd ended');
      final config = NetworkConfig(endpoints: [Uri.parse(await next())]);
      Future<void> newLibrary(int library, int assets) async {
        photolibd.stdin.writeln('$library $assets');
        await next();
      }

      // 2,000 assets first: tests run JIT, which pauses every isolate while it
      // installs the code that runs for the first time; release builds are
      // compiled ahead of time.
      await newLibrary(0, 2000);
      await syncReplica(ui, config);
      // The UI watches what the engine writes on a connection of its own.
      final streams = StreamIterator(
        ui
            .select(ui.syncCursor)
            .watch()
            .map((cursors) => {for (final c in cursors) c.stream})
            .timeout(const Duration(minutes: 1)),
      );
      addTearDown(streams.cancel);
      var library = 0;
      await withinFrameBudget(() async {
        // Each try in a library of its own, which takes the place of the last.
        await newLibrary(++library, _assets);
        final clock = Stopwatch()..start();
        await syncReplica(ui, config);
        // The gate's log keeps how long it took.
        // ignore: avoid_print
        print('$_assets assets synced in ${clock.elapsed}');
      });
      expect(
        await ui
            .customSelect(
              'SELECT COUNT(*) AS n, MIN(library_id) = MAX(library_id) AS one '
              'FROM asset',
            )
            .getSingle()
            .then((r) => r.data),
        {'n': _assets, 'one': 1},
      );
      while (await streams.moveNext() &&
          !streams.current.contains('assets/${uuid(library)}')) {}
    },
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
