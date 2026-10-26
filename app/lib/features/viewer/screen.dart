import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The brightness of the app's window, from 0 to 1, which the viewer sets
/// (VIEW-39): Android's window attribute (ViewerChannel.kt), iOS's screen
/// (ThumbnailChannel.swift).
class ScreenBrightness {
  /// The platform's.
  const new();

  static const _channel = MethodChannel('org.photolib/viewer');

  /// The brightness now.
  Future<double> get() async =>
      await _channel.invokeMethod<double>('brightness') ?? 1;

  /// Sets the brightness, or with null gives it back to the system.
  Future<void> set(double? value) =>
      _channel.invokeMethod<void>('setBrightness', value);
}

/// The window's brightness on phones; null where no app sets it.
final screenBrightnessProvider = Provider<ScreenBrightness?>(
  (ref) =>
      !kIsWeb &&
          const {
            TargetPlatform.android,
            TargetPlatform.iOS,
          }.contains(defaultTargetPlatform)
      ? const ScreenBrightness()
      : null,
);
