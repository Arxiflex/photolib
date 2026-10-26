@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:test/test.dart';

import 'kernel.dart';

Uint8List _id(int kind, int n) => Uint8List(16)
  ..[0] = kind
  ..[14] = n >> 8
  ..[15] = n & 255;

String _hex(List<int> b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

String _uuid(Uint8List id) {
  final h = _hex(id);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

void main() {
  final kernel = testKernel();
  late Directory dir;
  late Vault vault;
  late Replica db;
  late OfflineStore store;
  late Map<String, Uint8List> server;
  late List<String> asked;
  OfflineSync? sync;

  // What the server answers; set a callback to fail or hold a request.
  Future<Stream<List<int>>> Function(String path)? onFetch;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-offline-sync-');
    vault = Vault(
      location: dir.path,
      keystore: MemoryKeystore(),
      files: storeFiles(dir.path),
      keyring: kernel.keyring,
    );
    await vault.unlock();
    db = Replica(NativeDatabase.memory());
    store = await OfflineStore.open(
      vault,
      storeFiles(dir.path),
      budget: 1 << 20,
      chunkSize: 4096,
    );
    server = {};
    asked = [];
    onFetch = null;
    for (final (n, privacy) in [(1, 'standard'), (2, 'private')]) {
      await db
          .into(db.library)
          .insert(
            LibraryCompanion.insert(
              id: _id(1, n),
              ownerId: _id(2, 1),
              kind: 'managed',
              privacy: privacy,
              access: 'rw',
              state: 'online',
            ),
          );
    }
  });
  tearDown(() async {
    await sync?.close();
    sync = null;
    await db.close();
    await vault.lock();
    await dir.delete(recursive: true);
  });

  OfflineSync engine() => sync = OfflineSync(
    db: db,
    store: store,
    parallel: 3,
    fetch: (path) async {
      asked.add(path);
      if (onFetch case final f?) return await f(path);
      final bytes = server[path.split('?').first];
      if (bytes == null) throw const OfflineMissing();
      return Stream.fromIterable([
        for (var i = 0; i < bytes.length; i += 1500)
          bytes.sublist(i, (i + 1500).clamp(0, bytes.length)),
      ]);
    },
  );

  // An image of the server with its renditions, whose bytes the fake serves.
  Future<void> asset(
    int n, {
    int library = 1,
    int tile = 300,
    int preview = 2000,
    int original = 6000,
  }) async {
    await db
        .into(db.asset)
        .insert(
          AssetCompanion.insert(
            id: _id(3, n),
            libraryId: _id(1, library),
            ownerId: _id(2, 1),
            originalFilename: '$n.jpg',
            source: 'upload',
            mediaKind: 'image',
            createdAt: 1000 + n,
          ),
        );
    var f = 0;
    for (final (role, size) in [
      ('thumb_s', tile),
      ('thumb_m', tile * 2),
      ('preview', preview),
      ('original', original),
    ]) {
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
              size: size,
              contentHash: Value(hash),
              state: 'present',
            ),
          );
      server['media/${_uuid(_id(3, n))}/$role'] = Uint8List.fromList([
        for (var i = 0; i < size; i++) (i + n) & 255,
      ]);
    }
  }

  Future<void> album(int n, List<int> assets) async {
    await db
        .into(db.album)
        .insert(
          AlbumCompanion.insert(
            id: _id(5, n),
            ownerId: _id(2, 1),
            title: 'Album $n',
            createdAt: 1,
          ),
        );
    for (final (i, a) in assets.indexed) {
      await db
          .into(db.albumItem)
          .insert(
            AlbumItemCompanion.insert(
              id: _id(6, n * 100 + i),
              albumId: _id(5, n),
              kind: 'asset',
              assetId: Value(_id(3, a)),
              sortKey: 'k${i.toString().padLeft(4, '0')}',
            ),
          );
    }
  }

  OfflinePin pin(int n, {bool originals = false}) =>
      OfflinePin.album(_id(5, n), 'Album $n', originals: originals);

  // Every byte of the offline files now, a chunk being written included; one
  // renamed or removed while it is counted counts as it was found.
  int diskNow() {
    var total = 0;
    final offline = Directory('${dir.path}/offline');
    if (!offline.existsSync()) return 0;
    for (final f in offline.listSync(recursive: true)) {
      if (f is File) {
        try {
          total += f.lengthSync();
        } on FileSystemException {
          // Renamed into place a moment ago.
        }
      }
    }
    return total;
  }

  Future<int> onDisk() async => diskNow();

  const travel = StoragePolicy(); // the default preset

  test(
    'a pinned album is fetched whole and then served from the store',
    () async {
      for (var n = 1; n <= 4; n++) {
        await asset(n);
      }
      await album(1, [1, 2, 3, 4]);
      final sync = engine();
      await sync.reconcile(travel, [pin(1)]);
      final progress = sync.state.pins[pin(1).id]!;
      expect(progress.files, 12);
      expect(progress.have, 12);
      expect(progress.complete, isTrue);
      expect(sync.state.running, isFalse);
      expect(sync.state.waiting, isFalse);
      expect(asked, hasLength(12));
      expect(asked.where((p) => p.endsWith('/original')), isEmpty);

      // Offline: the same answers as the server's, and no request.
      final media = OfflineMedia(db, store);
      asked.clear();
      for (var n = 1; n <= 4; n++) {
        final path = 'media/${_uuid(_id(3, n))}/thumb_m';
        final got = await media.fetch(path, {});
        expect(got!.status, 200);
        expect(got.bytes, server[path]);
        final etag = got.etag!;
        expect((await media.fetch(path, {'if-none-match': etag}))!.status, 304);
        final pinned = await media.fetch(
          '$path?h=${etag.replaceAll('"', '')}',
          {},
        );
        expect(pinned!.bytes, server[path]);
      }
      expect(asked, isEmpty);
      expect(
        await media.fetch('media/${_uuid(_id(3, 1))}/original', {}),
        isNull,
      );
      expect(
        await media.fetch('media/${_uuid(_id(3, 9))}/thumb_s', {}),
        isNull,
      );
    },
  );

  test('the assets it holds whole are told, as the pins come and go', () async {
    for (var n = 1; n <= 3; n++) {
      await asset(n);
    }
    await album(1, [1, 2]);
    await album(2, [2, 3]);
    final sync = engine();
    await sync.reconcile(travel, [pin(1)]);
    expect(sync.state.kept, {_hex(_id(3, 1)), _hex(_id(3, 2))});
    await sync.reconcile(travel, [pin(1), pin(2)]);
    expect(sync.state.kept, {for (var n = 1; n <= 3; n++) _hex(_id(3, n))});
    await sync.reconcile(travel, [pin(2)]);
    expect(sync.state.kept, {_hex(_id(3, 2)), _hex(_id(3, 3))});
    await sync.reconcile(travel, []);
    expect(sync.state.kept, isEmpty);
  });

  test('an asset with a file still to come is not told as kept', () async {
    await asset(1);
    await album(1, [1]);
    var served = 0;
    onFetch = (path) async {
      if (++served > 2) throw const OfflineUnreachable();
      return Stream.value(server[path.split('?').first]!);
    };
    final sync = engine();
    await sync.reconcile(travel, [pin(1)]);
    expect(sync.state.waiting, isTrue);
    expect(sync.state.kept, isEmpty);
  });

  test('the budget is never exceeded, at any moment, on disk', () async {
    for (var n = 1; n <= 12; n++) {
      await asset(n);
    }
    await album(1, [for (var n = 1; n <= 12; n++) n]);
    // 12 × 2,900 bytes of renditions, with the envelopes on top.
    const policy = StoragePolicy(budget: 20000);
    final sync = engine();
    var worst = 0;
    var worstDisk = 0;
    final seen = sync.progress.listen((s) {
      if (s.used > worst) worst = s.used;
      final d = diskNow();
      if (d > worstDisk) worstDisk = d;
    });
    await sync.reconcile(policy, [pin(1)]);
    await seen.cancel();
    expect(worst, lessThanOrEqualTo(20000));
    expect(worstDisk, lessThanOrEqualTo(20000));
    expect(store.used, lessThanOrEqualTo(20000));
    expect(await onDisk(), store.used);
    final progress = sync.state.pins[pin(1).id]!;
    expect(progress.left, greaterThan(0));
    expect(progress.leftBytes, greaterThan(0));
    expect(progress.complete, isFalse);
    // The tiles of every item come before any preview.
    expect([
      for (var n = 1; n <= 12; n++)
        for (final r in ['thumb_s', 'thumb_m'])
          store.has(
            OfflineMedia.keyOf(
              _hex(_id(3, n)),
              r,
              _hex(
                Uint8List(32)
                  ..[0] = n
                  ..[1] = r.length,
              ),
            ),
          ),
    ], everyElement(isTrue));
  });

  test('unpinning frees the space', () async {
    for (var n = 1; n <= 3; n++) {
      await asset(n);
    }
    await album(1, [1, 2, 3]);
    await album(2, [3]);
    final sync = engine();
    await sync.reconcile(travel, [pin(1), pin(2)]);
    final both = store.used;
    expect(both, greaterThan(0));
    await sync.reconcile(travel, [pin(2)]);
    expect(store.used, lessThan(both));
    expect(store.used, await onDisk());
    // What the other pin still wants stays.
    expect(
      await OfflineMedia(
        db,
        store,
      ).fetch('media/${_uuid(_id(3, 3))}/preview', {}),
      isNotNull,
    );
    expect(
      await OfflineMedia(
        db,
        store,
      ).fetch('media/${_uuid(_id(3, 1))}/preview', {}),
      isNull,
    );
    await sync.reconcile(travel, []);
    expect(store.used, 0);
    expect(await onDisk(), 0);
    expect(sync.state.pins, isEmpty);
  });

  test('lowering the budget drops files until it fits', () async {
    for (var n = 1; n <= 6; n++) {
      await asset(n);
    }
    await album(1, [for (var n = 1; n <= 6; n++) n]);
    final sync = engine();
    await sync.reconcile(travel, [pin(1)]);
    final full = store.used;
    await sync.reconcile(const StoragePolicy(budget: 12000), [pin(1)]);
    expect(full, greaterThan(12000));
    expect(store.used, lessThanOrEqualTo(12000));
    expect(await onDisk(), store.used);
    expect(store.budget, 12000);
  });

  test(
    'without the network it waits, keeps what it has and goes on later',
    () async {
      for (var n = 1; n <= 4; n++) {
        await asset(n);
      }
      await album(1, [1, 2, 3, 4]);
      var served = 0;
      onFetch = (path) async {
        if (++served > 5) throw const OfflineUnreachable('no signal');
        return Stream.value(server[path.split('?').first]!);
      };
      final sync = engine();
      await sync.reconcile(travel, [pin(1)]);
      expect(sync.state.waiting, isTrue);
      expect(sync.state.running, isFalse);
      final partial = sync.state.pins[pin(1).id]!;
      expect(partial.have, lessThan(partial.files));
      expect(partial.have, greaterThan(0));

      onFetch = null;
      asked.clear();
      await sync.retry();
      expect(sync.state.waiting, isFalse);
      expect(sync.state.pins[pin(1).id]!.complete, isTrue);
      // Only the missing files were asked for.
      expect(asked.length, partial.files - partial.have);
    },
  );

  test('a file the server lacks or has at another size is skipped', () async {
    for (var n = 1; n <= 3; n++) {
      await asset(n);
    }
    await album(1, [1, 2, 3]);
    server.remove('media/${_uuid(_id(3, 2))}/preview');
    server['media/${_uuid(_id(3, 3))}/thumb_s'] = Uint8List(7);
    final sync = engine();
    await sync.reconcile(travel, [pin(1)]);
    expect(sync.state.failed, 2);
    expect(sync.state.pins[pin(1).id]!.have, 7);
    expect(store.used, await onDisk());
    expect(store.reserved, 0);
  });

  test(
    'a body cut off half way waits for the network and leaves no trace',
    () async {
      await asset(1);
      await album(1, [1]);
      onFetch = (path) async => Stream.fromFuture(
        Future<List<int>>.delayed(
          Duration.zero,
          () => throw const SocketException('connection lost'),
        ),
      );
      final sync = engine();
      await sync.reconcile(travel, [pin(1)]);
      expect(sync.state.waiting, isTrue);
      expect(store.used, 0);
      expect(store.reserved, 0);
      expect(await onDisk(), 0);
    },
  );

  test('an asset dated 2100 is kept like any other', () async {
    await asset(1);
    await asset(2);
    await db.customStatement(
      'UPDATE asset SET taken_utc = 4102444800000 WHERE rowid = 2',
    );
    final sync = engine();
    await sync.reconcile(
      const StoragePolicy(preset: StoragePreset.spaceSaver),
      [],
    );
    expect(sync.state.kept, {_hex(_id(3, 1)), _hex(_id(3, 2))});
    expect(asked.first, contains(_uuid(_id(3, 2))));
  });

  test('a new pass takes over from one that is running', () async {
    for (var n = 1; n <= 4; n++) {
      await asset(n);
    }
    await album(1, [1, 2, 3, 4]);
    final gate = Completer<void>();
    onFetch = (path) async {
      await gate.future;
      return Stream.value(server[path.split('?').first]!);
    };
    final sync = engine();
    final first = sync.reconcile(travel, [pin(1)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Unpinned before anything arrived.
    final second = sync.reconcile(travel, []);
    gate.complete();
    await Future.wait([first, second]);
    expect(store.used, 0);
    expect(await onDisk(), 0);
    expect(sync.state.pins, isEmpty);
  });

  test(
    'catalogue only keeps nothing, and pins wait for another preset',
    () async {
      await asset(1);
      await album(1, [1]);
      final sync = engine();
      await sync.reconcile(
        const StoragePolicy(preset: StoragePreset.catalogueOnly),
        [pin(1)],
      );
      expect(store.used, 0);
      expect(asked, isEmpty);
      await sync.reconcile(travel, [pin(1)]);
      expect(store.used, greaterThan(0));
      await sync.reconcile(
        const StoragePolicy(preset: StoragePreset.catalogueOnly),
        [pin(1)],
      );
      expect(store.used, 0);
    },
  );

  test(
    'private copies stay ciphertext at rest, the same bytes the server sent',
    () async {
      final secret = utf8.encode('PRIVATE-PICNIC-PHOTO' * 40);
      // What the server holds of a private library's file: ciphertext only.
      final ciphertext = await vault.seal(
        'private-library',
        Uint8List.fromList(secret),
      );
      expect(latin1.decode(ciphertext), isNot(contains('PRIVATE-PICNIC')));
      await asset(1, library: 2);
      await db.customStatement(
        'UPDATE asset_file SET size = ${ciphertext.length}',
      );
      for (final role in ['thumb_s', 'thumb_m', 'preview', 'original']) {
        server['media/${_uuid(_id(3, 1))}/$role'] = ciphertext;
      }
      await album(1, [1]);
      final sync = engine();
      await sync.reconcile(travel, [pin(1)]);
      expect(sync.state.pins[pin(1).id]!.complete, isTrue);

      var atRest = '';
      await for (final f in Directory(dir.path).list(recursive: true)) {
        if (f is File) atRest += latin1.decode(await f.readAsBytes());
      }
      expect(atRest, isNot(contains('PRIVATE-PICNIC')));
      // And what it gives back is the ciphertext, to be opened in memory.
      final got = await OfflineMedia(
        db,
        store,
      ).fetch('media/${_uuid(_id(3, 1))}/thumb_s', {});
      expect(got!.bytes, ciphertext);
      expect(await vault.unseal('private-library', got.bytes), secret);
    },
  );
}
