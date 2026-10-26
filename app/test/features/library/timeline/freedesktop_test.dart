import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/freedesktop.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';

void main() {
  late Directory dir;
  late ThumbnailItem photo;
  final never = Completer<void>().future;
  final modified = DateTime.utc(2024, 5, 3, 10, 20, 30);
  final seconds = '${modified.millisecondsSinceEpoch ~/ 1000}';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('freedesktop');
    final original = File('${dir.path}/my photo.jpg')..writeAsStringSync('x');
    await original.setLastModified(modified);
    photo = ThumbnailItem('p', original.uri);
  });
  tearDown(() => dir.delete(recursive: true));

  // A thumbnail as a file manager writes it.
  Uint8List thumbnail(String size, {String? uri, String? mtime}) {
    final png = img.encodePng(
      img.Image(width: 8, height: 6)
        ..textData = {
          'Thumb::URI': uri ?? photo.uri.toString(),
          'Thumb::MTime': mtime ?? seconds,
          'Software': 'a file manager',
        },
    );
    final name = md5.convert(utf8.encode(photo.uri.toString()));
    File('${dir.path}/thumbnails/$size/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
    return png;
  }

  Future<Uint8List?> read(int tier, [ThumbnailItem? item]) async =>
      (await freedesktopThumbnails(dir.path)(
        item ?? photo,
        tier,
        never,
      ))?.bytes;

  test('reads the smallest thumbnail of the tier or larger', () async {
    expect(photo.uri.toString(), endsWith('/my%20photo.jpg'));
    final large = thumbnail('large');
    final xLarge = thumbnail('x-large');
    expect(await read(128), large);
    expect(await read(256), large);
    expect(await read(512), xLarge);
    expect(await read(1024), isNull, reason: 'none so large');
  });

  test('ignores a thumbnail of an older file, or of another', () async {
    thumbnail('normal', mtime: '${int.parse(seconds) - 1}');
    expect(await read(128), isNull);
    thumbnail('normal', uri: 'file:///elsewhere.jpg');
    expect(await read(128), isNull);
    expect(
      await read(128, ThumbnailItem('x', Uri.parse('content://m/1'))),
      isNull,
    );
    expect(
      await read(128, ThumbnailItem('x', Uri.file('${dir.path}/gone.jpg'))),
      isNull,
    );
  });

  test('a thumbnail cut short is no thumbnail', () async {
    final png = thumbnail('normal');
    final name = md5.convert(utf8.encode('${photo.uri}'));
    File('${dir.path}/thumbnails/normal/$name.png').writeAsBytesSync(
      png.sublist(0, latin1.decode(png).indexOf('Thumb::MTime') + 14),
    );
    expect(await read(128), isNull);
  });

  test("a damaged thumbnail's text reads without fail: cut anywhere, it says "
      'only what it said; with any byte changed, it still reads', () {
    final png = thumbnail('normal');
    final text = pngText(png);
    expect(text['Thumb::MTime'], seconds);
    Map<String, String> parse(Uint8List damaged, String how) {
      try {
        return pngText(damaged);
      } on Object catch (e) {
        fail('$how: $e');
      }
    }

    for (var end = 0; end < png.length; end++) {
      expect({...text, ...parse(png.sublist(0, end), 'cut at $end')}, text);
    }
    for (var at = 0; at < png.length; at++) {
      for (var byte = 0; byte < 256; byte++) {
        parse(Uint8List.fromList(png)..[at] = byte, '$byte at $at');
      }
    }
    final random = Random(56);
    for (var i = 0; i < 1000; i++) {
      final end = random.nextInt(png.length) + 1;
      final at = random.nextInt(end);
      final byte = random.nextInt(256);
      parse(png.sublist(0, end)..[at] = byte, 'cut at $end, $byte at $at');
    }
    // 300 decodes outlast 30 s on a loaded machine, and then the tear-down
    // deleted the directory under the running loop.
  }, timeout: const Timeout.factor(4));
}
