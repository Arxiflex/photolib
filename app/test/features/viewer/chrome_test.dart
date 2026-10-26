import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/deep_zoom.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/ui/motion.dart';

import '../../support/pump_app.dart';
import '../../support/viewer.dart';

void main() {
  final strip = find.byKey(const ValueKey('filmstrip'));
  final photo = find.byType(DeepZoom).hitTestable();
  final bar = find.byType(CloseButton);
  double offset(WidgetTester tester) =>
      tester.widget<ListView>(strip).controller!.offset;
  Settings settings(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ViewerPage)))
          .read(settingsProvider);
  // The photo's place and the strip's offset, which chrome never moves.
  (Rect, double) still(WidgetTester tester) =>
      (tester.getRect(photo), offset(tester));

  Future<ValueNotifier<int>> pump(
    WidgetTester tester, {
    double width = 1000,
    int at = 20,
    Settings settings = const Settings(),
  }) => pumpViewer(
    tester,
    size: Size(width, 700),
    count: 40,
    at: at,
    settings: settings,
  );

  testWidgets('a tap on the photo hides and shows the bar alone: the '
      "filmstrip stays, the photo's rectangle and the strip's offset are the "
      'same', (tester) async {
    await pump(tester);
    final before = still(tester);
    for (final shown in [false, true]) {
      await tester.tapAt(tester.getCenter(photo));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(bar, shown ? findsOneWidget : findsNothing);
      expect(strip, findsOneWidget);
      expect(still(tester), before);
    }
  });

  testWidgets('the filmstrip is on by default from 760 dp and off below, and '
      'its button and F toggle it, kept per device', (tester) async {
    await pump(tester, width: 759);
    expect(strip, findsNothing);
    await pump(tester, width: 760);
    expect(strip, findsOneWidget);
    await tester.tap(find.byTooltip('Filmstrip'));
    await tester.pumpAndSettle();
    expect(strip, findsNothing);
    expect(settings(tester).filmstrip, isFalse);
    await tester.pressKey(LogicalKeyboardKey.keyF, character: 'f');
    expect(strip, findsOneWidget);
    expect(settings(tester).filmstrip, isTrue);
    await pump(tester, width: 400, settings: const Settings(filmstrip: true));
    expect(strip, findsOneWidget, reason: 'as the user left it');
  });

  testWidgets('the strip is centred on the item shown from its first frame '
      'and does not scroll as the viewer settles', (tester) async {
    await pump(tester);
    // 20.5 cells of 64 px, less half the window.
    expect(offset(tester), 20.5 * 64 - 500);
    // Shown anew: centred in the frame that first paints it, and still.
    await tester.pressKey(LogicalKeyboardKey.keyF, character: 'f');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
    await tester.pump();
    expect(offset(tester), 20.5 * 64 - 500);
    await tester.pumpAndSettle();
    expect(offset(tester), 20.5 * 64 - 500);
  });

  testWidgets('a click on a visible thumbnail leaves the strip where it is; '
      'a cut-off one is uncovered by the least amount', (tester) async {
    final position = await pump(tester);
    final start = offset(tester);
    // Clicks [cell] [x] px in.
    Future<void> click(int cell, double x) async {
      final left = tester.getTopLeft(strip).dx + cell * 64 - start;
      await tester.tapAt(Offset(left + x, tester.getCenter(strip).dy));
      await tester.pumpAndSettle();
    }

    await click(24, 32);
    expect(position.value, 24);
    expect(offset(tester), start);
    // Cell 28 starts at 1792, 20 px before the window ends at 812 + 1000.
    final cut = 29 * 64 - (start + 1000);
    await click(28, 10);
    expect(position.value, 28);
    expect(offset(tester), start + cut);
  });

  testWidgets('arrow keys recentre the strip, smoothly, only once the item '
      'comes within 20 % of an edge', (tester) async {
    final position = await pump(tester);
    final start = offset(tester);
    // Cells 21 to 24 end by 1612, 20 % of the strip before its end.
    for (var i = 0; i < 4; i++) {
      await tester.pressKey(LogicalKeyboardKey.arrowRight);
      expect(offset(tester), start, reason: 'cell ${21 + i}');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    // The page turns half way through its slide.
    while (position.value != 25) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(Motion.short ~/ 2);
    expect(offset(tester), inExclusiveRange(start, 25.5 * 64 - 500));
    await tester.pumpAndSettle();
    expect(offset(tester), 25.5 * 64 - 500);
  });

  testWidgets('a manual scroll stays; the info panel, hiding the bar and a '
      "toast leave the strip's offset alone", (tester) async {
    await pump(tester);
    await tester.drag(strip, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final scrolled = offset(tester);
    final (place, _) = still(tester);
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pumpAndSettle();
    expect(offset(tester), scrolled, reason: 'the info opened');
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pumpAndSettle();
    expect(still(tester), (place, scrolled), reason: 'the info closed');
    await tester.tapAt(tester.getCenter(photo));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(still(tester), (place, scrolled), reason: 'the bar hidden');
    ScaffoldMessenger.of(tester.element(photo))
        .showSnackBar(const SnackBar(content: Text('toast')));
    await tester.pumpAndSettle();
    expect(still(tester), (place, scrolled), reason: 'a toast');
  });
}
