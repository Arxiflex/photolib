part of 'perf_test.dart';

/// Eight 12 MP JPEGs with a camera's noise and an EXIF thumbnail, as files of
/// 10,000 names in [dir], become a folder's items, whose timeline is scrolled
/// through the desktop pipeline (ADR-0107, ADR-0114). Cold, with an empty
/// disk cache: 20,000 px in 5 s (janky), then at 1 and 3 screens a second and
/// a fling over parts not yet seen, timing each tile's stages. Then the
/// warm-up fills the disk cache and the index's ThumbHashes, the app opens
/// cold (empty memory) and scrolls the same ways again: no visible cell may go
/// without an image for more than a frame. A tile of one original is timed
/// cold (its first decoder) and warm (from the disk cache to an image), the
/// fastest of ten each.
Future<void> _folder(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Replica db,
  Directory dir,
  _Result result,
  TileCipher cipher,
) async {
  final folder = _Folder(tester, binding, db, dir, result, cipher);
  final originals = await folder.make();
  await folder.cold();
  if (!await folder.viewer()) return;
  await folder.warmUp();
  await folder.coldOpen();
  await folder.warm();
  await tester.pumpWidget(const SizedBox());
  await folder.tile(originals.first);
}

/// The folder benchmark's pipeline, the cells it shows and its tiles' stages.
class _Folder {
  new(this.tester, this.binding, this.db, this.dir, this.result, this.cipher);

  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  final Replica db;
  final Directory dir;
  final _Result result;
  final TileCipher cipher;
  final GlobalKey<TimelineViewState> key = GlobalKey();
  late ThumbnailPipeline pipeline;
  late TimelinePages pages;
  late Thumbnails shown;
  int decoding = 0;
  // Each tile's stages in ms, and those of a decode or a read with its upload.
  Map<String, List<double>> stages = {};

  TimelineViewState get view => key.currentState!;
  int get tier => tierFor(
    view.layout.cellExtent * MediaQuery.devicePixelRatioOf(view.context),
  );
  Future<void> until(bool Function() done) =>
      _until(binding, done, timeout: const Duration(seconds: 60));

  /// The originals, their 10,000 links as the folder's items and the
  /// pipeline over an empty disk cache; returns the originals.
  Future<List<String>> make() async {
    final originals = await Future.wait([
      for (var k = 0; k < 8; k++) _photo('${dir.path}/original-$k.jpg', k),
    ]);
    for (var i = 0; i < 10000; i++) {
      Link('${dir.path}/$i.jpg').createSync(originals[i % 8]);
    }
    await db.customStatement(
      'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < 9999) INSERT INTO local_asset (id, source, volume, '
      'source_id, path, size, mtime, taken_local, extracted, added) SELECT '
      "randomblob(16), 'folder', ?, i, i || '.jpg', 1, 0, "
      "strftime('%Y-%m-%dT%H:%M:%S', 1700000000 - i * 3600, 'unixepoch'), 1, "
      '0 FROM n',
      [dir.path],
    );
    pipeline = await desktopPipeline(
      await DiskCache.open('${dir.path}/cache', cipher),
    );
    return originals;
  }

  Thumbnails thumbnails() => Thumbnails(
    (item, tier, tile) async {
      decoding++;
      try {
        return await pipeline.load(item as ThumbnailItem, tier, tile);
      } finally {
        decoding--;
      }
    },
    cached: (item, tier) => pipeline.cached(item as ThumbnailItem, tier),
    onTile: (_, _, tile) {
      final ms = tile.stages;
      for (final (name, value) in [
        for (final e in ms.entries) (e.key, e.value),
        if (ms['decode'] case final decode?) ('exact', decode + ms['upload']!),
        if (ms['cache'] case final cache?) ('read', cache + ms['upload']!),
      ]) {
        (stages[name] ??= []).add(value);
      }
    },
  );

