import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_ml/registry.dart';

/// A host that records what on-device ML asks of it.
class RecordingMlHost implements MlHost {
  /// A host of [target], a phone or not.
  new({this.target = 'linux', this.phone = false, this.platformText = false});

  @override
  final String target;

  @override
  final bool phone;

  @override
  final bool platformText;

  /// What was asked, in order.
  final calls = <String>[];

  /// What [install] does after recording; installs at once by default.
  Future<bool> Function(void Function(int bytes) progress)? installing;

  /// What [listen] was given.
  Future<bool> Function()? background;

  /// What [listen] was given.
  void Function()? stopBackground;

  @override
  Future<bool> install(
    RegistryModel model,
    RegistryFile file,
    SavedServer? server,
    void Function(int bytes) progress,
  ) async {
    calls.add('install ${file.name} from ${server?.name ?? 'mirror'}');
    return await installing?.call(progress) ?? true;
  }

  @override
  void start(
    Replica db,
    RegistryModel model,
    RegistryFile file, {
    required bool backlog,
  }) => calls.add('start ${model.name}${backlog ? ' with backlog' : ''}');

  @override
  void startFaces(
    Replica db, {
    required RegistryModel detector,
    required RegistryFile detectorFile,
    required RegistryModel embedder,
    required RegistryFile embedderFile,
    required bool backlog,
  }) => calls.add(
    'faces ${detector.name} ${embedder.name}${backlog ? ' with backlog' : ''}',
  );

  @override
  void stopFaces(Replica db) => calls.add('faces stop');

  @override
  void stop(Replica db) => calls.add('stop');

  @override
  void startText(
    Replica db,
    List<(RegistryModel, RegistryFile)> models, {
    required bool backlog,
  }) => calls.add(
    'start text ${[for (final (m, _) in models) m.id].join(',')}'
    '${backlog ? ' with backlog' : ''}',
  );

  @override
  void stopText(Replica db) => calls.add('stop text');

  @override
  void interacted(Replica db) => calls.add('interacted');

  @override
  void hold(Replica db, {required bool held}) =>
      calls.add(held ? 'hold' : 'go');

  @override
  Future<void> schedule({required bool on}) async =>
      calls.add('schedule ${on ? 'on' : 'off'}');

  @override
  void listen({
    required Future<bool> Function() background,
    required void Function() stop,
  }) {
    this.background = background;
    stopBackground = stop;
  }
}
