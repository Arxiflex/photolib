import 'dart:typed_data';

/// The keyring of either binding, for code that runs on every target.
abstract interface class KernelKeyring {
  /// Runs the function [method] with this keyring's keys.
  Uint8List call(int method, Uint8List request);

  /// Zeroizes and frees every key; the keyring is unusable afterwards.
  void close();
}

/// A method id that only panics (`photolib_kernel::PANIC_PROBE`), to test that a panic fails only its call.
const panicProbe = 0x7fffffff;

/// The encoded `CallResponse` of a call that panicked: kernel.panic, `CALL_ERROR_CODE_PANIC`.
const kernelPanic = [0x12, 0x02, 0x08, 0x05];
