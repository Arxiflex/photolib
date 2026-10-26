/// The Photolib kernel on the web: the WebAssembly module that `tools/kernel/wasm.sh` builds from `kernel/wasm`,
/// through `dart:js_interop`, for dart2js and dart2wasm alike. Its API is the one of `photolib_kernel.dart`, so code
/// that imports this library `if (dart.library.js_interop)` runs on every target.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'keyring.dart';

export 'keyring.dart';

extension type _Module(JSObject _) implements JSObject {
  @JS('default')
  external JSPromise<JSAny?> init();
}

extension type _Guard(JSObject _) implements JSObject {
  external JSAny? guard(JSObject target, String method, [JSAny? a, JSAny? b]);
}

/// The kernel module, loaded when first needed. WebAssembly cannot unwind, so a panic traps the module: the call that
/// trapped returns kernel.panic, as natively, and since a trap may leave the module broken, it and its keyrings and
/// streams refuse every later call with a [StateError]; load the module again.
class Kernel {
  Kernel._(this._instance);

  final _Instance _instance;
  static var _loads = 0;

  /// Loads a new instance of the module from [url], its JavaScript file (`photolib_kernel_wasm.js`), which fetches
  /// the `.wasm` beside it. The module is single-threaded, so the page needs no cross-origin isolation.
  static Future<Kernel> load(Uri url) async {
    final guard = url.resolve('photolib_kernel_guard.js').toString();
    // A URL of its own makes each load a new instance.
    final unique = url.replace(fragment: '${_loads++}').toString();
    final module = _Module(await importModule(unique.toJS).toDart);
    await module.init().toDart;
    return Kernel._(
      _Instance(module, _Guard(await importModule(guard.toJS).toDart)),
    );
  }

  /// Runs the function [method] (a `photolib.kernel.v1.Method`) on the encoded request message.
  Uint8List call(int method, Uint8List request) =>
      _instance.bytes(_instance.module, 'call', method.toJS, request.toJS);

  /// Opens a stream of [method]; push the input to it in pieces, then finish it.
  KernelStream openStream(int method, Uint8List request) =>
      _instance.stream(_instance.module, method, request);

  /// A new, empty keyring.
  Keyring keyring() => Keyring._(
    _instance,
    _instance.call(_instance.module, 'newKeyring')! as JSObject,
  );
}

/// One instance of the module, which every call enters through the guard, and which is unusable once one trapped.
class _Instance {
  _Instance(this.module, this._guard);

  final JSObject module;
  final _Guard _guard;
  var _trapped = false;

  /// [method] of [target], an object of this instance, or null if it trapped.
  JSAny? call(JSObject target, String method, [JSAny? a, JSAny? b]) {
    if (_trapped) throw StateError('the kernel module trapped: load it again');
    final result = _guard.guard(target, method, a, b);
    _trapped = result == null;
    return result;
  }

  Uint8List bytes(JSObject target, String method, [JSAny? a, JSAny? b]) {
    final result = call(target, method, a, b) as JSUint8Array?;
    return result?.toDart ?? Uint8List.fromList(kernelPanic);
  }

  KernelStream stream(JSObject target, int method, Uint8List request) =>
      KernelStream._(
        this,
        call(target, 'openStream', method.toJS, request.toJS) as JSObject?,
      );
}

/// Keys inside the module, named by handles in requests. [close] zeroizes them all, as locking the app does.
class Keyring implements KernelKeyring {
  Keyring._(this._instance, this._keyring);

  final _Instance _instance;
  JSObject? _keyring;

  JSObject get _live => _keyring ?? (throw StateError('the keyring is closed'));

  @override
  Uint8List call(int method, Uint8List request) =>
      _instance.bytes(_live, 'call', method.toJS, request.toJS);

  /// Opens a stream of [method] with this keyring's keys.
  KernelStream openStream(int method, Uint8List request) =>
      _instance.stream(_live, method, request);

  @override
  void close() {
    final keyring = _keyring;
    _keyring = null;
    // Through the guard: a trapped instance may trap again.
    if (keyring != null) _instance._guard.guard(keyring, 'free');
  }
}

/// A streaming call; finishing it frees it. Every step of a stream whose opening trapped returns kernel.panic.
class KernelStream {
  KernelStream._(this._instance, this._stream);

  final _Instance _instance;
  final JSObject? _stream;

  Uint8List push(Uint8List input) => _step('push', input.toJS);

  Uint8List finish() => _step('finish');

  Uint8List _step(String method, [JSAny? input]) => switch (_stream) {
    final stream? => _instance.bytes(stream, method, input),
    null => Uint8List.fromList(kernelPanic),
  };
}
