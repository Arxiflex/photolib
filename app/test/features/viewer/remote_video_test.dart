import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib_data/photolib_data.dart' show uuidv7;
import 'package:video_player/video_player.dart' show VideoFormat;

import '../../support/fake_server.dart';

/// A browser's proxy, which holds none of the video.
Future<Uri> _kept(ThumbnailItem item) async =>
    throw UnsupportedError('a browser plays kept videos');

void main() {
  test('a server video plays from the signed URL of its H.264 proxy', () async {
    final server = FakeServer();
    final id = Uint8List.fromList(uuidv7());
    final item = ThumbnailItem.remote(id, video: true);
    final player = await videoOf(item, null, server: _kept, link: server);
    expect(player.dataSource, startsWith('https://photos.example.org/media/'));
    expect(player.dataSource, contains('video_proxy_720?t='));
    expect(server.signed.single, endsWith('/video_proxy_720'));
  });

  test(
    'on Safari, whose HLS is dependable, a server video streams its ladder',
    () async {
      final server = FakeServer();
      final item = ThumbnailItem.remote(
        Uint8List.fromList(uuidv7()),
        video: true,
      );
      final player = await videoOf(
        item,
        null,
        server: _kept,
        link: server,
        adaptive: true,
      );
      expect(player.dataSource, contains('/hls?t='));
      expect(player.formatHint, VideoFormat.hls);
      expect(server.signed.single, endsWith('/hls'));
    },
  );

  test('a server video the browser keeps plays from the kept bytes', () async {
    final item = ThumbnailItem.remote(
      Uint8List.fromList(uuidv7()),
      video: true,
    );
    final player = await videoOf(
      item,
      null,
      server: (_) async => Uri.parse('blob:https://photos.example.org/kept'),
    );
    expect(player.dataSource, 'blob:https://photos.example.org/kept');
  });

  test('a server video without a session cannot play', () async {
    final item = ThumbnailItem.remote(
      Uint8List.fromList(uuidv7()),
      video: true,
    );
    await expectLater(videoOf(item, null, server: _kept), throwsStateError);
  });
}
