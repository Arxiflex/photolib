import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pipeline.dart';
import 'thumbnails.dart';

/// Poster frames of videos on Linux (docs/10-client-app.md §3.4, ADR-0107):
/// the first frame through the `ffmpeg` on [path] (`$PATH`), upright and with
/// its short side at the tier, as JPEG; null without one. FFmpeg reads only
/// the file (`-protocol_whitelist file,pipe`), and a cancelled request kills
/// it.
Future<Thumbnailer?> ffmpegPosters({String? path}) async {
  final dirs = (path ?? Platform.environment['PATH'] ?? '').split(':');
  final found = [
    for (final dir in dirs)
      if (await File('$dir/ffmpeg').exists()) '$dir/ffmpeg',
  ];
  if (found.isEmpty) return null;
  final ffmpeg = found.first;
  return Thumbnailer('ffmpeg', (item, tier, cancelled) async {
    if (!item.video || !item.uri.isScheme('file')) return null;
    final process = await Process.start(ffmpeg, [
      ...'-nostdin -v error -threads 1 -protocol_whitelist file,pipe -i'.split(
        ' ',
      ),
      item.uri.toFilePath(),
      ...['-frames:v', '1', '-vf'],
      "scale=w='if(lt(iw,ih),min(iw,$tier),-2)':"
          "h='if(lt(iw,ih),-2,min(ih,$tier))'",
      ...'-f image2pipe -c:v mjpeg -q:v 4 -'.split(' '),
    ]);
    unawaited(cancelled.then((_) => process.kill()));
    final (out, err) = (
      process.stdout.fold(BytesBuilder(copy: false), (b, d) => b..add(d)),
      process.stderr.transform(const SystemEncoding().decoder).join(),
    );
    final jpeg = (await out).takeBytes();
    if (await process.exitCode != 0 || jpeg.isEmpty) {
      throw NoThumbnail(video: true, cause: (await err).trim());
    }
    return Pixels.encoded(jpeg);
  });
}
