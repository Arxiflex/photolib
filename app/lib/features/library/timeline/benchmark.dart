/// The timeline benchmark (M0-30) on this device: the cost of a layout over a
/// million assets, each image pipeline's decodes, and frame times while
/// dragging, flinging, jumping and scrubbing. `tools/timeline_bench.py` builds
/// it from `app/benchmark/timeline.dart`; test builds run it from Settings
/// (ADR-0040).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';

import '../../../l10n/app_localizations.dart';
import 'benchmark_io.dart' if (dart.library.js_interop) 'benchmark_web.dart';
import 'buckets.dart';
import 'layout.dart';
import 'pages.dart';
import 'selection.dart';
import 'thumb_hash.dart';
import 'thumbnails.dart';
import 'timeline_view.dart';

const _side = 256;

/// As many assets and days as the spike's library: a million on 5,569 days
/// back from 31 March 2026.
TimelineBuckets syntheticLibrary() {
  final random = Random(42);
  final counts = List.filled(5569, 0);
  for (var i = 0; i < 1000000; i++) {
    counts[random.nextInt(counts.length)]++;
  }
  int day(int back) {
    final day = DateTime.utc(2026, 3, 31 - back);
    return day.year * 10000 + day.month * 100 + day.day;
  }

  return TimelineBuckets(
    days: [for (var d = 0; d < counts.length; d++) day(d)],
    counts: counts,
  );
}

/// The benchmark in a test build: Settings opens it while the diagnostics flag
/// is on, and it offers its JSON to copy once done.
class TimelineBenchmarkPage extends StatefulWidget {
  const TimelineBenchmarkPage({super.key, this.benchmark = _benchmark});

  /// The benchmark, which reports to its argument.
  final Widget Function(ValueChanged<Map<String, Object>> onDone) benchmark;

  static Widget _benchmark(ValueChanged<Map<String, Object>> onDone) =>
      TimelineBenchmark(buckets: syntheticLibrary(), onDone: onDone);

  @override
  State<TimelineBenchmarkPage> createState() => _TimelineBenchmarkPageState();
}

class _TimelineBenchmarkPageState extends State<TimelineBenchmarkPage> {
  String? _json;
  late final _benchmark = widget.benchmark(
    (results) => setState(
      () => _json = const JsonEncoder.withIndent('  ').convert(results),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final json = _json;
    return PopScope(
      canPop: json != null,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: json != null,
          title: Text(strings.timelineBenchmark),
          actions: [
            if (json != null)
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: strings.timelineBenchmarkCopy,
                onPressed: () => Clipboard.setData(ClipboardData(text: json)),
              ),
          ],
        ),
        body: json == null
            ? _benchmark
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(json),
              ),
      ),
    );
  }
}

/// Runs the scenarios with each image pipeline in turn and gives [onDone]
/// the results.
class TimelineBenchmark extends StatefulWidget {
  const TimelineBenchmark({
    super.key,
    required this.buckets,
    required this.onDone,
  });

  final TimelineBuckets buckets;
  final ValueChanged<Map<String, Object>> onDone;

  @override
  State<TimelineBenchmark> createState() => _TimelineBenchmarkState();
}

class _TimelineBenchmarkState extends State<TimelineBenchmark> {
  var _view = GlobalKey<TimelineViewState>();
  Thumbnails? _thumbnails;
  var _hashes = <ThumbHash>[];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  Widget build(BuildContext context) => switch (_thumbnails) {
    final thumbnails? => TimelineView(
      key: _view,
      buckets: widget.buckets,
      // Each position's item is its number.
      pages: TimelinePages(
        (first, count) async => [
          for (
            var a = first;
            a < first + count && a < widget.buckets.assets;
            a++
          )
            a,
        ],
      ),
      thumbnails: thumbnails,
      selection: ValueNotifier(Selection.none),
      placeholder: (asset) => _hashes[(asset as int) % _hashes.length],
    ),
    null => const Center(child: CircularProgressIndicator()),
  };

