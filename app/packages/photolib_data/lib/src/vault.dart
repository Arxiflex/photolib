import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_data/photolib_data.dart'
    show recoveryEntropy, recoveryWords;
import 'package:photolib_data/src/keys.dart';
import 'package:photolib_data/src/open_native.dart'
    if (dart.library.js_interop) 'package:photolib_data/src/open_web.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_kernel/keyring.dart';

/// The lock states of the local store (docs/21 §5.1). At L1 unlocking needs only the keystore, so the app unlocks at
/// start.
enum LockState { locked, unlocking, unlocked, locking }

/// Key classes (docs/21 §3): class C is readable only while unlocked, class B also while locked, after the device's
/// first unlock, for background work.
enum KeyClass { b, c }

/// The platform keystore (`secure_store`, ADR-0057): non-exportable keys, each of which releases or computes 32 bytes.
abstract interface class DeviceKeystore {
  /// The 32 bytes of keystore key [name], or null when there is none.
  Future<Uint8List?> read(String name);

  /// Creates keystore key [name], replacing any, and returns its 32 bytes.
  Future<Uint8List> create(String name);

  Future<void> delete(String name);
}

/// Where the store keeps its lockbox and encrypted files: a directory natively, IndexedDB on the web.
abstract interface class StoreFiles {
  Future<Uint8List?> read(String name);

  Future<void> write(String name, Uint8List bytes);

  Future<void> delete(String name);

  /// Deletes every file whose name starts with [prefix]: nothing, or a directory such as `files/`.
  Future<void> deleteAll(String prefix);

  /// The names of the files whose names start with [prefix], a directory such as `offline/`, whole.
  Future<List<String>> list(String prefix);
}

/// The keystore no longer has the key of a store whose lockbox holds a
/// recovery code (docs/21 §6): unlock it with the code, or erase it.
class RecoveryNeeded implements Exception {
  /// The store waits for its recovery code.
  const RecoveryNeeded();
}

/// Seals and opens the tiles of the thumbnails' disk cache: PLB envelopes
/// under the cache key (docs/21 §3), each bound to its name. Both give null
/// once the vault locked.
abstract interface class TileCipher {
  /// [tile] as the envelope of [name].
  Future<Uint8List?> seal(String name, Uint8List tile);

  /// The tile in [envelope]; a [KernelError] when it is damaged or another's.
  Future<Uint8List?> open(String name, Uint8List envelope);
}

/// The key provider of every local store (ADR-0057): it holds the device data key while unlocked, opens the databases
/// with their page keys, encrypts files, and on lock drops every key handle and closes every connection.
class Vault {
  /// The store in [location], a directory natively; on the web the URL that serves sqlite3mc.wasm and
  /// drift_worker.js. [alpha] is where builds before the encrypted store kept a plaintext replica, natively.
  Vault({
    required this.location,
    required DeviceKeystore keystore,
    required StoreFiles files,
    required KernelKeyring Function() keyring,
    this.alpha,
  }) : _keystore = keystore,
       _files = files,
       _newKeyring = keyring;

  final String location;
  final String? alpha;
  final DeviceKeystore _keystore;
  final StoreFiles _files;
  final KernelKeyring Function() _newKeyring;
  final _states = StreamController<LockState>.broadcast(sync: true);
  final _replicas = <Replica>[];
  final _ciphers = <void Function()>[];
  var _state = LockState.locked;
  var _queue = Future<void>.value();
  KernelKeyring? _keyring;
  late int _ddk, _cacheKey;

  LockState get state => _state;

  Stream<LockState> get states => _states.stream;

  /// Whether the last [unlock] found the keystore key gone and no recovery
  /// code, and rebuilt the store empty: what existed only here is lost.
  bool get rebuilt => _rebuilt;
  var _rebuilt = false;

