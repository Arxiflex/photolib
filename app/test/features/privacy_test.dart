import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/privacy/privacy.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// The kernel's part, faked: an enrolment with a known kit, and a drill that
/// refuses as [refusal] says.
class _Custody implements Custody {
  final enrolled = <(String, String)>[];
  final opened = <String>[];
  KeyRefused? refusal;

  static final keys = CreateKeysRequest(identity: [1], signingKey: [8]);
  static final List<String> words = [for (var i = 1; i <= 24; i++) 'word$i'];

  @override
  Future<Enrolment> enrol(String user, String password) async {
    enrolled.add((user, password));
    return Enrolment(keys: keys, phrase: words.join(' '), kit: const [7, 7]);
  }

  @override
  Future<List<int>> openKit(String user, String phrase, List<int> wrap) async {
    opened.add(phrase);
    if (refusal case final refusal?) throw refusal;
    expect(wrap, [3], reason: 'the recovery path');
    return [9, 9];
  }
}

void main() {
  late FakeServer server;
  late _Custody custody;
  late List<GeneratedMessage> steps;
  late AccountKeys? stored;
  setUp(() {
    custody = _Custody();
    steps = [];
    stored = null;
    final at = Timestamp.fromDateTime(DateTime.utc(2026, 4, 1, 12));
    server = FakeServer({
      'KeyService/GetKeys': (_) =>
          GetKeysResponse(keys: stored, password: true, userId: 'user-1'),
      'KeyService/CreateKeys': (_) {
        stored = AccountKeys(
          paths: [
            UnlockPath(kind: UnlockKind.UNLOCK_KIND_PASSWORD),
            UnlockPath(kind: UnlockKind.UNLOCK_KIND_RECOVERY, wrap: [3]),
          ],
        );
        return CreateKeysResponse(keys: stored);
      },
      'KeyService/VerifyRecoveryKit': (_) {
        stored = stored!.deepCopy()
          ..recoveryVerifiedAt = at
          ..drillDueAt = Timestamp.fromDateTime(DateTime.utc(2026, 10, 2))
          ..ready = true;
        return VerifyRecoveryKitResponse(keys: stored);
      },
      'AuthService/StartLogin': (_) =>
          StartLoginResponse(loginId: 'login-1', ke2: [9]),
    });
  });

  Future<void> open(WidgetTester tester) async {
    final saved = SavedServer(
      endpoints: [Uri.parse('https://photos.example.org')],
      instance: 'instance-a',
      account: const Account(name: 'ann', token: 't', deviceId: 'd'),
    );
    await pumpApp(
      tester,
      serverStore: MemoryStore(jsonEncode(saved.toJson())),
      overrides: [
        connectProvider.overrideWithValue((config, instance) => server),
        custodyProvider.overrideWithValue(custody),
        // The kernel opens KE2 only with the password "right".
        opaqueProvider.overrideWithValue((method, request) async {
          steps.add(request);
          final password = (request as kernel.OpaqueLoginRequest).password;
          if (request.ke2.isNotEmpty && password != 'right') {
            throw KernelError(3, 'envelope_recovery');
          }
          return kernel.OpaqueClientResponse(message: [steps.length]);
        }),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Private libraries'));
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> press(WidgetTester tester, String label) =>
      tester.tapAndSettle(find.text(label));

  testWidgets('the setup says what losing the keys means, makes a kit and '
      'keeps private uploads off until words of it are typed again', (
    tester,
  ) async {
    await open(tester);
    expect(find.textContaining('your photos are lost for good'), findsOne);
    await tester.enterText(field('Password'), 'wrong');
    await press(tester, 'Set up');
    expect(find.text("This is not your account's password."), findsOne);
    expect(custody.enrolled, isEmpty, reason: 'no keys under a mistyped one');
    expect(
      server.requests<GeneratedMessage>('AuthService/FinishLogin'),
      isEmpty,
    );

    await tester.enterText(field('Password'), 'right');
    await press(tester, 'Set up');
    expect(custody.enrolled, [('user-1', 'right')]);
    expect(server.requests<CreateKeysRequest>('KeyService/CreateKeys'), [
      _Custody.keys,
    ]);
    for (final word in _Custody.words) {
      expect(find.text(word), findsOne);
    }
    await press(tester, 'I wrote them down');
    final asked = [
      for (var n = 1; n <= 24; n++)
        if (field('Word $n').evaluate().isNotEmpty) n,
    ];
    expect(asked, hasLength(3));
    for (final n in asked) {
      await tester.enterText(field('Word $n'), 'word${n + 1}');
    }
    await press(tester, 'Verify');
    expect(find.textContaining('do not match your recovery kit'), findsOne);
    expect(
      server.requests<GeneratedMessage>('KeyService/VerifyRecoveryKit'),
      isEmpty,
    );

    for (final n in asked) {
      await tester.enterText(field('Word $n'), ' WORD$n ');
    }
    await press(tester, 'Verify');
    expect(
      server.requests<VerifyRecoveryKitRequest>('KeyService/VerifyRecoveryKit'),
      [
        VerifyRecoveryKitRequest(kitId: [7, 7]),
      ],
    );
    expect(find.text('Private uploads are on.'), findsOne);
    expect(find.text('Recovery kit verified on Apr 1, 2026'), findsOne);
    expect(find.text('word1'), findsNothing, reason: 'the phrase is gone');
  });

  testWidgets('a drill takes the whole phrase, says which word is wrong and '
      'records the kit it opened', (tester) async {
    stored = AccountKeys(
      paths: [
        UnlockPath(kind: UnlockKind.UNLOCK_KIND_PASSWORD),
        UnlockPath(kind: UnlockKind.UNLOCK_KIND_RECOVERY, wrap: [3]),
      ],
      recoveryVerifiedAt: Timestamp(seconds: Int64(1700000000)),
      drillDueAt: Timestamp(seconds: Int64(1715000000)),
      ready: true,
    );
    await open(tester);
    expect(find.textContaining('Time for a recovery drill'), findsOne);
    expect(find.text('Password'), findsOne);
    expect(find.text('Recovery kit'), findsOne);
    await press(tester, 'Check recovery kit');
    custody.refusal = const KeyRefused('unknown_word', 7);
    await tester.enterText(field('Recovery phrase'), 'typed phrase');
    await press(tester, 'Verify');
    expect(find.text('Word 7 is not a recovery kit word.'), findsOne);
    custody.refusal = const KeyRefused('commitment_mismatch');
    await press(tester, 'Verify');
    expect(find.text('This is not your current recovery kit.'), findsOne);
    custody.refusal = null;
    await press(tester, 'Verify');
    expect(
      server.requests<VerifyRecoveryKitRequest>('KeyService/VerifyRecoveryKit'),
      [
        VerifyRecoveryKitRequest(kitId: [9, 9]),
      ],
    );
    expect(find.text('Your recovery kit works.'), findsOne);
    expect(custody.opened, ['typed phrase', 'typed phrase', 'typed phrase']);
  });

  test('the kernel wraps the identity and both paths under one master key, '
      "and only the kit's phrase opens the recovery path", () async {
    final custody = ProviderContainer().read(custodyProvider);
    const user = '01890a5d-ac96-774b-bcce-b302099a8057';
    final enrolment = await custody.enrol(user, 'correct horse');
    final keys = enrolment.keys;
    final [password, recovery] = keys.paths;
    // A PLW names its wrapping key in bytes 8 to 24 and the key it wraps in
    // 24 to 40 (docs/dev/crypto-v1.md).
    final amk = password.wrap.sublist(24, 40);
    expect(recovery.wrap.sublist(24, 40), amk);
    expect(keys.signingKey.sublist(8, 24), amk);
    expect(keys.decryptionKey.sublist(8, 24), amk);
    expect(recovery.wrap.sublist(8, 24), enrolment.kit);
    expect(password.params, hasLength(26));
    expect(utf8.decode(keys.identity.sublist(0, 3)), 'PLS');
    final words = enrolment.phrase.split(' ');
    expect(words, hasLength(24));
    final typed = '  ${enrolment.phrase.toUpperCase()}\n';
    expect(await custody.openKit(user, typed, recovery.wrap), enrolment.kit);
    Future<KeyRefused> refused(String phrase) async {
      try {
        await custody.openKit(user, phrase, recovery.wrap);
      } on KeyRefused catch (error) {
        return error;
      }
      fail('$phrase opened the kit');
    }

    final misspelt = [...words]..[6] = 'photolib';
    expect((await refused(misspelt.join(' '))).word, 7);
    final other = await custody.enrol(user, 'correct horse');
    expect((await refused(other.phrase)).reason, 'commitment_mismatch');
  });
}
