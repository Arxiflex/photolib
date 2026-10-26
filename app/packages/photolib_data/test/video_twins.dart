// The VM side of web_test.dart's posters: decodable twins of corpus videos, whose files only hold their structure
// (testdata/corpus/README.md), made as the server's video test makes them, with the pinned FFmpeg
// (tools/video/ffmpeg.sh), at a fifth of their size, where the test server serves this package from; and a clip that
// fades in from black. Suites running at once share them: each set is made once, then moved into place.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel, Object? paths) async {
  final made = sha256.convert([
    ...utf8.encode('$paths'),
    ...await File('test/video_twins.dart').readAsBytes(),
  ]);
  final out = '.dart_tool/web_test/videos-${'$made'.substring(0, 16)}';
  final found = await Process.run('bash', ['../../../tools/video/ffmpeg.sh']);
  if (found.exitCode != 0) throw StateError('ffmpeg.sh: ${found.stderr}');
  final ffmpeg = '${(found.stdout as String).trim()}/ffmpeg';
  final temp = await Directory('.dart_tool/web_test').createTemp('making-');
  Future<void> run(String args, String file) async {
    if (await File('$out/$file').exists()) return;
    final made = await Process.run(ffmpeg, [
      ...'-v error -y $args'.split(' '),
      '${temp.path}/$file',
    ]);
    if (made.exitCode != 0) throw StateError('$file: ${made.stderr}');
  }

  final twins = <String, Object?>{};
  for (final (i, path) in (paths! as List).cast<String>().indexed) {
    final record =
        jsonDecode(
              await File(
                '../../../testdata/corpus/golden/$path.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final meta = record['metadata'] as Map<String, dynamic>;
    final (width, height) = (meta['width'] as int, meta['height'] as int);
    final (muxer, audio) = switch (record['media']['mime']) {
      'video/mp4' => ('mp4', 'aac'),
      'video/quicktime' => ('mov', 'aac'),
      'video/webm' => ('webm', 'libopus'),
      final mime => throw StateError('$path: no twin for $mime'),
    };
    final codec = switch (meta['codec']) {
      'h264' => '-c:v libopenh264',
      'hevc' => '-c:v libkvazaar -tag:v hvc1',
      'vp9' => '-c:v libvpx-vp9 -deadline realtime -cpu-used 8',
      'prores' => '-c:v prores_ks',
      final codec => throw StateError('$path: no encoder for $codec'),
    };
    final seconds = (meta['duration_ms'] as int) / 1000;
    final file = '$i.$muxer';
    await run(
      '-f lavfi -i testsrc2=s=${width ~/ 5}x${height ~/ 5}:r=30:d=$seconds -f lavfi -i sine=r=48000:d=$seconds '
      '$codec -c:a $audio -ac 2 -shortest -f $muxer',
      file,
    );
    twins[path] = {
      'file': '$out/$file',
      'type': record['media']['mime'],
      ...meta,
    };
  }
  await run(
    '-f lavfi -i color=c=black:s=320x180:r=30:d=1,format=yuv420p[black];'
        'testsrc2=s=320x180:r=30:d=2,format=yuv420p[picture];[black][picture]concat=n=2 -c:v libopenh264 -f mp4',
    'fade.mp4',
  );
  twins['fade'] = {
    'file': '$out/fade.mp4',
    'type': 'video/mp4',
    'width': 320,
    'height': 180,
    'duration_ms': 3000,
  };
  try {
    await temp.rename(out);
  } on FileSystemException {
    await temp.delete(recursive: true); // made by another suite
  }
  channel.sink.add(twins);
}
