/// The Photolib kernel (`kernel/`) through its C ABI, `kernel/ffi`. Every call and stream step returns an encoded
/// `photolib.kernel.v1.CallResponse`. Keys never leave the kernel: functions that use them name them by handles into a
/// [Keyring].
library;

import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'keyring.dart';

export 'keyring.dart';

final class _Buffer extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int length;
}

final class _Stream extends Opaque {}

final class _Keyring extends Opaque {}

typedef _CallC = _Buffer Function(Uint32, Pointer<Uint8>, Size);
typedef _Call = _Buffer Function(int, Pointer<Uint8>, int);
typedef _OpenC = Pointer<_Stream> Function(Uint32, Pointer<Uint8>, Size);
typedef _Open = Pointer<_Stream> Function(int, Pointer<Uint8>, int);
typedef _PushC = _Buffer Function(Pointer<_Stream>, Pointer<Uint8>, Size);
typedef _Push = _Buffer Function(Pointer<_Stream>, Pointer<Uint8>, int);
typedef _KeyringCallC =
    _Buffer Function(Pointer<_Keyring>, Uint32, Pointer<Uint8>, Size);
typedef _KeyringCall =
    _Buffer Function(Pointer<_Keyring>, int, Pointer<Uint8>, int);
typedef _KeyringOpenC =
    Pointer<_Stream> Function(Pointer<_Keyring>, Uint32, Pointer<Uint8>, Size);
typedef _KeyringOpen =
    Pointer<_Stream> Function(Pointer<_Keyring>, int, Pointer<Uint8>, int);

// The library that the build hook (hook/build.dart) bundles: its asset id is this library's URI.
@Native<_CallC>(symbol: 'photolib_kernel_call')
external _Buffer _bundledCall(int method, Pointer<Uint8> data, int length);
@Native<_OpenC>(symbol: 'photolib_kernel_stream_open')
external Pointer<_Stream> _bundledOpen(
  int method,
  Pointer<Uint8> data,
  int length,
);
@Native<_PushC>(symbol: 'photolib_kernel_stream_push')
external _Buffer _bundledPush(
  Pointer<_Stream> stream,
  Pointer<Uint8> data,
  int length,
);
@Native<_Buffer Function(Pointer<_Stream>)>(
  symbol: 'photolib_kernel_stream_finish',
)
external _Buffer _bundledFinish(Pointer<_Stream> stream);
@Native<Void Function(_Buffer)>(symbol: 'photolib_kernel_free')
external void _bundledFree(_Buffer buffer);
@Native<Pointer<_Keyring> Function()>(symbol: 'photolib_kernel_keyring_new')
external Pointer<_Keyring> _bundledKeyringNew();
@Native<_KeyringCallC>(symbol: 'photolib_kernel_keyring_call')
external _Buffer _bundledKeyringCall(
  Pointer<_Keyring> keyring,
  int method,
  Pointer<Uint8> data,
  int length,
);
@Native<_KeyringOpenC>(symbol: 'photolib_kernel_keyring_stream_open')
external Pointer<_Stream> _bundledKeyringOpen(
  Pointer<_Keyring> keyring,
  int method,
  Pointer<Uint8> data,
  int length,
);
@Native<Void Function(Pointer<_Keyring>)>(
  symbol: 'photolib_kernel_keyring_free',
)
external void _bundledKeyringFree(Pointer<_Keyring> keyring);

/// The kernel library: the prebuilt one bundled with the app, or one loaded from a path.
class Kernel {
  Kernel()
    : _call = _bundledCall,
      _open = _bundledOpen,
      _push = _bundledPush,
      _finish = _bundledFinish,
      _free = _bundledFree,
      _keyringNew = _bundledKeyringNew,
      _keyringCall = _bundledKeyringCall,
      _keyringOpen = _bundledKeyringOpen,
      _keyringFree = _bundledKeyringFree;

  Kernel.open(String path) : this._(DynamicLibrary.open(path));

