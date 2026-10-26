// The cases of the on-device ML runtime spike (ADR-0050), shared by the native and the browser tests: each model that
// tools/ml/artefacts.json pins, a deterministic input and the outputs compared with golden.json, the fp32 model's
// outputs on the CPU of Linux x64.
import 'dart:math';
import 'dart:typed_data';

import 'package:photolib_ml/registry.dart';

export 'package:photolib_ml/registry.dart' show picture;

/// An input: its shape and values, float32 unless [int64].
typedef Input = ({List<int> shape, List<num> values, bool int64});

/// A pinned model, its [inputs], the [outputs] compared, and the fp32 model that is its [reference].
class Case {
  const Case(this.model, this.reference, this.inputs, this.outputs);

  final String model;
  final String reference;
  final Map<String, Input> Function() inputs;
  final List<String> outputs;
}

/// "a photo of a sailing boat in greece" in the SigLIP 2 tokenizer, padded to 64 tokens.
const tokens = [235250, 2686, 576, 476, 42745, 11390, 575, 204061, 1];

Map<String, Input> _yunet() => {
  'input': (
    shape: [1, 3, 640, 640],
    values: picture(640, 255, 0),
    int64: false,
  ),
};
Map<String, Input> _sface() => {
  'data': (shape: [1, 3, 112, 112], values: picture(112, 255, 0), int64: false),
};
Map<String, Input> _vision() => {
  'pixel_values': (
    shape: [1, 3, 256, 256],
    values: picture(256, 2, -1),
    int64: false,
  ),
};
Map<String, Input> _text() => {
  'input_ids': (
    shape: [1, 64],
    values: <int>[...tokens, ...List.filled(64 - tokens.length, 0)],
    int64: true,
  ),
};

Map<String, Input> _ppocrDetector() => {
  'x': (shape: [1, 3, 64, 64], values: picture(64, 1, 0), int64: false),
};
Map<String, Input> _ppocrRecogniser() => {
  'x': (shape: [1, 3, 48, 48], values: picture(48, 2, -1), int64: false),
};

final _yunetOutputs = [
  for (final head in ['cls', 'obj', 'bbox', 'kps'])
    for (final stride in [8, 16, 32]) '${head}_$stride',
];

final List<Case> cases = [
  Case('yunet', 'yunet', _yunet, _yunetOutputs),
  Case('sface', 'sface', _sface, ['fc1']),
  Case('sface-int8', 'sface', _sface, ['fc1']),
  Case('siglip2-vision', 'siglip2-vision', _vision, ['pooler_output']),
  Case('siglip2-vision-fp16', 'siglip2-vision', _vision, ['pooler_output']),
  Case('siglip2-vision-int8', 'siglip2-vision', _vision, ['pooler_output']),
  Case('siglip2-text', 'siglip2-text', _text, ['pooler_output']),
  Case('siglip2-text-fp16', 'siglip2-text', _text, ['pooler_output']),
  Case('siglip2-text-int8', 'siglip2-text', _text, ['pooler_output']),
  // PP-OCRv5 (M5-08): the detector's map, each recogniser's probabilities.
  const Case('ppocr-v5-det', 'ppocr-v5-det', _ppocrDetector, ['fetch_name_0']),
  for (final script in ['latin', 'eslav', 'chinese'])
    Case('ppocr-v5-rec-$script', 'ppocr-v5-rec-$script', _ppocrRecogniser, [
      'fetch_name_0',
    ]),
];

/// The cases the gate runs: the small face models. `PHOTOLIB_ML_MODELS=all` (or a comma-separated list) runs more.
List<Case> selected(String? models) => [
  for (final c in cases)
    if (models == 'all' ||
        (models?.split(',') ?? ['yunet', 'sface']).contains(c.model))
      c,
];

/// At most 1,024 evenly spaced values of the outputs, one after another: what golden.json keeps of a reference.
List<double> sample(List<Float32List> outputs) {
  final all = [for (final output in outputs) ...output];
  final n = min(all.length, 1024);
  return [for (var i = 0; i < n; i++) all[i * all.length ~/ n]];
}

double cosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var ab = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    ab += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return ab / sqrt(aa * bb);
}

/// Loads a case with [load], which returns a function running it once, and measures it: the load, the first run, the
/// median of five more runs (milliseconds), and the cosine of the outputs' sample to [golden].
Future<Map<String, Object>> measure(
  Future<Future<List<Float32List>> Function()> Function() load,
  List<double> golden,
) async {
  final watch = Stopwatch()..start();
  double lap() {
    final ms = watch.elapsedMicroseconds / 1000;
    watch.reset();
    return ms;
  }

  final run = await load();
  final loaded = lap();
  final outputs = await run();
  final first = lap();
  final runs = <double>[];
  for (var i = 0; i < 5; i++) {
    await run();
    runs.add(lap());
  }
  runs.sort();
  return {
    'load_ms': loaded.round(),
    'first_ms': first.round(),
    'run_ms': double.parse(runs[2].toStringAsFixed(1)),
    'cosine': cosine(sample(outputs), golden),
    'sample': sample(outputs),
  };
}
