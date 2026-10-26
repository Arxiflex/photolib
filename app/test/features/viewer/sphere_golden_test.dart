import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';

import '../../support/sphere_goldens.dart';
import '../../support/sphere_twins.dart';

Future<Uint8List> rgba(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();

Future<ui.Image> decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

void main() {
  testWidgets('the shader shows each corpus 360° video at its golden frame '
      'as FFmpeg v360 does', (tester) async {
    await tester.runAsync(() async {
      final program = await ui.FragmentProgram.fromAsset('shaders/sphere.frag');
      final ffmpeg = (await Process.run('bash', [
        '../tools/video/ffmpeg.sh',
      ])).stdout.toString().trim();
      final dir = await Directory.systemTemp.createTemp('sphere-golden-');
      addTearDown(() => dir.delete(recursive: true));
      final twins = await goldenTwins('../testdata/corpus', ffmpeg, dir);
      expect(
        [for (final t in twins) t.path],
        [
          'compound/sphere/cubemap.mp4',
          'compound/sphere/spherical-v1.mp4',
          'compound/sphere/spherical-v2-cropped.mp4',
          'compound/sphere/spherical-v2.mp4',
          'compound/sphere/stereo-left-right.mp4',
          'compound/sphere/stereo-top-bottom.mp4',
        ],
      );
      final differences = <String, double>{};
      for (final t in twins) {
        final frame = File('${t.twin.path}.frame.png');
        await ffmpegRun(ffmpeg, [
          ...['-ss', '${goldenAt.inMilliseconds / 1000}', '-i', t.twin.path],
          ...['-frames:v', '1', '-pix_fmt', 'rgb24', frame.path],
        ]);
        final image = await decode(frame);
        final recorder = ui.PictureRecorder();
        final shader = program.fragmentShader();
        final sphere = sphereOf(cube: t.cube, stereo: t.stereo, crop: t.crop);
        SpherePainter(
          shader,
          image,
          sphere,
          goldenViewOf(sphere),
        ).paint(Canvas(recorder), goldenSize);
        final shown = await recorder.endRecording().toImage(
          goldenSize.width.toInt(),
          goldenSize.height.toInt(),
        );
        differences[t.path] = frameDifference(
          await rgba(shown),
          await rgba(await decode(t.golden)),
        );
      }
      expect(
        differences.values.every((d) => d <= goldenTolerance),
        isTrue,
        reason: '$differences',
      );
      // tools/smoke.sh serves them to targets where FFmpeg does not run.
      if (Platform.environment['SPHERE_TWINS_OUT'] case final out?) {
        String keep(File f) {
          final name = f.uri.pathSegments.last;
          f.copySync('$out/$name');
          return name;
        }

        File('$out/twins.json').writeAsStringSync(
          jsonEncode([
            for (final t in twins)
              {
                'path': t.path,
                'cube': t.cube,
                'stereo': t.stereo,
                'crop': t.crop,
                'twin': keep(t.twin),
                'golden': keep(t.golden),
                'frame': keep(File('${t.twin.path}.frame.png')),
              },
          ]),
        );
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
