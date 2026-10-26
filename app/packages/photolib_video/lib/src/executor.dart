import 'plan.dart';

/// An engine that runs [Plan]s: FFmpeg, Media3 or AVFoundation.
abstract interface class Executor {
  Future<SourceInfo> probe(String path);

  /// Writes [plan] to [out], reading each cut's source from [paths] by asset id.
  Future<void> run(Plan plan, Map<String, String> paths, String out);
}
