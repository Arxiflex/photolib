@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_workers/testing.dart';
import 'package:test/test.dart';

const _items = 100000;

/// The corpus' media files, which the items take turns to be.
final _corpus = Directory('../../../testdata/corpus/files').absolute.path;
final _media = [
  for (final f in Directory(_corpus).listSync(recursive: true))
    if (f is File && !RegExp(r'\.(json|pdf|xmp|THM)$|/[^.]+$').hasMatch(f.path))
      f.path.substring(_corpus.length + 1),
]..sort();

/// Writes [count] folder items under the corpus in [state], every one waiting for extraction.
Future<void> _seed(Replica db, int count, {String state = 'present'}) async {
  for (var n = 0; n < count; n += 10000) {
    await db.batch((b) {
      for (var i = n; i < min(count, n + 10000); i++) {
        b.insert(
          db.localAsset,
          LocalAssetCompanion.insert(
            id: Uint8List(16)
              ..buffer.asByteData().setUint32(12, i)
              ..[0] = 1,
            source: 'folder',
            volume: Value(_corpus),
            sourceId: '$i',
            size: 1,
            mtime: i,
            path: Value(_media[i % _media.length]),
            state: Value(state),
          ),
        );
      }
    });
  }
}

Future<int> _waiting(Replica db) async =>
    (await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM local_asset '
              "WHERE extracted IS NULL AND state = 'present'",
            )
            .getSingle())
        .read<int>('n');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final kernel = buildKernel();
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('photolib-data-'),
  );
  tearDown(() => dir.delete(recursive: true));

  /// The replica in [dir], through a vault that the test's teardown locks.
  Future<Replica> openReplica() async {
    final vault = Vault(
      location: '${dir.path}/store',
      keystore: MemoryKeystore(),
      files: storeFiles('${dir.path}/store'),
      keyring: Kernel.open(kernel).keyring,
    );
    await vault.unlock();
    addTearDown(vault.lock);
    return vault.openReplica();
  }

  test(
    '100,000 items are read in the data isolate, adding at most 1% to the 60 Hz frames this isolate misses idle',
    () async {
      final db = await openReplica();
      Future<void> extracted() async {
        while (await _waiting(db) > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      // 1,000 items first: tests run JIT, which pauses every isolate while it installs the code the pipeline runs for
      // the first time; release builds are compiled ahead of time.
      const warmUp = 1000;
      await _seed(db, _items + warmUp, state: 'offline');
      await db.customUpdate(
        "UPDATE local_asset SET state = 'present' WHERE mtime < $warmUp",
        updates: {db.localAsset},
      );
      extractMetadata(db, kernel: kernel);
      await extracted();

      await withinFrameBudget(() async {
        final clock = Stopwatch()..start();
        await db.customUpdate(
          "UPDATE local_asset SET state = 'present', extracted = NULL "
          'WHERE mtime >= $warmUp',
          updates: {db.localAsset},
        );
        await extracted();
        print('$_items items extracted in ${clock.elapsed}');
      });
      final india = await (db.select(
        db.localAsset,
      )..where((a) => a.path.equals('time/zones/india.jpg'))).get();
      expect(
        india.map((a) => '${a.takenLocal} ${a.tzOffsetMin} ${a.make}').toSet(),
        {'2023-04-14T08:30:00 330 Canon'},
      );
    },
    // Measures the machine: beside the rest of the suite at load 50 it ran
    // past its 5 minutes.
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'the root isolate steers the data isolate: visible items first, the rest while the device is healthy',
    () async {
      final db = await openReplica();
      await _seed(db, 3);
      Future<List<bool>> done() async => [
        for (final a in await (db.select(
          db.localAsset,
        )..orderBy([(a) => OrderingTerm(expression: a.mtime)])).get())
          a.extracted != null,
      ];
      Future<void> until(List<bool> expected) async {
        while ('${await done()}' != '$expected') {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      reportDeviceHealth(db, healthy: false);
      extractMetadata(db, kernel: kernel);
      extractFirst(db, [
        (await (db.select(
          db.localAsset,
        )..where((a) => a.mtime.equals(1))).getSingle()).id,
      ]);
      await until([false, true, false]);

      reportDeviceHealth(db, healthy: true);
      await until([true, true, true]);
    },
  );

  test(
    'a restart halfway through 100,000 items resumes where it stopped and reads none twice',
    () async {
      // A restart is a close and an open of the replica in WAL, as the data
      // isolate keeps it: no sync to disk is under test, and a loaded
      // machine's took minutes.
      QueryExecutor open() => NativeDatabase(
        File('${dir.path}/replica'),
        setup: (db) => db
          ..execute('PRAGMA journal_mode = WAL')
          ..execute('PRAGMA synchronous = OFF'),
      );
      var db = Replica(open());
      await _seed(db, _items);
      var files = 0;
      late MetadataExtractor first;
      // The extractor's bookkeeping is under test, not the kernel's reads,
      // which the frame budget above makes: with them, a loaded machine read
      // half the items in 5 minutes.
      Future<List<LocalAssetCompanion?>> counted(
        List<MediaFile> batch, {
        required bool visible,
      }) async {
        if ((files += batch.length) >= _items ~/ 2) unawaited(first.stop());
        return [for (final _ in batch) const LocalAssetCompanion()];
      }

      first = MetadataExtractor(db, counted);
      await first.run();
      final left = await _waiting(db);
      await db.close();

      db = Replica(open());
      addTearDown(db.close);
      await MetadataExtractor(db, counted).run();

      expect(left, inInclusiveRange(1, _items ~/ 2));
      expect(files, _items);
      expect(await _waiting(db), 0);
    },
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
