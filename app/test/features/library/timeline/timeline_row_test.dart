import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/pages.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/l10n/app_localizations.dart';

void main() {
  testWidgets('rows ask a new Thumbnails and leave the old', (tester) async {
    final buckets = TimelineBuckets(days: [20250304], counts: [6]);
    final pages = TimelinePages(
      (first, count) async => [for (var a = first; a < 6; a++) a],
    );
    final selection = ValueNotifier(Selection.none);
    final asked = <String, List<Object>>{'old': [], 'new': []};
    final cancelled = <Object>[];
    Thumbnails of(String name) => Thumbnails((asset, tier, t) {
      asked[name]!.add(asset);
      unawaited(t.cancelled.then((_) => cancelled.add(asset)));
      return Completer<ui.Image>().future;
    }, concurrency: 6);
    Future<void> show(Thumbnails thumbnails) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: TimelineView(
            buckets: buckets,
            pages: pages,
            thumbnails: thumbnails,
            selection: selection,
          ),
        ),
      ),
    );

    await show(of('old'));
    await tester.pumpAndSettle();
    expect(asked['old'], unorderedEquals([0, 1, 2, 3, 4, 5]));

    await show(of('new'));
    await tester.pumpAndSettle();
    expect(asked['new'], unorderedEquals([0, 1, 2, 3, 4, 5]));
    expect(cancelled, unorderedEquals([0, 1, 2, 3, 4, 5]));
  });
}
