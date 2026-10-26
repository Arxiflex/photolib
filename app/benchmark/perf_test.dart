// The frame-timing benchmarks of tools/perf/budgets.json, run by
// tools/perf/run.sh. Each library of $PERF_FIXTURES (a directory of synthlib
// fixtures; an environment variable, as a define that changed each run would
// compile the app anew each run) is loaded into a replica. A timeline fixture
// becomes the device index, whose timeline is scrolled, jumped through and
// drag-selected, its thumbnails decoded from 64 small JPEG originals, and
// opens the viewer from a cell. Settings' 5,000 device folders scroll. Until
// the folders and albums views exist (M1-15), a grid of placeholders paged
// from a precomputed view table stands in for them. A folder of 10,000 12 MP
// JPEGs is scrolled through the desktop pipeline, cold and warm, opens the
// viewer from a cell, warm and cold, and a 12 MP JPEG's tile is timed. Eight
// videos, which --dart-define=PERF_FFMPEG's FFmpeg makes, are swiped through
// in the viewer, cold and warm, and a 4K 360° video, sphere.mp4 of
// $PERF_FIXTURES, plays projected and flat. A screen of a local photolibd's
// thumbnails opens cold and warm (server_tiles.dart). Each result is printed
// as `result: <json>` once measured, which tools/perf/run.sh keeps should a
// later test hang.
// --dart-define=PERF_TESTS=<test>,... runs those tests alone: the gate's rerun
// of the budgets that failed (tools/perf/run.sh). A janky sample over its
// budget in --dart-define=PERF_BUDGETS (tools/perf/budgets.json) is measured
// again, as is a timing (jank.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/kernel.dart';
import 'package:photolib/core/keystore.dart' show SecretStore;
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/folders/device_folders.dart';
import 'package:photolib/features/library/library.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/disk_cache.dart';
import 'package:photolib/features/library/timeline/ffmpeg.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/native_pipeline.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/features/library/timeline/thumb_hash.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/library/timeline/warmup.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/mpv.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';
import 'package:photolib/features/viewer/video.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:photolib_workers/testing.dart' show Frames, countIdleFrames;
import 'package:video_player/video_player.dart';

import '../test/support/photolibd.dart';
import 'bounded.dart';
import 'fixtures.dart';
import 'jank.dart';
import 'server_tiles.dart';

part 'perf_folder.dart';
part 'perf_video.dart';

