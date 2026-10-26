import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';

/// The timeline's sliver: headers and rows as children, placed by a
/// [TimelineLayout], so a jump anywhere lays out only what it shows. Flutter's
/// own varied-extent list sums the extents before an index, O(n) per lookup.
class SliverTimeline extends SliverMultiBoxAdaptorWidget {
  const SliverTimeline({
    super.key,
    required this.timeline,
    required super.delegate,
  });

  final TimelineLayout timeline;

  @override
  RenderSliverTimeline createRenderObject(BuildContext context) =>
      RenderSliverTimeline(
        childManager: context as SliverMultiBoxAdaptorElement,
        timeline: timeline,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverTimeline renderObject,
  ) => renderObject.timeline = timeline;
}

class RenderSliverTimeline extends RenderSliverFixedExtentBoxAdaptor {
  RenderSliverTimeline({required super.childManager, required this._timeline});

  TimelineLayout _timeline;
  TimelineLayout get timeline => _timeline;
  set timeline(TimelineLayout value) {
    if (identical(value, _timeline)) return;
    _timeline = value;
    markNeedsLayout();
  }

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder get itemExtentBuilder =>
      (index, _) => _timeline.childExtent(index);

  @override
  double indexToLayoutOffset(double itemExtent, int index) =>
      _timeline.childOffset(index);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) =>
      _timeline.childAt(scrollOffset);

  // The last child that starts before scrollOffset.
  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    final index = _timeline.childAt(scrollOffset);
    return index > 0 && _timeline.childOffset(index) >= scrollOffset
        ? index - 1
        : index;
  }

  @override
  double computeMaxScrollOffset(
    SliverConstraints constraints,
    double itemExtent,
  ) => _timeline.extent;

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _timeline.extent;
}
