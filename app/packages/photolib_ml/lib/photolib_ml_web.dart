/// ONNX Runtime on the web: onnxruntime-web's WebAssembly build with its WebGPU execution provider, through
/// dart:js_interop for dart2js and dart2wasm alike. Its API is the one of `photolib_ml.dart`, asynchronous as the
/// browser is; it runs single-threaded, so the page needs no cross-origin isolation.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

extension type _Module(JSObject _) implements JSObject {
  external _Env get env;
  @JS('InferenceSession')
  external _Sessions get sessions;
  @JS('Tensor')
  external JSFunction get tensor;
}

extension type _Env(JSObject _) implements JSObject {
  external _Wasm get wasm;
  external _Versions get versions;
}

extension type _Wasm(JSObject _) implements JSObject {
  external set wasmPaths(JSAny value);
  external set numThreads(int value);
}

extension type _Versions(JSObject _) implements JSObject {
  external String get web;
}

extension type _Sessions(JSObject _) implements JSObject {
  external JSPromise<_Session> create(String model, JSAny options);
}

extension type _Session(JSObject _) implements JSObject {
  external JSPromise<JSObject> run(JSObject feeds, JSArray<JSString> fetches);
  external JSPromise<JSAny?> release();
}

/// The onnxruntime-web module, loaded when first needed.
class Ort {
  Ort._(this._module);

  final _Module _module;

  /// Loads the ES module at [url] (`ort.webgpu.bundle.min.mjs`), which fetches its `.wasm` from beside it.
  static Future<Ort> load(Uri url) async {
    final module = _Module(await importModule(url.toString().toJS).toDart);
    final wasm = url.resolve('ort-wasm-simd-threaded.asyncify.wasm');
    module.env.wasm
      ..wasmPaths = {'wasm': '$wasm'}.jsify()!
      ..numThreads = 1;
    return Ort._(module);
  }

  String get version => _module.env.versions.web;
}

/// A tensor in a JavaScript typed array, which onnxruntime-web reads in place.
class Tensor {
  Tensor.float32(this.shape) : _int64 = false {
    _floats = JSFloat32Array.withLength(length);
  }
  Tensor.int64(this.shape) : _int64 = true {
    _ints = List.filled(length, 0);
  }

  final List<int> shape;
  final bool _int64;
  late final JSFloat32Array _floats;
  late final List<int> _ints;

  int get length => shape.fold(1, (a, b) => a * b);

  /// The values: a Float32List over the typed array, or the int64 values, which become a BigInt64Array when run.
  List<num> get values => _int64 ? _ints : _floats.toDart;

  JSObject _value(_Module ort) => ort.tensor.callAsConstructor(
    (_int64 ? 'int64' : 'float32').toJS,
    _int64
        ? globalContext
              .getProperty<JSObject>('BigInt64Array'.toJS)
              .callMethod('from'.toJS, _ints.jsify(), globalContext['BigInt'])
        : _floats,
    shape.jsify(),
  );
}

/// A model loaded for inference.
class Session {
  Session._(this._ort, this._session);

  final Ort _ort;
  final _Session _session;

  /// Loads the model at [url] on one execution provider, `wasm` (the CPU) or `webgpu`; one the browser cannot run
  /// is an error, never a fallback to another.
  static Future<Session> load(
    Ort ort,
    Uri url, {
    String provider = 'wasm',
  }) async => Session._(
    ort,
    await ort._module.sessions
        .create(
          url.toString(),
          {
            'executionProviders': [provider],
          }.jsify()!,
        )
        .toDart,
  );

  /// Runs the model on [inputs] by name and returns the float32 [outputs] it names, copied out.
  Future<List<Float32List>> run(
    Map<String, Tensor> inputs,
    List<String> outputs,
  ) async {
    final feeds = JSObject();
    inputs.forEach((name, tensor) => feeds[name] = tensor._value(_ort._module));
    final results = await _session
        .run(feeds, [for (final name in outputs) name.toJS].toJS)
        .toDart;
    return [
      for (final name in outputs)
        Float32List.fromList(
          results
              .getProperty<JSObject>(name.toJS)
              .getProperty<JSFloat32Array>('data'.toJS)
              .toDart,
        ),
    ];
  }

  Future<void> close() => _session.release().toDart;
}
