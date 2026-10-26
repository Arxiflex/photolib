import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';

const _pano = '../testdata/corpus/files/compound/pano';

/// An image of [w] × [h] whose pixel at x, y is [rgba] of them.
Future<ui.Image> pixels(int w, int h, int Function(int x, int y) rgba) {
  final bytes = ByteData(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bytes.setUint32((y * w + x) * 4, rgba(x, y));
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes.buffer.asUint8List(),
    w,
    h,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

Future<ui.Image> decode(String path, {int? width}) async {
  final codec = await ui.instantiateImageCodec(
    File(path).readAsBytesSync(),
    targetWidth: width,
  );
  return (await codec.getNextFrame()).image;
}

/// RGBA bytes of what [view] shows of [sphere] in [image] on [size].
Future<Uint8List> render(
  ui.FragmentProgram program,
  ui.Image image,
  Sphere sphere,
  SphereView view, [
  Size size = const Size(160, 120),
]) async {
  final recorder = ui.PictureRecorder();
  final shader = program.fragmentShader();
  SpherePainter(shader, image, sphere, view).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final shown = await picture.toImage(size.width.toInt(), size.height.toInt());
  final bytes = await shown.toByteData();
  shown.dispose();
  picture.dispose();
  shader.dispose();
  return bytes!.buffer.asUint8List();
}

/// RGBA bytes of what SphereFilter shows of [image], a player's frame, on
/// [size]: the frame's cells in view in their slots, as SphereFilter lays out
/// its view, then the shader over that.
Future<Uint8List> filtered(
  ui.FragmentProgram program,
  ui.Image image,
  Sphere sphere,
  SphereView view,
  Size size,
) async {
  final frame = Size(image.width.toDouble(), image.height.toDouble());
  final packing = SpherePacking.of(sphere, view, size, frame);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (part, slot) in packing.regions(sphere.eye)) {
    final (w, h) = (slot.width * size.width, slot.height * size.height);
    final at = Offset(slot.left * size.width, slot.top * size.height);
    canvas
      ..save()
      ..clipRect(at & Size(w, h))
      ..drawImageRect(
        image,
        Offset.zero & frame,
        Rect.fromLTWH(
          at.dx - part.left * w / part.width,
          at.dy - part.top * h / part.height,
          w / part.width,
          h / part.height,
        ),
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }
  final (w, h) = (size.width.toInt(), size.height.toInt());
  final held = await recorder.endRecording().toImage(w, h);
  final cells = packing.cells();
  final shader = program.fragmentShader();
  sphereUniforms(
    shader,
    sphere,
    view,
    size,
    image.width,
    image.height,
    0,
    packing,
  );
  shader
    ..setImageSampler(0, held, filterQuality: FilterQuality.low)
    ..setImageSampler(1, cells);
  final drawn = ui.PictureRecorder();
  Canvas(drawn).drawRect(Offset.zero & size, Paint()..shader = shader);
  final shown = await drawn.endRecording().toImage(w, h);
  final rgba = (await shown.toByteData())!.buffer.asUint8List();
  shader.dispose();
  cells.dispose();
  return rgba;
}

/// Noise four texels across, as fine as a 2048 × 1024 frame holds it
/// smoothly.
Future<ui.Image> smoothNoise() async {
  var seed = 1;
  final noise = await pixels(512, 256, (x, y) {
    seed = seed * 1103515245 + 12345 & 0x7fffffff;
    return seed << 8 | 0xff;
  });
  return await scaled(noise, 2048, 1024);
}

/// [image] drawn at [w] × [h], the part [from] of it if given.
Future<ui.Image> scaled(ui.Image image, int w, int h, [Rect? from]) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    from ?? Rect.fromLTWH(0, 0, image.width * 1.0, image.height * 1.0),
    Rect.fromLTWH(0, 0, w * 1.0, h * 1.0),
    Paint()..filterQuality = FilterQuality.low,
  );
  return recorder.endRecording().toImage(w, h);
}

