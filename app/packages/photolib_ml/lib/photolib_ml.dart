/// ONNX Runtime's C API (`onnxruntime_c_api.h`) through dart:ffi, as ADR-0050 chose. Every function is reached
/// through the `OrtApi` table, which only grows, so the library need export nothing but `OrtGetApiBase`. Calls are
/// synchronous and work on any isolate; run them on a background one.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _P = Pointer<Void>;
typedef _Out = Pointer<_P>;
typedef _Str = Pointer<Utf8>;
typedef _Strs = Pointer<_Str>;
typedef _Release = void Function(_P);

/// An error that ONNX Runtime reported.
class OrtException implements Exception {
  OrtException(this.message);

  final String message;

  @override
  String toString() => 'OrtException: $message';
}

/// The library the build hook bundles (hook/build.dart); on iOS, which links
/// the static xcframework, the symbol resolves from the process.
@Native<Pointer<_P> Function()>(
  symbol: 'OrtGetApiBase',
  assetId: 'package:photolib_ml/onnxruntime.dart',
)
external Pointer<_P> _bundledApiBase();

/// An ONNX Runtime library, loaded from a path or bundled with the app.
class Ort {
  Ort.open(String path)
    : this._(
        DynamicLibrary.open(path)
            .lookupFunction<Pointer<_P> Function(), Pointer<_P> Function()>(
              'OrtGetApiBase',
            )(),
      );

  /// The library the build hook bundled for the app's target.
  new bundled() : this._(_bundledApiBase());

  Ort._(this._base) {
    // OrtApiBase is {GetApi, GetVersionString}; API version 17 is ONNX Runtime 1.17, which has every entry used here.
    final api = _base[0]
        .cast<NativeFunction<Pointer<_P> Function(Uint32)>>()
        .asFunction<Pointer<_P> Function(int)>()(17);
    if (api == nullptr) throw OrtException('ONNX Runtime older than 1.17');
    _api = api;
    _env = using(
      (arena) => _make(
        (out) => _createEnv(3, 'photolib'.toNativeUtf8(allocator: arena), out),
      ),
    );
    _cpu = _make((out) => _createCpuMemoryInfo(1, 0, out));
  }

  final Pointer<_P> _base;
  late final Pointer<_P> _api;
  late final _P _env, _cpu;

  /// The library's version, such as `1.31.0`.
  String get version => _base[1]
      .cast<NativeFunction<_Str Function()>>()
      .asFunction<_Str Function()>()()
      .toDartString();

  /// The execution providers this build has, such as `CPUExecutionProvider`.
  List<String> get providers => using((arena) {
    final names = arena<_Strs>();
    final count = arena<Int32>();
    _check(_getAvailableProviders(names, count));
    final result = [
      for (var i = 0; i < count.value; i++) names.value[i].toDartString(),
    ];
    _check(_releaseAvailableProviders(names.value, count.value));
    return result;
  });

  Pointer<NativeFunction<T>> _f<T extends Function>(int index) =>
      _api[index].cast<NativeFunction<T>>();

  void _check(_P status) {
    if (status == nullptr) return;
    final message = _getErrorMessage(status).toDartString();
    _releaseStatus(status);
    throw OrtException(message);
  }

  /// Calls [create] with an out-parameter and returns what it wrote there.
  _P _make(_P Function(_Out out) create) => using((arena) {
    final out = arena<_P>();
    _check(create(out));
    return out.value;
  });

  // Indices into OrtApi, in the order of onnxruntime_c_api.h.
  late final _getErrorMessage = _f<_Str Function(_P)>(2)
      .asFunction<_Str Function(_P)>();
  late final _createEnv = _f<_P Function(Int32, _Str, _Out)>(3)
      .asFunction<_P Function(int, _Str, _Out)>();
  late final _createSession = _f<_P Function(_P, _P, _P, _Out)>(7)
      .asFunction<_P Function(_P, _P, _P, _Out)>();
  late final _run =
      _f<_P Function(_P, _P, _Strs, _Out, Size, _Strs, Size, _Out)>(
        9,
      ).asFunction<_P Function(_P, _P, _Strs, _Out, int, _Strs, int, _Out)>();
  late final _createSessionOptions = _f<_P Function(_Out)>(10)
      .asFunction<_P Function(_Out)>();
  late final _setIntraOpNumThreads = _f<_P Function(_P, Int32)>(24)
      .asFunction<_P Function(_P, int)>();
  late final _createTensor =
      _f<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, _Out)>(
        49,
      ).asFunction<_P Function(_P, _P, int, Pointer<Int64>, int, int, _Out)>();
  late final _getTensorMutableData = _f<_P Function(_P, _Out)>(51)
      .asFunction<_P Function(_P, _Out)>();
  late final _getTensorElementType = _f<_P Function(_P, Pointer<Int32>)>(60)
      .asFunction<_P Function(_P, Pointer<Int32>)>();
  late final _getTensorShapeElementCount = _f<_P Function(_P, Pointer<Size>)>(
    64,
  ).asFunction<_P Function(_P, Pointer<Size>)>();
  late final _getTensorTypeAndShape = _f<_P Function(_P, _Out)>(65)
      .asFunction<_P Function(_P, _Out)>();
  late final _createCpuMemoryInfo = _f<_P Function(Int32, Int32, _Out)>(69)
      .asFunction<_P Function(int, int, _Out)>();
  late final _releaseStatus = _release(93);
  late final _releaseSession = _release(95);
  late final _releaseValue = _release(96);
  late final _releaseTypeAndShape = _release(99);
  late final _releaseSessionOptions = _release(100);
  late final _getAvailableProviders =
      _f<_P Function(Pointer<_Strs>, Pointer<Int32>)>(125)
          .asFunction<_P Function(Pointer<_Strs>, Pointer<Int32>)>();
  late final _releaseAvailableProviders = _f<_P Function(_Strs, Int32)>(126)
      .asFunction<_P Function(_Strs, int)>();
  late final _appendExecutionProvider =
      _f<_P Function(_P, _Str, _Strs, _Strs, Size)>(216)
          .asFunction<_P Function(_P, _Str, _Strs, _Strs, int)>();

  _Release _release(int index) =>
      _f<Void Function(_P)>(index).asFunction<_Release>();
}

