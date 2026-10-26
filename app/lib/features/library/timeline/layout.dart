import 'dart:math' as math;
import 'dart:typed_data';

import 'buckets.dart';

/// The density levels of docs/10 §3.2, densest first: the cell width each
/// aims at, the bounds of its columns, and month segments for the two densest.
enum Density {
  years(36, 10, 30),
  months(64, 6, 16),
  days(160, 3, 10),
  comfortable(360, 1, 5);

  const Density(this._cell, this._min, this._max);

  final double _cell;
  final int _min, _max;

  int columns(double width) => (width / _cell).ceil().clamp(_min, _max);

  /// Its segments in a view grouped by [view].
  Grouping grouping(Grouping view) => index < 2 ? Grouping.month : view;

  /// The level whose columns are nearest [columns] by ratio, where a pinch
  /// that ends there snaps to.
  static Density nearest(double width, double columns) {
    double distance(Density d) => math.log(d.columns(width) / columns).abs();
    return values.reduce((a, b) => distance(b) < distance(a) ? b : a);
  }
}

/// The scroll geometry of the timeline (docs/10 §3.1): segments of a header and
/// rows of square cells, so every offset follows from the asset counts alone.
class TimelineLayout {
  TimelineLayout(
    List<int> counts, {
    required this.columns,
    required this.cellExtent,
    required this.headerExtent,
  }) : _assetsBefore = Int32List(counts.length + 1),
       _rowsBefore = Int32List(counts.length + 1) {
    for (var s = 0; s < counts.length; s++) {
      _assetsBefore[s + 1] = _assetsBefore[s] + counts[s];
      _rowsBefore[s + 1] =
          _rowsBefore[s] + (counts[s] + columns - 1) ~/ columns;
    }
  }

  final int columns;
  final double cellExtent;
  final double headerExtent;
  final Int32List _assetsBefore;
  final Int32List _rowsBefore;

  int get segmentCount => _rowsBefore.length - 1;
  int get childCount => segmentCount + _rowsBefore[segmentCount];
  double get extent => segmentOffset(segmentCount);

  double segmentOffset(int segment) =>
      segment * headerExtent + _rowsBefore[segment] * cellExtent;

  int _rows(int segment) => _rowsBefore[segment + 1] - _rowsBefore[segment];
  int _firstChild(int segment) => segment + _rowsBefore[segment];

  /// The row of a child within its segment; -1 for the header.
  int _row(int index, int segment) => index - _firstChild(segment) - 1;

  bool isHeader(int index) => _row(index, segmentOf(index)) < 0;

  double childOffset(int index) {
    final segment = segmentOf(index);
    final row = _row(index, segment);
    return segmentOffset(segment) +
        (row < 0 ? 0 : headerExtent + row * cellExtent);
  }

  double childExtent(int index) => isHeader(index) ? headerExtent : cellExtent;

  /// The index of the first asset of a row child, or of a header's segment.
  int firstAsset(int index) {
    final segment = segmentOf(index);
    final row = _row(index, segment);
    return _assetsBefore[segment] + (row < 0 ? 0 : row * columns);
  }

  /// The assets of a row child; none for a header.
  int assetCount(int index) {
    final segment = segmentOf(index);
    final row = _row(index, segment);
    if (row < 0) return 0;
    final left =
        _assetsBefore[segment + 1] - _assetsBefore[segment] - row * columns;
    return left < columns ? left : columns;
  }

  int _segmentOfAsset(int asset) =>
      _last(segmentCount, (s) => _assetsBefore[s] <= asset);

  /// The first asset of a segment and the one after its last.
  (int, int) assetsOf(int segment) =>
      (_assetsBefore[segment], _assetsBefore[segment + 1]);

  /// The offset of the row of [asset].
  double assetOffset(int asset) {
    final segment = _segmentOfAsset(asset);
    return segmentOffset(segment) +
        headerExtent +
        (asset - _assetsBefore[segment]) ~/ columns * cellExtent;
  }

  int assetColumn(int asset) =>
      (asset - _assetsBefore[_segmentOfAsset(asset)]) % columns;

  /// The asset at [offset] in [column], and whether a cell is there; if not,
  /// the nearest: a header's first, or a row's last.
  (int, bool) assetAt(double offset, int column) {
    final index = childAt(offset);
    final count = assetCount(index);
    return (
      firstAsset(index) + math.max(0, math.min(column, count - 1)),
      column < count,
    );
  }

  int segmentOf(int index) =>
      _last(segmentCount, (s) => _firstChild(s) <= index);

  /// The segment at [offset], in O(log S).
  int segmentAt(double offset) =>
      _last(segmentCount, (s) => segmentOffset(s) <= offset + _epsilon);

  /// The child at [offset]; a boundary belongs to the child that starts there.
  int childAt(double offset) {
    if (segmentCount == 0) return 0;
    final segment = segmentAt(offset);
    final within = offset - segmentOffset(segment) - headerExtent;
    if (within < -_epsilon) return _firstChild(segment);
    final row = (within / cellExtent + _epsilon).floor();
    final rows = _rows(segment);
    return _firstChild(segment) + 1 + (row < rows ? row : rows - 1);
  }

  static const _epsilon = 1e-6;

  /// The largest of 0 … count - 1 that passes [test], which holds for a prefix.
  static int _last(int count, bool Function(int) test) {
    var low = 0, high = count - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (test(mid)) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
