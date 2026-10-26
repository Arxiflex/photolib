import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/collections/collections.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../support/pump_app.dart' show MemoryStore;

void main() {
  Future<Vault> unlocked(Directory dir, [DeviceKeystore? keystore]) async {
    final vault = Vault(
      location: dir.path,
      keystore: keystore ?? MemoryKeystore(),
      files: storeFiles(dir.path),
      keyring: Kernel().keyring,
    );
    await vault.unlock();
    addTearDown(vault.lock);
    return vault;
  }

  test('what the vault keeps is read once it opens on another try', () async {
    final dir = await Directory.systemTemp.createTemp('vault-retry');
    addTearDown(() => dir.delete(recursive: true));
    final vault = await unlocked(dir);
    await VaultText(
      () async => vault,
      'settings',
    ).write('{"themeMode":"dark"}');
    await VaultText(
      () async => vault,
      'collections',
    ).write('[{"kind":"places","pinned":true}]');
    var opens = 0;
    final container = ProviderContainer(
      retry: retry,
      overrides: [
        vaultProvider.overrideWith(
          (ref) async => opens++ == 0
              ? throw KeystoreUnavailable(
                  PlatformException(code: 'Libsecret error'),
                )
              : vault,
        ),
      ],
    );
    addTearDown(container.dispose);
    Future<(ThemeMode, CollectionKind)> read() async {
      container
        ..read(settingsProvider)
        ..read(collectionsProvider);
      await container.read(settingsProvider.notifier).loaded;
      await container.read(collectionsProvider.notifier).loaded;
      return (
        container.read(settingsProvider).themeMode,
        container.read(collectionsProvider).visible.first.kind,
      );
    }

    expect(await read(), (ThemeMode.system, CollectionKind.albums));
    container.invalidate(vaultProvider);
    expect(await read(), (ThemeMode.dark, CollectionKind.places));
  });

  test('a vault object kept as text is sealed at rest, and read back after '
      'a restart', () async {
    final dir = await Directory.systemTemp.createTemp('vault-text');
    addTearDown(() => dir.delete(recursive: true));
    final keystore = MemoryKeystore();
    Future<VaultText> open() async {
      final vault = await unlocked(dir, keystore);
      return VaultText(() async => vault, 'settings');
    }

    const text = '{"downloadFolder":"/home/ana/Pictures"}';
    await (await open()).write(text);
    final stored = [
      for (final f in dir.listSync(recursive: true))
        if (f is File) latin1.decode(f.readAsBytesSync()),
    ].join();
    expect(stored, isNot(contains('Pictures')));
    final next = await open();
    expect(await next.read(), text);
    await next.write(null);
    expect(await next.read(), isNull);
  });

  testWidgets('a vault that cannot open fails at once, as waiting heals no '
      'missing keystore', (tester) async {
    var tries = 0;
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWith((ref) {
          tries++;
          // As the keystore fails where no session bus runs.
          return Future.error(PlatformException(code: 'Libsecret error'));
        }),
      ],
    );
    addTearDown(container.dispose);
    Object? error;
    VaultText(
      () => container.read(vaultProvider.future),
      'settings',
    ).read().then(
      (_) {},
      onError: (Object e) {
        error = e;
      },
    );
    await tester.pump();
    expect(error, isA<PlatformException>());
    await tester.pump(const Duration(minutes: 1));
    expect(tries, 1);
  });

  test('the replica the app opens reads metadata with the kernel the app '
      'bundles (ADR-0072)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dir = await Directory.systemTemp.createTemp('replica');
    addTearDown(() => dir.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        // No account: the device's own replica.
        serverStoreProvider.overrideWithValue(MemoryStore()),
        vaultProvider.overrideWith((ref) async {
          final vault = Vault(
            location: dir.path,
            keystore: MemoryKeystore(),
            files: storeFiles(dir.path),
            keyring: Kernel().keyring,
          );
          await vault.unlock();
          ref.onDispose(vault.lock);
          return vault;
        }),
      ],
    );
    addTearDown(container.dispose);
    final db = await container.read(replicaProvider.future);
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: Uint8List(16)..[0] = 1,
            source: 'folder',
            volume: Value(Directory('../testdata/corpus/files').absolute.path),
            sourceId: '1',
            size: 1,
            mtime: 1,
            path: const Value('time/zones/india.jpg'),
          ),
        );
    LocalAssetData row;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      row = await db.select(db.localAsset).getSingle();
    } while (row.extracted == null);
    expect('${row.takenLocal} ${row.make}', '2023-04-14T08:30:00 Canon');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
