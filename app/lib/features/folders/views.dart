import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/folders/sorting.dart';

/// What this device keeps of the folders and albums views: each folder's
/// [views], each list's manual [order] and the [pinned] entries, by key, and
/// the [recent] targets of moves and copies, newest first.
@immutable
class FolderViews {
  /// The views.
  const new({
    this.views = const {},
    this.order = const {},
    this.pinned = const {},
    this.recent = const [],
  });

  /// A folder's view by its key.
  final Map<String, ItemView> views;

  /// The keys of a list as the user dragged them, by the list's key.
  final Map<String, List<String>> order;

  /// The keys of the pinned entries.
  final Set<String> pinned;

  /// The folders a move or copy went to, newest first.
  final List<String> recent;

  FolderViews _with({
    Map<String, ItemView>? views,
    Map<String, List<String>>? order,
    Set<String>? pinned,
    List<String>? recent,
  }) => FolderViews(
    views: views ?? this.views,
    order: order ?? this.order,
    pinned: pinned ?? this.pinned,
    recent: recent ?? this.recent,
  );
}

/// Where the views are kept: sealed in the vault, as the settings are.
final folderViewsStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return VaultText(() => vault, 'folders');
});

/// The views, read at start and written back on every change.
class FolderViewsNotifier extends StoredNotifier<FolderViews> {
  @override
  Provider<SecretStore> get store => folderViewsStoreProvider;

  @override
  FolderViews get initial => const FolderViews();

  @override
  FolderViews decode(Object json) {
    final map = json as Map<String, Object?>;
    List<String> strings(Object? list) => [...?(list as List?)?.cast()];
    return FolderViews(
      views: {
        for (final MapEntry(:key, :value)
            in ((map['views'] as Map?) ?? const {}).entries)
          '$key': ItemView.decode('$value'),
      },
      order: {
        for (final MapEntry(:key, :value)
            in ((map['order'] as Map?) ?? const {}).entries)
          '$key': strings(value),
      },
      pinned: strings(map['pinned']).toSet(),
      recent: strings(map['recent']),
    );
  }

  @override
  Object? encode(FolderViews state) => {
    'views': {
      for (final MapEntry(:key, :value) in state.views.entries)
        key: value.encode(),
    },
    'order': state.order,
    'pinned': [...state.pinned],
    'recent': state.recent,
  };

  /// The view of the folder [key].
  ItemView viewOf(String key) => state.views[key] ?? const ItemView();

  /// Keeps [view] as the folder [key]'s.
  void setView(String key, ItemView view) =>
      change((s) => s._with(views: {...s.views, key: view}));

  /// [keys], given in their default order, as the list [list] shows them:
  /// the pinned first, each in the order they were dragged into, then those
  /// never dragged, as given.
  List<String> arrange(String list, List<String> keys) {
    final given = keys.toSet();
    final ordered = [
      ...?state.order[list]?.where(given.contains),
      ...keys.where((k) => !(state.order[list]?.contains(k) ?? false)),
    ];
    return [
      ...ordered.where(state.pinned.contains),
      ...ordered.where((k) => !state.pinned.contains(k)),
    ];
  }

  /// Moves the entry at [from] of [shown], the list [list] as shown, to [to]
  /// and keeps that order.
  void reorder(String list, List<String> shown, int from, int to) {
    final keys = [...shown];
    keys.insert(to, keys.removeAt(from));
    change((s) => s._with(order: {...s.order, list: keys}));
  }

  /// Pins the entry [key] above the others of its list, or unpins it.
  void togglePin(String key) => change(
    (s) => s._with(
      pinned: s.pinned.contains(key)
          ? ({...s.pinned}..remove(key))
          : {...s.pinned, key},
    ),
  );

  /// Puts [dir] first among the recent targets, which keep the last ten.
  void addRecent(String dir) => change(
    (s) => s._with(
      recent: [dir, ...s.recent.where((d) => d != dir)].take(10).toList(),
    ),
  );
}

/// The folders and albums views of this device.
final folderViewsProvider = NotifierProvider<FolderViewsNotifier, FolderViews>(
  FolderViewsNotifier.new,
);
