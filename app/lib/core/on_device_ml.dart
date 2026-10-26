import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/ml.dart'
    if (dart.library.js_interop) 'package:photolib/core/ml_web.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';
import 'package:photolib_ml/registry.dart';

/// What on-device ML needs of the device (ADR-0278): the native app's is in
/// ml.dart; browsers have none (design 09 §3.3).
abstract interface class MlHost {
  /// The registry's name of this platform, such as `android`.
  String get target;

  /// Whether this is a phone, which indexes only new captures in the
  /// foreground and its backlog in the OS's background tasks.
  bool get phone;

  /// Whether the platform reads text itself (Google ML Kit, Apple Vision),
  /// which needs no models (ADR-0388).
  bool get platformText;

  /// Installs [file] of [model] from [server], else from the registry's
  /// mirrors, telling [progress] the bytes there; false when the server has
  /// not installed it.
  Future<bool> install(
    RegistryModel model,
    RegistryFile file,
    SavedServer? server,
    void Function(int bytes) progress,
  );

  /// Runs [file] of [model] on [db]'s photos in its data isolate, past the new
  /// captures with [backlog].
  void start(
    Replica db,
    RegistryModel model,
    RegistryFile file, {
    required bool backlog,
  });

  /// Finds faces on [db]'s photos in its data isolate with [detector] and
  /// [embedder] (ADR-0389); the caller does so only for a user who agreed.
  void startFaces(
    Replica db, {
    required RegistryModel detector,
    required RegistryFile detectorFile,
    required RegistryModel embedder,
    required RegistryFile embedderFile,
    required bool backlog,
  });

  /// Stops what [startFaces] started.
  void stopFaces(Replica db);

  /// Stops what [start] started.
  void stop(Replica db);

  /// Reads the text of [db]'s photos in its data isolate with the OCR
  /// [models] installed, or with the platform's own recognition where
  /// [platformText], past the new captures with [backlog] (ADR-0388).
  void startText(
    Replica db,
    List<(RegistryModel, RegistryFile)> models, {
    required bool backlog,
  });

  /// Stops what [startText] started.
  void stopText(Replica db);

  /// The user scrolls or edits: what [start] started waits.
  void interacted(Replica db);

  /// Holds on-device ML back, or lets it go.
  void hold(Replica db, {required bool held});

  /// Asks the OS to run the backlog in the background, or no longer.
  Future<void> schedule({required bool on});

  /// Has the OS's background task run [background], which says whether more
  /// is left, and end it early with [stop].
  void listen({
    required Future<bool> Function() background,
    required void Function() stop,
  });
}

/// The device's host; null in browsers, and in tests unless they fake one.
final mlHostProvider = FutureProvider<MlHost?>((ref) => mlHost());

/// Where on-device ML is.
enum MlPhase {
  /// The user has not asked for it.
  off,

  /// The model waits for an unmetered network.
  waiting,

  /// The model downloads.
  downloading,

  /// The user's server has not installed the model.
  missing,

  /// It cannot run here: no model file for this platform, or a download
  /// failed.
  unavailable,

  /// The model runs, as far as the device's gates let it.
  running,

  /// A desktop found no libvips to decode photos with, so nothing can run
  /// (the macOS app bundles it with tools/macos/bundle_vips.py).
  noDecoder,
}

/// Whether [host] is null for want of libvips: the lookup finished with no
/// host on a desktop. Phones decode through their runners and browsers have
/// no host, so neither is blamed on the library.
bool decoderMissing(AsyncValue<MlHost?> host) =>
    !kIsWeb &&
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform) &&
    host.hasValue &&
    host.value == null;

/// Where on-device ML is, and how far a download is, 0 to 1.
typedef MlStatus = ({MlPhase phase, double progress});

/// What holds on-device ML back on a device in [health], with the user's
/// [settings].
Hold? mlHold(Map<Object?, Object?> health, Settings settings) => backgroundHold(
  health,
  chargingOnly: settings.indexWhileCharging,
  battery: settings.indexBattery,
  allowSaver: settings.indexAllowSaver,
);

/// The image model on-device ML runs: the registry's first image embedding.
final RegistryModel mlModel = registry.firstWhere(
  (m) => m.task == 'image_text_embedding',
);

