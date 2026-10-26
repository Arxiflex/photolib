// Ort.bundled() reaches the library that the build hook (hook/build.dart)
// bundles through its asset. This package's own tests bundle none
// (`bundle: false`), so here it fails naming that asset, and so does a runner
// given no runtime's path.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/runner.dart';
import 'package:test/test.dart';

const asset = 'package:photolib_ml/onnxruntime.dart';

void main() {
  test("the bundled runtime is the build hook's asset", () {
    expect(Ort.bundled, throwsA(predicate((e) => '$e'.contains(asset))));
  });

  test('a runner given no runtime loads the bundled one', () async {
    final state = Directory.systemTemp.createTempSync('runner');
    addTearDown(() => state.deleteSync(recursive: true));
    final model = RunnerModel(
      name: 'none',
      path: 'none.onnx',
      input: 'input',
      shape: const [1],
      output: 'output',
      golden: Float32List(1),
      reference: Float32List(1),
    );
    await expectLater(
      Runner.start(null, model, state: state.path),
      throwsA(
        isA<OrtException>().having(
          (e) => e.message,
          'message',
          contains(asset),
        ),
      ),
    );
  });
}
