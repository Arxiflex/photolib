import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib/features/viewer/viewer_page.dart';

import '../../support/info_facts.dart';
import '../../support/pump_app.dart';
import '../../support/viewer.dart';

void main() {
  FakeFacts facts() => FakeFacts(
    albums: const [
      InfoAlbum('g', 'Sailing', path: ['Trips', 'Greece'], count: 412),
    ],
    tags: ['Travel/Greece/Sailing', 'Food'],
  );

  Future<void> pump(
    WidgetTester tester,
    Size size,
    Brightness brightness,
  ) async {
    await pumpViewer(
      tester,
      size: size,
      ids: true,
      brightness: brightness,
      rowOf: (item) => row(item).copyWith(
        width: const Value(4000),
        height: const Value(3000),
        make: const Value('Canon'),
        model: const Value('EOS R5'),
      ),
      overrides: [infoFactsProvider.overrideWith((ref) async => facts())],
    );
    await tester.pressKey(LogicalKeyboardKey.keyI, character: 'i');
    await tester.pumpAndSettle();
  }

  // The bar, the panel beside the photo and the sheet under it, in the
  // app's light and dark themes, at 100 % and 200 % text.
  for (final (layout, size) in const [
    ('panel', Size(1100, 800)),
    ('sheet', Size(390, 844)),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 2.0]) {
        final name = '${layout}_${brightness.name}_${(scale * 100).round()}';
        testWidgets('the bar and the $layout in ${brightness.name} at '
            '${(scale * 100).round()} % text', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, size, brightness);
          await expectLater(
            find.byType(ViewerPage),
            matchesGoldenFile('goldens/viewer_$name.png'),
          );
        });
      }
    }
  }

  testWidgets('every control of the bar, the panel and the arrows has a '
      'label and a tooltip, and Tab moves through them as they read', (
    tester,
  ) async {
    await pump(tester, const Size(1100, 800), Brightness.light);
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.tooltip, isNotEmpty, reason: '${button.icon}');
    }
    // Where each focus stop is, as Tab reaches it.
    final stops = <Offset>[];
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.findRenderObject() case final RenderBox box
          when box.hasSize) {
        stops.add(box.localToGlobal(Offset.zero));
      }
    }
    // The bar's row first, left to right, then down the screen.
    final bar = stops.takeWhile((s) => s.dy < 48).toList();
    expect(bar.length, greaterThan(3));
    expect([
      for (final s in bar) s.dx,
    ], orderedEquals([for (final s in bar) s.dx]..sort()));
    expect(
      stops.skip(bar.length).every((s) => s.dy >= 48),
      isTrue,
      reason: '$stops',
    );
  });
}
