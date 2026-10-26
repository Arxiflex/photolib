import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/replica.dart';

/// What the Collections tab lists (VIEW-34).
enum CollectionKind {
  /// The albums and album folders.
  albums,

  /// The device's folders.
  folders,

  /// The favourites.
  favourites,

  /// The people.
  people,

  /// The places.
  places,

  /// The tags.
  tags,
}

@immutable
class CollectionEntry {
  const CollectionEntry(this.kind, {this.pinned = false, this.hidden = false});

  final CollectionKind kind;
  final bool pinned;
  final bool hidden;

  CollectionEntry copyWith({bool? pinned, bool? hidden}) => CollectionEntry(
    kind,
    pinned: pinned ?? this.pinned,
    hidden: hidden ?? this.hidden,
  );
}

/// The user's order is [entries]; pinned collections are shown first.
@immutable
class CollectionsLayout {
  const CollectionsLayout(this.entries);

  final List<CollectionEntry> entries;

  List<CollectionEntry> get visible => [
    for (final pinned in [true, false])
      ...entries.where((e) => !e.hidden && e.pinned == pinned),
  ];

  List<CollectionEntry> get hidden => [
    for (final entry in entries)
      if (entry.hidden) entry,
  ];
}

/// Where the layout is kept: sealed in the vault, as the settings are.
final collectionsStoreProvider = Provider<SecretStore>((ref) {
  final vault = ref.watch(vaultProvider.future);
  return VaultText(() => vault, 'collections');
});

/// The layout, read from [collectionsStoreProvider] at start and written
/// back on every change.
class CollectionsNotifier extends StoredNotifier<CollectionsLayout> {
  @override
  Provider<SecretStore> get store => collectionsStoreProvider;

  @override
  CollectionsLayout get initial => CollectionsLayout([
    for (final kind in CollectionKind.values) CollectionEntry(kind),
  ]);

  /// The stored entries of kinds still known, then those added since.
  @override
  CollectionsLayout decode(Object json) {
    final kinds = CollectionKind.values.asNameMap();
    final entries = [
      for (final e in (json as List).cast<Map<String, Object?>>())
        if (kinds[e['kind']] case final kind?)
          CollectionEntry(
            kind,
            pinned: e['pinned'] == true,
            hidden: e['hidden'] == true,
          ),
    ];
    return CollectionsLayout([
      ...entries,
      for (final kind in CollectionKind.values)
        if (!entries.any((e) => e.kind == kind)) CollectionEntry(kind),
    ]);
  }

  @override
  Object? encode(CollectionsLayout state) => [
    for (final e in state.entries)
      {'kind': e.kind.name, 'pinned': e.pinned, 'hidden': e.hidden},
  ];

  void togglePin(CollectionKind kind) =>
      _update(kind, (e) => e.copyWith(pinned: !e.pinned));

  void toggleHidden(CollectionKind kind) =>
      _update(kind, (e) => e.copyWith(hidden: !e.hidden));

  /// Swaps with the neighbour [delta] places away among the visible
  /// collections that are pinned alike.
  void move(CollectionKind kind, int delta) => change((state) {
    final entries = [...state.entries];
    final from = entries.indexWhere((e) => e.kind == kind);
    final group = [
      for (var i = 0; i < entries.length; i++)
        if (!entries[i].hidden && entries[i].pinned == entries[from].pinned) i,
    ];
    final at = group.indexOf(from);
    if (at < 0 || at + delta < 0 || at + delta >= group.length) return state;
    final to = group[at + delta];
    final moved = entries[from];
    entries[from] = entries[to];
    entries[to] = moved;
    return CollectionsLayout(entries);
  });

  void _update(
    CollectionKind kind,
    CollectionEntry Function(CollectionEntry) edit,
  ) => change(
    (state) => CollectionsLayout([
      for (final e in state.entries) e.kind == kind ? edit(e) : e,
    ]),
  );
}

final collectionsProvider =
    NotifierProvider<CollectionsNotifier, CollectionsLayout>(
      CollectionsNotifier.new,
    );
