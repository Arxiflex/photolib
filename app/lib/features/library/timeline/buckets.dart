/// How a view groups its days into segments (VIEW-03).
enum Grouping { day, week, month }

/// Assets per segment, newest first, from the assets per local day that
/// `timeline_bucket` keeps (docs/10 §2). A segment is named by its first day,
/// `yyyymmdd`; 0 is the undated segment, which is last.
class TimelineBuckets {
  /// Day segments.
  TimelineBuckets({required this.days, required this.counts}) {
    for (var s = days.length - 1; s >= 0; s--) {
      if (days[s] != 0) _months[days[s] ~/ 100] = s;
    }
  }

  TimelineBuckets._(this.days, this.counts, Map<int, int> months) {
    _months.addAll(months);
  }

  final List<int> days;
  final List<int> counts;
  final _months = <int, int>{};

  /// These days in segments of [grouping]; weeks start on [firstDay].
  TimelineBuckets grouped(Grouping grouping, {int firstDay = DateTime.monday}) {
    if (grouping == Grouping.day) return this;
    final starts = <int>[], sums = <int>[], months = <int, int>{};
    for (var s = 0; s < days.length; s++) {
      final d = days[s];
      final start = d == 0
          ? 0
          : grouping == Grouping.month
          ? d ~/ 100 * 100 + 1
          : _weekStart(d, firstDay);
      if (starts.isEmpty || starts.last != start) {
        starts.add(start);
        sums.add(0);
      }
      sums.last += counts[s];
      if (d != 0) months.putIfAbsent(d ~/ 100, () => starts.length - 1);
    }
    return TimelineBuckets._(starts, sums, months);
  }

  static int _weekStart(int day, int firstDay) {
    final d = DateTime.utc(day ~/ 10000, day ~/ 100 % 100, day % 100);
    final start = d.subtract(Duration(days: (d.weekday - firstDay) % 7));
    return start.year * 10000 + start.month * 100 + start.day;
  }

  /// The newest segment with assets of a month, for an O(1) jump; null
  /// without assets.
  int? segmentOfMonth(int year, int month) => _months[year * 100 + month];

  /// Each month (`yyyymm`) with its newest segment, newest first.
  late final List<(int, int)> months = [
    for (final MapEntry(:key, :value) in _months.entries) (key, value),
  ]..sort((a, b) => b.$1 - a.$1);

  /// Each year with its newest segment, newest first.
  late final List<(int, int)> years = [
    for (var i = 0; i < months.length; i++)
      if (i == 0 || months[i - 1].$1 ~/ 100 != months[i].$1 ~/ 100)
        (months[i].$1 ~/ 100, months[i].$2),
  ];

  DateTime? day(int segment) {
    final d = days[segment];
    return d == 0 ? null : DateTime(d ~/ 10000, d ~/ 100 % 100, d % 100);
  }

  int get assets => counts.fold(0, (a, b) => a + b);
}
