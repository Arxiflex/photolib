import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';

import '../../support/viewer.dart';

void main() {
  const size = Size(1000, 600);
  final previous = find.byKey(const ValueKey('arrow previous'));
  final next = find.byKey(const ValueKey('arrow next'));
  double shown(WidgetTester tester, Finder arrow) =>
      arrow.evaluate().isEmpty ? 0 : opacity(tester, arrow);

  Future<TestGesture> mouse(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: at);
    await tester.pump();
    return mouse;
  }

  testWidgets('a moving mouse shows faint 52 dp arrows at the edges, '
      'vertically centred; within 18 % of an edge one is opaque and its '
      'whole strip a button', (tester) async {
    final position = await pumpViewer(tester, size: size, at: 1);
    expect(shown(tester, previous), 0);
    final pointer = await mouse(tester, const Offset(500, 300));
    await pointer.moveTo(const Offset(510, 300));
    await tester.pumpAndSettle();
    expect(shown(tester, previous), 0.5);
    expect(shown(tester, next), 0.5);
    expect(tester.getSize(previous), const Size(52, 52));
    final stage = tester.getRect(find.byType(DeepZoom).hitTestable());
    expect(tester.getCenter(previous).dy, closeTo(stage.center.dy, 1));
    expect(tester.getRect(previous).left, lessThan(32));
    expect(tester.getRect(next).right, greaterThan(size.width - 32));
    // A click in the middle of a faint arrow's strip is the photo's.
    await pointer.moveTo(const Offset(190, 500));
    await tester.pumpAndSettle();
    expect(shown(tester, previous), 0.5, reason: '19 % from the edge');
    await pointer.moveTo(const Offset(170, 500));
    await tester.pumpAndSettle();
    expect(shown(tester, previous), 1);
    await tester.tapAt(const Offset(170, 500), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(position.value, 0);
    expect(find.byType(CloseButton), findsOneWidget, reason: 'the bar stays');
  });

  testWidgets('none before the first item or after the last, none on touch, '
      'and they go a few seconds after the mouse stops and with the bar', (
    tester,
  ) async {
    await pumpViewer(tester, size: size);
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(const Offset(500, 300));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
    }
    expect(shown(tester, next), 0, reason: 'touches');
    final pointer = await mouse(tester, const Offset(500, 300));
    await pointer.moveTo(const Offset(520, 300));
    await tester.pumpAndSettle();
    expect(previous, findsNothing, reason: 'the first item');
    expect(shown(tester, next), 0.5);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(shown(tester, next), 0, reason: 'the mouse stopped');
    await pointer.moveTo(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(500, 300), kind: PointerDeviceKind.mouse);
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsNothing);
    expect(next, findsNothing, reason: 'hidden with the bar');
    await pumpViewer(tester, size: size, at: 3);
    expect(next, findsNothing, reason: 'the last item');
  });

  testWidgets("on a 360° photo the arrows' strips are 92 dp wide", (
    tester,
  ) async {
    final position = await pumpViewer(
      tester,
      size: size,
      at: 1,
      rowOf: (item) => item.key == '1'
          ? row(item).copyWith(
              projection: const Value('equirectangular'),
              width: const Value(4000),
              height: const Value(2000),
            )
          : row(item),
    );
    final pointer = await mouse(tester, const Offset(500, 300));
    await pointer.moveTo(const Offset(120, 400));
    await tester.pumpAndSettle();
    expect(shown(tester, previous), 0.5);
    await pointer.moveTo(const Offset(80, 400));
    await tester.pumpAndSettle();
    expect(shown(tester, previous), 1);
    await tester.tapAt(const Offset(80, 400), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(position.value, 0);
  });

  testWidgets('the keyboard reaches the arrows, and the arrow keys always '
      'turn the page', (tester) async {
    final position = await pumpViewer(tester, size: size, at: 1);
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.widget.key == const ValueKey('arrow next focus')) break;
    }
    await tester.pumpAndSettle();
    expect(shown(tester, next), 1, reason: 'shown while it has focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(position.value, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(position.value, 1);
  });
}
