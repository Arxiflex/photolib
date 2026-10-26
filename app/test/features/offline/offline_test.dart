@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../../support/fake_server.dart';
import '../../support/pump_app.dart' show MemoryStore;

Uint8List _id(int kind, int n) => Uint8List(16)
  ..[0] = kind
  ..[15] = n;

String _hex(List<int> b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

String _uuid(Uint8List id) {
  final h = _hex(id);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

void main() {
  late Directory dir;
  late Vault vault;
  late Replica db;
  late FakeServer server;
  late MemoryStore policyStore;
  late MemoryStore pinsStore;
  late ProviderContainer container;
  var signedOut = false;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-offline-app-');
    (vault, _) = await scratchVault('${dir.path}/store', Kernel().keyring);
    db = Replica(NativeDatabase.memory());
    server = FakeServer();
    policyStore = MemoryStore();
    pinsStore = MemoryStore();
    signedOut = false;
    await db
        .into(db.library)
        .insert(
          LibraryCompanion.insert(
            id: _id(1, 1),
            ownerId: _id(2, 1),
            kind: 'managed',
            privacy: 'standard',
            access: 'rw',
            state: 'online',
          ),
        );
    for (var n = 1; n <= 3; n++) {
      await db
          .into(db.asset)
          .insert(
            AssetCompanion.insert(
              id: _id(3, n),
              libraryId: _id(1, 1),
              ownerId: _id(2, 1),
              originalFilename: '$n.jpg',
              source: 'upload',
              mediaKind: 'image',
              createdAt: n,
            ),
          );
      var f = 0;
      for (final role in ['thumb_s', 'thumb_m', 'preview']) {
        final hash = Uint8List(32)
          ..[0] = n
          ..[1] = role.length;
        await db
            .into(db.assetFile)
            .insert(
              AssetFileCompanion.insert(
                id: _id(4, n * 10 + f++),
                assetId: _id(3, n),
                role: role,
                mime: 'image/jpeg',
                size: 100 + n,
                contentHash: Value(hash),
                state: 'present',
              ),
            );
        server.files['media/${_uuid(_id(3, n))}/$role'] = List.filled(
          100 + n,
          n,
        );
      }
      await db
          .into(db.albumItem)
          .insert(
            AlbumItemCompanion.insert(
              id: _id(6, n),
              albumId: _id(5, 1),
              kind: 'asset',
              assetId: Value(_id(3, n)),
              sortKey: 'k$n',
            ),
          );
    }
    await db
        .into(db.album)
        .insert(
          AlbumCompanion.insert(
            id: _id(5, 1),
            ownerId: _id(2, 1),
            title: 'Trip',
            createdAt: 1,
          ),
        );
    container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWith((ref) async => vault),
        replicaProvider.overrideWith((ref) async => db),
        replicaNameProvider.overrideWith((ref) async => 'acct'),
        sessionProvider.overrideWith((ref) => server),
        offlineSignedOutProvider.overrideWith((ref) => signedOut),
        offlinePolicyStoreProvider.overrideWithValue(policyStore),
        offlinePinsStoreProvider.overrideWithValue(pinsStore),
        networkChangesProvider.overrideWithValue(const Stream.empty()),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await vault.lock();
    await dir.delete(recursive: true);
  });

  final album = OfflinePin.album(_id(5, 1), 'Trip');

  Future<OfflineProgress> settled() async {
    final sync = await container.read(offlineSyncProvider.future);
    return await sync.progress.firstWhere(
      (p) => !p.running && p.pins.isNotEmpty,
    );
  }

  test(
    'a pinned album is kept by the session and shown with no network',
    () async {
      container.listen(offlineKeepingProvider, (_, _) {});
      await container.read(offlinePinsProvider.notifier).loaded;
      final done = settled();
      container.read(offlinePinsProvider.notifier).pin(album);
      final progress = await done;
      expect(progress.pins[album.id]!.complete, isTrue);
      expect(progress.pins[album.id]!.files, 9);

      // Airplane mode: the server holds nothing, the session cannot reach it.
      server.files.clear();
      final media = container.read(mediaProvider)!;
      final path = 'media/${_uuid(_id(3, 2))}/thumb_m';
      final got = await media(path, {});
      expect(got.status, 200);
      expect(got.bytes, List.filled(102, 2));
      // What was not pinned is the network's: unreachable here.
      await expectLater(
        media('media/${_uuid(_id(3, 2))}/original', {}),
        throwsA(anything),
      );
    },
  );

  test('unpinning frees the space the pin took', () async {
    container.listen(offlineKeepingProvider, (_, _) {});
    await container.read(offlinePinsProvider.notifier).loaded;
    final first = settled();
    container.read(offlinePinsProvider.notifier).pin(album);
    await first;
    final store = await container.read(offlineStoreProvider.future);
    expect(store.used, greaterThan(0));
    final sync = await container.read(offlineSyncProvider.future);
    final gone = sync.progress.firstWhere((p) => !p.running && p.pins.isEmpty);
    container.read(offlinePinsProvider.notifier).unpin(album.id);
    await gone;
    expect(store.used, 0);
  });

  test('the pins and the policy are kept sealed and read back', () async {
    container.read(offlinePinsProvider.notifier).pin(album);
    container
        .read(offlinePolicyProvider.notifier)
        .setPreset(StoragePreset.spaceSaver);
    await Future<void>.delayed(Duration.zero);
    expect(pinsStore.value, contains('Trip'));
    expect(policyStore.value, contains('spaceSaver'));

    final again = ProviderContainer(
      overrides: [
        replicaNameProvider.overrideWith((ref) async => 'acct'),
        vaultProvider.overrideWith((ref) async => vault),
        offlinePolicyStoreProvider.overrideWithValue(policyStore),
        offlinePinsStoreProvider.overrideWithValue(pinsStore),
      ],
    );
    addTearDown(again.dispose);
    await again.read(offlinePinsProvider.notifier).loaded;
    await again.read(offlinePolicyProvider.notifier).loaded;
    expect(again.read(offlinePinsProvider), [album]);
    expect(again.read(offlinePolicyProvider).preset, StoragePreset.spaceSaver);
  });

  test('signing out erases what was kept offline', () async {
    container.listen(offlineKeepingProvider, (_, _) {});
    await container.read(offlinePinsProvider.notifier).loaded;
    final first = settled();
    container.read(offlinePinsProvider.notifier).pin(album);
    await first;
    final store = await container.read(offlineStoreProvider.future);
    expect(store.used, greaterThan(0));
    signedOut = true;
    container.invalidate(offlineSignedOutProvider);
    await container.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.used, 0);
    expect(container.read(offlinePinsProvider), isEmpty);
  });
}
