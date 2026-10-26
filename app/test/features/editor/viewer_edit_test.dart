import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/editor/save_copy.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/thumbnail_at.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';

import '../../support/viewer.dart';

/// Grey images, the copy's upright, and the items they were asked for.
class _Asked extends Grey {
  final items = <ThumbnailItem>[];

  @override
  Future<ui.Image> load(ThumbnailItem item, int tier, Tile tile) {
    items.add(item);
    if (item.key != 'copy') return super.load(item, tier, tile);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xff808080), BlendMode.src);
    return Future.value(recorder.endRecording().toImageSync(30, 40));
  }
}

void main() {
  testWidgets('after an edit the viewer stays where it was and shows the '
      'copy saved there', (tester) async {
    final copy = ThumbnailItem('copy', Uri.file('/p/1_edit.jpg'));
    final pipeline = _Asked();
    final position = await pumpViewer(
      tester,
      size: const Size(1200, 800),
      count: 8,
      at: 1,
      pipeline: pipeline,
      overrides: [
        saveCopyProvider.overrideWithValue((item, edit, time) async => copy),
      ],
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save copy'));
    await tester.pumpAndSettle();
    expect(position.value, 1);
    expect(pipeline.items.last, copy);
    expect(find.text('Saved as a copy'), findsOneWidget);
    // The filmstrip's cell there shows the copy too.
    final cell = find.descendant(
      of: find.byWidgetPredicate((w) => w is ThumbnailAt && w.asset == 1),
      matching: find.byType(RawImage),
    );
    expect(tester.widget<RawImage>(cell).image?.height, 40);
    // Far away and back, it loads the copy again, never the original.
    pipeline.items.clear();
    for (final key in [LogicalKeyboardKey.end, LogicalKeyboardKey.home]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(pipeline.items, contains(copy));
    expect(pipeline.items.map((i) => i.key), isNot(contains('1')));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Saved as a copy'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
