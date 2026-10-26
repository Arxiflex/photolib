import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:photolib_api/src/stack_io.dart'
    if (dart.library.js_interop) 'package:photolib_api/src/stack_web.dart'
    show addresses, gunzip;
import 'package:photolib_log/photolib_log.dart';
import 'package:protobuf/protobuf.dart';

import 'gen/photolib/api/v1/error.pb.dart';
import 'gen/photolib/api/v1/server_info.pb.dart';
import 'gen/photolib/api/v1/sync.pb.dart';
import 'network.dart';

/// A call that failed. Only a [ServerError] that [logsOut] ends the session; anything that is not photolibd's own
/// answer is [Unreachable] and makes the app work offline (design 10 §9).
sealed class CallError implements Exception {
  /// True only for an explicit revocation: `unauthenticated` with a reason code.
  bool get logsOut => false;
}

/// photolibd's answer: a Connect code, and the reason and parameters the app renders in its user's language.
final class ServerError extends CallError {
  ServerError(this.code, this.detail);

  /// The Connect code, such as `not_found`.
  final String code;
  final ErrorDetail? detail;

  @override
  bool get logsOut => code == 'unauthenticated' && detail != null;

  @override
  String toString() => 'ServerError($code, ${detail?.code})';
}

/// No answer from photolibd: a timeout, a TLS failure, a refused connection, or a page from something in between,
/// such as a reverse proxy's 502 or 504 or a captive portal.
final class Unreachable extends CallError {
  Unreachable(this.cause);
  final Object cause;

  @override
  String toString() => 'Unreachable($cause)';
}

/// A call with the session to plain HTTP beyond the local networks, which
/// is sent nowhere: the server needs HTTPS there (ADR-0125).
final class HttpsRequired extends Unreachable {
  /// A call to [url].
  new(Uri url) : super('$url needs HTTPS for the session');
}

/// The largest upload append: well under a proxy's request cap (Cloudflare's 100 MB), and sent within a 60 s proxy
/// timeout from 1.2 Mbit/s up (design 16 §2). A proxy's 413 halves it, down to 64 KiB.
const appendBytes = 8 << 20;
const _minAppendBytes = 64 << 10;

/// The most a sync message may hold, or a compressed one inflate to, far more
/// than a batch of photolibd's: more is an attack on the app's memory.
const int _maxMessage = 64 << 20;

/// The most an event of hints may hold, far more than 1,000 stream names.
const int _maxEvent = 1 << 20;

/// The iteration of the resumable upload draft (-13) that photolibd speaks (ADR-0061).
const _interop = {'upload-draft-interop-version': '10'};

final _connectCodes =
    ('canceled unknown invalid_argument deadline_exceeded not_found already_exists permission_denied '
            'resource_exhausted failed_precondition aborted out_of_range unimplemented internal unavailable '
            'data_loss unauthenticated')
        .split(' ')
        .toSet();

const _upload = Logger('photolib.upload');

/// One server: the API ([rpc], for the generated `…ServiceApi` classes), media and uploads, all through one client
/// built from [config].
class Server {
  Server(this.config, {this.instance})
    : client = httpClient(config),
      endpoint = _base(config.endpoints.first);

  final NetworkConfig config;

  /// The instance the endpoints must report in their GetServerInfo epoch, `<instance id>.<restores>` (ADR-0091); null
  /// accepts the first that answers, for the app to pin.
  final String? instance;
  final http.Client client;

  /// The endpoint in use, chosen by [selectEndpoint].
  Uri endpoint;

  late final RpcClient rpc = _Connect(this);

  static Uri _base(Uri url) =>
      url.path.endsWith('/') ? url : url.replace(path: '${url.path}/');

