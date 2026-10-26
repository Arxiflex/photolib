// The registry apps compile in (lib/registry.dart): the server's, giving each
// model a device runs what the runner checks it with.
@TestOn('vm')
library;

import 'dart:io';

import 'package:photolib_ml/registry.dart';
import 'package:photolib_ml/runner.dart';
import 'package:test/test.dart';

import '../tool/registry.dart' as tool;
import 'native_test.dart' show fetch, runtime;

void main() {
  test("is the server's registry", () {
    expect(
      File('lib/src/registry.g.dart').readAsStringSync(),
      tool.source(),
      reason: 'stale: run dart run tool/registry.dart in photolib_ml',
    );
  });

  test('gives every image model a device runs its input, golden and '
      'reference', () {
    final embeddings = [
      for (final model in registry)
        if (model.preprocess != null) model,
    ];
    expect(
      [for (final m in embeddings) m.name],
      ['siglip2-b16-256@onnx-d1114256', 'sface@2021dec', 'auraface@v1'],
    );
    for (final model in embeddings) {
      final size = model.preprocess!.size;
      // AuraFace is the optional model of servers and desktops: 261 MB is no
      // phone's.
      final targets = model.name == 'auraface@v1'
          ? ['macos', 'windows', 'linux']
          : ['android', 'ios', 'macos', 'windows', 'linux'];
      for (final target in targets) {
        final file = model.imageFile(target)!;
        final (_, shape) = file.input;
        expect(shape, [1, 3, size, size], reason: file.name);
        expect(file.goldenInput, hasLength(3 * size * size));
        expect(file.reference, hasLength(model.dim));
      }
    }
    final siglip = registry.first;
    final input = siglip.preprocess!;
    // The whole image squashed to the square, as its own processor does.
    expect(
      [input.size, ...input.mean, ...input.std, input.crop],
      [256, .5, .5, .5, .5, .5, .5, false],
    );
    final vision = siglip.imageFile('ios')!;
    expect(
      (vision.name, vision.input.$1, vision.output, vision.precision),
      ('vision_model_fp16.onnx', 'pixel_values', 'pooler_output', 'fp16'),
    );
    expect(vision.goldenInput.first, picture(256, 2, -1).first);
  });

  test("SFace runs on the runner from the registry's entry, reproducing its "
      'reference', () async {
    final files = fetch([runtime, 'sface']);
    final model = registry.firstWhere((m) => m.id == 'sface');
    final file = model.imageFile('linux')!;
    final state = await Directory.systemTemp.createTemp('ml-');
    addTearDown(() => state.delete(recursive: true));
    final runner = await Runner.start(
      files[runtime],
      RunnerModel(
        name: model.name,
        path: files['sface']!,
        input: file.input.$1,
        shape: file.input.$2,
        output: file.output,
        golden: file.goldenInput,
        reference: file.reference,
        precision: file.precision,
      ),
      state: state.path,
    );
    addTearDown(runner.close);
    expect(runner.rtFlags, 'onnxruntime 1.31.0 CPU fp32');
    final [output] = await runner.run([file.goldenInput]);
    expect(cosine(output, file.reference), greaterThan(.999));
  });
}
