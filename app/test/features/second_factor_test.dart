import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/second_factor.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/server_app.dart';

void main() {
  setUpServerApp();

  Answers challenged(List<SecondFactor> factors, {String options = ''}) => {
    ...login(
      finish: (_) => FinishLoginResponse(
        secondFactor: SecondFactorChallenge(
          loginId: 'login-2',
          factors: factors,
          passkeyOptionsJson: options,
        ),
      ),
    ),
    'AuthService/FinishSecondFactor': (request) =>
        switch (request as FinishSecondFactorRequest) {
          FinishSecondFactorRequest(totpCode: '123456') ||
          FinishSecondFactorRequest(recoveryCode: 'abcd-efgh') ||
          FinishSecondFactorRequest(
            passkeyCredentialJson: '{"id":"c"}',
          ) => FinishSecondFactorResponse(
            session: Session(token: 'token-1', deviceId: 'device-1'),
          ),
          _ => refused('permission_denied', 'login.failed'),
        },
  };

  const both = [
    SecondFactor.SECOND_FACTOR_TOTP,
    SecondFactor.SECOND_FACTOR_RECOVERY_CODE,
  ];

  FinishSecondFactorRequest answered() => server
      .requests<FinishSecondFactorRequest>('AuthService/FinishSecondFactor')
      .last;

  Future<void> challenge(WidgetTester tester, Answers answers) async {
    keep();
    server = FakeServer(answers);
    await pumpServerApp(tester);
    await openServer(tester);
    await signIn(tester, 'ann', 'correct horse');
    expect(find.text("Confirm it's you"), findsOneWidget);
  }

  testWidgets('a password sign-in the server challenges takes a code from '
      'the authenticator app', (tester) async {
    await challenge(tester, challenged(both));
    await tester.enterText(field('Code from your authenticator app'), '123456');
    await tester.tapAndSettle(find.text('Confirm'));
    expect((answered().loginId, answered().totpCode), ('login-2', '123456'));
    expect(saved()!.account!.token, 'token-1');
    expect(find.text('Signed in as ann'), findsOneWidget);
  });

  testWidgets('or a recovery code', (tester) async {
    await challenge(tester, challenged(both));
    await tester.tapAndSettle(find.text('Use a recovery code instead'));
    await tester.enterText(field('Recovery code'), ' abcd-efgh ');
    await tester.tapAndSettle(find.text('Confirm'));
    expect(answered().recoveryCode, 'abcd-efgh');
    expect(saved()!.account, isNotNull);
  });

  testWidgets('a wrong code says so and may be tried again', (tester) async {
    await challenge(tester, challenged(both));
    await tester.enterText(field('Code from your authenticator app'), '000000');
    await tester.tapAndSettle(find.text('Confirm'));
    expect(
      find.text('That did not work. After five tries, sign in again.'),
      findsOneWidget,
    );
    expect(saved()!.account, isNull);
    await tester.enterText(field('Code from your authenticator app'), '123456');
    await tester.tapAndSettle(find.text('Confirm'));
    expect(saved()!.account, isNotNull);
  });

  testWidgets('a passkey answers through the relay in the system browser', (
    tester,
  ) async {
    final relayed = <(Uri, String, String)>[];
    keep();
    server = FakeServer(
      challenged([SecondFactor.SECOND_FACTOR_PASSKEY], options: '{"o":1}'),
    );
    await pumpServerApp(
      tester,
      overrides: [
        passkeyRelayProvider.overrideWithValue((
          page,
          options,
          label, {
          create = false,
        }) async {
          relayed.add((page, options, label));
          return '{"id":"c"}';
        }),
      ],
    );
    await openServer(tester);
    await signIn(tester, 'ann', 'correct horse');
    await tester.tapAndSettle(find.text('Use a passkey'));
    expect(relayed.single, (
      Uri.parse('https://photos.example.org/passkey'),
      '{"o":1}',
      'Use a passkey',
    ));
    expect(answered().passkeyCredentialJson, '{"id":"c"}');
    expect(saved()!.account, isNotNull);
  });

  testWidgets('where no relay can run, a passkey-only account is told why', (
    tester,
  ) async {
    keep();
    server = FakeServer(
      challenged([SecondFactor.SECOND_FACTOR_PASSKEY], options: '{"o":1}'),
    );
    await pumpServerApp(
      tester,
      overrides: [passkeyRelayProvider.overrideWithValue(null)],
    );
    await openServer(tester);
    await signIn(tester, 'ann', 'correct horse');
    expect(
      find.textContaining('which this version of Photolib cannot'),
      findsOneWidget,
    );
    expect(find.text('Use a passkey'), findsNothing);
  });

  group('the loopback relay', () {
    final page = Uri.parse('https://photos.example.org/base/passkey');

    Future<String> relay(Map<String, String> answer, {bool create = false}) =>
        loopbackRelay(
          page,
          '{"challenge":"x y"}',
          'Use a passkey',
          create: create,
          done: 'Done.',
          // A real client: the test binding's answers every request with a 400.
          open: (url) => HttpOverrides.runWithHttpOverrides(() async {
            expect(url.removeFragment(), page);
            final fragment = Uri.splitQueryString(url.fragment);
            expect(fragment['op'], create ? 'create' : 'get');
            expect(fragment['options'], '{"challenge":"x y"}');
            expect(fragment['label'], 'Use a passkey');
            final back = Uri.parse(fragment['return']!);
            expect((back.scheme, back.host), ('http', '127.0.0.1'));
            final client = HttpClient();
            // The browser asks for its icon first.
            final icon = await (await client.getUrl(
              back.resolve('/favicon.ico'),
            )).close();
            expect(icon.statusCode, 404);
            final response = await (await client.getUrl(
              back.replace(queryParameters: answer),
            )).close();
            expect(await utf8.decodeStream(response), contains('Done.'));
            client.close();
          }, _Network()),
        );

    test('hands back the credential the page returns to it', () async {
      expect(await relay({'credential': '{"id":"c"}'}), '{"id":"c"}');
    });

    test('runs a create ceremony when asked to', () async {
      expect(
        await relay({'credential': '{"id":"c"}'}, create: true),
        '{"id":"c"}',
      );
    });

    test('fails with the error the page returns', () async {
      await expectLater(
        relay({'error': 'NotAllowedError'}),
        throwsA(
          isA<PasskeyFailed>().having((e) => e.name, 'name', 'NotAllowedError'),
        ),
      );
    });
  });
}

class _Network extends HttpOverrides;
