import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:photolib_data/photolib_data.dart';

/// What the items of a folder or an album are sorted by (VIEW-37); custom is
/// an album's own order.
enum ItemSort {
  /// By file name, with natural numeric order.
  name,

  /// By capture time.
  taken,

  /// By the file's modification time.
  modified,

  /// By file size.
  size,

  /// Shuffled.
  random,

  /// By file name extension.
  extension,

  /// As the user placed them.
  custom,
}

/// How a folder or an album shows its items: their sort, ascending unless
/// [descending], as a grid or a [list]; a random order is [seed]'s.
@immutable
class ItemView {
  /// A view; the newest taken first by default.
  const new({
    this.sort = ItemSort.taken,
    this.descending = true,
    this.list = false,
    this.seed = 0,
  });

  /// The view [stored] holds, as [encode] wrote it; the default when it is
  /// none.
  factory decode(String? stored) {
    final [sort, order, layout, seed, ...] = [
      ...?stored?.split('_'),
      ...['', '', '', ''],
    ];
    return ItemView(
      sort: ItemSort.values.asNameMap()[sort] ?? ItemSort.taken,
      descending: order != 'asc',
      list: layout == 'list',
      seed: int.tryParse(seed) ?? 0,
    );
  }

  /// The view an album's `sort_mode` and `layout` hold; its own order is
  /// `custom`.
  factory album(String mode, String layout) => ItemView.decode(
    '${mode.contains('_') ? mode : '${mode}_asc'}_${layout}_0',
  );

  /// What the items are sorted by.
  final ItemSort sort;

  /// Whether the largest come first.
  final bool descending;

  /// Whether the items show as a list of names, sizes and dates.
  final bool list;

  /// What a random order is shuffled by.
  final int seed;

  /// This view with [sort], [descending], [list] or [seed] changed.
  ItemView copyWith({
    ItemSort? sort,
    bool? descending,
    bool? list,
    int? seed,
  }) => ItemView(
    sort: sort ?? this.sort,
    descending: descending ?? this.descending,
    list: list ?? this.list,
    seed: seed ?? this.seed,
  );

  /// The sort as an album's `sort_mode` holds it: `custom`, or the sort and
  /// its order, as in `taken_desc`.
  String get mode => sort == ItemSort.custom
      ? 'custom'
      : '${sort.name}_${descending ? 'desc' : 'asc'}';

  /// This view as `<mode>_<grid|list>_<seed>`.
  String encode() => '${mode}_${list ? 'list' : 'grid'}_$seed';
}

/// The file name of [a].
String nameOf(LocalAssetData a) => a.name ?? a.path?.split('/').last ?? '';

String _extension(LocalAssetData a) {
  final name = nameOf(a);
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// When [a] was taken: by its metadata, else its platform's time or its
/// file's.
int takenOf(LocalAssetData a) => a.takenUtc ?? a.taken ?? a.mtime;

/// When [a] was taken, on the clock where it was when its metadata says.
DateTime takenAt(LocalAssetData a) =>
    DateTime.tryParse(a.takenLocal ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(takenOf(a));

/// [items] in [view]'s order; ties by name, then by id.
List<LocalAssetData> sortItems(List<LocalAssetData> items, ItemView view) {
  if (view.sort == ItemSort.custom) return items;
  if (view.sort == ItemSort.random) {
    return [...items]..shuffle(Random(view.seed));
  }
  int key(LocalAssetData a, LocalAssetData b) => switch (view.sort) {
    ItemSort.taken => takenOf(a).compareTo(takenOf(b)),
    ItemSort.modified => a.mtime.compareTo(b.mtime),
    ItemSort.size => a.size.compareTo(b.size),
    ItemSort.extension => _extension(a).compareTo(_extension(b)),
    _ => 0,
  };
  int name(LocalAssetData a, LocalAssetData b) =>
      naturalCompare(nameOf(a), nameOf(b));
  final sign = view.descending ? -1 : 1;
  return [...items]..sort((a, b) {
    final k = key(a, b);
    if (k != 0) return sign * k;
    final n = name(a, b);
    if (n != 0) return view.sort == ItemSort.name ? sign * n : n;
    return Comparable.compare(a.sourceId, b.sourceId);
  });
}
