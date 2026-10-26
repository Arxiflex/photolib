import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device's battery, power saving, heat, memory and network: Android's
/// DeviceHealth.kt, the Apple runners' DeviceHealth.swift.
const deviceHealthChannel = MethodChannel('org.photolib/device_health');

/// What holds background work back (docs/09-ml-and-search.md §3.4).
enum Hold {
  /// A thermal status above Android's moderate (Apple's fair), or the battery
  /// above 42 °C.
  heat,

  /// Battery saver, Low Power Mode.
  powerSaving,

  /// No charger, where work must charge (on-device indexing's option).
  charger,

  /// A battery below its threshold without a charger.
  battery,
}

/// What holds background work back on a device in [state], the first [Hold]
/// in their order, or null when nothing does: heat always; power saving
/// unless [allowSaver]; no charger with [chargingOnly]; else a battery below
/// [battery] percent.
Hold? backgroundHold(
  Map<Object?, Object?> state, {
  bool chargingOnly = false,
  int battery = 20,
  bool allowSaver = false,
}) {
  final charging = state['charging'] == true;
  if ((state['thermal'] as int? ?? 0) > 2 ||
      (state['temperature'] as num? ?? 0) > 42) {
    return Hold.heat;
  }
  if (!allowSaver && state['powerSaving'] == true) return Hold.powerSaving;
  if (chargingOnly && !charging) return Hold.charger;
  if (!charging && (state['battery'] as int? ?? 100) < battery) {
    return Hold.battery;
  }
  return null;
}

/// Whether a device in [state] has less than 4 GB of RAM, where on-device ML
/// keeps to new captures and uses synced results (design 09 §3.4): a 4 GB
/// phone reports a little less than 4e9 bytes, its kernel's share.
bool liteMode(Map<Object?, Object?> state) =>
    (state['memory'] as int? ?? 1 << 40) < 3500000000;

/// Whether downloads for on-device ML wait for an unmetered network.
bool meteredHold(Map<Object?, Object?> state, {bool allowMetered = false}) =>
    !allowMetered && state['metered'] == true;

/// Gives [report] the device's state at once and every minute, on Android,
/// iOS and macOS. Elsewhere nothing holds background work back, and this
/// returns null.
Timer? watchDeviceHealth(void Function(Map<Object?, Object?> state) report) {
  if (kIsWeb ||
      !const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform)) {
    return null;
  }
  Future<void> ask() async {
    try {
      final state = await deviceHealthChannel.invokeMapMethod('state');
      if (state != null) report(state);
    } on MissingPluginException {
      // An engine without the runner's channels, as in widget tests.
    }
  }

  unawaited(ask());
  return Timer.periodic(const Duration(minutes: 1), (_) => ask());
}

/// The device's state, as [watchDeviceHealth] reports it; never on a device
/// without the channel.
final deviceHealthProvider = StreamProvider<Map<Object?, Object?>>((ref) {
  final states = StreamController<Map<Object?, Object?>>();
  final timer = watchDeviceHealth(states.add);
  ref.onDispose(() {
    timer?.cancel();
    unawaited(states.close());
  });
  return states.stream;
});