  /// Opens the folder's timeline anew, with nothing in memory.
  Future<void> open() async {
    await tester.pumpWidget(const SizedBox());
    shown = thumbnails();
    final (buckets, first) = await libraryTimeline(db).first;
    pages = first;
    await tester.pumpWidget(
      _app(
        pipeline,
        db,
        buckets,
        ValueNotifier(pages),
        shown,
        key,
        placeholder: (item) => (item as ThumbnailItem).thumbHash,
      ),
    );
    await binding.endOfFrame;
  }

  /// The longest any visible cell went without an image while [action] ran,
  /// in frames.
  Future<int> blank(Future<void> Function() action) async {
    var longest = 0;
    var on = true;
    var streaks = <int, int>{};
    void frame(Duration _) {
      if (!on) return;
      final (first, last) = view.visible;
      final next = <int, int>{};
      for (var a = first; a <= last; a++) {
        final item = pages[a];
        if (item == null || shown.shown(item, tier) == null) {
          longest = max(longest, next[a] = (streaks[a] ?? 0) + 1);
        }
      }
      streaks = next;
      SchedulerBinding.instance.addPostFrameCallback(frame);
    }

    SchedulerBinding.instance.addPostFrameCallback(frame);
    try {
      await action();
    } finally {
      on = false;
    }
    return longest;
  }

  /// At 1 and 3 screens a second and a fling, each over a part of its own
  /// from 30,000 px on, with nothing in memory.
  Future<void> runs(
    void Function(String run, int blank, Map<String, List<double>> stages) got,
  ) async {
    final controller = view.controller;
    final screen = controller.position.viewportDimension;
    var from = 30000.0;
    for (final (run, speed) in [('1x', 1.0), ('3x', 3.0), ('fling', 0.0)]) {
      controller.jumpTo(from);
      shown.clear();
      await until(() => decoding == 0 && allShown(view, pages, shown));
      stages = {};
      final frames = await blank(() async {
        if (speed == 0) {
          (controller.position as ScrollPositionWithSingleContext).goBallistic(
            8000,
          );
          await until(() => !controller.position.isScrollingNotifier.value);
        } else {
          await controller.animateTo(
            from + 10 * speed * screen,
            duration: const Duration(seconds: 10),
            curve: Curves.linear,
          );
        }
      });
      await until(() => decoding == 0);
      got(run, frames, stages);
      from += 40 * screen;
    }
  }

  void report(String run, Map<String, List<double>> stages) {
    final each = [
      for (final MapEntry(key: stage, value: ms) in stages.entries)
        [
          stage,
          '${_p(ms, 50).toStringAsFixed(1)}/${_p(ms, 95).toStringAsFixed(1)}',
          'ms (${ms.length})',
        ].join(' '),
    ];
    stdout.writeln('tile-latency: $_target $run p50/p95 ${each.join(', ')}');
  }

  /// Scrolls with an empty disk cache, one of its own for each attempt, and
  /// times tiles, checked where a GPU shows them: `headless` emulates one, and
  /// the gate's shared machines time decodes as they will.
  Future<void> cold() async {
    await _leastJanky(binding, result, 'folder-scroll', 'cold_janky', (
      attempt,
    ) async {
      if (attempt > 0) {
        await until(() => decoding == 0);
        await pipeline.idle;
        pipeline = await desktopPipeline(
          await DiskCache.open('${dir.path}/cache-$attempt', cipher),
        );
      }
      await open();
      await until(() => allShown(view, pages, shown));
      return await _frames(() => _scroll(view.controller));
    });
    await until(() => decoding == 0);
    await runs((run, _, stages) {
      report('cold $run', stages);
      if (!timed) return;
      result('tile-latency', 'embedded_$run', _p(stages['embedded'], 95));
      result('tile-latency', 'exact_$run', _p(stages['exact'], 95));
    });
    await pipeline.idle;
  }

