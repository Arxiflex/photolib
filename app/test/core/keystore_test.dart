import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide LockState;
import 'package:photolib/app.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// libsecret's answer on Linux without a Secret Service (no D-Bus session).
final _noBus = PlatformException(
  code: 'Libsecret error',
  message:
      'secret_service_get_sync: Failed to execute child process '
      '“dbus-launch” (No such file or directory)',
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('keystore-'));
  tearDown(() => dir.deleteSync(recursive: true));

  final asked = <bool>[];
  setUp(asked.clear);
  PassphraseKeystore passphrase() => PassphraseKeystore(
    storeFiles(dir.path),
    Kernel().keyring,
    ({required create, required retry}) async {
      asked.add(create);
      return 'correct horse battery';
    },
  );

  void answer(PlatformException? error) => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        error == null ? null : (call) => throw error,
      );

  /// The app support directory in [dir] and a platform keystore holding
  /// [keychain], else one that answers as Linux without a Secret Service.
  void platform(WidgetTester tester, [Map<String, String>? keychain]) {
    final messenger = tester.binding.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const storage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    messenger
      ..setMockMethodCallHandler(paths, (call) async => dir.path)
      ..setMockMethodCallHandler(storage, (call) async {
        final arguments = call.arguments as Map;
        final key = arguments['key'] as String;
        return switch ((call.method, keychain)) {
          (_, null) => throw PlatformException(code: 'Libsecret error'),
          ('read', final held?) => held[key],
          ('write', final held?) => held[key] = arguments['value'] as String,
          ('delete', final held?) => held.remove(key),
          _ => throw MissingPluginException(call.method),
        };
      });
    addTearDown(() {
      for (final channel in [paths, storage]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
  }

  /// The app at a start: its store and server, the passphrase answered.
  ProviderContainer start() {
    final app = ProviderContainer(
      retry: retry,
      overrides: [
        connectProvider.overrideWithValue(
          (config, instance) => FakeServer({
            'AuthService/StartLogin': (_) => StartLoginResponse(),
            'AuthService/FinishLogin': (_) => FinishLoginResponse(
              session: Session(token: 'token-1', deviceId: 'device-1'),
            ),
          }),
        ),
        opaqueProvider.overrideWithValue(
          (method, request) async => kernel.OpaqueClientResponse(),
        ),
      ],
    );
    addTearDown(app.dispose);
    app.listen(passphrasePromptProvider, (_, prompt) {
      prompt?.answer.complete('correct horse battery');
    });
    return app;
  }

  String stored() => [
    for (final file in dir.listSync(recursive: true))
      if (file is File) latin1.decode(file.readAsBytesSync()),
  ].join();

  test(
    'a keyring that does not answer or stays locked is unavailable',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      addTearDown(() => answer(null));
      final locked = PlatformException(code: 'KeyringLocked');
      for (final error in [_noBus, locked]) {
        answer(error);
        for (final call in [
          () => SecureStorageKeystore().read('dev'),
          () => SecureStorageKeystore().create('dev'),
          () => const KeystoreEntry('server').write('x'),
          () => FallbackKeystore(
            SecureStorageKeystore(),
            passphrase(),
          ).read('dev'),
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<KeystoreUnavailable>().having(
                (e) => e.cause.code,
                'code',
                error.code,
              ),
            ),
          );
        }
      }
      expect(asked, isEmpty);
      answer(PlatformException(code: 'Bad arguments'));
      await expectLater(
        SecureStorageKeystore().read('dev'),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  testWidgets('without a keyring the library says so, once, and tries again '
      'when asked', (tester) async {
    var opens = 0;
    await pumpApp(
      tester,
      replica: (_) {
        opens++;
        return Future<Replica>.error(KeystoreUnavailable(_noBus));
      },
    );
    expect(find.textContaining('GNOME Keyring or KWallet'), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    expect(opens, 1);
    await tester.tapAndSettle(find.text('Try again'));
    expect(opens, 2);
  });

  testWidgets('a store that does not open for another reason says the '
      'library could not open, and tries again when asked', (tester) async {
    var opens = 0;
    await pumpApp(
      tester,
      replica: (_) {
        opens++;
        return Future<Replica>.error(
          StateError('the keystore key of the store is gone'),
        );
      },
    );
    expect(
      find.text('Photolib could not open the library kept on this device'),
      findsOneWidget,
    );
    expect(find.text('Your photos will appear here'), findsNothing);
    await tester.tapAndSettle(find.text('Try again'));
    expect(opens, 2);
  });

  group('Linux keyring', () {
    test('keys stay in the Secret Service while one runs', () async {
      final service = MemoryKeystore();
      final key = await FallbackKeystore(service, passphrase()).create('dev');
      expect(service.keys['dev'], key);
      expect(asked, isEmpty);
    });

    test('without a Secret Service, keys are sealed under a passphrase, and '
        'stay there once one runs', () async {
      final key = await FallbackKeystore(
        const _NoService(),
        passphrase(),
      ).create('dev');
      expect(asked, [true]);

      final service = MemoryKeystore();
      expect(await FallbackKeystore(service, passphrase()).read('dev'), key);
      expect(service.keys, isEmpty);
      expect(asked, [true, false]);
    });

    test('a store whose keys the Secret Service holds does not open while '
        'it is away, and asks for no passphrase', () async {
      await expectLater(
        FallbackKeystore(const _NoService(), passphrase()).read('dev'),
        throwsA(isA<PlatformException>()),
      );
      expect(asked, isEmpty);
    });

    test('a locked keyring is no missing one', () async {
      await expectLater(
        FallbackKeystore(
          const _NoService('KeyringLocked'),
          passphrase(),
        ).create('dev'),
        throwsA(isA<PlatformException>()),
      );
      expect(asked, isEmpty);
    });
  });

  testWidgets('on Linux without a Secret Service the store opens under the '
      'passphrase the user chose', (tester) async {
    platform(tester);
    final vault = await tester.runAsync(
      () => start()
          .read(vaultProvider.future)
          .timeout(const Duration(seconds: 30)),
    );
    expect(vault!.state, LockState.unlocked);
    expect(File('${dir.path}/store/keystore').existsSync(), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('on Linux without a Secret Service the server and its session '
      'are kept, sealed in the store', (tester) async {
    platform(tester);
    final app = start();
    const saved = '{"session":"s3cr3t-token"}';
    final read = await tester.runAsync(() async {
      await app.read(serverStoreProvider).write(saved);
      return await app.read(serverStoreProvider).read();
    });
    expect(read, saved);
    expect(stored(), isNot(contains('s3cr3t-token')));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  group('the server and its session', () {
    testWidgets(
      'on Linux without a Secret Service, a sign-in is kept sealed in the '
      'store across a restart',
      (tester) async {
        platform(tester);
        final account = await tester.runAsync(() async {
          final first = start();
          await first.read(accountsProvider.future);
          final servers = first.read(accountsProvider.notifier);
          await servers.add(
            SavedServer(
              endpoints: [Uri.parse('https://photos.example.org')],
              instance: 'instance-a',
            ),
          );
          await servers.signIn('ann', 'correct horse');
          first.dispose();
          return (await start().read(accountsProvider.future)).server?.account;
        });
        expect((account?.name, account?.token), ('ann', 'token-1'));
        expect(
          stored(),
          allOf(
            isNot(contains('token-1')),
            isNot(contains('photos.example.org')),
          ),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('one an earlier build kept in the keystore moves into the '
        'store, which reads it while locked too', (tester) async {
      final keychain = {
        'photolib.keystore.server': jsonEncode(
          SavedServer(
            endpoints: [Uri.parse('https://photos.example.org')],
            instance: 'instance-a',
            account: const Account(
              name: 'ann',
              token: 'token-1',
              deviceId: 'device-1',
            ),
          ).toJson(),
        ),
      };
      platform(tester, keychain);
      final tokens = await tester.runAsync(
        () async => [
          for (final locked in [false, true])
            await () async {
              final app = start();
              if (locked) await (await app.read(vaultProvider.future)).lock();
              final server = (await app.read(accountsProvider.future)).server;
              app.dispose();
              return server?.account?.token;
            }(),
        ],
      );
      expect(tokens, ['token-1', 'token-1']);
      expect(keychain.keys, isNot(contains('photolib.keystore.server')));
      expect(stored(), isNot(contains('token-1')));
    });
  });

  group('the passphrase prompt', () {
    late Future<String> answer;
    Future<void> ask(
      WidgetTester tester, {
      required bool create,
      bool retry = false,
    }) async {
      await pumpApp(tester, size: const Size(1000, 700));
      answer =
          ProviderScope.containerOf(tester.element(find.byType(PhotolibApp)))
              .read(passphrasePromptProvider.notifier)
              .ask(create: create, retry: retry);
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester, List<String> typed) async {
      for (final (i, text) in typed.indexed) {
        await tester.enterText(find.byType(TextField).at(i), text);
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('a new passphrase is typed twice, 10 characters at least', (
      tester,
    ) async {
      await ask(tester, create: true);
      expect(find.textContaining('runs no keyring'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));

      await submit(tester, ['too short', 'too short']);
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      await submit(tester, ['correct horse battery', 'correct horse']);
      expect(find.text('The passphrases differ.'), findsOneWidget);
      await submit(tester, ['correct horse battery', 'correct horse battery']);

      expect(await answer, 'correct horse battery');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the passphrase is asked again after a wrong one', (
      tester,
    ) async {
      await ask(tester, create: false, retry: true);
      expect(find.text('Wrong passphrase. Try again.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await submit(tester, ['correct horse battery']);
      expect(await answer, 'correct horse battery');
    });
  });
}

/// A desktop whose Secret Service does not answer, as libsecret reports it.
class _NoService implements DeviceKeystore {
  const new([this.code = 'Libsecret error']);

  final String code;

  Never _fail() => throw PlatformException(
    code: code,
    message: 'Failed to execute child process "dbus-launch"',
  );

  @override
  Future<Uint8List?> read(String name) async => _fail();

  @override
  Future<Uint8List> create(String name) async => _fail();

  @override
  Future<void> delete(String name) async => _fail();
}
