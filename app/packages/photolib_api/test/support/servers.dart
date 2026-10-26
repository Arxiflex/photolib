import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_api/testing.dart' show envelope;

/// A request the server saw.
typedef Seen = ({String method, String path, HttpHeaders headers, int length});

/// photolibd behind a reverse proxy that terminates TLS with a certificate from a private CA and, by default,
/// requires a client certificate. The upstream answers GetServerInfo in binary Connect, media with byte ranges and
/// one resumable upload, `upload/1`, as photolibd does (server/crates/photolib-server/tests/uploads.rs); the proxy has
/// the limits the app must live with: a request cap (Cloudflare's 100 MB), an upstream timeout (60 s) and HTML error
/// pages.
class ProxiedServer {
  ProxiedServer._(this._http, this._scheme, this.mtls);
  final HttpServer _http;
  final String _scheme;
  final bool mtls;

  /// Without a `context` it serves plain HTTP, for browsers, which own TLS.
  static Future<ProxiedServer> start(
    SecurityContext? context, {
    bool mtls = true,
  }) async {
    final loopback = InternetAddress.loopbackIPv4;
    final http = context == null
        ? await HttpServer.bind(loopback, 0)
        : await HttpServer.bindSecure(
            loopback,
            0,
            context,
            requestClientCertificate: mtls,
          );
    final scheme = context == null ? 'http' : 'https';
    return ProxiedServer._(http, scheme, context != null && mtls)..listen();
  }

  static final media = List.generate(1000, (i) => i % 251);

  String epoch = 'instance-a';
  String minClientVersion = '';

  /// The proxy's request cap and upstream timeout.
  int cap = 100 * 1000 * 1000;
  Duration timeout = const Duration(seconds: 60);

  /// How long the upstream takes to answer; past [timeout] the proxy answers with its 504 page instead.
  Duration delay = Duration.zero;

  /// When set, the answer to every request instead of the upstream's.
  void Function(HttpResponse)? answer;

  /// The answers to requests for these paths instead of the upstream's.
  final answers = <String, void Function(HttpResponse)>{};

  /// Whether answers allow any origin, as a browser on another origin needs.
  bool cors = false;

  /// The session AuthService takes; null takes none.
  String? session;

  /// How far the server's clock, which every answer's `date` carries, is off.
  Duration clock = Duration.zero;

  final seen = <Seen>[];

  /// The upload's bytes, and its length once created.
  final uploaded = BytesBuilder(copy: false);
  int? uploadLength;

  /// Where the network goes away during an append, in order: the request that reaches the offset keeps the bytes
  /// before it and gets no answer, its connection dropped, or left open when `hangs`, which [onHang] hears.
  final losses = <({int at, bool hangs})>[];
  void Function()? onHang;

  Uri get url => Uri.parse('$_scheme://localhost:${_http.port}/');

  void listen() => _http.listen((request) async {
    final response = request.response;
    response.headers.date = DateTime.now().add(clock);
    if (cors) {
      response.headers
        ..set('access-control-allow-origin', '*')
        ..set('access-control-allow-headers', '*')
        ..set('access-control-allow-methods', '*');
      response.headers.set(
        'access-control-expose-headers',
        'location, upload-offset, upload-complete',
      );
      if (request.method == 'OPTIONS') return response.close();
    }
    final body = (await request.fold(
      BytesBuilder(copy: false),
      (all, chunk) => all..add(chunk),
    )).takeBytes();
    seen.add((
      method: request.method,
      path: request.uri.path,
      headers: request.headers,
      length: body.length,
    ));
    // nginx with `ssl_verify_client on` completes the handshake without a certificate and answers 400.
    if (mtls && request.certificate == null) {
      page(400)(response);
    } else if (body.length > cap) {
      page(413)(response);
    } else if (_lost(request, body)) {
      return;
    } else if (answer ?? answers[request.uri.path] case final answer?) {
      answer(response);
    } else if (delay > timeout) {
      await Future<void>.delayed(timeout);
      page(504)(response);
    } else {
      await Future<void>.delayed(delay);
      _upstream(request, body);
    }
    await response.close();
  });

  /// Whether `request` is an append that the network loses next; it keeps what arrived before the loss.
  bool _lost(HttpRequest request, Uint8List body) {
    final offset = int.tryParse(request.headers.value('upload-offset') ?? '');
    if (request.method != 'PATCH' ||
        losses.isEmpty ||
        offset == null ||
        offset != uploaded.length)
      return false;
    final loss = losses.first;
    if (loss.at < offset || loss.at >= offset + body.length) return false;
    losses.removeAt(0);
    uploaded.add(body.sublist(0, loss.at - offset));
    if (loss.hangs) {
      onHang?.call();
    } else {
      unawaited(
        request.response
            .detachSocket(writeHeaders: false)
            .then((socket) => socket.destroy()),
      );
    }
    return true;
  }

