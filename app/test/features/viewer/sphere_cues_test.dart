import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:photolib/features/viewer/sphere_frame.dart';

import '../../support/viewer.dart';

void main() {
  const size = Size(1000, 600);
  final ring = find.byKey(const ValueKey('sphere-ring'));
  final dial = find.byKey(const ValueKey('sphere-dial'));
  final frame = find.byType(SphereFrame).hitTestable();
  SphereView view(WidgetTester tester) =>
      tester.widget<SphereFrame>(frame).view.value;

  // Three photos, the middle one a sphere.
  Future<ValueNotifier<int>> pump(WidgetTester tester, {int at = 1}) =>
      pumpViewer(
        tester,
        size: size,
        count: 3,
        at: at,
        rowOf: (item) => item.key == '1'
            ? row(item).copyWith(
                projection: const Value('equirectangular'),
                width: const Value(4000),
                height: const Value(2000),
              )
            : row(item),
      );

  // Turns the page from the photo before the sphere to it.
  Future<void> toSphere(WidgetTester tester) async {
    await pump(tester, at: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 30 && ring.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a sphere opens rotatable with no tap and no words on it: a '
      'ring with 360° fades in and out once, never taking input, and a drag '
      'turns it instead of the page', (tester) async {
    await toSphere(tester);
    expect(ring, findsOneWidget);
    await tester.pump();
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(of: ring, matching: find.byType(IgnorePointer)),
          )
          .map((w) => w.ignoring),
      contains(true),
    );
    expect(tester.getSize(ring), const Size(96, 96));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(tester, ring), inExclusiveRange(0, 1), reason: 'fading in');
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(tester, ring), 1);
    await tester.pump(const Duration(seconds: 1));
    expect(opacity(tester, ring), 0, reason: 'gone after a second or so');
    expect(find.textContaining(RegExp('[A-Za-z]')), findsNothing);
    await tester.pumpAndSettle();
    final position = tester.widget<SphereFrame>(frame).key;
    final yaw = view(tester).yaw;
    await tester.drag(frame, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(view(tester).yaw, greaterThan(yaw + 0.1));
    expect(tester.widget<SphereFrame>(frame).key, position, reason: 'paged');
  });

  testWidgets('a slow turn shows it moves, for at most nine seconds, and '
      'stops at the first touch', (tester) async {
    await toSphere(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final start = view(tester).yaw;
    await tester.pump(const Duration(seconds: 3));
    final turned = view(tester).yaw;
    expect(turned, greaterThan(start));
    await tester.pump(const Duration(seconds: 7));
    final end = view(tester).yaw;
    await tester.pump(const Duration(seconds: 5));
    expect(view(tester).yaw, end, reason: 'done within nine seconds');
    await tester.pumpWidget(const SizedBox());

    await toSphere(tester);
    await tester.pump(const Duration(seconds: 2));
    final gesture = await tester.startGesture(tester.getCenter(frame));
    await gesture.up();
    final touched = view(tester).yaw;
    await tester.pump(const Duration(seconds: 3));
    expect(view(tester).yaw, touched, reason: 'stopped by a touch');
  });

  testWidgets('the wheel narrows the lens and a double click faces front', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();
    final fov = view(tester).fov;
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(frame)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await tester.pump();
    expect(view(tester).fov, lessThan(fov));
    await tester.drag(frame, const Offset(-200, 50));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(frame));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getCenter(frame));
    await tester.pumpAndSettle();
    expect(view(tester).yaw, 0);
    expect(view(tester).pitch, 0);
    expect(view(tester).fov, const SphereView().fov);
  });

  testWidgets('a 48 dp compass dial at the bottom right shows where it '
      'looks, faces front when clicked, tells how in its tooltip and goes '
      'with the bar', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(tester.getSize(dial), const Size(48, 48));
    final stage = tester.getRect(frame);
    expect(tester.getRect(dial).right, closeTo(stage.right - 16, 1));
    expect(tester.getRect(dial).bottom, closeTo(stage.bottom - 16, 1));
    expect(
      find.byTooltip(
        'Heading. Click to face front. Drag to look around, scroll or pinch '
        'to zoom, double-click to reset',
      ),
      findsOneWidget,
    );
    await tester.drag(frame, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final needle = tester.widget<Transform>(
      find.byKey(const ValueKey('sphere-needle')),
    );
    // Turned back by as much as the view turned.
    expect(needle.transform.entry(1, 0), closeTo(-sin(view(tester).yaw), 1e-6));
    await tester.tap(dial);
    await tester.pumpAndSettle();
    expect(view(tester).yaw, 0);
    await tester.tapAt(stage.center);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(CloseButton), findsNothing);
    expect(dial, findsNothing);
  });

  testWidgets('a long press on the dial offers the little planet and the '
      'fisheye', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    await tester.longPress(dial);
    await tester.pumpAndSettle();
    // Escape closes the menu, not the viewer.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Little planet'), findsNothing);
    expect(dial, findsOneWidget);
    await tester.longPress(dial);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Little planet'));
    await tester.pumpAndSettle();
    expect(view(tester).planet, isTrue);
  });

  testWidgets('swipes never page past a sphere; the keys, the arrows and the '
      'filmstrip do', (tester) async {
    final position = await pump(tester);
    await tester.fling(frame, const Offset(-400, 0), 2000);
    await tester.pumpAndSettle();
    expect(position.value, 1);
    await tester.tapAt(const Offset(985, 300));
    await tester.pumpAndSettle();
    expect(position.value, 1, reason: 'no edge tap on a sphere');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(position.value, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('filmstrip')),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(position.value, 0);
  });
}