/// A tensor in native memory, which ONNX Runtime reads in place: an input is never copied, and another isolate can
/// run a tensor that this one filled. Free it when no session needs it any more.
class Tensor {
  Tensor.float32(this.shape) : _int64 = false, pointer = _allocate(shape, 4);
  Tensor.int64(this.shape) : _int64 = true, pointer = _allocate(shape, 8);

  final List<int> shape;
  final Pointer<Void> pointer;
  final bool _int64;

  int get length => shape.fold(1, (a, b) => a * b);

  /// The values, a view of the native memory: a Float32List or an Int64List.
  List<num> get values => _int64
      ? pointer.cast<Int64>().asTypedList(length)
      : pointer.cast<Float>().asTypedList(length);

  void free() => calloc.free(pointer);

  static Pointer<Void> _allocate(List<int> shape, int bytes) =>
      calloc<Uint8>(shape.fold(bytes, (a, b) => a * b)).cast();
}

/// A model loaded for inference.
class Session {
  /// Loads the model at [path] on the CPU or, with [provider], on an execution provider such as `XNNPACK`, `CoreML`
  /// or `WebGPU` (nodes it cannot run stay on the CPU). A provider this build lacks is an error, never a silent
  /// fallback to the CPU. [threads] 0 lets ONNX Runtime choose.
  Session(this._ort, String path, {String? provider, int threads = 0}) {
    final options = _ort._make(_ort._createSessionOptions);
    try {
      using((arena) {
        _ort._check(_ort._setIntraOpNumThreads(options, threads));
        if (provider != null) {
          _ort._check(
            _ort._appendExecutionProvider(
              options,
              provider.toNativeUtf8(allocator: arena),
              nullptr,
              nullptr,
              0,
            ),
          );
        }
        // ORTCHAR_T is wchar_t, UTF-16, on Windows.
        final file = Platform.isWindows
            ? path.toNativeUtf16(allocator: arena).cast<Void>()
            : path.toNativeUtf8(allocator: arena).cast<Void>();
        _session = _ort._make(
          (out) => _ort._createSession(_ort._env, file, options, out),
        );
      });
    } finally {
      _ort._releaseSessionOptions(options);
    }
  }

  final Ort _ort;
  late final _P _session;

  /// Runs the model on [inputs] by name and returns the float32 [outputs] it names, copied out.
  List<Float32List> run(Map<String, Tensor> inputs, List<String> outputs) =>
      using((arena) {
        final names = arena<_Str>(inputs.length);
        final values = arena<_P>(inputs.length);
        final wanted = arena<_Str>(outputs.length);
        final results = arena<_P>(outputs.length);
        try {
          var i = 0;
          for (final MapEntry(key: name, value: tensor) in inputs.entries) {
            final shape = arena<Int64>(tensor.shape.length);
            shape.asTypedList(tensor.shape.length).setAll(0, tensor.shape);
            names[i] = name.toNativeUtf8(allocator: arena);
            values[i++] = _ort._make(
              (out) => _ort._createTensor(
                _ort._cpu,
                tensor.pointer,
                tensor.length * (tensor._int64 ? 8 : 4),
                shape,
                tensor.shape.length,
                tensor._int64
                    ? 7
                    : 1, // ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 : _FLOAT
                out,
              ),
            );
          }
          for (var j = 0; j < outputs.length; j++) {
            wanted[j] = outputs[j].toNativeUtf8(allocator: arena);
          }
          _ort._check(
            _ort._run(
              _session,
              nullptr,
              names,
              values,
              inputs.length,
              wanted,
              outputs.length,
              results,
            ),
          );
          return [for (var j = 0; j < outputs.length; j++) _floats(results[j])];
        } finally {
          for (var j = 0; j < inputs.length; j++) {
            if (values[j] != nullptr) _ort._releaseValue(values[j]);
          }
          for (var j = 0; j < outputs.length; j++) {
            if (results[j] != nullptr) _ort._releaseValue(results[j]);
          }
        }
      });

  void close() => _ort._releaseSession(_session);

  Float32List _floats(_P value) {
    final info = _ort._make((out) => _ort._getTensorTypeAndShape(value, out));
    try {
      return using((arena) {
        final type = arena<Int32>(), count = arena<Size>();
        _ort._check(_ort._getTensorElementType(info, type));
        _ort._check(_ort._getTensorShapeElementCount(info, count));
        if (type.value != 1) throw OrtException('output type ${type.value}');
        final data = _ort._make(
          (out) => _ort._getTensorMutableData(value, out),
        );
        return Float32List.fromList(
          data.cast<Float>().asTypedList(count.value),
        );
      });
    } finally {
      _ort._releaseTypeAndShape(info);
    }
  }
}
