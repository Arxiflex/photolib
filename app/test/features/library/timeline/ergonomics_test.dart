import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/l10n/app_localizations.dart';

void main() {
  // 300 days of 20 assets, one a day back from 4 March 2025.
  final buckets = TimelineBuckets(
    days: [
      for (var d = 0; d < 300; d++)
        switch (DateTime(2025, 3, 4 - d)) {
          final t => t.year * 10000 + t.month * 100 + t.day,
        },
    ],
    counts: List.filled(300, 20),
  );
  final selection = ValueNotifier(Selection.none);
  final view = GlobalKey<TimelineViewState>();

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 600),
    bool Function(Object asset)? animated,
    Future<ui.Codec?> Function(Object asset)? animation,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    selection.value = Selection.none;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final tile = recorder.endRecording().toImageSync(256, 256);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: TimelineView(
            key: view,
            buckets: buckets,
            pages: TimelinePages(
              (first, count) async => [
                for (var a = first; a < first + count; a++) a,
              ],
            ),
            thumbnails: Thumbnails((asset, tier, t) async => tile.clone()),
            selection: selection,
            animated: animated,
            animation: animation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a rotation keeps the item at the top, and the selection', (
    tester,
  ) async {
    await pump(tester);
    final state = view.currentState!;
    state.controller.jumpTo(5000);
    selection.value = Selection.none.add(100, 150);
    await tester.pump();
    final (top, _) = state.visible;
    for (final size in const [Size(900, 400), Size(400, 600)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final (first, _) = state.visible;
      expect(top, inInclusiveRange(first, first + state.layout.columns - 1));
    }
    expect(selection.value.ranges, [(100, 150)]);
  });

  testWidgets('while selecting, a long press previews the item until it '
      'lifts; dragged on, it selects as ever', (tester) async {
    await pump(tester);
    selection.value = Selection.none.add(0, 1);
    await tester.pump();
    final cell = view.currentState!.cellOf(5).center;
    var press = await tester.startGesture(cell);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('peek')), findsOneWidget);
    final shown = tester.getSize(find.byType(ThumbnailAt));
    expect(shown.width, shown.height, reason: 'square, as cells are');
    expect(selection.value.ranges, [(0, 1)]);
    await press.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('peek')), findsNothing);
    expect(selection.value.ranges, [(0, 1)]);

    press = await tester.startGesture(cell);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await press.moveTo(view.currentState!.cellOf(7).center);
    await tester.pump();
    expect(find.byKey(const ValueKey('peek')), findsNothing);
    expect(selection.value.ranges, [(0, 1), (5, 8)]);
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an animated cell has a badge; asked to, it plays in the grid '
      'while nothing is selected', (tester) async {
    await pump(tester, animated: (asset) => asset == 0);
    expect(find.byIcon(Icons.gif_box), findsOneWidget);

    await pump(
      tester,
      animated: (asset) => asset == 0,
      animation: (_) async => _Codec(),
    );
    final frames = find.descendant(
      of: find.byType(TimelineView),
      matching: find.byType(RawImage),
    );
    expect(tester.widget<RawImage>(frames).image, isNotNull);
    expect(find.byIcon(Icons.gif_box), findsNothing);
    selection.value = Selection.none.add(0, 1);
    await tester.pump();
    expect(find.byIcon(Icons.gif_box), findsOneWidget);
    expect(frames, findsNothing);
  });
}

/// Two frames of 50 ms, played once.
class _Codec implements ui.Codec {
  @override
  int get frameCount => 2;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    return _Frame(recorder.endRecording().toImageSync(1, 1));
  }

  @override
  void dispose() {}
}

class _Frame implements ui.FrameInfo {
  new(this.image);

  @override
  final ui.Image image;

  @override
  Duration get duration => const Duration(milliseconds: 50);
}
