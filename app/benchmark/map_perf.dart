// The map over a synthlib library of a million assets, a million of them
// geotagged by the generator's phones (tools/synthlib): the time to read their
// places and to index them, then the frames drawn while the camera sweeps the
// world, zooms in on Berlin and pans there at three zooms, and how long each
// query of the kernel took. Run it with
//
//   MAP_FIXTURE=<synthlib dir> flutter drive --profile -d linux \
//     --driver test_driver/integration_test.dart --target benchmark/map_perf.dart
//
// (under xvfb-run on a machine with no display; `taskset -c 0,1` limits its
// cores). Each result is printed as `result: <json>`; this is not a budget of
// tools/perf/budgets.json, which docs/19 §3 pins.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/kernel.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/map/map_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;

import 'bounded.dart';
import 'fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  final scratch = Directory.systemTemp.createTempSync('photolib-map-perf');
  tearDownAll(() => scratch.delete(recursive: true));

  testWidgets('map-1m', (tester) async {
    await bounded(
      const Duration(minutes: 20),
      () => _map(tester, binding, scratch),
    );
  });
}

Future<void> _map(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Directory scratch,
) async {
  final fixture = Directory(Platform.environment['MAP_FIXTURE']!);
  final vault = Vault(
    location: '${scratch.path}/store',
    keystore: MemoryKeystore(),
    files: storeFiles('${scratch.path}/store'),
    keyring: await loadKernel(),
  );
  await vault.unlock();
  addTearDown(vault.lock);
  final db = await vault.openReplica(name: 'map');
  addTearDown(db.close);
  final loaded = Stopwatch()..start();
  await loadFixture(db, fixture, writeOriginals('${scratch.path}/o').path);
  _result('load-fixture-s', loaded.elapsedMilliseconds / 1000);

  final read = Stopwatch()..start();
  final points = await geoPoints(db);
  _result('located', points.length.toDouble());
  _result('read-places-s', read.elapsedMilliseconds / 1000);

  final queries = <double>[];
  final controller = MapController();
  final opened = Stopwatch()..start();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [replicaProvider.overrideWith((ref) => db)],
      child: MaterialApp(
        theme: appTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapPage(
          controller: controller,
          onQuery: (took, clusters) => queries.add(took.inMicroseconds / 1000),
        ),
      ),
    ),
  );
  while (queries.isEmpty) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (opened.elapsed > const Duration(minutes: 5)) {
      fail('the map showed nothing in 5 minutes');
    }
  }
  _result('open-to-first-clusters-s', opened.elapsedMilliseconds / 1000);
  queries.clear();

  Future<void> sweep(
    String name,
    double zoom,
    LatLng from,
    LatLng to, {
    double? zoomTo,
  }) => _sweep(tester, binding, controller, queries, (
    name,
    zoom,
    from,
    to,
    zoomTo,
  ));

  await sweep('world-pan', 1.5, const LatLng(20, -150), const LatLng(20, 150));
  await sweep(
    'zoom-in-berlin',
    2,
    const LatLng(52.5, 13.4),
    const LatLng(52.5, 13.4),
    zoomTo: 14,
  );
  for (final zoom in [6.0, 10.0, 14.0]) {
    final span = 90 / pow(2, zoom);
    await sweep(
      'pan-z${zoom.toInt()}',
      zoom,
      LatLng(52.5 - span, 13.4 - span),
      LatLng(52.5 + span, 13.4 + span),
    );
  }
}

/// Moves the camera from [path]'s start to its end for 5 s, a step a frame,
/// and reports the frames and queries meanwhile.
Future<void> _sweep(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  MapController controller,
  List<double> queries,
  (String, double, LatLng, LatLng, double?) path,
) async {
  final (name, zoom, from, to, zoomTo) = path;
  const seconds = 5;
  controller.move(from, zoom);
  await tester.pump(const Duration(milliseconds: 100));
  queries.clear();
  final frames = <FrameTiming>[];
  void listen(List<FrameTiming> t) => frames.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(listen);
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: seconds)) {
    final t = clock.elapsedMicroseconds / (seconds * 1e6);
    controller.move(
      LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      ),
      zoom + ((zoomTo ?? zoom) - zoom) * t,
    );
    await binding.endOfFrame;
  }
  SchedulerBinding.instance.removeTimingsCallback(listen);
  await tester.pump(const Duration(seconds: 1));
  _report(name, frames, queries);
}

void _result(String metric, double value) {
  final result = {
    'budget': 'map',
    'metric': metric,
    'value': (value * 100).round() / 100,
  };
  stdout.writeln('result: ${jsonEncode(result)}');
}

double _percentile(List<double> sorted, double p) =>
    sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

void _report(String name, List<FrameTiming> frames, List<double> queries) {
  final build = [for (final f in frames) f.buildDuration.inMicroseconds / 1000]
    ..sort();
  final raster = [
    for (final f in frames) f.rasterDuration.inMicroseconds / 1000,
  ]..sort();
  final worst = [
    for (final f in frames)
      max(f.buildDuration.inMicroseconds, f.rasterDuration.inMicroseconds) /
          1000,
  ];
  final janky = worst.where((ms) => ms > 1000 / 60).length;
  final q = [...queries]..sort();
  final result = {
    'budget': 'map',
    'scenario': name,
    'frames': frames.length,
    'build_ms_p50': _percentile(build, 0.5),
    'build_ms_p95': _percentile(build, 0.95),
    'build_ms_max': build.isEmpty ? 0 : build.last,
    'raster_ms_p50': _percentile(raster, 0.5),
    'raster_ms_p95': _percentile(raster, 0.95),
    'janky_pct': frames.isEmpty ? 100 : (100 * janky / frames.length).round(),
    'queries': queries.length,
    'query_ms_p50': _percentile(q, 0.5),
    'query_ms_p95': _percentile(q, 0.95),
    'query_ms_max': q.isEmpty ? 0 : q.last,
  };
  stdout.writeln('result: ${jsonEncode(result)}');
}