// `headless` is software GL under Xvfb, whose raster thread emulates a GPU.
const _target = String.fromEnvironment('PERF_TARGET');
// Whether images reach the screen through a GPU, which `headless` emulates:
// there tile latencies and decoded thumbnails are printed only.
const timed = _target != 'headless';
const _tests = String.fromEnvironment('PERF_TESTS');
const _columns = 6;
const _rowExtent = 120.0;
const _pageSize = 120;
const _palette = [0xffc05a4b, 0xff4b7fc0, 0xff5aa06e, 0xffd9a441];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  // As main.dart does.
  if (Platform.isLinux || Platform.isWindows) MpvPlayers.register();
  final scratch = Directory.systemTemp.createTempSync('photolib-perf');
  tearDownAll(() => scratch.delete(recursive: true));
  late final Vault vault;
  setUpAll(() async {
    vault = Vault(
      location: '${scratch.path}/store',
      keystore: MemoryKeystore(),
      files: storeFiles('${scratch.path}/store'),
      keyring: await loadKernel(),
    );
    await vault.unlock();
  });
  tearDownAll(() => vault.lock());
  // A test over a replica of its own, which its teardown closes: opened
  // outside its body, whose timers throw once bounded.dart stops it.
  void bench(
    String name,
    Duration limit,
    Future<void> Function(WidgetTester tester, Replica db) body, {
    bool skip = false,
  }) => testWidgets(name, (tester) async {
    final db = await vault.openReplica(name: name);
    addTearDown(db.close);
    await bounded(limit, () => body(tester, db));
  }, skip: skip || _tests.isNotEmpty && !_tests.split(',').contains(name));
  // Built here (untimed) when server-tiles runs, after run.sh built it.
  final photolibd = _tests.isEmpty || _tests.split(',').contains('server-tiles')
      ? Photolibd.build()
      : null;
  final originals = writeOriginals('${scratch.path}/originals');
  final fixtures = _fixtures.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final dir in fixtures) {
    final fixture = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final result = _recorder(fixture);

    // Up to five attempts of each janky sample (ADR-0140) on a loaded machine,
    // within perf.py watch's 10 min a fixture.
    bench(fixture, const Duration(minutes: 8), (tester, db) async {
      await _fixture(tester, binding, db, dir, originals.path, result);
    });
  }

  bench('folder-10k', const Duration(minutes: 9), (tester, db) async {
    await _folder(
      tester,
      binding,
      db,
      Directory('${scratch.path}/folder')..createSync(),
      _recorder(''),
      await vault.tileCipher(),
    );
  });

  // Linux under Xvfb, whose screen x11grab reads.
  bench('sphere-video', const Duration(minutes: 9), (tester, _) async {
    for (final flat in [false, true]) {
      final fps = await _sphereFps(tester, flat: flat);
      stdout.writeln('sphere-video: $_target ${flat ? 'flat ' : ''}$fps fps');
      _recorder('')('sphere-video', flat ? 'flat' : 'fps', fps);
    }
  }, skip: _target != 'headless');

  bench('device-folders-5k', const Duration(minutes: 5), (tester, db) async {
    await _deviceFolders(tester, binding, db, _recorder(''));
  });

  bench('server-tiles', const Duration(minutes: 9), (tester, _) async {
    final result = _recorder('');
    await serverTiles(
      tester,
      binding,
      photolibd!,
      Directory('${scratch.path}/server-tiles')..createSync(),
      (metric, value) => result('server-tiles', metric, value),
      await vault.tileCipher(),
    );
  });

  bench('videos', const Duration(minutes: 9), (tester, db) async {
    await _videos(
      tester,
      binding,
      db,
      Directory('${scratch.path}/videos')..createSync(),
      _recorder(''),
      await vault.tileCipher(),
    );
  });
}

/// Loads the fixture of [dir] into [db] and scrolls its view: a timeline
/// (see [_Timeline]) or a stand-in grid.
Future<void> _fixture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Replica db,
  Directory dir,
  String originals,
  _Result result,
) async {
  // fps of the scroll whose janky share counts.
  Future<void> scroll(Future<_Drawn> Function(int attempt) draw) async {
    final drawn = await _leastJanky(
      binding,
      result,
      'timeline-scroll',
      'janky',
      draw,
    );
    final ms = _times(drawn.frames);
    result(
      'timeline-scroll',
      'fps',
      1000 * ms.length / ms.fold(0.0, (a, b) => a + b),
    );
  }

  final count = await loadFixture(db, dir, originals);
  if (count == null) {
    await _Timeline(tester, binding, db, result).run(scroll);
    return;
  }
  final pages = _Pages(db);
  final controller = ScrollController();
  Future<void> settle() async {
    do {
      await pages.idle;
      await binding.endOfFrame;
    } while (pages.loading);
  }

  await tester.pumpWidget(MaterialApp(home: _Grid(pages, controller, count)));
  await binding.endOfFrame;

  await scroll((attempt) async {
    if (attempt > 0) {
      pages.clear();
      controller.jumpTo(0);
    }
    await settle();
    return await _frames(() => _scroll(controller));
  });
}

/// Prints a result for [fixture] ('' for none); a janky share with the share
/// of frames an idle isolate missed meanwhile, which tools/perf/perf.py takes
/// off (ADR-0140), and the attempts it took.
_Result _recorder(String fixture) => (budget, metric, value, {idle, attempts}) {
  final result = {
    'budget': budget,
    'metric': metric,
    'target': _target,
    'fixture': fixture,
    'value': cents(value),
    if (idle != null) 'idle': cents(idle),
    'attempts': ?attempts,
  };
  stdout.writeln('result: ${jsonEncode(result)}');
};

typedef _Result = void Function(
  String budget,
  String metric,
  double value, {
  double? idle,
  int? attempts,
});

final _fixtures = Directory(Platform.environment['PERF_FIXTURES']!);