  Kernel._(DynamicLibrary library)
    : _call = library.lookupFunction<_CallC, _Call>('photolib_kernel_call'),
      _open = library.lookupFunction<_OpenC, _Open>(
        'photolib_kernel_stream_open',
      ),
      _push = library.lookupFunction<_PushC, _Push>(
        'photolib_kernel_stream_push',
      ),
      _finish = library
          .lookupFunction<
            _Buffer Function(Pointer<_Stream>),
            _Buffer Function(Pointer<_Stream>)
          >('photolib_kernel_stream_finish'),
      _free = library
          .lookupFunction<Void Function(_Buffer), void Function(_Buffer)>(
            'photolib_kernel_free',
          ),
      _keyringNew = library
          .lookupFunction<
            Pointer<_Keyring> Function(),
            Pointer<_Keyring> Function()
          >('photolib_kernel_keyring_new'),
      _keyringCall = library.lookupFunction<_KeyringCallC, _KeyringCall>(
        'photolib_kernel_keyring_call',
      ),
      _keyringOpen = library.lookupFunction<_KeyringOpenC, _KeyringOpen>(
        'photolib_kernel_keyring_stream_open',
      ),
      _keyringFree = library
          .lookupFunction<
            Void Function(Pointer<_Keyring>),
            void Function(Pointer<_Keyring>)
          >('photolib_kernel_keyring_free');

  final _Call _call;
  final _Open _open;
  final _Push _push;
  final _Buffer Function(Pointer<_Stream>) _finish;
  final void Function(_Buffer) _free;
  final Pointer<_Keyring> Function() _keyringNew;
  final _KeyringCall _keyringCall;
  final _KeyringOpen _keyringOpen;
  final void Function(Pointer<_Keyring>) _keyringFree;

  /// Runs the function [method] (a `photolib.kernel.v1.Method`) on the encoded request message.
  Uint8List call(int method, Uint8List request) =>
      _take(_withBytes(request, (data, n) => _call(method, data, n)));

  /// Opens a stream of [method]; push the input to it in pieces, then finish it.
  KernelStream openStream(int method, Uint8List request) => KernelStream._(
    this,
    _withBytes(request, (data, n) => _open(method, data, n)),
  );

  /// A new, empty keyring.
  Keyring keyring() => Keyring._(this, _keyringNew());

  Uint8List _take(_Buffer buffer) {
    final bytes = Uint8List.fromList(buffer.data.asTypedList(buffer.length));
    _free(buffer);
    return bytes;
  }
}

/// Keys inside the kernel, named by handles in requests. [close] zeroizes them all, as locking the app does.
class Keyring implements KernelKeyring {
  Keyring._(this._kernel, this._keyring);

  final Kernel _kernel;
  Pointer<_Keyring>? _keyring;

  Pointer<_Keyring> get _live =>
      _keyring ?? (throw StateError('the keyring is closed'));

  @override
  Uint8List call(int method, Uint8List request) => _kernel._take(
    _withBytes(
      request,
      (data, n) => _kernel._keyringCall(_live, method, data, n),
    ),
  );

  /// Opens a stream of [method] with this keyring's keys.
  KernelStream openStream(int method, Uint8List request) => KernelStream._(
    _kernel,
    _withBytes(
      request,
      (data, n) => _kernel._keyringOpen(_live, method, data, n),
    ),
  );

  @override
  void close() {
    final keyring = _keyring;
    _keyring = null;
    if (keyring != null) _kernel._keyringFree(keyring);
  }
}

/// A streaming call; finishing it frees it.
class KernelStream {
  KernelStream._(this._kernel, this._stream);

  final Kernel _kernel;
  final Pointer<_Stream> _stream;

  Uint8List push(Uint8List input) => _kernel._take(
    _withBytes(input, (data, n) => _kernel._push(_stream, data, n)),
  );

  Uint8List finish() => _kernel._take(_kernel._finish(_stream));
}

final _zeros = Uint8List(1 << 16);

T _withBytes<T>(
  Uint8List bytes,
  T Function(Pointer<Uint8> data, int length) use,
) {
  final data = malloc<Uint8>(bytes.length);
  final copy = data.asTypedList(bytes.length)..setAll(0, bytes);
  try {
    return use(data, bytes.length);
  } finally {
    // The request may hold a key being imported. setRange copies at memcpy speed; fillRange goes byte by byte.
    for (var at = 0; at < copy.length; at += _zeros.length) {
      copy.setRange(at, min(at + _zeros.length, copy.length), _zeros);
    }
    malloc.free(data);
  }
}