  void _upstream(HttpRequest request, List<int> body) {
    final response = request.response;
    final path = request.uri.path;
    if (path == '/photolib.api.v1.ServerInfoService/GetServerInfo') {
      response.headers.contentType = ContentType('application', 'proto');
      response.add(
        (GetServerInfoResponse()
              ..apiVersion = '1.0'
              ..minClientVersion = minClientVersion
              ..epoch = epoch
              ..capabilities.add('sync.hints.v1'))
            .writeToBuffer(),
      );
    } else if (path == '/photolib.api.v1.AuthService/ListDevices') {
      final bearer = request.headers.value('authorization');
      if (session == null || bearer != 'Bearer $session') {
        return connectError(401, 'unauthenticated', reason: 'session.required')(
          response,
        );
      }
      response.headers.contentType = ContentType('application', 'proto');
      response.add(ListDevicesResponse().writeToBuffer());
    } else if (path == '/healthz' && request.method == 'POST') {
      response.statusCode = 204;
    } else if (path.startsWith('/media/')) {
      response.headers
        ..contentType = ContentType('video', 'mp4')
        ..set('accept-ranges', 'bytes')
        ..set('etag', '"m1"');
      if (request.headers.value('if-none-match') == '"m1"') {
        response.statusCode = HttpStatus.notModified;
        return;
      }
      final range = RegExp(r'^bytes=(\d+)-(\d+)$')
          .firstMatch(request.headers.value('range') ?? '');
      if (range == null) return response.add(media);
      final (from, to) = (int.parse(range[1]!), int.parse(range[2]!));
      response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $from-$to/${media.length}')
        ..add(media.sublist(from, to + 1));
    } else if (path == '/upload' && request.method == 'POST') {
      uploadLength = int.parse(request.headers.value('upload-length')!);
      uploaded.clear();
      response
        ..statusCode = 201
        ..headers.set('location', 'upload/1')
        ..headers.set('upload-complete', '?0')
        ..headers.set('upload-offset', '0');
    } else if (path == '/upload/1' && uploadLength == null) {
      response.statusCode = 404;
    } else if (path == '/upload/1' && request.method == 'HEAD') {
      response
        ..statusCode = 204
        ..headers.set('upload-offset', '${uploaded.length}')
        ..headers.set(
          'upload-complete',
          uploaded.length == uploadLength ? '?1' : '?0',
        );
    } else if (path == '/upload/1' && request.method == 'PATCH') {
      final offset = int.parse(request.headers.value('upload-offset')!);
      if (offset != uploaded.length) {
        response.headers
          ..set('upload-offset', '${uploaded.length}')
          ..set('upload-complete', '?0');
        return connectError(409, 'aborted', reason: 'upload.offset_mismatch')(
          response,
        );
      }
      uploaded.add(body);
      final complete = request.headers.value('upload-complete') == '?1';
      response
        ..statusCode = complete ? 200 : 204
        ..headers.set('upload-complete', complete ? '?1' : '?0');
      if (complete) response.write('{"uploadId": "1"}');
    } else if (path == '/upload/1' && request.method == 'DELETE') {
      uploadLength = null;
      uploaded.clear();
      response.statusCode = 204;
    } else {
      response.statusCode = 404;
    }
  }

  Future<void> close() => _http.close(force: true);
}

/// A redirect, such as forward-auth SSO sends to its login page.
void Function(HttpResponse) redirect(Uri to) =>
    (response) => response
      ..statusCode = HttpStatus.found
      ..headers.set('location', '$to');

/// A reverse proxy's HTML error page.
void Function(HttpResponse) page(int status) =>
    (response) => response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write(
        '<html><head><title>$status</title></head><body><center><h1>$status</h1></center><hr>nginx</body></html>',
      );

/// photolibd's Connect error: a code and, when `reason` is given, a `photolib.api.v1.ErrorDetail`.
void Function(HttpResponse) connectError(
  int status,
  String code, {
  String? reason,
  Map<String, String> params = const {},
}) => (response) {
  final detail = ErrorDetail(code: reason, params: params.entries);
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode({
        'code': code,
        if (reason != null)
          'details': [
            {
              'type': 'photolib.api.v1.ErrorDetail',
              'value': base64Encode(detail.writeToBuffer()).replaceAll('=', ''),
            },
          ],
      }),
    );
};

/// A Sync answer of one message compressed, as photolibd gzips one of 1 KiB
/// and more for a client that accepts it.
void Function(HttpResponse) gzipped(List<int> compressed) =>
    (response) => response
      ..headers.contentType = ContentType('application', 'connect+proto')
      ..headers.set('connect-content-encoding', 'gzip')
      ..add(envelope(1, compressed))
      ..add(envelope(2, utf8.encode('{}')));

/// An HTTP proxy that tunnels CONNECT requests, as a corporate or VPN proxy does, and records their targets.
class TunnelProxy {
  TunnelProxy._(this._socket);
  final ServerSocket _socket;
  final targets = <String>[];

  static Future<TunnelProxy> start() async {
    final proxy = TunnelProxy._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    proxy._socket.listen(proxy._tunnel);
    return proxy;
  }

  void _tunnel(Socket client) {
    final head = <int>[];
    late final StreamSubscription<List<int>> subscription;
    subscription = client.listen((data) async {
      head.addAll(data);
      if (!latin1.decode(head).contains('\r\n\r\n')) return;
      subscription.pause();
      final target = latin1.decode(head).split(' ')[1];
      targets.add(target);
      final uri = Uri.parse('http://$target');
      final upstream = await Socket.connect(uri.host, uri.port);
      client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
      upstream.listen(
        client.add,
        onDone: client.destroy,
        onError: (_) => client.destroy(),
      );
      subscription
        ..onData(upstream.add)
        ..onDone(upstream.destroy)
        ..resume();
    });
  }

  String get address => '127.0.0.1:${_socket.port}';

  Future<void> close() => _socket.close();
}
