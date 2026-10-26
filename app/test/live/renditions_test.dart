// Server items' tiles (T5) from a real photolibd: its WebP thumb_s and
// thumb_m of an external library, through the signed-in app's providers,
// revalidated by ETag, and pending while there is none.
// main builds photolibd (untimed), as photolibd_test.dart does.
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

import '../support/photolibd.dart';
import '../support/server_library.dart';

void main() {
  // Real time and real connections, for photolibd and the kernel's Argon2id.
  final binding = LiveTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final binary = Photolibd.build();
  late ServerLibrary library;
  late Directory cache;
  setUpAll(() async {
    library = await ServerLibrary.start(binary, 3);
    cache = await Directory.systemTemp.createTemp('photolib-cache-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache.path,
    );
  });
  tearDownAll(() async {
    await library.stop();
    await cache.delete(recursive: true);
  });

  test("a server item's tile is photolibd's thumb_s up to tier 256 and its "
      'thumb_m above, at the tier, with the ThumbHash sync brought', () async {
    final pipeline = await library.app.read(thumbnailPipelineProvider.future);
    for (final item in library.items) {
      expect(item.thumbHash, isNotNull);
      for (final tier in [128, 256, 512, 1024]) {
        final image = await pipeline.load(item, tier, Tile());
        expect(image.height, tier == 1024 ? 720 : tier);
        expect(image.width, closeTo(image.height * 4 / 3, 1));
      }
    }
    await pipeline.idle;
  });

  test('a tile whose hash the replica lacks is revalidated with its ETag, '
      "and photolibd's 304 keeps it", () async {
    final statuses = <int>[];
    final media = library.app.read(mediaProvider)!;
    final pipeline = ThumbnailPipeline(
      cache: await DiskCache.open(
        '${cache.path}/revalidated',
        await (await library.app.read(vaultProvider.future)).tileCipher(),
      ),
      media: (path, headers) async {
        final file = await media(path, headers);
        statuses.add(file.status);
        return file;
      },
    );
    final item = library.items.first;
    final unhashed = ThumbnailItem.remote(
      Uint8List.fromList([
        for (var i = 0; i < 32; i += 2)
          int.parse(item.key.substring(i, i + 2), radix: 16),
      ]),
    );
    for (var i = 0; i < 2; i++) {
      final image = await pipeline.load(unhashed, 256, Tile());
      expect(image.height, 256);
      await pipeline.idle;
    }
    expect(statuses, [200, 304]);
  });

  test('an asset photolibd has no rendition of, or does not show, is '
      'pending', () async {
    final pipeline = await library.app.read(thumbnailPipelineProvider.future);
    await expectLater(
      pipeline.load(ThumbnailItem.remote(Uint8List(16)), 256, Tile()),
      throwsA(isA<Pending>()),
    );
  });
}
