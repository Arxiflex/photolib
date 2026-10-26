// The acceptance case of M3-21: a pinned album of 5,000 items is fully
// browsable and playable with no network, never passes its budget, frees its
// space when unpinned and keeps private copies as ciphertext.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/offline/video_proxy.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart' show Unreachable;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../../support/fake_server.dart';
import '../../support/pump_app.dart' show MemoryStore;

final int _items = int.parse(Platform.environment['OFFLINE_ASSETS'] ?? '5000');
const _videoEvery = 50;

Uint8List _id(int kind, int n) => Uint8List(16)
  ..[0] = kind
  ..[12] = n >> 24
  ..[13] = n >> 16
  ..[14] = n >> 8
  ..[15] = n;

String _hex(List<int> b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();

String _uuid(Uint8List id) {
  final h = _hex(id);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

// The bytes of a file: a pattern of its asset and role, of the size the
// replica says.
Uint8List _bytes(int n, String role, int size) {
  final seed = n * 31 + role.length;
  return Uint8List.fromList([for (var i = 0; i < size; i++) (i + seed) & 255]);
}

const _sizes = {'thumb_s': 1024, 'thumb_m': 3072, 'preview': 8192, 'r1': 60000};

/// Serves the files above, or no one: the airplane.
class _Server extends FakeServer {
  bool airborne = false;
  int asked = 0;

  @override
  Future<Media> media(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    asked++;
    if (airborne) throw Unreachable('airplane mode');
    final [_, uuid, role] = path.split('?').first.split('/');
    final n = int.parse(uuid.substring(28), radix: 16);
    final size = _sizes[role] ?? (throw StateError(path));
    final bytes = _bytes(n, role, size);
    final range = RegExp(r'bytes=(\d+)-(\d+)')
        .firstMatch(headers['range'] ?? '');
    final part = range == null
        ? bytes
        : bytes.sublist(
            int.parse(range[1] ?? '0'),
            int.parse(range[2] ?? '0') + 1,
          );
    return (
      status: range == null ? 200 : 206,
      etag: null,
      bytes: Stream.value(part),
      length: part.length,
    );
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('a pinned album of $_items items is browsable and plays with no '
      'network, within its budget, and unpinning frees it', () async {
    final dir = await Directory.systemTemp.createTemp('photolib-airplane-');
    addTearDown(() => dir.delete(recursive: true));
    final (vault, _) = await scratchVault(
      '${dir.path}/store',
      Kernel().keyring,
    );
    addTearDown(vault.lock);
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    final server = _Server();
    final album = _id(5, 1);
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
    await db
        .into(db.album)
        .insert(
          AlbumCompanion.insert(
            id: album,
            ownerId: _id(2, 1),
            title: 'Big trip',
            createdAt: 1,
          ),
        );
    var expectedBytes = 0;
    await db.batch((b) {
      for (var n = 1; n <= _items; n++) {
        final video = n % _videoEvery == 0;
        b.insert(
          db.asset,
          AssetCompanion.insert(
            id: _id(3, n),
            libraryId: _id(1, 1),
            ownerId: _id(2, 1),
            originalFilename: '$n.${video ? 'mp4' : 'jpg'}',
            source: 'upload',
            mediaKind: video ? 'video' : 'image',
            createdAt: n,
            takenUtc: Value(n * 1000),
          ),
        );
        // Two tables, one row each: not a cascade of one statement.
        // ignore: cascade_invocations
        b.insert(
          db.albumItem,
          AlbumItemCompanion.insert(
            id: _id(6, n),
            albumId: album,
            kind: 'asset',
            assetId: Value(_id(3, n)),
            sortKey: n.toRadixString(36).padLeft(6, '0'),
          ),
        );
        var f = 0;
        for (final MapEntry(key: role, value: size) in _sizes.entries) {
          if (role == 'r1' && !video) continue;
          expectedBytes += size;
          b.insert(
            db.assetFile,
            AssetFileCompanion.insert(
              id: _id(4, n * 10 + f++),
              assetId: _id(3, n),
              role: role,
              mime: video ? 'video/mp4' : 'image/jpeg',
              size: size,
              contentHash: Value(
                Uint8List(32)
                  ..[0] = n
                  ..[1] = n >> 8
                  ..[2] = role.length,
              ),
              state: 'present',
            ),
          );
        }
      }
    });

    const budget = 2000000000;
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWith((ref) async => vault),
        replicaProvider.overrideWith((ref) async => db),
        replicaNameProvider.overrideWith((ref) async => 'acct'),
        sessionProvider.overrideWith((ref) => server),
        offlineSignedOutProvider.overrideWith((ref) => false),
        offlinePolicyStoreProvider.overrideWithValue(
          MemoryStore('{"preset":"travel","budget":$budget}'),
        ),
        offlinePinsStoreProvider.overrideWithValue(MemoryStore()),
        networkChangesProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(offlineKeepingProvider, (_, _) {});
    await container.read(offlinePolicyProvider.notifier).loaded;
    await container.read(offlinePinsProvider.notifier).loaded;
    final sync = await container.read(offlineSyncProvider.future);
    final store = await container.read(offlineStoreProvider.future);
    expect(store.budget, budget);

    // Pinned online: every file arrives, the budget holds at every step.
    var worst = 0;
    final seen = sync.progress.listen((p) => worst = max(worst, p.used));
    final clock = Stopwatch()..start();
    final done = sync.progress.firstWhere(
      (p) => !p.running && p.pins.values.any((x) => x.files > 0),
    );
    final pin = OfflinePin.album(album, 'Big trip');
    container.read(offlinePinsProvider.notifier).pin(pin);
    final progress = await done;
    await seen.cancel();
    // The measured time goes in the log, never into an assertion.
    // ignore: avoid_print
    print('pinned $_items items in ${clock.elapsedMilliseconds} ms');
    expect(progress.pins[pin.id]?.complete, isTrue);
    expect(progress.pins[pin.id]?.have, progress.pins[pin.id]?.files);
    expect(progress.failed, 0);
    expect(worst, lessThanOrEqualTo(budget));
    expect(store.used, lessThanOrEqualTo(budget));
    expect(store.used, greaterThan(expectedBytes));
    expect(sync.state.kept.length, _items);

    // Airplane mode: nothing can be asked of the server.
    server
      ..airborne = true
      ..asked = 0;
    final media = container.read(mediaProvider)!;
    // Browsing: the album lists every item, each tile and preview opens.
    final listed = await albumItems(db, album).first;
    expect(listed, hasLength(_items));
    for (var n = 1; n <= _items; n++) {
      for (final role in ['thumb_s', 'thumb_m', 'preview']) {
        final got = await media('media/${_uuid(_id(3, n))}/$role', {});
        expect(got.status, 200);
        expect(got.bytes.length, _sizes[role], reason: '$n $role');
        expect(got.bytes[7], _bytes(n, role, _sizes[role] ?? 0)[7]);
      }
    }
    expect(server.asked, 0, reason: 'the network was never asked');

    // Playing: the proxy serves each video's ranges from the store.
    final offline = await container.read(offlineMediaProvider.future);
    final proxy = await VideoProxy.start(offline, null);
    addTearDown(proxy.close);
    var played = 0;
    for (var n = _videoEvery; n <= _items; n += _videoEvery) {
      final url = await proxy.url('media/${_uuid(_id(3, n))}/r1');
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      final request = await client.getUrl(url)
        ..headers.set('range', 'bytes=1000-30999');
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      client.close();
      expect(response.statusCode, 206);
      expect(body, _bytes(n, 'r1', 60000).sublist(1000, 31000));
      played++;
    }
    expect(played, _items ~/ _videoEvery);
    expect(server.asked, 0);

    // Unpinned: the space goes back, exactly.
    final used = store.used;
    final gone = sync.progress.firstWhere((p) => !p.running && p.pins.isEmpty);
    container.read(offlinePinsProvider.notifier).unpin(pin.id);
    await gone;
    expect(used, greaterThan(0));
    expect(store.used, 0);
    expect(sync.state.kept, isEmpty);
    final left = Directory('${dir.path}/store/offline-acct');
    expect(
      !left.existsSync() || left.listSync(recursive: true).isEmpty,
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}
