import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/selection_bar.dart';

void main() {
  late List<String> calls;

  Future<void> pumpBar(
    WidgetTester tester, {
    required int count,
    bool selectAll = true,
    bool slideshow = true,
  }) async {
    calls = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          appBar: SelectionBar(
            count: count,
            onClear: () => calls.add('clear'),
            onSelectAll: selectAll ? () => calls.add('all') : null,
            onSlideshow: slideshow ? () => calls.add('slideshow') : null,
            onDownload: () => calls.add('download'),
            actions: [
              IconButton(
                icon: const Icon(Icons.favorite_border),
                tooltip: 'Favourite',
                onPressed: () => calls.add('favourite'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('counts the selection', (tester) async {
    await pumpBar(tester, count: 1);
    expect(find.text('1 selected'), findsOneWidget);
    await pumpBar(tester, count: 1200);
    expect(find.text('1,200 selected'), findsOneWidget);
  });

  testWidgets('clears, selects all, plays a slideshow, downloads and runs '
      'its actions', (tester) async {
    await pumpBar(tester, count: 3);
    for (final tooltip in [
      'Clear selection',
      'Select all',
      'Slideshow',
      'Download',
      'Favourite',
    ]) {
      await tester.tap(find.byTooltip(tooltip));
    }
    expect(calls, ['clear', 'all', 'slideshow', 'download', 'favourite']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
    'shares on phones, where it would download',
    (tester) async {
      await pumpBar(tester, count: 3);
      expect(find.byTooltip('Download'), findsNothing);
      await tester.tap(find.byTooltip('Share'));
      expect(calls, ['download']);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('offers select all and a slideshow only when it can', (
    tester,
  ) async {
    await pumpBar(tester, count: 3, selectAll: false, slideshow: false);
    expect(find.byTooltip('Select all'), findsNothing);
    expect(find.byTooltip('Slideshow'), findsNothing);
  });
}
