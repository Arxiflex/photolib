import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/embedded.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/vips.dart';
import 'package:photolib_data/photolib_data.dart' show rawExtensions;

import 'fixtures.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('vips'));
  tearDown(() => dir.delete(recursive: true));

  // libvips is on the gate's machines, as the server needs it.
  late final Thumbnailer decode;
  setUpAll(() async => decode = (await vipsDecoder())!);
  final never = Completer<void>().future;

  Future<img.Image> tile(String path, int tier, {bool video = false}) async {
    final pixels = (await decode(
      ThumbnailItem(path, Uri.file(path), video: video),
      tier,
      never,
    ))!;
    return img.decodeImage(pixels.bytes)!;
  }

  Future<String> file(String name, List<int> bytes) async =>
      (await File('${dir.path}/$name').writeAsBytes(bytes)).path;

  test('a bundled libvips finds its HEIF and JPEG XL modules beside it', () {
    final frameworks = Directory('${dir.path}/Frameworks')..createSync();
    final library = '${frameworks.path}/libvips.42.dylib';
    expect(vipsModuleDir(library), isNull, reason: 'no vips-modules folder');
    expect(vipsModuleDir('libvips.42.dylib'), isNull, reason: 'a bare name');
    Directory('${frameworks.path}/vips-modules').createSync();
    expect(vipsModuleDir(library), '${frameworks.path}/vips-modules');
    if (Platform.isWindows) return;
    expect(vipsSetModuleDir('${frameworks.path}/vips-modules'), isTrue);
    final get = DynamicLibrary.process()
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)
        >('getenv');
    final name = 'VIPS_MODULEDIR'.toNativeUtf8();
    addTearDown(() => malloc.free(name));
    expect(get(name).toDartString(), '${frameworks.path}/vips-modules');
  });

  test('decodes HEIC, AVIF and JPEG XL to the tier, never larger', () async {
    for (final (name, data) in [
      ('a.heic', heic),
      ('a.avif', avif),
      ('a.jxl', jxl),
    ]) {
      final path = await file(name, base64.decode(data));
      final small = await tile(path, 32);
      expect((small.width, small.height), (48, 32), reason: name);
      final whole = await tile(path, 128);
      expect((whole.width, whole.height), (96, 64), reason: name);
      // Red grows to the right in the gradient.
      expect(whole.getPixel(90, 32).r, greaterThan(whole.getPixel(5, 32).r));
    }
  });

  test('decodes a 12 MP JPEG upright, by its EXIF orientation', () async {
    final photo = img.Image(width: 4000, height: 3000)
      ..exif.imageIfd.orientation = 6;
    final path = await file('big.jpg', img.encodeJpg(photo, quality: 50));
    final upright = await tile(path, 256);
    expect((upright.width, upright.height), (256, 341));
  });

  test('shows every RAW of the corpus by its largest embedded JPEG, turned '
      'as the RAW is and in colour, never its sensor data', () async {
    final golden = Directory('../testdata/corpus/golden').absolute;
    final raws = {
      for (final entry in golden.listSync(recursive: true))
        if (entry is File)
          if (jsonDecode(entry.readAsStringSync())
              case {
                'path': final String path,
                'format': final String format,
                'metadata': final Map<String, Object?> metadata,
              }
              when rawExtensions.contains(format))
            path: metadata['orientation'] as int? ?? 1,
    };
    expect(raws.length, greaterThan(20));
    for (final MapEntry(key: path, value: orientation) in raws.entries) {
      final raw = await tile('${golden.parent.path}/files/$path', 64);
      final preview = (await largestPreview(
        '${golden.parent.path}/files/$path',
      ))!;
      final stored = await tile(
        await file('stored.jpg', oriented(preview, 1)),
        64,
      );
      // Of the eight ways to turn the stored preview, the RAW's looks most
      // like the tile.
      int distance(int turn) {
        final turned = img.bakeOrientation(
          stored.clone()..exif.imageIfd.orientation = turn,
        );
        if (turned.width != raw.width || turned.height != raw.height) {
          return 1 << 62;
        }
        var sum = 0;
        for (final p in turned) {
          final q = raw.getPixel(p.x, p.y);
          sum += (p.r - q.r).abs().toInt() + (p.g - q.g).abs().toInt();
        }
        return sum;
      }

      final turns = [for (var turn = 1; turn <= 8; turn++) turn];
      expect(
        turns.reduce((a, b) => distance(a) <= distance(b) ? a : b),
        orientation,
        reason: path,
      );
      final chroma = [
        for (final p in raw)
          [p.r, p.g, p.b].reduce(max) - [p.r, p.g, p.b].reduce(min),
      ].reduce(max);
      expect(chroma, greaterThan(64), reason: '$path: no colour');
    }
  });

  test(
    'refuses what it cannot read, a header over 300 MP and videos',
    () async {
      final text = await file('a.jpg', utf8.encode('not a photo'));
      await expectLater(tile(text, 128), throwsA(isA<NoThumbnail>()));
      // libvips reads PPM, but only the loaders of the allow-list run.
      final ppm = await file('a.ppm', utf8.encode('P3 1 1 255 0 0 0'));
      await expectLater(tile(ppm, 128), throwsA(isA<NoThumbnail>()));
      // An 8 × 8 JPEG whose frame header claims 20,000 × 20,000 pixels.
      final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
      final sof = jpeg.indexed
          .firstWhere((b) => b.$2 == 0xc0 && jpeg[b.$1 - 1] == 0xff)
          .$1;
      ByteData.sublistView(jpeg)
        ..setUint16(sof + 4, 20000)
        ..setUint16(sof + 6, 20000);
      await expectLater(
        tile(await file('bomb.jpg', jpeg), 128),
        throwsA(
          isA<NoThumbnail>().having(
            (e) => e.cause,
            'cause',
            contains('300 MP'),
          ),
        ),
      );
      final movie = ThumbnailItem('m', Uri.file(text), video: true);
      await expectLater(
        decode(movie, 128, never),
        throwsA(isA<Declined>().having((e) => e.reason, 'reason', 'video')),
      );
    },
  );

  test('gives on-device ML upright 8-bit RGBA, its short side at most the '
      'size asked for; null for what it cannot read', () async {
    final (library, version) = (await vipsLibrary())!;
    expect(version, matches(RegExp(r'^vips \d+\.\d+\.\d+$')));
    final photo = img.Image(width: 1600, height: 1200)
      ..clear(img.ColorRgb8(200, 40, 10))
      ..exif.imageIfd.orientation = 6;
    final jpeg = await file('p.jpg', img.encodeJpg(photo));
    final upright = (await _pixels(library, jpeg))!;
    expect((upright.width, upright.height), (720, 960));
    expect(upright.rgba, hasLength(720 * 960 * 4));
    expect(upright.rgba.sublist(0, 4), [
      within(distance: 6, from: 200),
      within(distance: 6, from: 40),
      within(distance: 6, from: 10),
      255,
    ]);

    final grey = img.Image(width: 30, height: 20, numChannels: 1)
      ..clear(img.ColorRgb8(90, 90, 90));
    final png = await file('g.png', img.encodePng(grey));
    final pixels = (await _pixels(library, png))!;
    expect((pixels.width, pixels.height), (30, 20));
    expect(pixels.rgba.sublist(0, 4), [90, 90, 90, 255]);

    final text = await file('t.jpg', utf8.encode('not a photo'));
    expect(await _pixels(library, text), isNull);
  });
}

// On an isolate, as the data isolate decodes, with nothing of the test's.
Future<({int width, int height, Uint8List rgba})?> _pixels(
  String library,
  String path,
) => Isolate.run(() => vipsPixels(library, path, 720));
