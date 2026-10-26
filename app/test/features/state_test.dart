import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/media_grid.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/pump_app.dart';
import '../support/viewer.dart' show Grey;

/// VIEW-36: what the user was looking at survives a rotation, a switch of
/// views, the viewer and a restart.
void main() {
  late Replica db;
  late MemoryStore kept;
  late MemoryStore settings;
  setUp(() async {
    db = Replica(NativeDatabase.memory());
    kept = MemoryStore();
    settings = MemoryStore();
    // 300 photos, 5 a day back from May 30, 2024.
    for (var n = 0; n < 300; n++) {
      final day = DateTime.utc(2024, 5, 30 - n ~/ 5, 12, n % 5);
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..buffer.asByteData().setUint32(12, n),
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '$n',
              path: Value('$n.jpg'),
              name: Value('$n.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: Value(day.toIso8601String().substring(0, 19)),
            ),
          );
    }
  });
  tearDown(() => db.close());

  Future<void> start(WidgetTester tester) => pumpApp(
    tester,
    replica: (_) => db,
    kept: kept,
    settings: settings,
    overrides: [thumbnailPipelineProvider.overrideWith((ref) async => Grey())],
  );

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  TimelineViewState timeline(WidgetTester tester) =>
      tester.state<TimelineViewState>(find.byType(TimelineView));

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a restart keeps the scroll position, the selection and the '
      "library's view options", (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('View options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group by month'));
    await tester.pumpAndSettle();
    timeline(tester).controller.jumpTo(3000);
    await tester.pumpAndSettle();
    final (top, _) = timeline(tester).visible;
    await tester.longPressAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    final selected = timeline(tester).widget.selection.value;
    await stop(tester);

    await start(tester);
    expect(timeline(tester).visible.$1, top);
    expect(timeline(tester).widget.selection.value, selected);
    expect(find.text('1 selected'), findsOneWidget);
    expect(timeline(tester).widget.grouping, Grouping.month);
    await stop(tester);
  });

  testWidgets('a restart opens the viewer again on the item it showed', (
    tester,
  ) async {
    await start(tester);
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    await tester.pressKey(LogicalKeyboardKey.arrowRight);
    final shown = tester
        .widget<ViewerPage>(find.byType(ViewerPage))
        .position
        .value;
    await stop(tester);

    await start(tester);
    expect(
      tester.widget<ViewerPage>(find.byType(ViewerPage)).position.value,
      shown,
    );
    await tester.pressKey(LogicalKeyboardKey.escape);
    expect(find.byType(ViewerPage), findsNothing);
    await stop(tester);

    await start(tester);
    expect(find.byType(ViewerPage), findsNothing, reason: 'it was closed');
    await stop(tester);
  });

  testWidgets('switching views and opening and closing the viewer keep the '
      'scroll position and the selection', (tester) async {
    await start(tester);
    timeline(tester).controller.jumpTo(2000);
    await tester.longPressAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    final (top, _) = timeline(tester).visible;
    await tester.pressKey(LogicalKeyboardKey.arrowDown);
    await tester.pressKey(LogicalKeyboardKey.enter);
    expect(find.byType(ViewerPage), findsOneWidget);
    await tester.pressKey(LogicalKeyboardKey.escape);
    expect(find.text('1 selected'), findsOneWidget);
    await tab(tester, 'Search');
    await tab(tester, 'Library');
    expect(timeline(tester).visible.$1, top);
    expect(find.text('1 selected'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('a restart and a switch of views keep the search text, its '
      'filters and what it selected', (tester) async {
    await start(tester);
    await tab(tester, 'Search');
    await tester.enterText(find.byType(TextField), '1');
    // The search runs once typing pauses.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilterChip, 'Photos'));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(MediaGrid));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tab(tester, 'Library');
    await tab(tester, 'Search');
    expect(find.text('1 selected'), findsOneWidget);
    await stop(tester);

    await start(tester);
    await tab(tester, 'Search');
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '1'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Photos'))
          .selected,
      isTrue,
    );
    await stop(tester);
  });

  testWidgets("a restart and a switch of views keep the search's scroll "
      'position', (tester) async {
    ScrollController grid() =>
        tester.widget<GridView>(find.byType(GridView)).controller!;
    await start(tester);
    await tab(tester, 'Search');
    await tester.tap(find.widgetWithText(FilterChip, 'Photos'));
    await tester.pumpAndSettle();
    // Four columns of 100 px: the 41st item heads the top row.
    grid().jumpTo(1000);
    await tester.pumpAndSettle();
    await tab(tester, 'Library');
    await tab(tester, 'Search');
    expect(grid().offset, 1000);
    await stop(tester);

    await start(tester);
    await tab(tester, 'Search');
    expect(grid().offset, 1000);
    await tester.tap(find.widgetWithText(FilterChip, 'Photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Photos'));
    await tester.pumpAndSettle();
    expect(grid().offset, 0, reason: 'another search starts at the top');
    await stop(tester);
  });
}
