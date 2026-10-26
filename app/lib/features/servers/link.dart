/// How the app reaches its server (ADR-0125): a [Link] over the endpoint
/// that answers as the server's instance.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

/// A server's API as the app uses it: the first call picks the fastest
/// address that answers as its instance (MOB-16), and a call that finds none
/// picks again at the next. Tests fake it.
abstract interface class Link implements RpcClient {
  /// The file at [path] below the server's address, such as
  /// `media/<asset>/original` (ADR-0084), asked for with [headers]: 200, or
  /// 304 to an `If-None-Match`, with its ETag and length when the server says
  /// them.
  Future<Media> media(String path, {Map<String, String> headers});

  /// A URL for the media at [path] that works without the session for an
  /// hour, such as `media/<asset>/video_proxy_720`: what a browser's video
  /// element plays.
  Future<Uri> sign(String path);

  /// Creates a resumable upload of [length] bytes whose BLAKE3 is [blake3]
  /// into the account's upload destination, from [path] (ADR-0061); returns
  /// its path for [sendUpload].
  Future<String> createUpload(int length, String blake3, {String? path});

  /// Sends what the server lacks of the upload at [path], reading the file
  /// from the offset the server has, and completes once it is stored.
  Future<void> sendUpload(
    String path,
    int length,
    Stream<List<int>> Function(int offset) read,
  );

  /// The device joined or left a network: picks the address again at once.
  void networkChanged();

  /// Closes the connections once the calls under way have ended.
  void close();
}

/// A file of the server's media as [Link.media] answers it.
typedef Media = ({
  int status,
  String? etag,
  Stream<List<int>> bytes,
  int? length,
});

/// Opens a [Link] to the server at [config], of any instance when null.
typedef Connect = Link Function(NetworkConfig config, String? instance);

/// How the app opens a [Link].
final connectProvider = Provider<Connect>((ref) => _ServerLink.new);

/// Every change of the device's networks, such as joining or leaving Wi-Fi,
/// which needs no location permission (MOB-16).
final networkChangesProvider = Provider<Stream<Object?>>(
  (ref) => Connectivity().onConnectivityChanged,
);

/// The fingerprint of a certificate this device does not trust
/// ([untrustedCertificate]).
final certificateProvider =
    Provider<Future<String?> Function(NetworkConfig config, Uri url)>(
      (ref) => untrustedCertificate,
    );

class _ServerLink implements Link {
  new(NetworkConfig config, String? instance)
    : _server = Server(config, instance: instance);

  final Server _server;
  Future<GetServerInfoResponse>? _info;
  var _calls = 0;
  var _closed = false;

  @override
  Future<T> invoke<T extends GeneratedMessage>(
    ClientContext? ctx,
    String serviceName,
    String methodName,
    GeneratedMessage request,
    T emptyResponse,
  ) => _call(
    (info) async => methodName == 'GetServerInfo'
        ? (emptyResponse..mergeFromMessage(info))
        : await _server.rpc.invoke(
            ctx,
            serviceName,
            methodName,
            request,
            emptyResponse,
          ),
  );

  @override
  Future<Media> media(String path, {Map<String, String> headers = const {}}) =>
      _call((_) async {
        final response = await _server.get(path, headers: headers);
        return (
          status: response.statusCode,
          etag: response.headers['etag'],
          bytes: response.stream,
          length: response.contentLength,
        );
      });

  Future<T> _call<T>(
    Future<T> Function(GetServerInfoResponse info) call,
  ) async {
    final selecting = _info ??= _server.selectEndpoint();
    _calls++;
    try {
      return await call(await selecting);
    } on Unreachable {
      if (identical(_info, selecting)) _info = null;
      rethrow;
    } finally {
      if (--_calls == 0 && _closed) _server.close();
    }
  }

  @override
  Future<Uri> sign(String path) => _call((_) => _server.sign(path));

  @override
  Future<String> createUpload(int length, String blake3, {String? path}) =>
      _call((_) => _server.createUpload(null, length, blake3, path: path));

  @override
  Future<void> sendUpload(
    String path,
    int length,
    Stream<List<int>> Function(int offset) read,
  ) => _call((_) => _server.sendUpload(path, length, read));

  @override
  void networkChanged() {
    if (_closed) return;
    // A selection that finds no address fails the next call, which selects
    // again.
    (_info = _server.selectEndpoint()).ignore();
  }

  @override
  void close() {
    _closed = true;
    if (_calls == 0) _server.close();
  }
}
