import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/viewer/attitude.dart';
import 'package:photolib/features/viewer/sphere.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  const g = 9.81;

  test('turning the upright phone about up turns the view west, about its '
      'side lifts it', () {
    final a = Attitude()..gravity(0, g, 0);
    for (var i = 0; i < 50; i++) {
      a.turn(0, 1, 0, 0.01);
    }
    expect(a.yaw, closeTo(-0.5, 1e-9));
    expect(a.pitch, closeTo(0, 1e-9));
    for (var i = 0; i < 20; i++) {
      a.turn(0.5, 0, 0, 0.01);
    }
    expect(a.pitch, closeTo(0.1, 1e-3));
    // On its side, the phone's x axis is up: the same turns, about y.
    final side = Attitude()
      ..gravity(g, 0, 0)
      ..turn(1, 0, 0, 0.1);
    expect(side.yaw, closeTo(-0.1, 1e-9));
    side.turn(0, -1, 0, 0.1);
    expect(side.pitch, closeTo(0.1, 1e-3));
  });

  test('gravity draws the pitch to where the camera looks, so the '
      "gyroscope's drift never builds up", () {
    final flat = Attitude();
    for (var i = 0; i < 400; i++) {
      flat
        ..turn(0.01, 0, 0, 0.01)
        ..gravity(0, 0, g);
    }
    expect(flat.pitch, closeTo(-pi / 2, 0.02));
  });

  test('with the compass locked the yaw comes to true heading, the nearer '
      'way round; unlocked it stays where it started', () {
    // Upright, the camera facing east: x points south. The field points
    // north and down.
    const north = 20.0;
    const down = 40.0;
    final locked = Attitude(yaw: -3, locked: true)..gravity(0, g, 0);
    final free = Attitude(yaw: -3)..gravity(0, g, 0);
    for (var i = 0; i < 400; i++) {
      locked.field(-north, -down, 0);
      free.field(-north, -down, 0);
    }
    // From -3 rad, past -π to π/2.
    expect((locked.yaw + 2 * pi) % (2 * pi), closeTo(pi / 2, 0.01));
    expect(free.yaw, -3);
  });

  test("with the compass locked a sphere's view looks where the phone does, "
      "from the heading of the picture's middle; unlocked it stays", () async {
    // Upright, facing east, as above; the picture's middle faces south.
    final field = StreamController<MagnetometerEvent>.broadcast();
    final gravity = StreamController<AccelerometerEvent>.broadcast();
    final sensors = (
      gyroscope: const Stream<GyroscopeEvent>.empty(),
      gravity: gravity.stream,
      field: field.stream,
    );
    final at = DateTime(2026);
    Future<SphereView> look({required double north, bool locked = true}) async {
      final view = ValueNotifier(SphereView(yaw: rad(10)));
      final motion = SphereMotion(view, sensors, north: north)..locked = locked;
      gravity.add(AccelerometerEvent(0, g, 0, at));
      for (var i = 0; i < 400; i++) {
        field.add(MagnetometerEvent(-20, -40, 0, at));
      }
      await pumpEventQueue();
      motion.dispose();
      return view.value;
    }

    expect((await look(north: pi)).yaw, closeTo(-pi / 2, 0.02));
    expect((await look(north: pi, locked: false)).yaw, rad(10));
  });

  test('stopped, it reads no sensor; started again, it goes on from the view '
      "as it is, at the phone's pitch, past the sensors' stale readings", () {
    final gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
    final gravity = StreamController<AccelerometerEvent>.broadcast(sync: true);
    final view = ValueNotifier(const SphereView());
    final motion = SphereMotion(view, (
      gyroscope: gyroscope.stream,
      gravity: gravity.stream,
      field: const Stream.empty(),
    ));
    var at = DateTime(2026);
    // Upright, looking [up] radians up, turning left about up at 1 rad/s.
    void turn(int readings, double up) {
      for (var i = 0; i < readings; i++) {
        at = at.add(const Duration(milliseconds: 20));
        gravity.add(AccelerometerEvent(0, g * cos(up), -g * sin(up), at));
        gyroscope.add(GyroscopeEvent(0, cos(up), -sin(up), at));
      }
    }

    // The first five readings count for nothing, the sixth starts the clock.
    turn(31, 0.2);
    final before = view.value;
    expect(before.yaw, closeTo(-0.5, 1e-9));
    expect(before.pitch, closeTo(0.2, 1e-9));
    motion.running = false;
    expect(gyroscope.hasListener || gravity.hasListener, isFalse);
    // A minute later, the phone held higher, the sensors first give what
    // they held when they stopped.
    motion.running = true;
    turn(5, 0.2);
    at = at.add(const Duration(minutes: 1));
    turn(25, 0.4);
    expect(view.value.pitch, closeTo(0.4, 1e-9));
    expect(view.value.yaw - before.yaw, closeTo(-0.48, 1e-9));
    motion.dispose();
  });

  // A raw gyroscope's bias, a few thousandths of a radian a second.
  const bias = (0.004, -0.003, 0.006);
  // Moving the phone [by] metres east, north and up in [seconds]: speeding
  // up, then slowing down.
  V3 Function(double) carried(V3 by, double seconds) => (t) {
    final s = 2 * pi / seconds / seconds * sin(2 * pi * t / seconds);
    return (by.$1 * s, by.$2 * s, by.$3 * s);
  };

  /// The furthest [view] strays, in degrees of yaw or pitch, from where it
  /// was when [move] began.
  double strays(ValueNotifier<SphereView> view, void Function() move) {
    final from = view.value;
    var most = 0.0;
    void look() => most = max(
      most,
      max(
        ((view.value.yaw - from.yaw + pi) % (2 * pi) - pi).abs(),
        (view.value.pitch - from.pitch).abs(),
      ),
    );
    view.addListener(look);
    move();
    view.removeListener(look);
    return most * 180 / pi;
  }

  test('a phone set down on a table, picked up from it, carried forward or '
      'at rest for a minute leaves the view within 1° of where it was', () {
    final strayed = <String, double>{};
    // Each phone is held, or lies still, before it moves.
    for (final (name, phone, before, move)
        in <(String, Phone, void Function(Phone), void Function(Phone))>[
          (
            'set down',
            Phone.flat(bias: bias),
            (p) => p.move(1, hand: true),
            (p) => p
              ..move(0.7, push: carried((0, 0.2, -0.3), 0.7), hand: true)
              // It lands with a knock.
              ..move(0.02, push: (_) => (0, 0, 20), turn: (_) => (0.5, 0, 0))
              ..move(0.02, turn: (_) => (-0.5, 0, 0))
              ..move(60),
          ),
          (
            'picked up',
            Phone.flat(bias: bias),
            (p) => p.move(10),
            (p) => p
              ..move(0.5, push: carried((0, -0.3, 0.4), 0.5), hand: true)
              ..move(60, hand: true),
          ),
          (
            // Taken from a shelf a step forward, which hardly changes how
            // much the accelerometer reads, only where it points.
            'carried forward',
            Phone.upright(bias: bias),
            (p) => p.move(1),
            (p) => p
              ..move(1, push: carried((0, 0.5, 0), 1), hand: true)
              ..move(5, hand: true),
          ),
          (
            'at rest',
            Phone.upright(bias: bias),
            (p) => p.move(1),
            (p) => p.move(60),
          ),
        ]) {
      final view = ValueNotifier(const SphereView());
      final motion = SphereMotion(view, phone.sensors);
      before(phone);
      strayed[name] = strays(view, () => move(phone));
      motion.dispose();
    }
    expect(strayed.values, everyElement(lessThan(1)), reason: '$strayed');
  });

  test("the gyroscope's bias is learnt while the phone is still: 0.01 rad/s "
      'of it turns the view at rest by less than 0.5°, and once it has '
      'settled not at all; a slow turn by hand still turns it all the way', () {
    final phone = Phone.upright(bias: (0, 0.01, 0));
    final view = ValueNotifier(const SphereView());
    final motion = SphereMotion(view, phone.sensors);
    expect(strays(view, () => phone.move(60)), lessThan(0.5));
    var changes = 0;
    view.addListener(() => changes++);
    phone.move(30);
    expect(changes, 0, reason: 'settled');
    // A quarter turn to the left in 30 s, 3° a second.
    final from = view.value.yaw;
    phone
      ..move(30, turn: (_) => (0, 0, pi / 60), hand: true)
      ..move(2, hand: true);
    expect((view.value.yaw - from) * 180 / pi, closeTo(-90, 2));
    motion.dispose();
  });

  test('a phone picked up from the table, raised to look ahead and turned '
      'a quarter to the right turns the view by as much', () {
    final phone = Phone.flat(bias: bias);
    final view = ValueNotifier(const SphereView());
    final motion = SphereMotion(view, phone.sensors);
    phone.move(2);
    expect(view.value.pitch * 180 / pi, closeTo(-90, 1));
    final from = view.value.yaw;
    phone
      ..move(1, turn: (_) => (pi / 2, 0, 0), hand: true)
      ..move(0.5, hand: true);
    expect(view.value.pitch * 180 / pi, closeTo(0, 2));
    phone
      ..move(pi / 2, turn: (_) => (0, 0, -1), hand: true)
      ..move(0.5, hand: true);
    expect((view.value.yaw - from) * 180 / pi, closeTo(90, 2));
    motion.dispose();
  });
}

