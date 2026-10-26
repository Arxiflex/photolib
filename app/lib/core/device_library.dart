import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/media_store.dart';
import 'package:photolib/core/photo_kit.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';

/// The device's photo library: MediaStore on Android, PhotoKit on iOS
/// (docs/10-client-app.md §5.2, §6.1).
abstract interface class DeviceLibrary {
  /// What the user lets Photolib read now.
  Future<MediaAccess> access();

  /// Shows the system's permission dialog, or the app's settings once the
  /// system no longer asks; returns the access granted.
  Future<MediaAccess> requestAccess();

  /// The system's picker that changes a limited selection (iOS); null on
  /// Android, where requesting access again offers it.
  Future<void> Function()? get select;

  /// An event whenever the library changes.
  Stream<void> get changes;

  /// Brings the device index of [replica] up to date.
  Future<void> index(Replica replica);
}

/// This platform's photo library, if it has one.
final deviceLibraryProvider = Provider<DeviceLibrary?>((ref) {
  if (kIsWeb) return null;
  if (Platform.isAndroid) return const MediaStoreChannel();
  if (Platform.isIOS) return const PhotoKitChannel();
  return null;
});

/// Runs [sync] on an isolate of its own, with a client of [replica]'s data
/// isolate, reaching the channels through the root isolate's token: indexing
/// never runs on the root isolate.
Future<void> indexAside(
  Replica replica,
  Future<void> Function(Replica db) sync,
) {
  final token =
      RootIsolateToken.instance ?? (throw StateError('not the root isolate'));
  return onDataConnection(replica, (db) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    await sync(db);
  });
}

/// Runs [_run] one at a time: a call while it runs makes it run once more
/// afterwards, so a burst of changes costs at most two runs.
class Coalesced {
  /// [_run], coalesced.
  new(this._run);

  final Future<void> Function() _run;
  Future<void>? _running;
  var _again = false;

  /// Runs now, or once more after the run under way, which it returns.
  Future<void> call() {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          await _run();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
  }
}

/// Brings the device index up to date, now and whenever the library changes.
final mediaIndexProvider = Provider<Future<void> Function()>((ref) {
  final library = ref.watch(deviceLibraryProvider);
  if (library == null) return () async {};
  const log = Logger('photolib.index');
  final index = Coalesced(() async {
    final took = Stopwatch()..start();
    try {
      await library.index(await ref.read(replicaProvider.future));
      log.info(
        'device library indexed',
        fields: {'ms': took.elapsedMilliseconds},
      );
    } on Object catch (error, stack) {
      log.error('indexing failed', error: error, stackTrace: stack);
    }
  });
  final changes = library.changes.listen((_) => index());
  ref.onDispose(changes.cancel);
  return index.call;
});

/// What the user lets Photolib read, asked again on every resume and never
/// cached (docs/10-client-app.md §5.3); null without a device library. Each
/// answer that grants some access starts indexing.
class MediaAccessNotifier extends AsyncNotifier<MediaAccess?> {
  @override
  Future<MediaAccess?> build() async {
    final library = ref.watch(deviceLibraryProvider);
    if (library == null) return null;
    // Each account's replica has a device index of its own (docs/10 §2),
    // which a switch brings up to date.
    await ref.watch(replicaNameProvider.selectAsync((n) => n));
    final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
    ref.onDispose(lifecycle.dispose);
    return _indexing(await library.access());
  }

  /// Asks the user for access, and indexes what they grant.
  Future<void> request() async {
    if (ref.read(deviceLibraryProvider) case final library?) {
      state = AsyncData(_indexing(await library.requestAccess()));
    }
  }

  MediaAccess _indexing(MediaAccess access) {
    const Logger('photolib.folders')
        .info('media access', fields: {'access': access.name});
    if (access != MediaAccess.none) unawaited(ref.read(mediaIndexProvider)());
    return access;
  }
}

/// What the user lets Photolib read of the device's library.
final mediaAccessProvider =
    AsyncNotifierProvider<MediaAccessNotifier, MediaAccess?>(
      MediaAccessNotifier.new,
    );
