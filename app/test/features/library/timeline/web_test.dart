@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/core/logging.dart';
import 'package:photolib/features/library/timeline/browser_thumbnails.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_data/photolib_data.dart' show TileCache;
import 'package:photolib_workers/testing.dart';
import 'package:web/web.dart' as web;

import 'fixtures.dart';

void main() {
  final never = Tile();
  final files = <String, web.File>{};
  ThumbnailItem file(String name, List<int> bytes, String type) {
    files[name] = web.File(
      [Uint8List.fromList(bytes).toJS].toJS,
      name,
      web.FilePropertyBag(type: type),
    );
    return ThumbnailItem(name, Uri(scheme: 'folder', path: 'Photos/$name'));
  }

  // A 600 × 400 gradient, red growing to the right, and the same turned to
  // portrait by its EXIF orientation.
  final gradient = img.Image(width: 600, height: 400);
  for (final p in gradient) {
    p.setRgb(p.x * 255 ~/ 600, 40, 90);
  }
  final jpeg = file('a.jpg', img.encodeJpg(gradient), 'image/jpeg');
  final turned = file(
    'b.jpg',
    img.encodeJpg(gradient.clone()..exif.imageIfd.orientation = 6),
    'image/jpeg',
  );
  (int, int) size(ui.Image image) => (image.width, image.height);

  for (final imageDecoder in [true, false]) {
    test('decodes a file in a worker with '
        '${imageDecoder ? 'ImageDecoder' : 'createImageBitmap'}, to the tier '
        'and upright, never larger', () async {
      final pipeline = ThumbnailPipeline(
        decoders: [
          browserThumbnails(
            (item) async => files[item.key],
            imageDecoder: imageDecoder,
          ),
        ],
      );
      final heard = <LogRecord>[];
      final listening = Log.records.listen(heard.add);
      expect(size(await pipeline.load(jpeg, 128, never)), (192, 128));
      expect(size(await pipeline.load(jpeg, 1024, never)), (600, 400));
      expect(size(await pipeline.load(turned, 128, never)), (128, 192));
      await listening.cancel();
      final decodes = heard.where((r) => r.message == 'browser decode');
      expect(decodes.map((r) => r.fields['via']).toSet(), {
        if (imageDecoder) 'ImageDecoder' else 'createImageBitmap',
      });
      expect(decodes.first.fields['file'], 'folder:Photos/a.jpg');
      expect(
        heard
            .where((r) => r.message == 'decoded')
            .map((r) => r.fields['decoder']),
        everyElement('browser'),
      );
    });
  }

  test('a format the browser cannot decode, or a video, is marked', () async {
    final pipeline = ThumbnailPipeline(
      decoders: [browserThumbnails((item) async => files[item.key])],
    );
    final photo = file('a.heic', base64.decode(heic), 'image/heic');
    await expectLater(
      pipeline.load(photo, 128, never),
      throwsA(isA<NoThumbnail>().having((e) => e.video, 'video', false)),
    );
    final movie = file('a.mov', [0, 0, 0, 8], 'video/quicktime');
    await expectLater(
      pipeline.load(
        ThumbnailItem(movie.key, movie.uri, video: true),
        128,
        never,
      ),
      throwsA(isA<NoThumbnail>().having((e) => e.video, 'video', true)),
    );
  });

  test("a video's poster comes from the browser's player and is kept with "
      'its duration in the disk tier, so a reload plays nothing; its JPEG, '
      "fresh or kept, decodes with Flutter's codec on Chromium, which is "
      'ImageDecoder there, else with createImageBitmap in the worker, not '
      "CanvasKit's on the page (ADR-0056)", () async {
    final clip = await spawnHybridUri('web_clip.dart').stream.first as String;
    final movie = file('a.mp4', base64.decode(clip), 'video/mp4');
    final video = ThumbnailItem(movie.key, movie.uri, video: true);
    addTearDown(() => ui_web.browser.debugBrowserEngineOverride = null);
    for (final engine in ui_web.BrowserEngine.values) {
      ui_web.browser.debugBrowserEngineOverride = engine;
      var opened = 0;
      final posters = browserPosters((item) async {
        opened++;
        return files[item.key];
      });
      final cache = _Tiles();
      for (final visit in [1, 2]) {
        final reason = '${engine.name}, visit $visit';
        final heard = <LogRecord>[];
        final listening = Log.records.listen(heard.add);
        final pipeline = ThumbnailPipeline(cache: cache, decoders: [posters]);
        expect(size(await pipeline.load(video, 128, never)), (228, 128));
        expect(pipeline.duration(video), const Duration(seconds: 2));
        await pipeline.idle;
        await listening.cancel();
        expect(opened, 1, reason: reason);
        expect(
          [
            for (final r in heard)
              if (r.message == 'browser decode') r.fields['via'],
          ],
          [if (engine != ui_web.BrowserEngine.blink) 'createImageBitmap'],
          reason: reason,
        );
      }
    }
  });

  test('a kept tile the browser cannot decode is made again and replaced, '
      'on every engine', () async {
    final tile = Uint8List.fromList(
      img.encodeJpg(img.copyResize(gradient, height: 128)),
    );
    final again = Thumbnailer('again', (_, _, _) async => Pixels.encoded(tile));
    addTearDown(() => ui_web.browser.debugBrowserEngineOverride = null);
    for (final engine in ui_web.BrowserEngine.values) {
      ui_web.browser.debugBrowserEngineOverride = engine;
      final cache = _Tiles();
      await cache.put('${jpeg.key}-128', Uint8List.fromList([1, 2, 3]));
      final pipeline = ThumbnailPipeline(cache: cache, decoders: [again]);
      expect(size(await pipeline.load(jpeg, 128, never)), (
        192,
        128,
      ), reason: engine.name);
      await pipeline.idle;
      expect(await cache.get('${jpeg.key}-128'), tile, reason: engine.name);
    }
  });

  test('a video the browser cannot play is marked so', () async {
    final movie = file('b.mov', [0, 0, 0, 8], 'video/quicktime');
    final pipeline = ThumbnailPipeline(
      decoders: [browserPosters((item) async => files[item.key])],
    );
    await expectLater(
      pipeline.load(
        ThumbnailItem(movie.key, movie.uri, video: true),
        128,
        never,
      ),
      throwsA(
        isA<NoThumbnail>().having((e) => e.unplayable, 'unplayable', true),
      ),
    );
  });

  test('a decoded thumbnail is kept in memory: the next cell takes it from '
      'there', () async {
    var decodes = 0;
    final decode = browserThumbnails((item) async {
      decodes++;
      return files[item.key];
    });
    final thumbnails = Thumbnails(
      (item, tier, cancelled) =>
          ThumbnailPipeline(decoders: [decode])
              .load(item as ThumbnailItem, tier, cancelled),
    );
    final ready = Completer<void>();
    thumbnails.want(jpeg, 256, ready.complete, at: 0);
    await ready.future;
    thumbnails.want(jpeg, 256, () {}, at: 1);
    expect(thumbnails.get(jpeg, 256), isNotNull);
    expect(decodes, 1);
  });

  // HEIC without a HEIC decoder (M1-43, ADR-0387): the kernel's module finds
  // the coded images, WebCodecs decodes them. Chrome decodes AVC in software
  // everywhere and HEIF allows avc1 items, so the twins of the corpus' grid
  // files (tools/corpus/avc_twins.py) prove the path where HEVC is not
  // decodable, as it is not in Chrome on Linux.
  group('a HEIF still', () {
    late final Map<String, Object?> sent;
    late final Map<String, Object?> twins;
    setUpAll(() async {
      sent = ((await spawnHybridUri('web_heif.dart').stream.first) as Map)
          .cast<String, Object?>();
      twins = (sent['twins']! as Map).cast<String, Object?>();
    });

    ThumbnailPipeline heif() => ThumbnailPipeline(
      decoders: [
        browserThumbnails(
          (item) async => files[item.key],
          kernel: sent['module']! as String,
        ),
      ],
    );

    ThumbnailItem twin(String name) => file(
      name,
      base64.decode((sent['files']! as Map)[name]! as String),
      'image/heic',
    );

    /// The colour at each probe of [twin], read from [image] within 4/255.
    Future<void> expectProbes(
      ui.Image image,
      Map<String, Object?> twin,
      String reason,
    ) async {
      final [shownWidth, shownHeight] = (twin['shown']! as List).cast<num>();
      expect(
        image.width / image.height,
        closeTo(shownWidth / shownHeight, 0.02),
      );
      final pixels = (await image.toByteData())!;
      final probes = twin['probes']! as List;
      expect(probes, isNotEmpty);
      for (final [x as num, y as num, rgb as List<Object?>]
          in probes.cast<List<Object?>>()) {
        final px = (x * image.width / shownWidth).floor().clamp(
          0,
          image.width - 1,
        );
        final py = (y * image.height / shownHeight).floor().clamp(
          0,
          image.height - 1,
        );
        for (var c = 0; c < 3; c++) {
          expect(
            pixels.getUint8((py * image.width + px) * 4 + c),
            closeTo(rgb[c]! as num, 4),
            reason: '$reason at $x,$y (channel $c)',
          );
        }
      }
    }

    test('is decoded with WebCodecs in the worker, composed from its grid, '
        'cropped, turned and mirrored as the file says, at the tier, and the '
        "thmb item is used where it is big enough: the corpus' golden "
        'colours within 4/255', () async {
      final pipeline = heif();
      final heard = <LogRecord>[];
      final listening = Log.records.listen(heard.add);
      for (final name in twins.keys) {
        final item = twin(name);
        final entry = (twins[name]! as Map).cast<String, Object?>();
        final thumb = (entry['thumb']! as Map).cast<String, Object?>();
        // The thumbnail is 96 x 64: a tier within it shows that item.
        await expectProbes(
          await pipeline.load(item, 48, never),
          thumb,
          '$name at 48',
        );
        for (final tier in [128, 1024]) {
          final image = await pipeline.load(item, tier, never);
          final shown = (entry['shown']! as List).cast<num>();
          final scale = tier / (shown[0] < shown[1] ? shown[0] : shown[1]);
          expect(
            image.width,
            (shown[0] * (scale < 1 ? scale : 1)).round(),
            reason: '$name at $tier',
          );
          await expectProbes(image, entry, '$name at $tier');
        }
      }
      await listening.cancel();
      expect(
        heard
            .where((r) => r.message == 'browser decode')
            .map((r) => r.fields['via'])
            .toSet(),
        {'WebCodecs'},
      );
    });

    test('asks the browser once for each codec configuration: the next file, '
        'the next tier and a second visit ask nothing', () async {
      final pipeline = heif();
      final heard = <LogRecord>[];
      final listening = Log.records.listen(heard.add);
      Future<int> checks(String name, int tier) async {
        await pipeline.load(twin(name), tier, never);
        return heard
                .where((r) => r.message == 'browser decode')
                .last
                .fields['support_checks']!
            as int;
      }

      // The worker lives for the session: what an earlier test asked is
      // known. A file's tiles share a configuration, the thumbnail has
      // another, and a single image's differs by its size: three in all.
      final first = await checks('grid.heic', 128);
      expect(await checks('irot.heic', 128), first);
      expect(await checks('grid.heic', 1024), first);
      expect(await checks('grid.heic', 128), first);
      final withThumbnails = await checks('clap.heic', 48);
      expect(withThumbnails, lessThanOrEqualTo(first + 1));
      expect(await checks('imir.heic', 48), withThumbnails);
      expect(await checks('single.heic', 1024), lessThanOrEqualTo(3));
      await listening.cancel();
    });

    test('whose codec the browser cannot decode is marked with the reason, '
        'quickly, and the other files go on', () async {
      final pipeline = heif();
      final hevc = file(
        'iphone.heic',
        base64.decode(sent['hevc']! as String),
        'image/heic',
      );
      final jpegItem = jpeg;
      await pipeline.load(jpegItem, 128, never);
      final clock = Stopwatch()..start();
      await expectLater(
        pipeline.load(hevc, 128, never),
        throwsA(
          isA<NoThumbnail>().having(
            (e) => e.cause,
            'cause',
            allOf(
              contains('iphone.heic'),
              contains('HEVC'),
              contains('desktop app'),
              contains('connected server'),
            ),
          ),
        ),
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
      expect(size(await pipeline.load(jpeg, 128, never)), (192, 128));
      expect(
        size(await pipeline.load(twin('single.heic'), 128, never)).$1,
        128,
      );
    });

    test('that is cut off is marked, and the folder is not', () async {
      final pipeline = heif();
      final whole = base64.decode(
        (sent['files']! as Map)['grid.heic']! as String,
      );
      // Without its thumbnail the grid still shows; without its last tile it
      // cannot.
      final bare = file(
        'bare.heic',
        whole.sublist(0, whole.length - 100),
        'image/heic',
      );
      expect(size(await pipeline.load(bare, 128, never)).$1, 171);
      final cut = file(
        'cut.heic',
        whole.sublist(0, whole.length - 25000),
        'image/heic',
      );
      await expectLater(
        pipeline.load(cut, 128, never),
        throwsA(isA<NoThumbnail>()),
      );
      expect(size(await pipeline.load(twin('grid.heic'), 128, never)).$1, 171);
    });

    test('is the only kind of file that asks for the kernel: another format '
        'the browser refuses keeps its own reason', () async {
      // A module that is not there: a file that asked for it would say so.
      final pipeline = ThumbnailPipeline(
        decoders: [
          browserThumbnails(
            (item) async => files[item.key],
            kernel: 'http://127.0.0.1:9/none.js',
          ),
        ],
      );
      final other = file(
        'x.psd',
        List.filled(64, 7),
        'image/vnd.adobe.photoshop',
      );
      await expectLater(
        pipeline.load(other, 128, never),
        throwsA(
          isA<NoThumbnail>().having(
            (e) => e.cause,
            'cause',
            allOf(contains('x.psd'), isNot(contains('dynamically imported'))),
          ),
        ),
      );
    });

    test('keeps the page within its frame budget while a folder of 500 '
        "fills: the decoding is the worker's", () async {
      final whole = Uint8List.fromList(
        base64.decode((sent['files']! as Map)['grid.heic']! as String),
      );
      final blob = web.Blob([whole.toJS].toJS);
      final items = [
        for (var i = 0; i < 500; i++)
          () {
            final name = 'IMG_$i.HEIC';
            files[name] = web.File(
              [blob].toJS,
              name,
              web.FilePropertyBag(type: 'image/heic'),
            );
            return ThumbnailItem(name, Uri(scheme: 'folder', path: name));
          }(),
      ];
      final pipeline = heif();
      await withinFrameBudget(() async {
        for (var i = 0; i < items.length; i += 4) {
          await Future.wait([
            for (final item in items.skip(i).take(4))
              pipeline.load(item, 128, never),
          ]);
        }
      });
    });
  });
}

class _Tiles implements TileCache {
  final _tiles = <String, Uint8List>{};

  @override
  bool contains(String key) => _tiles.containsKey(key);

  @override
  Future<Uint8List?> get(String key) async => _tiles[key];

  @override
  Future<void> put(String key, Uint8List tile) async => _tiles[key] = tile;

  @override
  Future<void> remove(String key) async => _tiles.remove(key);
}
