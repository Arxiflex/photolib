import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/offline/video_proxy.dart'
    if (dart.library.js_interop) 'package:photolib/features/offline/video_proxy_web.dart';
import 'package:photolib/features/search/search.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart'
    show CallError, SearchServiceApi, SearchTextRequest, ServerError;
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.offline');

/// A browser keeps no originals and a smaller budget (ADR-0200 P8, D6).
const int _webBudget = 500000000;

/// What this device keeps of the server's library, and how much it may take
/// for it (LIB-20): one for the device, sealed in the vault as
/// `offline-policy`.
final offlinePolicyStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return VaultText(() => vault, 'offline-policy');
});

/// The device's storage policy, read at start and written on every change.
class OfflinePolicyNotifier extends StoredNotifier<StoragePolicy> {
  @override
  Provider<SecretStore> get store => offlinePolicyStoreProvider;

  @override
  StoragePolicy get initial =>
      kIsWeb ? const StoragePolicy(budget: _webBudget) : const StoragePolicy();

  @override
  StoragePolicy decode(Object json) => StoragePolicy.fromJson(json);

  @override
  Object? encode(StoragePolicy state) => state.toJson();

  /// Keeps what [preset] says.
  void setPreset(StoragePreset preset) =>
      change((policy) => policy.copyWith(preset: preset));

  /// Allows [bytes] on disk, at least [StoragePolicy.minBudget].
  void setBudget(int bytes) => change(
    (policy) => policy.copyWith(budget: max(bytes, StoragePolicy.minBudget)),
  );
}

/// The device's storage policy.
final offlinePolicyProvider =
    NotifierProvider<OfflinePolicyNotifier, StoragePolicy>(
      OfflinePolicyNotifier.new,
    );

/// The pins of the account in use: a vault object of its own for each
/// account, as pins are not synced.
final offlinePinsStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  final name = ref.watch(replicaNameProvider).value ?? standaloneReplica;
  return VaultText(() => vault, 'offline-pins/$name');
});

/// What the account in use keeps available offline on this device (MOB-15).
class OfflinePinsNotifier extends StoredNotifier<List<OfflinePin>> {
  @override
  Provider<SecretStore> get store => offlinePinsStoreProvider;

  @override
  List<OfflinePin> get initial => const [];

  @override
  List<OfflinePin> decode(Object json) => OfflinePin.listFromJson(json);

  @override
  Object? encode(List<OfflinePin> state) => OfflinePin.listToJson(state);

  /// Keeps [pin] available offline, in place of one with its id.
  void pin(OfflinePin pin) => change(
    (pins) => [
      for (final p in pins)
        if (p.id != pin.id) p,
      pin,
    ],
  );

  /// Lets go of the pin [id]; what only it kept goes with the next pass.
  void unpin(String id) => change(
    (pins) => [
      for (final p in pins)
        if (p.id != id) p,
    ],
  );

  /// Whether the pin [id] keeps originals too.
  void setOriginals(String id, {required bool on}) => change(
    (pins) => [
      for (final p in pins)
        if (p.id == id) p.copyWith(originals: on) else p,
    ],
  );

  /// Lets go of every pin.
  void clear() => change((_) => const []);
}

/// The pins of the account in use.
final offlinePinsProvider =
    NotifierProvider<OfflinePinsNotifier, List<OfflinePin>>(
      OfflinePinsNotifier.new,
    );

/// Whether no account is signed in, its sessions loaded: what was kept
/// offline for it goes (a browser left behind keeps nothing of the library,
/// ADR-0200 D6).
final offlineSignedOutProvider = Provider<bool>(
  (ref) =>
      ref.watch(accountsProvider).hasValue &&
      ref.watch(sessionProvider) == null,
);

/// The offline store of the account in use, in the vault's directory (or the
/// browser's IndexedDB) under a name of its own (docs/21 §3).
final offlineStoreProvider = FutureProvider<OfflineStore>((ref) async {
  final vault = await ref.watch(vaultProvider.future);
  final name = await ref.watch(replicaNameProvider.future);
  await ref.read(offlinePolicyProvider.notifier).loaded;
  return await OfflineStore.open(
    vault,
    storeFiles(vault.location),
    budget: ref.read(offlinePolicyProvider).budget,
    name: 'offline-$name',
    chunkSize: kIsWeb ? 256 << 10 : 1 << 20,
  );
});