double rad(double d) => d * pi / 180;

typedef V3 = (double, double, double);

double dot(V3 a, V3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;

/// A phone in a room (x east, y north, z up), its gyroscope and
/// accelerometer read every 20 ms as sensors_plus delivers them: a little
/// noisy, the gyroscope off by [bias].
class Phone {
  new(this._axes, {this.bias = (0, 0, 0)});

  /// On its back, its top to the north.
  new flat({V3 bias = (0, 0, 0)})
    : this([(1, 0, 0), (0, 1, 0), (0, 0, 1)], bias: bias);

  /// Upright, its camera to the north.
  new upright({V3 bias = (0, 0, 0)})
    : this([(1, 0, 0), (0, 0, 1), (0, -1, 0)], bias: bias);

  final V3 bias;

  // Its x, y and z axes, in the room's.
  final List<V3> _axes;
  final _noise = Random(1);
  var _seconds = 0.0;
  final _gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
  final _gravity = StreamController<AccelerometerEvent>.broadcast(sync: true);

  MotionSensors get sensors => (
    gyroscope: _gyroscope.stream,
    gravity: _gravity.stream,
    field: const Stream.empty(),
  );

  /// For [seconds], turns at [turn] radians a second about the room's axes
  /// and speeds up by [push] m/s² along them, at each second from the
  /// start, held by a [hand] that trembles.
  void move(
    double seconds, {
    V3 Function(double t)? turn,
    V3 Function(double t)? push,
    bool hand = false,
  }) {
    for (var i = 0; i < (seconds / 0.02).round(); i++) {
      _seconds += 0.02;
      var w = turn?.call(i * 0.02) ?? (0.0, 0.0, 0.0);
      if (hand) {
        // A hand's tremor near 9 Hz and its sway near 1 Hz.
        double shake(double phase) =>
            0.02 * sin(2 * pi * 9 * _seconds + phase) +
            0.01 * sin(2 * pi * 1.3 * _seconds + 2 * phase);
        w = (w.$1 + shake(0), w.$2 + shake(1), w.$3 + shake(2));
      }
      final k = sqrt(dot(w, w));
      if (k > 0) {
        // Rodrigues' rotation of each axis about w.
        final (kx, ky, kz) = (w.$1 / k, w.$2 / k, w.$3 / k);
        final (c, s) = (cos(k * 0.02), sin(k * 0.02));
        for (final (j, v) in _axes.indexed) {
          final kv = dot((kx, ky, kz), v);
          _axes[j] = (
            v.$1 * c + (ky * v.$3 - kz * v.$2) * s + kx * kv * (1 - c),
            v.$2 * c + (kz * v.$1 - kx * v.$3) * s + ky * kv * (1 - c),
            v.$3 * c + (kx * v.$2 - ky * v.$1) * s + kz * kv * (1 - c),
          );
        }
      }
      final a = push?.call(i * 0.02) ?? (0.0, 0.0, 0.0);
      final up = (a.$1, a.$2, a.$3 + 9.81);
      double noise(double by) => (_noise.nextDouble() * 2 - 1) * by;
      final at = DateTime(2026)
          .add(Duration(microseconds: (_seconds * 1e6).round()));
      _gyroscope.add(
        GyroscopeEvent(
          dot(w, _axes[0]) + bias.$1 + noise(0.003),
          dot(w, _axes[1]) + bias.$2 + noise(0.003),
          dot(w, _axes[2]) + bias.$3 + noise(0.003),
          at,
        ),
      );
      _gravity.add(
        AccelerometerEvent(
          dot(up, _axes[0]) + noise(0.03),
          dot(up, _axes[1]) + noise(0.03),
          dot(up, _axes[2]) + noise(0.03),
          at,
        ),
      );
    }
  }
}
