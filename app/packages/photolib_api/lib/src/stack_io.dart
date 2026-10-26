import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:photolib_api/src/diagnose.dart';
import 'package:photolib_api/src/network.dart';

/// dart:io's HttpClient with an explicit SecurityContext: the system roots plus the server's CA, and the client
/// identity for mutual TLS.
http.Client stack(NetworkConfig config) {
  final client = _client(config);
  if (config.pinnedCertificate case final pin?) {
    client.badCertificateCallback = (certificate, _, _) =>
        _fingerprint(certificate) == pin;
  }
  return IOClient(client);
}

Future<String?> certificate(NetworkConfig config, Uri url) async {
  String? seen;
  final client = _client(config)
    ..connectionTimeout = config.timeout
    ..badCertificateCallback = (certificate, _, _) {
      seen = _fingerprint(certificate);
      return false;
    };
  try {
    // Opening connects and shakes hands; aborting sends nothing.
    (await client.openUrl('HEAD', url)).abort();
  } on Exception {
    // Refused, or untrusted: the callback saw the certificate.
  } finally {
    client.close(force: true);
  }
  return seen;
}

/// The DNS, TCP and TLS steps of [diagnose] against [endpoint], or against
/// the proxy of [config], which TLS then passes through unseen.
Stream<Finding> reach(NetworkConfig config, Uri endpoint, DateTime now) async* {
  final proxy = config.proxy == null
      ? null
      : Uri.parse('http://${config.proxy}');
  final (host, port) = proxy == null
      ? (endpoint.host, endpoint.port)
      : (proxy.host, proxy.port);
  final (dns, addresses) = await _lookUp(host, config.timeout);
  yield dns;
  final (tcp, socket) = addresses.isEmpty
      ? (const Finding(CheckStep.tcp, ran: false), null)
      : await _connect(addresses.first, port, config.timeout);
  yield tcp;
  if (socket == null || endpoint.scheme != 'https' || proxy != null) {
    socket?.destroy();
    yield const Finding(CheckStep.tls, ran: false);
  } else {
    yield await _handshake(socket, host, config, now);
  }
}

Future<(Finding, List<InternetAddress>)> _lookUp(
  String host,
  Duration timeout,
) async {
  if (InternetAddress.tryParse(host) case final address?) {
    return (Finding(CheckStep.dns, detail: host), [address]);
  }
  try {
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    return (
      Finding(CheckStep.dns, detail: '$host: ${addresses.join(', ')}'),
      [...addresses],
    );
  } on Exception catch (error) {
    return (
      Finding(CheckStep.dns, fault: Fault.dnsFailed, detail: '$error'),
      <InternetAddress>[],
    );
  }
}

Future<(Finding, Socket?)> _connect(
  InternetAddress address,
  int port,
  Duration timeout,
) async {
  try {
    final socket = await Socket.connect(address, port, timeout: timeout);
    return (Finding(CheckStep.tcp, detail: '${address.address}:$port'), socket);
  } on SocketException catch (error) {
    // A connect that times out has no OS error.
    final fault = error.osError == null ? Fault.timedOut : Fault.refused;
    return (Finding(CheckStep.tcp, fault: fault, detail: '$error'), null);
  }
}

Future<Finding> _handshake(
  Socket socket,
  String host,
  NetworkConfig config,
  DateTime now,
) async {
  X509Certificate? seen;
  try {
    final secure = await SecureSocket.secure(
      socket,
      host: host,
      context: _context(config),
      onBadCertificate: (certificate) {
        seen = certificate;
        return _fingerprint(certificate) == config.pinnedCertificate;
      },
    ).timeout(config.timeout);
    final subject = secure.peerCertificate?.subject;
    secure.destroy();
    return Finding(CheckStep.tls, detail: '$subject');
  } on Exception catch (error) {
    socket.destroy();
    return switch (seen) {
      null => Finding(CheckStep.tls, fault: Fault.tlsFailed, detail: '$error'),
      final seen => Finding(
        CheckStep.tls,
        fault: switch (seen) {
          _ when seen.endValidity.isBefore(now) => Fault.certificateExpired,
          _ when config.pinnedCertificate != null => Fault.certificateChanged,
          _ when seen.issuer == seen.subject => Fault.selfSigned,
          _ => Fault.untrustedCertificate,
        },
        detail: '$error; ${seen.subject}; ${seen.issuer}',
        fingerprint: _fingerprint(seen),
        date: seen.endValidity,
      ),
    };
  }
}

SecurityContext _context(NetworkConfig config) {
  final context = SecurityContext(withTrustedRoots: true);
  if (config.trustedCertificates case final ca?) {
    context.setTrustedCertificatesBytes(ca);
  }
  if (config.clientIdentity case final identity?) {
    context
      ..useCertificateChainBytes(
        identity,
        password: config.clientIdentityPassword,
      )
      ..usePrivateKeyBytes(identity, password: config.clientIdentityPassword);
  }
  return context;
}

/// The addresses [host] resolves to, as bytes.
Future<List<List<int>>> addresses(String host) async => [
  for (final address in await InternetAddress.lookup(host)) address.rawAddress,
];

HttpClient _client(NetworkConfig config) =>
    HttpClient(context: _context(config))
      ..findProxy = (_) =>
          config.proxy == null ? 'DIRECT' : 'PROXY ${config.proxy}';

String _fingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();

/// The gzip [data] inflates to; a FormatException when it is broken or would
/// exceed [limit] bytes.
Future<Uint8List> gunzip(Uint8List data, int limit) async {
  final out = _Capped(limit);
  gzip.decoder.startChunkedConversion(out)
    ..add(data)
    ..close();
  return out.bytes.takeBytes();
}

class _Capped implements Sink<List<int>> {
  new(this._limit);
  final int _limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    bytes.add(chunk);
    if (bytes.length > _limit) {
      throw const FormatException('gzip past its limit');
    }
  }

  @override
  void close() {}
}
