import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/ui/swipe_to_dismiss.dart';
import 'package:photolib/ui/theme.dart';

import '../support/pump_app.dart';
import 'motion_test.dart' show reduceMotion;

void main() {
  late int dismissed, up;
  final photo = find.text('photo');

  /// A page 800 px high: 15 % of it is 120 px.
  Future<void> pumpPage(
    WidgetTester tester, {
    bool swipeUp = false,
    bool enabled = true,
    ValueChanged<double>? onDrag,
  }) async {
    dismissed = up = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: SwipeToDismiss(
          onDismissed: () => dismissed++,
          onSwipeUp: swipeUp ? () => up++ : null,
          enabled: enabled,
          onDrag: onDrag,
          child: const Center(child: Text('photo')),
        ),
      ),
    );
  }

  double background(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(SwipeToDismiss),
              matching: find.byType(ColoredBox),
            )
            .first,
      )
      .color
      .a;

  testWidgets('a drag down past 15 % of the height dismisses', (tester) async {
    await pumpPage(tester);
    await tester.timedDrag(
      photo,
      const Offset(0, 130),
      const Duration(seconds: 1),
    );
    expect(dismissed, 1);
  });

  testWidgets('a shorter drag moves the page and fades the background, then '
      'springs back', (tester) async {
    await pumpPage(tester);
    final start = tester.getCenter(photo);
    final drag = await tester.startGesture(start);
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.getCenter(photo).dy, greaterThan(start.dy + 50));
    expect(background(tester), lessThan(1));
    await drag.up();
    await tester.pump();
    expect(tester.getCenter(photo), isNot(start));
    await tester.pumpAndSettle();
    expect(tester.getCenter(photo), start);
    expect(background(tester), 1);
    expect(dismissed, 0);
  });

  testWidgets('with onDrag, a drag says how far down it is instead of moving '
      'the page, and springs back to 0 or stays where it dismissed', (
    tester,
  ) async {
    final progress = <double>[];
    await pumpPage(tester, onDrag: progress.add);
    final start = tester.getCenter(photo);
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(progress.last, 100 / 800);
    expect(tester.getCenter(photo), start);
    expect(
      find.descendant(
        of: find.byType(SwipeToDismiss),
        matching: find.byType(ColoredBox),
      ),
      findsNothing,
      reason: "the background is the caller's",
    );
    await drag.up();
    await tester.pumpAndSettle();
    expect(progress.last, 0);
    expect(dismissed, 0);
    progress.clear();
    await tester.timedDrag(
      photo,
      const Offset(0, 200),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(dismissed, 1);
    expect(progress.last, greaterThan(0.15));
  });

  testWidgets('a flick dismisses however short', (tester) async {
    await pumpPage(tester);
    await tester.fling(photo, const Offset(0, 60), 1500);
    expect(dismissed, 1);
  });

  testWidgets('a drag up does nothing', (tester) async {
    await pumpPage(tester);
    final start = tester.getCenter(photo);
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(tester.getCenter(photo), start);
    await drag.up();
    expect(dismissed, 0);
  });

  testWidgets('with a swipe up, a drag up past 10 % of the height or a '
      'flick up calls it, moving nothing', (tester) async {
    await pumpPage(tester, swipeUp: true);
    final start = tester.getCenter(photo);
    final drag = await tester.startGesture(start);
    for (var i = 0; i < 3; i++) {
      await drag.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.getCenter(photo), start);
    await drag.up();
    expect(up, 0, reason: '60 px, slowly');
    await tester.timedDrag(
      photo,
      const Offset(0, -100),
      const Duration(seconds: 1),
    );
    expect(up, 1);
    await tester.fling(photo, const Offset(0, -60), 1500);
    expect((up, dismissed), (2, 0));
  });

  testWidgets('disabled, it leaves drags to its child', (tester) async {
    await pumpPage(tester, enabled: false);
    final start = tester.getCenter(photo);
    await tester.fling(photo, const Offset(0, 200), 1500);
    await tester.pumpAndSettle();
    expect(tester.getCenter(photo), start);
    expect(dismissed, 0);
  });

  testWidgets('under reduce motion the page snaps back at once', (
    tester,
  ) async {
    reduceMotion(tester);
    await pumpPage(tester);
    final start = tester.getCenter(photo);
    await tester.timedDrag(
      photo,
      const Offset(0, 100),
      const Duration(seconds: 1),
    );
    await tester.pump();
    expect(tester.getCenter(photo), start);
  });

  testWidgets('Escape and a screen reader dismiss it too', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);
    await tester.pressKey(LogicalKeyboardKey.escape);
    expect(dismissed, 1);
    tester.semantics.performAction(
      find.semantics.byAction(SemanticsAction.dismiss),
      SemanticsAction.dismiss,
    );
    expect(dismissed, 2);
    semantics.dispose();
  });
}