  /// The slowest frame from the tap on a cell through the viewer's first
  /// page turn, of its open alone and of its dismiss: warm, over cells
  /// shown, whose tiles are in memory and on disk; cold, at the folder's end,
  /// which no cell has shown, while its cells decode. False when the grid is
  /// gone.
  Future<bool> viewer() async {
    final grid = view;
    if (!grid.mounted) return false;
    final page = find.byType(ViewerPage);
    for (final metric in ['warm', 'cold']) {
      if (metric == 'cold') {
        shown.paused = true;
        grid.controller.jumpTo(grid.controller.position.maxScrollExtent);
        await binding.endOfFrame;
      } else {
        grid.controller.jumpTo(0);
        await until(() => allShown(grid, pages, shown) && decoding == 0);
      }
      var opened = 0;
      final drawn = await _frames(() async {
        shown.paused = false;
        final (first, last) = grid.visible;
        await tester.tapAt(grid.cellOf((first + last) ~/ 2).center);
        await Future<void>.delayed(const Duration(seconds: 1));
        opened = Timeline.now;
        expect(page, findsOneWidget);
        final swipe = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        for (var i = 0; i < 10; i++) {
          await swipe.moveBy(const Offset(-30, 0));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        await swipe.up();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      result('viewer-folder', metric, _times(drawn.frames).reduce(max));
      result(
        'viewer-folder',
        '${metric}_open',
        _times(framesWithin(drawn.frames, 0, opened)).reduce(max),
      );
      // A finger's swipe down a quarter of the height: past 16 %, a dismiss.
      final step = Offset(0, tester.getSize(page).height / 40);
      final dismissed = await _frames(() async {
        final swipe = await tester.startGesture(
          tester.getCenter(find.byType(PageView)),
        );
        for (var i = 0; i < 10; i++) {
          await swipe.moveBy(step);
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        await swipe.up();
        await until(() => page.evaluate().isEmpty);
      });
      result(
        'viewer-folder',
        '${metric}_dismiss',
        _times(dismissed.frames).reduce(max),
      );
    }
    await until(() => decoding == 0);
    return true;
  }

  /// Warms every item into the disk cache and the index's ThumbHashes.
  Future<void> warmUp() async {
    final items = [
      for (final item in await folderTimeline(db, dir.path))
        ThumbnailItem.local(item),
    ];
    final stopped = ValueNotifier(false);
    final warmup = Warmup(
      (item) => pipeline.warm(item, tier),
      stopped,
      workers: pipeline.workers,
      save: (hashes) => saveThumbHashes(db, hashes),
    );
    final warming = Stopwatch()..start();
    // A line every thousand tiles: tools/perf/run.sh takes 5 min without one
    // for a hang, and a loaded machine warms 10,000 tiles slower than that.
    void tell() {
      if (warmup.progress.value case (final done, _)
          when done > 0 && done % 1000 == 0) {
        stdout.writeln('warm-up: $_target $done tiles');
      }
    }

    warmup.progress.addListener(tell);
    try {
      warmup.add(items);
      await _until(
        binding,
        () => warmup.progress.value == (0, 0),
        timeout: const Duration(minutes: 5),
      );
    } finally {
      stopped.value = true;
      warmup.progress.removeListener(tell);
    }
    stdout.writeln(
      'warm-up: $_target ${items.length} tiles in '
      '${warming.elapsed.inSeconds} s',
    );
  }

  /// A cold open: the first screen's ThumbHashes in its first frame, then how
  /// long each of its cells waits for an image.
  Future<void> coldOpen() async {
    final opened = Stopwatch()..start();
    await open();
    await binding.endOfFrame;
    final (first, last) = view.visible;
    final hashed = [
      for (var a = first; a <= last; a++)
        (pages[a] as ThumbnailItem?)?.hash != null,
    ];
    final waits = <int, double>{};
    while (waits.length < hashed.length && opened.elapsed.inSeconds < 10) {
      for (var a = first; a <= last; a++) {
        if (!waits.containsKey(a) && shown.shown(pages[a]!, tier) != null) {
          waits[a] = opened.elapsedMicroseconds / 1000;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final missing = hashed.where((h) => !h).length;
    stdout.writeln(
      'cold-open: $_target ${hashed.length - missing} of ${hashed.length} '
      'ThumbHashes in the first frame, tiles p50 '
      '${_p([...waits.values], 50)} ms p95 ${_p([...waits.values], 95)} ms',
    );
    result('folder-open', 'hashes_missing', missing * 1.0);
    if (timed) {
      result(
        'folder-open',
        'tiles_p95',
        waits.length == hashed.length ? _p([...waits.values], 95) : 10000,
      );
    }
  }

  /// Scrolls after the warm-up: no visible cell may go without an image for
  /// more than a frame.
  Future<void> warm() async {
    await _leastJanky(binding, result, 'folder-scroll', 'warm_janky', (
      _,
    ) async {
      await until(() => decoding == 0);
      view.controller.jumpTo(0);
      shown.clear();
      await until(() => allShown(view, pages, shown));
      return await _frames(() => _scroll(view.controller));
    });
    await until(() => decoding == 0);
    await runs((run, frames, stages) {
      report('warm $run', stages);
      stdout.writeln('blank-cells: $_target warm $run $frames frames');
      if (timed) result('tile-latency', 'read_$run', _p(stages['read'], 95));
      if (run != 'fling') result('folder-scroll', 'blank_$run', frames * 1.0);
    });
  }

  /// A 256 px tile of [original], cold and warm, the fastest of ten each.
  Future<void> tile(String original) async {
    final never = Completer<void>().future;
    var (decoded, read) = (double.infinity, double.infinity);
    for (var run = 0; run < 10; run++) {
      final item = ThumbnailItem('tile-$run', Uri.file(original));
      final watch = Stopwatch()..start();
      // The first decoder that takes it: FFmpeg's, where installed, does not.
      for (final decoder in pipeline.decoders) {
        if (await decoder(item, 256, never) != null) break;
      }
      decoded = min(decoded, watch.elapsedMicroseconds / 1000);
      await pipeline.warm(item, 256);
      watch.reset();
      (await pipeline.load(item, 256, Tile())).dispose();
      read = min(read, watch.elapsedMicroseconds / 1000);
    }
    stdout.writeln('thumbnail-tile: $_target cold $decoded ms, warm $read ms');
    if (timed) {
      result('thumbnail-tile', 'cold', decoded);
      result('thumbnail-tile', 'warm', read);
    }
  }
}

/// A percentile by nearest rank, 0 of nothing.
double _p(List<double>? values, int percentile) {
  if (values == null || values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[(percentile * sorted.length / 100).ceil() - 1];
}

/// Writes a 12 MP JPEG with a camera's noise and a 160 px EXIF thumbnail to
/// [path], on an isolate.
Future<String> _photo(String path, int k) => Isolate.run(() {
  final image = img.Image(width: 4000, height: 3000);
  for (final p in image) {
    final noise = (p.x * 73856093 ^ p.y * 19349663 ^ k * 83492791) & 31;
    p
      ..r = (p.x ~/ 16 + k * 37 + noise) % 256
      ..g = (p.y ~/ 12 + k * 91 + noise) % 256
      ..b = ((p.x + p.y) ~/ 28 + noise) % 256;
  }
  final thumbnail = img.encodeJpg(img.copyResize(image, width: 160));
  // A little-endian TIFF: an empty IFD0, then IFD1 pointing to the thumbnail.
  final tiff = [
    ...[0x49, 0x49, 0x2a, 0, 8, 0, 0, 0, 0, 0, 14, 0, 0, 0, 2, 0],
    ..._long(0x0201, 44),
    ..._long(0x0202, thumbnail.length),
    ...[0, 0, 0, 0],
    ...thumbnail,
  ];
  final app1 = [...'Exif'.codeUnits, 0, 0, ...tiff];
  File(path).writeAsBytesSync([
    ...[
      0xff,
      0xd8,
      0xff,
      0xe1,
      (app1.length + 2) >> 8,
      (app1.length + 2) & 255,
    ],
    ...app1,
    ...img.encodeJpg(image, quality: 85).skip(2),
  ]);
  return path;
});

// A little-endian TIFF entry of one LONG.
List<int> _long(int tag, int value) => [
  ...[tag & 255, tag >> 8, 4, 0, 1, 0, 0, 0],
  for (var i = 0; i < 4; i++) value >> (8 * i) & 255,
];
