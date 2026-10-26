@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'kernel.dart';

void main() {
  final kernel = testKernel();
  final library = buildKernel();
  late Directory dir;
  late String store;
  late MemoryKeystore keystore;
  late List<KernelKeyring> keyrings;
  Vault open() => Vault(
    location: store,
    keystore: keystore,
    files: storeFiles(store),
    keyring: () {
      final keyring = kernel.keyring();
      keyrings.add(keyring);
      return keyring;
    },
    alpha: dir.path,
  );
  late Vault vault;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photolib-vault-');
    store = '${dir.path}/store';
    keystore = MemoryKeystore();
    keyrings = [];
    vault = open();
  });
  tearDown(() async {
    await vault.lock();
    await dir.delete(recursive: true);
  });

  test('unlocking and locking go through the four states', () async {
    final states = <LockState>[];
    vault.states.listen(states.add);
    expect(vault.state, LockState.locked);
    await vault.unlock();
    await vault.lock();
    expect(states, [
      LockState.unlocking,
      LockState.unlocked,
      LockState.locking,
      LockState.locked,
    ]);
  });

  test(
    'locking drops every key handle and closes every database connection',
    () async {
      await vault.unlock();
      final replicas = [
        await vault.openReplica(),
        await vault.openReplica(name: 'other'),
      ];
      await vault.write('thumbnail', utf8.encode('pixels'));
      expect(_openFiles(store), isNotEmpty);
      await vault.lock();

      expect(keyrings, isNotEmpty);
      for (final keyring in keyrings) {
        expect(() => keyring.call(6, Uint8List(0)), throwsStateError);
      }
      expect(_openFiles(store), isEmpty);
      for (final db in replicas) {
        await expectLater(db.select(db.outbox).get(), throwsA(anything));
      }
      await expectLater(vault.read('thumbnail'), throwsStateError);
      await expectLater(vault.openReplica(), throwsStateError);
    },
    testOn: 'linux',
  );

  test('locking a store leaves the databases of another open', () async {
    final other = Vault(
      location: '${dir.path}/other',
      keystore: MemoryKeystore(),
      files: storeFiles('${dir.path}/other'),
      keyring: kernel.keyring,
    );
    await other.unlock();
    final db = await other.openReplica();
    await vault.unlock();
    await vault.lock();

    expect(await db.select(db.outbox).get(), isEmpty);
    await other.lock();
  });

  test(
    'the store reopens under the same keys after locking and from a new vault',
    () async {
      await vault.unlock();
      final db = await vault.openReplica();
      await db
          .into(db.tag)
          .insert(
            TagCompanion.insert(
              id: Uint8List(16),
              ownerId: Uint8List(16),
              name: 'kept',
              path: 'kept',
            ),
          );
      await vault.write('offline copy', utf8.encode('original'));
      await vault.lock();

      vault = open();
      await vault.unlock();
      final again = await vault.openReplica();
      expect((await again.select(again.tag).getSingle()).name, 'kept');
      expect(utf8.decode((await vault.read('offline copy'))!), 'original');
      expect(await vault.read('never written'), isNull);
    },
  );

  test(
    'class B objects are readable while locked, class C ones only unlocked',
    () async {
      await vault.unlock();
      await vault.write('token', utf8.encode('refresh'), keyClass: KeyClass.b);
      await vault.write('thumbnail', utf8.encode('pixels'));
      await vault.lock();

      final token = await vault.read('token', keyClass: KeyClass.b);
      expect(utf8.decode(token!), 'refresh');
      await expectLater(vault.read('thumbnail'), throwsStateError);
      await vault.write(
        'journal',
        utf8.encode('progress'),
        keyClass: KeyClass.b,
      );
      for (final keyring in keyrings) {
        expect(() => keyring.call(6, Uint8List(0)), throwsStateError);
      }
    },
  );

  test(
    'an object read with the other class\'s key fails authentication',
    () async {
      await vault.unlock();
      await vault.write('thumbnail', utf8.encode('pixels'));
      await expectLater(
        vault.read('thumbnail', keyClass: KeyClass.b),
        throwsA(
          isA<KernelError>().having(
            (e) => e.reason,
            'reason',
            'commitment_mismatch',
          ),
        ),
      );
    },
  );

  test(
    'an envelope its caller keeps opens as its object only, while unlocked',
    () async {
      await vault.unlock();
      final envelope = await vault.seal('log', utf8.encode('a record'));
      expect(latin1.decode(envelope), isNot(contains('a record')));
      expect(utf8.decode(await vault.unseal('log', envelope)), 'a record');
      await expectLater(
        vault.unseal('other', envelope),
        throwsA(isA<KernelError>()),
      );
      await vault.lock();
      await expectLater(vault.unseal('log', envelope), throwsStateError);

      vault = open();
      await vault.unlock();
      expect(utf8.decode(await vault.unseal('log', envelope)), 'a record');
    },
  );

  test(
    'crypto-erase deletes the lockbox, the keystore keys and the store; the next unlock starts afresh',
    () async {
      await vault.unlock();
      await vault.openReplica();
      await vault.write('token', utf8.encode('refresh'), keyClass: KeyClass.b);
      await vault.erase();

      expect(vault.state, LockState.locked);
      expect(keystore.keys, isEmpty);
      expect(Directory(store).existsSync(), isFalse);
      await vault.unlock();
      final db = await vault.openReplica();
      expect(await db.select(db.tag).get(), isEmpty);
      expect(await vault.read('token', keyClass: KeyClass.b), isNull);
    },
  );

  test(
    'a tile cipher seals tiles on an isolate of its own under the cache key, '
    'each bound to its name, until the vault locks',
    () async {
      final (vault, cipher) = await scratchVault(
        '${dir.path}/tiles',
        kernel.keyring,
        kernel: library,
      );
      final envelope = (await cipher.seal('thumbnails/a', utf8.encode('px')))!;
      expect(latin1.decode(envelope), isNot(contains('px')));
      expect(utf8.decode((await cipher.open('thumbnails/a', envelope))!), 'px');
      await expectLater(
        cipher.open('thumbnails/b', envelope),
        throwsA(isA<KernelError>()),
      );
      await vault.lock();
      expect(await cipher.open('thumbnails/a', envelope), isNull);
      await vault.unlock();
      final again = await vault.tileCipher(kernel: library);
      expect(utf8.decode((await again.open('thumbnails/a', envelope))!), 'px');
      await vault.lock();
    },
  );

  Future<void> keep(Vault vault, String text) async {
    final db = await vault.openReplica();
    await db
        .into(db.tag)
        .insert(
          TagCompanion.insert(
            id: Uint8List(16),
            ownerId: Uint8List(16),
            name: text,
            path: text,
          ),
        );
    await vault.write('edit', utf8.encode(text));
  }

  Future<List<String>> kept(Vault vault) async {
    final db = await vault.openReplica();
    return [
      for (final tag in await db.select(db.tag).get()) tag.name,
      if (await vault.read('edit') case final edit?) utf8.decode(edit),
    ];
  }

  test('a store whose keystore key is gone, with no recovery code, is rebuilt '
      'empty, and says so', () async {
    await vault.unlock();
    await keep(vault, 'local only');
    await vault.lock();
    await keystore.delete('dev');

    vault = open();
    await vault.unlock();
    expect(vault.rebuilt, isTrue);
    expect(await kept(vault), isEmpty);
    await vault.lock();
    vault = open();
    await vault.unlock();
    expect(vault.rebuilt, isFalse);
  });

  test('the recovery drill: with the keystore key gone, the store waits for '
      'its recovery code, which unlocks it under a new keystore key', () async {
    await vault.unlock();
    expect(await vault.hasRecoveryCode(), isFalse);
    await vault.addRecoveryCode();
    final code = await vault.addRecoveryCode();
    expect(await vault.hasRecoveryCode(), isTrue);
    await keep(vault, 'local only');
    await vault.lock();
    await keystore.delete('dev');

    vault = open();
    await expectLater(vault.unlock(), throwsA(isA<RecoveryNeeded>()));
    expect(vault.state, LockState.locked);
    await expectLater(
      vault.unlock(recoveryCode: 'not a code'),
      throwsFormatException,
    );
    final other = recoveryWords(Uint8List(32));
    await expectLater(
      vault.unlock(recoveryCode: other),
      throwsA(isA<KernelError>()),
    );
    await vault.unlock(recoveryCode: code);
    expect(await kept(vault), ['local only', 'local only']);
    expect(vault.rebuilt, isFalse);
    await vault.lock();

    vault = open();
    await vault.unlock();
    expect(await kept(vault), ['local only', 'local only']);
    expect(await vault.hasRecoveryCode(), isTrue);
  });

  test('a keystore that fails to answer leaves the store as it is', () async {
    await vault.unlock();
    await keep(vault, 'kept');
    await vault.lock();
    final failing = Vault(
      location: store,
      keystore: _Unanswering(),
      files: storeFiles(store),
      keyring: kernel.keyring,
    );
    await expectLater(failing.unlock(), throwsA(isA<StateError>()));
    vault = open();
    await vault.unlock();
    expect(await kept(vault), ['kept', 'kept']);
  });

  test('what exists only on this device: unsent changes and rows no server '
      'confirmed', () async {
    await vault.unlock();
    final db = await vault.openReplica();
    expect(await localOnlyCount(db), 0);
    await keep(vault, 'local only');
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            mutationId: Uint8List(16),
            entity: 'tag',
            entityId: Uint8List(16),
            mutation: Uint8List(0),
            createdAt: 0,
          ),
        );
    await (db.update(db.tag)..where((t) => t.name.equals('local only'))).write(
      const TagCompanion(txid: Value(7)),
    );
    await db
        .into(db.tag)
        .insert(
          TagCompanion.insert(
            id: Uint8List(16)..[0] = 1,
            ownerId: Uint8List(16),
            name: 'unsent',
            path: 'unsent',
          ),
        );
    expect(await localOnlyCount(db), 2);
  });

  group('a plaintext replica of a build before the encrypted store', () {
    late String plain;
    setUp(() {
      plain = '${dir.path}/replica';
      final killed = '${dir.path}/killed';
      final db = sqlite3.open(killed)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute('PRAGMA user_version = 1')
        ..execute(
          'CREATE TABLE tag (id BLOB NOT NULL PRIMARY KEY, owner_id BLOB NOT NULL, parent_id BLOB, '
          'name TEXT NOT NULL, path TEXT NOT NULL, color TEXT, is_album INTEGER NOT NULL DEFAULT 0, '
          "origin TEXT NOT NULL DEFAULT 'user', txid INTEGER) STRICT",
        )
        ..execute(
          "INSERT INTO tag (id, owner_id, name, path) VALUES (x'01', x'02', ?, 'p')",
          [markers[4]],
        );
      // Copied while open: an alpha build that was killed, its last writes still in the WAL.
      for (final suffix in ['', '-wal']) {
        File('$killed$suffix').copySync('$plain$suffix');
      }
      db.close();
      File(killed).deleteSync();
      expect(File('$plain-wal').lengthSync(), greaterThan(0));
    });

    test(
      'is re-keyed, verified and deleted; its caches are dropped and rebuilt',
      () async {
        File('$store/files/0011')
          ..createSync(recursive: true)
          ..writeAsStringSync(markers[5]);
        await vault.unlock();
        final db = await vault.openReplica();

        expect((await db.select(db.tag).getSingle()).name, markers[4]);
        for (final suffix in ['', '-wal', '-shm']) {
          expect(
            File('$plain$suffix').existsSync(),
            isFalse,
            reason: '$plain$suffix',
          );
        }
        expect(File('$store/files/0011').existsSync(), isFalse);
        await vault.write('thumbnail', utf8.encode('rebuilt'));
        expect(utf8.decode((await vault.read('thumbnail'))!), 'rebuilt');
        await vault.lock();
        expect(await markerHits(dir.path), isEmpty);
      },
    );

    test('is re-keyed again after an interrupted run', () async {
      File('$store/replica.rekey')
        ..createSync(recursive: true)
        ..writeAsStringSync('half a copy');
      await vault.unlock();
      final db = await vault.openReplica();
      expect((await db.select(db.tag).getSingle()).name, markers[4]);
      expect(File('$store/replica.rekey').existsSync(), isFalse);
    });

    test(
      'that is damaged stays where it is, and the store does not open',
      () async {
        final bytes = File(plain).readAsBytesSync();
        File(plain).writeAsBytesSync([
          ...bytes.take(100),
          ...List.filled(bytes.length - 100, 7),
        ]);
        File('$plain-wal').deleteSync();
        await vault.unlock();
        await expectLater(vault.openReplica(), throwsA(isA<SqliteException>()));
        expect(File(plain).existsSync(), isTrue);
        expect(File('$store/replica').existsSync(), isFalse);
      },
    );
  });
}

/// The files under [dir] that this process holds open.
List<String> _openFiles(String dir) => [
  for (final fd in Directory('/proc/self/fd').listSync(followLinks: false))
    if (fd is Link && fd.existsSync())
      if (fd.targetSync() case final target when target.startsWith(dir)) target,
];

/// A keystore whose service does not answer, as Linux without a keyring.
class _Unanswering extends MemoryKeystore {
  @override
  Future<Uint8List?> read(String name) =>
      Future.error(StateError('no Secret Service'));
}
