import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// A password sign-in that the server answers with a second factor challenge
/// (ADR-0088).
void main() {
  late FakeServer server;
  late MemoryStore store;
  setUp(
    () => store = MemoryStore()
      ..value = jsonEncode(
        SavedServer(
          endpoints: [Uri.parse('https://photos.example.org')],
          instance: 'instance-a',
        ).toJson(),
      ),
  );

  Future<void> pump(WidgetTester tester) => pumpApp(
    tester,
    serverStore: store,
    overrides: [
      connectProvider.overrideWithValue((config, instance) => server),
      certificateProvider.overrideWithValue((config, url) async => null),
      opaqueProvider.overrideWithValue(
        (method, request) async => kernel.OpaqueClientResponse(message: [1]),
      ),
    ],
  );

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  SavedServer? saved() => store.value == null
      ? null
      : Accounts.fromJson(jsonDecode(store.value!) as Map).server;

  Future<void> signIn(WidgetTester tester) async {
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('photos.example.org'));
    await tester.enterText(field('Email or sign-in name'), 'ann');
    await tester.enterText(field('Password'), 'pw');
    await tester.tapAndSettle(find.text('Sign in'));
  }

  testWidgets(
    'an authenticator or recovery code answers the second factor a password '
    'sign-in asks for, and a wrong one may be tried again',
    (tester) async {
      server = FakeServer({
        'AuthService/StartLogin': (_) => StartLoginResponse(
          loginId: 'login-1',
          ke2: [9],
          ksfParams: List.generate(26, (i) => i),
        ),
        'AuthService/FinishLogin': (_) => FinishLoginResponse(
          secondFactor: SecondFactorChallenge(
            loginId: 'login-2',
            factors: [
              SecondFactor.SECOND_FACTOR_TOTP,
              SecondFactor.SECOND_FACTOR_RECOVERY_CODE,
            ],
          ),
        ),
        'AuthService/FinishSecondFactor': (request) =>
            (request as FinishSecondFactorRequest).totpCode == '123456'
            ? FinishSecondFactorResponse(
                session: Session(token: 'token-2', deviceId: 'device-2'),
              )
            : ServerError(
                'permission_denied',
                ErrorDetail(code: 'login.failed'),
              ),
      });
      await pump(tester);
      await signIn(tester);
      expect(
        find.text(
          'This account also needs a code from your authenticator app, '
          'or a recovery code.',
        ),
        findsOneWidget,
      );
      expect(saved()!.account, isNull);
      final code = field('Code from your authenticator app');
      await tester.enterText(code, 'aaaa-bbbb');
      await tester.tapAndSettle(find.text('Confirm'));
      expect(
        find.text('That did not work. After five tries, sign in again.'),
        findsOneWidget,
      );
      await tester.enterText(code, ' 123456 ');
      await tester.tapAndSettle(find.text('Confirm'));

      final answers = server.requests<FinishSecondFactorRequest>(
        'AuthService/FinishSecondFactor',
      );
      expect(
        [for (final a in answers) (a.loginId, a.totpCode, a.recoveryCode)],
        [('login-2', '', 'aaaa-bbbb'), ('login-2', '123456', '')],
      );
      expect(
        server.requests<GeneratedMessage>('AuthService/StartLogin'),
        hasLength(1),
      );
      expect(saved()!.account!.token, 'token-2');
      expect(find.text('Signed in as ann'), findsOneWidget);
    },
  );
}
