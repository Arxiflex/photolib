import 'dart:js_interop';

import 'package:photolib/features/servers/servers.dart' show Link;
import 'package:photolib_data/photolib_data.dart';
import 'package:web/web.dart' as web;

/// What a browser's player reads a pinned video from: an object URL of the
/// bytes the offline store holds, opened in memory when the player asks, as a
/// browser has no loopback server (ADR-0200 D6: nothing of it stays on disk
/// but the store's sealed chunks).
class VideoProxy {
  new _(this._media);

  final OfflineMedia _media;
  final _urls = <String>[];

  /// Starts a proxy of the files [media] holds; a browser plays no other.
  static Future<VideoProxy> start(OfflineMedia media, Link? link) async =>
      VideoProxy._(media);

  /// The URL a player reads `media/<asset>/<role>` from.
  Future<Uri> url(String path) async {
    final file = await _media.open(path);
    final bytes = await file?.read();
    if (bytes == null) throw UnsupportedError('a browser plays kept videos');
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final url = web.URL.createObjectURL(blob);
    _urls.add(url);
    return Uri.parse(url);
  }

  /// Lets the player's URLs go.
  Future<void> close() async {
    // A tear-off of an interop member is refused by the compiler.
    // ignore: prefer_foreach
    for (final url in _urls) {
      web.URL.revokeObjectURL(url);
    }
    _urls.clear();
  }
}
