// The one network stack (design 10 §9) against photolibd behind a reverse proxy with a private CA and mutual TLS.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:photolib_api/media_proxy.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:test/test.dart';

import 'support/pki.dart';
import 'support/servers.dart';

void main() {
  late Pki pki;
  late ProxiedServer photolibd;
  setUpAll(() async => pki = await Pki.create());
  tearDownAll(() => pki.delete());
  setUp(
    () async => photolibd = await ProxiedServer.start(
      pki.serverContext('server', ca: 'ca'),
    ),
  );
  tearDown(() => photolibd.close());

  NetworkConfig trusted({
    String identity = 'client',
    List<Uri>? endpoints,
    String? proxy,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) => NetworkConfig(
    endpoints: endpoints ?? [photolibd.url],
    trustedCertificates: pki['ca.pem'],
    clientIdentity: pki['$identity.p12'],
    clientIdentityPassword: Pki.password,
    proxy: proxy,
    headers: headers,
    timeout: timeout,
  );

  Server open(NetworkConfig config, {String? instance}) {
    final server = Server(config, instance: instance);
    addTearDown(server.close);
    return server;
  }

  /// Another photolibd behind a reverse proxy, closed after the test.
  Future<ProxiedServer> serve({
    String certificate = 'server',
    bool mtls = true,
  }) async {
    final server = await ProxiedServer.start(
      pki.serverContext(certificate, ca: 'ca'),
      mtls: mtls,
    );
    addTearDown(server.close);
    return server;
  }

  Future<GetServerInfoResponse> serverInfo(Server server) =>
      ServerInfoServiceApi(server.rpc)
          .getServerInfo(null, GetServerInfoRequest());

  /// Reads `bytes` from an offset on, a MiB at a time, as the app reads a file.
  Stream<List<int>> Function(int) reader(List<int> bytes) => (offset) async* {
    for (var at = offset; at < bytes.length; at += 1 << 20) {
      yield bytes.sublist(at, min(at + (1 << 20), bytes.length));
    }
  };

  /// Uploads `bytes` into a library, retrying at once.
  Future<void> upload(Server server, List<int> bytes) async {
    final path = await server.createUpload(
      'library-1',
      bytes.length,
      'af13',
      path: 'DCIM/Camera/IMG 1 ü%.jpg',
    );
    await server.sendUpload(
      path,
      bytes.length,
      reader(bytes),
      backoff: Duration.zero,
    );
  }

  // A player that cannot use the app's stack: plain dart:io, which trusts no private CA and has no identity.
  Future<(HttpClientResponse, List<int>)> play(
    Uri url, {
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    final player = HttpClient();
    addTearDown(player.close);
    final request = await player.openUrl(method, url);
    headers.forEach(request.headers.set);
    final response = await request.close();
    return (
      response,
      await response.fold(<int>[], (all, bytes) => all..addAll(bytes)),
    );
  }

  test('one configuration carries API calls, thumbnails, video and uploads through the proxy', () async {
    final proxy = await TunnelProxy.start();
    addTearDown(proxy.close);
    final server = open(
      trusted(proxy: proxy.address, headers: {'cf-access-token': 'token'}),
    );

    expect((await serverInfo(server)).epoch, 'instance-a');
    final thumbnail = await server.get('media/0190a3c2/thumb_s');
    expect(await thumbnail.stream.toBytes(), ProxiedServer.media);
    final media = await MediaProxy.start(server);
    addTearDown(media.close);
    final (response, video) = await play(
      media.url('media/0190a3c2/original'),
      headers: {'range': 'bytes=10-19'},
    );
    expect(response.statusCode, 206);
    expect(video, ProxiedServer.media.sublist(10, 20));
    await upload(server, [1, 2, 3]);
    expect(photolibd.uploaded.toBytes(), [1, 2, 3]);

    expect(photolibd.seen.map((r) => (r.method, r.path)), [
      ('POST', '/photolib.api.v1.ServerInfoService/GetServerInfo'),
      ('GET', '/media/0190a3c2/thumb_s'),
      ('GET', '/media/0190a3c2/original'),
      ('POST', '/upload'),
      ('HEAD', '/upload/1'),
      ('PATCH', '/upload/1'),
    ]);
    final creation = photolibd.seen[3].headers;
    expect(
      [
        'upload-complete',
        'upload-length',
        'photolib-library',
        'photolib-hash',
        'photolib-path',
        'upload-draft-interop-version',
      ].map(creation.value),
      [
        '?0',
        '3',
        'library-1',
        'af13',
        'DCIM/Camera/IMG%201%20%C3%BC%25.jpg',
        '10',
      ],
    );
    expect(
      photolibd.seen.map((r) => r.headers.value('cf-access-token')),
      everyElement('token'),
    );
    expect(proxy.targets, isNotEmpty);
    expect(proxy.targets, everyElement(photolibd.url.authority));
  });

  test("never sends a request, with the server's headers and identity, outside its endpoint", () async {
    final server = open(trusted());
    final media = await MediaProxy.start(server);
    addTearDown(media.close);
    for (final path in [
      '//elsewhere.example/x',
      'https://elsewhere.example/x',
    ]) {
      await expectLater(server.get(path), throwsArgumentError);
      await expectLater(
        server.sendUpload(path, 1, reader([1])),
        throwsArgumentError,
      );
    }
    final (response, _) = await play(media.url('//elsewhere.example/x'));
    expect(response.statusCode, HttpStatus.badRequest);
    expect(photolibd.seen, isEmpty);
    photolibd.answer = (response) => response
      ..statusCode = 201
      ..headers.set('location', '//elsewhere.example/upload/1');
    await expectLater(
      server.createUpload('library-1', 1, 'af13'),
      throwsA(isA<Unreachable>()),
    );
  });

  test(
    'follows no redirect, which could take the headers and identity elsewhere',
    () async {
      final elsewhere = await serve();
      photolibd.answer = redirect(elsewhere.url.resolve('media/1/thumb_s'));
      final server = open(trusted(headers: {'cf-access-token': 'token'}));
      await expectLater(serverInfo(server), throwsA(isA<Unreachable>()));
      await expectLater(
        server.get('media/1/thumb_s'),
        throwsA(isA<Unreachable>()),
      );
      expect(elsewhere.seen, isEmpty);
    },
  );

  // The one-configuration test shows them arriving over HTTPS.
  test('sends the configured headers over HTTPS only, never to a plain-HTTP address any machine could own', () async {
    final lan = await ProxiedServer.start(null);
    addTearDown(lan.close);
    final server = open(
      trusted(
        endpoints: [lan.url, photolibd.url],
        headers: {'cf-access-token': 'token'},
      ),
    );
    await server.selectEndpoint();
    expect(lan.seen.single.headers.value('cf-access-token'), isNull);
  });

  group('the session over plain HTTP (ADR-0125)', () {
    late ProxiedServer lan;
    setUp(() async => lan = await ProxiedServer.start(null));
    tearDown(() => lan.close());

    // The plain-HTTP server answers for every address, as their proxy.
    Server through(String hosts) => open(
      NetworkConfig(
        endpoints: [for (final h in hosts.split(' ')) Uri.parse('http://$h/')],
        proxy: lan.url.authority,
        session: 'token-1',
      ),
      instance: 'instance-a',
    );

    test(
      'goes to the addresses photolibd counts as local (proxy.rs)',
      () async {
        const locals =
            '127.0.0.1 10.1.2.3 172.16.0.1 192.168.1.20 169.254.0.1 [::1] '
            '[fd00::1] [fe80::1] [::ffff:192.168.1.2]';
        for (final local in locals.split(' ')) {
          await serverInfo(through(local));
          final bearer = lan.seen.last.headers.value('authorization');
          expect(bearer, isNotNull, reason: local);
        }
      },
    );

    test('goes nowhere else, as the server needs HTTPS there', () async {
      const remotes =
          '203.0.113.9 172.32.0.1 100.64.0.1 [2001:db8::1] [::ffff:8.8.8.8]';
      final needsHttps = throwsA(isA<HttpsRequired>());
      for (final remote in remotes.split(' ')) {
        final server = through(remote);
        await expectLater(server.selectEndpoint(), needsHttps);
        await expectLater(serverInfo(server), needsHttps);
        await expectLater(server.get('media/1/thumb_s'), needsHttps);
        await expectLater(server.createUpload('l', 1, 'af13'), needsHttps);
        // Not tried again, which would take an hour.
        const hour = Duration(hours: 1);
        await expectLater(
          server.sendUpload('upload/1', 1, reader([1]), backoff: hour),
          needsHttps,
        );
      }
      const probe = '/photolib.api.v1.ServerInfoService/GetServerInfo';
      expect(
        lan.seen.map((r) => (r.path, r.headers.value('authorization'))),
        everyElement((probe, null)),
      );
      expect(HttpsRequired(Uri()).logsOut, isFalse);
    });

    test('chooses an endpoint it may go to', () async {
      final server = through('203.0.113.9 192.168.1.20');
      await server.selectEndpoint();
      expect(server.endpoint, Uri.parse('http://192.168.1.20/'));
    });
  });

  test('sends the session to localhost, judged by where it resolves, never to an address it probes', () async {
    final lan = await ProxiedServer.start(null);
    addTearDown(lan.close);
    final server = open(
      NetworkConfig(endpoints: [lan.url], session: 'token-1'),
      instance: 'instance-a',
    );
    await server.selectEndpoint();
    await serverInfo(server);
    await server.get('media/1/thumb_s');
    await upload(server, [1]);
    expect(lan.seen.map((r) => r.headers.value('authorization')), [
      null,
      for (var i = 1; i < lan.seen.length; i++) 'Bearer token-1',
    ]);
  });

  test("reads a self-signed server's certificate for its user to confirm, and nothing of a trusted one", () async {
    final selfSigned = await serve(certificate: 'self-signed', mtls: false);
    expect(
      await untrustedCertificate(
        NetworkConfig(endpoints: [selfSigned.url]),
        selfSigned.url,
      ),
      pki.fingerprint('self-signed'),
    );
    expect(await untrustedCertificate(trusted(), photolibd.url), isNull);
    expect(photolibd.seen, isEmpty);
  });

  test(
    'a 304 Not Modified is an answer, for the app and for players',
    () async {
      final server = open(trusted());
      final cached = await server.get(
        'media/1/thumb_s',
        headers: {'if-none-match': '"m1"'},
      );
      expect(cached.statusCode, HttpStatus.notModified);
      final media = await MediaProxy.start(server);
      addTearDown(media.close);
      final (response, _) = await play(
        media.url('media/1/original'),
        headers: {'if-none-match': '"m1"'},
      );
      expect(
        (response.statusCode, response.headers.value('etag')),
        (HttpStatus.notModified, '"m1"'),
      );
    },
  );

  test('the loopback proxy wants its token and serves only GET', () async {
    final media = await MediaProxy.start(open(trusted()));
    addTearDown(media.close);
    final url = media.url('media/1/original');
    final wrongToken = url.replace(
      path: url.path.replaceFirst(RegExp('^/[^/]+'), '/guess'),
    );
    expect((await play(wrongToken)).$1.statusCode, HttpStatus.notFound);
    final (post, _) = await play(url, method: 'POST');
    expect(post.statusCode, HttpStatus.methodNotAllowed);
    expect(post.headers.value('access-control-allow-origin'), isNull);
    expect(photolibd.seen, isEmpty);
  });

  for (final (name, config) in <(String, NetworkConfig Function())>[
    (
      'without the client certificate',
      () => NetworkConfig(
        endpoints: [photolibd.url],
        trustedCertificates: pki['ca.pem'],
      ),
    ),
    (
      'with a client certificate from another CA',
      () => trusted(identity: 'stranger'),
    ),
    (
      'without the private CA',
      () => NetworkConfig(
        endpoints: [photolibd.url],
        clientIdentity: pki['client.p12'],
        clientIdentityPassword: Pki.password,
      ),
    ),
  ]) {
    test(
      '$name, API calls, thumbnails, video and uploads all fail as unreachable',
      () async {
        final server = open(config());
        final media = await MediaProxy.start(server);
        addTearDown(media.close);
        await expectLater(serverInfo(server), throwsA(isA<Unreachable>()));
        await expectLater(
          server.get('media/1/thumb_s'),
          throwsA(isA<Unreachable>()),
        );
        expect(
          (await play(media.url('media/1/original'))).$1.statusCode,
          HttpStatus.badGateway,
        );
        await expectLater(
          server.createUpload('library-1', 1, 'af13'),
          throwsA(isA<Unreachable>()),
        );
        expect(photolibd.uploaded.isEmpty, isTrue);
      },
    );
  }

  test('a self-signed server is trusted once its fingerprint is pinned, and refused when its key changes', () async {
    final selfSigned = await serve(certificate: 'self-signed', mtls: false);
    NetworkConfig pinned(String certificate) => NetworkConfig(
      endpoints: [selfSigned.url],
      pinnedCertificate: pki.fingerprint(certificate),
    );
    expect((await serverInfo(open(pinned('self-signed')))).epoch, 'instance-a');
    await expectLater(
      serverInfo(open(pinned('self-signed-2'))),
      throwsA(isA<Unreachable>()),
    );
    await expectLater(
      serverInfo(open(NetworkConfig(endpoints: [selfSigned.url]))),
      throwsA(isA<Unreachable>()),
    );
  });

  group('the endpoint (MOB-16)', () {
    Future<ProxiedServer> another({
      String epoch = 'instance-a',
      Duration delay = Duration.zero,
    }) async {
      return await serve()
        ..epoch = epoch
        ..delay = delay;
    }

    Future<Uri> selected(
      List<Uri> endpoints, {
      String? instance = 'instance-a',
    }) async {
      final server = open(trusted(endpoints: endpoints), instance: instance);
      expect((await server.selectEndpoint()).epoch, instance ?? anything);
      return server.endpoint;
    }

    test(
      'is the fastest of those that answer as the pinned instance',
      () async {
        final slow = await another(delay: const Duration(milliseconds: 300));
        expect(await selected([slow.url, photolibd.url]), photolibd.url);
        expect(await selected([photolibd.url, slow.url]), photolibd.url);
      },
    );

    test('is never another instance, such as a server at the same address on a foreign LAN', () async {
      final foreign = await another(epoch: 'instance-b');
      expect(await selected([foreign.url, photolibd.url]), photolibd.url);
      await expectLater(
        open(
          trusted(endpoints: [foreign.url]),
          instance: 'instance-a',
        ).selectEndpoint(),
        throwsA(isA<Unreachable>()),
      );
    });

    test(
      'is still the pinned instance once restored, which its epoch counts',
      () async {
        final restored = await another(epoch: 'instance-a.2');
        final server = open(
          trusted(endpoints: [restored.url]),
          instance: 'instance-a',
        );
        expect((await server.selectEndpoint()).epoch, 'instance-a.2');
      },
    );

    test('skips an endpoint that does not answer', () async {
      final gone = await another();
      final url = gone.url;
      await gone.close();
      expect(await selected([url, photolibd.url]), photolibd.url);
    });

    test('is the first to answer when no instance is pinned yet, for the app to pin', () async {
      final slow = await another(
        epoch: 'instance-b',
        delay: const Duration(milliseconds: 300),
      );
      expect(
        await selected([slow.url, photolibd.url], instance: null),
        photolibd.url,
      );
    });

    test('keeps a base path', () async {
      final server = open(
        trusted(endpoints: [photolibd.url.resolve('photolib')]),
      );
      await expectLater(serverInfo(server), throwsA(isA<Unreachable>()));
      expect(
        photolibd.seen.single.path,
        '/photolib/photolib.api.v1.ServerInfoService/GetServerInfo',
      );
    });
  });

  group('only an explicit revocation logs out', () {
    Future<CallError> failure(Future<void> call) async {
      try {
        await call;
      } on CallError catch (error) {
        return error;
      }
      throw StateError('the call succeeded');
    }

    for (final (name, answer) in [
      ("a reverse proxy's 502 page", page(502)),
      ("a reverse proxy's 401 page", page(401)),
      ("a captive portal's page", page(200)),
      (
        "a reverse proxy's 502 that claims to be JSON",
        (HttpResponse response) => response
          ..statusCode = 502
          ..headers.contentType = ContentType.json
          ..write('Bad Gateway'),
      ),
      (
        'an unauthenticated error without a reason',
        connectError(401, 'unauthenticated'),
      ),
    ]) {
      test('$name is not', () async {
        photolibd.answer = answer;
        final server = open(trusted());
        for (final error in [
          await failure(serverInfo(server)),
          await failure(server.get('media/1/thumb_s')),
        ]) {
          expect(error.logsOut, isFalse, reason: '$error');
        }
      });
    }

    test(
      "a reverse proxy's 504 page after its 60 s upstream timeout is not",
      () async {
        final proxy = await serve()
          ..timeout =
              const Duration(milliseconds: 100) // 60 s, scaled down
          ..delay = const Duration(seconds: 60);
        final error = await failure(
          serverInfo(open(trusted(endpoints: [proxy.url]))),
        );
        expect(
          error,
          isA<Unreachable>().having(
            (error) => '$error',
            'cause',
            contains('HTTP 504 text/html'),
          ),
        );
        expect(error.logsOut, isFalse);
      },
    );

    test('no answer within the timeout is not', () async {
      photolibd.delay = const Duration(seconds: 5);
      final server = open(trusted(timeout: const Duration(milliseconds: 100)));
      final error = await failure(serverInfo(server));
      expect(error, isA<Unreachable>());
      expect((error as Unreachable).cause, isA<TimeoutException>());
    });

    test('a revoked session, with its reason, does', () async {
      photolibd.answer = connectError(
        401,
        'unauthenticated',
        reason: 'auth.session_revoked',
      );
      final error = await failure(serverInfo(open(trusted())));
      expect(error.logsOut, isTrue);
      expect((error as ServerError).detail!.code, 'auth.session_revoked');
    });

    test('media photolibd has not, or not for this session, is its empty 404, '
        "not_found; a proxy's 404 page is unreachable", () async {
      photolibd.answer = (response) => response..statusCode = 404;
      final server = open(trusted());
      final error = await failure(server.get('media/1/thumb_s'));
      expect(
        error,
        isA<ServerError>().having((e) => e.code, 'code', 'not_found'),
      );
      expect(error.logsOut, isFalse);
      photolibd.answer = page(404);
      expect(await failure(server.get('media/1/thumb_s')), isA<Unreachable>());
    });

    test(
      'other errors carry the code, reason and parameters the app translates',
      () async {
        photolibd.answer = connectError(
          404,
          'not_found',
          reason: 'asset.not_found',
          params: {'asset_id': '0190a3c2'},
        );
        final error = await failure(serverInfo(open(trusted())));
        expect((error as ServerError).code, 'not_found');
        expect(
          (error.detail!.code, error.detail!.params['asset_id'], error.logsOut),
          ('asset.not_found', '0190a3c2', false),
        );
      },
    );
  });

  group('uploads', () {
    const megabyte = 1000 * 1000;
    final video = Uint8List(120 * megabyte);
    for (var i = 0; i < video.length; i += 4096) {
      video[i] = i ~/ 4096;
    }
    Iterable<Seen> appends(ProxiedServer server) =>
        server.seen.where((request) => request.method == 'PATCH');

    /// Sends `bytes` to the upload at `path` on a clock on which an append's
    /// timeout passes only when the server hangs: a loaded machine slows the
    /// other appends down, never into a timeout.
    Future<void> send(Server server, String path, List<int> bytes) {
      const appendTimeout = Duration(days: 1);
      final timeouts = <(Timer, void Function())>[];
      photolibd.onHang = () {
        final (timer, timeout) = timeouts.last;
        timer.cancel();
        timeout();
      };
      return runZoned(
        () => server.sendUpload(
          path,
          bytes.length,
          reader(bytes),
          backoff: Duration.zero,
          appendTimeout: appendTimeout,
        ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            if (duration == appendTimeout) timeouts.add((timer, callback));
            return timer;
          },
        ),
      );
    }

    test('pass a 100 MB request cap in appends of at most 8 MiB and resume after the network drops or hangs', () async {
      const cuts = [30 * megabyte, 70 * megabyte];
      photolibd.losses.addAll([
        (at: cuts[0], hangs: false),
        (at: cuts[1], hangs: true),
      ]);
      final heard = <LogRecord>[];
      addTearDown(Log.records.listen(heard.add).cancel);
      final server = open(trusted());
      final path = await server.createUpload('library-1', video.length, 'af13');
      await send(server, path, video);
      final requests = heard.where((r) => r.logger == 'photolib.network');
      expect(requests.first.fields, containsPair('method', 'POST'));
      expect(requests.first.fields, containsPair('route', '/upload'));
      expect(requests.first.fields, containsPair('status', 201));
      expect(requests.first.fields['ms'], isA<int>());
      final failed = requests.where((r) => r.message == 'request failed');
      expect(failed, isNotEmpty, reason: 'the drop and the hang');
      expect(failed.map((r) => r.error), everyElement(isNotNull));
      final upload = heard.where((r) => r.logger == 'photolib.upload');
      expect(upload.map((r) => r.message).toSet(), {
        'upload created',
        'upload resumed',
        'appended',
        'upload interrupted',
        'upload complete',
      });
      expect(
        upload.where((r) => r.message == 'upload interrupted'),
        hasLength(2),
      );
      expect(appends(photolibd).last.headers.value('upload-complete'), '?1');
      final heads = photolibd.seen.where((r) => r.method == 'HEAD');
      expect(heads.length, 3, reason: 'once to start, once after each loss');
      // Appends of at most 8 MiB; one the network lost is sent again from where it was cut, and only that.
      final expected = <(int, int)>[];
      for (var at = 0; at < video.length;) {
        final length = min(appendBytes, video.length - at);
        expected.add((at, length));
        at = cuts.firstWhere(
          (cut) => cut > at && cut < at + length,
          orElse: () => at + length,
        );
      }
      final sent = appends(photolibd)
          .map((r) => (int.parse(r.headers.value('upload-offset')!), r.length));
      expect(sent, expected);
      expect(
        sha256.convert(photolibd.uploaded.takeBytes()),
        sha256.convert(video),
      );
      // 120 MB through TLS takes over half a minute on a saturated machine.
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('count what a timed-out append left as progress', () async {
      // A slow uplink: every append times out a MiB in, more times in a row
      // than the attempts an upload without progress has.
      final bytes = video.sublist(0, 10 << 20);
      final cuts = [for (var mib = 1; mib <= 6; mib++) mib << 20];
      photolibd.losses.addAll([for (final at in cuts) (at: at, hangs: true)]);
      final server = open(trusted());
      var path = await server.createUpload('l', bytes.length, 'a');
      await send(server, path, bytes);
      expect(appends(photolibd).map((r) => r.headers.value('upload-offset')), [
        '0',
        for (final cut in cuts) '$cut',
      ]);
      expect(photolibd.uploaded.takeBytes(), bytes);

      // An append that times out before the server kept a byte is no progress:
      // the fifth in a row ends the upload.
      photolibd.losses.addAll([
        for (var i = 0; i < 6; i++) (at: 0, hangs: true),
      ]);
      path = await server.createUpload('l', bytes.length, 'a');
      await expectLater(send(server, path, bytes), throwsA(isA<Unreachable>()));
      expect(photolibd.losses, hasLength(1), reason: 'five appends, no sixth');
    });

    test("halve their appends after a proxy's 413 and fail without logging out under a cap they cannot pass", () async {
      final nginx = await serve()
        ..cap = 1 << 20; // client_max_body_size 1m
      final bytes = video.sublist(0, 3 << 20);
      await upload(open(trusted(endpoints: [nginx.url])), bytes);
      expect(nginx.uploaded.takeBytes(), bytes);
      expect(appends(nginx).map((r) => r.length), [
        3 << 20,
        3 << 19,
        for (var i = 0; i < 4; i++) 3 << 18,
      ]);

      final tiny = await serve()
        ..cap = 1000;
      final error = upload(open(trusted(endpoints: [tiny.url])), bytes);
      await expectLater(
        error,
        throwsA(
          isA<Unreachable>()
              .having((error) => '$error', 'cause', contains('HTTP 413'))
              .having((error) => error.logsOut, 'logsOut', isFalse),
        ),
      );
    });

    test('a refusal, a cancelled upload or one the server no longer has is not retried', () async {
      final server = open(trusted());
      final path = await server.createUpload('library-1', 3, 'af13');
      final refused = server.sendUpload(path, 3, (offset) {
        photolibd.answer = connectError(
          400,
          'invalid_argument',
          reason: 'upload.hash_mismatch',
        );
        return reader([1, 2, 3])(offset);
      });
      await expectLater(
        refused,
        throwsA(
          isA<ServerError>().having(
            (e) => e.detail!.code,
            'reason',
            'upload.hash_mismatch',
          ),
        ),
      );
      photolibd.answer = null;
      await server.cancelUpload(path);
      final gone = server.sendUpload(path, 3, reader([1, 2, 3]));
      await expectLater(
        gone,
        throwsA(isA<ServerError>().having((e) => e.code, 'code', 'not_found')),
      );
      expect(photolibd.seen.map((r) => r.method), [
        'POST',
        'HEAD',
        'PATCH',
        'DELETE',
        'HEAD',
      ]);
    });
  });
}
