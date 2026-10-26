import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/layout.dart';

void main() {
  // Three days: 5, 1 and 8 assets in 4 columns, so 2, 1 and 2 rows.
  final layout = TimelineLayout(
    [5, 1, 8],
    columns: 4,
    cellExtent: 100,
    headerExtent: 40,
  );

  test('the extent follows from the counts alone', () {
    expect(layout.childCount, 3 + 5);
    expect(layout.extent, 3 * 40 + 5 * 100);
    expect(
      [for (var s = 0; s < 3; s++) layout.segmentOffset(s)],
      [0, 240, 380],
    );
  });

  test('each child is a header or a row with its offset, extent and cells', () {
    final children = [
      for (var i = 0; i < layout.childCount; i++)
        (
          layout.childOffset(i),
          layout.childExtent(i),
          layout.firstAsset(i),
          layout.assetCount(i),
        ),
    ];
    expect(children, [
      (0, 40, 0, 0), // header of day 0
      (40, 100, 0, 4),
      (140, 100, 4, 1),
      (240, 40, 5, 0), // header of day 1
      (280, 100, 5, 1),
      (380, 40, 6, 0), // header of day 2
      (420, 100, 6, 4),
      (520, 100, 10, 4),
    ]);
    expect(layout.isHeader(3), isTrue);
    expect(layout.isHeader(4), isFalse);
    expect(layout.segmentOf(4), 1);
  });

  test('an offset finds its child by binary search, a boundary the next', () {
    expect(
      [
        for (final o in <double>[0, 39.9, 40, 239.9, 240, 519, 520, 619.9])
          layout.childAt(o),
      ],
      [0, 0, 1, 2, 3, 6, 7, 7],
    );
    expect(layout.childAt(-5), 0, reason: 'before the start');
    expect(layout.childAt(620), 7, reason: 'at and past the end');
    expect(layout.childAt(1e9), 7);
    expect(layout.segmentAt(379.9), 1);
    expect(layout.segmentAt(380), 2);
  });

  test('a million assets in thousands of days', () {
    final counts = [for (var d = 0; d < 13000; d++) d % 7 == 0 ? 1 : 83];
    final big = TimelineLayout(
      counts,
      columns: 4,
      cellExtent: 102.75,
      headerExtent: 48,
    );
    final total = counts.fold(0, (a, b) => a + b);
    expect(total, greaterThan(900000));
    for (final i in [0, 1, 1234, 98765, big.childCount - 1]) {
      expect(big.childAt(big.childOffset(i)), i);
      expect(big.childAt(big.childOffset(i) + big.childExtent(i) / 2), i);
    }
    final last = big.childCount - 1;
    expect(big.firstAsset(last) + big.assetCount(last), total);
    expect(big.childOffset(last) + big.childExtent(last), big.extent);
  });

  test('an empty timeline has no children and no extent', () {
    final empty = TimelineLayout(
      const [],
      columns: 4,
      cellExtent: 100,
      headerExtent: 40,
    );
    expect(empty.childCount, 0);
    expect(empty.extent, 0);
    expect(empty.childAt(0), 0);
  });

  test('an asset finds its row, and a point its asset', () {
    expect(
      [
        for (final a in [0, 3, 4, 5, 6, 13]) layout.assetOffset(a),
      ],
      [40, 40, 140, 280, 420, 520],
    );
    expect(layout.assetAt(150, 0), (4, true));
    expect(layout.assetAt(150, 2), (4, false), reason: 'past the last cell');
    expect(layout.assetAt(250, 3), (5, false), reason: 'a header');
    expect(layout.assetAt(530, 1), (11, true));
  });

  group('density', () {
    test(
      'each level has the columns of docs/10 §3.2 on phones and desktops',
      () {
        expect([for (final d in Density.values) d.columns(400)], [12, 7, 3, 2]);
        expect(
          [for (final d in Density.values) d.columns(1280)],
          [30, 16, 8, 4],
        );
        expect(
          [for (final d in Density.values) d.columns(1000)],
          [28, 16, 7, 3],
        );
        expect(Density.months.grouping(Grouping.week), Grouping.month);
        expect(Density.days.grouping(Grouping.week), Grouping.week);
      },
    );

    test('a pinch snaps to the level nearest its columns, by ratio', () {
      expect(Density.nearest(400, 3 / 1.4), Density.comfortable);
      expect(Density.nearest(400, 3 / 1.2), Density.days);
      expect(Density.nearest(400, 5), Density.months);
      expect(Density.nearest(400, 100), Density.years);
      expect(Density.nearest(400, 0.1), Density.comfortable);
    });
  });
}