  /// Probes every endpoint with GetServerInfo and switches to the first that answers as [instance], so the app uses
  /// the fastest way in and never talks to another machine on a foreign LAN (MOB-16), with a session the first it
  /// may go to, else [HttpsRequired]. Call it when the network changes.
  Future<GetServerInfoResponse> selectEndpoint() {
    final chosen = Completer<GetServerInfoResponse>();
    final failures = <Object>[];
    for (final base in config.endpoints.map(_base)) {
      _unary(
            base,
            'ServerInfoService',
            'GetServerInfo',
            GetServerInfoRequest(),
            GetServerInfoResponse(),
            signed: false,
          )
          .then((info) async {
            if (instance != null && info.epoch.split('.').first != instance)
              throw Unreachable('$base is instance ${info.epoch}');
            if (!await _mayCarry(base)) throw HttpsRequired(base);
            if (chosen.isCompleted) return;
            endpoint = base;
            const Logger('photolib.network')
                .info('endpoint chosen', fields: {'endpoint': '$base'});
            chosen.complete(info);
          })
          .catchError((Object error) {
            failures.add(error);
            if (failures.length == config.endpoints.length) {
              chosen.completeError(
                failures.whereType<HttpsRequired>().firstOrNull ??
                    Unreachable(failures),
              );
            }
          });
    }
    return chosen.future;
  }

  /// A URL that plays the media at [path] without the session, for the hour
  /// photolibd gives it: a browser's `<video>` cannot send the bearer token
  /// (`POST media/<asset>/<role>`, design 08 §4.5).
  Future<Uri> sign(String path) => _guard(() async {
    final response = await _send(http.Request('POST', _url(path)));
    if (response.statusCode != 200) return await _fail(response);
    final body = jsonDecode(await response.stream.bytesToString());
    final signed = body is Map<String, Object?> ? body['url'] : null;
    if (signed is! String) throw const FormatException('no URL signed');
    final url = Uri.parse(signed);
    return _url(url.path.substring(1)).replace(query: url.query);
  });

  /// Fetches media — a thumbnail, a preview, video bytes — from [endpoint]; `headers` may ask for a byte range or
  /// revalidate a cached copy (304).
  Future<http.StreamedResponse> get(
    String path, {
    Map<String, String> headers = const {},
  }) => _guard(() async {
    final response = await _send(
      http.Request('GET', _url(path))..headers.addAll(headers),
    );
    final html =
        response.headers['content-type']?.startsWith('text/html') ?? false;
    final answered =
        response.statusCode ~/ 100 == 2 || response.statusCode == 304;
    if (answered && !html) return response;
    // photolibd's answer for media it lacks, or does not show to this session.
    if (response.statusCode == 404 && response.contentLength == 0) {
      throw ServerError('not_found', null);
    }
    return _fail(response);
  });

  /// The file [file] of the model [model] (`id@revision`) that devices
  /// run, from byte [offset] on (design 09 §12.2); null when the server has
  /// not installed it.
  Future<http.StreamedResponse?> modelFile(
    String model,
    String file,
    int offset,
  ) => _guard(() async {
    final response = await _send(
      http.Request(
        'GET',
        _url(
          'models/${Uri.encodeComponent(model)}/${Uri.encodeComponent(file)}',
        ),
      )..headers['range'] = 'bytes=$offset-',
    );
    if (response.statusCode != 404) {
      return response.statusCode ~/ 100 == 2 ? response : await _fail(response);
    }
    await response.stream.drain<void>();
    return null;
  });

  /// Creates an upload of [length] bytes whose BLAKE3 hash is [blake3]
  /// (lowercase hex) into [library], or without one into the account's upload
  /// destination, which photolibd makes at the first (IETF resumable uploads,
  /// ADR-0061, ADR-0226), from [path] below its source's root ("/"-separated),
  /// which ingest reads the file's name and folder from (ADR-0066). Returns its
  /// path for [sendUpload], which the app keeps to resume after a restart.
  /// [ml] hands off the vector the device's model (`id@revision`) computed
  /// of the file on its runtime (`rt_flags`), as the half floats [halfFloats]
  /// makes, which the server keeps for the library's active model (design 09
  /// §3.2).
  Future<String> createUpload(
    String? library,
    int length,
    String blake3, {
    String? path,
    ({String model, String runtime, Uint8List vector})? ml,
  }) => _guard(() async {
    final response = await _send(
      http.Request('POST', _url('upload'))
        ..headers.addAll({
          ..._interop,
          'upload-complete': '?0',
          'upload-length': '$length',
          'photolib-library': ?library,
          'photolib-hash': blake3,
          if (path != null)
            'photolib-path': path.split('/').map(Uri.encodeComponent).join('/'),
          if (ml != null) ...{
            'photolib-ml-model': ml.model,
            'photolib-ml-runtime': ml.runtime,
            'photolib-ml-vector': base64.encode(ml.vector),
          },
        }),
    );
    final location = response.headers['location'];
    if (response.statusCode != 201 || location == null) return _fail(response);
    await response.stream.drain<void>();
    final url = '${_url('upload').resolve(location)}';
    if (!url.startsWith('$endpoint')) throw Unreachable('an upload at $url');
    _upload.info(
      'upload created',
      fields: {'upload': location, 'bytes': length, 'file': ?path},
    );
    return url.substring('$endpoint'.length);
  });

