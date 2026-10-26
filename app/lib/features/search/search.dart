import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:photolib/core/kept.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/library.dart' show veiledProvider;
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib_api/photolib_api.dart'
    show CallError, SearchServiceApi, SearchTextRequest;
import 'package:photolib_data/photolib_data.dart';

/// How many results a page of the grid holds.
const searchPageSize = 200;

/// The search on screen: filters and file names over the replica
/// (docs/09-ml-and-search.md §4.3), kept across restarts (VIEW-36).
class SearchQuery extends Notifier<LocalQuery> {
  late String _kept;

  @override
  LocalQuery build() {
    final key = _kept = keptKey(ref.watch(replicaNameProvider).value, 'search');
    return switch (ref.watch(keptProvider.select((k) => k[key]))) {
      final Map<String, Object?> json => queryOfJson(json),
      _ => const LocalQuery(),
    };
  }

  /// Shows [query] and keeps it.
  void set(LocalQuery query) =>
      ref.read(keptProvider.notifier).put(_kept, queryToJson(query));
}

/// [query] as the app keeps it, such as in a pin.
Map<String, Object?> queryToJson(LocalQuery query) => {
  'text': query.text,
  'facets': [for (final f in query.facets) f.name],
  if (query.days case (:final first, :final last))
    'days': [first.toIso8601String(), last.toIso8601String()],
  if (query.folder case (:final source, :final volume, :final dir))
    'folder': [source, volume, dir],
  if (query.camera case (:final make, :final model)) 'camera': [make, model],
  if (query.area case final a?) 'area': [a.west, a.south, a.east, a.north],
};

/// The query [json] holds, as [queryToJson] wrote it.
LocalQuery queryOfJson(Map<String, Object?> json) => LocalQuery(
  text: json['text'] as String? ?? '',
  facets: {
    for (final name in json['facets'] as List<Object?>? ?? const [])
      ?Facet.values.asNameMap()[name],
  },
  days: switch (json['days']) {
    [final String first, final String last] => (
      first: DateTime.parse(first),
      last: DateTime.parse(last),
    ),
    _ => null,
  },
  folder: switch (json['folder']) {
    [final String source, final String volume, final String dir] => (
      source: source,
      volume: volume,
      dir: dir,
    ),
    _ => null,
  },
  area: switch (json['area']) {
    [
      final double west,
      final double south,
      final double east,
      final double north,
    ] =>
      Area(west: west, south: south, east: east, north: north),
    _ => null,
  },
  camera: switch (json['camera']) {
    [final String? make, final String? model] => (make: make, model: model),
    _ => null,
  },
);

/// The search on screen.
final searchQueryProvider = NotifierProvider<SearchQuery, LocalQuery>(
  SearchQuery.new,
);

/// The server's assets whose pictures hold the text as OCR read it
/// (`SearchService.SearchText`), asked once per text and signed in; none when
/// signed out or the server cannot answer, so that the names still find items.
final FutureProviderFamily<Set<Uint8List>, String> ocrHitsProvider =
    FutureProvider.autoDispose.family((ref, text) async {
      final link = ref.watch(sessionProvider);
      if (link == null || text.trim().isEmpty) return const {};
      try {
        final found = await SearchServiceApi(link).searchText(
          null,
          SearchTextRequest(query: text.trim(), pageSize: 200),
        );
        return {for (final hit in found.hits) uuidBytes(hit.assetId)};
      } on CallError {
        return const {};
      }
    });

/// A page of what the search finds, by its number, with how many items it
/// finds in all; a page out of sight is dropped.
final FutureProviderFamily<({int count, List<LocalAssetData> items}), int>
searchPageProvider = FutureProvider.autoDispose.family((ref, page) async {
  final query = ref.watch(searchQueryProvider);
  final veiled = ref.watch(veiledProvider);
  final db = await ref.watch(replicaProvider.future);
  final hits = await ref.watch(ocrHitsProvider(query.text).future);
  return await searchPage(
    db,
    query.copyWith(textHits: hits),
    limit: searchPageSize,
    offset: page * searchPageSize,
    veiled: veiled,
  );
});

/// A result as the library's timeline has it.
ThumbnailItem itemOf(LocalAssetData a) => ThumbnailItem.local(
  TimelineItemData(
    id: a.id,
    source: a.source,
    volume: a.volume,
    sourceId: a.sourceId,
    path: a.path,
    size: a.size,
    mtime: a.mtime,
    mime: a.mime,
    favorite: a.favorite,
    hidden: a.hidden,
    archived: a.archived,
    added: 0,
    day: 0,
    sortKey: 0,
    folder: a.folder,
    facets: a.facets,
    assetId: a.assetId,
    backup:
        (a.tile == 1 ? Availability.backedUp : Availability.notBackedUp).sql,
  ),
);

/// A desktop folder's root by its path, any other folder by its own name.
String folderLabel(LocalFolder f) => f.dir.isEmpty
    ? isolated(f.volume)
    : f.dir.substring(0, f.dir.length - 1).split('/').last;

/// A camera's model, after its make unless the model starts with it.
String cameraLabel(Camera c) {
  final (make, model) = (c.make ?? '', c.model ?? '');
  return model.toLowerCase().startsWith(make.split(' ').first.toLowerCase())
      ? model
      : '$make $model'.trim();
}
