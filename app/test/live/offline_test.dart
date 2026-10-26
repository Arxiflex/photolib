// Offline pins against a real photolibd: the library is pinned over the
// network, photolibd is stopped (airplane mode), and every tile and preview is
// still served, byte for byte what photolibd rendered, from the sealed store.
// main builds photolibd (untimed) unless PHOTOLIBD names a built one.
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/photolibd.dart';
import '../support/server_library.dart';

const _count = 40;

void main() {
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final binary = Platform.environment['PHOTOLIBD'] ?? Photolibd.build();
  late ServerLibrary library;
  late Directory cache;
  setUpAll(() async {
    library = await ServerLibrary.start(binary, _count);
    cache = await Directory.systemTemp.createTemp('photolib-cache-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache.path,
    );
  });
  tearDownAll(() async {
    try {
      await library.stop();
    } on PathNotFoundException {
      // The test stopped photolibd itself, which removed its scratch space.
    }
    await cache.delete(recursive: true);
  });

  test('a pinned library is browsed with photolibd stopped, from sealed '
      'chunks, and unpinning leaves nothing', () async {
    final app = library.app;
    final saved = app.read(serverProvider).requireValue!;
    final db = await app.read(replicaProvider.future);
    // The replica holds what photolibd rendered.
    for (var tries = 0; ; tries++) {
      await syncReplica(db, saved.config, instance: saved.instance);
      final files = await db.select(db.assetFile).get();
      if (files.where((f) => f.role == 'preview').length >= _count) break;
      if (tries > 300) fail('previews never rendered');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    app.listen(offlineKeepingProvider, (_, _) {});
    await app.read(offlinePolicyProvider.notifier).loaded;
    await app.read(offlinePinsProvider.notifier).loaded;
    final sync = await app.read(offlineSyncProvider.future);
    final store = await app.read(offlineStoreProvider.future);

    final done = sync.progress.firstWhere(
      (p) => !p.running && p.pins.values.any((x) => x.files > 0),
    );
    final pin = OfflinePin.library();
    app.read(offlinePinsProvider.notifier).pin(pin);
    // The library at the default preset (travel) is kept as previews.
    final progress = await done;
    expect(progress.pins[pin.id]?.complete, isTrue);
    expect(progress.failed, 0);
    expect(store.used, lessThanOrEqualTo(store.budget));
    expect(sync.state.kept.length, _count);

    // What photolibd serves, asked for before it stops.
    final live = app.read(sessionProvider)!;
    final assets = await db.select(db.asset).get();
    final expected = <String, List<int>>{};
    for (final a in assets) {
      final id = _uuid(a.id);
      for (final role in ['thumb_s', 'thumb_m', 'preview']) {
        final media = await live.media('media/$id/$role');
        expect(media.status, 200);
        expected['$id/$role'] = [
          for (final chunk in await media.bytes.toList()) ...chunk,
        ];
      }
    }

    // Airplane mode: photolibd is gone.
    await library.photolibd.stop();
    final media = app.read(mediaProvider)!;
    for (final entry in expected.entries) {
      final got = await media('media/${entry.key}', {});
      expect(got.status, 200, reason: entry.key);
      expect(got.bytes, entry.value, reason: entry.key);
    }
    // And the app's own tiles decode from it.
    final pipeline = ThumbnailPipeline(
      cache: await DiskCache.open(
        '${cache.path}/offline-tiles',
        await (await app.read(vaultProvider.future)).tileCipher(),
      ),
      media: media,
    );
    for (final a in assets.take(5)) {
      final item = ThumbnailItem.remote(a.id);
      final image = await pipeline.load(item, 256, Tile());
      expect(image.height, 256);
    }
    await pipeline.idle;

    // Unpinned: the space is returned.
    final used = store.used;
    final gone = sync.progress.firstWhere((p) => !p.running && p.pins.isEmpty);
    app.read(offlinePinsProvider.notifier).unpin(pin.id);
    await gone;
    expect(used, greaterThan(0));
    expect(store.used, 0);
  });
}

String _uuid(List<int> id) {
  final h = [for (final b in id) b.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