  /// Sends what the server lacks of the upload at [path]: asks for its offset,
  /// then appends what `read(offset)` streams from there in requests of at most
  /// [appendBytes]. A broken connection, one that hangs for [appendTimeout], a
  /// proxy's error page or a conflict resumes from the server's offset, up to
  /// [attempts] times in a row without that offset moving, which the part of a
  /// failed append the server kept moves too (a slow uplink); a proxy's 413
  /// halves the appends. Completes once the server has verified and stored all
  /// [length] bytes.
  Future<void> sendUpload(
    String path,
    int length,
    Stream<List<int>> Function(int offset) read, {
    int attempts = 5,
    Duration backoff = const Duration(seconds: 1),
    Duration appendTimeout = const Duration(minutes: 2),
  }) async {
    var (size, failures, offset) = (appendBytes, 0, 0);
    final took = Stopwatch()..start();
    void complete() => _upload.info(
      'upload complete',
      fields: {'upload': path, 'bytes': length, 'ms': took.elapsedMilliseconds},
    );
    while (true) {
      try {
        final start = await _uploadOffset(path);
        if (start == null) return complete();
        if (start > offset) failures = 0;
        offset = start;
        _upload.debug(
          'upload resumed',
          fields: {'upload': path, 'offset': offset, 'of': length},
        );
        await for (final chunk in _appends(
          read(offset),
          size,
          length - offset,
        )) {
          final last = offset + chunk.length == length;
          final response = await _append(
            path,
            offset,
            last,
            chunk,
            appendTimeout,
          );
          if (response.statusCode == 413 && chunk.length > _minAppendBytes) {
            await response.stream.drain<void>();
            size = chunk.length ~/ 2;
            _upload.info(
              'appends halved after a 413',
              fields: {'upload': path, 'bytes': size},
            );
            break;
          }
          if (response.statusCode ~/ 100 != 2) await _fail(response);
          await response.stream.drain<void>();
          _upload.debug(
            'appended',
            fields: {'upload': path, 'offset': offset, 'bytes': chunk.length},
          );
          if (last) return complete();
          (offset, failures) = (offset + chunk.length, 0);
        }
      } on CallError catch (error) {
        if (!_resumable(error) || ++failures >= attempts) {
          _upload.warning(
            'upload failed',
            fields: {'upload': path, 'attempts': failures},
            error: error,
          );
          rethrow;
        }
        _upload.warning(
          'upload interrupted',
          fields: {'upload': path, 'attempt': failures},
          error: error,
        );
        await Future<void>.delayed(backoff * failures);
      }
    }
  }

  /// Stops the upload at [path] for good; the server forgets its bytes.
  Future<void> cancelUpload(String path) => _guard(() async {
    _upload.info('upload cancelled', fields: {'upload': path});
    final response = await _send(
      http.Request('DELETE', _url(path))..headers.addAll(_interop),
    );
    if (response.statusCode ~/ 100 != 2) await _fail(response);
    await response.stream.drain<void>();
  });

  /// The offset of the upload at [path], null once it is complete.
  Future<int?> _uploadOffset(String path) => _guard(() async {
    final response = await _send(
      http.Request('HEAD', _url(path))..headers.addAll(_interop),
    );
    // A HEAD answer has no body to carry photolibd's error.
    if (response.statusCode == 404) throw ServerError('not_found', null);
    if (response.statusCode ~/ 100 != 2) return _fail(response);
    await response.stream.drain<void>();
    if (response.headers['upload-complete'] == '?1') return null;
    return int.parse(response.headers['upload-offset'] ?? '');
  });

