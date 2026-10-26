import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/desktop/file_drag.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/scrubber.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_players.dart';
import '../../support/pump_app.dart';

void main() {
  late Replica db;
  late Directory dir;
  final dragged = <Object?>[];
  // What the macOS runner says Finder opened with the app.
  List<String>? opened;
  setUp(() {
    opened = null;
    db = Replica(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('drag-');
    dragged.clear();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  /// The app over a library of three photos in /p, taken on one day, newest
  /// first; the runner takes file drags.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    List<Override> overrides = const [],
  }) async {
    for (var n = 1; n <= 3; n++) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = n,
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '$n',
              path: Value('$n.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: Value('2024-05-03T1${3 - n}:00:00'),
              takenUtc: Value(
                DateTime.utc(2024, 5, 3, 13 - n).millisecondsSinceEpoch,
              ),
            ),
          );
    }
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      fileDragChannel,
      (call) async => switch (call.method) {
        'drag' => dragged.add(call.arguments),
        _ => opened,
      },
    );
    await pumpApp(
      tester,
      size: size,
      replica: (_) => db,
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(),
        ),
        ...overrides,
      ],
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  // The centre of the timeline's [n]th cell.
  Offset cell(WidgetTester tester, int n) => tester
      .state<TimelineViewState>(find.byType(TimelineView))
      .cellOf(n)
      .center;

  Future<void> mouseDrag(WidgetTester tester, int n, Offset by) async {
    final mouse = await tester.startGesture(
      cell(tester, n),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(by);
    await mouse.up();
    await tester.pumpAndSettle();
  }

  // Drops [paths] on the window, as the runner does, and waits until the app
  // has taken them.
  Future<void> drop(WidgetTester tester, List<String> paths) async {
    var taken = false;
    unawaited(
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        fileDragChannel.name,
        fileDragChannel.codec.encodeMethodCall(MethodCall('dropped', paths)),
        (_) => taken = true,
      ),
    );
    await tester.pumpUntil(() => taken);
    await tester.pumpAndSettle();
  }

  testWidgets('a mouse dragging a cell out of the window drags its file', (
    tester,
  ) async {
    await pump(tester);
    await mouseDrag(tester, 1, const Offset(40, 0));

    expect(dragged, [
      ['/p/2.jpg'],
    ]);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a drag out selects nothing, however long it holds the mouse', (
    tester,
  ) async {
    await pump(tester);
    final mouse = await tester.startGesture(
      cell(tester, 1),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(1, 0));
    await mouse.moveBy(const Offset(1, 0));
    // The platform's drag has the mouse now: the window hears nothing more.
    await tester.pump(kLongPressTimeout * 2);
    await mouse.up();
    await tester.pumpAndSettle();

    expect(dragged, hasLength(1));
    expect(find.text('1 selected'), findsNothing);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a selected cell drags every selected file, in order', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPressAt(cell(tester, 2));
    await tester.tapAt(cell(tester, 0));
    await tester.pumpAndSettle();

    await mouseDrag(tester, 2, const Offset(0, 40));

    expect(dragged, [
      ['/p/1.jpg', '/p/3.jpg'],
    ]);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a click opens, and touch scrolls and selects: neither drags', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(cell(tester, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.dragFrom(cell(tester, 0), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(dragged, isEmpty);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a mouse dragging the photo the viewer shows drags its file; '
      'touch still swipes the viewer away', (tester) async {
    await pump(tester);
    await tester.tapAt(cell(tester, 1), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final viewer = tester.getCenter(find.byType(ViewerPage));

    final mouse = await tester.startGesture(
      viewer,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 60));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(dragged, [
      ['/p/2.jpg'],
    ]);
    expect(find.byType(ViewerPage), findsOneWidget);

    await tester.dragFrom(viewer, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsNothing);
    expect(dragged, hasLength(1));
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a mouse on the scrubber over a cell drags no file', (
    tester,
  ) async {
    await pump(tester, size: const Size(400, 800));
    final scrubber = tester.getRect(find.byType(TimelineScrubber));
    final mouse = await tester.startGesture(
      Offset(scrubber.center.dx, cell(tester, 2).dy),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, 40));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(dragged, isEmpty);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a folder dropped on the window joins the library', (
    tester,
  ) async {
    await pump(tester);
    await drop(tester, [dir.path]);

    final folders = await tester.runAsync(db.select(db.mediaSource).get);
    expect(folders!.map((f) => f.root), [dir.path]);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('a folder in one of the library says so', (tester) async {
    await pump(tester);
    await tester.runAsync(() => addFolder(db, dir.path));
    final inside = Directory('${dir.path}/2024')..createSync();
    await drop(tester, [inside.path]);

    expect(find.textContaining('already in the library'), findsOneWidget);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('dropped photos and videos open in the viewer, other files '
      'not', (tester) async {
    for (final name in ['a.JPG', 'b.mp4', 'notes.txt']) {
      File('${dir.path}/$name').writeAsStringSync(name);
    }
    await pump(tester);
    await drop(tester, [
      for (final name in ['a.JPG', 'notes.txt', 'b.mp4']) '${dir.path}/$name',
    ]);

    final viewer = tester.widget<ViewerPage>(find.byType(ViewerPage));
    expect(viewer.count, 2);
    final items = await tester.runAsync(() => viewer.pages.fetch(0, 2));
    expect(
      [for (final i in items!.cast<ThumbnailItem>()) (i.uri.path, i.video)],
      [('${dir.path}/a.JPG', false), ('${dir.path}/b.mp4', true)],
    );
    await unmount(tester);
  }, variant: desktop);

  // Not in the library, they have no row: what they say of themselves
  // decides (docs/10 §4.4).
  testWidgets('a photo sphere and a 360° video dropped on the window open '
      'projected, as their metadata says, and a flat photo flat', (
    tester,
  ) async {
    VideoPlayerPlatform.instance = FakePlayers();
    const corpus = '../testdata/corpus/files/compound';
    final files = [
      for (final f in [
        'pano/photosphere.jpg',
        'sphere/spherical-v2.mp4',
        'pano/PANO_20190101_120000.jpg',
      ])
        File('$corpus/$f').copySync('${dir.path}/${f.split('/').last}').path,
    ];
    await pump(tester);
    await drop(tester, files);

    final shown = <String>[];
    for (final type in [SpherePhoto, SphereVideo, ViewerPage]) {
      await tester.pumpUntil(() => find.byType(type).evaluate().isNotEmpty);
      shown.add(
        [
          '${find.byType(SpherePhoto).evaluate().length} sphere photo',
          '${find.byType(SphereVideo).evaluate().length} sphere video',
          '${find.byKey(const ValueKey('sphere-dial')).evaluate().length} dial',
        ].join(', '),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(shown, [
      '1 sphere photo, 0 sphere video, 1 dial',
      '0 sphere photo, 1 sphere video, 1 dial',
      '0 sphere photo, 0 sphere video, 0 dial',
    ]);
    await unmount(tester);
  }, variant: desktop);

  testWidgets('the photos and videos the app is opened with open in the '
      'viewer', (tester) async {
    for (final name in ['a.heic', 'b.mov']) {
      File('${dir.path}/$name').writeAsStringSync(name);
    }
    await pump(
      tester,
      overrides: [
        openedFilesProvider.overrideWithValue([
          for (final name in ['b.mov', 'a.heic']) '${dir.path}/$name',
        ]),
      ],
    );
    await tester.pumpUntil(() => find.byType(ViewerPage).evaluate().isNotEmpty);
    await tester.pumpAndSettle();

    final viewer = tester.widget<ViewerPage>(find.byType(ViewerPage));
    final items = await tester.runAsync(() => viewer.pages.fetch(0, 2));
    expect(
      [for (final i in items!.cast<ThumbnailItem>()) i.uri.path],
      ['${dir.path}/b.mov', '${dir.path}/a.heic'],
    );
    await unmount(tester);
  }, variant: desktop);

  testWidgets('on macOS the files Finder opened with the app open in the '
      'viewer', (tester) async {
    File('${dir.path}/a.jpg').writeAsStringSync('a');
    opened = ['${dir.path}/a.jpg'];
    await pump(tester);
    await tester.pumpUntil(() => find.byType(ViewerPage).evaluate().isNotEmpty);

    // Without macOS's runner the viewer never settles: no pumpAndSettle.
    expect(tester.widget<ViewerPage>(find.byType(ViewerPage)).count, 1);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('phones drag nothing out', (tester) async {
    await pump(tester);
    await mouseDrag(tester, 1, const Offset(40, 0));
    expect(dragged, isEmpty);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
