import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:photolib_kernel/keyring.dart';

/// A kernel call failed: [code] is a `photolib.kernel.v1.CallErrorCode`, [reason] the crypto specification's error.
class KernelError implements Exception {
  KernelError(this.code, this.reason);

  final int code;
  final String reason;

  @override
  String toString() => 'KernelError($code, $reason)';
}

/// The kernel calls of the local store over a [KernelKeyring], encoding their few protobuf messages by hand
/// (proto/photolib/kernel/v1). Fields are given as (number, value): an int is a varint, bytes and strings are
/// length-delimited, a list of fields is a nested message.
extension type Keys(KernelKeyring keyring) {
  /// Imports [secret], zeroes it, and returns its handle.
  int import(Uint8List secret) {
    try {
      return _key(_call(5, [(1, secret)]));
    } finally {
      secret.fillRange(0, secret.length, 0);
    }
  }

  void drop(int key) => _call(6, [(1, key)]);

  /// `KEK_pass`: [passcode] stretched with the Argon2id parameter set [params] and the hardware binding's output.
  int stretch(String passcode, Uint8List params, [Uint8List? hardware]) => _key(
    _call(8, [(1, passcode), (2, params), (3, 'kek/passcode'), (4, hardware)]),
  );

  int derive(int key, String label, [Uint8List? context]) =>
      _key(_call(7, [(1, key), (2, label), (3, context)]));

  /// The cache key of the device data key [ddk] (docs/21 §4).
  int cacheKey(int ddk) => derive(ddk, 'local/cache');

  /// The key of class C object [name] under [cacheKey].
  int objectKey(int cacheKey, String name) =>
      derive(cacheKey, 'local/object', objectId(name));

  Uint8List encryptBlob(int key, Uint8List plaintext, Uint8List salt) =>
      _one(_call(10, [(1, key), (2, 11), (5, salt), (6, plaintext)]));

  Uint8List decryptBlob(int key, Uint8List envelope) =>
      _one(_call(11, [(1, key), (2, 11), (4, envelope)]));

  /// [plaintext] sealed, padded, under the object key of content kind [kind]
  /// of [fileKey] (crypto-v1, Key derivation).
  Uint8List sealObject(
    int fileKey,
    int kind,
    Uint8List plaintext,
    Uint8List salt,
  ) => _object(
    fileKey,
    kind,
    (key) =>
        _call(10, [(1, key), (2, kind), (4, 1), (5, salt), (6, plaintext)]),
  );

  /// What [sealObject] sealed.
  Uint8List openObject(int fileKey, int kind, Uint8List envelope) => _object(
    fileKey,
    kind,
    (key) => _call(11, [(1, key), (2, kind), (4, envelope)]),
  );

  Uint8List _object(int fileKey, int kind, Uint8List Function(int key) use) {
    final key = derive(fileKey, 'file-key', Uint8List.fromList([kind]));
    try {
      return _one(use(key));
    } finally {
      drop(key);
    }
  }

  /// Seals the device data key [ddk] in a lockbox, a slot for each factor
  /// (1 keystore, 4 recovery code): wrapped under a key handle, or the wrap a
  /// lockbox it replaces held.
  Uint8List sealLockbox(
    int ddk,
    Uint8List deviceId,
    List<(int, Object)> slots,
  ) => _one(
    _call(14, [
      (1, ddk),
      (2, deviceId),
      for (final (factor, key) in slots)
        (
          3,
          key is int
              ? [(1, factor), (6, key), (7, randomBytes(24))]
              : [(1, factor), (5, key)],
        ),
    ]),
  );

  /// The device data key in [slot] of [lockbox], under [key].
  int openLockbox(Uint8List lockbox, int key, {int slot = 0}) =>
      _key(_call(16, [(1, lockbox), (2, slot), (3, key)]));

  /// The device id of [lockbox], and the factor and wrap of each slot.
  (Uint8List, List<(int, Uint8List)>) readLockbox(Uint8List lockbox) {
    final response = _call(15, [(1, lockbox)]);
    final slots = [
      for (final (n, slot) in _scan(response))
        if (n == 3) _fields(slot),
    ];
    return (
      _one(response),
      [
        for (final s in slots)
          (_varint(s[1] ?? Uint8List(0)), s[5] ?? Uint8List(0)),
      ],
    );
  }

