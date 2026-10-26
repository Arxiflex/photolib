import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';

/// Follows the hints of the server [config] reaches as [instance] into [db]
/// until [stop] completes. Tests fake it.
typedef Follow = Future<void> Function(
  Replica db,
  NetworkConfig config,
  String instance,
  Future<void> stop,
);

/// [followHints], syncing in the replica's data isolate, or its data worker
/// in a browser (ADR-0120).
final followProvider = Provider<Follow?>((ref) => _follow);

Future<void> _follow(
  Replica db,
  NetworkConfig config,
  String instance,
  Future<void> stop,
) async {
  final server = Server(config, instance: instance);
  try {
    await followHints(
      server.hints,
      streams: SyncEngine(db, server).streams,
      sync: () => syncReplica(db, config, instance: instance),
      stop: stop,
    );
  } finally {
    server.close();
  }
}

const _log = Logger('photolib.sync');

/// While the app is in the foreground, follows the server of the account in
/// use and syncs its replica at each hint (design 05 §9, ADR-0225, ADR-0234);
/// a revoked session signs that account out.
final hintsProvider = Provider<void>((ref) {
  final (replica, token) = ref.watch(
    serverProvider.select((s) => (s.value?.replica, s.value?.account?.token)),
  );
  final db = replica == null ? null : replicaOf(ref, replica);
  final server = ref.read(serverProvider).value;
  final follow = ref.read(followProvider);
  if (token == null || db == null || server == null || follow == null) return;
  final accounts = ref.read(accountsProvider.notifier);
  Completer<void>? stop;
  void show() {
    if (stop != null) return;
    final following = stop = Completer<void>();
    final followed = follow(
      db,
      server.config,
      server.instance,
      following.future,
    );
    unawaited(
      followed.catchError((Object error) {
        _log.warning('hints stopped', error: error);
        if (error is CallError && error.logsOut) {
          unawaited(accounts.ended(token));
        }
      }),
    );
  }

  void hide() {
    stop?.complete();
    stop = null;
  }

  final lifecycle = AppLifecycleListener(onShow: show, onHide: hide);
  ref.onDispose(() {
    lifecycle.dispose();
    hide();
  });
  if (WidgetsBinding.instance.lifecycleState
      case null || AppLifecycleState.resumed || AppLifecycleState.inactive) {
    show();
  }
});
