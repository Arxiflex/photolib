@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:test/test.dart';

import 'kernel.dart';

void main() {
  final kernel = testKernel();
  late Directory dir;
  late Vault vault;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-tiles-');
    vault = Vault(
      location: dir.path,
      keystore: MemoryKeystore(),
      files: storeFiles(dir.path),
      keyring: kernel.keyring,
    );
    await vault.unlock();
  });
  tearDown(() async {
    await vault.lock();
    await dir.delete(recursive: true);
  });
  Uint8List tile(String text) => utf8.encode(text.padRight(10, '.'));
  Future<String> stored() async => [
    await for (final f in dir.list(recursive: true))
      if (f is File) latin1.decode(await f.readAsBytes()),
  ].join();

  test(
    'tiles are kept sealed in the store, and found again after a reload',
    () async {
      final cache = await VaultCache.open(vault);
      await cache.put('a-128', tile('poster-a'));
      expect(cache.contains('a-128'), isTrue);
      expect(await cache.get('a-128'), tile('poster-a'));
      await cache.close();
      expect(await stored(), isNot(contains('poster-a')));

      final reloaded = await VaultCache.open(vault);
      expect(reloaded.contains('a-128'), isTrue);
      expect(await reloaded.get('a-128'), tile('poster-a'));
      expect(await reloaded.get('b-128'), isNull);
    },
  );

  test(
    'it holds at most its bytes, the least recently used evicted first',
    () async {
      final cache = await VaultCache.open(vault, maxBytes: 25);
      await cache.put('a', tile('a'));
      await cache.put('b', tile('b'));
      await cache.get('a');
      await cache.put('c', tile('c'));
      expect(
        [for (final k in 'abc'.split('')) cache.contains(k)],
        [true, false, true],
      );
      await cache.close();
      final reloaded = await VaultCache.open(vault, maxBytes: 25);
      expect(await reloaded.get('b'), isNull);
      expect(await reloaded.get('c'), tile('c'));
    },
  );

  test('a lost or unreadable tile or list is a miss, never an error', () async {
    final cache = await VaultCache.open(vault);
    await cache.put('a', tile('a'));
    await cache.put('b', tile('b'));
    await cache.close();
    for (final f in await dir.list(recursive: true).toList()) {
      if (f is File && f.path.contains('files/')) {
        await f.writeAsBytes([1, 2, 3]);
      }
    }
    expect(await (await VaultCache.open(vault)).get('a'), isNull);

    final fresh = await VaultCache.open(vault);
    await fresh.put('c', tile('c'));
    await vault.lock();
    expect(await fresh.get('c'), isNull);
    await fresh.put('d', tile('d'));
    expect(fresh.contains('d'), isFalse);
  });
}
