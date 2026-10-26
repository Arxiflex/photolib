import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/library/timeline/buckets.dart';

void main() {
  // Newest first, as the bucket table orders them; 0 is the undated segment.
  final buckets = TimelineBuckets(
    days: [20250304, 20250301, 20250117, 20241231, 20240101, 0],
    counts: [3, 1, 4, 1, 5, 9],
  );

  test('a month maps to its newest day in O(1)', () {
    expect(buckets.segmentOfMonth(2025, 3), 0);
    expect(buckets.segmentOfMonth(2025, 1), 2);
    expect(buckets.segmentOfMonth(2024, 12), 3);
    expect(buckets.segmentOfMonth(2024, 1), 4);
    expect(buckets.segmentOfMonth(2025, 2), isNull, reason: 'no assets');
  });

  test('each year starts at its newest segment', () {
    expect(buckets.years, [(2025, 0), (2024, 3)]);
  });

  test('a segment has its local day, and none when undated', () {
    expect(buckets.day(1), DateTime(2025, 3, 1));
    expect(buckets.day(5), isNull);
    expect(buckets.assets, 23);
  });

  group('grouped', () {
    final month = buckets.grouped(Grouping.month);
    // Weeks from Monday: 4 Mar 2025 is a Tuesday, 1 Mar a Saturday.
    final week = buckets.grouped(Grouping.week);

    test('by month, a segment per month with the sum of its days', () {
      expect(month.days, [20250301, 20250101, 20241201, 20240101, 0]);
      expect(month.counts, [4, 4, 1, 5, 9]);
      expect(month.segmentOfMonth(2025, 1), 1);
      expect(month.years, [(2025, 0), (2024, 2)]);
      expect(month.assets, buckets.assets);
    });

    test('by week, from the locale\'s first day, across months and years', () {
      expect(week.days, [20250303, 20250224, 20250113, 20241230, 20240101, 0]);
      expect(week.counts, [3, 1, 4, 1, 5, 9]);
      expect(week.segmentOfMonth(2025, 3), 0);
      expect(week.segmentOfMonth(2025, 2), isNull);
      expect(week.segmentOfMonth(2024, 12), 3);
      expect(week.years, [(2025, 0), (2024, 3)]);
      final sunday = buckets.grouped(Grouping.week, firstDay: DateTime.sunday);
      expect(sunday.days, [
        20250302,
        20250223,
        20250112,
        20241229,
        20231231,
        0,
      ]);
    });

    test('by day, the days', () {
      final day = buckets.grouped(Grouping.day);
      expect(day.days, buckets.days);
      expect(day.counts, buckets.counts);
    });
  });
}
