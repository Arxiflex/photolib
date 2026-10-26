import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/map/map_page.dart';

import '../support/pump_app.dart';

void main() {
  double top(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  Future<void> openCollections(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tapAndSettle(find.text('Collections'));
  }

  testWidgets('lists the collections with no controls until customising', (
    tester,
  ) async {
    await openCollections(tester);
    expect(top(tester, 'Albums'), lessThan(top(tester, 'People')));
    expect(top(tester, 'People'), lessThan(top(tester, 'Places')));
    expect(top(tester, 'Places'), lessThan(top(tester, 'Tags')));
    expect(find.byTooltip('Pin Albums'), findsNothing);
    expect(find.textContaining('Hidden'), findsNothing);
  });

  testWidgets('Customise shows the controls and Done hides them', (
    tester,
  ) async {
    await openCollections(tester);
    await tester.tapAndSettle(find.text('Customise'));
    expect(find.byTooltip('Pin Albums'), findsOneWidget);
    expect(find.byTooltip('Hide Albums'), findsOneWidget);

    await tester.tapAndSettle(find.text('Done'));
    expect(find.byTooltip('Pin Albums'), findsNothing);
    expect(find.text('Customise'), findsOneWidget);
  });

  testWidgets('pinning lifts a collection to the top', (tester) async {
    await openCollections(tester);
    await tester.tapAndSettle(find.text('Customise'));
    await tester.tapAndSettle(find.byTooltip('Pin Tags'));
    expect(top(tester, 'Tags'), lessThan(top(tester, 'Albums')));
    expect(find.byTooltip('Unpin Tags'), findsOneWidget);
  });

  testWidgets('moving swaps neighbours, and the ends cannot move out', (
    tester,
  ) async {
    await openCollections(tester);
    await tester.tapAndSettle(find.text('Customise'));
    await tester.tapAndSettle(find.byTooltip('Move Albums down'));
    expect(top(tester, 'Folders'), lessThan(top(tester, 'Albums')));

    await tester.tapAndSettle(find.byTooltip('Move Folders up'));
    expect(top(tester, 'Folders'), lessThan(top(tester, 'Albums')));
  });

  testWidgets('a hidden collection is listed apart and can be shown again', (
    tester,
  ) async {
    await openCollections(tester);
    await tester.tapAndSettle(find.text('Customise'));
    await tester.tapAndSettle(find.byTooltip('Hide People'));
    expect(find.text('Hidden (1)'), findsOneWidget);
    expect(top(tester, 'Hidden (1)'), lessThan(top(tester, 'People')));
    expect(top(tester, 'Tags'), lessThan(top(tester, 'Hidden (1)')));

    await tester.tapAndSettle(find.text('Done'));
    expect(find.text('People'), findsNothing);

    await tester.tapAndSettle(find.text('Customise'));
    await tester.tapAndSettle(find.byTooltip('Show People'));
    expect(find.textContaining('Hidden'), findsNothing);
    expect(top(tester, 'Albums'), lessThan(top(tester, 'People')));
  });

  testWidgets(
    'the map is listed after the collections that can be customised',
    (tester) async {
      await openCollections(tester);
      expect(top(tester, 'Tags'), lessThan(top(tester, 'Map')));
      // The store never opens in this test, so the page waits for it.
      await tester.ensureVisible(find.text('Map'));
      await tester.tap(find.text('Map'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MapPage), findsOneWidget);
    },
  );
}
