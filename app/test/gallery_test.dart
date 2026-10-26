import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/gallery.dart';
import 'package:photolib/ui/media_grid.dart';
import 'package:photolib/ui/swipe_to_dismiss.dart';

import 'support/pages.dart';
import 'support/pump_app.dart';

Future<void> pumpGallery(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  ThemeMode theme = ThemeMode.light,
  Size size = const Size(480, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(GalleryApp(themeMode: theme));
  await tester.pumpAndSettle();
}

// The gallery in both themes and both pseudo-locales against its goldens and
// the Material accessibility guidelines; refresh the goldens with
// `flutter test --update-goldens test/gallery_test.dart`.
void main() {
  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    for (final locale in pseudoLocales) {
      group('the gallery, ${theme.name}, in $locale', () {
        testWidgets('matches its golden', (tester) async {
          await pumpGallery(tester, locale: locale, theme: theme);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/gallery_${theme.name}_$locale.png'),
          );
        });

        testWidgets('meets the accessibility guidelines', (tester) async {
          final semantics = tester.ensureSemantics();
          await pumpGallery(tester, locale: locale, theme: theme);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
        });
      });
    }
  }

  testWidgets('the theme button switches between light and dark', (
    tester,
  ) async {
    await pumpGallery(tester);
    Brightness brightness() =>
        Theme.of(tester.element(find.text('Buttons'))).brightness;
    await tester.tapAndSettle(find.byTooltip('Dark'));
    expect(brightness(), Brightness.dark);
    await tester.tapAndSettle(find.byTooltip('Light'));
    expect(brightness(), Brightness.light);
  });

  testWidgets('the buttons and Ctrl+= and Ctrl+- zoom the grid', (
    tester,
  ) async {
    await pumpGallery(tester);
    int columns() => tester.widget<MediaGrid>(find.byType(MediaGrid)).columns;
    final start = columns();
    await tester.tapAndSettle(find.byTooltip('Zoom in'));
    expect(columns(), lessThan(start));
    await tester.pressKey(
      LogicalKeyboardKey.minus,
      modifiers: [LogicalKeyboardKey.controlLeft],
    );
    expect(columns(), start);
    await tester.tapAndSettle(find.byTooltip('Zoom out'));
    expect(columns(), greaterThan(start));
    await tester.pressKey(
      LogicalKeyboardKey.equal,
      modifiers: [LogicalKeyboardKey.controlLeft],
    );
    expect(columns(), start);
  });

  testWidgets('the selection bar counts and clears the grid selection', (
    tester,
  ) async {
    await pumpGallery(tester);
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tapAndSettle(find.bySemanticsLabel('Photo 1 of 60'));
    expect(find.text('4 selected'), findsOneWidget);
    await tester.tapAndSettle(find.byTooltip('Clear selection'));
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('a photo opens full screen, swipes away and closes with its '
      'button', (tester) async {
    await pumpGallery(tester);
    await tester.tapAndSettle(find.byTooltip('Clear selection'));
    for (final close in [
      () =>
          tester.fling(find.byType(SwipeToDismiss), const Offset(0, 300), 1500),
      () => tester.tap(find.byTooltip('Close')),
    ]) {
      await tester.tapAndSettle(find.bySemanticsLabel('Photo 1 of 60'));
      expect(find.byType(SwipeToDismiss), findsOneWidget);
      await close();
      await tester.pumpAndSettle();
      expect(find.byType(SwipeToDismiss), findsNothing);
    }
  });

  testWidgets('a sheet and a menu open', (tester) async {
    await pumpGallery(tester);
    await tester.tapAndSettle(find.text('Show a sheet'));
    await tester.tapAndSettle(find.widgetWithText(ListTile, 'Move to trash'));
    expect(find.widgetWithText(ListTile, 'Move to trash'), findsNothing);

    await tester.tapAndSettle(find.byTooltip('More'));
    expect(
      find.widgetWithText(MenuItemButton, 'Move to trash'),
      findsOneWidget,
    );
  });
}
