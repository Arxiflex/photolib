@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:photolib_api/photolib_api.dart' show NetworkConfig;
import 'package:photolib_api/testing.dart' show SyncServer;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_harness/photolib_harness.dart';
import 'package:test/test.dart';

import 'kernel.dart';
import 'support/sync_rows.dart';

void main() {
  final kernel = testKernel();
  // Several clients of one replica in this isolate are the point here, not a mistake.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late Vault vault;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-data-');
    vault = Vault(
      location: '${dir.path}/store',
      keystore: MemoryKeystore(),
      files: storeFiles('${dir.path}/store'),
      keyring: kernel.keyring,
    );
    await vault.unlock();
  });
  tearDown(() async {
    await vault.lock();
    await dir.delete(recursive: true);
  });

  test(
    'the replica has the same schema and answers the same queries',
    () async {
      expect(await probeReplica(await vault.openReplica()), expectedProbe);
    },
  );

  test(
    'every opening in the process is a client of one data isolate, the only writer',
    () async {
      final ui = await vault.openReplica();
      final again = await vault.openReplica();
      final port = (await ui.serializableConnection()).connectPort;
      expect((await again.serializableConnection()).connectPort, port);
    },
  );

  test(
    'a background isolate writes through the data isolate and the UI sees it live',
    () async {
      final ui = await vault.openReplica();
      final cursors = StreamIterator(ui.select(ui.syncCursor).watch());
      addTearDown(cursors.cancel);
      Future<List<String>> next() async {
        expect(await cursors.moveNext(), isTrue);
        return [for (final c in cursors.current) c.stream];
      }

      // The write must follow the initial query, or that query may already see it.
      expect(await next(), isEmpty);
      final caller = Isolate.current.debugName;
      final worker = await onDataConnection(ui, (db) async {
        await db
            .into(db.syncCursor)
            .insert(
              SyncCursorCompanion.insert(
                stream: 'assets/1',
                cursor: Uint8List(1),
                updatedAt: 1,
              ),
            );
        return Isolate.current.debugName;
      });
      expect(await next(), ['assets/1']);
      expect(worker, isNot(caller));
    },
  );

  test(
    'a replica that cannot be opened says why, and the next opening tries again',
    () async {
      final later = Directory('${dir.path}/store/later')
        ..createSync(recursive: true);
      await expectLater(
        vault.openReplica(name: 'later'),
        throwsA(predicate((e) => '$e'.contains('cannot open ${later.path}'))),
      );
      expect(takeProblems(), [contains('data isolate failed to open')]);
      await later.delete();
      final db = await vault.openReplica(name: 'later');
      expect(await db.select(db.outbox).get(), isEmpty);
    },
  );

  test("forgetting a replica's server waits for its sync under way, which "
      'leaves nothing of that server behind', () async {
    final db = await vault.openReplica();
    final photolibd = await SyncServer.start();
    addTearDown(photolibd.close);
    photolibd.streams.addAll({
      for (final s in ['account', 'albums', 'tags', 'people']) s: [],
      'libraries': [
        [
          rows('libraries', [library(1)]),
        ],
      ],
      'assets/${uuid(1)}': [
        for (var b = 0; b < 20; b++)
          [
            rows('assets', [
              for (var i = 0; i < 50; i++) asset(b * 50 + i + 2),
            ]),
          ],
      ],
      'faces/${uuid(1)}': [],
    });
    final synced = syncReplica(db, NetworkConfig(endpoints: [photolibd.url]));
    await forgetReplica(db);
    await synced;
    expect(await db.select(db.asset).get(), isEmpty);
    expect(await db.select(db.syncCursor).get(), isEmpty);
  });

  test('another replica gets its own data isolate', () async {
    final a = await vault.openReplica();
    final b = await vault.openReplica(name: 'other');
    expect(
      (await a.serializableConnection()).connectPort,
      isNot((await b.serializableConnection()).connectPort),
    );
  });

  test(
    'nothing Photolib stores holds plaintext: the replica, its WAL and the cached files',
    () async {
      await storeMarkers(vault, await vault.openReplica());
      expect(
        await File('${dir.path}/store/replica-wal').length(),
        greaterThan(0),
      );
      await vault.lock();
      expect(await markerHits('${dir.path}/store'), isEmpty);

      final plain = File('${dir.path}/plain')
        ..writeAsStringSync(markers.join());
      expect((await markerHits(dir.path))[plain.path], markers);
    },
  );

  test('without its page key the replica is no database', () async {
    final db = await vault.openReplica();
    await db
        .into(db.syncCursor)
        .insert(
          SyncCursorCompanion.insert(
            stream: 's',
            cursor: Uint8List(1),
            updatedAt: 1,
          ),
        );
    await vault.lock();
    final raw = Replica(NativeDatabase(File('${dir.path}/store/replica')));
    addTearDown(raw.close);
    await expectLater(
      raw.select(raw.syncCursor).get(),
      throwsA(predicate((e) => '$e'.contains('file is not a database'))),
    );
  });
}
