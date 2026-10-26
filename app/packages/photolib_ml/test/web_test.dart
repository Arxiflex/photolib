// The spike's browser half (ADR-0050): onnxruntime-web, pinned in
// tools/ml/artefacts.json, through the dart:js_interop binding, on its
// WebAssembly CPU backend and on WebGPU where the browser has an adapter,
// compared with the same golden outputs as native_test.dart. The gate runs it
// in Chrome, which on Linux has WebGPU on SwiftShader through
// tool/chrome_webgpu.sh, and in Firefox, without; PHOTOLIB_ML_MODELS=all adds
// SigLIP 2.
@TestOn('browser')
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:photolib_harness/photolib_harness.dart';
import 'package:photolib_ml/photolib_ml_web.dart';
import 'package:test/test.dart';

import 'spike.dart';

@JS('navigator.userAgent')
external String get userAgent;

@JS('crossOriginIsolated')
external bool get crossOriginIsolated;

extension type _Gpu(JSObject _) implements JSObject {
  external JSPromise<JSObject?> requestAdapter();
}

@JS('navigator.gpu')
external _Gpu? get _gpu;

Future<bool> webGpu() async =>
    await _gpu?.requestAdapter().toDart.then((adapter) => adapter != null) ??
    false;

Map<String, Tensor> tensors(Map<String, Input> inputs) => inputs.map(
  (name, input) => MapEntry(
    name,
    (input.int64 ? Tensor.int64(input.shape) : Tensor.float32(input.shape))
      ..values.setAll(0, input.values),
  ),
);

void main() {
  strict();
  late final Ort ort;
  late final Map<String, Uri> models;
  late final List<Case> chosen;
  late final Map<String, List<double>> goldens;
  final browser = RegExp(r'(Chrome|Firefox)/(\d+)').firstMatch(userAgent)!;
  const compiler = bool.fromEnvironment('dart.tool.dart2wasm')
      ? 'dart2wasm'
      : 'dart2js';

  setUpAll(() async {
    final setup = await spawnHybridUri('ml_server.dart').stream.first as Map;
    ort = await Ort.load(Uri.parse(setup['module'] as String));
    models = (setup['models'] as Map).map(
      (k, v) => MapEntry(k as String, Uri.parse(v as String)),
    );
    chosen = selected(setup['selection'] as String?);
    goldens = (jsonDecode(setup['golden'] as String) as Map).map(
      (k, v) => MapEntry(k as String, (v as List).cast<double>()),
    );
  });

  test('the pinned onnxruntime-web runs without cross-origin isolation', () {
    expect(crossOriginIsolated, isFalse);
    expect(ort.version, '1.30.0');
  });

  test(
    'WebGPU without an adapter fails instead of falling back to wasm',
    () async {
      if (await webGpu()) return;
      await expectLater(
        Session.load(ort, models['yunet']!, provider: 'webgpu'),
        throwsA(anything),
      );
    },
  );

  for (final provider in ['wasm', 'webgpu']) {
    test('the models on $provider match the fp32 golden outputs', () async {
      if (provider == 'webgpu' && !await webGpu()) return;
      for (final c in chosen) {
        final input = tensors(c.inputs());
        late Session session;
        final result = await measure(() async {
          session = await Session.load(
            ort,
            models[c.model]!,
            provider: provider,
          );
          return () => session.run(input, c.outputs);
        }, goldens[c.reference]!);
        await session.close();
        // onnxruntime-web logs its warnings, such as initializers among a
        // model's inputs, with console.error.
        expect(takeProblems(), everyElement(contains('[W:onnxruntime:')));
        result.remove('sample');
        // The measurements are the run's report.
        // ignore: avoid_print
        print(
          jsonEncode({
            'target': '${browser[1]} ${browser[2]} $compiler $provider',
            'model': c.model,
            ...result,
          }),
        );
        // Every execution provider must reproduce the CPU reference (design 09
        // §3.2); a variant is measured.
        if (c.model == c.reference) {
          expect(result['cosine'], greaterThanOrEqualTo(.99), reason: c.model);
        }
      }
    });
  }
}
