import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:photolib_api/src/gen/photolib/api/v1/auth.pb.dart';
import 'package:photolib_api/src/gen/photolib/api/v1/server_info.pb.dart';
import 'package:photolib_api/src/network.dart';
import 'package:photolib_api/src/server.dart';
import 'package:photolib_api/src/stack_io.dart'
    if (dart.library.js_interop) 'package:photolib_api/src/stack_web.dart'
    show reach;

/// A step of the connection check, in the order it runs (OPS-29).
enum CheckStep {
  /// Finding the server's address by its name.
  dns,

  /// Connecting to it.
  tcp,

  /// The secure connection and the server's certificate.
  tls,

  /// photolibd's answer: its instance and the app versions it serves.
  server,

  /// This device's session.
  auth,

  /// An upload append's size through every proxy on the way.
  upload,

  /// The network this device is on.
  network,

  /// This device's clock against the server's.
  clock,
}

/// Why a step failed.
enum Fault {
  /// The address's name does not resolve.
  dnsFailed,

  /// Nothing listens there, or no route leads there.
  refused,

  /// No answer within the timeout.
  timedOut,

  /// The certificate expired, on [Finding.date].
  certificateExpired,

  /// The server's own certificate, with [Finding.fingerprint], not pinned yet.
  selfSigned,

  /// Not the certificate pinned: another, with [Finding.fingerprint].
  certificateChanged,

  /// Signed by a CA this device does not trust; [Finding.fingerprint].
  untrustedCertificate,

  /// The TLS handshake failed otherwise, such as a client certificate refused.
  tlsFailed,

  /// Something else answered: a proxy's error page, a redirect to a sign-in
  /// or Wi-Fi portal.
  notPhotolib,

  /// Another Photolib server answered than the one this device knows.
  otherServer,

  /// The server no longer serves this version of the app.
  appTooOld,

  /// The server does not take this device's session.
  signedOut,

  /// A proxy refuses requests as large as an upload's appends.
  uploadCap,

  /// The network is metered, such as mobile data.
  metered,

  /// This device's clock is [Finding.minutes] off the server's.
  clockSkew,
}

/// How one step went: passed when [ran] without a [fault]; not run when an
/// earlier step failed or it does not apply, such as TLS over plain HTTP.
class Finding {
  /// The step and what it found.
  const new(
    this.step, {
    this.ran = true,
    this.fault,
    this.detail = '',
    this.fingerprint,
    this.date,
    this.minutes,
  });

  /// The step.
  final CheckStep step;

  /// Whether it ran.
  final bool ran;

  /// Why it failed; null when it passed.
  final Fault? fault;

  /// What it saw, for the technical detail.
  final String detail;

  /// The SHA-256 of the certificate seen, lowercase hex of its DER.
  final String? fingerprint;

  /// When the certificate expired.
  final DateTime? date;

  /// How many minutes this device's clock is ahead, behind when negative.
  final int? minutes;

  /// Whether it ran and found nothing wrong.
  bool get passed => ran && fault == null;

  @override
  String toString() => '$step ${ran ? fault ?? 'ok' : 'not run'} $detail';
}

/// The clock may be this far off the server's before the check fails: past
/// it, one-time codes and TLS start to fail.
const clockTolerance = Duration(minutes: 5);

/// Runs every [CheckStep] against [endpoint] with [config], in order, and
/// names each step's [Fault]. A step that needs an earlier one does not run
/// once that failed. [instance] is the server's instance id the app knows,
/// [version] the app's (`1.2.3`; null or empty skips it), [metered] whether
/// the network is metered, and [now] this device's clock. On a metered
/// network no upload is tried; else the upload step sends one append
/// ([appendBytes]).
Stream<Finding> diagnose(
  NetworkConfig config,
  Uri endpoint, {
  String? instance,
  String? version,
  Future<bool> Function()? metered,
  DateTime Function() now = DateTime.now,
}) async* {
  final at = NetworkConfig(
    endpoints: [endpoint],
    trustedCertificates: config.trustedCertificates,
    clientIdentity: config.clientIdentity,
    clientIdentityPassword: config.clientIdentityPassword,
    pinnedCertificate: config.pinnedCertificate,
    proxy: config.proxy,
    headers: config.headers,
    timeout: config.timeout,
    session: config.session,
  );
  var ok = true;
  await for (final finding in reach(at, endpoint, now())) {
    if (finding.ran && !finding.passed) ok = false;
    yield finding;
  }
  final client = httpClient(at);
  final server = Server(at);
  try {
    final (found, date) = ok
        ? await _server(client, endpoint, instance, version)
        : (const Finding(CheckStep.server, ran: false), null);
    yield found;
    final auth = !found.passed || config.session == null
        ? const Finding(CheckStep.auth, ran: false)
        : await _auth(server);
    yield auth;
    final onMetered = await metered?.call() ?? false;
    yield !found.passed || !auth.passed && auth.ran || onMetered
        ? const Finding(CheckStep.upload, ran: false)
        : await _upload(client, endpoint);
    yield Finding(CheckStep.network, fault: onMetered ? Fault.metered : null);
    yield _clock(date, now());
  } finally {
    client.close();
    server.close();
  }
}

