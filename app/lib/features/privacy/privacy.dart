import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_kernel/keyring.dart';
import 'package:protobuf/protobuf.dart';

/// What turning private mode on makes (design 06 §4, ADR-0255): the keys
/// CreateKeys keeps, and the recovery kit's [phrase] with its [kit] id.
@immutable
class Enrolment {
  /// The [keys] made, the kit's [phrase] and [kit] id.
  const new({required this.keys, required this.phrase, required this.kit});

  /// The identity, its seeds wrapped under the AMK, and the unlock paths.
  final CreateKeysRequest keys;

  /// The 24 words the person writes down.
  final String phrase;

  /// The key id of KEK_rec, which VerifyRecoveryKit names.
  final List<int> kit;
}

/// Why the kernel refused: its reason, such as bad_length, unknown_word (at
/// the 1-based position [word]), bad_checksum, or commitment_mismatch for
/// another kit's phrase.
class KeyRefused implements Exception {
  /// The kernel refused for [reason], at the word [word].
  const new(this.reason, [this.word]);

  /// The reason code of the crypto specification.
  final String reason;

  /// The position of an unknown word.
  final int? word;
}

/// The kernel's part in private mode, off the root isolate: Argon2id takes a
/// second. Tests fake it.
abstract interface class Custody {
  /// A new AMK, identity and recovery kit for [user], the AMK wrapped under
  /// [password] and the kit.
  Future<Enrolment> enrol(String user, String password);

  /// The kit id of [phrase], once its key opened [wrap], the recovery path of
  /// [user]'s AMK; throws [KeyRefused].
  Future<List<int>> openKit(String user, String phrase, List<int> wrap);
}

/// How the app makes and opens private-mode keys.
final custodyProvider = Provider<Custody>((ref) => const _KernelCustody());

/// The signed-in account's keys, read again whenever the page shows.
final FutureProvider<GetKeysResponse> keysProvider = FutureProvider.autoDispose(
  (ref) async {
    final link = ref.watch(sessionProvider) ?? (throw StateError('signed out'));
    return await KeyServiceApi(link).getKeys(null, GetKeysRequest());
  },
);

class _KernelCustody implements Custody {
  const new();

  @override
  Future<Enrolment> enrol(String user, String password) async {
    final (keys, phrase, kit) = await compute(_enrol, (user, password));
    return Enrolment(
      keys: CreateKeysRequest.fromBuffer(keys),
      phrase: phrase,
      kit: kit,
    );
  }

  @override
  Future<List<int>> openKit(String user, String phrase, List<int> wrap) =>
      compute(_openKit, (user, phrase, Uint8List.fromList(wrap)));
}

extension on KernelKeyring {
  T run<T extends GeneratedMessage>(
    kernel.Method method,
    GeneratedMessage request,
    T response,
  ) {
    final answer = kernel.CallResponse.fromBuffer(
      call(method.value, request.writeToBuffer()),
    );
    if (answer.hasError()) {
      final params = answer.error.params;
      throw KeyRefused(
        params['reason'] ?? '',
        int.tryParse(params['word'] ?? ''),
      );
    }
    return response..mergeFromBuffer(answer.response);
  }

  int import(List<int> secret) => run(
    kernel.Method.METHOD_IMPORT_KEY,
    kernel.ImportKeyRequest(secret: secret),
    kernel.KeyResponse(),
  ).key;

  /// [key] wrapped under [wrapping] as [type] of crypto-v1's registry, for
  /// [user] at AMK generation 0.
  List<int> wrap(int wrapping, int key, int type, List<int> user) => run(
    kernel.Method.METHOD_WRAP_KEY,
    kernel.WrapKeyRequest(
      wrappingKey: wrapping,
      key: key,
      wrappedType: type,
      context: kernel.WrapContext(userId: user),
      nonce: _random(24),
    ),
    kernel.WrapKeyResponse(),
  ).wrap;

  List<int> public(int key, kernel.KeyPair pair) => run(
    kernel.Method.METHOD_PUBLIC_KEY,
    kernel.PublicKeyRequest(key: key, keyPair: pair),
    kernel.PublicKeyResponse(),
  ).publicKey;

  kernel.KeyResponse recoveryKey(String phrase) => run(
    kernel.Method.METHOD_RECOVERY_KEY,
    kernel.RecoveryKeyRequest(phrase: phrase),
    kernel.KeyResponse(),
  );
}

// Wrapped types of crypto-v1's registry.
const _amk = 1;
const _signingKey = 8;
const _decryptionKey = 9;

Future<(Uint8List, String, List<int>)> _enrol((String, String) input) async {
  final (user, password) = input;
  final id = _uuid(user);
  final keyring = (await loadKernel())();
  try {
    final amk = keyring.import(_random(32));
    final sign = keyring.import(_random(32));
    final decrypt = keyring.import(_random(32));
    final genesis = keyring.run(
      kernel.Method.METHOD_SIGN_ENTRY,
      kernel.SignEntryRequest(
        key: sign,
        logType: 1,
        bodyType: 1,
        logId: id,
        timeMs: Int64(DateTime.now().millisecondsSinceEpoch),
        body: [
          ...keyring.public(sign, kernel.KeyPair.KEY_PAIR_ED25519),
          ...keyring.public(decrypt, kernel.KeyPair.KEY_PAIR_X_WING),
        ],
      ),
      kernel.SignEntryResponse(),
    );
    // A private library's password path: 256 MiB, three passes, a new salt.
    final params = ksfParams(256, 3, _random(16));
    final kekPassword = keyring.run(
      kernel.Method.METHOD_DERIVE_PASSWORD_KEY,
      kernel.DerivePasswordKeyRequest(
        password: password,
        params: params,
        label: 'kek/password', // i18n-ok: a KDF label, never shown
      ),
      kernel.KeyResponse(),
    );
    final phrase = keyring
        .run(
          kernel.Method.METHOD_RECOVERY_PHRASE,
          kernel.RecoveryPhraseRequest(entropy: _random(32)),
          kernel.RecoveryPhraseResponse(),
        )
        .phrase;
    final kit = keyring.recoveryKey(phrase);
    final keys = CreateKeysRequest(
      identity: genesis.entry,
      signingKey: keyring.wrap(amk, sign, _signingKey, id),
      decryptionKey: keyring.wrap(amk, decrypt, _decryptionKey, id),
      paths: [
        UnlockPath(
          kind: UnlockKind.UNLOCK_KIND_PASSWORD,
          wrap: keyring.wrap(kekPassword.key, amk, _amk, id),
          params: params,
        ),
        UnlockPath(
          kind: UnlockKind.UNLOCK_KIND_RECOVERY,
          wrap: keyring.wrap(kit.key, amk, _amk, id),
        ),
      ],
    );
    return (keys.writeToBuffer(), phrase, kit.keyId);
  } finally {
    keyring.close();
  }
}

Future<List<int>> _openKit((String, String, Uint8List) input) async {
  final (user, phrase, wrap) = input;
  final keyring = (await loadKernel())();
  try {
    final kit = keyring.recoveryKey(phrase);
    keyring.run(
      kernel.Method.METHOD_UNWRAP_KEY,
      kernel.UnwrapKeyRequest(
        wrappingKey: kit.key,
        wrappedType: _amk,
        context: kernel.WrapContext(userId: _uuid(user)),
        wrap: wrap,
      ),
      kernel.KeyResponse(),
    );
    return kit.keyId;
  } finally {
    keyring.close();
  }
}

/// The 16 bytes of a UUID's text.
List<int> _uuid(String id) {
  final hex = id.replaceAll('-', '');
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

List<int> _random(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}
