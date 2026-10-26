import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/viewer/regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String path;
  setUpAll(() {
    // Red on the left, blue on the right.
    final image = img.Image(width: 64, height: 32);
    for (final p in image) {
      p
        ..r = p.x < 32 ? 255 : 0
        ..b = p.x < 32 ? 0 : 255;
    }
    final dir = Directory.systemTemp.createTempSync('regions');
    addTearDown(() => dir.delete(recursive: true));
    path = '${dir.path}/two.png';
    File(path).writeAsBytesSync(img.encodePng(image));
  });

  // The colours of an image's pixels, as 0xRRGGBB.
  Future<Set<int>> colours(ui.Image image) async {
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    return {
      for (var i = 0; i < rgba.length; i += 4)
        rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2],
    };
  }

  test('a file decoded whole per sample size gives its regions', () async {
    final regions = (await CodecRegions.open(path))!;
    addTearDown(regions.close);
    expect(regions.size, const ui.Size(64, 32));
    final right = await regions.decode(
      const ui.Rect.fromLTRB(32, 0, 64, 32),
      1,
    );
    expect([right.width, right.height], [32, 32]);
    expect(await colours(right), {0x0000ff});
    final all = await regions.decode(const ui.Rect.fromLTRB(0, 0, 64, 32), 2);
    expect([all.width, all.height], [32, 16]);
    expect(await colours(all), containsAll([0xff0000, 0x0000ff]));
  });

  test(
    'past its pixel ceiling it gives the finest sample size within it',
    () async {
      final regions = (await CodecRegions.open(path, maxPixels: 512))!;
      addTearDown(regions.close);
      final right = await regions.decode(
        const ui.Rect.fromLTRB(32, 0, 64, 32),
        1,
      );
      expect([right.width, right.height], [16, 16]);
      expect(await colours(right), {0x0000ff});
    },
  );

  test('a file that is no image has no regions', () async {
    File('$path.txt').writeAsStringSync('no image');
    expect(await CodecRegions.open('$path.txt'), isNull);
  });
}
