import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

void main() {
  late Directory dir;
  late Vault vault;
  late TileCipher cipher;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('disk_cache');
    (vault, cipher) = await scratchVault('${dir.path}.store', Kernel().keyring);
  });
  tearDown(() async {
    await vault.lock();
    await dir.delete(recursive: true);
    await Directory('${dir.path}.store').delete(recursive: true);
  });

  Uint8List bytes(int seed, [int length = 1000]) => Uint8List.fromList([
    for (var i = 0; i < length; i++) (seed * 31 + i) & 255,
  ]);

  int onDisk() => dir.listSync().whereType<File>().fold(
    0,
    (sum, f) => sum + f.lengthSync(),
  );

  Future<DiskCache> fill(int n, {int maxBytes = 1 << 20}) async {
    final cache = await DiskCache.open(dir.path, cipher, maxBytes: maxBytes);
    for (var i = 0; i < n; i++) {
      await cache.put('k$i', bytes(i));
    }
    return cache;
  }

  test('keeps tiles sealed under the cache key, none in plaintext, and drops '
      "an earlier build's plaintext entry as damaged", () async {
    await (await fill(3)).close();
    final plain = bytes(1).sublist(0, 64);
    for (final file in dir.listSync().whereType<File>()) {
      final data = file.readAsBytesSync();
      final at = Iterable<int>.generate(data.length - plain.length + 1)
          .where((i) => _equal(data.sublist(i, i + plain.length), plain));
      expect(at, isEmpty, reason: file.path);
    }
    final earlier = File('${dir.path}/k9')
      ..writeAsBytesSync([0x50, 0x4c, 0x54, 0x32, 0, 0, 0, 0, ...bytes(9)]);
    final cache = await DiskCache.open(dir.path, cipher);
    expect(await cache.get('k9'), isNull);
    expect(earlier.existsSync(), isFalse);
    expect(await cache.get('k1'), bytes(1));
    await cache.close();
  });

  test('a locked store makes misses, dropping nothing', () async {
    final cache = await fill(1);
    await vault.lock();
    expect(await cache.get('k0'), isNull);
    await cache.put('k1', bytes(1));
    expect(cache.contains('k1'), isFalse);
    await vault.unlock();
    final reopened = await DiskCache.open(dir.path, await vault.tileCipher());
    expect(await reopened.get('k0'), bytes(0));
    await reopened.close();
  });

  test('returns what was put, after reopening too', () async {
    final cache = await fill(3);
    expect(await cache.get('k1'), bytes(1));
    expect(await cache.get('nothing'), isNull);
    await cache.close();
    final again = await DiskCache.open(dir.path, cipher);
    expect(
      [for (var i = 0; i < 3; i++) await again.get('k$i')],
      [for (var i = 0; i < 3; i++) bytes(i)],
    );
    await again.remove('k1');
    expect(await again.get('k1'), isNull);
    await again.close();
    expect(onDisk(), again.bytes);
  });

  test('closes once what it was writing is written, and then neither writes '
      'nor reads', () async {
    Map<String, int> files() => {
      for (final f in dir.listSync().cast<File>()) f.path: f.lengthSync(),
    };
    final cache = await DiskCache.open(dir.path, cipher);
    final writing = cache.put('k0', bytes(0));
    await cache.close();
    final closed = files();
    await writing;
    await cache.put('k1', bytes(1));
    final read = await cache.get('k0');
    await cache.remove('k0');
    expect(files(), closed);
    expect(read, isNull);
    expect(onDisk(), cache.bytes);
    final again = await DiskCache.open(dir.path, cipher);
    expect(await again.get('k0'), bytes(0));
    expect(again.contains('k1'), isFalse);
    await again.close();
  });

  test('closes once its reads and writes under way are done, and then writes '
      'nothing', () async {
    final cache = await fill(3);
    final reads = [for (var i = 0; i < 30; i++) cache.get('k${i % 3}')];
    final put = cache.put('k3', bytes(3));
    await cache.close();
    String listing() => ([
      for (final f in dir.listSync().whereType<File>())
        '${f.path} ${f.lengthSync()}',
    ]..sort()).join('\n');
    final closed = listing();
    await Future.wait([...reads, put]);
    await cache.put('k4', bytes(4));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(listing(), closed);
  });

  test('stays within its bytes, the least recently used going first', () async {
    // About 1.1 kB an entry, sealed, with the index: ten fit, not eleven.
    final cache = await fill(10, maxBytes: 11500);
    await cache.get('k0');
    await cache.put('k10', bytes(10));
    expect(await cache.get('k1'), isNull, reason: 'least recently used');
    expect(await cache.get('k0'), bytes(0));
    await cache.close();
    expect(onDisk(), lessThanOrEqualTo(11500));
    expect(onDisk(), cache.bytes);

    // The order of use survives a restart.
    final again = await DiskCache.open(dir.path, cipher, maxBytes: 11500);
    await again.put('k11', bytes(11));
    expect(await again.get('k2'), isNull);
    expect(await again.get('k0'), bytes(0));
    await again.close();
    expect(onDisk(), lessThanOrEqualTo(11500));
  });

  test('refuses an entry larger than the whole cache, or a key that is no '
      'file name', () async {
    final cache = await DiskCache.open(dir.path, cipher, maxBytes: 500);
    await cache.put('big', bytes(1));
    expect(await cache.get('big'), isNull);
    for (final key in ['../up', '..', '.hidden', 'thumb_cache_index', '']) {
      await expectLater(cache.put(key, bytes(1, 10)), throwsArgumentError);
    }
    await cache.close();
    expect(onDisk(), lessThanOrEqualTo(500));
  });

  test('rebuilds a corrupt index from the files', () async {
    await (await fill(5)).close();
    final index = File('${dir.path}/thumb_cache_index');
    final damaged = index.readAsBytesSync()..[12] ^= 0x40;
    index.writeAsBytesSync(damaged);
    var cache = await DiskCache.open(dir.path, cipher);
    expect(
      [for (var i = 0; i < 5; i++) await cache.get('k$i')],
      [for (var i = 0; i < 5; i++) bytes(i)],
    );
    await cache.close();
    expect(onDisk(), cache.bytes);

    index.writeAsStringSync('not an index');
    cache = await DiskCache.open(dir.path, cipher, maxBytes: 3500);
    await cache.close();
    expect(onDisk(), lessThanOrEqualTo(3500), reason: 'still bounded');
    expect(onDisk(), cache.bytes);
  });

  test('drops a damaged entry and keeps the others', () async {
    await (await fill(3)).close();
    final file = File('${dir.path}/k1');
    file.writeAsBytesSync(file.readAsBytesSync()..[500] ^= 1);
    File('${dir.path}/k2').writeAsBytesSync([1, 2, 3]);
    final cache = await DiskCache.open(dir.path, cipher);
    expect(await cache.get('k1'), isNull);
    expect(await cache.get('k2'), isNull);
    expect(await cache.get('k0'), bytes(0));
    expect(file.existsSync(), isFalse);
    await cache.close();
    expect(onDisk(), cache.bytes);
  });

  test('forgets files that went away and deletes strays', () async {
    await (await fill(3)).close();
    File('${dir.path}/k0').deleteSync();
    File('${dir.path}/~7').writeAsStringSync('a write a crash cut short');
    Directory('${dir.path}/junk').createSync();
    final cache = await DiskCache.open(dir.path, cipher);
    expect(await cache.get('k0'), isNull);
    expect(await cache.get('k1'), bytes(1));
    await cache.close();
    expect(dir.listSync().map((e) => e.uri.pathSegments.last).toSet(), {
      'thumb_cache_index',
      'k1',
      'k2',
    });
    expect(onDisk(), cache.bytes);
  });

  test('opens beside another cache of its directory, whose index rewrite '
      'renames a stray away as it is deleted', () async {
    for (var i = 0; i < 20; i++) {
      final at = await dir.createTemp();
      final first = await DiskCache.open(at.path, cipher);
      await (await DiskCache.open(at.path, cipher)).close();
      await first.close();
    }
  });

  test('opens while another writes in its directory, whatever vanishes as it '
      'reads', () async {
    final writer = await DiskCache.open(dir.path, cipher);
    var writing = true;
    final writes = () async {
      for (var i = 0; writing; i++) {
        await writer.put('w${i % 50}', bytes(i));
      }
    }();
    for (var round = 0; round < 30; round++) {
      await (await DiskCache.open(dir.path, cipher)).close();
    }
    writing = false;
    await writes;
    await writer.close();
  });

  test(
    'whatever happens to the index, it opens bounded and never lies',
    () async {
      final random = Random(56);
      for (var round = 0; round < 50; round++) {
        final cache = await DiskCache.open(dir.path, cipher, maxBytes: 8000);
        for (var i = 0; i < 4; i++) {
          final k = random.nextInt(12);
          await cache.put('k$k', bytes(k, 200 + 100 * k));
          await cache.get('k${random.nextInt(12)}');
        }
        await cache.close();
        expect(onDisk(), cache.bytes);
        expect(onDisk(), lessThanOrEqualTo(8000));
        final index = File('${dir.path}/thumb_cache_index');
        final data = index.readAsBytesSync();
        if (random.nextBool()) {
          index.writeAsBytesSync(data.sublist(0, random.nextInt(data.length)));
        } else {
          index.writeAsBytesSync(
            data..[random.nextInt(data.length)] ^= 1 << random.nextInt(8),
          );
        }
        final reopened = await DiskCache.open(dir.path, cipher, maxBytes: 8000);
        for (var k = 0; k < 12; k++) {
          final got = await reopened.get('k$k');
          if (got != null) expect(got, bytes(k, 200 + 100 * k));
        }
        await reopened.close();
        expect(onDisk(), reopened.bytes);
      }
    },
    // 100 opens, each on an isolate, which a loaded machine starts slowly, and
    // thousands of round trips to the I/O threads: 35 s at load 75, under 1 s
    // idle.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

bool _equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
