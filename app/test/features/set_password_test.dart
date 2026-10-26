import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/server_app.dart';

void main() {
  setUpServerApp();

  Future<void> setPassword(
    WidgetTester tester, {
    Map<String, String> fields = const {},
  }) async {
    await tester.tapAndSettle(find.text('Set a password'));
    for (final MapEntry(:key, :value) in {
      ...fields,
      'Password': 'correct horse',
      'Password again': 'correct horse',
    }.entries) {
      await tester.enterText(field(key), value);
    }
    await tester.tapAndSettle(find.text('Set password'));
  }

  testWidgets('a password setup token, from an administrator or from '
      'photolibd admin password-setup, sets a password and signs in', (
    tester,
  ) async {
    keep();
    server = FakeServer(setupAnswers());
    await pumpServerApp(tester);
    await openServer(tester);
    await setPassword(
      tester,
      fields: {
        'Password setup token': ' token-9 ',
        'Email or sign-in name': 'ann',
      },
    );
    final started = server
        .requests<StartPasswordSetupRequest>('AuthService/StartPasswordSetup')
        .single;
    expect(started.passwordSetupToken, 'token-9');
    expect(steps.first, isA<kernel.OpaqueRegisterRequest>());
    expect(
      server
          .requests<StartLoginRequest>('AuthService/StartLogin')
          .single
          .handle,
      'ann',
    );
    expect(saved()!.account!.name, 'ann');
    expect(find.text('Signed in as ann'), findsOneWidget);
  });

  testWidgets('a new password gets the Argon2id cost calibrated on this '
      'device', (tester) async {
    keep();
    server = FakeServer(setupAnswers());
    stretch = (params) => ByteData.sublistView(params).getUint32(1) > 128 << 10
        ? throw StateError('out of memory')
        : const Duration(milliseconds: 400);
    await pumpServerApp(tester);
    await openServer(tester);
    await setPassword(
      tester,
      fields: {'Password setup token': 't', 'Email or sign-in name': 'ann'},
    );
    final [request, record] = steps
        .take(2)
        .cast<kernel.OpaqueRegisterRequest>()
        .toList();
    expect(request.params.sublist(0, 10), [1, 0, 2, 0, 0, 0, 0, 0, 15, 1]);
    expect(record.params, request.params);
    expect(
      server
          .requests<FinishPasswordSetupRequest>(
            'AuthService/FinishPasswordSetup',
          )
          .single
          .ksfParams,
      request.params,
    );
  });

  testWidgets('a wrong or used token says so', (tester) async {
    keep();
    server = FakeServer({
      ...setupAnswers(),
      'AuthService/StartPasswordSetup': (_) =>
          refused('permission_denied', 'password_setup.invalid'),
    });
    await pumpServerApp(tester);
    await openServer(tester);
    await setPassword(
      tester,
      fields: {'Password setup token': 'old', 'Email or sign-in name': 'ann'},
    );
    expect(
      find.text(
        'This password setup token is wrong, used or expired. '
        'Ask for a new one.',
      ),
      findsOneWidget,
    );
    expect(saved()!.account, isNull);
  });

  testWidgets('setup that stopped before the password was set goes on after '
      'a restart with the token photolibd gave', (tester) async {
    keep();
    var offline = true;
    server = FakeServer({
      ...setupAnswers(),
      'AuthService/StartPasswordSetup': (request) => offline
          ? Unreachable('timeout')
          : setupAnswers()['AuthService/StartPasswordSetup']!(request),
    });
    await pumpServerApp(tester);
    await openServer(tester);
    await tester.tapAndSettle(find.text('Set up a new server'));
    for (final (label, text) in [
      ('Setup token', 'token-0'),
      ('Sign-in name', 'ann'),
      ('Name', 'Ann'),
      ('Password', 'correct horse'),
      ('Password again', 'correct horse'),
    ]) {
      await tester.enterText(field(label), text);
    }
    await tester.tapAndSettle(find.text('Create administrator'));
    expect(saved()!.account, isNull);

    offline = false;
    await tester.pumpWidget(const SizedBox()); // a restart
    await pumpServerApp(tester);
    await openServer(tester);
    await setPassword(tester);
    expect(
      server.requests<GeneratedMessage>('SetupService/CreateFirstAdmin'),
      hasLength(1),
    );
    expect(
      server
          .requests<StartPasswordSetupRequest>('AuthService/StartPasswordSetup')
          .last
          .passwordSetupToken,
      'setup-2',
    );
    expect(saved()!.account!.name, 'ann');
    expect(saved()!.setup, isNull);
  });
}