  Future<http.StreamedResponse> _append(
    String path,
    int offset,
    bool last,
    Uint8List chunk,
    Duration timeout,
  ) => _guard(() async {
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    try {
      return await client.send(
        await _signed(
          http.AbortableRequest('PATCH', _url(path), abortTrigger: abort.future)
            ..headers.addAll({
              ..._interop,
              'content-type': 'application/partial-upload',
              'upload-offset': '$offset',
              'upload-complete': last ? '?1' : '?0',
            })
            ..bodyBytes = chunk,
        ),
      );
    } finally {
      timer.cancel();
    }
  });

  /// The `SyncResponse`s that SyncService.Sync sends for [request], encoded,
  /// for the caller to read as it likes: Connect server streaming (ADR-0091),
  /// gzipped where photolibd chooses to. Any failure, a stream that stops
  /// before photolibd ends it included, is a [CallError].
  Stream<Uint8List> sync(SyncRequest request) async* {
    final message = request.writeToBuffer();
    final response = await _guard(() async {
      final response = await _send(
        http.Request(
            'POST',
            endpoint.resolve('photolib.api.v1.SyncService/Sync'),
          )
          ..headers.addAll({
            'content-type': 'application/connect+proto',
            'connect-protocol-version': '1',
            'connect-accept-encoding': 'gzip',
          })
          ..bodyBytes = (Uint8List(5 + message.length)
            ..buffer.asByteData().setUint32(1, message.length)
            ..setRange(5, 5 + message.length, message)),
      );
      final type = response.headers['content-type'];
      if (response.statusCode != 200 || type != 'application/connect+proto')
        return _fail(response);
      return response;
    });
    try {
      await for (final (flags, bytes) in _envelopes(
        response.stream.timeout(config.timeout),
      )) {
        // Flag 1: compressed, in the one encoding accepted.
        final data = flags & 1 == 0 ? bytes : await gunzip(bytes, _maxMessage);
        if (flags & 2 != 0) {
          final end = jsonDecode(utf8.decode(data));
          if (end case {'error': {'code': final String code} && final error}
              when _connectCodes.contains(code)) {
            throw ServerError(code, _detail(error['details']));
          }
          if (end case {'error': _}) throw Unreachable('an unknown error');
          return;
        }
        if (flags > 1) throw Unreachable('a message flagged $flags');
        yield data;
      }
    } on CallError {
      rethrow;
    } on Exception catch (error) {
      throw Unreachable(error);
    }
    throw Unreachable('the stream ended before photolibd ended it');
  }

  /// The hints photolibd sends a device that follows [streams] (`GET
  /// /events`, design 05 §9), on the endpoint [selectEndpoint] chooses for
  /// each channel: the names of streams that may have advanced, first those
  /// the account may read, then each time a change advanced some; never what
  /// changed. Ends when photolibd ends the channel; a channel silent for
  /// [NetworkConfig.timeout], past its 15 s keep-alives, or an event over
  /// 1 MiB is [Unreachable], and a server without `sync.hints.v1` an
  /// [UnsupportedError].
  Stream<List<String>> hints(Iterable<String> streams) {
    final response = _guard(() async {
      final info = await selectEndpoint();
      if (!info.capabilities.contains('sync.hints.v1')) {
        throw UnsupportedError('the server has no sync.hints.v1');
      }
      final url = _url('events')
          .replace(queryParameters: {'streams': streams.join(',')});
      final response = await _send(http.Request('GET', url));
      final type = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 || !type.startsWith('text/event-stream')) {
        await _fail(response);
      }
      return response;
    });
    // Combinators, not a generator, so that a cancel closes the channel at
    // once rather than at its next event.
    return Stream.fromFuture(response)
        .asyncExpand((r) => _events(r.stream.timeout(config.timeout)))
        .handleError(
          (Object error) => throw Unreachable(error),
          test: (error) => error is Exception && error is! CallError,
        );
  }

  void close() => client.close();

  /// `path` on [endpoint]; never another origin, which would get this server's headers and client identity.
  Uri _url(String path) {
    final url = endpoint.resolve(path);
    if (url.origin != endpoint.origin)
      throw ArgumentError.value(path, 'path', 'leaves ${endpoint.origin}');
    return url;
  }

  Future<T> _unary<T extends GeneratedMessage>(
    Uri base,
    String service,
    String method,
    GeneratedMessage request,
    T response, {
    bool signed = true,
  }) => _guard(() async {
    final message = request.info_.qualifiedMessageName;
    final package = message.substring(0, message.lastIndexOf('.'));
    final answer = await _send(
      http.Request('POST', base.resolve('$package.$service/$method'))
        ..headers.addAll({
          'content-type': 'application/proto',
          'connect-protocol-version': '1',
        })
        ..bodyBytes = request.writeToBuffer(),
      signed: signed,
    );
    if (answer.statusCode != 200 ||
        answer.headers['content-type'] != 'application/proto')
      return _fail(answer);
    return response..mergeFromBuffer(await answer.stream.toBytes());
  });

  Future<http.StreamedResponse> _send(
    http.BaseRequest request, {
    bool signed = true,
  }) => (signed ? _signed(request) : Future.value(request))
      .then(client.send)
      .timeout(config.timeout);

  Future<http.BaseRequest> _signed(http.BaseRequest request) async {
    if (config.session case final token?) {
      if (!await _mayCarry(request.url)) throw HttpsRequired(request.url);
      request.headers['authorization'] = 'Bearer $token';
    }
    return request;
  }

  /// Whether the session may go to [url]: over HTTPS, or over plain HTTP to
  /// a host whose every address photolibd counts as local, as a bearer
  /// sniffed beyond them is the whole session until it is revoked
  /// (ADR-0125). Judged at every call: on another network a name may resolve
  /// elsewhere.
  Future<bool> _mayCarry(Uri url) async {
    if (config.session == null || url.scheme == 'https') return true;
    final resolved = await addresses(url.host);
    return resolved.isNotEmpty && resolved.every(_local);
  }
}

