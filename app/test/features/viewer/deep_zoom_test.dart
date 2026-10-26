import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';

void main() {
  test('the sample size keeps tiles at least as sharp as the screen', () {
    expect(
      [
        for (final s in <double>[4, 1, 0.6, 0.5, 0.26, 0.25, 0.01])
          sampleFor(s),
      ],
      [1, 1, 1, 2, 2, 4, 64],
    );
  });

  // A phone's 1080 × 2400 pixels.
  const phone = Size(1080 / 2.625, 2400 / 2.625), dpr = 2.625;
  Matrix4 view(double zoom, double x, double y) => Matrix4.identity()
    ..translateByDouble(
      -x * (zoom - 1) * phone.width,
      -y * (zoom - 1) * phone.height,
      0,
      1,
    )
    ..scaleByDouble(zoom, zoom, 1, 1);

  test('no tiles while the screen-size image is sharp', () {
    const image = Size(4000, 3000);
    expect(tilesOnScreen(image, phone, dpr, view(1, 0, 0), 1080).tiles, []);
    expect(
      tilesOnScreen(image, phone, dpr, view(1.5, 0, 0), 1080).tiles,
      isNotEmpty,
    );
  });

  test('tiles are squares of half the short side in device pixels times '
      'the sample, clipped to the image, where the screen shows it', () {
    // 1080 device px show 4000 image px, 0.27 each: at 1.5× sample 2.
    final (:sample, :tiles) = tilesOnScreen(
      const Size(4000, 3000),
      phone,
      dpr,
      view(1.5, 0, 0.5),
      1080,
    );
    expect(sample, 2);
    // 540 tile px are 1080 image px; the screen shows x 0–2667, all of y.
    expect(tiles, [
      for (final y in <double>[0, 1080, 2160])
        for (final x in <double>[0, 1080, 2160])
          Rect.fromLTRB(x, y, x + 1080, min(y + 1080, 3000)),
    ]);
  });

  test('a 200 MP image never needs more than 64 MiB of tiles on a phone, '
      'and reaches full resolution', () {
    const image = Size(16384, 12288);
    var most = 0, finest = 0;
    for (var zoom = 1.0; zoom < 100; zoom *= 1.25) {
      for (final x in <double>[0, 0.3, 0.5, 1]) {
        for (final y in <double>[0, 0.5, 0.7, 1]) {
          final (:sample, :tiles) = tilesOnScreen(
            image,
            phone,
            dpr,
            view(zoom, x, y),
            1080,
          );
          var bytes = 0;
          for (final t in tiles) {
            bytes += (t.width / sample).ceil() * (t.height / sample).ceil() * 4;
          }
          most = max(most, bytes);
          if (tiles.isNotEmpty) finest = sample;
        }
      }
    }
    expect(most, lessThan(64 << 20));
    expect(finest, 1);
  });

  group('DeepZoom', () {
    late _Regions regions;
    late TransformationController controller;
    setUp(() {
      regions = _Regions(const Size(4000, 3000));
      controller = TransformationController();
    });
    tearDown(() => controller.dispose());

    Future<void> pump(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        DeepZoom(
          size: regions.size,
          base: _image(400, 300),
          controller: controller,
          regions: regions,
        ),
      );
    }

    // [zoom]× about the centre of the 400 × 800 view.
    Future<void> zoom(WidgetTester tester, double zoom) async {
      controller.value = Matrix4.identity()
        ..translateByDouble(200 * (1 - zoom), 400 * (1 - zoom), 0, 1)
        ..scaleByDouble(zoom, zoom, 1, 1);
      await tester.pump();
    }

    testWidgets('decodes only the tiles on screen, two at a time, and none '
        'while the screen-size image is sharp', (tester) async {
      await pump(tester);
      expect(regions.calls, isEmpty);
      // At 4×, 0.4 px per image px: sample 2, tiles of 400 image px; the
      // screen shows x 1500–2500 and y 500–2500.
      await zoom(tester, 4);
      expect(regions.pending, 2);
      await regions.finishAll(tester);
      expect(regions.calls, hasLength(4 * 6));
      expect(regions.calls.map((c) => c.$2).toSet(), {2});
      expect(regions.calls.map((c) => c.$1.topLeft).toSet(), {
        for (final y in <double>[400, 800, 1200, 1600, 2000, 2400])
          for (final x in <double>[1200, 1600, 2000, 2400]) Offset(x, y),
      });
      expect(regions.live, 24);
      await zoom(tester, 1);
      expect(regions.live, 0, reason: 'every tile disposed');
    });

    testWidgets('a coarser tile stays until the finer ones over it arrive', (
      tester,
    ) async {
      await pump(tester);
      await zoom(tester, 4);
      await regions.finishAll(tester);
      await zoom(tester, 6);
      expect(regions.pending, 2);
      // The screen shows x 1667–2333 and y 833–2167: 2 × 4 tiles of 400.
      expect(regions.live, 2 * 4, reason: 'nothing finer to show there yet');
      await regions.finishAll(tester);
      expect(regions.calls.last.$2, 1);
      // Only the finer tiles at 6×: x 1667–2333 and y 833–2167 in tiles of
      // 200.
      expect(regions.live, 4 * 7);
    });

    testWidgets('a tile that arrives after it left the screen is dropped', (
      tester,
    ) async {
      await pump(tester);
      await zoom(tester, 4);
      await zoom(tester, 1);
      await regions.finishAll(tester);
      expect(regions.live, 0);
      expect(regions.calls, hasLength(2), reason: 'none started since');
    });
  });
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
  return recorder.endRecording().toImageSync(width, height);
}

/// Decodes regions as grey images when the test says so, and counts those
/// not yet disposed.
class _Regions implements Regions {
  _Regions(this.size);

  @override
  final Size size;
  final calls = <(Rect, int)>[];
  final _waiting = <(Completer<ui.Image>, ui.Image)>[];
  final _given = <ui.Image>[];

  int get pending => _waiting.length;
  int get live => _given.where((i) => !i.debugDisposed).length;

  @override
  Future<ui.Image> decode(Rect region, int sample) {
    calls.add((region, sample));
    final image = _image(
      (region.width / sample).ceil(),
      (region.height / sample).ceil(),
    );
    final done = Completer<ui.Image>();
    _waiting.add((done, image));
    return done.future;
  }

  Future<void> finishAll(WidgetTester tester) async {
    while (_waiting.isNotEmpty) {
      final (done, image) = _waiting.removeAt(0);
      _given.add(image);
      done.complete(image);
      await tester.pump();
    }
  }

  @override
  void close() {}
}