Finding _clock(DateTime? server, DateTime now) {
  if (server == null) return const Finding(CheckStep.clock, ran: false);
  final skew = now.difference(server);
  return Finding(
    CheckStep.clock,
    fault: skew.abs() > clockTolerance ? Fault.clockSkew : null,
    minutes: (skew.inSeconds / 60).round(),
    detail: 'server ${server.toIso8601String()}',
  );
}

Future<(Finding, DateTime?)> _server(
  http.Client client,
  Uri endpoint,
  String? instance,
  String? version,
) async {
  final http.StreamedResponse answer;
  try {
    answer = await client
        .send(
          http.Request(
              'POST',
              endpoint.resolve(
                'photolib.api.v1.ServerInfoService/GetServerInfo',
              ),
            )
            ..headers.addAll({
              'content-type': 'application/proto',
              'connect-protocol-version': '1',
            }),
        )
        .timeout(const Duration(seconds: 30));
  } on TimeoutException {
    return (const Finding(CheckStep.server, fault: Fault.timedOut), null);
  } on Exception catch (error) {
    return (
      Finding(CheckStep.server, fault: Fault.notPhotolib, detail: '$error'),
      null,
    );
  }
  final date = switch (answer.headers['date']) {
    final String text => _date(text),
    null => null,
  };
  final body = await answer.stream.toBytes();
  final type = answer.headers['content-type'] ?? '';
  if (answer.statusCode != 200 || type != 'application/proto') {
    final where = answer.headers['location'];
    return (
      Finding(
        CheckStep.server,
        fault: Fault.notPhotolib,
        detail: ['HTTP ${answer.statusCode}', type, ?where].join(' '),
      ),
      date,
    );
  }
  final info = GetServerInfoResponse.fromBuffer(body);
  final detail =
      'API ${info.apiVersion}, app ${info.minClientVersion} and '
      'later, instance ${info.epoch}';
  final Fault? fault;
  if (instance != null && info.epoch.split('.').first != instance) {
    fault = Fault.otherServer;
  } else if (version case final v?
      when v.isNotEmpty && _older(v, info.minClientVersion)) {
    fault = Fault.appTooOld;
  } else {
    fault = null;
  }
  return (Finding(CheckStep.server, fault: fault, detail: detail), date);
}

final _httpDate = RegExp(
  r'^\w{3}, (\d\d) (\w{3}) (\d{4}) (\d\d):(\d\d):(\d\d) GMT$',
);
const _months = 'JanFebMarAprMayJunJulAugSepOctNovDec';

/// An HTTP date (`Sun, 06 Nov 1994 08:49:37 GMT`); null for anything else.
DateTime? _date(String text) {
  final match = _httpDate.firstMatch(text.trim());
  if (match == null) return null;
  final [day, name, year, hour, minute, second] = [
    for (var group = 1; group <= 6; group++) match.group(group) ?? '',
  ];
  final month = _months.indexOf(name);
  if (month % 3 != 0) return null;
  return DateTime.utc(
    int.parse(year),
    month ~/ 3 + 1,
    int.parse(day),
    int.parse(hour),
    int.parse(minute),
    int.parse(second),
  );
}

/// Whether [version] is older than [oldest], both `major.minor.patch`.
bool _older(String version, String oldest) {
  List<int> parts(String v) => [
    for (final part in v.split('+').first.split('.')) int.tryParse(part) ?? 0,
  ];
  final (a, b) = (parts(version), parts(oldest));
  for (var i = 0; i < 3; i++) {
    final (x, y) = (i < a.length ? a[i] : 0, i < b.length ? b[i] : 0);
    if (x != y) return x < y;
  }
  return false;
}

Future<Finding> _auth(Server server) async {
  try {
    await AuthServiceApi(server.rpc).listDevices(null, ListDevicesRequest());
    return const Finding(CheckStep.auth);
  } on ServerError catch (error) {
    return Finding(
      CheckStep.auth,
      fault: error.code == 'unauthenticated' ? Fault.signedOut : null,
      detail: '$error',
    );
  } on Unreachable catch (error) {
    return Finding(CheckStep.auth, fault: Fault.notPhotolib, detail: '$error');
  }
}

/// Sends one append's worth to photolibd, which drains it (`POST /healthz`):
/// a proxy that caps requests below it answers 413 or cuts the connection.
Future<Finding> _upload(http.Client client, Uri endpoint) async {
  try {
    final answer = await client
        .send(
          http.Request('POST', endpoint.resolve('healthz'))
            ..bodyBytes = Uint8List(appendBytes),
        )
        .timeout(const Duration(minutes: 2));
    await answer.stream.drain<void>();
    final detail = 'HTTP ${answer.statusCode} for $appendBytes bytes';
    return Finding(
      CheckStep.upload,
      fault: answer.statusCode == 413 ? Fault.uploadCap : null,
      detail: detail,
    );
  } on Exception catch (error) {
    return Finding(CheckStep.upload, fault: Fault.uploadCap, detail: '$error');
  }
}
