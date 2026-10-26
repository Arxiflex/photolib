import 'package:flutter/foundation.dart';

/// Selected timeline positions as sorted, disjoint ranges, so that a drag over
/// thousands of items, a day or everything is a single range (docs/10 §3.6).
@immutable
class Selection {
  Selection._(this.ranges) : count = ranges.fold(0, (n, r) => n + r.$2 - r.$1);

  /// The ranges [json] holds, as [toJson] wrote them.
  factory fromJson(Object? json) => [
    if (json is List)
      for (final range in json)
        if (range case [final int start, final int end]) (start, end),
  ].fold(none, (s, r) => s.add(r.$1, r.$2));

  static final none = Selection._(const []);

  /// Each range's first position and the one after its last.
  final List<(int, int)> ranges;
  final int count;

  bool get isEmpty => ranges.isEmpty;

  Selection add(int start, int end) {
    final merged = <(int, int)>[];
    for (final (s, e) in [
      ...ranges,
      (start, end),
    ]..sort((a, b) => a.$1 - b.$1)) {
      if (s >= e) continue;
      if (merged.isNotEmpty && merged.last.$2 >= s) {
        final (ls, le) = merged.removeLast();
        merged.add((ls, e > le ? e : le));
      } else {
        merged.add((s, e));
      }
    }
    return Selection._(merged);
  }

  Selection remove(int start, int end) => Selection._([
    for (final (s, e) in ranges) ...[
      if (s < start) (s, e < start ? e : start),
      if (e > end) (s > end ? s : end, e),
    ],
  ]);

  Selection toggle(int position) => contains(position)
      ? remove(position, position + 1)
      : add(position, position + 1);

  bool contains(int position) => containsAll(position, position + 1);

  /// Whether every position from [start] to before [end] is selected.
  bool containsAll(int start, int end) {
    var low = 0, high = ranges.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (ranges[mid].$1 <= start) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return ranges.isNotEmpty &&
        ranges[low].$1 <= start &&
        end <= ranges[low].$2;
  }

  /// The ranges as JSON.
  List<List<int>> toJson() => [
    for (final (start, end) in ranges) [start, end],
  ];

  /// The selected positions, in order.
  Iterable<int> get positions sync* {
    for (final (start, end) in ranges) {
      for (var p = start; p < end; p++) {
        yield p;
      }
    }
  }

  /// The [n]th selected position.
  int operator [](int n) {
    for (final (s, e) in ranges) {
      if (n < e - s) return s + n;
      n -= e - s;
    }
    throw RangeError.index(n, this);
  }

  @override
  bool operator ==(Object other) =>
      other is Selection && listEquals(other.ranges, ranges);

  @override
  int get hashCode => Object.hashAll(ranges);
}
