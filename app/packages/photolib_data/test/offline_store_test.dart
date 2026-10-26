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
  late StoreFiles files;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-offline-');
    vault = Vault(
      location: dir.path,
      keystore: MemoryKeystore(),
      files: storeFiles(dir.path),
      keyring: kernel.keyring,
    );
    await vault.unlock();
    files = storeFiles(dir.path);
  });
  tearDown(() async {
    await vault.lock();
    await dir.delete(recursive: true);
  });

  Uint8List bytes(int n, [int seed = 1]) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + seed) & 255]);

  // The bytes the offline files take on disk.
  Future<int> onDisk() async {
    var total = 0;
    final offline = Directory('${dir.path}/offline');
    if (!offline.existsSync()) return 0;
    for (final f in offline.listSync(recursive: true)) {
      if (f is File) total += f.lengthSync();
    }
    return total;
  }

  List<File> chunks() => Directory(
    '${dir.path}/offline',
  ).listSync(recursive: true).whereType<File>().toList();

  Future<OfflineStore> open({int budget = 1 << 20, int chunk = 1000}) =>
      OfflineStore.open(vault, files, budget: budget, chunkSize: chunk);

  test('a blob is read back whole and by range across chunk borders', () async {
    final store = await open();
    final blob = bytes(3500);
    await store.putBytes('a.original', blob);
    expect(store.has('a.original'), isTrue);
    expect(store.sizeOf('a.original'), 3500);
    expect(await store.read('a.original'), blob);
    expect(
      await store.read('a.original', start: 900, end: 2100),
      blob.sublist(900, 2100),
    );
    expect(await store.read('a.original', start: 3000), blob.sublist(3000));
    expect(await store.read('a.original', start: 4000), isEmpty);
    expect(await store.read('b.original'), isNull);
  });

  test('an empty blob is kept', () async {
    final store = await open();
    await store.putBytes('e', Uint8List(0));
    expect(store.has('e'), isTrue);
    expect(await store.read('e'), isEmpty);
  });

  test('nothing is at rest in the clear: names hashed, bytes sealed', () async {
    final store = await open();
    await store.putBytes(
      'asset-7.original',
      utf8.encode('GRANDMA-CANDLES' * 200),
    );
    final seen = StringBuffer();
    for (final f in chunks()) {
      seen.write(f.path + latin1.decode(f.readAsBytesSync()));
    }
    expect('$seen', isNot(contains('GRANDMA')));
    expect('$seen', isNot(contains('asset-7')));
  });

  test('used counts what is on disk, and removing frees it', () async {
    final store = await open();
    await store.putBytes('a', bytes(2500));
    await store.putBytes('b', bytes(10));
    expect(store.used, await onDisk());
    final before = store.used;
    final freed = await store.remove('a');
    expect(freed, greaterThan(2500));
    expect(store.used, before - freed);
    expect(store.used, await onDisk());
    expect(store.has('a'), isFalse);
    await store.remove('b');
    expect(store.used, 0);
    expect(await onDisk(), 0);
  });

  test(
    'the bytes it counts are the bytes on disk, whatever the size',
    () async {
      // Envelopes add a tag for each 64 KiB: sizes across those borders.
      final store = await open(budget: 1 << 26, chunk: 1 << 20);
      var expected = 0;
      for (final size in [
        0,
        1,
        65536,
        65537,
        131072,
        200000,
        1 << 20,
        3000000,
      ]) {
        await store.putBytes('s$size', bytes(size));
        expected += store.sealedSize(size);
        expect(store.used, expected, reason: '$size');
        expect(store.used, await onDisk(), reason: '$size');
      }
      // Reopened, it counts the same, and what it frees is what it took.
      final again = await open(budget: 1 << 26, chunk: 1 << 20);
      expect(again.used, store.used);
      expect(await again.retain({}), expected);
      expect(again.used, 0);
      expect(await onDisk(), 0);
    },
  );

  test(
    'a blob that fills the budget to the byte fits, one more byte does not',
    () async {
      const size = 200000;
      final exact = (await open(
        budget: 1 << 30,
        chunk: 1 << 20,
      )).sealedSize(size);
      final fits = await open(budget: exact, chunk: 1 << 20);
      await fits.putBytes('a', bytes(size));
      expect(fits.used, exact);
      expect(await onDisk(), exact);
      await fits.remove('a');
      final tight = await open(budget: exact - 1, chunk: 1 << 20);
      await expectLater(
        tight.putBytes('a', bytes(size)),
        throwsA(isA<BudgetExceeded>()),
      );
    },
  );

  test(
    'a blob that does not fit is refused before a byte is written',
    () async {
      final store = await open(budget: 3000);
      await store.putBytes('a', bytes(2000));
      await expectLater(
        store.putBytes('b', bytes(2000)),
        throwsA(isA<BudgetExceeded>()),
      );
      expect(store.has('b'), isFalse);
      expect(store.used, await onDisk());
      expect(store.used, lessThanOrEqualTo(3000));
    },
  );

  test('puts that run together never take more than the budget', () async {
    final store = await open(budget: 10000);
    Future<bool> kept(int i) async {
      try {
        await store.putBytes('k$i', bytes(2000, i));
        return true;
      } on BudgetExceeded {
        return false;
      }
    }

    final results = await Future.wait([for (var i = 0; i < 12; i++) kept(i)]);
    expect(results.where((ok) => ok), isNotEmpty);
    expect(results.where((ok) => ok).length, lessThan(12));
    expect(store.used, lessThanOrEqualTo(10000));
    expect(await onDisk(), lessThanOrEqualTo(10000));
    expect(store.reserved, 0);
  });

  test('a stream longer or shorter than declared leaves no trace', () async {
    final store = await open();
    await expectLater(
      store.put('long', Stream.value(bytes(2000)), size: 1500),
      throwsA(isA<SizeMismatch>()),
    );
    await expectLater(
      store.put('short', Stream.value(bytes(1000)), size: 1500),
      throwsA(isA<SizeMismatch>()),
    );
    expect(store.has('long') || store.has('short'), isFalse);
    expect(await onDisk(), 0);
    expect(store.reserved, 0);
  });

  test('a stream in pieces of any size makes the same blob', () async {
    final store = await open();
    final blob = bytes(4321);
    await store.put(
      'p',
      Stream.fromIterable([
        for (var i = 0; i < blob.length; i += 777)
          blob.sublist(i, (i + 777).clamp(0, blob.length)),
      ]),
      size: blob.length,
    );
    expect(await store.read('p'), blob);
  });

  test('reopened, it finds its blobs and sweeps those half written', () async {
    var store = await open();
    await store.putBytes('a', bytes(2500));
    final used = store.used;
    await store.putBytes('torn', bytes(2600));
    // A crash before the last chunk of the second blob.
    final last = chunks().where((f) => f.path.endsWith('/2.3.2600.1000'));
    expect(last, hasLength(1));
    last.single.deleteSync();
    store = await open();
    expect(store.has('a'), isTrue);
    expect(store.has('torn'), isFalse);
    expect(store.used, used);
    expect(await onDisk(), used);
    expect(await store.read('a'), bytes(2500));
  });

  test('retain keeps the wanted blobs and frees the rest', () async {
    final store = await open();
    await store.putBytes('a', bytes(500));
    await store.putBytes('b', bytes(500));
    await store.putBytes('c', bytes(500));
    final freed = await store.retain({'b'});
    expect(freed, greaterThan(1000));
    expect(store.has('a'), isFalse);
    expect(store.has('b'), isTrue);
    expect(store.has('c'), isFalse);
    expect(store.used, await onDisk());
  });

  test('a damaged chunk reads as lost and is dropped', () async {
    final store = await open();
    await store.putBytes('a', bytes(2500));
    chunks().first.writeAsBytesSync(Uint8List(40));
    expect(await store.read('a'), isNull);
    expect(store.has('a'), isFalse);
    expect(store.used, await onDisk());
  });

  test('clear empties it', () async {
    final store = await open();
    await store.putBytes('a', bytes(2500));
    await store.clear();
    expect(store.used, 0);
    expect(await onDisk(), 0);
    expect(store.has('a'), isFalse);
  });

  test('a locked vault reads nothing and refuses writes', () async {
    final store = await open();
    await store.putBytes('a', bytes(100));
    await vault.lock();
    expect(await store.read('a'), isNull);
    await expectLater(store.putBytes('b', bytes(10)), throwsA(anything));
    expect(store.reserved, 0);
  });
}
