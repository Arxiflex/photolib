import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/registry.dart';

/// The version of the face recognition notice this app shows (ADR-0389), which
/// the server's `FaceService` asks for too: a notice that changes in meaning
/// raises it, and faces stop being found until the user agrees to the new one.
const faceNotice = 1;

/// The model that finds faces: the registry's first face detector.
final RegistryModel faceDetector = registry.firstWhere(
  (m) => m.task == 'face_detection',
);

/// The model that describes them: SFace, or with [id] another face embedding
/// of the registry, such as the optional AuraFace.
RegistryModel faceEmbedder([String id = 'sface']) => registry.firstWhere(
  (m) => m.task == 'face_embedding' && m.id == id,
  orElse: () => registry.firstWhere((m) => m.task == 'face_embedding'),
);

/// The file of [model] that runs on [target], if any.
RegistryFile? faceFile(RegistryModel model, String target) =>
    model.files.where((f) => f.targets.contains(target)).firstOrNull;

const _log = Logger('photolib.faces');

/// Finding faces on this device (ADR-0389): nothing is downloaded or run
/// until the user has agreed to the notice, and everything stops when they
/// withdraw. Once they agree the models download as the search model does
/// (from their server, else the registry's mirrors, on an unmetered network
/// unless allowed), then run in the data isolate as the device's gates let
/// them.
class OnDeviceFaces extends Notifier<MlStatus> {
  MlStatus _status = (phase: MlPhase.off, progress: 0);
  MlHost? _host;
  Future<void>? _installing;
  Replica? _running;

  @override
  MlStatus build() {
    final settings = ref.watch(settingsProvider);
    if (settings.faceNotice != faceNotice) {
      if (_running case final db?) _host?.stopFaces(db);
      _running = null;
      return _status = (phase: MlPhase.off, progress: 0);
    }
    final hosted = ref.watch(mlHostProvider);
    final host = _host = hosted.value;
    if (decoderMissing(hosted)) {
      return _status = (phase: MlPhase.noDecoder, progress: 0);
    }
    final db = ref.watch(replicaProvider).value;
    final health = ref.watch(deviceHealthProvider).value ?? const {};
    final server = ref.watch(serverProvider).value;
    if (host == null || db == null) return _status;
    final detector = faceFile(faceDetector, host.target);
    final embedder = faceFile(faceEmbedder(settings.faceEmbedder), host.target);
    if (detector == null || embedder == null) {
      return _status = (phase: MlPhase.unavailable, progress: 0);
    }
    if (_running != null) {
      host.hold(db, held: mlHold(health, settings) != null);
      return _status;
    }
    if (_installing == null &&
        !{MlPhase.missing, MlPhase.unavailable}.contains(_status.phase)) {
      if (meteredHold(health, allowMetered: settings.indexAllowMetered)) {
        return _status = (phase: MlPhase.waiting, progress: 0);
      }
      _installing = _install(
        host,
        db,
        server,
        faceEmbedder(settings.faceEmbedder),
        detector,
        embedder,
      ).whenComplete(() => _installing = null);
    }
    return _status;
  }

  void _set(MlPhase phase, [double progress = 0]) {
    if (!ref.mounted) return;
    state = _status = (phase: phase, progress: progress);
  }

  Future<void> _install(
    MlHost host,
    Replica db,
    SavedServer? server,
    RegistryModel embedderModel,
    RegistryFile detector,
    RegistryFile embedder,
  ) async {
    await Future<void>.value();
    _set(MlPhase.downloading);
    final total = detector.size + embedder.size;
    var done = 0;
    try {
      for (final (model, file) in [
        (faceDetector, detector),
        (embedderModel, embedder),
      ]) {
        final installed = await host.install(
          model,
          file,
          server,
          (bytes) => _set(MlPhase.downloading, (done + bytes) / total),
        );
        if (!installed) return _set(MlPhase.missing);
        done += file.size;
      }
    } on Object catch (error) {
      _log.warning('a face model did not install', error: error);
      return _set(MlPhase.unavailable);
    }
    // The user may have withdrawn while the models downloaded.
    if (!ref.mounted || ref.read(settingsProvider).faceNotice != faceNotice) {
      return;
    }
    host.startFaces(
      db,
      detector: faceDetector,
      detectorFile: detector,
      embedder: embedderModel,
      embedderFile: embedder,
      backlog: !host.phone,
    );
    _running = db;
    _set(MlPhase.running);
    ref.invalidateSelf();
  }
}

/// Finding faces on this device, run while the app runs.
final onDeviceFacesProvider = NotifierProvider<OnDeviceFaces, MlStatus>(
  OnDeviceFaces.new,
);