/// The server's media from the offline store.
final offlineMediaProvider = FutureProvider<OfflineMedia>((ref) async {
  final store = await ref.watch(offlineStoreProvider.future);
  final db = await ref.watch(replicaProvider.future);
  return OfflineMedia(db, store);
});

/// The assets a search pin's results are: the server copies of the device
/// items it finds, the server's own text hits, and its assets whose file
/// names hold the text.
Future<List<Uint8List>> _searchAssets(
  Ref ref,
  Replica db,
  OfflinePin pin,
) async {
  final query = queryOfJson(pin.query ?? const {});
  final ids = <String, Uint8List>{};
  void add(Uint8List id) => ids.putIfAbsent(_hex(id), () => id);
  for (var page = 0; ; page++) {
    final found = await searchPage(
      db,
      query,
      limit: searchPageSize,
      offset: page * searchPageSize,
    );
    for (final item in found.items) {
      if (item.assetId case final asset?) add(asset);
    }
    if ((page + 1) * searchPageSize >= found.count) break;
  }
  final text = query.text.trim();
  if (text.isNotEmpty) {
    (await assetsNamed(db, text)).forEach(add);
    final link = ref.read(sessionProvider);
    if (link != null) {
      try {
        final hits = await SearchServiceApi(link)
            .searchText(null, SearchTextRequest(query: text, pageSize: 200));
        hits.hits.map((hit) => uuidBytes(hit.assetId)).forEach(add);
      } on CallError {
        // Offline: the names still find them.
      }
    }
  }
  return ids.values.toList();
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// The files of the signed-in server, opened for the offline store: not found
/// is [OfflineMissing], any other trouble reaching it [OfflineUnreachable].
OfflineFetch _fetcher(Ref ref) => (path) async {
  final link = ref.read(sessionProvider);
  if (link == null) throw const OfflineUnreachable('signed out');
  try {
    final media = await link.media(path);
    if (media.status != 200) throw OfflineUnreachable('status ${media.status}');
    return media.bytes;
  } on ServerError catch (e) {
    if (e.code == 'not_found') throw const OfflineMissing();
    throw OfflineUnreachable(e);
  } on CallError catch (e) {
    throw OfflineUnreachable(e);
  }
};

/// Keeps the offline store as the policy and the pins say.
final offlineSyncProvider = FutureProvider<OfflineSync>((ref) async {
  final store = await ref.watch(offlineStoreProvider.future);
  final db = await ref.watch(replicaProvider.future);
  final sync = OfflineSync(
    db: db,
    store: store,
    fetch: _fetcher(ref),
    search: (pin) => _searchAssets(ref, db, pin),
    ceiling: kIsWeb ? Keep.previews : Keep.originals,
  );
  ref.onDispose(() => unawaited(sync.close()));
  return sync;
});

/// Where the offline store is, as it changes.
final offlineProgressProvider = StreamProvider<OfflineProgress>((ref) async* {
  final sync = await ref.watch(offlineSyncProvider.future);
  yield sync.state;
  yield* sync.progress;
});

/// Runs the pass that makes the store what the policy and pins say: at start,
/// at every change of either, when the replica's assets or albums change and
/// when the network returns, and every five minutes while a pass waits for it
/// (ADR-0200 P9, MOB-15). Signed out, it erases the store and the pins.
final offlineKeepingProvider = Provider<void>((ref) {
  if (ref.watch(offlineSignedOutProvider)) {
    unawaited(_erase(ref));
    return;
  }
  final sync = ref.watch(offlineSyncProvider).value;
  final db = ref.watch(replicaProvider).value;
  if (sync == null || db == null) return;
  Timer? soon;
  var closed = false;
  Future<void> reconcile() async {
    await ref.read(offlinePolicyProvider.notifier).loaded;
    await ref.read(offlinePinsProvider.notifier).loaded;
    if (closed) return;
    try {
      await sync.reconcile(
        ref.read(offlinePolicyProvider),
        ref.read(offlinePinsProvider),
      );
    } on Object catch (e, stack) {
      _log.warning('offline pass failed', error: e, stackTrace: stack);
    }
  }

  void later(Duration wait) {
    soon?.cancel();
    soon = Timer(wait, () => unawaited(reconcile()));
  }

  ref
    ..listen(offlinePolicyProvider, (_, _) => later(Duration.zero))
    ..listen(offlinePinsProvider, (_, _) => later(Duration.zero));
  final changes = planChanges(db)
      .listen((_) => later(const Duration(seconds: 10)));
  final network = ref
      .watch(networkChangesProvider)
      .listen((_) => later(const Duration(seconds: 3)));
  final waiting = Timer.periodic(const Duration(minutes: 5), (_) {
    if (sync.state.waiting) later(Duration.zero);
  });
  ref.onDispose(() {
    closed = true;
    soon?.cancel();
    waiting.cancel();
    unawaited(changes.cancel());
    unawaited(network.cancel());
  });
  later(Duration.zero);
});

Future<void> _erase(Ref ref) async {
  try {
    final store = await ref.read(offlineStoreProvider.future);
    await store.clear();
    ref.read(offlinePinsProvider.notifier).clear();
  } on Object catch (e, stack) {
    _log.warning('offline store not erased', error: e, stackTrace: stack);
  }
}

/// The assets, in hex, whose every wanted file this device holds: the cells'
/// *kept on this device* badge (ADR-0200 P2). Refreshed at most once a second.
final offlineKeptProvider = StreamProvider<Set<String>>((ref) async* {
  final sync = await ref.watch(offlineSyncProvider.future);
  yield {...sync.state.kept};
  yield* everySecond(sync.progress.map((p) => {...p.kept}));
});

/// What keeping the asset (in hex) whole on this device adds, in bytes: the
/// sealed sizes of its renditions and its original that it does not hold yet
/// (ADR-0200 I5: a size shown is the sum of the files the action adds).
final FutureProviderFamily<int, String> offlineKeepSizeProvider = FutureProvider
    .autoDispose
    .family((ref, asset) async {
      final db = await ref.watch(replicaProvider.future);
      final store = await ref.watch(offlineStoreProvider.future);
      final id = [
        for (var i = 0; i < asset.length; i += 2)
          int.parse(asset.substring(i, i + 2), radix: 16),
      ];
      final plan = await planOffline(
        db,
        const StoragePolicy(preset: StoragePreset.everything),
        [OfflinePin.asset(id, '')],
        ceiling: kIsWeb ? Keep.previews : Keep.originals,
      );
      return plan.files
          .where((f) => !store.has(f.key))
          .fold<int>(0, (sum, f) => sum + store.sealedSize(f.size));
    });

/// The URL a player reads a server video from (ADR-0246, ADR-0200 P1): the
/// proxy gives it the bytes this device keeps, else the server's, in ranges.
/// The proxy that serves it lives as long as the app.
final Provider<Future<Uri> Function(ThumbnailItem item)>
serverVideoUrlProvider = Provider((ref) {
  Future<VideoProxy>? proxy;
  ref.onDispose(() {
    if (proxy case final started?) unawaited(started.then((p) => p.close()));
  });
  return (item) async {
    final media = await ref.read(offlineMediaProvider.future);
    final uuid = item.uri.pathSegments.last;
    // The 720p proxy plays anywhere; the original when the server has no other.
    final role = await media.describe('media/$uuid/r1') == null
        ? 'original'
        : 'r1';
    final started = proxy ??= VideoProxy.start(
      media,
      ref.read(sessionProvider),
    );
    return await (await started).url('media/$uuid/$role');
  };
});

/// A person a pin can keep, with how many photos they are in.
typedef NamedPerson = ({Uint8List id, String name, int photos});

/// The people a person pin picks from.
final FutureProvider<List<NamedPerson>> namedPeopleProvider =
    FutureProvider.autoDispose((ref) async {
      final db = await ref.watch(replicaProvider.future);
      return await namedPeople(db);
    });
