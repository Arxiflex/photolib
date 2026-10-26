import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/ui/motion.dart';
import 'package:photolib/ui/tokens.dart';

/// A grid of square cells with the gallery's gestures: pinch to change the
/// columns, anchored on the item under the fingers; long press then drag to
/// select a range, scrolling at the edges, and while selecting a long press
/// previews; tap to open, or to toggle while selecting. Single-pointer
/// alternatives (I18N-16): tap and Space toggle, a screen reader's long
/// press selects, and pages offer zoom buttons that step through [levels]
/// with [MediaGrid.step]. The keyboard (docs/17 §5): arrows move a ringed
/// focus cell by cell and row by row, the first to the first cell shown,
/// Shift with them selects on from the last cell toggled, Space toggles and
/// Enter opens; a pointer hides the ring. A rotation keeps the row at the top,
/// and the grid opens at the row of [top].
class MediaGrid extends StatefulWidget {
  /// A grid of [count] cells.
  const new({
    required this.count,
    required this.itemBuilder,
    required this.selection,
    required this.columns,
    required this.levels,
    required this.onColumns,
    this.onOpen,
    this.onPress,
    this.top = 0,
    this.onTop,
    super.key,
  });

  /// How many cells.
  final int count;

  /// What cell `i` shows.
  final IndexedWidgetBuilder itemBuilder;

  /// The items selected, as ranges, so that any number is (VIEW-08).
  final ValueNotifier<Selection> selection;

  /// The current column count, one of [levels] (ascending).
  final int columns;

  /// The column counts a pinch or [step] goes through.
  final List<int> levels;

  /// Called with the column count a pinch chose.
  final ValueChanged<int> onColumns;

  /// Opens a cell.
  final ValueChanged<int>? onOpen;

  /// Called as a pointer goes down on a cell while nothing is selected,
  /// before the tap that may open it.
  final ValueChanged<int>? onPress;

  /// The cell whose row is at the top once the grid has laid out.
  final int top;

  /// Called with the first cell of the row at the top when that changes.
  final ValueChanged<int>? onTop;

  /// The level [by] steps from [columns], stopping at the ends.
  static int step(List<int> levels, int columns, int by) =>
      levels[(levels.indexOf(columns) + by).clamp(0, levels.length - 1)];

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

typedef _Anchor = ({int index, double fraction, double y});

class _MediaGridState extends State<MediaGrid>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final _ticker = createTicker(_autoScroll);
  Size _size = Size.zero;

  var _scale = 1.0;
  Offset _focal = Offset.zero;
  _Anchor? _pinched;

  final _focus = FocusNode(debugLabel: 'grid', skipTraversal: true);

  /// The focus of each cell an arrow went to; others have their own.
  final _cells = <int, FocusNode>{};

  /// The focused cell, ringed.
  int? _cursor;

  /// The last cell toggled, where Shift and an arrow select from.
  int? _last;

  int? _dragAnchor;
  Selection _dragBase = Selection.none;
  var _adding = true;
  // While selecting, the item a long press previews, and what ends that.
  int? _peeked;
  VoidCallback? _unpeek;
  Offset _pointer = Offset.zero;
  Duration _lastTick = Duration.zero;

  int? _top;

