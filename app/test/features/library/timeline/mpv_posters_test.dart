@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolib/features/library/timeline/mpv_posters.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';

void main() {
  late Directory dir;
  late String ffmpeg;
  final never = Completer<void>().future;

  setUpAll(() async {
    final found = await Process.run('bash', ['../tools/video/ffmpeg.sh']);
    expect(found.exitCode, 0, reason: '${found.stderr}');
    ffmpeg = '${(found.stdout as String).trim()}/ffmpeg';
  });
  setUp(() async => dir = await Directory.systemTemp.createTemp('mpv'));
  tearDown(() => dir.delete(recursive: true));

  // A one-second 320 × 240 clip, turned to portrait by its display matrix
  // when [rotate].
  Future<ThumbnailItem> clip(String name, {bool rotate = false}) async {
    final path = '${dir.path}/$name';
    for (final args in [
      '-f lavfi -i testsrc=size=320x240:rate=5 -t 1 -c:v mpeg4 $path',
      if (rotate) '-display_rotation 90 -i $path -c copy $path.mov',
    ]) {
      final made = await Process.run(ffmpeg, [
        ...'-v error -y $args'.split(' '),
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
    }
    return ThumbnailItem(
      name,
      Uri.file(rotate ? '$path.mov' : path),
      video: true,
    );
  }

  test('libmpv gives a video its first frame, upright, at the tier', () async {
    final posters = (await mpvPosters())!;
    final poster = img.decodeJpg(
      (await posters(await clip('a.mp4'), 128, never))!.bytes,
    )!;
    expect((poster.width, poster.height), (170, 128));
    final upright = img.decodeJpg(
      (await posters(await clip('b.mp4', rotate: true), 128, never))!.bytes,
    )!;
    expect((upright.width, upright.height), (128, 170));
    final whole = img.decodeJpg(
      (await posters(await clip('c.mp4'), 1024, never))!.bytes,
    )!;
    expect((whole.width, whole.height), (320, 240), reason: 'never larger');
  });

  test('a stream libmpv cannot read is a video without a poster; a photo is '
      'not its kind', () async {
    final posters = (await mpvPosters())!;
    final broken = File('${dir.path}/broken.mov')..writeAsStringSync('moov');
    await expectLater(
      posters(ThumbnailItem('x', broken.uri, video: true), 128, never),
      throwsA(
        isA<NoThumbnail>()
            .having((e) => e.video, 'video', true)
            .having((e) => e.cause, 'cause', 'unrecognized file format'),
      ),
    );
    expect(await posters(ThumbnailItem('p', broken.uri), 128, never), isNull);
  });

  test('without libmpv there are no posters', () async {
    expect(await mpvPosters(library: 'libnompv.so'), isNull);
  });
}
