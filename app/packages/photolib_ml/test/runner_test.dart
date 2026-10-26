// The runner (ADR-0254): a model on an isolate of its own, run with the first
// execution provider that reproduces the server's output for the golden input,
// through the ONNX Runtime that tools/ml/artefacts.json pins.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:photolib_ml/photolib_ml.dart';
import 'package:photolib_ml/runner.dart';
import 'package:test/test.dart';

import 'native_test.dart' show fetch, runtime;
import 'spike.dart' show picture;

void main() {
  final files = fetch([runtime, 'sface']);
  final golden = Float32List.fromList(picture(112, 255, 0));
  // The fp32 model's output on the CPU: what the server computes (ADR-0050).
  final server = Float32List.fromList(
    ((jsonDecode(File('test/golden.json').readAsStringSync()) as Map)['sface']
            as List)
        .cast<double>(),
  );
  late Directory state;
  setUp(() async => state = await Directory.systemTemp.createTemp('ml-'));
  tearDown(() => state.delete(recursive: true));

  RunnerModel sface({Float32List? reference}) => RunnerModel(
    name: 'sface@2021dec',
    path: files['sface']!,
    input: 'data',
    shape: const [1, 3, 112, 112],
    output: 'fc1',
    golden: golden,
    reference: reference ?? server,
  );

  Future<Runner> start(
    RunnerModel model, {
    List<String> providers = const [],
  }) async {
    final runner = await Runner.start(
      files[runtime],
      model,
      providers: providers,
      state: state.path,
    );
    addTearDown(runner.close);
    return runner;
  }

  Map<String, Object?> saved() =>
      jsonDecode(File('${state.path}/sface@2021dec.json').readAsStringSync())
          as Map<String, Object?>;

  test("runs its model on an isolate of its own, reproducing the server's "
      'output, and says with what', () async {
    final runner = await start(sface());
    expect(runner.rtFlags, 'onnxruntime 1.31.0 CPU fp32');
    final outputs = await runner.run([golden, golden]);
    expect(outputs, hasLength(2));
    for (final output in outputs) {
      expect(cosine(output, server), greaterThan(.999));
    }
  });

  test('a provider that fails to run three times is quarantined for the '
      'runtime; the CPU runs the model meanwhile', () async {
    for (var i = 1; i <= 4; i++) {
      final runner = await start(sface(), providers: ['CoreML']);
      expect(runner.rtFlags, 'onnxruntime 1.31.0 CPU fp32');
      expect(saved(), {
        'runtime': '1.31.0',
        'failures': {'CoreML': i.clamp(1, 3)},
      });
      await runner.close();
    }

    // A runtime upgrade tries it again.
    File('${state.path}/sface@2021dec.json').writeAsStringSync(
      jsonEncode({
        'runtime': '1.30.0',
        'failures': {'CoreML': 3, 'CPU': 3},
      }),
    );
    await start(sface(), providers: ['CoreML']);
    expect(saved(), {
      'runtime': '1.31.0',
      'failures': {'CoreML': 1},
    });
  });

  test("a provider whose output strays from the server's is quarantined at "
      'once; with none left, the model does not run', () async {
    final stray = Float32List.fromList([for (final v in server) -v]);
    await expectLater(
      start(sface(reference: stray)),
      throwsA(
        isA<OrtException>().having(
          (e) => e.message,
          'message',
          'no execution provider reproduces sface@2021dec',
        ),
      ),
    );
    expect(saved()['failures'], {'CPU': 3});
  });

  test('a run that fails fails alone', () async {
    final runner = await start(sface());
    await expectLater(
      runner.run([Float32List(3)]),
      throwsA(isA<OrtException>()),
    );
    expect(
      cosine((await runner.run([golden])).single, server),
      greaterThan(.999),
    );
  });

  test('a closed runner runs nothing more', () async {
    final runner = await start(sface());
    await runner.close();
    await expectLater(runner.run([golden]), throwsA(isA<OrtException>()));
  });
}