/// The mean absolute difference of the RGB channels of two RGBA frames.
double difference(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    if (i % 4 != 3) sum += (a[i] - b[i]).abs();
  }
  return sum / (a.length * 3 / 4);
}

int transparent(Uint8List rgba) => [
  for (var i = 3; i < rgba.length; i += 4)
    if (rgba[i] < 255) i,
].length;

double rad(double d) => d * pi / 180;

void main() {
  late ui.FragmentProgram program;
  setUpAll(
    () async =>
        program = await ui.FragmentProgram.fromAsset('shaders/sphere.frag'),
  );

  testWidgets('the shader casts the rays the model does', (tester) async {
    await tester.runAsync(() async {
      // Red is the longitude and green the latitude, east and south growing.
      final gradient = await pixels(
        1024,
        512,
        (x, y) => (x * 256 ~/ 1024) << 24 | (y * 256 ~/ 512) << 16 | 0xff,
      );
      const cylinder = Sphere(cylinder: true);
      for (final (sphere, view) in [
        (const Sphere(), const SphereView()),
        (
          const Sphere(),
          SphereView(yaw: rad(-100), pitch: rad(35), fov: rad(100)),
        ),
        (
          const Sphere(),
          SphereView(yaw: rad(40), pitch: rad(-60), fov: rad(30)),
        ),
        (const Sphere(), const SphereView.planet()),
        (
          const Sphere(),
          SphereView(
            yaw: rad(20),
            pitch: rad(-30),
            fov: rad(150),
            fisheye: true,
          ),
        ),
        (cylinder, SphereView(yaw: rad(70), pitch: rad(10), fov: rad(60))),
        (cylinder, SphereView(yaw: rad(-120), pitch: rad(-15))),
      ]) {
        const size = Size(160, 120);
        final rgba = await render(program, gradient, sphere, view);
        for (final (x, y) in [(80, 60), (5, 7), (150, 110), (40, 90)]) {
          final (lon, lat) = view.ray(
            Offset((x + 0.5 - 80) / 60, (y + 0.5 - 60) / 60),
          );
          final i = (y * size.width.toInt() + x) * 4;
          final u = (lon / (2 * pi) + 0.5) * 256;
          final v = sphere.down(lat) * 256;
          // Off by a texel at most, and where the longitude wraps, by either.
          expect(
            min((rgba[i] - u).abs(), 256 - (rgba[i] - u).abs()),
            lessThan(2.5),
            reason: '$view at $x, $y',
          );
          expect(rgba[i + 1], closeTo(v, 2.5), reason: '$view at $x, $y');
        }
      }
    });
  });

  testWidgets('the corpus spheres show no seam where their sides meet, and '
      'no black: a partial one is clamped to its picture', (tester) async {
    await tester.runAsync(() async {
      final sphere = await decode('$_pano/photosphere.jpg', width: 2048);
      // The same picture turned half way round, its sides in the middle.
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawImage(sphere, const Offset(-1024, 0), Paint())
        ..drawImage(sphere, const Offset(1024, 0), Paint());
      final shifted = await recorder.endRecording().toImage(2048, 1024);
      for (final (pitch, fov) in [
        (0.0, 75.0),
        (50.0, 75.0),
        (-70.0, 75.0),
        (0.0, 2.0),
      ]) {
        // Through 2°, a texel spans ten pixels.
        final view = SphereView(yaw: pi, pitch: rad(pitch), fov: rad(fov));
        final across = await render(program, sphere, const Sphere(), view);
        final whole = await render(
          program,
          shifted,
          const Sphere(),
          view.copyWith(yaw: 0),
        );
        var worst = 0;
        for (var i = 0; i < across.length; i++) {
          worst = max(worst, (across[i] - whole[i]).abs());
        }
        expect(worst, lessThanOrEqualTo(2), reason: 'pitch $pitch');
        expect(transparent(across), 0);
      }

      final cropped = await decode(
        '$_pano/photosphere-cropped.jpg',
        width: 2048,
      );
      const band = Sphere(crop: Rect.fromLTWH(0, 0.25, 1, 0.5));
      const size = Size(160, 120);
      for (final asked in [
        SphereView(pitch: rad(80)),
        SphereView(yaw: rad(170), pitch: rad(-80), fov: rad(120)),
        const SphereView(fov: 3),
      ]) {
        expect(
          transparent(await render(program, cropped, band, asked)),
          greaterThan(0),
          reason: 'the band ends at 45°',
        );
        final view = asked.clamp(band, size);
        expect(transparent(await render(program, cropped, band, view)), 0);
      }
      expect(
        transparent(
          await render(program, cropped, band, const SphereView.planet()),
        ),
        0,
      );
    });
  });

  testWidgets('zooming out picks a filtered level of detail, never an '
      'aliased one', (tester) async {
    await tester.runAsync(() async {
      // Black and white texels, a chequerboard.
      final board = await pixels(
        2048,
        1024,
        (x, y) => (x + y).isEven ? 0x000000ff : 0xffffffff,
      );
      final levels = levelsOf(board);
      expect([for (final l in levels) l.width], [2048, 1024, 512, 256]);
      const size = Size(256, 256);
      final view = SphereView(fov: rad(120));
      final level = view.level(const Sphere(), 256, 2048, levels.length);
      expect(level, 2);
      double spread(Uint8List rgba) {
        final grey = [for (var i = 0; i < rgba.length; i += 4) rgba[i]];
        final mean = grey.reduce((a, b) => a + b) / grey.length;
        return sqrt(
          grey.map((g) => (g - mean) * (g - mean)).reduce((a, b) => a + b) /
              grey.length,
        );
      }

      // The middle of the view, where the level is right.
      Uint8List middle(Uint8List rgba) => Uint8List.fromList([
        for (var y = 96; y < 160; y++)
          ...rgba.sublist((y * 256 + 96) * 4, (y * 256 + 160) * 4),
      ]);
      final filtered = middle(
        await render(program, levels[level], const Sphere(), view, size),
      );
      final aliased = middle(
        await render(program, board, const Sphere(), view, size),
      );
      expect(spread(filtered), lessThan(8));
      expect(spread(aliased), greaterThan(30));
    });
  });

  testWidgets("a player's texture filtered as the viewport's part of the "
      'frame in view shows what the whole frame does, near a pole and on a '
      'cubemap too', (tester) async {
    await tester.runAsync(() async {
      // Holding it at a lower scale than the frame's softens it.
      final frame = await smoothNoise();
      // A cubemap of it, as v360 lays one out.
      final faces = ui.PictureRecorder();
      final canvas = Canvas(faces);
      for (final (face, yaw, pitch) in [
        (0, 90.0, 0.0),
        (1, -90.0, 0.0),
        (2, 0.0, 90.0),
        (3, 0.0, -90.0),
        (4, 0.0, 0.0),
        (5, 180.0, 0.0),
      ]) {
        final shown = await render(
          program,
          frame,
          const Sphere(),
          SphereView(yaw: rad(yaw), pitch: rad(pitch), fov: pi / 2),
          const Size(512, 512),
        );
        final image = await pixels(
          512,
          512,
          (x, y) => ByteData.sublistView(shown).getUint32((y * 512 + x) * 4),
        );
        canvas.drawImage(
          image,
          Offset(face % 3 * 512.0, face ~/ 3 * 512.0),
          Paint(),
        );
      }
      final cube = await faces.endRecording().toImage(1536, 1024);
      const size = Size(640, 480);
      for (final (image, sphere, view) in [
        (frame, const Sphere(), SphereView(yaw: pi, pitch: rad(20))),
        (
          frame,
          const Sphere(eye: Rect.fromLTWH(0, 0, 0.5, 1)),
          SphereView(yaw: pi, fov: rad(40)),
        ),
        (frame, const Sphere(), SphereView(yaw: rad(-60), pitch: rad(-80))),
        (frame, const Sphere(), SphereView(yaw: rad(30), pitch: rad(70))),
        (frame, const Sphere(), SphereView(pitch: rad(89), fov: rad(100))),
        (
          cube,
          const Sphere(cube: true),
          SphereView(yaw: rad(45), pitch: rad(35)),
        ),
        (
          frame,
          const Sphere(crop: Rect.fromLTWH(0.25, 0, 0.5, 1)),
          SphereView(yaw: rad(-30), pitch: rad(60)),
        ),
      ]) {
        final whole = await render(program, image, sphere, view, size);
        final rgba = await filtered(program, image, sphere, view, size);
        // Held whole, the part in view near a pole differed by 11 and the
        // cubemap by 19.
        expect(difference(rgba, whole), lessThan(7), reason: '$view');
      }
    });
  });

  testWidgets("a panorama's tiles in view, over its smaller picture, show what "
      'the original does', (tester) async {
    await tester.runAsync(() async {
      final original = await smoothNoise();
      final picture = await scaled(original, 512, 256);
      const sphere = Sphere();
      const size = Size(320, 240);
      final view = SphereView(yaw: rad(50), pitch: rad(15), fov: rad(30));
      final whole = await render(program, original, sphere, view, size);
      final (sample, tiles) = view.tiles(
        sphere,
        size,
        const Size(2048, 1024),
        512,
      )!;
      expect(sample, 1);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final shaders = [program.fragmentShader()];
      SpherePainter(shaders.last, picture, sphere, view).paint(canvas, size);
      for (final (col, row) in tiles) {
        final part = Rect.fromLTWH(col / 4, row / 2, 0.25, 0.5);
        final tile = await scaled(
          original,
          512,
          512,
          Rect.fromLTWH(col * 512.0, row * 512.0, 512, 512),
        );
        shaders.add(program.fragmentShader());
        SpherePainter(
          shaders.last,
          tile,
          sphere.part(part),
          view,
        ).paint(canvas, size);
      }
      final shown = await recorder.endRecording().toImage(320, 240);
      final rgba = (await shown.toByteData())!.buffer.asUint8List();
      final base = await render(program, picture, sphere, view, size);
      expect(difference(base, whole), greaterThan(4));
      expect(difference(rgba, whole), lessThan(1));
      for (final shader in shaders) {
        shader.dispose();
      }
    });
  });

  testWidgets('a cubemap shows each face of FFmpeg v360 3 × 2 layout where '
      'it looks: right, left, up / down, front, back', (tester) async {
    await tester.runAsync(() async {
      const colours = [
        0xff0000ff,
        0x00ff00ff,
        0x0000ffff,
        0xffff00ff,
        0xff00ffff,
        0x00ffffff,
      ];
      final cube = await pixels(
        600,
        400,
        (x, y) => colours[x ~/ 200 + 3 * (y ~/ 200)],
      );
      for (final (face, yaw, pitch) in [
        (0, 90.0, 0.0),
        (1, -90.0, 0.0),
        (2, 0.0, 80.0),
        (3, 0.0, -80.0),
        (4, 0.0, 0.0),
        (5, 180.0, 0.0),
      ]) {
        final rgba = await render(
          program,
          cube,
          const Sphere(cube: true),
          SphereView(yaw: rad(yaw), pitch: rad(pitch), fov: rad(30)),
        );
        const i = (60 * 160 + 80) * 4;
        expect(
          rgba[i] << 24 | rgba[i + 1] << 16 | rgba[i + 2] << 8 | rgba[i + 3],
          colours[face],
          reason: 'face $face',
        );
      }
    });
  });
}