final Object? _budgets = jsonDecode(
  File(const String.fromEnvironment('PERF_BUDGETS')).readAsStringSync(),
);

/// The limit of [budget]'s [metric] on this target.
num _limit(String budget, String metric) {
  final spec = ['budgets', budget, 'metrics', metric].fold<Object?>(
    _budgets,
    (json, key) => json is Map<String, Object?> ? json[key] : null,
  );
  final limit = spec is Map<String, Object?>
      ? spec['max'] ?? spec['min']
      : null;
  return switch (limit) {
    final num limit => limit,
    {_target: final num limit} => limit,
    _ => throw StateError('No budget for $budget $metric on $_target'),
  };
}

/// Draws a janky sample of [budget]'s [metric] with [draw], its [share] of
/// janky frames, and again after a rest while it is over its budget less what
/// an idle isolate missed meanwhile, five times at most (jank.dart); records
/// the least janky and returns it.
Future<_Drawn> _leastJanky(
  IntegrationTestWidgetsFlutterBinding binding,
  _Result result,
  String budget,
  String metric,
  Future<_Drawn> Function(int attempt) draw, {
  double Function(IntegrationTestWidgetsFlutterBinding, List<FrameTiming>)
      share =
      _janky,
}) async {
  final limit = _limit(budget, metric);
  final (drawn, jank, attempts) = await leastJanky(
    (attempt) async {
      final drawn = await draw(attempt);
      return (drawn, (janky: share(binding, drawn.frames), idle: drawn.idle));
    },
    budget: limit.toDouble(),
    rest: (last) {
      stdout.writeln(
        'janky: $_target $budget $metric ${cents(last.janky)} %, '
        '${cents(last.idle)} % missed idle, over $limit %: again in 5 s',
      );
      return Future<void>.delayed(const Duration(seconds: 5));
    },
  );
  result(budget, metric, jank.janky, idle: jank.idle, attempts: attempts);
  return drawn;
}

Future<void> _scroll(ScrollController controller) => controller.animateTo(
  min(20000, controller.position.maxScrollExtent),
  duration: const Duration(seconds: 5),
  curve: Curves.linear,
);

