import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/sliver.dart';

void main() {
  // The test view is 800 x 600. About a million assets: 10,000 days of 1 to 199 in 4 columns of 100 px.
  final counts = [for (var d = 0; d < 10000; d++) 1 + d * 7919 % 199];
  final layout = TimelineLayout(
    counts,
    columns: 4,
    cellExtent: 100,
    headerExtent: 40,
  );
  final built = <int>{};

  Future<ScrollController> pump(WidgetTester tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          slivers: [
            SliverTimeline(
              timeline: layout,
              delegate: SliverChildBuilderDelegate((context, i) {
                built.add(i);
                return Text('$i', key: ValueKey(i));
              }, childCount: layout.childCount),
            ),
          ],
        ),
      ),
    );
    return controller;
  }

  testWidgets('the scroll extent is the layout extent, without building it', (
    tester,
  ) async {
    built.clear();
    final controller = await pump(tester);
    expect(controller.position.maxScrollExtent, layout.extent - 600);
    expect(built, {for (var i = 0; layout.childOffset(i) < 600; i++) i});
  });

  testWidgets('a jump lays out only the children at the new offset', (
    tester,
  ) async {
    final controller = await pump(tester);
    final segment = layout.segmentCount * 2 ~/ 3;
    final offset = layout.segmentOffset(segment);
    final first = layout.childAt(offset);
    built.clear();
    controller.jumpTo(offset);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(ValueKey(first))).dy, 0);
    expect(built, {
      for (var i = first; layout.childOffset(i) < offset + 600; i++) i,
    });
    expect(
      tester.getSize(find.byKey(ValueKey(first + 1))).height,
      layout.childExtent(first + 1),
    );
  });
}