  Future<void> _run() async {
    final buckets = widget.buckets;
    final (jpegs, pixels, smalls) = await compute(thumbnailSamples, 64);
    final keyring = (await loadKernel())();
    _hashes = [
      for (final small in smalls)
        ThumbHash.tryParse(encodeThumbHash(keyring.call, 64, 64, small))!,
    ];
    keyring.close();
    final (platform, cleanUp) = await platformSources(jpegs);
    final sources = <String, ThumbnailSource>{
      // Flutter's codecs: the engine decodes the encoded bytes off the UI thread.
      'codec': (asset, tier, _) async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(
          jpegs[(asset as int) % jpegs.length],
        );
        final codec = await ui.instantiateImageCodecWithSize(
          buffer,
          getTargetSize: (_, _) =>
              ui.TargetImageSize(width: tier, height: tier),
        );
        return _frame(codec);
      },
      // What a platform decoder hands over: RGBA pixels, copied once.
      'raw': (asset, tier, _) async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(
          pixels[(asset as int) % pixels.length],
        );
        final descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: _side,
          height: _side,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        return _frame(
          await descriptor.instantiateCodec(
            targetWidth: tier,
            targetHeight: tier,
          ),
        );
      },
      ...platform,
    };

    final results = <String, Object>{
      'compiler': kIsWeb ? (kIsWasm ? 'dart2wasm' : 'dart2js') : 'aot',
      'platform': defaultTargetPlatform.name,
      'assets': buckets.assets,
      'days': buckets.days.length,
      'jpeg_bytes': jpegs.fold(0, (a, b) => a + b.length) ~/ jpegs.length,
    };
    final watch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      TimelineLayout(
        buckets.counts,
        columns: 4 + i % 7,
        cellExtent: 100,
        headerExtent: 48,
      );
    }
    results['layout_ms'] = watch.elapsedMicroseconds / 100 / 1000;

    final recorder = _FrameRecorder();
    for (final MapEntry(key: name, value: source) in sources.entries) {
      final thumbnails = Thumbnails(source);
      results['decode/$name'] = await _decodes(source, thumbnails.concurrency);
      setState(() {
        _view = GlobalKey();
        _thumbnails = thumbnails;
      });
      await _until(() => _view.currentState != null);
      final view = _view.currentState!;
      final dpr = ui.PlatformDispatcher.instance.implicitView!.devicePixelRatio;
      final tier = tierFor(view.layout.cellExtent * dpr);
      bool loaded() {
        final (first, last) = view.visible;
        for (var a = first; a <= last; a++) {
          if (thumbnails.get(a, tier) == null) return false;
        }
        return true;
      }

      await _until(loaded);
      results['view'] = {
        'size': [
          view.layout.columns * view.layout.cellExtent,
          view.controller.position.viewportDimension,
        ],
        'dpr': dpr,
        'columns': view.layout.columns,
        'tier': tier,
        'decoders': thumbnails.concurrency,
        'memory_mib': thumbnails.maxBytes >> 20,
      };
      final controller = view.controller;
      final position = controller.position as ScrollPositionWithSingleContext;

      // Reading speed: below the fling threshold, so every row decodes.
      results['$name/drag'] = await recorder.measure(
        () => controller.animateTo(
          controller.offset + 8000,
          duration: const Duration(seconds: 8),
          curve: Curves.linear,
        ),
      );
      // Flutter's top fling speed: placeholders until it slows.
      results['$name/fling'] = await recorder.measure(() async {
        for (var i = 0; i < 3; i++) {
          position.goBallistic(8000);
          await _until(() => !position.isScrollingNotifier.value);
          await _until(loaded);
        }
      });
      // The machine's own share (ADR-0140): the same view, fully loaded, moved
      // a hundredth of a pixel a frame for four seconds, which draws 60 frames
      // a second and decodes nothing, as an idle app would.
      if (name == 'codec') {
        results['idle'] = await recorder.measure(() async {
          final idle = Stopwatch()..start();
          final from = controller.offset;
          for (var frame = 0; idle.elapsedMilliseconds < 4000; frame++) {
            controller.jumpTo(from + (frame.isEven ? 0.01 : 0));
            await SchedulerBinding.instance.endOfFrame;
          }
        });
      }
      // Twenty scrubber jumps to random months: placeholders, then thumbnails.
      final random = Random(37);
      final months = [
        for (final (year, _) in buckets.years)
          for (var m = 1; m <= 12; m++)
            if (buckets.segmentOfMonth(year, m) != null) (year, m),
      ];
      final placeholders = <double>[], filled = <double>[];
      results['$name/jump'] = await recorder.measure(() async {
        for (var i = 0; i < 20; i++) {
          final (year, month) = months[random.nextInt(months.length)];
          thumbnails.paused = true;
          final jump = Stopwatch()..start();
          view.jumpToMonth(year, month);
          await SchedulerBinding.instance.endOfFrame;
          placeholders.add(jump.elapsedMicroseconds / 1000);
          thumbnails.paused = false;
          await _until(loaded);
          filled.add(jump.elapsedMicroseconds / 1000);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      });
      results['$name/jump_ms'] = {
        'placeholders': percentiles(placeholders),
        'thumbnails': percentiles(filled),
      };
      if (name == 'codec') {
        // Dragging the scrubber end to end in 3 s: a new screen every frame.
        thumbnails.paused = true;
        results['scrub'] = await recorder.measure(() async {
          final scrub = Stopwatch()..start();
          while (scrub.elapsedMilliseconds < 3000) {
            controller.jumpTo(
              position.maxScrollExtent * scrub.elapsedMilliseconds / 3000,
            );
            await SchedulerBinding.instance.endOfFrame;
          }
        });
        thumbnails.paused = false;
      }
    }
    recorder.dispose();
    await cleanUp();
    widget.onDone(results);
  }
}

