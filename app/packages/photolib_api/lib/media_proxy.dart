/// The loopback media proxy, for native targets only.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'src/server.dart';

/// Opens a run of an end-to-end encrypted object's chunks, as the kernel's DecryptBlob does with `first_chunk`
/// and `more`: its header, the index of the first chunk, the sealed chunks and whether more follow them. Null when
/// they fail to authenticate.
typedef OpenChunks = Uint8List? Function(
  Uint8List header,
  int first,
  Uint8List chunks,
  bool more,
);

/// A loopback HTTP server for players that cannot use the app's network stack (libmpv, AVPlayer with a private CA or
/// a client certificate, ExoPlayer): they read [url] on 127.0.0.1 behind an unguessable token, and the proxy fetches
/// it through [Server.get] with the server's network configuration, byte ranges included (design 10 §9).
class MediaProxy {
  MediaProxy._(this._http, this._prefix);
  final HttpServer _http;
  final String _prefix;
  final _sessions = <String, _Session>{};

  /// The proxy fetches whole windows (or chunks, if larger), so the server never learns where a range starts (design
  /// 08 §6.4).
  static const _window = 1 << 20;

  static const _forwarded = [
    'range',
    'if-range',
    'if-none-match',
    'if-modified-since',
  ];
  static const _returned = [
    'content-type',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
    'cache-control',
  ];

  static Future<MediaProxy> start(Server server) async {
    final proxy = MediaProxy._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      '/${_token()}/',
    );
    // A player that hangs up mid-stream is no error of the app's.
    proxy._http.listen((request) => proxy._serve(server, request).ignore());
    return proxy;
  }

  /// The URL a player reads `path` of the server's media from.
  Uri url(String path) =>
      Uri.parse('http://127.0.0.1:${_http.port}$_prefix$path');

  /// The URL a player reads the plaintext of the encrypted object at `path` from, a session behind a token of its own:
  /// each byte range asked for is answered from the aligned 1 MiB windows it covers, fetched whole and opened by
  /// [open].
  Uri decrypted(String path, String type, OpenChunks open) {
    final token = _token();
    _sessions['/$token'] = _Session(path, type, open);
    return Uri.parse('http://127.0.0.1:${_http.port}/$token');
  }

  static String _token() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<void> _serve(Server server, HttpRequest request) async {
    final response = request.response;
    final target = request.uri.toString();
    final session = _sessions[target];
    try {
      if (request.headers.host != '127.0.0.1') {
        // A page that rebinds its own name to 127.0.0.1 still sends that name (DNS rebinding).
        response.statusCode = HttpStatus.forbidden;
      } else if (session == null && !target.startsWith(_prefix)) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else if (session != null) {
        await _decrypt(server, session, request);
      } else {
        final media = await server.get(
          target.substring(_prefix.length),
          headers: {
            for (final name in _forwarded)
              if (request.headers.value(name) case final value?) name: value,
          },
        );
        response.statusCode = media.statusCode;
        for (final name in _returned) {
          if (media.headers[name] case final value?) {
            response.headers.set(name, value);
          }
        }
        if (media.contentLength case final length?) {
          response.contentLength = length;
        }
        await response.addStream(media.stream);
      }
    } on CallError {
      response.statusCode = HttpStatus.badGateway;
    } on FormatException {
      response.statusCode = HttpStatus.badGateway;
    } on ArgumentError {
      response.statusCode = HttpStatus.badRequest;
    } finally {
      await response.close();
    }
  }

  Future<void> _decrypt(
    Server server,
    _Session session,
    HttpRequest request,
  ) async {
    final (header, total) = session.head ??= await _head(server, session);
    final chunk = 1 << header[6], sealed = chunk + 16;
    final chunks = (total - 88 + sealed - 1) ~/ sealed;
    final size = total - 88 - 16 * chunks;
    final range = RegExp(r'^bytes=(\d+)-(\d*)$')
        .firstMatch(request.headers.value('range') ?? 'bytes=0-');
    final start = int.parse(range?[1] ?? '$size');
    final response = request.response..headers.contentType = session.type;
    if (start >= size) {
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set('content-range', 'bytes */$size');
      return;
    }
    final span = max(_window, chunk);
    // A closed range (an HLS segment) is answered whole; an open one (a progressive player reading on) stops at the
    // end of its window and the player asks again, so a seek never waits behind decrypted bytes it will drop.
    final to = int.tryParse(range![2]!);
    final end = min(size, to == null ? (start ~/ span + 1) * span : to + 1);
    Future<Uint8List?> open(int window) async {
      final first = window * span ~/ chunk;
      final last = (min(window * span + span, size) - 1) ~/ chunk;
      final ciphertext = await server.get(
        session.path,
        headers: {
          'range':
              'bytes=${88 + first * sealed}-${min(88 + (last + 1) * sealed, total) - 1}',
        },
      );
      final bytes = await ciphertext.stream.toBytes();
      return session.open(header, first, bytes, last < chunks - 1);
    }

    final first = start ~/ span;
    final plaintext = await open(first);
    if (plaintext == null) {
      response.statusCode = HttpStatus.badGateway;
      return;
    }
    response
      ..statusCode = HttpStatus.partialContent
      ..headers.set('accept-ranges', 'bytes')
      ..headers.set('content-range', 'bytes $start-${end - 1}/$size')
      ..contentLength = end - start;
    // The next window is fetched only once the player has taken this one. One that fails to open ends the response
    // short of its length, which players see as an error.
    Stream<Uint8List> windows(int window, Uint8List? bytes) async* {
      for (; bytes != null; bytes = await open(++window)) {
        final base = window * span;
        yield Uint8List.sublistView(
          bytes,
          max(start, base) - base,
          min(end, base + span) - base,
        );
        if (base + span >= end) return;
      }
    }

    await response.addStream(windows(first, plaintext));
  }

  /// The object's header and its whole length. Its chunk size is checked here, as the proxy computes offsets with it
  /// before the kernel opens anything.
  static Future<(Uint8List, int)> _head(Server server, _Session session) async {
    final response = await server.get(
      session.path,
      headers: {'range': 'bytes=0-87'},
    );
    final header = await response.stream.toBytes();
    final total = response.headers['content-range']?.split('/').last;
    if (header.length != 88 || header[6] < 16 || header[6] > 22) {
      throw const FormatException('not an envelope');
    }
    return (header, int.parse(total ?? ''));
  }

  Future<void> close() => _http.close(force: true);
}

class _Session {
  _Session(this.path, String type, this.open) : type = ContentType.parse(type);
  final String path;
  final ContentType type;
  final OpenChunks open;
  (Uint8List, int)? head;
}
