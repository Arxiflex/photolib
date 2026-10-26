import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.keystore');

/// The native keystore keys of the local store (ADR-0057): 32 random bytes per key that the platform keystore holds,
/// readable after the device's first unlock and never backed up or synced.
class SecureStorageKeystore implements DeviceKeystore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // The data-protection keychain needs a signed app; the login keychain does not.
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
  );

  static String _key(String name) => 'photolib.keystore.$name';

  @override
  Future<Uint8List?> read(String name) async {
    final value = await _call(() => _storage.read(key: _key(name)));
    return value == null ? null : base64.decode(value);
  }

  @override
  Future<Uint8List> create(String name) async {
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    await _call(
      () => _storage.write(key: _key(name), value: base64.encode(key)),
    );
    return key;
  }

  @override
  Future<void> delete(String name) =>
      _call(() => _storage.delete(key: _key(name)));
}

/// [call], whose libsecret codes for a Secret Service that does not answer or
/// a keyring that stays locked become [KeystoreUnavailable].
Future<T> _call<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    if (e.code == 'Libsecret error' || e.code == 'KeyringLocked') {
      throw KeystoreUnavailable(e);
    }
    rethrow;
  }
}

/// The platform keystore does not answer: on Linux no Secret Service runs for
/// a store whose keys it holds (ADR-0154), or its keyring stays locked. Only
/// the user can change that (ADR-0057).
class KeystoreUnavailable implements Exception {
  /// What the keystore answered.
  const new(this.cause);

  /// The keystore's answer.
  final PlatformException cause;

  @override
  String toString() => 'KeystoreUnavailable: $cause';
}

/// The store's keystore on Linux (docs/10 §8.2, ADR-0154): the Secret Service,
/// or, when none runs as the store makes its first key, keys sealed under a
/// passphrase for good. Keys the Secret Service holds are never looked for
/// elsewhere, and a locked keyring is no missing one.
class FallbackKeystore implements DeviceKeystore {
  /// The Secret Service [_service], else [_passphrase].
  new(this._service, this._passphrase);

  final DeviceKeystore _service;
  final PassphraseKeystore _passphrase;
  DeviceKeystore? _chosen;

  Future<T> _use<T>(
    Future<T> Function(DeviceKeystore keystore) run, {
    bool fallback = false,
  }) async {
    if (_chosen case final chosen?) return await run(chosen);
    if (await _passphrase.exists) return await run(_chosen = _passphrase);
    try {
      final result = await run(_service);
      _chosen = _service;
      return result;
    } on Exception catch (e) {
      final answer = e is KeystoreUnavailable ? e.cause : e;
      if (!fallback ||
          answer is! PlatformException ||
          answer.code == 'KeyringLocked') {
        rethrow;
      }
      _log.warning('no Secret Service: keys under a passphrase', error: e);
      return await run(_chosen = _passphrase);
    }
  }

  @override
  Future<Uint8List?> read(String name) => _use((k) => k.read(name));

  @override
  Future<Uint8List> create(String name) =>
      _use((k) => k.create(name), fallback: true);

  @override
  Future<void> delete(String name) => _use((k) => k.delete(name));
}

/// A passphrase the keystore asks for: a new one when `create`, else the one
/// chosen, again after a wrong one when `retry`; `answer` takes it.
typedef PassphrasePrompt = ({
  bool create,
  bool retry,
  Completer<String> answer,
});

/// The passphrase prompt shown, if any (PassphraseGate).
class PassphrasePrompts extends Notifier<PassphrasePrompt?> {
  @override
  PassphrasePrompt? build() => null;

  /// Shows a prompt and returns what the user typed.
  Future<String> ask({required bool create, required bool retry}) async {
    final prompt = (create: create, retry: retry, answer: Completer<String>());
    state = prompt;
    try {
      return await prompt.answer.future;
    } finally {
      if (state?.answer == prompt.answer) state = null;
    }
  }
}

/// The passphrase prompt shown, if any.
final passphrasePromptProvider =
    NotifierProvider<PassphrasePrompts, PassphrasePrompt?>(
      PassphrasePrompts.new,
    );

/// One secret text of this install, such as its server sessions.
abstract interface class SecretStore {
  Future<String?> read();

  /// Replaces the text; null deletes it.
  Future<void> write(String? value);
}

/// A [SecretStore] in the platform keystore, as [SecureStorageKeystore] keeps its keys.
class KeystoreEntry implements SecretStore {
  const KeystoreEntry(this.name);

  final String name;

  @override
  Future<String?> read() => _call(
    () => SecureStorageKeystore._storage.read(
      key: SecureStorageKeystore._key(name),
    ),
  );

  @override
  Future<void> write(String? value) => _call(
    () => SecureStorageKeystore._storage.write(
      key: SecureStorageKeystore._key(name),
      value: value,
    ),
  );
}