Future<ui.Image> _frame(ui.Codec codec) async {
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Photo-like JPEGs (gradient, shapes, grain) at [_side] px, as `thumb_s`
/// renditions are, their RGBA pixels and those of a 64 px copy.
(List<Uint8List>, List<Uint8List>, List<Uint8List>) thumbnailSamples(
  int count,
) {
  final random = Random(30);
  final jpegs = <Uint8List>[], pixels = <Uint8List>[], smalls = <Uint8List>[];
  for (var k = 0; k < count; k++) {
    final image = img.Image(width: _side, height: _side);
    final a = [for (var c = 0; c < 3; c++) random.nextInt(256)];
    final b = [for (var c = 0; c < 3; c++) random.nextInt(256)];
    for (var y = 0; y < _side; y++) {
      for (var x = 0; x < _side; x++) {
        final t = (x + y) / (2 * _side);
        int channel(int c) =>
            (a[c] + (b[c] - a[c]) * t + random.nextInt(25) - 12)
                .clamp(0, 255)
                .round();
        image.setPixelRgb(x, y, channel(0), channel(1), channel(2));
      }
    }
    for (var s = 0; s < 6; s++) {
      img.fillCircle(
        image,
        x: random.nextInt(_side),
        y: random.nextInt(_side),
        radius: 8 + random.nextInt(48),
        color: img.ColorRgb8(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        ),
        antialias: true,
      );
    }
    jpegs.add(img.encodeJpg(image, quality: 80));
    pixels.add(image.getBytes(order: img.ChannelOrder.rgba));
    smalls.add(
      img.copyResize(image, width: 64).getBytes(order: img.ChannelOrder.rgba),
    );
  }
  return (jpegs, pixels, smalls);
}

/// Latency of one decode at a time, and throughput with [at] at once.
Future<Map<String, Object>> _decodes(ThumbnailSource source, int at) async {
  const n = 256;
  final latencies = <double>[];
  for (var i = 0; i < n; i++) {
    final watch = Stopwatch()..start();
    (await source(i, _side, Tile())).dispose();
    latencies.add(watch.elapsedMicroseconds / 1000);
  }
  final watch = Stopwatch()..start();
  var next = 0;
  await Future.wait([
    for (var w = 0; w < at; w++)
      () async {
        while (next < n) {
          (await source(next++, _side, Tile())).dispose();
        }
      }(),
  ]);
  return {
    'latency_ms': percentiles(latencies),
    'per_s': (n / (watch.elapsedMicroseconds / 1e6)).round(),
  };
}

Future<void> _until(bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < const Duration(seconds: 10)) {
    await SchedulerBinding.instance.endOfFrame;
  }
}

class _FrameRecorder {
  _FrameRecorder() {
    SchedulerBinding.instance.addTimingsCallback(_timings.addAll);
  }

  final _timings = <ui.FrameTiming>[];

  void dispose() =>
      SchedulerBinding.instance.removeTimingsCallback(_timings.addAll);

  Future<int> _frameNumber() async {
    await SchedulerBinding.instance.endOfFrame;
    return ui.PlatformDispatcher.instance.frameData.frameNumber;
  }

  Future<Map<String, Object>> measure(Future<void> Function() action) async {
    final start = await _frameNumber();
    final watch = Stopwatch()..start();
    await action();
    final end = await _frameNumber();
    final elapsed = watch.elapsed;
    // The engine reports timings in batches; idle frames flush the last one.
    await _until(() => _timings.any((t) => t.frameNumber >= end));
    return summarize([
      for (final t in _timings)
        if (t.frameNumber > start && t.frameNumber <= end) t,
    ], elapsed);
  }
}

/// p50, p90 and p99 by nearest rank, rounded to two decimals.
List<double> percentiles(List<double> values) {
  if (values.isEmpty) return [];
  final sorted = [...values]..sort();
  return [
    for (final p in [50, 90, 99])
      (sorted[(p * sorted.length / 100).ceil() - 1] * 100).round() / 100,
  ];
}

/// Frame times in milliseconds and the share of frames whose build and raster
/// together miss a 60 Hz vsync, which a single-threaded browser cannot hide.
Map<String, Object> summarize(List<ui.FrameTiming> frames, Duration elapsed) {
  double ms(Duration d) => d.inMicroseconds / 1000;
  final totals = [
    for (final f in frames) ms(f.buildDuration) + ms(f.rasterDuration),
  ];
  return {
    'frames': frames.length,
    'fps': (frames.length / (elapsed.inMicroseconds / 1e6) * 10).round() / 10,
    'build_ms': percentiles([for (final f in frames) ms(f.buildDuration)]),
    'raster_ms': percentiles([for (final f in frames) ms(f.rasterDuration)]),
    'frame_ms': percentiles(totals),
    'janky_pct': frames.isEmpty
        ? 0.0
        : (totals.where((t) => t > 1000 / 60).length / frames.length * 1000)
                  .round() /
              10,
  };
}