/// The app showing [pages] of [buckets] in the timeline [view], with
/// [pipeline] and [db] as its own; a cell opens the viewer.
Widget _app(
  ThumbnailPipeline pipeline,
  Replica db,
  TimelineBuckets buckets,
  ValueListenable<TimelinePages> pages,
  Thumbnails thumbnails,
  GlobalKey<TimelineViewState> view, {
  ValueNotifier<Selection>? selection,
  ValueNotifier<int>? position,
  ThumbHash? Function(Object item)? placeholder,
}) => ProviderScope(
  overrides: [
    thumbnailPipelineProvider.overrideWith((ref) async => pipeline),
    replicaProvider.overrideWith((ref) async => db),
    // Videos play as they show, which the swipes between them time.
    settingsStoreProvider.overrideWithValue(_Played()),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ValueListenableBuilder<TimelinePages>(
        valueListenable: pages,
        builder: (context, pages, _) => TimelineView(
          key: view,
          buckets: buckets,
          pages: pages,
          thumbnails: thumbnails,
          selection: selection ?? ValueNotifier(Selection.none),
          placeholder: placeholder,
          onOpen: (asset, cell) => Navigator.of(context).push(
            ViewerPage.route(
              () => cell,
              ViewerPage(
                pages: pages,
                count: buckets.assets,
                position: (position ?? ValueNotifier(asset))..value = asset,
                thumbnails: thumbnails,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// The device index's timeline: scrolled, jumped from its far end to months
/// spread over it, with no page or thumbnail loaded, opening the viewer, and
/// drag-selected for 5,000 items at its densest level.
class _Timeline {
  new(this.tester, this.binding, this.db, this.result);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  final Replica db;
  final _Result result;
  final ThumbnailPipeline pipeline = ThumbnailPipeline(originals: true);
  final ValueNotifier<Selection> selection = ValueNotifier(Selection.none);
  final GlobalKey<TimelineViewState> key = GlobalKey();
  int decoding = 0;
  late final Thumbnails thumbnails = Thumbnails((item, tier, tile) async {
    decoding++;
    try {
      return await pipeline.load(item as ThumbnailItem, tier, tile);
    } finally {
      decoding--;
    }
  });
  late final TimelinePages first;
  late final ValueNotifier<TimelinePages> pages;
  // The page fetches in flight, which the run waits out before the teardown
  // closes the replica under them.
  int fetching = 0;
  Future<List<Object>> Function(int, int) counted(
    Future<List<Object>> Function(int, int) fetch,
  ) => (from, count) async {
    fetching++;
    try {
      return await fetch(from, count);
    } finally {
      fetching--;
    }
  };

  TimelineViewState get view => key.currentState!;
  ScrollController get controller => view.controller;
  bool shown() => allShown(view, pages.value, thumbnails);
  Future<void> until(bool Function() done) => _until(binding, done);

  /// Its benchmarks, the scroll's attempts drawn by [scroll].
  Future<void> run(
    Future<void> Function(Future<_Drawn> Function(int attempt) draw) scroll,
  ) async {
    final (buckets, loaded) = await libraryTimeline(db).first;
    // Its first page loaded, as libraryTimeline gives it, with every fetch
    // counted.
    first = TimelinePages(counted(loaded.fetch), size: loaded.size);
    if (buckets.assets > 0) await first.preload(0);
    pages = ValueNotifier(first);
    await tester.pumpWidget(
      _app(pipeline, db, buckets, pages, thumbnails, key, selection: selection),
    );
    await binding.endOfFrame;
    // A retry starts as the first did: at the top, with nothing else loaded.
    await scroll((attempt) async {
      if (attempt > 0) {
        await until(() => decoding == 0);
        controller.jumpTo(0);
        await reload();
        thumbnails.clear();
      }
      await until(shown);
      return await _frames(() => _scroll(controller));
    });
    await scrubs();
    if (!view.mounted) return;
    await opens();
    await dragSelect();
    await tester.pumpWidget(const SizedBox());
    await until(() => fetching == 0);
  }

  /// The timeline's pages anew, with only the first loaded, as
  /// libraryTimeline makes them: its days, which it counts over every asset,
  /// stay those of the fixture.
  Future<void> reload() async {
    final fresh = TimelinePages(first.fetch, size: first.size);
    await fresh.preload(0);
    pages.value = fresh;
  }

  /// Each jump starts at the far end, all loaded there and nothing of the
  /// month, nor anything in flight. The fastest of up to three per month
  /// counts. Decoded images reach the screen through the GPU, which
  /// `headless` emulates: its thumbnails are not timed.
  Future<void> scrubs() async {
    final (fast, decodedFast) = (
      _limit('scrub-to-month', 'placeholders'),
      timed ? _limit('scrub-to-month', 'thumbnails_local') : double.infinity,
    );
    final months = view.segments.months;
    var placeholders = 0.0;
    var decoded = 0.0;
    for (var i = 0; i < months.length; i += max(1, months.length ~/ 8)) {
      final month = months[i].$1;
      final (fastest, all) = await bestOf(
        3,
        (_) async {
          controller.jumpTo(controller.position.maxScrollExtent);
          await reload();
          await until(() => shown() && decoding == 0);
          thumbnails
            ..paused = true
            ..clear();
          final watch = Stopwatch()..start();
          view.jumpToMonth(month ~/ 100, month % 100);
          thumbnails.paused = false;
          await binding.endOfFrame;
          final painted = watch.elapsedMicroseconds / 1000;
          await until(shown);
          return (painted, watch.elapsedMicroseconds / 1000);
        },
        (a, b) => (min(a.$1, b.$1), min(a.$2, b.$2)),
        (best) => best.$1 <= fast && best.$2 <= decodedFast,
      );
      placeholders = max(placeholders, fastest);
      decoded = max(decoded, all);
    }
    result('scrub-to-month', 'placeholders', placeholders);
    if (timed) result('scrub-to-month', 'thumbnails_local', decoded);
  }

  /// From the tap on a shown cell to the end of the first frame of the
  /// viewer, and of the first with its bar, the fastest of up to three, with
  /// the grid's thumbnails in memory and without.
  Future<void> opens() async {
    final navigator = Navigator.of(view.context);
    for (final (metric, chrome, cold) in [
      ('open', 'chrome', false),
      ('open_cold', 'chrome_cold', true),
    ]) {
      final limits = (_limit('viewer', metric), _limit('viewer', chrome));
      final (open, barred) = await bestOf<(double, double)>(
        3,
        (_) async {
          controller.jumpTo(0);
          await until(() => shown() && decoding == 0);
          if (cold) thumbnails.clear();
          final watch = Stopwatch()..start();
          await tester.tapAt(view.cellOf(0).center);
          final viewer = find.byType(ViewerPage);
          final bar = find.byKey(const ValueKey('viewer-close'));
          double? open;
          double? barred;
          while ((open == null || barred == null) &&
              watch.elapsed.inSeconds < 5) {
            await binding.endOfFrame;
            final ms = watch.elapsedMicroseconds / 1000;
            if (viewer.evaluate().isNotEmpty) open ??= ms;
            if (bar.evaluate().isNotEmpty) barred ??= ms;
          }
          expect(barred, open, reason: 'the bar shows from the first frame');
          await Future<void>.delayed(const Duration(seconds: 1));
          navigator.pop();
          await until(() => viewer.evaluate().isEmpty);
          return (open!, barred!);
        },
        (a, b) => (min(a.$1, b.$1), min(a.$2, b.$2)),
        (best) => best.$1 <= limits.$1 && best.$2 <= limits.$2,
      );
      result('viewer', metric, open);
      result('viewer', chrome, barred);
    }
  }

  Future<void> dragSelect() async {
    view.zoom(-Density.values.length);
    await binding.endOfFrame;
    final size = view.context.size!;
    final cell = view.layout.cellExtent;
    await _leastJanky(binding, result, 'drag-select-5k', 'janky', (_) async {
      selection.value = Selection.none;
      controller.jumpTo(0);
      await until(() => shown() && decoding == 0);
      final drawn = await _frames(() async {
        final drag = await tester.startGesture(
          Offset(cell / 2, TimelineViewState.headerExtent + cell / 2),
        );
        await Future<void>.delayed(kLongPressTimeout * 2);
        await drag.moveTo(Offset(cell / 2, size.height - 4));
        await until(() => selection.value.count >= 5000);
        await drag.up();
      });
      expect(selection.value.count, greaterThanOrEqualTo(5000));
      return drawn;
    });
  }
}

/// The frames' times in ms: build and raster, or build alone on `headless`,
/// where the raster thread emulates a GPU.
List<double> _times(List<FrameTiming> frames) => [
  for (final f in frames)
    max(
          f.buildDuration.inMicroseconds,
          _target == 'headless' ? 0 : f.rasterDuration.inMicroseconds,
        ) /
        1000,
];

/// The share of [frames] over the display's frame budget.
double _janky(
  IntegrationTestWidgetsFlutterBinding binding,
  List<FrameTiming> frames,
) {
  final display = binding.platformDispatcher.views.first.display;
  final budget = 1000 / max(60, display.refreshRate);
  return lateShare(_times(frames), (m) => m > budget);
}

/// Scrolls Settings' source tree of 5,000 device folders (ADR-0210,
/// ADR-0290), on 2 volumes 3 deep, every one open by a search, 20,000 px in
/// 5 s.
Future<void> _deviceFolders(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Replica db,
  _Result result,
) async {
  await db.customStatement(
    'WITH RECURSIVE f(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM f '
    'WHERE i < 5000) INSERT INTO device_folder (id, volume, path, name, '
    "visibility) SELECT i, IIF(i % 7 = 0, '1111-2222', 'external_primary'), "
    "'Pictures/Folder ' || (i / 100) || '/Folder ' || i || '/', "
    "'Folder ' || i, IIF(i % 5 = 0, 'hidden', 'inherit') FROM f",
  );
  await db.customStatement(
    'INSERT INTO timeline_day SELECT 20240101 + id % 28, id, 0, id '
    'FROM device_folder',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [replicaProvider.overrideWith((ref) async => db)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: SourcesPage(),
      ),
    ),
  );
  await _until(binding, () => find.byType(EditableText).evaluate().isNotEmpty);
  // As the platform types: a profile build ignores tester.enterText's input.
  tester
      .state<EditableTextState>(find.byType(EditableText))
      .userUpdateTextEditingValue(
        const TextEditingValue(text: 'Folder'),
        SelectionChangedCause.keyboard,
      );
  await _until(binding, () => find.text('Folder 1').evaluate().isNotEmpty);
  // The tree's list, not the search field's or the details pane's.
  final list = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  if (list.position.maxScrollExtent < 20000) {
    throw StateError('the tree scrolls ${list.position.maxScrollExtent} px');
  }
  await _leastJanky(binding, result, 'device-folders-scroll', 'janky', (
    _,
  ) async {
    list.position.jumpTo(0);
    return await _frames(
      () => list.position.animateTo(
        min(20000, list.position.maxScrollExtent),
        duration: const Duration(seconds: 5),
        curve: Curves.linear,
      ),
    );
  });
}

/// Polls [done] without asking for frames, whose raster would compete with
/// the decodes, then waits for the frame that shows the result.
Future<void> _until(
  IntegrationTestWidgetsFlutterBinding binding,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await binding.endOfFrame;
}

/// The frames drawn while [action] runs, after a rest, and the share in % of
/// 60 Hz frames an idle isolate of the app missed meanwhile: the machine's
/// load, which slows every frame too (ADR-0140). A profile build reports
/// frame timings in batches 100 ms apart: this keeps those whose vsync
/// started while [action] ran, once the last has arrived.
Future<_Drawn> _frames(Future<void> Function() action) async {
  const rest = Duration(milliseconds: 500);
  final frames = <FrameTiming>[];
  await Future<void>.delayed(rest);
  SchedulerBinding.instance.addTimingsCallback(frames.addAll);
  try {
    final idle = await countIdleFrames();
    final start = Timeline.now;
    final int end;
    final Frames missed;
    try {
      await action();
    } finally {
      end = Timeline.now;
      missed = await idle();
    }
    await Future<void>.delayed(rest);
    return (frames: framesWithin(frames, start, end), idle: 100 * missed.share);
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(frames.addAll);
  }
}

typedef _Drawn = ({List<FrameTiming> frames, double idle});

/// The cells of `temp.view`, loaded a page at a time.
class _Pages extends ChangeNotifier {
  new(this._db);

  final Replica _db;
  final _pages = <int, List<(String?, int)>>{};
  final _loading = <int, Future<void>>{};

  bool get loading => _loading.isNotEmpty;
  Future<void> get idle => Future.wait(_loading.values);

  void clear() => _pages.clear();

  /// The cell at [index], or null while its page loads.
  (String?, int)? operator [](int index) {
    final page = index ~/ _pageSize;
    final cells = _pages[page];
    if (cells == null) {
      _loading[page] ??= _load(page);
      return null;
    }
    return cells[index % _pageSize];
  }

  Future<void> _load(int page) async {
    final rows = await _db
        .customSelect(
          'SELECT label, colour FROM temp.view WHERE pos > ${page * _pageSize} '
          'AND pos <= ${(page + 1) * _pageSize} ORDER BY pos',
        )
        .get();
    _pages[page] = [
      for (final r in rows)
        (r.readNullable<String>('label'), r.read<int>('colour')),
    ];
    _loading.remove(page);
    notifyListeners();
  }
}

class _Grid extends StatelessWidget {
  const new(this.pages, this.controller, this.count);

  final _Pages pages;
  final ScrollController controller;
  final int count;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pages,
    builder: (context, _) => GridView.builder(
      controller: controller,
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisExtent: _rowExtent,
      ),
      itemBuilder: (context, index) {
        final cell = pages[index];
        if (cell == null) return const SizedBox.shrink();
        final (label, colour) = cell;
        return ColoredBox(
          color: Color(_palette[colour]),
          child: label == null ? null : Center(child: Text(label)),
        );
      },
    ),
  );
}

/// Settings in which videos play as they show.
class _Played implements SecretStore {
  @override
  Future<String?> read() async =>
      jsonEncode(const Settings(toggles: {Toggle.autoplay: true}).toJson());

  @override
  Future<void> write(String? value) async {}
}
