part of 'playback_probe.dart';

bool _has(Map<String, dynamic> r, String quirk) =>
    (r['quirks'] as List).contains(quirk);

/// The corpus file itself when it decodes, else its twin, in [dir].
Future<File> _twin(Map<String, dynamic> r, Directory dir) async {
  final file = File('$_corpus/files/${r['path']}');
  if (!'${r['notes'] ?? ''}'.startsWith('Placeholder')) return file;
  final m = r['metadata'] as Map<String, dynamic>;
  final (w, h, codec) = (m['width'] as int, m['height'] as int, m['codec']);
  final (muxer, ext, audio) = switch (r['media']['mime']) {
    'video/mp4' => ('mp4', 'mp4', 'aac'),
    'video/quicktime' => ('mov', 'mov', 'aac'),
    'video/mp2t' => ('mpegts', 'mts', 'ac3'),
    'video/webm' => ('webm', 'webm', 'libopus'),
    'video/x-matroska' => ('matroska', 'mkv', 'ac3'),
    'video/x-msvideo' => ('avi', 'avi', 'pcm_s16le'),
    'video/mpeg' => ('vob', 'mpg', 'mp2'),
    'video/x-flv' => ('flv', 'flv', 'libmp3lame'),
    'video/3gpp' => ('3gp', '3gp', 'aac'),
    'video/x-ms-wmv' => ('asf', 'wmv', 'wmav2'),
    final other => throw StateError('${r['path']}: no twin for $other'),
  };
  final encoder = switch (codec) {
    'h264' => '-c:v libopenh264 -b:v 4M',
    'hevc' => '-c:v libkvazaar -kvazaar-params preset=ultrafast -tag:v hvc1',
    'av1' => '-c:v libsvtav1 -preset 12',
    'vp8' => '-c:v libvpx -deadline realtime -b:v 1M',
    'vp9' => '-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 1M',
    'mpeg2' => '-c:v mpeg2video -b:v 6M -flags +ildct+ilme -top 1',
    'dv' => '-c:v dvvideo -pix_fmt yuv420p',
    'xvid' => '-c:v mpeg4 -vtag XVID',
    'flv1' => '-c:v flv',
    'h263' => '-c:v h263',
    'wmv' => '-c:v wmv2',
    'prores' => '-c:v prores_ks',
    final other => throw StateError('${r['path']}: no encoder for $other'),
  };
  final rate = codec == 'dv' || codec == 'mpeg2'
      ? 25
      : _has(r, 'slow_motion') || _has(r, 'slow_motion_sef')
      ? 120
      : w * h > 1920 * 1088
      ? 10
      : 30;
  // Kvazaar encodes multiples of 8; HEVC's conformance window crops the rest.
  final hevc = codec == 'hevc';
  int coded(int n) => hevc ? (n + 7) ~/ 8 * 8 : n;
  final encoded = '${dir.path}/encoded.$ext';
  final twin = File('${dir.path}/twin.$ext');
  await _run([
    ...['-f', 'lavfi', '-i', 'testsrc2=s=${coded(w)}x${coded(h)}:r=$rate:d=2'],
    ...['-f', 'lavfi', '-i', 'sine=r=48000:d=2'],
    ...encoder.split(' '),
    ...['-c:a', audio, '-ac', '2', '-shortest', '-f', muxer],
    if (muxer == 'mp4' || muxer == 'mov') ...['-movflags', '+faststart'],
    encoded,
  ]);
  final rotated = m['orientation'] == 6;
  if (!hevc && !rotated) {
    File(encoded).renameSync(twin.path);
  } else {
    final transfer = _has(r, 'hdr_hlg') || _has(r, 'dolby_vision')
        ? 18
        : _has(r, 'hdr_pq')
        ? 16
        : null;
    final hdr = transfer == null
        ? ''
        : ':transfer_characteristics=$transfer:colour_primaries=9'
              ':matrix_coefficients=9';
    final crop = 'crop_right=${coded(w) - w}:crop_bottom=${coded(h) - h}';
    await _run([
      if (rotated) ...['-display_rotation', '-90'],
      ...['-i', encoded, '-map', '0', '-c', 'copy'],
      if (hevc) ...['-bsf:v', 'hevc_metadata=$crop$hdr'],
      twin.path,
    ]);
  }
  if (_has(r, 'truncated_file')) {
    final bytes = twin.readAsBytesSync();
    twin.writeAsBytesSync(bytes.sublist(0, bytes.length * 3 ~/ 5));
  }
  return twin;
}

/// The video of a twin of motion photo [r]: the photo with a decodable H.264
/// clip of 1280 × 960 where its own is, as the corpus makes them
/// (tools/corpus/catalog_compound.py), read by the viewer's [motionClipProvider]
/// from where extraction found it.
Future<File> _motion(Map<String, dynamic> r, Directory dir) async {
  final clip = '${dir.path}/clip.mp4';
  await _run([
    ...['-f', 'lavfi', '-i', 'testsrc2=s=1280x960:r=30:d=1.5'],
    ...['-c:v', 'libopenh264', '-b:v', '4M', '-movflags', '+faststart', clip],
  ]);
  final motion = r['metadata']['motion'] as Map<String, dynamic>;
  final (offset, length) = (motion['offset'] as int, motion['length'] as int);
  final original = File('$_corpus/files/${r['path']}').readAsBytesSync();
  final video = File(clip).readAsBytesSync();
  final photo = File('${dir.path}/photo')
    ..writeAsBytesSync([
      ...original.sublist(0, offset),
      ...video,
      ...original.sublist(offset + length),
    ]);
  final item = ThumbnailItem('${r['path']}'.replaceAll('/', '-'), photo.uri);
  final container = ProviderContainer(
    overrides: [
      cacheDirectoryProvider.overrideWith((_) => dir),
      assetRowProvider(item).overrideWith(
        (_) => Stream.value(
          LocalAssetData(
            id: Uint8List(16),
            source: 'folder',
            volume: dir.path,
            sourceId: '1',
            size: photo.lengthSync(),
            mtime: 0,
            state: 'present',
            favorite: 0,
            trashed: 0,
            edited: 0,
            folder: 0,
            hidden: 0,
            archived: 0,
            tile: 0,
            motionOffset: offset,
            motionLength: video.length,
          ),
        ),
      ),
    ],
  );
  final listening = container.listen(motionClipProvider(item), (_, _) {});
  try {
    final clip = await container.read(motionClipProvider(item).future);
    return clip!;
  } finally {
    listening.close();
    container.dispose();
  }
}
