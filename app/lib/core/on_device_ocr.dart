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

const _log = Logger('photolib.ocr');

/// The detector and recognisers on-device OCR runs (ADR-0388), the registry's
/// text models.
final List<RegistryModel> ocrRegistry = [
  for (final task in ['text_detection', 'text_recognition'])
    ...registry.where((m) => m.task == task),
];

/// The OCR models' file for [target], each model's first, in the registry's
/// order; empty where the registry has none for it (the phones).
List<(RegistryModel, RegistryFile)> ocrFiles(String target) => [
  for (final model in ocrRegistry)
    if (model.files.where((f) => f.targets.contains(target)).firstOrNull
        case final file?)
      (model, file),
];

/// On-device OCR (ADR-0388): once the user agrees, the text models download,
/// on an unmetered network unless allowed, from the user's server or,
/// standalone, the registry's mirrors, then read the text of the device's
/// photos in the data isolate as the device's gates let it. Only where the
/// registry has the models for the platform: the desktops. Phones read with
/// the platform's own OCR (ML Kit, Vision), which needs no download.
class OnDeviceOcr extends Notifier<MlStatus> {
  MlStatus _status = (phase: MlPhase.off, progress: 0);
  MlHost? _host;
  Future<void>? _installing;
  Replica? _running;

  @override
  MlStatus build() {
    final settings = ref.watch(settingsProvider);
    if (!settings.indexText) {
      if (_running case final db?) _host?.stopText(db);
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
    final files = ocrFiles(host.target);
    if (files.isEmpty && !host.platformText) {
      return (phase: MlPhase.unavailable, progress: 0);
    }
    if (_running != null) {
      host.hold(db, held: mlHold(health, settings) != null);
      return _status;
    }
    if (host.platformText) {
      // The platform reads with what it has: nothing to download.
      host.startText(db, const [], backlog: !host.phone);
      _running = db;
      host.hold(db, held: mlHold(health, settings) != null);
      return _status = (phase: MlPhase.running, progress: 0);
    }
    // A failed download waits for the user to ask again, or a restart.
    if (_installing == null &&
        !{MlPhase.missing, MlPhase.unavailable}.contains(_status.phase)) {
      if (meteredHold(health, allowMetered: settings.indexAllowMetered)) {
        return _status = (phase: MlPhase.waiting, progress: 0);
      }
      _installing = _install(
        host,
        db,
        files,
        server,
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
    List<(RegistryModel, RegistryFile)> files,
    SavedServer? server,
  ) async {
    await Future<void>.value();
    _set(MlPhase.downloading);
    final total = files.fold<int>(0, (sum, f) => sum + f.$2.size);
    var done = 0;
    try {
      for (final (model, file) in files) {
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
      _log.warning('the text models did not install', error: error);
      return _set(MlPhase.unavailable);
    }
    if (!ref.mounted) return;
    host.startText(db, files, backlog: !host.phone);
    _running = db;
    _set(MlPhase.running);
    // A rebuild applies the device's gates to what now runs.
    ref.invalidateSelf();
  }
}

/// On-device OCR, run while the app runs.
final onDeviceOcrProvider = NotifierProvider<OnDeviceOcr, MlStatus>(
  OnDeviceOcr.new,
);
