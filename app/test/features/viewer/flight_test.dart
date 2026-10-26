import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/regions.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib_data/photolib_data.dart';

import '../../support/pump_app.dart';
import '../../support/viewer.dart';
import '../../ui/motion_test.dart' show reduceMotion;

/// The viewer's open and close (docs/10 §4.1, M1-52): one flight of the photo
/// between its cell and its place, the rest of the page laid out as it ends
/// and fading in with it. Its photos are pure red and four times as wide as
/// high, so that the flight is found in the viewer's pixels.
void main() {
  late Replica db;
  late _Red pipeline;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    pipeline = _Red();
  });
  tearDown(() => db.close());

  /// The library of 1.jpg and 2.jpg on May 3, 3.jpg and 4.jpg before, in a
  /// window of [size].
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
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
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '${i + 1}',
              path: Value('${i + 1}.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: Value(taken),
              extracted: const Value(1),
            ),
          );
    }
    await pumpApp(
      tester,
      replica: (_) => db,
      size: size,
      overrides: [
        thumbnailPipelineProvider.overrideWith((ref) async => pipeline),
        regionsProvider.overrideWithValue((_) async => null),
      ],
    );
  }

  /// Taps the [n]th photo of May 3, which starts the open.
  Future<void> tap(WidgetTester tester, int n) async {
    final semantics = tester.ensureSemantics();
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel(RegExp('${n + 1} of 2\$')));
    semantics.dispose();
  }

  Future<void> open(WidgetTester tester, int n) async {
    await tap(tester, n);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  // As pixels show a rect.
  Matcher near(Rect rect) => rectMoreOrLessEquals(rect, epsilon: 1);

  Rect cell(WidgetTester tester, int asset) =>
      tester.state<TimelineViewState>(find.byType(TimelineView)).cellOf(asset);

  /// What the viewer paints between its bar and [bottom]: the bounds of its
  /// pure red pixels, its photo's, and how many others are opaque.
  Future<(Rect?, int)> painted(WidgetTester tester, double bottom) async {
    final top = tester
        .getRect(find.byKey(const ValueKey('viewer-close')))
        .bottom;
    final (width, rgba) = (await tester.runAsync(() async {
      final image = await captureImage(tester.element(find.byType(ViewerPage)));
      return (image.width, (await image.toByteData())!.buffer.asUint8List());
    }))!;
    Rect? red;
    var opaque = 0;
    for (var y = top.ceil(); y < bottom; y++) {
      for (var x = 0; x < width; x++) {
        final i = 4 * (y * width + x);
        if (rgba[i + 3] < 255) continue;
        if (rgba[i] > 250 && rgba[i + 1] < 5 && rgba[i + 2] < 5) {
          final pixel = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
          red = red?.expandToInclude(pixel) ?? pixel;
        } else {
          opaque++;
        }
      }
    }
    return (red, opaque);
  }

  testWidgets('the photo flies from its cell to its place above the '
      'filmstrip, cropped as the cell crops it, with no band around it, and '
      'lands there to the pixel', (tester) async {
    await pump(tester, size: const Size(1000, 700));
    final from = cell(tester, 0);
    await tap(tester, 0);
    await tester.pump();
    await tester.pump(Motion.medium ~/ 2);
    final strip = tester.getRect(find.byKey(const ValueKey('filmstrip')));
    // Fitted between the window's top and the strip.
    final to = Rect.fromCenter(
      center: Offset(500, strip.top / 2),
      width: 1000,
      height: 250,
    );
    final (half, opaque) = await painted(tester, strip.top);
    expect(half, near(Rect.lerp(from, to, Motion.curve.transform(0.5))!));
    expect(opaque, 0, reason: 'nothing opaque but the photo: no bands');
    await expectLater(
      find.byType(ViewerPage),
      matchesGoldenFile('goldens/viewer_flight_50.png'),
    );
    await tester.pump(Motion.medium ~/ 2 - const Duration(microseconds: 1));
    final (last, _) = await painted(tester, strip.top);
    await tester.pump(const Duration(milliseconds: 16));
    final (landed, _) = await painted(tester, strip.top);
    expect(landed, last, reason: 'no jump as it lands');
    expect(landed, near(to));
    await tester.pumpAndSettle();
    expect((await painted(tester, strip.top)).$1, landed);
    await unmount(tester);
  });

  testWidgets('closing mirrors the open: the bar and the strip fade out while '
      'the photo flies into the cell of the item shown, over the grid', (
    tester,
  ) async {
    await pump(tester, size: const Size(1000, 700));
    await open(tester, 0);
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    final strip = find.byKey(const ValueKey('filmstrip'));
    final bottom = tester.getRect(strip).top;
    final (shown, _) = await painted(tester, bottom);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(Motion.medium ~/ 2);
    final (half, opaque) = await painted(tester, bottom);
    expect(
      half,
      near(
        Rect.lerp(cell(tester, 1), shown, Motion.curve.flipped.transform(0.5))!,
      ),
    );
    expect(opaque, 0, reason: 'the grid shows through');
    for (final chrome in [strip, find.byKey(const ValueKey('viewer-close'))]) {
      expect(opacity(tester, chrome), inExclusiveRange(0, 1));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('a zoomed photo flies back from where it shows', (tester) async {
    await pump(tester, size: const Size(1000, 700));
    await open(tester, 0);
    await tester.pressKey(LogicalKeyboardKey.equal, character: '+');
    final bottom = tester.getRect(find.byKey(const ValueKey('filmstrip'))).top;
    final (zoomed, _) = await painted(tester, bottom);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const ValueKey('flight')), findsOneWidget);
    expect((await painted(tester, bottom)).$1, near(zoomed!));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a swipe down drives the same flight: half the height takes '
      'the photo half way into its cell, and letting go there closes the '
      'viewer, a shorter one springs back', (tester) async {
    await pump(tester);
    await open(tester, 0);
    final (shown, _) = await painted(tester, 800);
    final from = tester.getCenter(find.byType(PageView));
    final bar = find.byKey(const ValueKey('viewer-close'));

    // Past the drag's slop first, as a finger goes, then on: the drag
    // starts there.
    var drag = await tester.startGesture(from);
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(opacity(tester, bar), lessThan(1));
    await drag.up();
    await tester.pumpAndSettle();
    expect((await painted(tester, 800)).$1, shown);
    expect(opacity(tester, bar), 1);

    drag = await tester.startGesture(from);
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 400));
    await tester.pump();
    expect(
      (await painted(tester, 800)).$1,
      near(Rect.lerp(cell(tester, 0), shown, 0.5)!),
    );
    expect(opacity(tester, bar), closeTo(0.5, 0.01));
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('a slow drag down closes past 16 % of the height and springs '
      'back short of it; a flick of 0.5 px/ms closes', (tester) async {
    await pump(tester);
    Future<bool> drags(double dy, Duration time) async {
      await open(tester, 0);
      await tester.timedDragFrom(
        tester.getCenter(find.byType(PageView)),
        Offset(0, dy),
        time,
      );
      await tester.pumpAndSettle();
      final closed = find.byType(ViewerPage).evaluate().isEmpty;
      if (!closed) await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      return closed;
    }

    // 800 high: 16 % is 128 px past the drag's slop, slowly; then a flick
    // of 0.3 px/ms and one of 0.6.
    expect(await drags(130, const Duration(seconds: 2)), isFalse);
    expect(await drags(170, const Duration(seconds: 2)), isTrue);
    expect(await drags(60, const Duration(milliseconds: 200)), isFalse);
    expect(await drags(72, const Duration(milliseconds: 120)), isTrue);
    await unmount(tester);
  });

  testWidgets("Android's back gesture drives the same flight by its "
      'progress, and closes it once committed', (tester) async {
    await pump(tester);
    await open(tester, 0);
    final (shown, _) = await painted(tester, 800);
    Future<void> say(String method, [double? progress]) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, {
              'touchOffset': const [5.0, 300.0],
              'progress': ?progress,
              'swipeEdge': 0,
            }),
          ),
          (_) {},
        );
    await say('startBackGesture', 0);
    await say('updateBackGestureProgress', 0.25);
    await tester.pump();
    expect(
      (await painted(tester, 800)).$1,
      near(Rect.lerp(shown, cell(tester, 0), 0.25)!),
    );
    await say('commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.byType(ViewerPage), findsNothing);
    await unmount(tester);
  });

  testWidgets('under reduce motion the viewer cross-fades in, laid out as it '
      'ends from its first frame, and nothing flies', (tester) async {
    reduceMotion(tester);
    await pump(tester, size: const Size(1000, 700));
    await tap(tester, 0);
    await tester.pump();
    // Flutter runs a route's transition in 5 % of its time: 15 ms.
    await tester.pump(const Duration(milliseconds: 8));
    final photo = find.byType(DeepZoom).hitTestable();
    final first = tester.getRect(photo);
    expect(opacity(tester, photo), inExclusiveRange(0, 1));
    for (final chrome in ['filmstrip', 'viewer-close']) {
      expect(find.byKey(ValueKey(chrome)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('flight')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getRect(photo), first);
    expect(opacity(tester, photo), 1);
    await unmount(tester);
  });

  testWidgets("the item shown flies alone with the grid's thumbnail: its "
      'neighbours and the info wait for it to land', (tester) async {
    pipeline.held = Completer();
    await pump(tester, size: const Size(1000, 700));
    await tap(tester, 1);
    await tester.pump();
    await tester.pump(Motion.medium ~/ 2);
    final pages = find.byType(DeepZoom, skipOffstage: false);
    expect(pages, findsOneWidget);
    final strip = tester.getRect(find.byKey(const ValueKey('filmstrip')));
    expect((await painted(tester, strip.top)).$1, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pump();
    expect(find.byKey(const ValueKey('info')), findsNothing);
    await tester.pump(Motion.medium);
    expect(pages, findsNWidgets(3));
    expect(find.byKey(const ValueKey('info')), findsOneWidget);
    pipeline.held!.complete();
    await tester.pumpAndSettle();
    await unmount(tester);
  });
}

/// Red images of 80 × 20; the screen-size ones wait for [held] when set.
class _Red extends ThumbnailPipeline {
  Completer<void>? held;

  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) async {
    if (tier >= 512) await held?.future;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xffff0000), BlendMode.src);
    return recorder.endRecording().toImageSync(80, 20);
  }
}
