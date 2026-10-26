import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/feature_flags.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib_data/photolib_data.dart';

import '../../support/pump_app.dart';
import '../../support/viewer.dart';

void main() {
  late Replica db;
  late _Pipeline pipeline;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    pipeline = _Pipeline();
  });
  tearDown(() => db.close());

  // Four photos, newest first: 1.jpg and 2.jpg on May 3, then 3.jpg, 4.jpg.
  Future<void> add({String source = 'folder'}) async {
    await db.delete(db.localAsset).go();
    for (final (i, taken) in [
      '2024-05-03T12:00:00',
      '2024-05-03T11:00:00',
      '2024-05-01T12:00:00',
      '2024-04-30T12:00:00',
    ].indexed) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = i + 1,
              source: source,
              volume: Value(source == 'folder' ? '/p' : 'external_primary'),
              sourceId: '${i + 1}',
              path: Value(source == 'folder' ? '${i + 1}.jpg' : 'DCIM/'),
              name: Value('${i + 1}.jpg'),
              mime: const Value('image/jpeg'),
              size: 2512000,
              mtime: 0,
              takenLocal: Value(taken),
              takenUtc: Value(
                DateTime.parse('${taken}Z').millisecondsSinceEpoch,
              ),
              width: const Value(4000),
              height: const Value(3000),
              extracted: const Value(1),
              timeSource: const Value('exif:DateTimeOriginal'),
              timeConfidence: const Value(95),
              timePrecision: const Value('second'),
              make: const Value('Canon'),
              model: const Value('EOS R5'),
              lat: const Value(48.85836),
              lon: const Value(2.29448),
            ),
          );
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double dpr = 1,
    String source = 'folder',
    Locale? locale,
    Future<Regions?> Function(ThumbnailItem)? regions,
  }) async {
    await add(source: source);
    await pumpApp(
      tester,
      replica: (_) => db,
      size: size,
      dpr: dpr,
      locales: [?locale],
      overrides: [
        thumbnailPipelineProvider.overrideWith((ref) async => pipeline),
        regionsProvider.overrideWithValue(regions ?? (_) async => null),
        if (locale != null)
          featureFlagsProvider.overrideWithValue(
            FeatureFlags.parse('pseudoLocales'),
          ),
      ],
    );
  }

  /// Taps the [n]th photo of May 3 in the timeline, which starts the open.
  Future<void> tap(WidgetTester tester, int n) async {
    final semantics = tester.ensureSemantics();
    await tester.pump();
    // Right to left, marks surround the numbers.
    tester.semantics.tap(
      find.semantics.byLabel(RegExp('${n + 1}\u200f? of \u200f?2\$')),
    );
    semantics.dispose();
  }

  /// Opens the [n]th photo of May 3 from the timeline.
  Future<void> open(WidgetTester tester, int n) async {
    await tap(tester, n);
    await tester.pumpAndSettle();
  }

  String at(int year, int month, int day, [int hour = 12]) =>
      DateFormat.yMMMd('en').add_jm().format(DateTime(year, month, day, hour));

  // The date and time of the item shown, of those [add] adds.
  String shown(WidgetTester tester) => [
    at(2024, 5, 3),
    at(2024, 5, 3, 11),
    at(2024, 5, 1),
    at(2024, 4, 30),
  ][tester.widget<ViewerPage>(find.byType(ViewerPage)).position.value];

  // Runs the bar's action [label], from ⋮ when it is not pinned.
  Future<void> act(WidgetTester tester, String label) async {
    if (find.byTooltip(label).evaluate().isEmpty) {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    } else {
      await tester.tap(find.byTooltip(label));
    }
    await tester.pumpAndSettle();
  }

  double zoom(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer).hitTestable())
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('swipes between items, their neighbours preloaded at screen '
      'size', (tester) async {
    final heard = <LogRecord>[];
    addTearDown(Log.records.listen(heard.add).cancel);
    await pump(tester);
    await open(tester, 1);
    expect(shown(tester), at(2024, 5, 3, 11));
    final opened = heard.singleWhere((r) => r.message == 'viewer opened');
    expect(opened.logger, 'photolib.viewer');
    expect(opened.fields, containsPair('position', 1));
    expect(heard.where((r) => r.message == 'screen-size image'), hasLength(3));
    // A phone preloads one on each side, at its short side, 400 px here.
    expect(pipeline.at(512), unorderedEquals(['1.jpg', '2.jpg', '3.jpg']));

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(shown(tester), at(2024, 5, 1));
    expect(pipeline.at(512), contains('4.jpg'));
    expect(pipeline.live, 3, reason: '1.jpg is out of reach and disposed');

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(shown(tester), at(2024, 5, 3, 11));
    await unmount(tester);
  });

  testWidgets('a double tap zooms in and out; zoomed, swipes pan instead of '
      'turning the page or closing', (tester) async {
    await pump(tester);
    await open(tester, 0);
    final centre = tester.getCenter(find.byType(PageView));
    Future<void> doubleTap() async {
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(zoom(tester), greaterThan(1.5));
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(shown(tester), at(2024, 5, 3));
    await tester.drag(find.byType(PageView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsOneWidget);

    await doubleTap();
    expect(zoom(tester), 1);
    await tester.drag(find.byType(PageView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('opens the regions of an item once zoomed, then zooms into '
      'tiles to 2 device pixels per image pixel', (tester) async {
    final regions = <_Regions>[];
    await pump(
      tester,
      regions: (item) async => (regions..add(_Regions())).last,
    );
    await open(tester, 0);
    expect(regions, isEmpty, reason: 'nothing read while it fits');
    await tester.pressKey(LogicalKeyboardKey.equal, character: '+');
    final deep = tester.widget<DeepZoom>(find.byType(DeepZoom).hitTestable());
    expect(deep.regions, regions.single);
    expect(deep.size, const Size(4000, 3000));
    // 4000 px across 400: 10× shows 1 image px per device px.
    expect(
      tester
          .widget<InteractiveViewer>(
            find.byType(InteractiveViewer).hitTestable(),
          )
          .maxScale,
      20,
    );
    await tester.pumpWidget(const SizedBox());
    expect(regions.single.closed, isTrue);
    await tester.pump(Duration.zero);
  });

  testWidgets('the keyboard turns pages, zooms, shows the info and closes', (
    tester,
  ) async {
    await pump(tester);
    await open(tester, 1);
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    expect(shown(tester), at(2024, 5, 1));
    await tester.pressKey(LogicalKeyboardKey.arrowLeft);
    expect(shown(tester), at(2024, 5, 3, 11));
    await tester.pressKey(LogicalKeyboardKey.end);
    expect(shown(tester), at(2024, 4, 30));
    await tester.pressKey(LogicalKeyboardKey.home);
    expect(shown(tester), at(2024, 5, 3));

    await tester.pressKey(LogicalKeyboardKey.equal, character: '+');
    expect(zoom(tester), greaterThan(1));
    await tester.pressKey(LogicalKeyboardKey.minus, character: '-');
    expect(zoom(tester), 1);

    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    await tester.pressKey(LogicalKeyboardKey.equal, character: '+');
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    expect(find.byTooltip('Why this date?'), findsOneWidget);
    expect(shown(tester), at(2024, 5, 3, 11), reason: 'the same item');
    expect(zoom(tester), greaterThan(1), reason: 'as zoomed as it was');
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    expect(find.byTooltip('Why this date?'), findsNothing);
    expect(shown(tester), at(2024, 5, 3, 11));

    await tester.pressKey(LogicalKeyboardKey.escape);
    expect(find.byType(ViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('right to left, the left arrow shows the next item', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('ar', 'XB'));
    await open(tester, 1);
    expect(pipeline.at(512), isNot(contains('4.jpg')));
    await tester.pressKey(LogicalKeyboardKey.arrowLeft);
    expect(pipeline.at(512), contains('4.jpg'));
    await unmount(tester);
  });

  testWidgets('a filmstrip shows on wide windows, not on phones, and jumps '
      'to the item tapped', (tester) async {
    await pump(tester, size: const Size(1000, 700));
    await open(tester, 0);
    final strip = find.byKey(const ValueKey('filmstrip'));
    expect(strip, findsOneWidget);
    await tester.tap(
      find.descendant(of: strip, matching: find.byType(InkWell)).at(3),
    );
    await tester.pumpAndSettle();
    expect(shown(tester), at(2024, 4, 30));
    await tester.tap(find.byTooltip('Filmstrip'));
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    await tester.pressKey(LogicalKeyboardKey.keyF, character: 'f');
    expect(strip, findsOneWidget);
    await unmount(tester);

    await pump(tester);
    await open(tester, 0);
    expect(find.byKey(const ValueKey('filmstrip')), findsNothing);
    await unmount(tester);
  });

  testWidgets('pages over a window of items around the one shown, so that a '
      'large folder at a fractional width lays out without errors', (
    tester,
  ) async {
    final position = await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(1140.4417, 800),
      count: 1889,
      at: 1096,
    );
    final pager = find.byType(PageView);
    int window() =>
        tester.widget<PageView>(pager).childrenDelegate.estimatedChildCount!;
    expect(window(), lessThan(200));
    for (var i = 0; i < 30; i++) {
      await tester.fling(pager, const Offset(-600, 0), 2000);
      await tester.pumpAndSettle();
    }
    expect(position.value, 1126);
    expect(window(), lessThan(200));
    expect(
      tester.widget<PageView>(pager).controller!.page,
      inInclusiveRange(window() / 4, window() * 3 / 4),
      reason: 're-centred on the item shown',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(position.value, 1888);
    await tester.fling(pager, const Offset(600, 0), 2000);
    await tester.pumpAndSettle();
    expect(position.value, 1887);
    await unmount(tester);
  });

  testWidgets('the actions run from the bar or its menu at any width', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/viewer'),
      // The head of each item, which says whether it animates, aside.
      (call) async => call.method == 'read' ? null : calls.add(call.method),
    );
    for (final width in [600.0, 400.0]) {
      calls.clear();
      await pump(tester, size: Size(width, 800), source: 'mediastore');
      await open(tester, 0);
      await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
      final strip = find.byKey(const ValueKey('filmstrip'));
      final stripShown = strip.evaluate().isNotEmpty;
      for (final action in ['Share', 'Copy', 'Rotate', 'Filmstrip', 'Info']) {
        await act(tester, action);
      }
      expect(calls, ['share', 'copy'], reason: '$width');
      expect(strip.evaluate().isNotEmpty, !stripShown);
      expect(find.byTooltip('Why this date?'), findsNothing);
      // Closing with the info shown shrinks the page into its cell.
      await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await unmount(tester);
    }
  });

  testWidgets('a page turn rebuilds only the two cells whose outline changes, '
      'and recentres the filmstrip near its edge without rebuilding it', (
    tester,
  ) async {
    final position = await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(1000, 700),
      count: 40,
      at: 20,
      thumbnails: Thumbnails((_, _, _) => Completer<ui.Image>().future),
    );
    final strip = find.byKey(const ValueKey('filmstrip'));
    double offset() => tester.widget<ListView>(strip).controller!.offset;
    final before = offset();
    // Elements already built that build again.
    final built = {...find.byType(ThumbnailAt).evaluate(), ...strip.evaluate()};
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) {
      if (built.contains(element)) rebuilt.add(element.widget);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    expect(position.value, 21);
    expect(rebuilt.whereType<ThumbnailAt>().map((c) => c.asset), [20, 21]);
    expect(offset(), before, reason: 'the item is far from the edges');
    for (var i = 0; i < 4; i++) {
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
    }
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt.whereType<ListView>(), isEmpty);
    expect(offset(), before + 5 * 64);
    await unmount(tester);
  });

  testWidgets('opened from the grid, the bar and the filmstrip fade in with '
      'the flight, the strip painting every tile the grid holds from its '
      'first frame, and decoding nothing', (tester) async {
    // A desktop's Retina display: the grid's tiles are at 512 px.
    await pump(tester, size: const Size(1000, 700), dpr: 2);
    final grid = pipeline.loads.length;
    await tap(tester, 0);
    final strip = find.byKey(const ValueKey('filmstrip'), skipOffstage: false);
    final bar = find.byKey(const ValueKey('viewer-close'), skipOffstage: false);
    final tiles = find.descendant(
      of: strip,
      matching: find.byType(RawImage, skipOffstage: false),
    );
    // Its first build, offstage while the route measures its heroes; the
    // first frame shown; half way; the end.
    const frame = Duration(milliseconds: 16);
    for (final (step, wait) in [
      ('0 %', Duration.zero),
      ('first frame', frame),
      ('50 %', Motion.medium ~/ 2 - frame),
      ('100 %', Motion.medium ~/ 2),
    ]) {
      await tester.pump(wait);
      expect(bar, findsOneWidget, reason: step);
      expect(tiles, findsNWidgets(4), reason: step);
      expect(
        [for (final tile in tester.widgetList<RawImage>(tiles)) tile.image],
        everyElement(isNotNull),
        reason: step,
      );
      if (step == '0 %') continue;
      for (final chrome in [bar, strip]) {
        expect(
          opacity(tester, chrome),
          step == '100 %' ? 1 : inExclusiveRange(0, 1),
          reason: step,
        );
      }
    }
    await tester.pumpAndSettle();
    expect(
      pipeline.loads.skip(grid).where((load) => load.$2 < 1024),
      isEmpty,
      reason: 'only the screen-size images',
    );
    await unmount(tester);
  });

  testWidgets('a cell with no tile in memory shows a placeholder, and asks '
      "for the grid's tier, which the disk cache holds, once the photo shown "
      'is sharp', (tester) async {
    final asked = <(String, int)>[];
    final thumbnails = Thumbnails((item, tier, _) async {
      asked.add(((item as ThumbnailItem).key, tier));
      return _image(40, 30);
    });
    // The grid's cells last asked for 512 px.
    void cell() {}
    final item = ThumbnailItem('grid', Uri());
    thumbnails
      ..want(item, 512, cell, at: 0)
      ..unwant(item, 512, cell);
    pipeline.held = Completer();
    await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(1000, 700),
      thumbnails: thumbnails,
    );
    final strip = find.byKey(const ValueKey('filmstrip'));
    expect(
      find.descendant(of: strip, matching: find.byIcon(Icons.image_outlined)),
      findsNWidgets(4),
    );
    expect(asked, isEmpty, reason: 'behind the photo shown');
    pipeline.held!.complete();
    await tester.pumpAndSettle();
    expect(asked, unorderedEquals([for (var p = 0; p < 4; p++) ('$p', 512)]));
    expect(
      find.descendant(of: strip, matching: find.byIcon(Icons.image_outlined)),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('a slow decode keeps the filmstrip responsive', (tester) async {
    // One slow decode holds one of four slots, whatever cores this machine
    // has.
    final thumbnails = Thumbnails(
      concurrency: 4,
      (item, tier, _) async => (item as ThumbnailItem).key == '21'
          ? await Future.delayed(
              const Duration(seconds: 5),
              () => _image(40, 30),
            )
          : _image(40, 30),
    );
    final position = await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(1000, 700),
      count: 40,
      at: 20,
      thumbnails: thumbnails,
    );
    final strip = find.byKey(const ValueKey('filmstrip'));
    bool painted(int at) => find
        .descendant(
          of: find.byWidgetPredicate((w) => w is ThumbnailAt && w.asset == at),
          matching: find.byType(RawImage),
        )
        .evaluate()
        .isNotEmpty;
    expect(painted(21), isFalse, reason: 'slow');
    expect(painted(22), isTrue);
    await tester.tap(
      find.descendant(
        of: strip,
        matching: find.byWidgetPredicate(
          (w) => w is ThumbnailAt && w.asset == 24,
        ),
      ),
    );
    await tester.pump();
    expect(position.value, 24);
    await tester.pumpAndSettle();
    expect(painted(21), isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(painted(21), isTrue);
    await unmount(tester);
  });

  testWidgets("the filmstrip's cells decode however far they are from the "
      "grid's", (tester) async {
    // The grid shows three large cells at the top of the library.
    final thumbnails = Thumbnails((_, _, _) async => _image(40, 30))
      ..focus(0, 2, forward: true);
    await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(1000, 700),
      count: 40,
      at: 20,
      thumbnails: thumbnails,
    );
    final strip = find.byKey(const ValueKey('filmstrip'));
    final cells = find.descendant(
      of: strip,
      matching: find.byType(ThumbnailAt),
    );
    expect(cells, findsAtLeast(15));
    expect(
      find.descendant(of: strip, matching: find.byType(RawImage)),
      findsNWidgets(cells.evaluate().length),
    );
    await unmount(tester);
  });

  testWidgets('a finger on a cell starts its screen-size decode, which the '
      'viewer it opens takes over', (tester) async {
    await pump(tester);
    final view = tester.state<TimelineViewState>(find.byType(TimelineView));
    final finger = await tester.startGesture(view.cellOf(0).center);
    await tester.pump();
    expect(pipeline.at(512), ['1.jpg'], reason: 'while the finger is down');
    await finger.up();
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsOneWidget);
    expect(pipeline.at(512).where((f) => f == '1.jpg'), hasLength(1));
    await unmount(tester);
  });

  testWidgets('a jump far away cancels the loads of the items it leaves', (
    tester,
  ) async {
    pipeline.held = Completer();
    await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(400, 800),
      count: 40,
      at: 20,
      thumbnails: Thumbnails((_, _, _) => Completer<ui.Image>().future),
    );
    final near = [
      for (final p in [19, 20, 21]) pipeline.tiles['$p.jpg']!,
    ];
    expect(near.map((t) => t.isCancelled), everyElement(isFalse));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(near.map((t) => t.isCancelled), everyElement(isTrue));
    expect(pipeline.tiles['39.jpg']!.isCancelled, isFalse);
    await unmount(tester);
  });

  testWidgets('an item with nothing to show yet gets a progress ring, only '
      'after 400 ms', (tester) async {
    final never = Completer<ui.Image>().future;
    pipeline.held = Completer();
    await pumpViewer(
      tester,
      pipeline: pipeline,
      size: const Size(400, 800),
      thumbnails: Thumbnails((_, _, _) => never),
    );
    final ring = find.byKey(const ValueKey('viewer-progress'));
    expect(ring, findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ring.hitTestable(), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a video with no poster shows its mark, in the photo and the '
      'filmstrip, each saying why', (tester) async {
    const why = 'macos: refused 0.jpg: AVFoundationErrorDomain -11829';
    pipeline.failing['0.jpg'] = const NoThumbnail(video: true, cause: why);
    await pumpViewer(tester, pipeline: pipeline, size: const Size(1000, 700));
    final strip = find.byKey(const ValueKey('filmstrip'));
    final marks = find.byTooltip(why);
    expect(marks, findsNWidgets(2));
    expect(find.descendant(of: strip, matching: marks), findsOneWidget);
    expect(
      find.descendant(
        of: marks,
        matching: find.byIcon(Icons.videocam_outlined),
      ),
      findsNWidgets(2),
    );
    await unmount(tester);
  });

  testWidgets('swiped up, the info lists with no heading the date with its '
      'why inline, a one-line file row that opens the path, the camera, the '
      'place behind an agreement to load maps, where it lives and its '
      'albums', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, size: const Size(1000, 800));
    await open(tester, 0);
    expect(find.byTooltip('Why this date?'), findsNothing);
    await tester.fling(find.byType(PageView), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsNothing);
    final rows = [
      at(2024, 5, 3),
      '1.jpg',
      '12 MP · 4,000 × 3,000 · 2.5 MB',
      'Canon EOS R5',
      '48.85836, 2.29448',
      'Map tiles come from the internet and show which area you look at',
      'On this device',
      'Albums',
      'Not in any album',
      'View all metadata',
    ];
    final tops = [
      for (final text in rows) tester.getTopLeft(find.text(text)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()), reason: '$rows');
    expect(find.textContaining('/p'), findsNothing, reason: 'no path');
    await tester.tap(find.byTooltip('Why this date?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Read in the file, as exif:DateTimeOriginal\nConfidence: 95%'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Map of where it was taken'), findsNothing);
    await tester.tap(find.text('Show map'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Map of where it was taken'), findsOneWidget);
    await tester.tap(find.text('1.jpg'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('info-path')))
          .data,
      '\u2066/p/1.jpg\u2069',
    );
    expect(find.text('Copy path'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    // A swipe down hides it again.
    await tester.fling(find.byType(PageView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('View all metadata'), findsNothing);
    expect(find.byType(ViewerPage), findsOneWidget);
    await unmount(tester);
    semantics.dispose();
  });

  testWidgets('on Android an item is shared or copied by its MediaStore URI', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/viewer'),
      (call) async {
        if (call.method != 'read') calls.add(call);
        return null;
      },
    );
    // Wide enough for the whole bar, which a phone puts partly in its menu.
    await pump(tester, size: const Size(1000, 700), source: 'mediastore');
    await open(tester, 0);
    await act(tester, 'Share');
    await act(tester, 'Copy');
    expect(
      [
        for (final c in calls) [c.method, c.arguments],
      ],
      [
        [
          'share',
          [
            ['content://media/external_primary/images/media/1'],
            'image/jpeg',
          ],
        ],
        ['copy', 'content://media/external_primary/images/media/1'],
      ],
    );
    await unmount(tester);

    await pump(tester, size: const Size(1000, 700));
    await open(tester, 0);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsNothing, reason: 'a folder file');
    await unmount(tester);
  });
}

ui.Image _image(int width, int height) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
  return recorder.endRecording().toImageSync(width, height);
}

/// Grey images, by file name and tier, counting the screen-size ones not yet
/// disposed; those wait for [held] when set; none for the files [failing].
class _Pipeline extends ThumbnailPipeline {
  final loads = <(String, int)>[];
  final _given = <ui.Image>[];
  Completer<void>? held;
  final failing = <String, NoThumbnail>{};
  // The token of each load, by file.
  final tiles = <String, Tile>{};

  int get live => _given.where((i) => !i.debugDisposed).length;

  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async {
    loads.add((item.uri.pathSegments.last, tier));
    tiles[item.uri.pathSegments.last] = tile;
    if (tier >= 512) await held?.future;
    if (failing[item.uri.pathSegments.last] case final error?) throw error;
    final image = _image(40, 30);
    if (tier >= 512) _given.add(image);
    return image;
  }

  /// The files loaded at [tier].
  List<String> at(int tier) => [
    for (final (file, t) in loads)
      if (t == tier) file,
  ];
}

class _Regions implements Regions {
  bool closed = false;

  @override
  Size get size => const Size(4000, 3000);

  @override
  Future<ui.Image> decode(Rect region, int sample) async => _image(1, 1);

  @override
  void close() => closed = true;
}
