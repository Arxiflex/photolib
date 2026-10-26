import 'dart:async';

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter/gestures.dart';

/// One-finger zoom (VIEW-39): a tap, then a second press where it ended
/// within the double tap's time, dragged past the platform's touch slop. A
/// second press that does not move leaves the double tap to its recognizer;
/// one that moves, the first tap to none, which its tap handler asks
/// [pressing].
class OneFingerZoom extends OneSequenceGestureRecognizer {
  /// A recognizer that zooms while [enabled].
  new({super.debugOwner});

  /// Called with where on the screen the second press went down, once it
  /// drags.
  ValueChanged<Offset>? onStart;

  /// Called with how far the second press has moved down since, up being
  /// negative.
  ValueChanged<double>? onUpdate;

  /// Whether it zooms; while not, it lets every pointer pass.
  bool enabled = true;

  // Where the last tap ended, while a second press may follow it.
  Offset? _tapped;
  Timer? _timer;
  // Where each first press went down, until it is a tap or moves away.
  final _pressed = <int, Offset>{};
  Offset? _down;
  var _zooming = false;

  /// Whether a second press is down.
  bool get pressing => _down != null;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      enabled && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final tapped = _tapped;
    if (tapped != null && (event.position - tapped).distance < kDoubleTapSlop) {
      _forget();
      _down = event.position;
      startTrackingPointer(event.pointer, event.transform);
    } else {
      _pressed[event.pointer] = event.position;
      GestureBinding.instance.pointerRouter.addRoute(event.pointer, _first);
    }
  }

  void _first(PointerEvent event) {
    final moved =
        event is PointerMoveEvent &&
        (event.position - (_pressed[event.pointer] ?? event.position))
                .distance >
            computeHitSlop(event.kind, gestureSettings);
    if (!moved && event is! PointerUpEvent && event is! PointerCancelEvent) {
      return;
    }
    _pressed.remove(event.pointer);
    GestureBinding.instance.pointerRouter.removeRoute(event.pointer, _first);
    if (event is PointerUpEvent) {
      _forget();
      _tapped = event.position;
      _timer = Timer(kDoubleTapTimeout, _forget);
    }
  }

  void _forget() {
    _timer?.cancel();
    _tapped = null;
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down ?? event.position;
    if (event is PointerMoveEvent) {
      if (!_zooming &&
          (event.position - down).distance >
              computeHitSlop(event.kind, gestureSettings)) {
        _zooming = true;
        resolve(GestureDisposition.accepted);
        onStart?.call(down);
      }
      if (_zooming) onUpdate?.call(event.position.dy - down.dy);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_zooming) resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _zooming = false;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _zooming = false;
    _down = null;
  }

  @override
  void dispose() {
    _forget();
    for (final pointer in _pressed.keys) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, _first);
    }
    super.dispose();
  }

  @override
  String get debugDescription => 'one-finger zoom';
}

/// A vertical drag that starts only where [allowed] says, in the local
/// coordinates of its detector, and counts the slop it moved first.
class SideDrag extends VerticalDragGestureRecognizer {
  /// A drag from where [allowed].
  new({required this.allowed, super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  /// Whether a drag may start at a point.
  final bool Function(Offset local) allowed;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      allowed(event.localPosition) && super.isPointerAllowed(event);
}
