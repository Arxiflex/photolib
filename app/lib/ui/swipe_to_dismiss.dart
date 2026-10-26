import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// A full-screen page swiped down to close (feature catalogue, UX pattern
/// 11): the content follows the finger and shrinks, the background fades,
/// and it closes past 16 % of the height or on a flick of 0.5 px/ms, else
/// springs back (docs/10 §4.6).
/// Escape and a screen reader's dismiss action close it too (I18N-16). A swipe
/// up past 10 % of the height, or a flick up, calls [onSwipeUp] (pattern 12:
/// swipe up for info). While not [enabled], drags are left to the child.
class SwipeToDismiss extends StatefulWidget {
  const SwipeToDismiss({
    super.key,
    required this.onDismissed,
    this.onSwipeUp,
    this.enabled = true,
    this.mouse = true,
    this.onDrag,
    required this.child,
  });

  final VoidCallback onDismissed;
  final VoidCallback? onSwipeUp;
  final bool enabled;

  /// Whether a mouse's drags swipe it too.
  final bool mouse;

  /// Hears how far down a drag is, 0 to 1 of the height, when the caller
  /// shows it and the background instead.
  final ValueChanged<double>? onDrag;
  final Widget child;

  @override
  State<SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<SwipeToDismiss>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this)
    ..addListener(() => widget.onDrag?.call(_progress));
  var _dragged = 0.0;
  var _height = 1.0;

  double get _progress => (_offset.value / _height).clamp(0.0, 1.0);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details, double height) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_offset.value > height * 0.16 || velocity > 500) {
      widget.onDismissed();
      return;
    }
    if (_dragged < -height * 0.1 || velocity < -700) widget.onSwipeUp?.call();
    _offset.animateTo(
      0,
      duration: Motion.of(context, Motion.short),
      curve: Motion.curve,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = _height = constraints.maxHeight;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onDismissed,
        },
        child: Focus(
          autofocus: true,
          child: Semantics(
            onDismiss: widget.onDismissed,
            child: GestureDetector(
              supportedDevices: widget.mouse
                  ? null
                  : {...PointerDeviceKind.values}
                        .difference({PointerDeviceKind.mouse}),
              onVerticalDragStart: !widget.enabled
                  ? null
                  : (_) => _dragged = _offset.value,
              onVerticalDragUpdate: !widget.enabled
                  ? null
                  : (details) {
                      _dragged += details.delta.dy;
                      _offset.value = math.max(0, _dragged);
                    },
              onVerticalDragEnd: !widget.enabled
                  ? null
                  : (details) => _end(details, height),
              child: widget.onDrag != null
                  ? widget.child
                  : AnimatedBuilder(
                      animation: _offset,
                      builder: (context, child) => ColoredBox(
                        color: Theme.of(context).colorScheme.scrim
                            .withValues(alpha: 1 - _progress),
                        child: Transform.translate(
                          offset: Offset(0, _offset.value),
                          child: Transform.scale(
                            scale: 1 - _progress / 2,
                            child: child,
                          ),
                        ),
                      ),
                      child: widget.child,
                    ),
            ),
          ),
        ),
      );
    },
  );
}
