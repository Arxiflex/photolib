import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/embedded.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ThumbnailItem corpus(String path, {bool video = false}) => ThumbnailItem(
    path,
    Uri.file('${Uri.base.resolve('../testdata/corpus/files/').path}$path'),
    video: video,
  );

  test('reads the JPEG the kernel finds in a file: EXIF IFD1 thumbnail, a '
      "RAW's preview; nothing else", () async {
    final thumbnail = img.decodeJpg(
      (await embeddedPreview(corpus('stills/exif-thumbnail.jpg')))!,
    )!;
    expect((thumbnail.width, thumbnail.height), (160, 120));
    for (final raw in ['raw/nikon.nef', 'raw/fuji.raf', 'raw/canon.cr2']) {
      expect(img.decodeJpg((await embeddedPreview(corpus(raw)))!), isNotNull);
    }
    expect(await embeddedPreview(corpus('stills/baseline.jpg')), isNull);
    expect(await embeddedPreview(corpus('stills/rgb.png')), isNull);
    expect(
      await embeddedPreview(corpus('stills/exif-thumbnail.jpg', video: true)),
      isNull,
    );
  });

  test('a preview turns as its file does: its EXIF holds the orientation of '
      'the file alone, so the stand-in shows upright', () async {
    for (final (path, orientation) in [
      ('raw/nikon.nef', 6),
      ('raw/fuji.raf', 8),
      ('raw/panasonic.rw2', 3),
    ]) {
      final bytes = (await embeddedPreview(corpus(path)))!;
      expect(img.decodeJpgExif(bytes)!.imageIfd.orientation, orientation);
      expect(String.fromCharCodes(bytes), isNot(contains('FUJIFILM')));
      final shown = Completer<ui.Image>();
      final tile = Tile()..show = (image, _) => shown.complete(image);
      unawaited(
        ThumbnailPipeline(
          decoders: [
            Thumbnailer('decoder', (_, _, _) => Completer<Pixels?>().future),
          ],
          embedded: embeddedPreview,
        ).load(corpus(path), 256, tile),
      );
      final image = await shown.future;
      expect(
        (image.width, image.height),
        orientation >= 5 ? (120, 160) : (160, 120),
        reason: path,
      );
    }
  });

  test("a RAW's largest JPEG for the viewer, though past what a first read "
      'reaches, both upright as the RAW is turned, at the tier', () async {
    final dir = await Directory.systemTemp.createTemp('embedded');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/turned.nef')
      ..writeAsBytesSync(
        raw(
          img.encodeJpg(img.Image(width: 16, height: 8)),
          img.encodeJpg(img.Image(width: 640, height: 320)),
          orientation: 6,
        ),
      );
    final item = ThumbnailItem('turned', Uri.file(file.path));
    final pipeline = ThumbnailPipeline(embedded: embeddedPreview);
    final shown = Completer<ui.Image>();
    // It has no decoder: only the stand-in shows.
    pipeline
        .load(item, 256, Tile()..show = (i, _) => shown.complete(i))
        .ignore();
    final small = await shown.future;
    expect((small.width, small.height), (8, 16));
    final large = (await pipeline.preview(item, 256))!;
    expect((large.width, large.height), (256, 512));
    expect(await pipeline.preview(corpus('stills/baseline.jpg'), 256), isNull);
  });

  test('the cell is shown the embedded preview while the original decodes, '
      'and the tile replaces it', () async {
    final decode = Completer<Pixels?>();
    final pipeline = ThumbnailPipeline(
      decoders: [Thumbnailer('decoder', (_, _, _) => decode.future)],
      embedded: embeddedPreview,
    );
    final shown = Completer<(ui.Image, int)>();
    final tile = Tile()..show = (image, tier) => shown.complete((image, tier));
    final load = pipeline.load(corpus('stills/exif-thumbnail.jpg'), 256, tile);
    final (preview, tier) = await shown.future;
    expect((preview.width, preview.height, tier), (160, 120, 0));
    expect(tile.stages['embedded'], lessThan(1000));
    decode.complete(
      Pixels.encoded(img.encodeJpg(img.Image(width: 341, height: 256))),
    );
    expect((await load).width, 341);
  });
}

/// A little-endian TIFF RAW turned to [orientation], its IFD1 pointing to the
/// JPEG [small] and a SubIFD past the first 64 KiB to [large].
Uint8List raw(Uint8List small, Uint8List large, {required int orientation}) {
  const sub = 70000;
  final data = ByteData(sub + 30);
  var at = 0;
  void u16(int v) => (data..setUint16(at, v, Endian.little), at += 2);
  void u32(int v) => (data..setUint32(at, v, Endian.little), at += 4);
  // An IFD of entries (tag, type, value), and where the next IFD is.
  void ifd(List<(int, int, int)> entries, int next) {
    u16(entries.length);
    for (final (tag, type, value) in entries) {
      u16(tag);
      u16(type);
      u32(1);
      if (type == 3) {
        u16(value);
        u16(0);
      } else {
        u32(value);
      }
    }
    u32(next);
  }

  data.setUint32(0, 0x002a4949, Endian.little);
  at = 4;
  u32(8);
  ifd([(0x0112, 3, orientation), (0x014a, 4, sub)], 38);
  ifd([(0x0201, 4, 68), (0x0202, 4, small.length)], 0);
  at = sub;
  ifd([(0x0201, 4, 68 + small.length), (0x0202, 4, large.length)], 0);
  return data.buffer.asUint8List()
    ..setAll(68, small)
    ..setAll(68 + small.length, large);
}