  /// `KEK_rec`, from a recovery code's [entropy], which this zeroes.
  int recoveryKey(Uint8List entropy) {
    final secret = import(entropy);
    final key = derive(secret, 'kek/recovery');
    drop(secret);
    return key;
  }

  Uint8List databaseKey(int ddk, Uint8List fileId) =>
      _one(_call(37, [(1, ddk), (2, fileId)]));

  Uint8List _call(int method, List<(int, Object?)> fields) {
    final request = _encode(fields);
    final Map<int, Uint8List> response;
    try {
      response = _fields(keyring.call(method, request));
    } finally {
      request.fillRange(0, request.length, 0);
    }
    final error = response[2];
    if (error == null) return response[1] ?? Uint8List(0);
    final params = {
      for (final (n, entry) in _scan(error))
        if (n == 2)
          utf8.decode(_one(entry)): utf8.decode(_fields(entry)[2] ?? []),
    };
    throw KernelError(
      _varint(_one(error)),
      params['reason'] ?? params['field'] ?? '',
    );
  }

  int _key(Uint8List response) => _varint(_one(response));
}

Uint8List _encode(List<(int, Object?)> fields) {
  final out = BytesBuilder(copy: false);
  void varint(int v) {
    while (v >= 0x80) {
      out.addByte(v & 0x7f | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  for (final (number, value) in fields) {
    if (value == null) continue;
    if (value is int) {
      varint(number << 3);
      varint(value);
      continue;
    }
    final bytes = switch (value) {
      Uint8List b => b,
      String s => utf8.encode(s),
      List<(int, Object?)> m => _encode(m),
      _ => throw ArgumentError.value(value),
    };
    varint(number << 3 | 2);
    varint(bytes.length);
    out.add(bytes);
  }
  return out.takeBytes();
}

final _secure = Random.secure();

/// [length] random bytes.
Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _secure.nextInt(256)));

/// The 16-byte id of a database or object: the start of the SHA-256 of its
/// name.
Uint8List objectId(String name) =>
    Uint8List.fromList(sha256.convert(utf8.encode(name)).bytes.sublist(0, 16));

/// Field 1 of [message], the one field of most responses.
Uint8List _one(Uint8List message) => _fields(message)[1] ?? Uint8List(0);

/// [bytes] in lowercase hex.
String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// The last value of each field of [message]: a varint as its bytes, a length-delimited field as its contents.
Map<int, Uint8List> _fields(Uint8List message) => {
  for (final (n, v) in _scan(message)) n: v,
};

Iterable<(int, Uint8List)> _scan(Uint8List message) sync* {
  var at = 0;
  int varint() {
    var v = 0;
    for (var shift = 0; ; shift += 7) {
      final b = message[at++];
      v |= (b & 0x7f) << shift;
      if (b < 0x80) return v;
    }
  }

  while (at < message.length) {
    final tag = varint();
    if (tag & 7 == 0) {
      final start = at;
      varint();
      yield (tag >> 3, Uint8List.sublistView(message, start, at));
    } else {
      final length = varint();
      yield (tag >> 3, Uint8List.sublistView(message, at, at += length));
    }
  }
}

int _varint(Uint8List bytes) {
  var v = 0;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = v << 7 | bytes[i] & 0x7f;
  }
  return v;
}

/// The `meta_ml` section of a private library's file for an embedding
/// (design 09 §2.3): [vector], half floats as `local_ml` keeps it, with
/// [model] and [rtFlags], sealed and padded under the file's EmbedKey, the
/// object key of content kind 5 of [fileKey], with the random [salt]. The
/// server keeps the first section of each model, which no device rewrites.
Uint8List sealMlSection(
  KernelKeyring keyring,
  int fileKey, {
  required String model,
  required String rtFlags,
  required Uint8List vector,
  required Uint8List salt,
}) => Keys(keyring).sealObject(
  fileKey,
  _embedding,
  utf8.encode(
    jsonEncode({
      'model': model,
      'rt_flags': rtFlags,
      'vec': base64.encode(vector),
    }),
  ),
  salt,
);

/// The JSON of a section [sealMlSection] sealed under [fileKey].
Uint8List openMlSection(KernelKeyring keyring, int fileKey, Uint8List sealed) =>
    Keys(keyring).openObject(fileKey, _embedding, sealed);

/// PLB's content kind of embeddings (crypto-v1).
const _embedding = 5;
