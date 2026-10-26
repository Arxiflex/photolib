import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'pipeline.dart';

/// The thumbnails Linux file managers keep under [cacheHome]`/thumbnails`
/// (`$XDG_CACHE_HOME`, by the freedesktop.org Thumbnail Managing Standard),
/// read-only (docs/10-client-app.md §8.1): the smallest of the tier or larger
/// that names the file and its modification time.
Thumbnailer freedesktopThumbnails(String cacheHome) =>
    Thumbnailer('freedesktop', (item, tier, _) async {
      if (!item.uri.isScheme('file')) return null;
      final uri = item.uri.toString();
      final name = '${md5.convert(utf8.encode(uri))}.png';
      final FileStat stat;
      try {
        stat = await File.fromUri(item.uri).stat();
      } on FileSystemException {
        return null;
      }
      final mtime = '${stat.modified.millisecondsSinceEpoch ~/ 1000}';
      for (final (size, folder) in const [
        (128, 'normal'),
        (256, 'large'),
        (512, 'x-large'),
        (1024, 'xx-large'),
      ]) {
        if (size < tier) continue;
        try {
          final png = await File('$cacheHome/thumbnails/$folder/$name')
              .readAsBytes();
          final text = pngText(png);
          if (text['Thumb::URI'] == uri && text['Thumb::MTime'] == mtime) {
            return Pixels.encoded(png);
          }
        } on FileSystemException {
          // Not there.
        }
      }
      return null;
    });

/// The tEXt chunks of a PNG, as far as it is whole.
@visibleForTesting
Map<String, String> pngText(Uint8List png) {
  final text = <String, String>{};
  final view = ByteData.sublistView(png);
  for (var at = 8; at + 8 <= png.length;) {
    final end = at + 8 + view.getUint32(at);
    if (end > png.length) break;
    if (String.fromCharCodes(png, at + 4, at + 8) == 'tEXt') {
      final chunk = png.sublist(at + 8, end);
      final nul = chunk.indexOf(0);
      if (nul > 0) {
        text[latin1.decode(chunk.sublist(0, nul))] = latin1.decode(
          chunk.sublist(nul + 1),
        );
      }
    }
    at = end + 4;
  }
  return text;
}