/// Runs a call and turns every failure on the way — sockets, TLS, timeouts, a body cut short — into [Unreachable].
Future<T> _guard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on CallError {
    rethrow;
  } on Exception catch (error) {
    throw Unreachable(error);
  }
}

/// What a response that is not a success means, inside [_guard]: photolibd's Connect error, or [Unreachable].
Future<Never> _fail(http.StreamedResponse response) async {
  final type = response.headers['content-type'] ?? '';
  final body = await response.stream.toBytes();
  // Malformed JSON throws a FormatException, which _guard makes Unreachable.
  final json = type.startsWith('application/json')
      ? jsonDecode(utf8.decode(body))
      : null;
  if (json case {'code': final String code} when _connectCodes.contains(code)) {
    throw ServerError(code, _detail(json['details']));
  }
  throw Unreachable('HTTP ${response.statusCode} $type');
}

ErrorDetail? _detail(Object? details) {
  for (final detail in details is List ? details : const []) {
    if (detail case {
      'type': 'photolib.api.v1.ErrorDetail',
      'value': final String value,
    }) {
      return ErrorDetail.fromBuffer(base64.decode(base64.normalize(value)));
    }
  }
  return null;
}

/// Whether an upload goes on after `error`: the network, a proxy, a conflict or a passing server failure.
bool _resumable(CallError error) =>
    (error is Unreachable && error is! HttpsRequired) ||
    (error is ServerError &&
        const {'aborted', 'unavailable', 'internal'}.contains(error.code));

/// What photolibd counts as local (`proxy::local`): IPv4 loopback, private
/// and link-local, IPv6 loopback, unique-local and link-local, and an
/// IPv4-mapped IPv6 address as its IPv4 one.
bool _local(List<int> address) => switch (address) {
  [127, _, _, _] ||
  [10, _, _, _] ||
  [192, 168, _, _] ||
  [169, 254, _, _] => true,
  [172, final b, _, _] => b >= 16 && b < 32,
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, ...final v4] => _local(v4),
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] => true,
  [final a, final b, ...] when address.length == 16 =>
    a & 0xfe == 0xfc || (a == 0xfe && b & 0xc0 == 0x80),
  _ => false,
};

/// The first `length` bytes of `data` in chunks of `size`; at least one, which is empty when `length` is 0.
Stream<Uint8List> _appends(
  Stream<List<int>> data,
  int size,
  int length,
) async* {
  final chunk = BytesBuilder(copy: false);
  if (length > 0) {
    await for (final bytes in data) {
      for (var at = 0; at < bytes.length && length > 0;) {
        final take = min(min(size - chunk.length, bytes.length - at), length);
        chunk.add(bytes.sublist(at, at + take));
        (at, length) = (at + take, length - take);
        if (chunk.length == size || length == 0) yield chunk.takeBytes();
      }
      if (length == 0) return;
    }
    throw ArgumentError.value(length, 'length', 'bytes missing from the data');
  }
  yield Uint8List(0);
}

