// The spike's native half (ADR-0050): ONNX Runtime's official library for this desktop, pinned in
// tools/ml/artefacts.json, through the dart:ffi binding. `flutter test` runs the face models on the CPU;
// PHOTOLIB_ML_MODELS=all adds SigLIP 2 and the quantised variants, and PHOTOLIB_ML_GOLDEN=update rewrites golden.json
// from the fp32 models' outputs.
@TestOn('vm')
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';
import 'package:test/test.dart';

import 'spike.dart';

final runtime = {
  Abi.linuxX64: 'ort-linux-x64',
  Abi.linuxArm64: 'ort-linux-arm64',
  Abi.macosArm64: 'ort-macos-arm64',
  Abi.windowsX64: 'ort-windows-x64',
}[Abi.current()]!;

/// The local files of pinned artefacts, downloaded on first use.
Map<String, String> fetch(List<String> names) {
  final result = Process.runSync('python3', [
    '../../../tools/ml/fetch.py',
    ...names,
  ]);
  if (result.exitCode != 0) {
    throw StateError('tools/ml/fetch.py failed:\n${result.stderr}');
  }
  return (jsonDecode(result.stdout as String) as Map).map(
    (name, files) => MapEntry(name as String, (files as List).first as String),
  );
}

Map<String, Tensor> tensors(Map<String, Input> inputs) => inputs.map(
  (name, input) => MapEntry(
    name,
    (input.int64 ? Tensor.int64(input.shape) : Tensor.float32(input.shape))
      ..values.setAll(0, input.values),
  ),
);

void main() {
  final golden = File('test/golden.json');
  final goldens = (jsonDecode(golden.readAsStringSync()) as Map).map(
    (k, v) => MapEntry(k as String, (v as List).cast<double>()),
  );
  final update = Platform.environment['PHOTOLIB_ML_GOLDEN'] == 'update';
  final chosen = selected(Platform.environment['PHOTOLIB_ML_MODELS']);
  final files = fetch([runtime, ...chosen.map((c) => c.model)]);
  final ort = Ort.open(files[runtime]!);
  final sface = cases.firstWhere((c) => c.model == 'sface');

  test('the pinned runtime reports its version and the CPU', () {
    expect(ort.version, '1.31.0');
    expect(ort.providers, contains('CPUExecutionProvider'));
  });

  test('a provider the runtime lacks fails instead of falling back to the '
      'CPU', () {
    final missing = [
      'QNN',
      'CoreML',
      'XNNPACK',
      'WebGPU',
    ].firstWhere((p) => !ort.providers.contains('${p}ExecutionProvider'));
    expect(
      () => Session(ort, files['sface']!, provider: missing),
      throwsA(
        isA<OrtException>().having((e) => '$e', 'message', contains(missing)),
      ),
    );
  });

  test('a model that is not there fails', () {
    expect(() => Session(ort, 'missing.onnx'), throwsA(isA<OrtException>()));
  });

  test('another isolate runs a tensor that this one filled, by address', () {
    final input = tensors(sface.inputs());
    final library = files[runtime]!, model = files['sface']!;
    Float32List embed() {
      final session = Session(Ort.open(library), model);
      try {
        return session.run(input, sface.outputs)[0];
      } finally {
        session.close();
      }
    }

    final here = embed();
    final there = Isolate.run(embed);
    expect(there, completion(here));
    expect(cosine(here, goldens['sface']!), greaterThan(.999));
  });

  for (final c in chosen) {
    test('${c.model} on the CPU matches the fp32 golden output', () async {
      final input = tensors(c.inputs());
      final before = ProcessInfo.currentRss;
      late Session session;
      final result = await measure(() async {
        session = Session(ort, files[c.model]!, threads: 4);
        return () async => session.run(input, c.outputs);
      }, goldens[c.reference] ?? []);
      final rss = (ProcessInfo.currentRss - before) / 1e6;
      session.close();
      if (update && c.model == c.reference) {
        goldens[c.model] = result['sample'] as List<double>;
        golden.writeAsStringSync(
          '{\n${goldens.entries.map((e) => '  "${e.key}": ${jsonEncode(e.value)}').join(',\n')}\n}\n',
        );
      }
      result.remove('sample');
      print(
        jsonEncode({
          'target': '$runtime cpu',
          'model': c.model,
          ...result,
          'rss_mb': rss.round(),
        }),
      );
      // A runtime upgrade must reproduce the reference (design 09 §12.3); a variant is measured, not required.
      if (c.model == c.reference && !update) {
        expect(result['cosine'], greaterThanOrEqualTo(.999));
      }
    });
  }
}
