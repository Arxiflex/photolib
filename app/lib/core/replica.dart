import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, ProviderListenable;
import 'package:path_provider/path_provider.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_log/photolib_log.dart';

/// The local store of this install (ADR-0057): natively in the app support
/// directory's `store/`, where it re-keys the plaintext replica that builds
/// before it left in that directory; on the web in the page's origin, whose
/// base URL serves sqlite3mc.wasm and drift_worker.js (tools/data/web.sh) and
/// the kernel (tools/kernel/wasm.sh).
///
/// On Linux a passphrase that [ask] gets keeps the keys when no Secret
/// Service runs.
Future<Vault> openVault({
  Future<String> Function({required bool create, required bool retry})? ask,
}) async {
  final keyring = await loadKernel();
  if (kIsWeb) {
    return Vault(
      location: Uri.base.resolve('.').toString(),
      keystore: webKeystore(),
      files: storeFiles(''),
      keyring: keyring,
    );
  }
  final support = (await getApplicationSupportDirectory()).path;
  final files = storeFiles('$support/store');
  return Vault(
    location: '$support/store',
    keystore: defaultTargetPlatform == TargetPlatform.linux && ask != null
        ? FallbackKeystore(
            SecureStorageKeystore(),
            PassphraseKeystore(files, keyring, ask),
          )
        : SecureStorageKeystore(),
    files: files,
    keyring: keyring,
    alpha: support,
  );
}

/// Opens this install's vault, locked.
final vaultOpenerProvider = Provider<Future<Vault> Function()>(
  (ref) =>
      () => openVault(ask: ref.read(passphrasePromptProvider.notifier).ask),
);

/// The store, unlocked: at L1 the keystore unlocks it at start (docs/21 §5.1),
/// and locking it drops its keys. It fails with [RecoveryNeeded] once the
/// keystore lost its key, until the recovery code opens it. It fails at once,
/// never retried: waiting heals no missing keystore (nor kernel), and
/// StoreBanner says so.
final vaultProvider = FutureProvider<Vault>((ref) async {
  final vault = await ref.watch(vaultOpenerProvider)();
  await vault.unlock();
  ref.onDispose(vault.lock);
  return vault;
}, retry: (_, _) => null);

/// A vault object as text, sealed at rest (PLB) under a key of [_class].
class VaultText implements SecretStore {
  /// The object [_name] of the vault that [_vault] returns.
  const new(this._vault, this._name, [this._class = KeyClass.c]);

  final Future<Vault> Function() _vault;
  final String _name;
  final KeyClass _class;

  @override
  Future<String?> read() async {
    final bytes = await (await _vault()).read(_name, keyClass: _class);
    return bytes == null ? null : utf8.decode(bytes);
  }

  @override
  Future<void> write(String? value) async {
    final store = await _vault();
    await (value == null
        ? store.delete(_name)
        : store.write(_name, utf8.encode(value), keyClass: _class));
  }
}

/// A state kept as JSON in the [store] its notifier watches, read at start: a
/// change made before it is read applies over what it holds, and each change
/// is written back once it is read.
abstract class StoredNotifier<T> extends Notifier<T> {
  static const _log = Logger('photolib.stored');

  /// Completes once the stored state is read, or found unreadable.
  late Future<void> loaded;
  List<T Function(T)>? _early;

  /// Where the state is kept.
  Provider<SecretStore> get store;

  /// The state until the stored one is read, and when there is none.
  T get initial;

  /// The state [json] holds.
  T decode(Object json);

  /// [state] as JSON.
  Object? encode(T state);

  @override
  T build() {
    final store = ref.watch(this.store);
    final early = _early = [];
    loaded = () async {
      T? stored;
      try {
        if (await store.read() case final json?) {
          stored = decode(jsonDecode(json) as Object);
        }
      } on Object catch (e) {
        _log.warning('unreadable', error: e, fields: {'type': '$T'});
      }
      if (!ref.mounted) return;
      _early = null;
      if (stored != null) state = early.fold(stored, (s, change) => change(s));
      if (early.isNotEmpty) _write();
    }();
    return initial;
  }