  /// Unlocks with the keystore key of the lockbox's slot 1 (level L1). The
  /// first unlock makes the device data key, the keystore key and the lockbox.
  /// When the keystore no longer has that key (an OEM wipe, a keychain reset,
  /// docs/21 §6), [recoveryCode] opens the store under a new one; without it,
  /// a store with a recovery code throws [RecoveryNeeded] and any other is
  /// rebuilt ([rebuilt]). A keystore that fails changes nothing.
  Future<void> unlock({String? recoveryCode}) => _serial(() async {
    if (_state == LockState.unlocked) return;
    _set(LockState.unlocking);
    final keyring = _newKeyring();
    final keys = Keys(keyring);
    try {
      _rebuilt = false;
      _ddk = await _deviceDataKey(keys, recoveryCode);
      _cacheKey = keys.cacheKey(_ddk);
      _keyring = keyring;
      _set(LockState.unlocked);
    } catch (_) {
      keyring.close();
      _set(LockState.locked);
      rethrow;
    }
  });

  // The device data key, from the lockbox, with the recovery code once the
  // keystore key is gone, or new.
  Future<int> _deviceDataKey(Keys keys, String? recoveryCode) async {
    final lockbox = await _files.read(_lockbox);
    if (lockbox == null) return await _seal(keys, keys.import(randomBytes(32)));
    if (await _keystore.read(_dev) case final secret?) {
      final factor = keys.import(secret);
      try {
        return keys.openLockbox(lockbox, factor);
      } on KernelError {
        // Another keystore key, or a damaged lockbox: as gone.
      } finally {
        keys.drop(factor);
      }
    }
    final (device, slots) = _slots(keys, lockbox);
    final recovery = slots.indexWhere((s) => s.$1 == _recovery);
    if (recovery < 0) {
      await _wipe();
      _rebuilt = true;
      return await _seal(keys, keys.import(randomBytes(32)));
    }
    if (recoveryCode == null) throw const RecoveryNeeded();
    final entropy =
        recoveryEntropy(recoveryCode) ??
        (throw const FormatException('not a recovery code'));
    final kek = keys.recoveryKey(entropy);
    try {
      final ddk = keys.openLockbox(lockbox, kek, slot: recovery);
      return await _seal(keys, ddk, device, slots[recovery].$2);
    } finally {
      keys.drop(kek);
    }
  }

  (Uint8List, List<(int, Uint8List)>) _slots(Keys keys, Uint8List lockbox) {
    try {
      return keys.readLockbox(lockbox);
    } on KernelError {
      return (randomBytes(16), const []);
    }
  }

  // Seals [ddk] in a new lockbox under a new keystore key, with a recovery
  // slot's [recovery] wrap kept, and returns it.
  Future<int> _seal(
    Keys keys,
    int ddk, [
    Uint8List? device,
    Uint8List? recovery,
  ]) async {
    final factor = keys.import(await _keystore.create(_dev));
    final lockbox = keys.sealLockbox(ddk, device ?? randomBytes(16), [
      (1, factor),
      if (recovery != null) (_recovery, recovery),
    ]);
    keys.drop(factor);
    await _files.write(_lockbox, lockbox);
    return ddk;
  }

  /// Adds a local recovery code to the lockbox, replacing any (docs/21 §6),
  /// and returns its 24 words, which unlock the store without its keystore
  /// key.
  Future<String> addRecoveryCode() => _serial(() async {
    final keys = _keys;
    final lockbox = await _files.read(_lockbox) ?? Uint8List(0);
    final (device, slots) = keys.readLockbox(lockbox);
    final entropy = randomBytes(32);
    final words = recoveryWords(entropy);
    final kek = keys.recoveryKey(entropy);
    final sealed = keys.sealLockbox(_ddk, device, [
      for (final (factor, wrap) in slots)
        if (factor != _recovery) (factor, wrap),
      (_recovery, kek),
    ]);
    keys.drop(kek);
    await _files.write(_lockbox, sealed);
    return words;
  });

  /// Whether the lockbox holds a recovery code.
  Future<bool> hasRecoveryCode() => _serial(() async {
    final lockbox = await _files.read(_lockbox) ?? Uint8List(0);
    return _keys.readLockbox(lockbox).$2.any((s) => s.$1 == _recovery);
  });

  /// Closes every database connection, then zeroizes every key.
  Future<void> lock() => _serial(() async {
    if (_state == LockState.locked) return;
    _set(LockState.locking);
    try {
      for (final db in _replicas) {
        await db.close();
      }
      await closeDatabases(location);
    } finally {
      for (final close in _ciphers) {
        close();
      }
      _ciphers.clear();
      _replicas.clear();
      _keyring?.close();
      _keyring = null;
      _set(LockState.locked);
    }
  });

