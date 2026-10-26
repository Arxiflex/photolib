import 'package:http/http.dart' as http;
import 'package:photolib_log/photolib_log.dart';

import 'stack_io.dart' if (dart.library.js_interop) 'stack_web.dart';

/// How the app reaches one server. Every request to it — API calls, thumbnails, video and uploads — goes through
/// the one client [httpClient] builds from this, so they all share its trust configuration (design 10 §9).
class NetworkConfig {
  const NetworkConfig({
    required this.endpoints,
    this.trustedCertificates,
    this.clientIdentity,
    this.clientIdentityPassword,
    this.pinnedCertificate,
    this.proxy,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
    this.session,
  });

  /// The server's base URLs: LAN, WAN, VPN.
  final List<Uri> endpoints;

  /// PEM certificates of a private CA, trusted in addition to the system roots.
  final List<int>? trustedCertificates;

  /// A PKCS#12 bundle of the client certificate chain and its key, for a server behind mutual TLS.
  final List<int>? clientIdentity;
  final String? clientIdentityPassword;

  /// The SHA-256 (lowercase hex, of the DER) of a self-signed server certificate the user confirmed on first use.
  final String? pinnedCertificate;

  /// An HTTP proxy as `host:port`; null connects directly.
  final String? proxy;

  /// Headers for every HTTPS request, such as a Cloudflare Access token or proxy authentication. A plain-HTTP address
  /// gets none: any machine on the network it is on could answer.
  final Map<String, String> headers;

  /// The longest wait for the answer to an API call or a media request.
  final Duration timeout;

  /// The device's session token (ADR-0052), a bearer for every request to the endpoint in use, but never to an
  /// address before it answered as the server's instance; over plain HTTP only to an address photolibd counts as
  /// local, else the call fails with `HttpsRequired` (ADR-0125).
  final String? session;
}

/// The client for one server on the platform's stack. On the web the browser owns TLS and proxies, so there only
/// [NetworkConfig.headers] apply.
http.Client httpClient(NetworkConfig config) =>
    _Guarded(stack(config), config.headers);

const _log = Logger('photolib.network');

/// The SHA-256 (lowercase hex, of the DER) of the certificate that [url] presents when the platform does not trust it,
/// for its user to confirm before it becomes [NetworkConfig.pinnedCertificate]; null when it is trusted, does not
/// answer, or the browser owns TLS. Sends no request.
Future<String?> untrustedCertificate(NetworkConfig config, Uri url) =>
    certificate(config, url);

/// Keeps the server's headers and identity with the server: no redirect, which could lead anywhere, and headers only
/// where TLS has proved who answers. Logs every request: its method, path, status and time to the answer's headers.
class _Guarded extends http.BaseClient {
  _Guarded(this._inner, this._headers);
  final http.Client _inner;
  final Map<String, String> _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.followRedirects = false;
    if (request.url.scheme == 'https') request.headers.addAll(_headers);
    final took = Stopwatch()..start();
    final fields = {'method': request.method, 'route': request.url.path};
    try {
      final response = await _inner.send(request);
      _log.log(
        response.statusCode >= 400 ? LogLevel.warning : LogLevel.debug,
        'request',
        fields: {
          ...fields,
          'status': response.statusCode,
          'ms': took.elapsedMilliseconds,
        },
      );
      return response;
    } catch (error) {
      _log.warning(
        'request failed',
        fields: {...fields, 'ms': took.elapsedMilliseconds},
        error: error,
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
