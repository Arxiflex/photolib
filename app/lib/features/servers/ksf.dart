/// The Argon2id cost of new passwords, calibrated on the device (ADR-0125).
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib_api/kernel.dart' as kernel;

/// How long one Argon2id derivation with a parameter set takes here; an
/// error where it cannot run, as without its memory. Tests fake it.
typedef Stretch = Future<Duration> Function(Uint8List params);

/// Times a derivation with the kernel, off the root isolate.
final stretchProvider = Provider<Stretch>((ref) => _stretch);

Future<Duration> _stretch(Uint8List params) async {
  // A native kernel that cannot allocate aborts the app: an Android phone with
  // less than 4 GiB of memory does not try more than 128 MiB.
  if (ByteData.sublistView(params).getUint32(1) > 128 << 10 &&
      !kIsWeb &&
      Platform.isAndroid &&
      constrained(await File('/proc/meminfo').readAsString())) {
    throw StateError('Argon2id: too little memory for 256 MiB');
  }
  return Duration(microseconds: await compute(_timed, params));
}

Future<int> _timed(Uint8List params) async {
  final keyring = (await loadKernel())();
  try {
    final took = Stopwatch()..start();
    final answer = kernel.CallResponse.fromBuffer(
      keyring.call(
        kernel.Method.METHOD_DERIVE_PASSWORD_KEY.value,
        kernel.DerivePasswordKeyRequest(params: params).writeToBuffer(),
      ),
    );
    if (answer.hasError()) throw StateError('Argon2id: ${answer.error}');
    return took.elapsedMicroseconds;
  } finally {
    keyring.close();
  }
}

/// The Argon2id parameters of a new password, calibrated as
/// docs/dev/crypto-v1.md says: as many passes as take about a second here,
/// from 256 MiB and three, or 128 MiB and six where 256 MiB cannot be had, at
/// most 64; one lane and a new salt.
Future<Uint8List> newPasswordParams(Stretch stretch) async {
  final salt = randomBytes(16);
  var (mib, t) = (256, 3);
  Duration took;
  try {
    took = await stretch(ksfParams(mib, t, salt));
  } on Object {
    (mib, t) = (128, 6);
    took = await stretch(ksfParams(mib, t, salt));
  }
  final passes = (t * 1e6 / max(1, took.inMicroseconds)).ceil();
  return ksfParams(mib, min(64, max(t, passes)), salt);
}

/// An Argon2id parameter set of crypto v1: [mib] MiB, [t] passes, one lane.
Uint8List ksfParams(int mib, int t, List<int> salt) => Uint8List.fromList([
  1,
  ...(ByteData(9)
        ..setUint32(0, mib << 10)
        ..setUint32(4, t)
        ..setUint8(8, 1))
      .buffer
      .asUint8List(),
  ...salt,
]);

/// Whether [meminfo], `/proc/meminfo` where there is one, says the device has
/// less than 4 GiB of memory.
bool constrained(String? meminfo) {
  final total = RegExp(
    r'^MemTotal:\s+(\d+) kB',
    multiLine: true,
  ).firstMatch(meminfo ?? '')?[1];
  return (int.tryParse(total ?? '') ?? 4 << 20) < 4 << 20;
}

/// [length] bytes from a secure random source.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}
