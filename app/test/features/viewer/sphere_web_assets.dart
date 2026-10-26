// The VM side of sphere_web_test.dart: the browser test runner bundles no
// shaders, so this compiles the panorama shader for the web as `flutter build
// web` does into assets/ beside the test (git-ignored), which the test server serves; and
// it makes the corpus' 360° twins and their golden frames through the filters
// the browser answers for each kind it asks of (sphere_twins.dart), and sends
// them back as base64.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

import '../../support/sphere_twins.dart';

Future<void> hybridMain(StreamChannel<Object?> channel, Object? _) async {
  final filters = StreamIterator(channel.stream);
  final engine = Directory(
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/engine',
  );
  final impellerc = engine
      .listSync()
      .map((dir) => File('${dir.path}/impellerc'))
      .firstWhere((file) => file.existsSync());
  Directory('test/features/viewer/assets/shaders').createSync(recursive: true);
  final dir = Directory.systemTemp.createTempSync('photolib-spheres-');
  try {
    await _run(impellerc.path, [
      ...[
        '--sksl',
        '--iplr',
        '--json',
        '--sl=test/features/viewer/assets/shaders/sphere.frag',
      ],
      ...['--spirv=${dir.path}/sphere.spirv', '--input=shaders/sphere.frag'],
      ...['--input-type=frag', '--include=shaders'],
      '--include=${impellerc.parent.path}/shader_lib',
    ]);
    final found = await Process.run('bash', ['../tools/video/ffmpeg.sh']);
    final ffmpeg = (found.stdout as String).trim();
    channel.sink.add([
      for (final t in await sphereTwins('../testdata/corpus', ffmpeg, dir, ({
        required cube,
        stereo,
        crop,
      }) async {
        channel.sink.add({'cube': cube, 'stereo': stereo, 'crop': crop});
        await filters.moveNext();
        return filters.current! as String;
      }))
        {
          'path': t.path,
          'cube': t.cube,
          'stereo': t.stereo,
          'crop': t.crop,
          'twin': base64.encode(t.twin.readAsBytesSync()),
          'golden': base64.encode(t.golden.readAsBytesSync()),
        },
    ]);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Future<void> _run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  if (result.exitCode != 0) {
    throw StateError('$command ${arguments.join(' ')}: ${result.stderr}');
  }
}
