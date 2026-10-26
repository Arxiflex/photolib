import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:protobuf/protobuf.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// A new server's first administrator, created with photolibd's setup token
/// (ADR-0125), and the cost of their password.
void main() {
  late FakeServer server;
  late MemoryStore store;
  late List<GeneratedMessage> steps;
  late List<Uint8List> stretched;
  late Duration Function(Uint8List params) stretch;
  setUp(() {
    server = FakeServer();
    store = MemoryStore();
    steps = [];
    stretched = [];
    stretch = (_) => const Duration(seconds: 1);
  });

  Future<void> pump(WidgetTester tester) => pumpApp(
    tester,
    serverStore: store,
    overrides: [
      connectProvider.overrideWithValue((config, instance) => server),
      certificateProvider.overrideWithValue((config, url) async => null),
      // Each step's message is its number.
      opaqueProvider.overrideWithValue((method, request) async {
        steps.add(request);
        return kernel.OpaqueClientResponse(message: [steps.length]);
      }),
      stretchProvider.overrideWithValue((params) async {
        stretched.add(params);
        return stretch(params);
      }),
    ],
  );

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  SavedServer? saved() => store.value == null
      ? null
      : Accounts.fromJson(jsonDecode(store.value!) as Map).server;

  void keep() => store.value = jsonEncode(
    SavedServer(
      endpoints: [Uri.parse('https://photos.example.org')],
      instance: 'instance-a',
    ).toJson(),
  );

  Future<void> openServer(WidgetTester tester) async {
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('photos.example.org'));
  }

  Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

  ServerError refused(String code, String reason) =>
      ServerError(code, ErrorDetail(code: reason));

  Map<String, Object Function(GeneratedMessage)> login() => {
    'AuthService/StartLogin': (_) => StartLoginResponse(
      loginId: 'login-1',
      ke2: [9],
      ksfParams: List.generate(26, (i) => i),
    ),
    'AuthService/FinishLogin': (_) => FinishLoginResponse(
      session: Session(token: 'token-1', deviceId: 'device-1', userId: 'u'),
    ),
  };

  group('setting up a new server', () {
    Map<String, Object Function(GeneratedMessage)> setup() => {
      'SetupService/CreateFirstAdmin': (_) => CreateFirstAdminResponse(
        user: User(handle: 'ann', role: UserRole.USER_ROLE_ADMIN),
        passwordSetup: PasswordSetup(token: 'setup-2'),
      ),
      'AuthService/StartPasswordSetup': (_) => StartPasswordSetupResponse(
        registrationResponse: [7],
        registrationId: [8],
      ),
      ...login(),
    };

    Future<void> create(
      WidgetTester tester, {
      String token = 'token-0',
      String again = 'correct horse',
    }) async {
      for (final (label, text) in [
        ('Setup token', token),
        ('Sign-in name', 'ann'),
        ('Name', 'Ann'),
        ('Email', 'ann@example.org'),
        ('Password', 'correct horse'),
        ('Password again', again),
      ]) {
        await tester.enterText(field(label), text);
      }
      await tester.tapAndSettle(find.text('Create administrator'));
    }

    Future<void> open(WidgetTester tester) async {
      keep();
      await pump(tester);
      await openServer(tester);
      await tester.tapAndSettle(find.text('Set up a new server'));
    }

    testWidgets(
      "creates the first administrator with photolibd's setup token, who "
      'sets a password and is signed in',
      (tester) async {
        server = FakeServer(setup());
        await open(tester);
        await create(tester);

        final created = server
            .requests<CreateFirstAdminRequest>('SetupService/CreateFirstAdmin')
            .single;
        expect(created.setupToken, 'token-0');
        expect(
          (created.user.handle, created.user.displayName, created.user.email),
          ('ann', 'Ann', 'ann@example.org'),
        );
        final [request, record] = steps
            .take(2)
            .cast<kernel.OpaqueRegisterRequest>()
            .toList();
        expect(request.password, 'correct horse');
        expect(request.randomness, hasLength(96));
        expect(record.randomness, request.randomness);
        expect(request.params.sublist(0, 10), [1, 0, 4, 0, 0, 0, 0, 0, 3, 1]);
        expect(request.params, hasLength(26));
        expect(record.params, request.params);
        expect(request.response, isEmpty);
        expect(record.response, [7]);
        final started = server
            .requests<StartPasswordSetupRequest>(
              'AuthService/StartPasswordSetup',
            )
            .single;
        expect(started.registrationRequest, [1]);
        expect(started.passwordSetupToken, 'setup-2');
        final finished = server
            .requests<FinishPasswordSetupRequest>(
              'AuthService/FinishPasswordSetup',
            )
            .single;
        expect(finished.registrationRecord, [2]);
        expect(finished.ksfParams, request.params);
        expect(finished.passwordSetupToken, 'setup-2');
        expect(finished.registrationId, [8]);
        expect(
          server
              .requests<StartLoginRequest>('AuthService/StartLogin')
              .single
              .handle,
          'ann',
        );
        expect(saved()!.account!.admin, isTrue);
        expect(find.text('Signed in as ann'), findsOneWidget);
      },
    );

    // docs/dev/crypto-v1.md: about a second here, from 256 MiB and t = 3, or
    // 128 MiB and t = 6 where 256 MiB cannot be had, within the policy.
    for (final (name, Duration Function(int mib) took, mib, t) in [
      ('a fast device takes more passes', (_) => ms(300), 256, 10),
      ('a slow one no fewer than three', (_) => ms(1500), 256, 3),
      ('the fastest at most 64', (_) => ms(10), 256, 64),
      (
        'one without 256 MiB takes 128 MiB and no fewer than six passes',
        (mib) => mib == 256 ? throw StateError('out of memory') : ms(400),
        128,
        15,
      ),
    ]) {
      testWidgets('a new password costs about a second here: $name', (
        tester,
      ) async {
        stretch = (params) =>
            took(ByteData.sublistView(params).getUint32(1) >> 10);
        server = FakeServer(setup());
        await open(tester);
        await create(tester);

        final request = steps.first as kernel.OpaqueRegisterRequest;
        final cost = ByteData.sublistView(Uint8List.fromList(request.params));
        expect((cost.getUint32(1) >> 10, cost.getUint32(5)), (mib, t));
        expect(request.params.sublist(10), stretched.first.sublist(10));
        expect(stretched.map((p) => p.sublist(1, 9)), [
          [0, 4, 0, 0, 0, 0, 0, 3],
          if (mib == 128) [0, 2, 0, 0, 0, 0, 0, 6],
        ]);
        expect(saved()!.account!.name, 'ann');
      });
    }

    testWidgets('a wrong setup token says where to find the right one', (
      tester,
    ) async {
      server = FakeServer({
        ...setup(),
        'SetupService/CreateFirstAdmin': (_) =>
            refused('permission_denied', 'setup.token_invalid'),
      });
      await open(tester);
      await create(tester, token: 'old');
      expect(find.text('This setup token is wrong.'), findsOneWidget);
      expect(
        find.text("Copy the newest one from photolibd's log."),
        findsOneWidget,
      );
      expect(saved()!.account, isNull);
    });

    testWidgets('trying again after the password failed to be set keeps the '
        'administrator created', (tester) async {
      var offline = true;
      server = FakeServer({
        ...setup(),
        'AuthService/StartPasswordSetup': (request) => offline
            ? Unreachable('timeout')
            : setup()['AuthService/StartPasswordSetup']!(request),
      });
      await open(tester);
      await create(tester);
      expect(find.text('The server does not answer.'), findsOneWidget);
      offline = false;
      await tester.tapAndSettle(find.text('Create administrator'));
      expect(
        server.requests<GeneratedMessage>('SetupService/CreateFirstAdmin'),
        hasLength(1),
      );
      expect(saved()!.account!.name, 'ann');
    });

    testWidgets('refuses passwords that differ and empty fields', (
      tester,
    ) async {
      await open(tester);
      await create(tester, token: '', again: 'correct horsf');
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('The passwords differ.'), findsOneWidget);
      expect(
        server.calls.map((c) => c.$1),
        isNot(contains('SetupService/CreateFirstAdmin')),
      );
    });
  });
}