/// The messages of a Connect stream: each a flags byte, its length in four bytes, big-endian, and its bytes; a
/// FormatException at a length over [_maxMessage], before its bytes.
Stream<(int, Uint8List)> _envelopes(Stream<List<int>> body) async* {
  final header = Uint8List(5);
  final message = BytesBuilder(copy: false);
  var (headed, length) = (0, -1);
  await for (final chunk in body) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    for (var at = 0; at < bytes.length;) {
      if (length < 0) {
        header[headed++] = bytes[at++];
        if (headed < 5) continue;
        length = ByteData.sublistView(header).getUint32(1);
        if (length > _maxMessage) {
          throw FormatException('a message of $length bytes');
        }
      }
      final take = min(length - message.length, bytes.length - at);
      message.add(Uint8List.sublistView(bytes, at, at += take));
      if (message.length < length) continue;
      // Copies a message only when it spans chunks.
      yield (header[0], message.takeBytes());
      (headed, length) = (0, -1);
    }
  }
}

/// The stream names of each event of Server-Sent Events [body], its `data`
/// lines; a FormatException once an event holds over [_maxEvent] characters.
Stream<List<String>> _events(Stream<List<int>> body) {
  var (pending, names, data) = ('', <String>[], false);
  final events = StreamTransformer<String, List<String>>.fromHandlers(
    handleData: (text, sink) {
      final lines = '$pending$text'.split('\n');
      pending = lines.removeLast();
      for (var line in lines) {
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        if (line.isEmpty) {
          if (data) sink.add(names);
          (names, data) = (<String>[], false);
        } else if (line == 'data' || line.startsWith('data:')) {
          final value = line.length > 5 ? line.substring(5) : '';
          final name = value.startsWith(' ') ? value.substring(1) : value;
          if (name.isNotEmpty) names.add(name);
          data = true;
        }
      }
      if (names.fold(pending.length, (n, name) => n + name.length) >
          _maxEvent) {
        sink.addError(const FormatException('an event over 1 MiB'));
      }
    },
  );
  return body.transform(utf8.decoder).transform(events);
}

class _Connect implements RpcClient {
  _Connect(this._server);
  final Server _server;

  @override
  Future<T> invoke<T extends GeneratedMessage>(
    ClientContext? ctx,
    String serviceName,
    String methodName,
    GeneratedMessage request,
    T emptyResponse,
  ) => _server._unary(
    _server.endpoint,
    serviceName,
    methodName,
    request,
    emptyResponse,
  );
}

/// [values] as IEEE 754 binary16, little-endian, rounded to nearest even:
/// the precision of vectors on devices and the server.
Uint8List halfFloats(Float32List values) {
  final out = ByteData(values.length * 2);
  final bits = ByteData(4);
  for (final (i, v) in values.indexed) {
    final f = (bits..setFloat32(0, v)).getUint32(0);
    final sign = (f >> 16) & 0x8000;
    final exponent = ((f >> 23) & 0xff) - 112;
    var mantissa = f & 0x7fffff;
    int half;
    if (exponent == 143) {
      half = 0x7c00 | (mantissa == 0 ? 0 : 0x200); // infinity, NaN
    } else if (exponent >= 31) {
      half = 0x7c00; // too large: infinity
    } else {
      // A subnormal keeps fewer bits of the mantissa, with its implicit 1.
      final shift = exponent > 0 ? 13 : 14 - exponent;
      if (exponent <= 0) mantissa |= 0x800000;
      if (shift > 24) {
        half = 0;
      } else {
        half = (exponent > 0 ? exponent << 10 : 0) | mantissa >> shift;
        final rest = mantissa & ((1 << shift) - 1);
        final middle = 1 << (shift - 1);
        if (rest > middle || rest == middle && half.isOdd) half++;
      }
    }
    out.setUint16(i * 2, sign | half, Endian.little);
  }
  return out.buffer.asUint8List();
}
