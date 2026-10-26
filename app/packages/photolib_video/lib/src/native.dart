import 'package:flutter/services.dart';

import 'executor.dart';
import 'plan.dart';

/// Media3 Transformer on Android, AVFoundation on iOS and macOS: the platform code of this plugin, behind one channel.
class NativeExecutor implements Executor {
  static const _channel = MethodChannel('org.photolib.video');

  @override
  Future<SourceInfo> probe(String path) async => SourceInfo.fromJson(
    (await _channel.invokeMapMethod<String, Object?>('probe', path))!,
  );

  @override
  Future<void> run(Plan plan, Map<String, String> paths, String out) =>
      _channel.invokeMethod('execute', {
        'plan': plan.toJson(),
        'paths': paths,
        'out': out,
      });
}
