import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show Vault;
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Vault vault;
  late DiskCache cache;
  final pipelines = <ThumbnailPipeline>[];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('renditions');
    final (opened, cipher) = await scratchVault(
      '${dir.path}/store',
      Kernel().keyring,
    );
    vault = opened;
    cache = await DiskCache.open('${dir.path}/cache', cipher);
  });
  tearDown(() async {
    for (final pipeline in pipelines) {
      await pipeline.idle;
    }
    pipelines.clear();
    await vault.lock();
    await dir.delete(recursive: true);
  });
  // Over the disk cache, whose writes end before the test does.
  ThumbnailPipeline pipelineOf(MediaFetch? media) {
    final pipeline = ThumbnailPipeline(cache: cache, media: media);
    pipelines.add(pipeline);
    return pipeline;
  }

  final id = Uint8List.fromList(List.generate(16, (i) => i));
  const asset = '00010203-0405-0607-0809-0a0b0c0d0e0f';
  Uint8List jpeg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h));
  String hex(int n) =>
      List.filled(32, n.toRadixString(16).padLeft(2, '0')).join();

  // photolibd's /media: each rendition by its path with its hash as its ETag,
  // a 304 when If-None-Match has it, and an empty 404 for anything else.
  late Map<String, (Uint8List, int)> served;
  late List<String> asked;
  Future<MediaFile> media(String path, Map<String, String> headers) async {
    asked.add([path, ?headers['if-none-match']].join(' '));
    final (bytes, hash) =
        served[Uri.parse(path).path] ?? (throw ServerError('not_found', null));
    final etag = '"${hex(hash)}"';
    return headers['if-none-match'] == etag
        ? (status: 304, etag: etag, bytes: Uint8List(0))
        : (status: 200, etag: etag, bytes: bytes);
  }

  setUp(() {
    served = {
      'media/$asset/thumb_s': (jpeg(384, 256), 1),
      'media/$asset/thumb_m': (jpeg(1080, 720), 2),
    };
    asked = [];
  });

  ThumbnailItem item({bool hashed = true}) => ThumbnailItem.remote(
    id,
    renditions: {
      if (hashed) 'thumb_s': Uint8List.fromList(List.filled(32, 1)),
      if (hashed) 'thumb_m': Uint8List.fromList(List.filled(32, 2)),
    },
    hash: Uint8List(25),
  );
  (int, int) size(ui.Image image) => (image.width, image.height);

  test("a server item's tile is its thumb_s up to tier 256 and its thumb_m "
      'above, at the tier, asked for by the hash the replica has', () async {
    final pipeline = pipelineOf(media);
    expect(
      [
        for (final tier in [128, 256, 512, 1024])
          size(await pipeline.load(item(), tier, Tile())),
      ],
      [(192, 128), (384, 256), (768, 512), (1080, 720)],
    );
    expect(asked, [
      'media/$asset/thumb_s?h=${hex(1)}',
      'media/$asset/thumb_s?h=${hex(1)}',
      'media/$asset/thumb_m?h=${hex(2)}',
      'media/$asset/thumb_m?h=${hex(2)}',
    ]);
    expect(item().key, '000102030405060708090a0b0c0d0e0f-0');
    expect(item().uri, Uri(path: 'media/$asset'));
  });

  test('keeps the tile in the disk cache with its ETag, and reads one whose '
      'ETag is the hash the replica has without asking the server', () async {
    var pipeline = pipelineOf(media);
    await pipeline.load(item(), 256, Tile());
    await pipeline.idle;
    expect(cache.contains('${item().key}-256'), isTrue);
    pipeline = pipelineOf(media);
    final tile = Tile();
    expect(size(await pipeline.load(item(), 256, tile)), (384, 256));
    expect(asked, hasLength(1));
    expect(tile.stages.keys, ['cache', 'upload']);
  });

  test('revalidates a tile whose ETag the replica does not have: a 304 keeps '
      'it, a 200 replaces it', () async {
    final pipeline = pipelineOf(media);
    final unhashed = item(hashed: false);
    await pipeline.load(unhashed, 256, Tile());
    await pipeline.idle;
    expect(size(await pipeline.load(unhashed, 256, Tile())), (384, 256));
    served['media/$asset/thumb_s'] = (jpeg(256, 256), 3);
    expect(size(await pipeline.load(unhashed, 256, Tile())), (256, 256));
    await pipeline.idle;
    await pipeline.load(unhashed, 256, Tile());
    expect(asked, [
      'media/$asset/thumb_s',
      'media/$asset/thumb_s "${hex(1)}"',
      'media/$asset/thumb_s "${hex(1)}"',
      'media/$asset/thumb_s "${hex(3)}"',
    ]);
  });

  test('a rendition not rendered yet (404), a server out of reach or none '
      'signed in is pending; another error of the server fails', () async {
    served.clear();
    await expectLater(
      pipelineOf(media).load(item(), 256, Tile()),
      throwsA(isA<Pending>()),
    );
    for (final media in <MediaFetch?>[
      (_, _) => throw Unreachable('connection refused'),
      null,
    ]) {
      await expectLater(
        pipelineOf(media).load(item(), 256, Tile()),
        throwsA(isA<Pending>()),
      );
    }
    await expectLater(
      pipelineOf((_, _) => throw ServerError('internal', null))
          .load(item(), 256, Tile()),
      throwsA(isA<ServerError>()),
    );
  });

  test('keeps every tile of a screen that arrives at once, as they need no '
      'encoding', () async {
    final pipeline = pipelineOf(media);
    final items = [
      for (var i = 0; i < 40; i++) ThumbnailItem.remote(Uint8List(16)..[0] = i),
    ];
    for (final i in items) {
      served['${i.uri.path}/thumb_s'] = served['media/$asset/thumb_s']!;
    }
    await Future.wait([for (final i in items) pipeline.load(i, 256, Tile())]);
    await pipeline.idle;
    expect(items.where((i) => !cache.contains('${i.key}-256')), isEmpty);
  });

  test('a cached tile that does not decode is fetched again', () async {
    final pipeline = pipelineOf(media);
    await pipeline.load(item(), 256, Tile());
    await pipeline.idle;
    final key = '${item().key}-256';
    final entry = (await cache.get(key))!;
    // Its ETag, and the first bytes of the JPEG.
    final jpeg = served['media/$asset/thumb_s']!.$1;
    await cache.put(
      key,
      Uint8List.sublistView(entry, 0, entry.length - jpeg.length + 3),
    );
    expect(size(await pipeline.load(item(), 256, Tile())), (384, 256));
    expect(asked, hasLength(2));
  });
}
