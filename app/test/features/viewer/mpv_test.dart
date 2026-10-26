import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/viewer/mpv.dart';

void main() {
  test('players render in software on Windows, whose app ships no ANGLE', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final (platform, hardware) in [
      (TargetPlatform.windows, false),
      (TargetPlatform.linux, true),
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        mpvVideoConfiguration().enableHardwareAcceleration,
        hardware,
        reason: '$platform',
      );
    }
  });

  test('the notices bundled with libmpv are licence entries, one per '
      'library', () async {
    final dir = await Directory.systemTemp.createTemp('notices-');
    addTearDown(() => dir.delete(recursive: true));
    const ffmpeg =
        'FFmpeg: LGPL-2.1-or-later, built from '
        'https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz';
    final file = File('${dir.path}/libmpv-notices.txt')
      ..writeAsStringSync(
        'FFmpeg\n\n$ffmpeg\n\n'
        '  GNU LESSER GENERAL PUBLIC LICENSE\n'
        '${'-' * 80}\n'
        'zlib\n\nzlib: Zlib, built from zlib-1.3.2.tar.xz\n\n'
        '  (C) 1995-2026 Jean-loup Gailly and Mark Adler\n',
      );
    final entries = await bundledNotices(file).toList();
    expect(
      [for (final e in entries) e.packages],
      [
        ['FFmpeg'],
        ['zlib'],
      ],
    );
    expect(
      [for (final p in entries.first.paragraphs) p.text],
      [ffmpeg, 'GNU LESSER GENERAL PUBLIC LICENSE'],
    );
    expect(
      await bundledNotices(File('${dir.path}/missing.txt')).toList(),
      isEmpty,
      reason: 'only Windows bundles them',
    );
  });
}
