// The connection check (OPS-29) against photolibd behind a reverse proxy, with
// a fault injected at each step.
@TestOn('vm')
library;

import 'dart:io';

import 'package:photolib_api/photolib_api.dart';
import 'package:test/test.dart';

import 'support/pki.dart';
import 'support/servers.dart';

void main() {
  late Pki pki;
  setUpAll(() async => pki = await Pki.create());
  tearDownAll(() => pki.delete());

  Future<ProxiedServer> serve(String certificate) async {
    final server =
        await ProxiedServer.start(pki.serverContext(certificate), mtls: false)
          ..epoch = 'instance-a.0'
          ..session = 'token-1';
    addTearDown(server.close);
    return server;
  }

  NetworkConfig config({String? pin, String session = 'token-1'}) =>
      NetworkConfig(
        endpoints: const [],
        trustedCertificates: pki['ca.pem'],
        pinnedCertificate: pin,
        session: session,
        timeout: const Duration(seconds: 5),
      );

  /// Each step's fault, or `ok`, or `-` when it did not run.
  Future<Map<CheckStep, Object>> check(
    Uri endpoint, {
    NetworkConfig? with_,
    bool metered = false,
    Duration clock = Duration.zero,
  }) async => {
    await for (final finding in diagnose(
      with_ ?? config(),
      endpoint,
      instance: 'instance-a',
      version: '1.0.0',
      metered: () async => metered,
      now: () => DateTime.now().add(clock),
    ))
      finding.step: finding.ran ? finding.fault ?? 'ok' : '-',
  };

  Map<CheckStep, Object> passing([Map<CheckStep, Object> except = const {}]) =>
      {for (final step in CheckStep.values) step: except[step] ?? 'ok'};

  test('a server that works passes every step, in order', () async {
    final photolibd = await serve('server');
    final findings = await diagnose(
      config(),
      photolibd.url,
      instance: 'instance-a',
    ).toList();
    expect(findings.map((f) => f.step), CheckStep.values);
    expect(findings.where((f) => !f.passed), isEmpty, reason: '$findings');
    expect(
      photolibd.seen.where((r) => r.path == '/healthz').single.length,
      appendBytes,
    );
  });

  test('a name that does not resolve fails at DNS, and nothing after it '
      'that needs the server runs', () async {
    expect(await check(Uri.parse('https://photolib.invalid/')), {
      CheckStep.dns: Fault.dnsFailed,
      for (final step in [
        CheckStep.tcp,
        CheckStep.tls,
        CheckStep.server,
        CheckStep.auth,
      ])
        step: '-',
      CheckStep.upload: '-',
      CheckStep.network: 'ok',
      CheckStep.clock: '-',
    });
  });

  test('a port nothing listens on is refused', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final found = await check(Uri.parse('https://127.0.0.1:$port/'));
    expect(
      (found[CheckStep.dns], found[CheckStep.tcp], found[CheckStep.tls]),
      ('ok', Fault.refused, '-'),
    );
  });

  test('an expired certificate fails at TLS with its date', () async {
    final photolibd = await serve('expired');
    final tls = await diagnose(
      config(),
      photolibd.url,
    ).firstWhere((f) => f.step == CheckStep.tls);
    expect(tls.fault, Fault.certificateExpired);
    expect(tls.date!.isBefore(DateTime.now()), isTrue);
  });

  test('a self-signed certificate without a pin fails at TLS with the '
      'fingerprint to trust, and passes once pinned', () async {
    final photolibd = await serve('self-signed');
    final tls = await diagnose(
      config(),
      photolibd.url,
    ).firstWhere((f) => f.step == CheckStep.tls);
    expect(
      (tls.fault, tls.fingerprint),
      (Fault.selfSigned, pki.fingerprint('self-signed')),
    );
    expect(
      await check(
        photolibd.url,
        with_: config(pin: pki.fingerprint('self-signed')),
      ),
      passing(),
    );
    final changed = await check(
      photolibd.url,
      with_: config(pin: pki.fingerprint('self-signed-2')),
    );
    expect(changed[CheckStep.tls], Fault.certificateChanged);
  });

  test('a session the server does not take fails at sign-in', () async {
    final photolibd = await serve('server');
    expect(
      await check(photolibd.url, with_: config(session: 'stolen')),
      passing({CheckStep.auth: Fault.signedOut, CheckStep.upload: '-'}),
    );
  });

  test("a proxy's 413 below an upload append fails at uploads", () async {
    final photolibd = await serve('server');
    photolibd.cap = 1 << 20;
    expect(
      await check(photolibd.url),
      passing({CheckStep.upload: Fault.uploadCap}),
    );
  });

  test('a metered network fails at the network and sends no upload', () async {
    final photolibd = await serve('server');
    expect(
      await check(photolibd.url, metered: true),
      passing({CheckStep.network: Fault.metered, CheckStep.upload: '-'}),
    );
    expect(photolibd.seen.where((r) => r.path == '/healthz'), isEmpty);
  });

  for (final minutes in [10, -10]) {
    test('a clock $minutes minutes off fails at the clock', () async {
      final photolibd = await serve('server');
      final clock = await diagnose(
        config(),
        photolibd.url,
        now: () => DateTime.now().add(Duration(minutes: minutes)),
      ).firstWhere((f) => f.step == CheckStep.clock);
      expect((clock.fault, clock.minutes), (Fault.clockSkew, minutes));
    });
  }

  test('a clock within a few minutes passes', () async {
    final photolibd = await serve('server');
    photolibd.clock = const Duration(minutes: 3);
    expect(await check(photolibd.url), passing());
  });

  test("a proxy's error page, a redirect to a portal, another server and an "
      'app too old fail at the server', () async {
    final photolibd = await serve('server');
    photolibd.answer = page(502);
    expect((await check(photolibd.url))[CheckStep.server], Fault.notPhotolib);
    photolibd.answer = redirect(Uri.parse('https://portal.example/'));
    final found = await diagnose(
      config(),
      photolibd.url,
    ).firstWhere((f) => f.step == CheckStep.server);
    expect(found.fault, Fault.notPhotolib);
    expect(
      found.detail,
      allOf(startsWith('HTTP 302'), endsWith('portal.example/')),
    );
    photolibd
      ..answer = null
      ..epoch = 'instance-b.0';
    expect((await check(photolibd.url))[CheckStep.server], Fault.otherServer);
    photolibd
      ..epoch = 'instance-a.0'
      ..minClientVersion = '1.2.0';
    Future<Fault?> at(String version) async => (await diagnose(
      config(),
      photolibd.url,
      version: version,
    ).firstWhere((f) => f.step == CheckStep.server)).fault;
    expect(
      [await at('1.1.9'), await at('1.2.0'), await at('1.10.0+3')],
      [Fault.appTooOld, null, null],
    );
  });
}
