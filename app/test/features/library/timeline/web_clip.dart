// The VM side of web_test.dart: a two-second 320 × 180 H.264 clip, made with the pinned FFmpeg (tools/video/ffmpeg.sh).
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final found = await Process.run('bash', ['../tools/video/ffmpeg.sh']);
  final dir = await Directory.systemTemp.createTemp('clip');
  final clip = '${dir.path}/clip.mp4';
  final made = await Process.run('${(found.stdout as String).trim()}/ffmpeg', [
    ...'-v error -f lavfi -i testsrc2=s=320x180:r=30:d=2 -c:v libopenh264'
        .split(' '),
    clip,
  ]);
  if (made.exitCode != 0) throw StateError('${found.stderr}${made.stderr}');
  channel.sink.add(base64.encode(await File(clip).readAsBytes()));
  await dir.delete(recursive: true);
}
