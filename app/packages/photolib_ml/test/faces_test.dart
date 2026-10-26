// The device's face models (ADR-0389): YuNet and SFace on the CPU through
// the runner's isolate, each held to the registry's golden output before it
// runs. The gate runs the models of tools/ml/artefacts.json.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:photolib_ml/faces.dart';
import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/registry.dart';
import 'package:test/test.dart';

import 'native_test.dart' show fetch, runtime;

void main() {
  final files = fetch([runtime, 'yunet', 'sface']);
  final yunet = registry.firstWhere((m) => m.id == 'yunet');
  final sface = registry.firstWhere((m) => m.id == 'sface');

  Future<FaceRunner> start({String? detector, String? embedder}) =>
      FaceRunner.start(
        files[runtime],
        detector: yunet,
        detectorPath: detector ?? files['yunet']!,
        embedder: sface,
        embedderPath: embedder ?? files['sface']!,
        target: 'linux',
      );

  test('runs YuNet at any size and SFace on an aligned face', () async {
    final runner = await start();
    addTearDown(runner.close);
    expect(runner.rtFlags, startsWith('onnxruntime '));
    // 64 x 32: cells of 8, 16 and 32 pixels, each output's size per cell.
    final outputs = await runner.detect(Float32List(3 * 32 * 64), 64, 32);
    final cells = [
      for (final s in [8, 16, 32]) (64 ~/ s) * (32 ~/ s),
    ];
    expect(
      [for (final o in outputs) o.length],
      [
        ...cells,
        ...cells,
        for (final c in cells) c * 4,
        for (final c in cells) c * 10,
      ],
    );
    final embedding = await runner.embed(Float32List(3 * 112 * 112));
    expect(embedding, hasLength(128));
  });

  test('refuses a model that does not reproduce its golden output', () async {
    // SFace's file where YuNet's belongs.
    await expectLater(
      start(detector: files['sface']),
      throwsA(isA<OrtException>()),
    );
  });
}
