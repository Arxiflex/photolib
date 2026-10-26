/// The kernel's OPAQUE steps of signing in and setting a password.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/features/servers/ksf.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_data/photolib_data.dart' show KernelError;
import 'package:protobuf/protobuf.dart';

/// A kernel OPAQUE step (`METHOD_OPAQUE_REGISTER` or `_LOGIN`); its Argon2id
/// takes a second, so it runs off the root isolate. Tests fake it.
typedef Opaque = Future<kernel.OpaqueClientResponse> Function(
  kernel.Method method,
  GeneratedMessage request,
);

/// The kernel's OPAQUE steps.
final opaqueProvider = Provider<Opaque>((ref) => _opaque);

Future<kernel.OpaqueClientResponse> _opaque(
  kernel.Method method,
  GeneratedMessage request,
) async {
  final answer = kernel.CallResponse.fromBuffer(
    await compute(_kernelCall, (method.value, request.writeToBuffer())),
  );
  if (answer.hasError()) {
    final error = answer.error;
    throw KernelError(error.code.value, error.params['reason'] ?? '');
  }
  return kernel.OpaqueClientResponse.fromBuffer(answer.response);
}

Future<Uint8List> _kernelCall((int, Uint8List) call) async {
  final keyring = (await loadKernel())();
  try {
    return keyring.call(call.$1, call.$2);
  } finally {
    keyring.close();
  }
}

/// KE3 of an OPAQUE sign-in with [password] through the kernel, once [start]
/// answered its KE1 with the account's Argon2id parameters and KE2.
Future<List<int>> opaqueKe3(
  Opaque opaque,
  String password,
  Future<(List<int>, List<int>)> Function(List<int> ke1) start,
) async {
  final randomness = randomBytes(128);
  kernel.OpaqueLoginRequest step(List<int> params, [List<int>? ke2]) =>
      kernel.OpaqueLoginRequest(
        password: password,
        params: params,
        randomness: randomness,
        ke2: ke2,
      );
  const login = kernel.Method.METHOD_OPAQUE_LOGIN;
  // The first step derives nothing; the account's cost comes with KE2.
  final ke1 = await opaque(login, step(ksfParams(128, 3, Uint8List(16))));
  final (params, ke2) = await start(ke1.message);
  return (await opaque(login, step(params, ke2))).message;
}
