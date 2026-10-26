// The shaders against the kernel's CPU reference renderer through the C ABI, in flutter_tester, where the export also
// stays within design 11 §4.4's 256 MiB; and the reference's export with
// its tiles on worker isolates on every core.
// ignore_for_file: avoid_print
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_editor/photolib_editor.dart';
import 'package:photolib_editor/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';
import 'package:photolib_kernel/testing.dart';
import 'package:photolib_workers/photolib_workers.dart';

import 'probe.dart';

/// How many worker isolates export: every core unless
/// `--dart-define=workers=<n>`, such as a phone's pool of 4.
const workers = int.fromEnvironment('workers');

/// A worker's kernel, opened from the path its first tile names.
Reference? _kernel;

final _tile = Task<List<Object?>, List<Object>>('tile', (input, _) {
  final kernel = _kernel ??= Reference(Kernel.open(input[0]! as String).call);
  final [width, height, scale, x, y, w, h] = input.sublist(2).cast<int>();
  final guide = input[1] as Uint8List?;
  final (sums, micros) = exportTile(
    kernel,
    guide,
    width,
    height,
    scale,
    x,
    y,
    w,
    h,
  );
  return [sums, micros];
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = buildKernel();
  final kernel = Kernel.open(path);
  probe(
    () async => (await ShaderRenderer.load(assets: ''), Reference(kernel.call)),
    () => ProcessInfo.currentRss,
    budget: 256,
  );

  test('a $megapixels MP export by the reference on every core matches its '
      'preview', () async {
    final pool = WorkerPool([
      _tile,
    ], size: workers > 0 ? workers : Platform.numberOfProcessors);
    addTearDown(pool.close);
    final (width, height, scale) = sizes[megapixels]!;
    final result = await exportOnCores(
      width,
      height,
      scale,
      Reference(kernel.call),
      workers: pool.size,
      memory: () => ProcessInfo.currentRss,
      tile: (guide, x, y, w, h) async {
        final input = [path, guide, width, height, scale, x, y, w, h];
        final [sums, micros] = await pool.run(_tile, input).result;
        return (sums as Float32List, micros as int);
      },
    );
    print(jsonEncode({'export': result}));
    final d = result['preview_vs_export']! as Map<String, double>;
    expect(d['mean'], lessThanOrEqualTo(0.5));
    expect(d['p99'], lessThanOrEqualTo(2));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
