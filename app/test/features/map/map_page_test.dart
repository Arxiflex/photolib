@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/map/map_kernel.dart';
import 'package:photolib/features/map/map_logic.dart';
import 'package:photolib/features/map/map_state.dart';
import 'package:photolib/features/map/tracks.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../../support/pump_app.dart';
import '../../support/viewer.dart';

/// A tile source with no network: every tile is a blank pixel.
class _NoTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgY'
          'GD4DwABBAEAH33EvQAAAABJRU5ErkJggg==',
        ),
      );
}

/// Located MediaStore item [n], taken [day] days after the epoch.
LocalAssetCompanion _item(
  int n,
  double? lat,
  double? lon, {
  int day = 1,
  int hours = 0,
}) => LocalAssetCompanion.insert(
  id: Uint8List(16)..[15] = n,
  source: 'mediastore',
  volume: const Value('external_primary'),
  sourceId: '$n',
  size: 1,
  mtime: n,
  path: const Value('DCIM/Camera/'),
  name: Value('IMG_$n.jpg'),
  mime: const Value('image/jpeg'),
  lat: Value(lat),
  lon: Value(lon),
  takenUtc: Value((day * 86400 + hours * 3600) * 1000),
);

void main() {
  late Replica db;
  late KernelKeyring keyring;
  SemanticsHandle? semantics;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    keyring = Kernel().keyring();
  });
  tearDown(() => db.close());

  Finder photos([String? n]) =>
      find.bySemanticsLabel(n == null ? RegExp('^Photos: ') : 'Photos: $n');

  Future<void> openMap(
    WidgetTester tester,
    List<LocalAssetCompanion> items, {
    bool tiles = false,
    List<Override> overrides = const [],
  }) async {
    semantics = tester.ensureSemantics();
    await db.batch((b) => b.insertAll(db.localAsset, items));
    await pumpApp(
      tester,
      replica: (_) => db,
      settings: MemoryStore(tiles ? '{"maps":true}' : null),
      overrides: [
        thumbnailPipelineProvider.overrideWith((ref) async => Grey()),
        mapTileProviderProvider.overrideWithValue(_NoTiles()),
        mapKernelOpenerProvider.overrideWithValue(
          () async => MapKernel(
            (m, r) async => keyring.call(m, r),
            () async => keyring.close(),
          ),
        ),
        ...overrides,
      ],
    );
    await tester.tapAndSettle(find.text('Collections'));
    await tester.ensureVisible(find.text('Map'));
    await tester.tap(find.text('Map'));
    // The page slides in.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Pumps frames, as time passes, until [n] markers show.
  Future<void> shows(WidgetTester tester, int n) => tester.pumpUntil(
    () => photos().evaluate().length == n,
    within: const Duration(seconds: 10),
    step: const Duration(milliseconds: 16),
  );

  Future<void> idle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts the app, so that drift closes its queries on the test's clock.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    semantics?.dispose();
  }

  testWidgets('a library with no located photo says so', (tester) async {
    await openMap(tester, [_item(1, null, null)]);
    await tester.pumpUntil(
      () => find.text('No photos with a place yet').evaluate().isNotEmpty,
    );
    await unmount(tester);
  });

  testWidgets('nearby photos are one marker with their count, far ones '
      'another', (tester) async {
    await openMap(tester, [
      _item(1, 48.85, 2.35),
      _item(2, 48.86, 2.36),
      _item(3, -33.87, 151.21),
    ]);
    await shows(tester, 2);
    expect(photos('2'), findsOneWidget);
    expect(photos('1'), findsOneWidget);
    await unmount(tester);
  });

  final trip = [
    _item(1, 48.85, 2.35),
    _item(2, 48.86, 2.36, day: 5),
    _item(3, -33.87, 151.21, day: 3),
  ];

  testWidgets('a cluster opens by zooming in, until its photos stand apart', (
    tester,
  ) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    for (var taps = 0; photos('2').evaluate().isNotEmpty; taps++) {
      expect(taps, lessThan(8), reason: 'a tap zooms in by two levels');
      await tester.tap(photos('2'));
      await tester.pump(const Duration(milliseconds: 500));
      await idle(tester);
    }
    expect(photos('1'), findsNWidgets(2));
    await unmount(tester);
  });

  testWidgets('a single photo opens in the viewer', (tester) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    await tester.tap(photos('1'));
    await tester.pumpUntil(
      () => find.byType(ViewerPage).evaluate().isNotEmpty,
      step: const Duration(milliseconds: 16),
    );
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('split view shows the photos of the area under the map', (
    tester,
  ) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    await tester.tap(find.byTooltip('Show photos under the map'));
    await tester.pumpUntil(
      () => find.text('Photos: 3').evaluate().isNotEmpty,
      step: const Duration(milliseconds: 16),
    );
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byTooltip('Show photos under the map'));
    await idle(tester);
    expect(find.byType(GridView), findsNothing);
    await unmount(tester);
  });

  testWidgets('the time range slider limits the map to what was taken in it', (
    tester,
  ) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    final slider = find.byType(RangeSlider);
    final box = tester.getRect(slider);
    // The start thumb to the middle: the photos of day 1 are out.
    await tester.dragFrom(
      box.centerLeft + const Offset(24, 0),
      Offset(box.width * 0.45, 0),
    );
    await idle(tester);
    expect(photos('2'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a lasso keeps the photos inside the loop', (tester) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    final paris = tester.getCenter(photos('2'));
    await tester.tap(find.byTooltip('Select by drawing around photos'));
    await tester.pump();
    final gesture = await tester.startGesture(paris + const Offset(-24, -24));
    for (final d in const [
      Offset(24, -24),
      Offset(24, 24),
      Offset(-24, 24),
      Offset(-24, -22),
    ]) {
      await gesture.moveTo(paris + d);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await idle(tester);
    expect(photos('2'), findsOneWidget);
    expect(photos('1'), findsNothing);
    expect(find.byTooltip('Clear the selection'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear the selection'));
    await idle(tester);
    expect(photos('1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the heatmap paints over the map and goes again', (tester) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    bool heat() => find
        .byWidgetPredicate(
          (w) =>
              w is CustomPaint && '${w.painter.runtimeType}' == '_HeatPainter',
        )
        .evaluate()
        .isNotEmpty;
    expect(heat(), isFalse);
    await tester.tap(find.byTooltip('Heatmap'));
    await tester.pump();
    expect(heat(), isTrue);
    await tester.tap(find.byTooltip('Heatmap'));
    await tester.pump();
    expect(heat(), isFalse);
    await unmount(tester);
  });

  testWidgets('the background loads only after the user agreed', (
    tester,
  ) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.textContaining('tile.openstreetmap.org'), findsOneWidget);
    await tester.tap(find.text('Show the background'));
    await idle(tester);
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.textContaining('tile.openstreetmap.org'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a GPX track is drawn in its activity colour', (tester) async {
    final tracks = parseGpx(
      '<gpx><trk><type>cycling</type><trkseg>'
      '<trkpt lat="48.8" lon="2.3"/> <trkpt lat="48.9" lon="2.4"/> '
      '</trkseg></trk></gpx>',
    );
    await openMap(
      tester,
      trip,
      overrides: [trackPickerProvider.overrideWithValue(() async => tracks)],
    );
    await shows(tester, 2);
    await tester.tap(find.byTooltip('Add a GPX track'));
    await idle(tester);
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(layer.polylines.single.color, Activity.cycle.color);
    await unmount(tester);
  });

  testWidgets('a file without tracks says so', (tester) async {
    await openMap(
      tester,
      trip,
      overrides: [trackPickerProvider.overrideWithValue(() async => const [])],
    );
    await shows(tester, 2);
    await tester.tap(find.byTooltip('Add a GPX track'));
    await idle(tester);
    expect(find.text('That file has no GPX tracks'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"Search this area" searches the library in what the map shows', (
    tester,
  ) async {
    await openMap(tester, trip);
    await shows(tester, 2);
    // Zoom to Paris: the lasso around it is the area.
    final paris = tester.getCenter(photos('2'));
    await tester.tap(find.byTooltip('Select by drawing around photos'));
    await tester.pump();
    final gesture = await tester.startGesture(paris + const Offset(-24, -24));
    for (final d in const [
      Offset(24, -24),
      Offset(24, 24),
      Offset(-24, 24),
      Offset(-24, -22),
    ]) {
      await gesture.moveTo(paris + d);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await idle(tester);
    await tester.tap(find.byTooltip('Search this area'));
    await idle(tester);
    expect(find.text('Map area'), findsOneWidget);
    await tester.pumpUntil(
      () => find.text('2 items').evaluate().isNotEmpty,
      step: const Duration(milliseconds: 16),
    );
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(find.text('IMG_2.jpg'), findsOneWidget);
    expect(find.text('IMG_3.jpg'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a photo dated 2100 is on the map and the slider reaches it', (
    tester,
  ) async {
    await openMap(tester, [
      _item(1, 48.85, 2.35, day: 47482),
      _item(2, 38.72, -9.14),
    ]);
    await shows(tester, 2);
    final slider = find.byType(RangeSlider);
    final box = tester.getRect(slider);
    // The start thumb to the end: only the latest photo is left.
    await tester.dragFrom(
      box.centerLeft + const Offset(24, 0),
      Offset(box.width * 0.9, 0),
    );
    await idle(tester);
    expect(photos('1'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('trips draw a line through the photos taken within hours of '
      'each other', (tester) async {
    await openMap(tester, [
      _item(1, 48.85, 2.35),
      _item(2, 48.90, 2.40, hours: 1),
      _item(3, 48.95, 2.45, hours: 2),
      _item(4, -33.87, 151.21, day: 20),
    ]);
    await shows(tester, 2);
    List<Polyline> lines() => tester
        .widgetList<PolylineLayer>(find.byType(PolylineLayer))
        .expand((l) => l.polylines)
        .toList();
    expect(lines(), isEmpty);
    await tester.tap(find.byTooltip('Trips'));
    await idle(tester);
    expect(lines(), hasLength(1));
    expect(lines().single.points, hasLength(3));
    await tester.tap(find.byTooltip('Trips'));
    await idle(tester);
    expect(lines(), isEmpty);
    await unmount(tester);
  });
}