  /// Crypto-erase: deletes the lockbox and the keystore keys, which makes the store unreadable, then its files.
  Future<void> erase() async {
    await lock();
    await _serial(_wipe);
  }

  Future<void> _wipe() async {
    await _files.delete(_lockbox);
    await _keystore.delete(_dev);
    await _keystore.delete(_bg);
    await _files.deleteAll('');
    await deleteDatabases();
  }

  /// The replica [name] under its page key. A plaintext replica that an earlier build left in [alpha] is re-keyed
  /// into the store, verified and deleted first, and the store's files, all caches, are dropped (docs/21 §9).
  Future<Replica> openReplica({String name = 'replica'}) => _serial(() async {
    final key = _keys.databaseKey(_ddk, objectId(name));
    try {
      if (alpha != null && await rekeyPlaintext(alpha!, location, name, key)) {
        await _files.deleteAll(_objects);
      }
      final db = await openKeyed(location, name, key);
      _replicas.add(db);
      return db;
    } finally {
      key.fillRange(0, key.length, 0);
    }
  });

  /// A [TileCipher] on an isolate of its own, natively, with the kernel
  /// library at [kernel] or the bundled one: it opens the lockbox with the
  /// keystore key and keeps only the cache key, dropped when the vault locks.
  Future<TileCipher> tileCipher({String? kernel}) => _serial(() async {
    _keys;
    final lockbox = await _files.read(_lockbox);
    final secret = await _keystore.read(_dev);
    if (lockbox == null || secret == null) {
      throw StateError('the keystore key of the store is gone');
    }
    final (cipher, close) = await spawnTileCipher(lockbox, secret, kernel);
    _ciphers.add(close);
    return cipher;
  });

  /// Stores [bytes] as object [name], a PLB envelope under the object's key of [keyClass].
  Future<void> write(
    String name,
    Uint8List bytes, {
    KeyClass keyClass = KeyClass.c,
  }) => _withKey(name, keyClass, (keys, key) async {
    await _files.write(
      _object(name),
      keys.encryptBlob(key, bytes, randomBytes(32)),
    );
  });

  /// The object [name], or null when there is none.
  Future<Uint8List?> read(String name, {KeyClass keyClass = KeyClass.c}) async {
    final envelope = await _files.read(_object(name));
    if (envelope == null) return null;
    return _withKey(
      name,
      keyClass,
      (keys, key) async => keys.decryptBlob(key, envelope),
    );
  }

  Future<void> delete(String name) => _files.delete(_object(name));

  /// [bytes] as a PLB envelope under the class C key of object [name], for
  /// a caller that keeps it, as the log does.
  Future<Uint8List> seal(String name, Uint8List bytes) => _withKey(
    name,
    KeyClass.c,
    (keys, key) async => keys.encryptBlob(key, bytes, randomBytes(32)),
  );

  /// The bytes of an [envelope] that [seal] made for object [name].
  Future<Uint8List> unseal(String name, Uint8List envelope) => _withKey(
    name,
    KeyClass.c,
    (keys, key) async => keys.decryptBlob(key, envelope),
  );

  /// Runs [use] with the key of object [name], dropped after. A class B key comes from the keystore for this call
  /// only, so it is there while locked and no handle outlives the call.
  Future<T> _withKey<T>(
    String name,
    KeyClass keyClass,
    Future<T> Function(Keys keys, int key) use,
  ) async {
    if (keyClass == KeyClass.c) {
      return _serial(() async {
        final keys = _keys;
        final key = keys.objectKey(_cacheKey, name);
        try {
          return await use(keys, key);
        } finally {
          keys.drop(key);
        }
      });
    }
    final keys = Keys(_newKeyring());
    try {
      final secret = await _keystore.read(_bg) ?? await _keystore.create(_bg);
      return await use(keys, keys.objectKey(keys.import(secret), name));
    } finally {
      keys.keyring.close();
    }
  }