  /// Applies [change] to the state and keeps the outcome.
  @protected
  void change(T Function(T) change) {
    state = change(state);
    if (_early case final early?) {
      early.add(change);
    } else {
      _write();
    }
  }

  void _write() => unawaited(
    ref
        .read(store)
        .write(jsonEncode(encode(state)))
        .catchError(
          (Object e) =>
              _log.warning('not kept', error: e, fields: {'type': '$T'}),
        ),
  );
}

/// Each replica opened in this process, by name: a client of its data
/// isolate, its only writer (docs/10-client-app.md §1.5), kept open so that
/// switching back to an account is instant (ADR-0234). Opening one starts
/// reading the metadata of its device index there, as far as the device's
/// health allows.
final FutureProviderFamily<Replica, String> openReplicaProvider =
    FutureProvider.family((ref, name) async {
      final vault = await ref.watch(vaultProvider.future);
      final db = await vault.openReplica(name: name);
      if (ref.mounted) {
        extractMetadata(db);
        ref.listen(deviceHealthProvider, (_, state) {
          if (state.value case final state?) {
            reportDeviceHealth(db, healthy: backgroundHold(state) == null);
          }
        });
      }
      return db;
    });

/// The replica of the account in use; standalone, the device's own, as when
/// the accounts cannot be read.
final FutureProvider<Replica> replicaProvider = FutureProvider((ref) async {
  // Straight from the accounts, so that a read right after a switch finds the
  // new one; built again only when the name changes.
  final name = await ref
      .watch(accountsProvider.selectAsync((a) => a.replica))
      .catchError((Object _) => standaloneReplica);
  // Switched meanwhile: the build for the new name answers.
  if (!ref.mounted) return await Completer<Replica>().future;
  return await ref.watch(openReplicaProvider(name).future);
});

/// The replica of the account in use, once the accounts are read.
final ProviderListenable<String?> _accountReplica = accountsProvider.select(
  (s) => s.value?.replica,
);

/// The replica in use while it is [name], once open: never the one a switch
/// left (ADR-0234).
Replica? replicaOf(Ref ref, String name) {
  final opened = ref.watch(replicaProvider);
  return opened.isLoading || ref.watch(_accountReplica) != name
      ? null
      : opened.value;
}

/// Forgets what a removed account's server synced into the device's replica,
/// which the next account to connect adopts (ADR-0234).
final Provider<void> forgetRemovedProvider = Provider((ref) {
  bool holds(AsyncValue<Accounts>? accounts) =>
      accounts?.value?.servers.any((s) => s.replica == standaloneReplica) ??
      false;
  ref.listen(accountsProvider, (previous, next) {
    if (!holds(previous) || !next.hasValue || holds(next)) return;
    unawaited(
      ref
          .read(openReplicaProvider(standaloneReplica).future)
          .then(forgetReplica)
          .catchError(
            (Object e) =>
                const Logger('photolib.sync')
                    .warning('not forgotten', error: e),
          ),
    );
  });
});

/// The events of [source], a replica query the UI watches, at most once a
/// second, which waits paused until then. A scan commits a directory at a
/// time: a timeline snapshot of each, its cells and their thumbnails, cost
/// more CPU than the scan itself, nine times as much while the scanned items
/// came on screen (photolib-design#609).
Stream<T> everySecond<T>(Stream<T> source) => Stream.multi((out) {
  final since = Stopwatch();
  Timer? wait;
  final sub = source.listen(null, onError: out.addError, onDone: out.close);
  void emit(T event) {
    since
      ..reset()
      ..start();
    out.add(event);
  }

  sub.onData((event) {
    final left = const Duration(seconds: 1) - since.elapsed;
    if (!since.isRunning || left <= Duration.zero) {
      emit(event);
    } else {
      sub.pause();
      wait = Timer(left, () {
        emit(event);
        sub.resume();
      });
    }
  });
  out
    ..onPause = sub.pause
    ..onResume = sub.resume
    ..onCancel = () {
      wait?.cancel();
      return sub.cancel();
    };
});
