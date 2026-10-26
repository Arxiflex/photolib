// The tests of editor_test.dart and web_test.dart: the probe of lib/testing.dart against the thresholds of design 11
// §4.4, printing its measurements as JSON lines. --dart-define=megapixels=50 or 200 exports more than the gate's 12 MP.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_editor/photolib_editor.dart';
import 'package:photolib_editor/testing.dart';

const megapixels = int.fromEnvironment('megapixels', defaultValue: 12);
const sizes = {
  12: (4032, 3024, 2),
  50: (8160, 6120, 4),
  200: (16320, 12240, 8),
};

/// Defines the tests over the renderers that [load] returns; an export by either stays within [budget] MiB above the
/// baseline that [memory] measures, when given.
void probe(
  Future<(ShaderRenderer, Reference)> Function() load,
  int Function() memory, {
  int? budget,
}) {
  late ShaderRenderer gpu;
  late Reference cpu;
  setUpAll(() async => (gpu, cpu) = await load());

  test(
    'the shaders match the reference renderer on every card and recipe',
    () async {
      final results = await parity(gpu, cpu);
      print(jsonEncode({'parity': results}));
      for (final r in results) {
        expect(r['mean'] as double, lessThanOrEqualTo(0.5), reason: '$r');
        expect(r['p99'] as double, lessThanOrEqualTo(2), reason: '$r');
        expect(r['band_excess'] as int, lessThanOrEqualTo(1), reason: '$r');
      }
    },
  );

  for (final shader in [true, false]) {
    final name = shader ? 'shader' : 'reference';
    test(
      'a $megapixels MP export by the $name renderer matches its preview',
      () async {
        final (width, height, scale) = sizes[megapixels]!;
        final result = await export(
          width,
          height,
          scale,
          gpu: shader ? gpu : null,
          cpu: shader ? null : cpu,
          memory: memory,
        );
        print(jsonEncode({'export': result}));
        final d = result['preview_vs_export'] as Map<String, double>;
        expect(d['mean'], lessThanOrEqualTo(0.5));
        expect(d['p99'], lessThanOrEqualTo(2));
        if (budget != null) {
          expect(
            result['peak_above_baseline_mib'] as double,
            lessThanOrEqualTo(budget),
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }

  test('frame times while a slider moves', () async {
    print(jsonEncode({'interactivity': await interactivity(gpu)}));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