  double get _extent => _size.width / widget.columns;
  // i18n-ok: hit-testing mirrors the columns as the grid lays them out
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final top = (_scroll.offset / _extent).floor() * widget.columns;
      if (top != _top) widget.onTop?.call(_top = top);
    });
  }

  @override
  void dispose() {
    _endPeek();
    _ticker.dispose();
    _scroll.dispose();
    _focus.dispose();
    for (final node in _cells.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The item under [point] in the grid's box, and how far down it.
  _Anchor _at(Offset point) {
    final y = point.dy + (_scroll.hasClients ? _scroll.offset : 0);
    final row = y ~/ _extent;
    var column = point.dx.clamp(0, _size.width - 1) ~/ _extent;
    if (_rtl) column = widget.columns - 1 - column;
    return (
      index: (row * widget.columns + column).clamp(0, widget.count - 1),
      fraction: (y - row * _extent) / _extent,
      y: point.dy,
    );
  }

  @override
  void didUpdateWidget(MediaGrid old) {
    super.didUpdateWidget(old);
    if (old.columns == widget.columns || !_scroll.hasClients) return;
    // Columns changed by a pinch keep the item under the fingers; by anything
    // else, the item at the top.
    final oldExtent = _size.width / old.columns;
    final top = _scroll.offset ~/ oldExtent;
    final anchor =
        _pinched ??
        (
          index: top * old.columns,
          fraction: _scroll.offset / oldExtent - top,
          y: 0.0,
        );
    _pinched = null;
    final rows = (widget.count / widget.columns).ceil();
    final offset =
        (anchor.index ~/ widget.columns + anchor.fraction) * _extent - anchor.y;
    _scroll.position.correctPixels(
      offset.clamp(0, math.max(0, rows * _extent - _size.height)),
    );
  }

  void _select(int index) {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final (start, end) = (math.min(anchor, index), math.max(anchor, index) + 1);
    widget.selection.value = _adding
        ? _dragBase.add(start, end)
        : _dragBase.remove(start, end);
  }

  void _toggle(int index) {
    widget.selection.value = widget.selection.value.toggle(index);
    _last = index;
  }

  /// Moves the focus [dx] cells along or [dy] rows down; [extend] selects
  /// from the last cell toggled.
  void _arrow(int dx, int dy, {bool extend = false}) {
    final (count, columns) = (widget.count, widget.columns);
    if (count == 0) return;
    final from = _cursor;
    var to =
        from ??
        math.min((_scroll.offset / _extent).ceil() * columns, count - 1);
    if (from != null && dx != 0) {
      to = (from + (_rtl ? -dx : dx)).clamp(0, count - 1);
    } else if (from != null) {
      to = from + dy * columns;
      // A row down that lacks the column ends at its last cell.
      final lastRow = from ~/ columns == (count - 1) ~/ columns;
      if (to >= count && !lastRow) to = count - 1;
      if (to < 0 || to >= count) to = from;
    }
    if (extend) {
      final anchor = _last ??= from ?? to;
      widget.selection.value = widget.selection.value.add(
        math.min(anchor, to),
        math.max(anchor, to) + 1,
      );
    }
    // Scrolled into view: a cell not built yet takes the focus once it is.
    final top = to ~/ columns * _extent;
    final offset = _scroll.offset;
    if (top < offset || top + _extent > offset + _size.height) {
      _scroll.jumpTo(top < offset ? top : top + _extent - _size.height);
    }
    // Ringed at once: the next arrow may come before the focus moves.
    setState(() => _cursor = to);
    _cells.putIfAbsent(to, FocusNode.new).requestFocus();
  }

  /// Scrolls while the pointer is within a cell's half of an edge, faster the
  /// closer it is.
  void _autoScroll(Duration elapsed) {
    final zone = _extent / 2;
    final depth = _pointer.dy < zone
        ? _pointer.dy - zone
        : _pointer.dy > _size.height - zone
        ? _pointer.dy - (_size.height - zone)
        : 0.0;
    final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (depth == 0) return;
    final position = _scroll.position;
    _scroll.jumpTo(
      (position.pixels + depth / zone * _size.height * seconds).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _select(_at(_pointer).index);
  }

  void _pinchStart(ScaleStartDetails details) =>
      _pinched = _at(details.localFocalPoint);

  void _pinchUpdate(ScaleUpdateDetails details) => setState(() {
    _focal = details.localFocalPoint;
    _scale = details.scale.clamp(
      widget.columns / widget.levels.last,
      widget.columns / widget.levels.first,
    );
  });

  void _pinchEnd(ScaleEndDetails details) {
    final columns = _nearest(widget.columns / _scale);
    final start = _pinched;
    setState(() => _scale = 1);
    _pinched = null;
    if (columns == widget.columns || start == null) return;
    _pinched = (index: start.index, fraction: start.fraction, y: _focal.dy);
    widget.onColumns(columns);
  }

  /// Selects from where a long press went down, or while selecting
  /// previews the item there until the press moves to another.
  void _dragStart(LongPressStartDetails details) {
    _pointer = details.localPosition;
    final index = _at(_pointer).index;
    if (widget.selection.value.isEmpty) return _selectFrom(index);
    _peeked = index;
    _unpeek = peek(context, widget.itemBuilder(context, index));
  }

  void _selectFrom(int index) {
    _dragAnchor = index;
    _dragBase = widget.selection.value;
    _adding = !_dragBase.contains(index);
    _select(index);
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _endPeek() {
    _unpeek?.call();
    _unpeek = _peeked = null;
  }

  void _dragUpdate(LongPressMoveUpdateDetails details) {
    _pointer = details.localPosition;
    final index = _at(_pointer).index;
    if (_peeked case final peeked? when peeked != index) {
      _endPeek();
      _selectFrom(peeked);
    }
    if (_dragAnchor != null) _select(index);
  }

  void _dragEnd([LongPressEndDetails? _]) {
    _endPeek();
    _ticker.stop();
    _dragAnchor = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // A rotation keeps the row at the top where it was.
      if (_size.width > 0 &&
          constraints.maxWidth != _size.width &&
          _scroll.hasClients) {
        final rows = _scroll.offset / _extent;
        _size = constraints.biggest;
        final extent = (widget.count / widget.columns).ceil() * _extent;
        _scroll.position.correctPixels(
          (rows * _extent).clamp(0, math.max(0, extent - _size.height)),
        );
      }
      if (_size.width == 0 && widget.top > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo(
            math.min(
              widget.top ~/ widget.columns * _extent,
              _scroll.position.maxScrollExtent,
            ),
          );
        });
      }
      _size = constraints.biggest;
      return RawGestureDetector(
        excludeFromSemantics: true,
        gestures: {
          PinchRecognizer:
              GestureRecognizerFactoryWithHandlers<PinchRecognizer>(
                () => PinchRecognizer(debugOwner: this),
                (pinch) => pinch
                  ..onStart = _pinchStart
                  ..onUpdate = _pinchUpdate
                  ..onEnd = _pinchEnd,
              ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(debugOwner: this),
                (press) => press
                  ..onLongPressStart = _dragStart
                  ..onLongPressMoveUpdate = _dragUpdate
                  ..onLongPressEnd = _dragEnd
                  ..onLongPressCancel = _dragEnd,
              ),
        },
        child: ClipRect(
          child: Transform.scale(
            scale: _scale,
            origin: _focal - _size.center(Offset.zero),
            child: ValueListenableBuilder(
              valueListenable: widget.selection,
              builder: (context, selection, _) => _keyboard(
                GridView.builder(
                  controller: _scroll,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: widget.columns,
                  ),
                  itemCount: widget.count,
                  itemBuilder: (context, i) => _cell(context, i, selection),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  /// The arrows, while the grid or a cell has the focus, which a pointer
  /// gives the grid.
  Widget _keyboard(Widget child) => CallbackShortcuts(
    bindings: {
      for (final (key, dx, dy) in const [
        (LogicalKeyboardKey.arrowLeft, -1, 0),
        (LogicalKeyboardKey.arrowRight, 1, 0),
        (LogicalKeyboardKey.arrowUp, 0, -1),
        (LogicalKeyboardKey.arrowDown, 0, 1),
      ])
        for (final shift in const [false, true])
          SingleActivator(key, shift: shift): () =>
              _arrow(dx, dy, extend: shift),
    },
    child: Focus(
      focusNode: _focus,
      child: Listener(
        onPointerDown: (_) => _focus.requestFocus(),
        child: child,
      ),
    ),
  );

  Widget _cell(BuildContext context, int i, Selection selection) {
    final tokens = AppTokens.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final selected = selection.contains(i);
    void toggle() => _toggle(i);
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        onLongPress: toggle,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.space): toggle},
          child: Listener(
            onPointerDown: selection.isEmpty
                ? (_) => widget.onPress?.call(i)
                : null,
            child: InkWell(
              focusNode: _cells[i],
              onFocusChange: (focused) => setState(
                () => _cursor = focused ? i : (_cursor == i ? null : _cursor),
              ),
              onTap: selection.isEmpty ? () => widget.onOpen?.call(i) : toggle,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedPadding(
                    duration: Motion.of(context, Motion.short),
                    curve: Motion.curve,
                    padding: EdgeInsets.all(selected ? tokens.sm : 0),
                    child: widget.itemBuilder(context, i),
                  ),
                  if (!selection.isEmpty)
                    PositionedDirectional(
                      top: tokens.xs,
                      start: tokens.xs,
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: primary,
                      ),
                    ),
                  if (i == _cursor)
                    DecoratedBox(
                      key: const ValueKey('cursor'),
                      decoration: BoxDecoration(
                        border: Border.all(color: primary, width: 3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The level nearest [columns], by ratio rather than difference.
  int _nearest(double columns) => widget.levels.reduce(
    (a, b) =>
        math.log(a / columns).abs() <= math.log(b / columns).abs() ? a : b,
  );
}

/// Shows [child] large over the page, as a long press previews an item
/// while selecting (VIEW-08), until the function returned is called.
VoidCallback peek(BuildContext context, Widget child) {
  final entry = OverlayEntry(
    builder: (context) => IgnorePointer(
      child: ColoredBox(
        key: const ValueKey('peek'),
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.8,
            heightFactor: 0.8,
            child: Center(child: AspectRatio(aspectRatio: 1, child: child)),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  return () => entry
    ..remove()
    ..dispose();
}

/// A scale recognizer that wins at once when a second finger lands, so a
/// pinch never starts a scroll.
class PinchRecognizer extends ScaleGestureRecognizer {
  /// A recognizer for [debugOwner].
  new({super.debugOwner});

  var _pointers = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (++_pointers > 1) resolve(GestureDisposition.accepted);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers = 0;
    super.didStopTrackingLastPointer(pointer);
  }
}
