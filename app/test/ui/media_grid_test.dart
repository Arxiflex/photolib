import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/ui/media_grid.dart';
import 'package:photolib/ui/theme.dart';

import '../support/pump_app.dart';

const levels = [1, 3, 5, 9];

void main() {
  late ValueNotifier<Selection> selection;
  late List<int> opened;
  late List<int> zooms;
  late ScrollController scroll;
  late void Function(int) setColumns;

  /// [count] items in a 300 × 600 grid: 3 columns of 100 px cells, 6 rows
  /// shown.
  Future<void> pumpGrid(
    WidgetTester tester, {
    int columns = 3,
    int count = 100,
    TextDirection direction = TextDirection.ltr,
  }) async {
    var shown = columns;
    selection = ValueNotifier(Selection.none);
    opened = [];
    zooms = [];
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Directionality(
          textDirection: direction,
          child: StatefulBuilder(
            builder: (context, setState) {
              setColumns = (value) => setState(() => shown = value);
              return Scaffold(
                body: MediaGrid(
                  count: count,
                  columns: shown,
                  levels: levels,
                  onColumns: (value) => setState(() {
                    zooms.add(value);
                    shown = value;
                  }),
                  selection: selection,
                  onOpen: opened.add,
                  itemBuilder: (context, i) => Text('$i'),
                ),
              );
            },
          ),
        ),
      ),
    );
    scroll = tester.widget<GridView>(find.byType(GridView)).controller!;
  }

  /// The item drawn under [point].
  int itemAt(WidgetTester tester, Offset point) {
    for (var i = 0; i < 100; i++) {
      final cell = find.text('$i');
      if (cell.evaluate().isEmpty) continue;
      final box = tester.renderObject<RenderBox>(
        find.ancestor(of: cell, matching: find.byType(InkWell)),
      );
      final topLeft = box.localToGlobal(Offset.zero);
      if ((topLeft & box.size).contains(point)) return i;
    }
    return -1;
  }

  Offset cell(WidgetTester tester, int i) => tester.getCenter(find.text('$i'));

  Set<int> selected() => {...selection.value.positions};

  Future<TestGesture> longPress(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    return gesture;
  }

  group('selection', () {
    testWidgets('a tap opens an item', (tester) async {
      await pumpGrid(tester);
      await tester.tapAndSettle(find.text('4'));
      expect(opened, [4]);
      expect(selected(), isEmpty);
    });

    testWidgets('a long press selects, then taps toggle', (tester) async {
      await pumpGrid(tester);
      await tester.longPress(find.text('4'));
      await tester.pumpAndSettle();
      expect(selected(), {4});
      await tester.tapAndSettle(find.text('5'));
      await tester.tapAndSettle(find.text('4'));
      expect(selected(), {5});
      expect(opened, isEmpty);
    });

    testWidgets('dragging after a long press selects row by row, and going '
        'back shrinks the range', (tester) async {
      await pumpGrid(tester);
      final drag = await longPress(tester, cell(tester, 1));
      await drag.moveTo(cell(tester, 7));
      await tester.pump();
      expect(selected(), {1, 2, 3, 4, 5, 6, 7});
      await drag.moveTo(cell(tester, 3));
      await tester.pump();
      expect(selected(), {1, 2, 3});
      await drag.up();
    });

    testWidgets('dragging from a selected item clears the range', (
      tester,
    ) async {
      await pumpGrid(tester);
      selection.value = Selection.none.add(0, 9);
      final drag = await longPress(tester, cell(tester, 4));
      await drag.moveTo(cell(tester, 6));
      await drag.up();
      expect(selected(), {0, 1, 2, 3, 7, 8});
    });

    testWidgets('while selecting, a long press previews the item until it '
        'lifts', (tester) async {
      await pumpGrid(tester);
      selection.value = Selection.none.add(0, 1);
      await tester.pump();
      final press = await longPress(tester, cell(tester, 5));
      expect(find.byKey(const ValueKey('peek')), findsOneWidget);
      await press.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('peek')), findsNothing);
      expect(selected(), {0});
    });

    testWidgets('a drag selects 5,000 items as one range, with no cap', (
      tester,
    ) async {
      await pumpGrid(tester, count: 100000);
      final drag = await longPress(tester, cell(tester, 0));
      scroll.jumpTo(166600);
      await tester.pump();
      await drag.moveTo(const Offset(150, 50));
      await tester.pump();
      expect(selection.value.count, 5000);
      expect(selection.value.ranges, [(0, 5000)]);
      await drag.up();
    });

    testWidgets('a rotation keeps the row at the top, and the selection', (
      tester,
    ) async {
      await pumpGrid(tester);
      scroll.jumpTo(1000);
      selection.value = Selection.none.add(30, 33);
      await tester.pump();
      tester.view.physicalSize = const Size(600, 300);
      await tester.pumpAndSettle();
      expect(itemAt(tester, const Offset(10, 10)), 30);
      expect(selected(), {30, 31, 32});
    });

    testWidgets('right to left, the first item is at the top right', (
      tester,
    ) async {
      await pumpGrid(tester, direction: TextDirection.rtl);
      final drag = await longPress(tester, const Offset(250, 50));
      await drag.moveTo(const Offset(50, 50));
      await drag.up();
      expect(itemAt(tester, const Offset(250, 50)), 0);
      expect(selected(), {0, 1, 2});
    });

    testWidgets('holding near the bottom edge scrolls, faster the closer it '
        'is, and keeps selecting', (tester) async {
      await pumpGrid(tester);
      final drag = await longPress(tester, cell(tester, 0));
      final scrolled = <double>[];
      for (final y in [580.0, 598.0]) {
        await drag.moveTo(Offset(150, y));
        final start = scroll.offset;
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        scrolled.add(scroll.offset - start);
      }
      await drag.up();
      expect(scrolled[0], greaterThan(0));
      expect(scrolled[1], greaterThan(scrolled[0] * 1.5));
      final last = itemAt(tester, const Offset(150, 598));
      expect(last, greaterThan(18));
      expect(selected(), {for (var i = 0; i <= last; i++) i});
    });

    testWidgets('Space selects the focused item and Enter opens it', (
      tester,
    ) async {
      await pumpGrid(tester);
      await tester.pressKey(LogicalKeyboardKey.tab);
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(selected(), {0});
      await tester.pressKey(LogicalKeyboardKey.space);
      expect(selected(), isEmpty);
      await tester.pressKey(LogicalKeyboardKey.enter);
      expect(opened, [0]);
    });

    /// The item the focus ring is on, if any.
    int? ringed(WidgetTester tester) {
      final ring = find.byKey(const ValueKey('cursor'));
      if (ring.evaluate().isEmpty) return null;
      final item = itemAt(tester, tester.getCenter(ring));
      expect(
        tester.getRect(ring),
        tester.getRect(
          find.ancestor(of: find.text('$item'), matching: find.byType(InkWell)),
        ),
      );
      return item;
    }

    Future<int?> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      await tester.pressKey(
        key,
        modifiers: [if (shift) LogicalKeyboardKey.shiftLeft],
      );
      return ringed(tester);
    }

    testWidgets('arrow keys move a visible focus through the cells and '
        'scroll to it, Space and Shift select, Enter opens (docs/17 §5)', (
      tester,
    ) async {
      await pumpGrid(tester);
      expect(ringed(tester), isNull);
      // A click on the grid gives it the keys; the first arrow rings the first
      // cell shown.
      scroll.jumpTo(250);
      await tester.pump();
      final click = await tester.startGesture(
        const Offset(150, 300),
        kind: PointerDeviceKind.mouse,
      );
      await click.cancel();
      await tester.pump();
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 9);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 10);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 13);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), 12);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), 11);
      expect(await press(tester, LogicalKeyboardKey.arrowUp), 8);
      // Up past the top scrolls back to the first row, and stays there.
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(ringed(tester), 2);
      expect(scroll.offset, 0);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), 1);

      await press(tester, LogicalKeyboardKey.space);
      expect(selected(), {1});
      expect(await press(tester, LogicalKeyboardKey.arrowDown, shift: true), 4);
      expect(selected(), {1, 2, 3, 4});
      await press(tester, LogicalKeyboardKey.space);
      expect(selected(), {1, 2, 3});

      // Down to the last row, whose last cell takes the columns it lacks.
      selection.value = Selection.none;
      for (var i = 0; i < 31; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(ringed(tester), 97);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 99);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 99);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 99);
      await press(tester, LogicalKeyboardKey.enter);
      expect(opened, [99]);

      // A pointer hides the focus.
      final pointer = await tester.startGesture(
        const Offset(150, 300),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.cancel();
      await tester.pump();
      expect(ringed(tester), isNull);
    });

    testWidgets('a click hides the ring of a cell scrolled away and back, '
        'and the next arrow starts again', (tester) async {
      await pumpGrid(tester);
      await tester.pressKey(LogicalKeyboardKey.tab);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 1);
      scroll.jumpTo(3000);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();
      final click = await tester.startGesture(
        const Offset(150, 300),
        kind: PointerDeviceKind.mouse,
      );
      await click.cancel();
      await tester.pump();
      expect(ringed(tester), isNull);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 0);
    });

    testWidgets('arrows within one frame each move on from the last', (
      tester,
    ) async {
      await pumpGrid(tester);
      await tester.pressKey(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(ringed(tester), 4);
    });

    testWidgets('right to left, the arrows are mirrored', (tester) async {
      await pumpGrid(tester, direction: TextDirection.rtl);
      await tester.pressKey(LogicalKeyboardKey.tab);
      expect(ringed(tester), 0);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), 1);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), 0);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), 3);
    });

    testWidgets('a screen reader sees the selection and selects with a long '
        'press', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpGrid(tester);
      selection.value = Selection.none.add(4, 5);
      await tester.pump();
      expect(
        tester.getSemantics(find.text('4')),
        isSemantics(isSelected: true, hasTapAction: true),
      );
      final node = tester.getSemantics(find.text('5'));
      expect(node, isSemantics(isSelected: false, hasLongPressAction: true));
      tester.semantics.longPress(find.semantics.byLabel('5'));
      await tester.pump();
      expect(selected(), {4, 5});
      semantics.dispose();
    });
  });

  group('zoom', () {
    Future<void> pinch(WidgetTester tester, Offset center, double scale) async {
      const span = 40.0;
      final a = await tester.startGesture(
        center.translate(0, -span),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center.translate(0, span),
        pointer: 2,
      );
      for (var step = 1; step <= 5; step++) {
        final s = 1 + (scale - 1) * step / 5;
        await a.moveTo(center.translate(0, -span * s));
        await b.moveTo(center.translate(0, span * s));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    for (final (from, scale, to) in [
      (3, 1.8, 1),
      (5, 1.7, 3),
      (3, 0.55, 5),
      (5, 0.4, 9),
      (1, 0.5, 3),
      (9, 0.5, 9),
      (3, 1.15, 3),
    ]) {
      testWidgets('a pinch to $scale× takes $from columns to $to', (
        tester,
      ) async {
        await pumpGrid(tester, columns: from);
        await pinch(tester, const Offset(150, 300), scale);
        expect(zooms, from == to ? isEmpty : [to]);
      });
    }

    testWidgets('the item under the fingers stays under them', (tester) async {
      await pumpGrid(tester, columns: 5);
      scroll.jumpTo(500);
      await tester.pump();
      const focal = Offset(200, 330);
      final item = itemAt(tester, focal);
      await pinch(tester, focal, 1.7);
      expect(zooms, [3]);
      expect(itemAt(tester, focal), item);
    });

    testWidgets('columns changed by a button, even after a pinch that '
        'changed nothing, keep the top item in view', (tester) async {
      await pumpGrid(tester);
      scroll.jumpTo(1000);
      await tester.pump();
      expect(itemAt(tester, const Offset(10, 10)), 30);
      await pinch(tester, const Offset(150, 300), 1.15);
      setColumns(5);
      await tester.pump();
      expect(itemAt(tester, const Offset(10, 10)), 30);
    });

    test('a button steps one level, up to the ends', () {
      expect(MediaGrid.step(levels, 3, -1), 1);
      expect(MediaGrid.step(levels, 3, 1), 5);
      expect(MediaGrid.step(levels, 1, -1), 1);
      expect(MediaGrid.step(levels, 9, 1), 9);
    });

    testWidgets('a single finger scrolls rather than zooms', (tester) async {
      await pumpGrid(tester);
      await tester.drag(find.byType(GridView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(zooms, isEmpty);
    });
  });
}
