import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/scrubber.dart';

void main() {
  test('scrubber ticks: a month each, as heavy as it is tall', () {
    final layout = TimelineLayout(
      [4, 4, 1, 5],
      columns: 4,
      cellExtent: 100,
      headerExtent: 50,
    );
    final months = TimelineBuckets(
      days: [20250301, 20250101, 20241201, 20240101],
      counts: [4, 4, 1, 5],
    ).grouped(Grouping.month);
    // Each month is 150 px but the last, 250.
    expect(TimelineScrubber.ticks(layout, months), [
      (0, 0.6),
      (150, 0.6),
      (300, 0.6),
      (450, 1.0),
    ]);
  });
}
