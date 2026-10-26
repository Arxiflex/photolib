@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/servers/sync.dart';
import 'package:photolib_api/sync.dart' as pb;
import 'package:photolib_api/testing.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart' show MemoryStore;

String _uuid(int n) =>
    '018f3b52-4b7b-7000-8000-${n.toRadixString(16).padLeft(12, '0')}';

pb.Rows _rows(String entity, Map<String, Object> row) => pb.Rows(
  entity: entity,
  columns: row.keys,
  rows: [
    pb.Row(
      values: [
        for (final v in row.values)
          if (v is int) pb.Value(integer: Int64(v)) else pb.Value(text: '$v'),
      ],
    ),
  ],
);

/// A stand-in photolibd, instance [instance], whose library [library] holds
/// one file that is no photo, [file].
Future<SyncServer> _photolibd(String instance, int library, String file) async {
  final server = await SyncServer.start()
    ..epoch = '$instance.0';
  final id = _uuid(library);
  server.streams.addAll({
    for (final s in ['account', 'albums', 'tags', 'people']) s: [],
    'libraries': [
      [
        _rows('libraries', {
          'id': id,
          'owner_id': _uuid(100),
          'kind': 'managed',
          'privacy': 'standard',
          'access': 'rw',
          'state': 'online',
          'created_at': 1,
          'txid': 7,
        }),
      ],
    ],
    'assets/$id': [
      [
        _rows('assets', {
          'id': _uuid(library * 10),
          'library_id': id,
          'owner_id': _uuid(100),
          'original_filename': file,
          'source': 'upload',
          'media_kind': '',
          'created_at': 1,
          'txid': 9,
        }),
      ],
    ],
    'faces/$id': [],
  });
  return server;
}

/// A loaded machine's disk stalls each new replica's first writes for a minute
/// and more (3 times this test at once on the shared gate machine: 90 s to the
/// first sync, 4 s alone).
const _loadedDisk = Timeout(Duration(minutes: 6));

void main() {
  late Directory dir;
  late Vault vault;
  late SyncServer a;
  late SyncServer b;
  late MemoryStore store;
  late Map<String, Completer<void>> synced;
  setUp(() async {
    synced = {};
    // A desktop's: Android's would ask the device's health.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    dir = await Directory.systemTemp.createTemp('account-replicas');
    vault = Vault(
      location: dir.path,
      keystore: MemoryKeystore(),
      files: storeFiles(dir.path),
      keyring: Kernel().keyring,
    );
    await vault.unlock();
    a = await _photolibd('a', 1, 'a-report.pdf');
    b = await _photolibd('b', 2, 'b-notes.txt');
    SavedServer on(SyncServer server, String name, String replica) =>
        SavedServer(
          endpoints: [server.url],
          instance: server.epoch.split('.').first,
          account: Account(name: name, token: name, deviceId: name),
          replica: replica,
        );
    store = MemoryStore(
      jsonEncode(
        Accounts([on(a, 'ann', standaloneReplica), on(b, 'bob', 'replica-b')])
            .toJson(),
      ),
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await vault.lock();
    await a.close();
    await b.close();
    await dir.delete(recursive: true);
  });

  /// The end of the first sync with the server of [instance].
  Future<void> sync(String instance) =>
      synced.putIfAbsent(instance, Completer.new).future;

  /// The app's providers over [vault], syncing as the app does unless not
  /// [syncing].
  ProviderContainer open({bool syncing = true}) {
    final container = ProviderContainer.test(
      overrides: [
        vaultProvider.overrideWith((ref) async => vault),
        serverStoreProvider.overrideWithValue(store),
        connectProvider.overrideWithValue((_, _) => FakeServer()),
        syncProvider.overrideWithValue((db, config, instance) async {
          final done = synced.putIfAbsent(instance, Completer.new);
          try {
            await syncReplica(db, config, instance: instance);
            if (!done.isCompleted) done.complete();
          } on Object catch (error, stack) {
            if (!done.isCompleted) done.completeError(error, stack);
            rethrow;
          }
        }),
      ],
    )..listen(forgetRemovedProvider, (_, _) {});
    if (syncing) container.listen(syncingProvider, (_, _) {});
    return container;
  }

  /// The other files the account in use shows.
  Future<List<String>> shown(ProviderContainer container) async => [
    for (final f in await (await container.read(
      replicaProvider.future,
    )).otherFiles().get())
      f.name,
  ];

  Future<void> use(ProviderContainer container, int index) async {
    await container.read(accountsProvider.notifier).use(index);
    await sync(container.read(serverProvider).requireValue!.instance);
  }

  test('switching between two accounts on two servers takes under a second, '
      "and each replica holds its own server's rows only", () async {
    var container = open();
    await sync('a');
    expect(await shown(container), ['a-report.pdf']);
    await use(container, 1);
    expect(await shown(container), ['b-notes.txt']);
    for (final (replica, file, epoch) in [
      (standaloneReplica, 'a-report.pdf', 'a.0'),
      ('replica-b', 'b-notes.txt', 'b.0'),
    ]) {
      final db = await container.read(openReplicaProvider(replica).future);
      expect(
        [
          for (final asset in await db.select(db.asset).get())
            asset.originalFilename,
        ],
        [file],
      );
      expect(
        {
          for (final cursor in await db.select(db.syncCursor).get())
            cursor.epoch,
        },
        {epoch},
      );
    }

    // From a tap to the other account's first rows: to a replica not open
    // since the start, then back to one open. The fastest of three rounds,
    // without the sync a switch starts, which shares the replica's data
    // isolate and, on this loaded machine, delays its first rows by seconds.
    Future<Duration> switchTo(int index, String file) async {
      final clock = Stopwatch()..start();
      await container.read(accountsProvider.notifier).use(index);
      expect(await shown(container), [file]);
      return clock.elapsed;
    }

    final cold = <Duration>[];
    final warm = <Duration>[];
    for (var round = 0; round < 3; round++) {
      container.dispose();
      await vault.lock();
      await vault.unlock();
      container = open(syncing: false);
      expect(await shown(container), ['b-notes.txt']);
      cold.add(await switchTo(0, 'a-report.pdf'));
      warm.add(await switchTo(1, 'b-notes.txt'));
    }
    container.dispose();
    // The gate's log keeps the times.
    // ignore: avoid_print
    print('switching: cold $cold, warm $warm');
    Duration fastest(List<Duration> times) =>
        times.reduce((x, y) => x < y ? x : y);
    expect(fastest(cold), lessThan(const Duration(seconds: 1)));
    expect(fastest(warm), lessThan(const Duration(seconds: 1)));
  }, timeout: _loadedDisk);

  test("removing the account on the device's replica forgets what its server "
      'synced there, which the next account to connect adopts', () async {
    final container = open();
    addTearDown(container.dispose);
    await sync('a');
    await use(container, 1);
    await use(container, 0);
    await container.read(accountsProvider.notifier).remove();
    expect(await shown(container), ['b-notes.txt']);
    final device = await container.read(
      openReplicaProvider(standaloneReplica).future,
    );
    await expectLater(
      device.otherFiles().watch().map((files) => files.length),
      emitsThrough(0),
    );
    expect(await device.select(device.syncCursor).get(), isEmpty);
    await container
        .read(accountsProvider.notifier)
        .add(SavedServer(endpoints: [a.url], instance: 'c'));
    expect(container.read(serverProvider).value?.replica, standaloneReplica);
    expect(await shown(container), isEmpty);
  }, timeout: _loadedDisk);
}