  Keys get _keys => Keys(_keyring ?? (throw StateError('the store is locked')));

  void _set(LockState state) => _states.add(_state = state);

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Keystore keys where no platform keystore runs, as on a Linux desktop
/// without a Secret Service (docs/10 §8.2, ADR-0154): each key's 32 random
/// bytes, in one PLB envelope under `KEK_pass` of a passphrase the user
/// chooses at the first use and gives at every start, in the store's
/// `keystore` after the device parameters it was stretched with.
class PassphraseKeystore implements DeviceKeystore {
  /// Keys in [_files], under the passphrase [_ask] gets.
  PassphraseKeystore(this._files, this._keyring, this._ask);

  final StoreFiles _files;
  final KernelKeyring Function() _keyring;

  /// A new passphrase when `create`, else the one chosen, again after a
  /// wrong one (`retry`).
  final Future<String> Function({required bool create, required bool retry})
  _ask;
  Future<_Sealed>? _opening;

  /// Whether a passphrase was chosen.
  Future<bool> get exists async => await _files.read(_keystore) != null;

  @override
  Future<Uint8List?> read(String name) async =>
      _copy((await _open()).held[name]);

  @override
  Future<Uint8List> create(String name) async {
    final sealed = await _open();
    final key = sealed.held[name] = randomBytes(32);
    await _seal(sealed);
    return Uint8List.fromList(key);
  }

  @override
  Future<void> delete(String name) async {
    final sealed = await _opening;
    if (sealed != null && sealed.held.remove(name) != null) {
      await _seal(sealed);
    }
  }

  // The vault zeroes what it imports.
  static Uint8List? _copy(Uint8List? key) =>
      key == null ? null : Uint8List.fromList(key);

  Future<_Sealed> _open() => _opening ??= () async {
    final keys = Keys(_keyring());
    try {
      final file = await _files.read(_keystore);
      for (var retry = false; ; retry = true) {
        final passphrase = await _ask(create: file == null, retry: retry);
        final params = file?.sublist(0, 26) ?? _calibrated(keys);
        final kek = keys.stretch(passphrase, params);
        if (file == null) {
          return (
            keys: keys,
            kek: kek,
            params: params,
            held: <String, Uint8List>{},
          );
        }
        try {
          final box = keys.decryptBlob(kek, file.sublist(26));
          final json = jsonDecode(utf8.decode(box)) as Map<String, Object?>;
          return (
            keys: keys,
            kek: kek,
            params: params,
            held: {
              for (final MapEntry(:key, :value) in json.entries)
                key: base64.decode('$value'),
            },
          );
        } on KernelError {
          keys.drop(kek);
        }
      }
    } catch (_) {
      keys.keyring.close();
      _opening = null;
      rethrow;
    }
  }();

  Future<void> _seal(_Sealed sealed) async {
    final plain = utf8.encode(
      jsonEncode({
        for (final e in sealed.held.entries) e.key: base64.encode(e.value),
      }),
    );
    final box = sealed.keys.encryptBlob(sealed.kek, plain, randomBytes(32));
    plain.fillRange(0, plain.length, 0);
    await _files.write(
      _keystore,
      Uint8List.fromList([...sealed.params, ...box]),
    );
  }

  /// Device parameters (crypto v1): 64 MiB and as many passes as take
  /// 250 ms here, at least 3.
  static Uint8List _calibrated(Keys keys) {
    final salt = randomBytes(16);
    Uint8List params(int t) =>
        Uint8List.fromList([1, 0, 1, 0, 0, 0, 0, 0, t, 1, ...salt]);
    final took = Stopwatch()..start();
    keys.drop(keys.stretch('', params(3)));
    final t = (3 * 250 / max(1, took.elapsedMilliseconds)).ceil();
    return params(min(64, max(3, t)));
  }
}

typedef _Sealed = ({
  Keys keys,
  int kek,
  Uint8List params,
  Map<String, Uint8List> held,
});

const _keystore = 'keystore';
const _lockbox = 'lockbox';
const _objects = 'files/';
const _dev = 'dev';
const _bg = 'bg';
const _recovery = 4;

String _object(String name) => '$_objects${hex(objectId(name))}';
