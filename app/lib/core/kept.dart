import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';

/// Where [keptProvider] is kept: sealed in the vault as `state`.
final keptStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return VaultText(() => vault, 'state');
});

/// What the user was looking at (VIEW-36), kept across restarts: each
/// view's scroll position, selection, filters and search, and the viewer's
/// place, as JSON under the view's own key.
class KeptNotifier extends StoredNotifier<Map<String, Object?>> {
  @override
  Provider<SecretStore> get store => keptStoreProvider;

  @override
  Map<String, Object?> get initial => const {};

  @override
  Map<String, Object?> decode(Object json) => json as Map<String, Object?>;

  @override
  Object? encode(Map<String, Object?> state) => state;

  /// Keeps [value] under [key], or forgets the key's when null.
  void put(String key, Object? value) =>
      change((kept) => {...kept, key: value}..removeWhere((_, v) => v == null));
}

/// [key] of [replica]'s views, so that each account keeps its own
/// (ADR-0234); the device's own replica keeps the bare keys of the builds
/// before several accounts.
String keptKey(String? replica, String key) =>
    replica == null || replica == standaloneReplica ? key : '$replica/$key';

/// What the user was looking at, as kept.
final keptProvider = NotifierProvider<KeptNotifier, Map<String, Object?>>(
  KeptNotifier.new,
);
