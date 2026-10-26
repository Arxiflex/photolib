import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/features/viewer/motion.dart'
    if (dart.library.js_interop) 'package:photolib/features/viewer/motion_web.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where a phone's back camera looks (docs/10-client-app.md §4.4), fused
/// from its sensors in device axes (x right, y up the screen, z out of it):
/// the gyroscope turns it at once, less its bias, which it learns while the
/// device is still, and gravity corrects the pitch's drift; with the compass
/// [locked], the magnetic field corrects the yaw towards true heading, else
/// the yaw is relative to where it started.
class Attitude {
  /// Starts looking at [yaw], level until gravity says otherwise.
  new({this.yaw = 0, this.locked = false});

  /// Radians east: of north when [locked], else of where it started.
  double yaw;

  /// Radians above the horizon.
  double get pitch => asin((-_up.$3).clamp(-1.0, 1.0));

  /// Whether the compass sets the yaw.
  bool locked;

  // Up, in device axes: turned by the gyroscope, drawn towards gravity, and
  // whether gravity has said where it is since the sensors started.
  var _up = (0.0, 1.0, 0.0);
  var _known = false;

  // The gyroscope's bias; the sum, count and seconds of its readings since
  // they last stopped holding steady.
  var _bias = (0.0, 0.0, 0.0);
  var _sum = (0.0, 0.0, 0.0);
  var _count = 0;
  var _steady = 0.0;

  // How much of the gap to gravity's and the compass' readings each reading
  // closes: enough to stop drift, too little to shake.
  static const double _pull = 0.02;

  /// Starts again from sensors that stopped: the next gravity sets up.
  void restart() {
    _known = false;
    _count = 0;
  }

  /// A gyroscope reading: radians a second about each axis, for [seconds].
  void turn(double x, double y, double z, double seconds) {
    var (sx, sy, sz) = _sum;
    var c = _count;
    // Readings within 0.01 rad/s of the mean of those before them hold
    // steady.
    if (c == 0 || _length(x - sx / c, y - sy / c, z - sz / c) > 0.01) {
      (sx, sy, sz, c) = (0, 0, 0, 0);
      _steady = 0;
    }
    _sum = (sx + x, sy + y, sz + z);
    _count = c + 1;
    _steady += seconds;
    final (mx, my, mz) = (_sum.$1 / _count, _sum.$2 / _count, _sum.$3 / _count);
    // Steady for half a second under 0.05 rad/s, more than any bias and less
    // than a deliberate turn, the device is still: it reads its bias, and the
    // view rests.
    if (_steady >= 0.5 && _length(mx, my, mz) < 0.05) {
      _bias = (mx, my, mz);
      return;
    }
    final (wx, wy, wz) = (x - _bias.$1, y - _bias.$2, z - _bias.$3);
    final (ux, uy, uz) = _up;
    // A turn about up turns the camera west; up turns the other way.
    yaw -= (wx * ux + wy * uy + wz * uz) * seconds;
    _up = _unit(
      ux - (wy * uz - wz * uy) * seconds,
      uy - (wz * ux - wx * uz) * seconds,
      uz - (wx * uy - wy * ux) * seconds,
    );
  }

  /// An accelerometer reading: the reaction to gravity, up, plus whatever
  /// pushes the device.
  void gravity(double x, double y, double z) {
    final n = _length(x, y, z);
    if (n == 0) return;
    final (ax, ay, az) = (x / n, y / n, z / n);
    final (ux, uy, uz) = _up;
    // Further than 1° from up, a reading is likelier a push than a turn the
    // gyroscope missed: it draws up no faster than one 1° away, 1° a second.
    final gap = _length(ax - ux, ay - uy, az - uz);
    final k = _known ? _pull * min(1, 0.0175 / gap) : 1.0;
    _up = _unit(ux + k * (ax - ux), uy + k * (ay - uy), uz + k * (az - uz));
    _known = true;
  }

  /// A magnetometer reading, which sets the yaw while [locked].
  void field(double x, double y, double z) {
    if (!locked) return;
    final (ux, uy, uz) = _up;
    // East is the field across up, north up across east, as Android's
    // SensorManager.getRotationMatrix has them; the camera looks along -z.
    final (ex, ey, ez) = (y * uz - z * uy, z * ux - x * uz, x * uy - y * ux);
    if (ex == 0 && ey == 0 && ez == 0) return;
    final heading = atan2(-ez, -(ux * ey - uy * ex));
    yaw += _pull * ((heading - yaw + pi) % (2 * pi) - pi);
  }
}

