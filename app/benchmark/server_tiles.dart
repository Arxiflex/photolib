// The server-tiles budget of tools/perf/budgets.json, run by perf_test.dart.
import 'dart:io';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/native_pipeline.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart' show TileCipher;

import '../test/support/server_library.dart';

/// A screen of a server library's tiles (docs/10 §3.4, T5): 96 photos of an
/// external library of a photolibd on loopback, synced into a replica and
/// shown by the timeline through the desktop pipeline with the session's
/// media. Cold, with an empty disk cache, the p95 of the time each cell of
/// the first screen waits for its tile from the open; warm, opened again
/// with nothing in memory and the tiles on disk, the most frames a visible
/// cell goes without its tile. The best of three each.
Future<void> serverTiles(
  WidgetTester tester,
  SchedulerBinding binding,
  String photolibd,
  Directory dir,
  void Function(String metric, double value) result,
  TileCipher cipher,
) async {
  final library = await ServerLibrary.start(photolibd, 96);
  addTearDown(library.stop);
  final items = library.items;
  final screen = _Screen(
    tester,
    binding,
    TimelinePages(
      (first, count) async =>
          items.sublist(first, min(first + count, items.length)),
    ),
    TimelineBuckets(days: [20260101], counts: [items.length]),
  );
  await screen.pages.preload(0);
  final media = library.app.read(mediaProvider);
  var (cold, warm) = (double.infinity, 1 << 30);
  for (var run = 0; run < 3; run++) {
    final cache = await DiskCache.open('${dir.path}/cache-$run', cipher);
    final pipeline = await desktopPipeline(cache, media: media);
    final fetched = <String, List<double>>{};
    final read = <String, List<double>>{};
    final (waits, _) = await screen.open(pipeline, fetched);
    final (again, frames) = await screen.open(pipeline, read);
    stdout.writeln(
      'server-tiles: cold ${_report(waits, fetched)}; '
      'warm ${_report(again, read)}, $frames frames',
    );
    (cold, warm) = (min(cold, _p(waits, 95)), min(warm, frames));
    await tester.pumpWidget(const SizedBox());
    await pipeline.idle;
    await cache.close();
  }
  result('cold_p95', cold);
  result('warm_blank', warm.toDouble());
}

/// The timeline of [pages], opened anew.
class _Screen {
  new(this.tester, this.binding, this.pages, this.buckets);

  final WidgetTester tester;
  final SchedulerBinding binding;
  final TimelinePages pages;
  final TimelineBuckets buckets;
  final _key = GlobalKey<TimelineViewState>();

  /// Each visible cell's wait for its tile from the open, in ms, and the most
  /// frames one went without it, with nothing in memory; each tile's [stages].
  Future<(List<double>, int)> open(
    ThumbnailPipeline pipeline,
    Map<String, List<double>> stages,
  ) async {
    // A frame without the view, so that the next one makes it anew.
    await tester.pumpWidget(const SizedBox());
    await binding.endOfFrame;
    final thumbnails = Thumbnails(
      (item, tier, tile) => pipeline.load(item as ThumbnailItem, tier, tile),
      cached: (item, tier) => pipeline.cached(item as ThumbnailItem, tier),
      onTile: (_, _, tile) {
        for (final MapEntry(:key, :value) in tile.stages.entries) {
          (stages[key] ??= []).add(value);
        }
      },
    );
    bool shown(TimelineViewState view, int a) {
      final dpr = MediaQuery.devicePixelRatioOf(view.context);
      final tier = tierFor(view.layout.cellExtent * dpr);
      return thumbnails.shown(pages[a]!, tier) != null;
    }

    var (longest, streaks, on) = (0, <int, int>{}, true);
    void frame(Duration _) {
      if (!on) return;
      if (_key.currentState case final view?) {
        final (first, last) = view.visible;
        streaks = {
          for (var a = first; a <= last; a++)
            if (!shown(view, a)) a: (streaks[a] ?? 0) + 1,
        };
        longest = max(longest, streaks.values.fold(0, max));
      }
      binding.addPostFrameCallback(frame);
    }

    binding.addPostFrameCallback(frame);
    final opened = Stopwatch()..start();
    await tester.pumpWidget(_app(thumbnails));
    await binding.endOfFrame;
    final view = _key.currentState!;
    final (first, last) = view.visible;
    final waits = <int, double>{};
    while (waits.length <= last - first && opened.elapsed.inSeconds < 10) {
      for (var a = first; a <= last; a++) {
        if (!waits.containsKey(a) && shown(view, a)) {
          waits[a] = opened.elapsedMicroseconds / 1000;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await binding.endOfFrame;
    on = false;
    await pipeline.idle;
    return (
      [...waits.values, for (var a = waits.length; a <= last - first; a++) 1e4],
      longest,
    );
  }

  Widget _app(Thumbnails thumbnails) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TimelineView(
        key: _key,
        buckets: buckets,
        pages: pages,
        thumbnails: thumbnails,
        selection: ValueNotifier(Selection.none),
        placeholder: (item) => (item as ThumbnailItem).thumbHash,
        onOpen: (_, _) {},
      ),
    ),
  );
}

/// A percentile by nearest rank.
double _p(List<double> values, int percentile) {
  final sorted = [...values]..sort();
  return sorted[(percentile * sorted.length / 100).ceil() - 1];
}

String _report(List<double> waits, Map<String, List<double>> stages) => [
  '${waits.length} tiles p50/p95 ${_p(waits, 50)}/${_p(waits, 95)} ms',
  for (final MapEntry(:key, :value) in stages.entries)
    '$key ${_p(value, 50)}/${_p(value, 95)} ms',
].join(', ');
