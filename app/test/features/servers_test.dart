import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/own_origin.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/server_app.dart';

void main() {
  setUpServerApp();

  Future<void> addServer(
    WidgetTester tester,
    String addresses, {
    Map<String, String> fields = const {},
  }) async {
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Add a server'));
    await tester.enterText(field('Addresses'), addresses);
    for (final MapEntry(:key, :value) in fields.entries) {
      await tester.enterText(field(key), value);
    }
    await tester.tap(find.text('Connect'));
    // The progress bar runs while a dialog asks.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('adding a server', () {
    test('the address it was served from has no query or fragment', () {
      expect(
        ownAddress(
          Uri.parse('https://photos.example.org:8443/p/?a=1#/library'),
        ),
        Uri.parse('https://photos.example.org:8443/p/'),
      );
      expect(
        '${ownAddress(Uri.parse('http://127.0.0.1:8089/#/x'))}',
        'http://127.0.0.1:8089/',
      );
      expect(ownAddress(Uri.parse('file:///app/index.html')), isNull);
    });

    testWidgets('in a browser the address it was served from is filled in', (
      tester,
    ) async {
      await pumpServerApp(
        tester,
        overrides: [
          ownOriginProvider.overrideWithValue(
            Uri.parse('https://photos.example.org/photos/'),
          ),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('Add a server'));
      expect(
        tester.widget<TextFormField>(field('Addresses')).controller?.text,
        'https://photos.example.org/photos/',
      );
    });

    const pem = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';

    testWidgets(
      'takes its addresses, private CA, proxy and headers, and pins the '
      'instance that answers',
      (tester) async {
        await pumpServerApp(tester);
        await addServer(
          tester,
          'photos.example.org\n http://192.168.1.10:8080/photolib \n',
          fields: {
            'Private CA certificate (PEM)': pem,
            'HTTP proxy, as host:port': 'proxy.lan:3128',
            'Custom headers': 'CF-Access-Client-Id: abc\nX-Other:  1 ',
          },
        );
        final (probed, instance) = links.first;
        expect(instance, isNull, reason: 'the first answer names the instance');
        final config = saved()!.config;
        for (final config in [probed, config]) {
          expect(config.endpoints, [
            Uri.parse('https://photos.example.org'),
            Uri.parse('http://192.168.1.10:8080/photolib'),
          ]);
          expect(utf8.decode(config.trustedCertificates!), pem);
          expect(config.proxy, 'proxy.lan:3128');
          expect(config.headers, {
            'CF-Access-Client-Id': 'abc',
            'X-Other': '1',
          });
          expect(config.session, isNull);
        }
        expect(saved()!.instance, 'instance-a');
        expect(find.text('Sign in'), findsOneWidget);
      },
    );

    testWidgets(
      'refuses what cannot be an address, a proxy or a header, before '
      'sending anything',
      (tester) async {
        await pumpServerApp(tester);
        await addServer(
          tester,
          'photos example',
          fields: {
            'HTTP proxy, as host:port': 'proxy',
            'Custom headers': 'no colon',
          },
        );
        expect(
          find.text('Enter addresses such as photos.example.org'),
          findsOneWidget,
        );
        expect(find.text('Enter the proxy as host:port'), findsOneWidget);
        expect(find.text('Write each header as Name: value'), findsOneWidget);
        expect(links, isEmpty);
        expect(saved(), isNull);
      },
    );

    testWidgets('reads the private CA from a file', (tester) async {
      await pumpServerApp(
        tester,
        overrides: [
          fileProvider.overrideWithValue(
            (extensions) async => XFile.fromData(utf8.encode(pem)),
          ),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('Add a server'));
      await tester.tapAndSettle(find.byTooltip('Choose a certificate file'));
      expect(find.text(pem), findsOneWidget);
    });

    group('a client certificate (PKCS#12)', () {
      late Uint8List p12;
      setUpAll(() async {
        final dir = await Directory.systemTemp.createTemp('photolib-p12-');
        Future<void> openssl(String command) async {
          final run = await Process.run(
            'openssl',
            command.split(' '),
            workingDirectory: dir.path,
          );
          expect(run.exitCode, 0, reason: '${run.stderr}');
        }

        await openssl(
          'req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes '
          '-days 1 -keyout ann.key -out ann.pem -subj /CN=ann',
        );
        await openssl(
          'pkcs12 -export -inkey ann.key -in ann.pem -out ann.p12 '
          '-passout pass:secret',
        );
        p12 = File('${dir.path}/ann.p12').readAsBytesSync();
        await dir.delete(recursive: true);
      });

      Future<void> choose(WidgetTester tester, String password) async {
        await pumpServerApp(
          tester,
          overrides: [
            fileProvider.overrideWithValue(
              (extensions) async => extensions.contains('p12')
                  ? XFile.fromData(p12, path: '/certs/ann.p12')
                  : null,
            ),
          ],
        );
        await tester.tapAndSettle(find.byTooltip('Settings'));
        await tester.tapAndSettle(find.text('Add a server'));
        final choose = find.byTooltip('Choose a client certificate');
        await tester.ensureVisible(choose);
        await tester.tapAndSettle(choose);
        expect(find.text('ann.p12'), findsOneWidget);
        await tester.enterText(field('Addresses'), 'photos.example.org');
        await tester.enterText(field('Client certificate password'), password);
        await tester.tapAndSettle(find.text('Connect'));
      }

      testWidgets('goes with every request, once its password opens it', (
        tester,
      ) async {
        await choose(tester, 'secret');
        for (final config in [links.first.$1, saved()!.config]) {
          expect(config.clientIdentity, p12);
          expect(config.clientIdentityPassword, 'secret');
        }
      });

      testWidgets('with a wrong password is refused before anything is sent', (
        tester,
      ) async {
        await choose(tester, 'wrong');
        expect(
          find.text(
            'This is not a certificate (PKCS#12), or its password is wrong.',
          ),
          findsOneWidget,
        );
        expect(links, isEmpty);
      });
    });

    testWidgets('says when the server does not answer, and keeps nothing', (
      tester,
    ) async {
      server = FakeServer({
        'ServerInfoService/GetServerInfo': (_) => Unreachable('refused'),
      });
      await pumpServerApp(tester);
      await addServer(tester, 'https://photos.example.org');
      expect(find.text('The server does not answer.'), findsOneWidget);
      expect(find.text('Check the connection to see why.'), findsOneWidget);
      expect(saved(), isNull);
    });

    for (final trust in [true, false]) {
      testWidgets(
        'a self-signed server is ${trust ? '' : 'not '}added when its user '
        '${trust ? 'confirms' : 'rejects'} its fingerprint',
        (tester) async {
          untrusted = 'ab' * 31 + '0f';
          server = FakeServer({
            'ServerInfoService/GetServerInfo': (r) =>
                links.last.$1.pinnedCertificate == untrusted
                ? FakeServer.standard['ServerInfoService/GetServerInfo']!(r)
                : Unreachable('the certificate is not trusted'),
          });
          await pumpServerApp(tester);
          await addServer(tester, 'nas.local');
          expect(find.text('Trust this certificate?'), findsOneWidget);
          expect(
            find.text('${List.filled(31, 'AB').join(':')}:0F'),
            findsOneWidget,
          );
          await tester.tapAndSettle(find.text(trust ? 'Trust' : 'Cancel'));
          expect(saved()?.pin, trust ? untrusted : null);
          expect(find.text('Sign in'), trust ? findsOneWidget : findsNothing);
        },
      );
    }
  });

  const needsHttps =
      'This server needs an HTTPS address: beyond your local network, '
      'Photolib does not sign in over plain HTTP.';

  group('signing in', () {
    for (final admin in [true, false]) {
      testWidgets(
        'with an email and password through the kernel keeps the session, '
        'and the console for ${admin ? 'an administrator' : 'nobody else'}',
        (tester) async {
          keep();
          server = FakeServer({
            ...login(),
            if (!admin)
              'AdminService/GetSettings': (_) =>
                  refused('permission_denied', 'authz.denied'),
          });
          await pumpServerApp(tester);
          await openServer(tester);
          await signIn(tester, ' ann@example.org ', 'correct horse');

          final [ke1, ke3] = steps.cast<kernel.OpaqueLoginRequest>();
          expect(
            [ke1.password, ke3.password],
            ['correct horse', 'correct horse'],
          );
          expect(ke1.randomness, hasLength(128));
          expect(
            ke3.randomness,
            ke1.randomness,
            reason: 'both steps rebuild one state',
          );
          expect(ke1.params, hasLength(26));
          expect(ke1.ke2, isEmpty);
          expect(ke3.params, params);
          expect(ke3.ke2, [9]);
          expect(stretched, isEmpty, reason: 'only enrolment calibrates');
          final started = server
              .requests<StartLoginRequest>('AuthService/StartLogin')
              .single;
          expect(started.handle, 'ann@example.org');
          expect(started.ke1, [1]);
          final finished = server
              .requests<FinishLoginRequest>('AuthService/FinishLogin')
              .single;
          expect(finished.loginId, 'login-1');
          expect(finished.ke3, [2]);
          expect(finished.device.platform, 'android');
          expect(finished.device.name, isNotEmpty);
          expect(links.map((l) => l.$1.session), contains('token-1'));

          final account = saved()!.account!;
          expect(
            (account.name, account.token, account.deviceId, account.admin),
            ('ann@example.org', 'token-1', 'device-1', admin),
          );
          expect(find.text('Signed in as ann@example.org'), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.scrollTo(find.text('Diagnostics'));
          expect(
            find.text('Server administration'),
            admin ? findsOneWidget : findsNothing,
          );
        },
      );
    }

    for (final (
          String name,
          Map<String, Object Function(GeneratedMessage)> answers,
          String message,
        )
        in [
          (
            'a wrong password, which the kernel finds',
            <String, Object Function(GeneratedMessage)>{},
            'Wrong email, sign-in name or password.',
          ),
          (
            'a wrong password, which the server finds',
            {
              'AuthService/FinishLogin': (_) =>
                  refused('permission_denied', 'login.failed'),
            },
            'Wrong email, sign-in name or password.',
          ),
          (
            'a locked account',
            {
              'AuthService/StartLogin': (_) =>
                  refused('resource_exhausted', 'login.throttled'),
            },
            'Too many attempts in a short time.',
          ),
          (
            'an unreachable server',
            {
              'AuthService/StartLogin': (_) =>
                  Unreachable('a proxy error page'),
            },
            'The server does not answer.',
          ),
          (
            'plain HTTP beyond the local networks, which photolibd refuses',
            {
              'AuthService/StartLogin': (_) =>
                  refused('failed_precondition', 'login.insecure_http'),
            },
            needsHttps,
          ),
          (
            'a session the app may not send there (ADR-0125)',
            {'AdminService/GetSettings': (_) => HttpsRequired(Uri())},
            needsHttps,
          ),
          (
            'a challenge only a passkey answers',
            {
              'AuthService/FinishLogin': (_) => FinishLoginResponse(
                secondFactor: SecondFactorChallenge(
                  factors: [SecondFactor.SECOND_FACTOR_PASSKEY],
                ),
              ),
            },
            "This account's second factor is a passkey, "
                'which this version of Photolib cannot use yet.',
          ),
        ]) {
      testWidgets('$name says so, and the device stays signed out', (
        tester,
      ) async {
        keep();
        server = FakeServer({...login(), ...answers});
        if (name.contains('kernel')) {
          refusal = KernelError(
            kernel.CallErrorCode.CALL_ERROR_CODE_INVALID_INPUT.value,
            'envelope_recovery',
          );
        }
        await pumpServerApp(tester);
        await openServer(tester);
        await signIn(tester, 'ann', 'pw');
        expect(find.text(message), findsOneWidget);
        expect(saved()!.account, isNull);
        expect(find.text('Sign in'), findsOneWidget);
      });
    }

    testWidgets(
      'names this device and proves it with the secret of its last sign-in, '
      'which signing out keeps',
      (tester) async {
        store.value = jsonEncode(
          SavedServer(
            endpoints: [Uri.parse('https://photos.example.org')],
            instance: 'instance-a',
            deviceId: 'device-1',
            deviceSecret: 'secret-1',
          ).toJson(),
        );
        server = FakeServer(
          login(
            finish: (_) => FinishLoginResponse(
              session: Session(
                token: 'token-2',
                deviceId: 'device-1',
                deviceSecret: 'secret-2',
              ),
            ),
          ),
        );
        await pumpServerApp(tester);
        await openServer(tester);
        await signIn(tester, 'ann', 'pw');
        final started = server
            .requests<StartLoginRequest>('AuthService/StartLogin')
            .single;
        expect(
          (started.deviceId, started.deviceSecret),
          ('device-1', 'secret-1'),
        );
        expect(
          server
              .requests<FinishLoginRequest>('AuthService/FinishLogin')
              .single
              .device
              .deviceId,
          'device-1',
        );
        await tester.tapAndSettle(find.text('Sign out'));
        expect(saved()!.account, isNull);
        expect(
          (saved()!.deviceId, saved()!.deviceSecret),
          ('device-1', 'secret-2'),
        );
      },
    );

    testWidgets('a server that takes passkeys only says it needs one', (
      tester,
    ) async {
      keep();
      server = FakeServer({
        'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
          epoch: 'instance-a.0',
          authMethods: [AuthMethod.AUTH_METHOD_PASSKEY],
        ),
      });
      await pumpServerApp(tester);
      await openServer(tester);
      expect(
        find.text(
          'This server requires a passkey, which this version of Photolib '
          'cannot use yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsNothing);
    });
  });

  group('a session', () {
    Future<void> console(WidgetTester tester) async {
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.scrollTo(find.text('Server administration'));
      await tester.tapAndSettle(find.text('Server administration'));
    }

    testWidgets(
      'kept from an earlier start opens the console without signing in',
      (tester) async {
        keep(ann);
        await pumpServerApp(tester);
        await console(tester);
        await tester.tapAndSettle(find.widgetWithText(ListTile, 'Overview'));
        expect(find.text('Usage by account'), findsOneWidget);
        expect(
          links.where((l) => l.$1.session == 'token-1').map((l) => l.$2),
          everyElement('instance-a'),
        );
        expect(
          server.requests<GeneratedMessage>('AuthService/StartLogin'),
          isEmpty,
        );
      },
    );

    for (final (name, Object answer, String? token) in [
      (
        'renews at a start once fewer than 60 days are left',
        RotateSessionResponse(
          session: Session(token: 'token-2', deviceId: 'device-1'),
        ),
        'token-2',
      ),
      ('is kept offline at start', Unreachable('offline'), 'token-1'),
      (
        'ends at start when the server refuses to renew it',
        refused('unauthenticated', 'session.required'),
        null,
      ),
    ]) {
      testWidgets(name, (tester) async {
        keep(
          ann.copyWith(expires: DateTime.now().add(const Duration(days: 59))),
        );
        server = FakeServer({'AuthService/RotateSession': (_) => answer});
        await pumpServerApp(tester);
        await tester.pumpAndSettle();
        expect(
          server.requests<RotateSessionRequest>('AuthService/RotateSession'),
          hasLength(1),
        );
        expect(links.first.$1.session, 'token-1');
        expect(saved()!.account?.token, token);
      });
    }

    testWidgets('ends when the console signs this device out', (tester) async {
      keep(ann);
      var revoked = false;
      Object answer(GeneratedMessage request, String method) => revoked
          ? refused('unauthenticated', 'session.required')
          : FakeServer.standard[method]?.call(request) ??
                ListDevicesResponse(
                  devices: [
                    Device(deviceId: 'device-1', name: 'phone', current: true),
                  ],
                );
      server = FakeServer({
        for (final method in [
          'AdminService/GetStatus',
          'AuthService/ListDevices',
        ])
          method: (request) => answer(request, method),
        'AuthService/RevokeDevice': (_) {
          revoked = true;
          return RevokeDeviceResponse();
        },
      });
      await pumpServerApp(tester);
      await console(tester);
      await tester.tapAndSettle(find.widgetWithText(ListTile, 'Your devices'));
      await tester.tapAndSettle(find.text('Sign out'));
      expect(saved()!.account, isNull);
      expect(find.text('You are signed out of the server.'), findsWidgets);
    });

    testWidgets('ends when the server revokes it, which the app says until '
        'the next sign-in, across a restart too', (tester) async {
      keep(ann);
      server = FakeServer({
        'AdminService/GetStatus': (_) =>
            refused('unauthenticated', 'session.required'),
      });
      await pumpServerApp(tester);
      await console(tester);
      expect(saved()!.account, isNull);
      expect(find.text('Sign in as an administrator'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('photos.example.org'), -100);
      await tester.pump();
      await tester.tapAndSettle(find.text('photos.example.org'));
      const ended = 'The server ended this session. Sign in again.';
      expect(find.text(ended), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpServerApp(tester);
      await openServer(tester);
      expect(find.text(ended), findsOneWidget);
    });

    for (final (name, error, says) in [
      (
        'an unreachable server',
        Unreachable('timeout'),
        'The server does not answer.',
      ),
      (
        "a proxy's 401 page",
        Unreachable('HTTP 401 text/html'),
        'The server does not answer.',
      ),
      (
        'an unauthenticated error without a reason',
        ServerError('unauthenticated', null),
        'You are signed out of the server.',
      ),
    ]) {
      testWidgets('outlives $name, which shows as offline (ADR-0032)', (
        tester,
      ) async {
        keep(ann);
        server = FakeServer({
          'AdminService/GetStatus': (_) => error,
          'ServerInfoService/GetServerInfo': (_) => Unreachable('offline'),
        });
        await pumpServerApp(tester);
        await console(tester);
        await tester.tapAndSettle(find.widgetWithText(ListTile, 'Overview'));
        expect(find.text(says), findsOneWidget);
        expect(saved()!.account?.token, 'token-1');
        for (var page = 0; page < 2; page++) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
        // The faces section lengthens the settings: back up to the server.
        await tester.scrollUntilVisible(find.text('photos.example.org'), -100);
        await tester.pump();
        await tester.tapAndSettle(find.text('photos.example.org'));
        expect(
          find.text('The server does not answer. You stay signed in.'),
          findsOneWidget,
        );
        expect(find.text('Signed in as ann'), findsOneWidget);
      });
    }

    testWidgets('kept for plain HTTP beyond the local networks says the '
        'server needs HTTPS there', (tester) async {
      keep(ann);
      server = FakeServer({
        'ServerInfoService/GetServerInfo': (_) => HttpsRequired(Uri()),
      });
      await pumpServerApp(tester);
      await openServer(tester);
      expect(find.text(needsHttps), findsOneWidget);
      expect(links.map((l) => l.$1.session), everyElement('token-1'));
      expect(saved()!.account?.token, 'token-1');
    });

    for (final online in [true, false]) {
      testWidgets('signing out revokes this device'
          '${online ? '' : ', and offline forgets it all the same'}', (
        tester,
      ) async {
        keep(ann);
        server = FakeServer({
          if (!online)
            'AuthService/RevokeDevice': (_) => Unreachable('offline'),
        });
        await pumpServerApp(tester);
        await openServer(tester);
        await tester.tapAndSettle(find.text('Sign out'));
        expect(
          server
              .requests<RevokeDeviceRequest>('AuthService/RevokeDevice')
              .single
              .deviceId,
          'device-1',
        );
        expect(saved()!.account, isNull);
        expect(find.text('Sign in'), findsOneWidget);
      });
    }

    testWidgets('removing the server signs out and forgets it', (tester) async {
      keep(ann);
      await pumpServerApp(tester);
      await openServer(tester);
      await tester.tapAndSettle(find.text('Remove this server'));
      expect(
        server.requests<GeneratedMessage>('AuthService/RevokeDevice'),
        hasLength(1),
      );
      expect(store.value, isNull);
      expect(find.text('Add a server'), findsOneWidget);
    });
  });
}
