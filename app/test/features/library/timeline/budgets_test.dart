import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/benchmark.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

/// What a CPU can check of the timeline's budgets (ADR-0040): frames and
/// thumbnail times wait for a GPU, and tools/perf checks frame build times.
/// Each takes the best of several rounds, as a loaded machine stalls any one,
/// and decoding counts CPU time, which load stretches less.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lays out a million assets in a quarter of a 120 Hz frame', () {
    final counts = syntheticLibrary().counts;
    final times = <double>[];
    for (var i = 0; i < 7; i++) {
      final watch = Stopwatch()..start();
      TimelineLayout(counts, columns: 4 + i, cellExtent: 100, headerExtent: 48);
      times.add(watch.elapsedMicroseconds / 1000);
    }
    expect(times.reduce(min), lessThan(2));
  });

  test(
    "decodes from the disk cache, on a core's worth of CPU, the 320 "
    'thumbnails a second a fling at four columns needs (docs/10 §3.4)',
    () async {
      final dir = await Directory.systemTemp.createTemp('budgets');
      addTearDown(() => dir.delete(recursive: true));
      final (vault, cipher) = await scratchVault(
        '${dir.path}/store',
        Kernel().keyring,
      );
      addTearDown(vault.lock);
      final cache = await DiskCache.open('${dir.path}/cache', cipher);
      // Its index is still being written; a delete beside that fails.
      addTearDown(cache.close);
      final (jpegs, _, _) = thumbnailSamples(16);
      for (final (k, jpeg) in jpegs.indexed) {
        await cache.put('$k-256', jpeg);
      }
      final pipeline = ThumbnailPipeline(cache: cache);
      var best = 0.0;
      for (var round = 0; round < 20 && best < 320; round++) {
        final thumbnails = Thumbnails(
          (asset, tier, tile) => pipeline.load(
            ThumbnailItem(
              '${(asset as int) % jpegs.length}',
              Uri.file('/none'),
            ),
            tier,
            tile,
          ),
        )..focus(0, 255, forward: true);
        final done = Completer<void>();
        var left = 256;
        final start = _cpuSeconds();
        for (var asset = 0; asset < 256; asset++) {
          thumbnails.want(asset, 256, at: asset, () {
            if (--left == 0) done.complete();
          });
        }
        await done.future;
        best = max(best, 256 / (_cpuSeconds() - start));
      }
      expect(best, greaterThanOrEqualTo(320));
    },
    testOn: 'linux',
  );

  test('a queue of 5,000 waiting cells takes under 100 µs of CPU a decode, '
      'not a sort of the queue each', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawPaint(ui.Paint());
    final image = recorder.endRecording().toImageSync(8, 8);
    const cells = 5000;
    var best = double.infinity;
    for (var round = 0; round < 5 && best >= 100e-6; round++) {
      // Each decode ends in an event of its own, as a decoder's do.
      final thumbnails = Thumbnails(
        (asset, tier, tile) async {
          await Future<void>.delayed(Duration.zero);
          return image.clone();
        },
        concurrency: 15,
        maxBytes: 1 << 30,
      )..focus(0, cells - 1, forward: true);
      final done = Completer<void>();
      var left = cells;
      final start = _cpuSeconds();
      for (var asset = 0; asset < cells; asset++) {
        thumbnails.want(asset, 128, at: asset, () {
          if (--left == 0) done.complete();
        });
      }
      await done.future;
      best = min(best, (_cpuSeconds() - start) / cells);
    }
    expect(best * 1e6, lessThan(100));
  }, testOn: 'linux');
}

// The CPU time of all this process's threads, in seconds (Linux).
double _cpuSeconds() {
  final fields = File('/proc/self/stat')
      .readAsStringSync()
      .split(') ')
      .last
      .split(' ');
  return (int.parse(fields[11]) + int.parse(fields[12])) / 100;
}
