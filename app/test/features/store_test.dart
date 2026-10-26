import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/settings/store.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../support/pump_app.dart';

void main() {
  late Directory dir;
  late MemoryKeystore keystore;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('store');
    keystore = MemoryKeystore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Vault> open() async => Vault(
    location: dir.path,
    keystore: keystore,
    files: storeFiles(dir.path),
    keyring: Kernel().keyring,
  );

  // The vault's file and keystore I/O needs real time, which a widget test
  // gives only in runAsync: alternates it with frames until [done], as long
  // as a loaded machine takes.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    await tester.pumpUntil(done);
    await tester.pump();
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<Override> overrides,
  ) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        vaultOpenerProvider.overrideWithValue(open),
        settingsStoreProvider.overrideWithValue(MemoryStore()),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: StoreBanner()),
        ),
      ),
    );
    return container;
  }

  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('a store whose keystore lost its key waits for its recovery '
      'code: a wrong one is refused, the right one opens it', (tester) async {
    final code = (await tester.runAsync(() async {
      final vault = await open();
      await vault.unlock();
      final code = await vault.addRecoveryCode();
      await vault.lock();
      await keystore.delete('dev');
      return code;
    }))!;
    final container = await pump(tester, [
      recoveryOfferProvider.overrideWith((ref) async => null),
    ]);
    await settle(tester, () => container.read(vaultProvider).hasError);
    expect(find.text(en.storeRecoveryNeeded), findsOneWidget);

    await tester.tap(find.text(en.recoveryCodeEnter));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      recoveryWords(Uint8List(32)),
    );
    await tester.tap(find.text(en.recoveryUnlock));
    await settle(
      tester,
      () => find.text(en.recoveryWrong).evaluate().isNotEmpty,
    );

    await tester.enterText(find.byType(TextField), code.toUpperCase());
    await tester.tap(find.text(en.recoveryUnlock));
    await settle(tester, () => container.read(vaultProvider).hasValue);
    await tester.pumpAndSettle();
    expect(find.text(en.storeRecoveryNeeded), findsNothing);
    expect(container.read(vaultProvider).value!.rebuilt, isFalse);
    expect(keystore.keys, contains('dev'));
    await tester.runAsync(container.read(vaultProvider).value!.lock);
  });

  testWidgets('a store rebuilt for want of its key says what was lost, until '
      'the user has read it', (tester) async {
    await tester.runAsync(() async {
      final vault = await open();
      await vault.unlock();
      await vault.lock();
      await keystore.delete('dev');
    });
    final container = await pump(tester, [
      recoveryOfferProvider.overrideWith((ref) async => null),
    ]);
    await settle(tester, () => container.read(vaultProvider).hasValue);
    expect(find.text(en.storeRebuilt), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text(en.storeRebuilt), findsNothing);
    await tester.runAsync(container.read(vaultProvider).value!.lock);
  });

  testWidgets('without a keystore the store stays shut, naming the keyrings '
      'on Linux', (tester) async {
    for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      await pump(tester, [
        vaultProvider.overrideWith(
          (ref) => Future.error(PlatformException(code: 'Libsecret error')),
        ),
      ]);
      await tester.pump();
      expect(
        find.text(
          platform == TargetPlatform.linux
              ? en.storeNoKeyring
              : en.storeNoKeystore,
        ),
        findsOneWidget,
      );
      expect(find.text(en.errorRetry), findsOneWidget);
    }
    debugDefaultTargetPlatformOverride = null;
    expect(en.storeNoKeyring, contains('gnome-keyring, KWallet or KeePassXC'));
  });

  testWidgets('changes only here are offered a recovery code, which shows its '
      '24 words once', (tester) async {
    final vault = (await tester.runAsync(() async {
      final vault = await open();
      await vault.unlock();
      return vault;
    }))!;
    await pump(tester, [
      vaultProvider.overrideWith((ref) async => vault),
      recoveryOfferProvider.overrideWith((ref) async => 312),
    ]);
    await tester.pump();
    expect(find.text(en.recoveryOffer(312)), findsOneWidget);
    await tester.tap(find.text(en.recoveryCreate));
    await settle(
      tester,
      () => find.byType(SelectableText).evaluate().isNotEmpty,
    );
    final words = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(recoveryEntropy(words.data!), isNotNull);
    expect(await tester.runAsync(vault.hasRecoveryCode), isTrue);
    await tester.runAsync(vault.lock);
  });

  test('the offer stands while changes exist only here, no recovery code '
      'protects them, and "Later" has not put it off', () async {
    final vault = await open();
    await vault.unlock();
    addTearDown(vault.lock);
    final db = await vault.openReplica();
    final settings = MemoryStore();
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          vaultProvider.overrideWith((ref) async => vault),
          replicaProvider.overrideWith((ref) async => db),
          settingsStoreProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    var c = container();
    expect(await c.read(recoveryOfferProvider.future), isNull);
    await db
        .into(db.tag)
        .insert(
          TagCompanion.insert(
            id: Uint8List(16),
            ownerId: Uint8List(16),
            name: 'only here',
            path: 'only here',
          ),
        );
    c = container();
    expect(await c.read(recoveryOfferProvider.future), 1);
    await c.read(settingsProvider.notifier).loaded;
    c.read(settingsProvider.notifier).remindRecoveryLater();
    expect(await c.read(recoveryOfferProvider.future), isNull);
    final later = c.read(settingsProvider).recoveryReminder!;
    expect(
      later.difference(DateTime.now()).inDays,
      recoveryReminderAfter.inDays - 1,
    );

    settings.value = null;
    await vault.addRecoveryCode();
    expect(await container().read(recoveryOfferProvider.future), isNull);
  });
}
