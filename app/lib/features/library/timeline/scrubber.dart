import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/thumbnails.dart';
import 'package:photolib/l10n/formats.dart';

/// The scrubber (docs/10 §3.3): dragging maps the thumb straight to an offset.
/// Cached tiles show during the drag; decodes wait only while the thumb moves
/// a screen faster than one finishes, and start once it slows or is held.
class TimelineScrubber extends StatefulWidget {
  /// A scrubber that scrolls [controller] over [layout].
  const new({
    required this.controller,
    required this.layout,
    required this.buckets,
    required this.thumbnails,
    required this.formats,
    required this.label,
    super.key,
  });

  /// Each month's offset and its height against the tallest month's, the
  /// weight of its tick (docs/10 §3.3).
  static List<(double, double)> ticks(
    TimelineLayout layout,
    TimelineBuckets segments,
  ) {
    final undated = segments.days.isNotEmpty && segments.days.last == 0;
    final starts = [
      for (final (_, segment) in segments.months) layout.segmentOffset(segment),
      layout.segmentOffset(layout.segmentCount - (undated ? 1 : 0)),
    ];
    var tallest = 0.0;
    for (var i = 1; i < starts.length; i++) {
      tallest = math.max(tallest, starts[i] - starts[i - 1]);
    }
    return [
      for (var i = 0; i < starts.length - 1; i++)
        (starts[i], (starts[i + 1] - starts[i]) / tallest),
    ];
  }

  /// The column it takes at the end of the timeline while not dragged.
  static const width = 32.0;

  /// The timeline's scroll position, which a drag jumps.
  final ScrollController controller;

  /// The timeline's geometry.
  final TimelineLayout layout;

  /// The segments shown, whose months and years it marks.
  final TimelineBuckets buckets;

  /// The decodes it pauses while the thumb moves fast.
  final Thumbnails thumbnails;

  /// How it names months and years.
  final Formats formats;

  /// What a screen reader calls it.
  final String label;

  @override
  State<TimelineScrubber> createState() => _TimelineScrubberState();
}

class _TimelineScrubberState extends State<TimelineScrubber> {
  static const _thumb = 48.0;
  // About as long as a decode at the tiers cells use.
  static const _decode = Duration(milliseconds: 100);
  var _dragging = false;
  int? _year;
  final _clock = Stopwatch()..start();
  (Duration, double) _moved = (Duration.zero, 0.0);
  Timer? _still;

  @override
  void dispose() {
    _still?.cancel();
    super.dispose();
  }

  double get _max => widget.controller.position.maxScrollExtent;

  int? get _month {
    final day = widget.buckets.day(
      widget.layout.segmentAt(widget.controller.offset),
    );
    return day == null ? null : day.year * 100 + day.month;
  }

  // A haptic tick at each year the thumb crosses.
  void _jump(double y, double height) {
    final offset =
        ((y - _thumb / 2) / (height - _thumb)).clamp(0.0, 1.0) * _max;
    widget.controller.jumpTo(offset);
    _pace(offset);
    final month = _month;
    final year = month == null ? null : month ~/ 100;
    if (_year != null && year != _year) {
      unawaited(HapticFeedback.selectionClick());
    }
    _year = year;
  }

  void _pace(double offset) {
    final now = _clock.elapsed;
    final (then, from) = _moved;
    _moved = (now, offset);
    final fast =
        (offset - from).abs() * _decode.inMicroseconds >=
        widget.controller.position.viewportDimension *
            (now - then).inMicroseconds;
    _still?.cancel();
    widget.thumbnails.paused = fast;
    if (fast) _still = Timer(_decode, () => widget.thumbnails.paused = false);
  }

  void _drag(bool dragging) {
    _still?.cancel();
    widget.thumbnails.paused = false;
    _moved = (_clock.elapsed, widget.controller.offset);
    _year = null;
    setState(() => _dragging = dragging);
  }

  /// The month [by] months older than the one at the top, and its newest
  /// segment, as a screen reader adjusts the slider.
  (int, int) _step(int by) {
    final months = widget.buckets.months;
    final at = months.indexWhere((m) => m.$1 <= (_month ?? 0));
    return months[((at < 0 ? months.length : at) + by).clamp(
      0,
      months.length - 1,
    )];
  }

  String _named((int, int) month) =>
      widget.formats.month(DateTime(month.$1 ~/ 100, month.$1 % 100));

  void _go((int, int) month) => widget.controller.jumpTo(
    widget.layout.segmentOffset(month.$2).clamp(0, _max),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) {
            _drag(true);
            _jump(d.localPosition.dy, height);
          },
          onVerticalDragUpdate: (d) => _jump(d.localPosition.dy, height),
          onVerticalDragEnd: (_) => _drag(false),
          onVerticalDragCancel: () => _drag(false),
          child: SizedBox(
            width: _dragging ? 200 : TimelineScrubber.width,
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                if (!widget.controller.hasClients || _max <= 0) {
                  return const SizedBox.shrink();
                }
                final offset = widget.controller.offset;
                final top = offset.clamp(0, _max) / _max * (height - _thumb);
                final day = widget.buckets.day(widget.layout.segmentAt(offset));
                final month = day == null ? '' : widget.formats.month(day);
                return Semantics(
                  slider: true,
                  label: widget.label,
                  value: month,
                  increasedValue: _named(_step(1)),
                  decreasedValue: _named(_step(-1)),
                  onIncrease: () => _go(_step(1)),
                  onDecrease: () => _go(_step(-1)),
                  child: Stack(
                    children: [
                      if (_dragging) ...[
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _Ticks(
                              TimelineScrubber.ticks(
                                widget.layout,
                                widget.buckets,
                              ),
                              _max,
                              colors.outline,
                              Directionality.of(context),
                            ),
                          ),
                        ),
                        ..._years(height, colors),
                      ],
                      PositionedDirectional(
                        top: top,
                        end: 4,
                        child: Row(
                          children: [
                            if (_dragging && day != null)
                              _Bubble(month, colors.inverseSurface),
                            Container(
                              width: 24,
                              height: _thumb,
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Year labels where each year starts, as long as they do not overlap.
  List<Widget> _years(double height, ColorScheme colors) {
    final labels = <Widget>[];
    var next = 0.0;
    for (final (year, segment) in widget.buckets.years) {
      final top =
          widget.layout.segmentOffset(segment).clamp(0, _max) /
          _max *
          (height - _thumb);
      if (top < next) continue;
      next = top + 24;
      labels.add(
        PositionedDirectional(
          top: top,
          end: 36,
          child: Text(
            widget.formats.year(DateTime(year)),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }
    return labels;
  }
}

/// The scrubber's month ticks, centred under its thumb, longer for taller
/// months.
class _Ticks extends CustomPainter {
  new(this.ticks, this.max, this.color, this.direction);

  final List<(double, double)> ticks;
  final double max;
  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    const thumb = _TimelineScrubberState._thumb;
    // i18n-ok: the thumb's column
    final x = direction == TextDirection.rtl ? 16.0 : size.width - 16;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (final (offset, weight) in ticks) {
      final y = offset.clamp(0, max) / max * (size.height - thumb) + thumb / 2;
      final half = 2 + 8 * weight;
      canvas.drawLine(Offset(x - half, y), Offset(x + half, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Ticks old) =>
      old.max != max || old.color != color || !listEquals(old.ticks, ticks);
}

class _Bubble extends StatelessWidget {
  const new(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsetsDirectional.only(end: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
    ),
  );
}