double _length(double x, double y, double z) => sqrt(x * x + y * y + z * z);

(double, double, double) _unit(double x, double y, double z) {
  final n = _length(x, y, z);
  return (x / n, y / n, z / n);
}

/// A device's motion sensors: gyroscope, accelerometer and magnetometer.
typedef MotionSensors = ({
  Stream<GyroscopeEvent> gyroscope,
  Stream<AccelerometerEvent> gravity,
  Stream<MagnetometerEvent> field,
});

/// Opens the phone's or tablet's sensors, every 20 ms; null elsewhere, where
/// the viewer offers no motion control.
final sensorsProvider = Provider<MotionSensors Function()?>(
  (ref) =>
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform)
      ? () => (
          gyroscope: gyroscopeEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ),
          gravity: accelerometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ),
          field: magnetometerEventStream(
            samplingPeriod: SensorInterval.gameInterval,
          ),
        )
      : null,
);

/// Asks for the motion sensors, which a browser may refuse; from a tap.
final motionPermissionProvider = Provider<Future<bool> Function()>(
  (ref) => motionPermission,
);

/// Turns [view] as the device turns, from its sensors (docs/10-client-app.md
/// §4.4): its pitch is the device's, its yaw turns as the device does, by
/// the compass when [locked], so that drags still turn it too; locked to a
/// picture whose middle's heading, [north], is known, it looks where the
/// device does.
class SphereMotion {
  /// Starts turning [view] until [dispose].
  new(this.view, this._sensors, {this.north, this.onLost}) {
    running = true;
  }

  /// The view it turns.
  final ValueNotifier<SphereView> view;

  /// The compass heading of the middle of the picture, in radians east of
  /// north (GPano's PoseHeadingDegrees), if known.
  final double? north;

  /// Called when the gyroscope fails, as where the device has none.
  final VoidCallback? onLost;

  final MotionSensors _sensors;
  final _attitude = Attitude();
  var _subscriptions = const <StreamSubscription<Object>>[];
  DateTime? _last;
  double _yaw = 0;

  // Readings each sensor gives first, which may be stale or unsettled.
  static const int _warmUp = 5;

  /// Whether the compass sets the yaw.
  bool get locked => _attitude.locked;
  set locked(bool locked) => _attitude.locked = locked;

  /// Whether it reads the sensors: off while the app or the viewer is away,
  /// on again from the view as it is then.
  bool get running => _subscriptions.isNotEmpty;
  set running(bool on) {
    if (on == running) return;
    if (!on) return dispose();
    _attitude.restart();
    _last = null;
    _subscriptions = [
      _sensors.gyroscope.skip(_warmUp).listen((e) {
        final last = _last;
        _last = e.timestamp;
        if (last == null) return;
        final seconds = e.timestamp.difference(last).inMicroseconds / 1e6;
        _attitude.turn(e.x, e.y, e.z, seconds);
        _apply();
      }, onError: (Object _) => onLost?.call()),
      _sensors.gravity
          .skip(_warmUp)
          .listen(
            (e) => _attitude.gravity(e.x, e.y, e.z),
            onError: (Object _) {},
          ),
      _sensors.field.skip(_warmUp).listen((e) {
        _attitude.field(e.x, e.y, e.z);
        if (locked && north != null) _apply();
      }, onError: (Object _) {}),
    ];
  }

  void _apply() {
    final (v, north) = (view.value, this.north);
    final yaw = locked && north != null
        ? _attitude.yaw - north
        : v.yaw + _attitude.yaw - _yaw;
    final pitch = _attitude.pitch;
    // Turns under a milliradian, half a pixel through the default lens,
    // wait, so that a resting view rests.
    if ((yaw - v.yaw).abs() < 1e-3 && (pitch - v.pitch).abs() < 1e-3) return;
    view.value = v.copyWith(yaw: yaw, pitch: pitch);
    _yaw = _attitude.yaw;
  }

  /// Stops turning the view.
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions = const [];
  }
}
