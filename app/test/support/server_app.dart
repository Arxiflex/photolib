import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError, Replica;
import 'package:protobuf/protobuf.dart';

import 'fake_server.dart';
import 'pump_app.dart';

/// The server every link of the app reaches; a test replaces it.
late FakeServer server;

/// The store's object of the server and its session (ADR-0209).
late MemoryStore store;

/// The configuration and instance of every link the app opened.
late List<(NetworkConfig, String?)> links;

/// The requests of the kernel's OPAQUE steps.
late List<GeneratedMessage> steps;

/// The Argon2id parameters enrolment timed, each taking a second.
late List<Uint8List> stretched;

/// The fingerprint of a certificate the device does not trust, if any.
String? untrusted;

/// What the kernel throws at the second OPAQUE step, if anything.
KernelError? refusal;

/// How long an Argon2id derivation with these parameters takes here.
late Duration Function(Uint8List params) stretch;

/// The answers of a [FakeServer] by `Service/Method`.
typedef Answers = Map<String, Object Function(GeneratedMessage)>;

/// Starts each test with a [FakeServer] and an empty store.
void setUpServerApp() => setUp(() {
  server = FakeServer();
  store = MemoryStore();
  links = [];
  steps = [];
  stretched = [];
  untrusted = null;
  refusal = null;
  stretch = (_) => const Duration(seconds: 1);
});

/// The app, reaching [server] through every link, with a kernel whose OPAQUE
/// steps answer with their number.
Future<void> pumpServerApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Replica? replica,
}) => pumpApp(
  tester,
  serverStore: store,
  replica: replica == null ? null : (_) => replica,
  overrides: [
    connectProvider.overrideWithValue((config, instance) {
      links.add((config, instance));
      return server;
    }),
    certificateProvider.overrideWithValue((config, url) async => untrusted),
    // The second login step throws [refusal], as the kernel does for a wrong
    // password.
    opaqueProvider.overrideWithValue((method, request) async {
      steps.add(request);
      if (refusal case final refusal? when steps.length == 2) throw refusal;
      return kernel.OpaqueClientResponse(message: [steps.length]);
    }),
    stretchProvider.overrideWithValue((params) async {
      stretched.add(params);
      return stretch(params);
    }),
    ...overrides,
  ],
);

/// The text field labelled [label].
Finder field(String label) => find.widgetWithText(TextFormField, label);

/// The accounts the store holds.
Accounts accounts() => switch (store.value) {
  final json? => Accounts.fromJson(jsonDecode(json) as Map),
  null => const Accounts([]),
};

/// The server in use the store holds.
SavedServer? saved() => accounts().server;

/// Keeps a server, signed in as [account], in the store.
void keep([Account? account]) => store.value = jsonEncode(
  SavedServer(
    endpoints: [Uri.parse('https://photos.example.org')],
    instance: 'instance-a',
    account: account,
  ).toJson(),
);

/// When a renewed session ends.
final renewed = DateTime.utc(2099);

/// An administrator.
final ann = Account(
  name: 'ann',
  token: 'token-1',
  deviceId: 'device-1',
  admin: true,
  expires: renewed,
);

/// Opens the server's page from the settings.
Future<void> openServer(WidgetTester tester) async {
  await tester.tapAndSettle(find.byTooltip('Settings'));
  await tester.tapAndSettle(find.text('photos.example.org'));
}

/// Signs in on the server's page.
Future<void> signIn(
  WidgetTester tester,
  String account,
  String password,
) async {
  await tester.enterText(field('Email or sign-in name'), account);
  await tester.enterText(field('Password'), password);
  await tester.tapAndSettle(find.text('Sign in'));
}

/// photolibd's refusal with [reason].
ServerError refused(String code, String reason) =>
    ServerError(code, ErrorDetail(code: reason));

/// The Argon2id parameters the server sends.
final List<int> params = List.generate(26, (i) => i);

/// A server whose password sign-in opens a session, or answers [finish].
Answers login({Object Function(GeneratedMessage)? finish}) => {
  'AuthService/StartLogin': (_) =>
      StartLoginResponse(loginId: 'login-1', ke2: [9], ksfParams: params),
  'AuthService/FinishLogin':
      finish ??
      (_) => FinishLoginResponse(
        session: Session(token: 'token-1', deviceId: 'device-1', userId: 'u'),
      ),
};

/// A new server: CreateFirstAdmin makes ann with the password setup token
/// `setup-2`, and her password is set and signs in.
Answers setupAnswers() => {
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
