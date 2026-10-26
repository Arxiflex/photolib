import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:photolib/core/logging.dart';
import 'package:photolib/features/servers/servers.dart' show Link;
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.offline');

/// How much of a file one read of the offline store returns, a chunk of it.
const int _window = 1 << 20;

/// A loopback HTTP server that gives a player the bytes of a server video in
/// ranges (MOB-15, ADR-0200 P1): from the offline store when this device
/// keeps the file, opening only the chunks a range needs, else from the
/// server's own ranges through the session's [Link]. It listens on 127.0.0.1
/// behind a token no other program knows, and never touches the disk with
/// anything but the store's sealed chunks: a private library's file stays the
/// ciphertext the server sent until the player's decryptor opens it.
class VideoProxy {
  new _(this._http, this._media, this._link, this._token);

  final HttpServer _http;
  final OfflineMedia _media;
  final Link? _link;
  final String _token;

  /// Starts a proxy of the files [media] holds, else of [link]'s.
  static Future<VideoProxy> start(OfflineMedia media, Link? link) async {
    final random = Random.secure();
    final token = [
      for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16),
    ].map((h) => h.padLeft(2, '0')).join();
    final proxy = VideoProxy._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      media,
      link,
      token,
    );
    // A player that hangs up mid-stream is no error of the app's.
    proxy._http.listen((request) => proxy._serve(request).ignore());
    return proxy;
  }

  /// The URL a player reads `media/<asset>/<role>` from.
  Future<Uri> url(String path) async {
    final [_, asset, role] = Uri.parse(path).pathSegments;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _http.port,
      pathSegments: [_token, asset, role],
    );
  }

  /// Stops listening; a request under way ends.
  Future<void> close() => _http.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final parts = request.uri.pathSegments;
      if (parts.length != 3 || parts[0] != _token) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        await _file(request, 'media/${parts[1]}/${parts[2]}');
      }
    } on Object catch (e) {
      _log.debug('video request ended', fields: {'cause': '$e'});
      response.statusCode = HttpStatus.badGateway;
    } finally {
      await response.close().catchError((Object _) => null);
    }
  }

  Future<void> _file(HttpRequest request, String path) async {
    final response = request.response;
    final info = await _media.describe(path);
    if (info == null) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final total = info.size;
    final held = await _media.open(path);
    if (held == null && _link == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final range = _range(request.headers.value(HttpHeaders.rangeHeader), total);
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, info.mime);
    if (range == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      return;
    }
    final (first, last, partial) = range;
    response
      ..statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok
      ..contentLength = last - first + 1;
    if (partial) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $first-$last/$total',
      );
    }
    if (request.method == 'HEAD' || total == 0) return;
    if (held != null) {
      for (var at = first; at <= last; at += _window) {
        final bytes = await held.read(
          start: at,
          end: min(at + _window, last + 1),
        );
        if (bytes == null) {
          // Lost or locked meanwhile: the player sees a cut body.
          await response.detachSocket().then((s) => s.destroy());
          return;
        }
        response.add(bytes);
      }
      return;
    }
    final link = _link ?? (throw StateError('no server to ask'));
    final media = await link.media(
      path,
      headers: {'range': 'bytes=$first-$last'},
    );
    await response.addStream(media.bytes);
  }

  // The first and last byte a `Range` asks for, and whether it asked; null
  // when it cannot be met. Ranges of several parts are served whole.
  static (int, int, bool)? _range(String? header, int total) {
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header ?? '');
    final from = m?.group(1) ?? '';
    final to = m?.group(2) ?? '';
    if (from.isEmpty && to.isEmpty) return (0, max(0, total - 1), false);
    final first = from.isEmpty
        ? max(0, total - int.parse(to))
        : int.parse(from);
    final last = from.isEmpty || to.isEmpty
        ? total - 1
        : min(total - 1, int.parse(to));
    return first > last || first >= total ? null : (first, last, true);
  }
}
