import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/second_factor.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// The second factors page (ADR-0088) and its step-up (ADR-0242): a change the
/// server refuses with `step_up.required` asks for a proof and runs once more.
void main() {
  late FakeServer server;
  late List<GeneratedMessage> steps;
  late Map<String, int> refusals;

  ServerError refused(String code, String reason) =>
      ServerError(code, ErrorDetail(code: reason));

  /// Refuses [method] [times] times for want of a step-up, then answers it
  /// with [answer].
  Object Function(GeneratedMessage) stepped(
    String method,
    GeneratedMessage answer, {
    int times = 1,
  }) => (_) {
    final left = refusals.update(method, (n) => n - 1, ifAbsent: () => times);
    return left > 0 ? refused('permission_denied', 'step_up.required') : answer;
  };

  final params = List.generate(26, (i) => i);
  setUp(() {
    steps = [];
    refusals = {};
    server = FakeServer({
      'AuthService/ListSecondFactors': (_) => ListSecondFactorsResponse(
        passkeys: [Passkey(passkeyId: 'pk-1', name: "Ann's key")],
        totp: true,
        recoveryCodesLeft: 9,
      ),
      'AuthService/StartStepUp': (_) =>
          StartStepUpResponse(stepUpId: 'up-1', ke2: [9], ksfParams: params),
      'AuthService/DeletePasskey': stepped(
        'DeletePasskey',
        DeletePasskeyResponse(),
      ),
      'AuthService/DeleteTotp': stepped('DeleteTotp', DeleteTotpResponse()),
      'AuthService/CreateRecoveryCodes': stepped(
        'CreateRecoveryCodes',
        CreateRecoveryCodesResponse(recoveryCodes: ['aaaa-bbbb', 'cccc-dddd']),
      ),
      'AuthService/StartTotpSetup': stepped(
        'StartTotpSetup',
        StartTotpSetupResponse(setupId: 'totp-1', secret: 'JBSWY3DPEHPK3PXP'),
      ),
    });
  });

  Future<void> open(
    WidgetTester tester, {
    bool console = false,
    List<Uri>? endpoints,
    PasskeyRelay? relay,
  }) async {
    final store = MemoryStore()
      ..value = jsonEncode(
        SavedServer(
          endpoints: endpoints ?? [Uri.parse('https://photos.example.org')],
          instance: 'instance-a',
          account: const Account(
            name: 'ann',
            token: 'token-1',
            deviceId: 'device-1',
            admin: true,
          ),
        ).toJson(),
      );
    await pumpApp(
      tester,
      serverStore: store,
      overrides: [
        connectProvider.overrideWithValue((config, instance) => server),
        opaqueProvider.overrideWithValue((method, request) async {
          steps.add(request);
          return kernel.OpaqueClientResponse(message: [steps.length]);
        }),
        passkeyRelayProvider.overrideWithValue(relay),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    final entry = find.text(
      console
          ? 'Server administration'
          : (endpoints?.first.host ?? 'photos.example.org'),
    );
    await tester.scrollTo(entry);
    await tester.tapAndSettle(entry);
    await tester.tapAndSettle(find.text('Second factors'));
  }

  /// Answers the prompt with [password] or [code].
  Future<void> prove(
    WidgetTester tester, {
    String password = '',
    String code = '',
  }) async {
    expect(find.text("Confirm it's you"), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      password,
    );
    await tester.enterText(find.widgetWithText(TextField, 'Code'), code);
    await tester.tapAndSettle(find.text('OK'));
  }

  List<String> called() => [for (final (method, _) in server.calls) method];

  for (final console in [false, true]) {
    testWidgets(
      'removing a passkey on the ${console ? "admin console's" : "server's"} '
      'page asks for the password when the server wants a proof, '
      'proves the session with OPAQUE and tries once more',
      (tester) async {
        await open(tester, console: console);
        expect(find.text("Ann's key"), findsOneWidget);
        expect(find.text('Unused: 9'), findsOneWidget);
        await tester.tapAndSettle(find.byTooltip('Remove passkey'));
        await prove(tester, password: 'correct horse');

        final [ke1, ke3] = steps.cast<kernel.OpaqueLoginRequest>();
        expect(
          [ke1.password, ke3.password],
          ['correct horse', 'correct horse'],
        );
        expect(ke1.ke2, isEmpty);
        expect(ke3.ke2, [9]);
        expect(ke3.params, params);
        final started = server.requests<StartStepUpRequest>(
          'AuthService/StartStepUp',
        );
        expect(started.single.ke1, [1]);
        final finished = server.requests<FinishStepUpRequest>(
          'AuthService/FinishStepUp',
        );
        expect(finished.single.stepUpId, 'up-1');
        expect(finished.single.ke3, [2]);
        final removed = server.requests<DeletePasskeyRequest>(
          'AuthService/DeletePasskey',
        );
        expect(removed.map((r) => r.passkeyId), ['pk-1', 'pk-1']);
        expect(
          called().where((m) => m == 'AuthService/ListSecondFactors'),
          hasLength(2),
          reason: 'the page loads again',
        );
        expect(find.text("Confirm it's you"), findsNothing);
      },
    );
  }

  testWidgets('six digits prove the session as an authenticator code, '
      'anything else as a recovery code', (tester) async {
    await open(tester);
    await tester.tapAndSettle(find.text('Turn off'));
    await prove(tester, code: ' 123456 ');
    await tester.tapAndSettle(find.text('New codes'));
    await prove(tester, code: 'eeee-ffff');

    final [totp, recovery] = server.requests<FinishStepUpRequest>(
      'AuthService/FinishStepUp',
    );
    expect((totp.totpCode, totp.hasRecoveryCode()), ('123456', false));
    expect(
      (recovery.recoveryCode, recovery.hasTotpCode()),
      ('eeee-ffff', false),
    );
    expect(steps, isEmpty, reason: 'no password, no OPAQUE');
    expect(
      server.requests<StartStepUpRequest>('AuthService/StartStepUp').first.ke1,
      isEmpty,
    );
    expect(called().where((m) => m == 'AuthService/DeleteTotp'), hasLength(2));
    expect(find.text('Recovery codes'), findsWidgets);
    expect(find.text('aaaa-bbbb\ncccc-dddd'), findsOneWidget);
  });

  testWidgets('cancelling the prompt changes nothing and tries no more', (
    tester,
  ) async {
    await open(tester);
    await tester.tapAndSettle(find.text('Turn off'));
    await tester.tapAndSettle(find.text('Cancel'));
    expect(called(), isNot(contains('AuthService/StartStepUp')));
    expect(called().where((m) => m == 'AuthService/DeleteTotp'), hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a wrong password says so and keeps the prompt open', (
    tester,
  ) async {
    server.answers['AuthService/FinishStepUp'] = (_) =>
        refused('permission_denied', 'login.failed');
    await open(tester);
    await tester.tapAndSettle(find.text('Turn off'));
    await prove(tester, password: 'wrong');
    expect(find.text('Wrong password or code.'), findsOneWidget);
    expect(find.text("Confirm it's you"), findsOneWidget);
    expect(called().where((m) => m == 'AuthService/DeleteTotp'), hasLength(1));
  });

  testWidgets(
    'a change refused again after a proof is not retried a second time',
    (tester) async {
      server.answers['AuthService/DeleteTotp'] = stepped(
        'DeleteTotp',
        DeleteTotpResponse(),
        times: 2,
      );
      await open(tester);
      await tester.tapAndSettle(find.text('Turn off'));
      await prove(tester, code: '123456');
      expect(
        called().where((m) => m == 'AuthService/DeleteTotp'),
        hasLength(2),
      );
      expect(find.text("Confirm it's you"), findsNothing);
      expect(
        find.text(
          'This change needs your password or a code first. Try again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('setting up the authenticator app again asks for a proof, '
      'then shows the key and takes its code', (tester) async {
    server.answers['AuthService/FinishTotpSetup'] = (request) =>
        (request as FinishTotpSetupRequest).code == '654321'
        ? FinishTotpSetupResponse()
        : refused('invalid_argument', 'field.invalid');
    await open(tester);
    await tester.tapAndSettle(find.text('Set up'));
    await prove(tester, code: '123456');
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    final code = find.widgetWithText(TextField, 'Code');
    await tester.enterText(code, '000000');
    await tester.tapAndSettle(find.text('OK'));
    expect(find.text('That code is wrong.'), findsOneWidget);
    await tester.enterText(code, '654321');
    await tester.tapAndSettle(find.text('OK'));
    final finished = server.requests<FinishTotpSetupRequest>(
      'AuthService/FinishTotpSetup',
    );
    expect(finished.last.setupId, 'totp-1');
    expect(find.text('JBSWY3DPEHPK3PXP'), findsNothing);
    expect(find.text('Recovery codes'), findsOneWidget, reason: 'none new');
  });

  const creation = '{"rp":{"id":"photos.example.org","name":"Photolib"}}';

  testWidgets('adding a passkey on a desktop asks for a proof when the server '
      'wants one, then runs a create ceremony on the relay of the address '
      'passkeys bind to and shows the first recovery codes', (tester) async {
    server.answers['AuthService/StartPasskeySetup'] = stepped(
      'StartPasskeySetup',
      StartPasskeySetupResponse(setupId: 'setup-1', optionsJson: creation),
    );
    server.answers['AuthService/FinishPasskeySetup'] = (_) =>
        FinishPasskeySetupResponse(recoveryCodes: ['gggg-hhhh']);
    final relayed = <(Uri, String, String, bool)>[];
    await open(
      tester,
      endpoints: [
        Uri.parse('http://192.168.1.5:8080'),
        Uri.parse('https://photos.example.org/base/'),
      ],
      relay: (page, options, label, {create = false}) async {
        relayed.add((page, options, label, create));
        return '{"id":"c"}';
      },
    );
    await tester.tapAndSettle(find.text('Add a passkey'));
    await prove(tester, code: '123456');

    expect(relayed.single, (
      Uri.parse('https://photos.example.org/base/passkey'),
      creation,
      'Add a passkey',
      true,
    ));
    final added = server.requests<FinishPasskeySetupRequest>(
      'AuthService/FinishPasskeySetup',
    );
    expect(
      (added.single.setupId, added.single.credentialJson),
      ('setup-1', '{"id":"c"}'),
    );
    expect(added.single.name, isNotEmpty);
    expect(find.text('gggg-hhhh'), findsOneWidget);
  });

  testWidgets('a passkey the browser did not create adds none and says so', (
    tester,
  ) async {
    server.answers['AuthService/StartPasskeySetup'] = (_) =>
        StartPasskeySetupResponse(setupId: 'setup-1', optionsJson: creation);
    await open(
      tester,
      relay: (_, _, _, {create = false}) async =>
          throw const PasskeyFailed('NotAllowedError'),
    );
    await tester.tapAndSettle(find.text('Add a passkey'));
    expect(find.text('No passkey was added.'), findsOneWidget);
    expect(called(), isNot(contains('AuthService/FinishPasskeySetup')));
  });

  testWidgets('where no relay can run, no passkey is offered to add', (
    tester,
  ) async {
    await open(tester);
    expect(find.text("Ann's key"), findsOneWidget);
    expect(find.text('Add a passkey'), findsNothing);
  });
}