const _log = Logger('photolib.ml');

/// On-device ML (design 09 §3.3–3.4, §12.2): once the user agrees, the
/// model downloads, on an unmetered network unless allowed, from the user's
/// server or, standalone, the registry's mirrors, then runs in the data
/// isolate as the device's gates let it; a phone indexes its new captures in
/// small batches and leaves its backlog to the OS's background tasks, except
/// in lite mode.
class OnDeviceMl extends Notifier<MlStatus> {
  MlStatus _status = (phase: MlPhase.off, progress: 0);
  MlHost? _host;
  Future<void>? _installing;
  Replica? _running;
  Completer<void>? _stopBackground;

  @override
  MlStatus build() {
    final settings = ref.watch(settingsProvider);
    if (!settings.indexModels) {
      if (_running case final db?) {
        _host?.stop(db);
        unawaited(_host?.schedule(on: false));
      }
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
    final file = mlModel.imageFile(host.target);
    if (file == null) return (phase: MlPhase.unavailable, progress: 0);
    if (_running != null) {
      host.hold(db, held: mlHold(health, settings) != null);
      return _status;
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
        file,
        server,
        lite: liteMode(health),
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
    RegistryFile file,
    SavedServer? server, {
    required bool lite,
  }) async {
    await Future<void>.value();
    _set(MlPhase.downloading);
    try {
      final installed = await host.install(
        mlModel,
        file,
        server,
        (bytes) => _set(MlPhase.downloading, bytes / file.size),
      );
      if (!installed) return _set(MlPhase.missing);
    } on Object catch (error) {
      _log.warning('the model did not install', error: error);
      return _set(MlPhase.unavailable);
    }
    if (!ref.mounted) return;
    host
      ..start(db, mlModel, file, backlog: !host.phone)
      ..listen(background: () => _background(host, db, file), stop: _stop);
    _running = db;
    _set(MlPhase.running);
    // A rebuild applies the device's gates to what now runs.
    ref.invalidateSelf();
    if (host.phone && !lite) await host.schedule(on: true);
  }

  /// The OS's background task: the backlog until it is done or the task ends;
  /// whether more is left.
  Future<bool> _background(MlHost host, Replica db, RegistryFile file) async {
    final stop = _stopBackground = Completer<void>();
    host
      ..stop(db)
      ..start(db, mlModel, file, backlog: true)
      ..hold(db, held: false);
    final done = Completer<void>();
    MlProgressResult? left;
    final progress = mlProgress(db, mlModel.name).watchSingle().listen((p) {
      left = p;
      if (p.done >= p.total && !done.isCompleted) done.complete();
    });
    await Future.any([done.future, stop.future]);
    unawaited(progress.cancel());
    host
      ..stop(db)
      ..start(db, mlModel, file, backlog: false);
    _stopBackground = null;
    ref.invalidateSelf();
    return switch (left) {
      final p? => p.done < p.total,
      null => true,
    };
  }

  void _stop() => _stopBackground?.complete();

  /// The user scrolls or edits: the model running waits until 5 s after.
  void interacted() {
    if (_running case final db?) _host?.interacted(db);
  }
}

/// On-device ML, run while the app runs.
final onDeviceMlProvider = NotifierProvider<OnDeviceMl, MlStatus>(
  OnDeviceMl.new,
);

/// Tells on-device ML that the user scrolls or edits; tests count.
final interactionProvider = Provider<VoidCallback>(
  (ref) => ref.read(onDeviceMlProvider.notifier).interacted,
);

/// Reports the user's drags and scrolls in [child] to on-device ML, at most
/// once a second: heavy inference waits until 5 s after the last
/// (design 09 §3.4).
class InteractionReporter extends ConsumerStatefulWidget {
  /// Reports what happens in [child].
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  ConsumerState<InteractionReporter> createState() => _ReporterState();
}

class _ReporterState extends ConsumerState<InteractionReporter> {
  final _since = Stopwatch();

  void _report() {
    if (_since.isRunning && _since.elapsed < const Duration(seconds: 1)) {
      return;
    }
    _since
      ..reset()
      ..start();
    ref.read(interactionProvider)();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerMove: (_) => _report(),
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: (_) {
        _report();
        return false;
      },
      child: widget.child,
    ),
  );
}
