import 'package:drift/drift.dart';

import 'package:photolib_data/src/folder_indexer.dart' show mediaExtensions;
import 'package:photolib_data/src/ml.dart' show ocrModel;
import 'package:photolib_data/src/replica.dart';

/// What a local search asks for (docs/09-ml-and-search.md §4.3): every filter set must hold.
class LocalQuery {
  const LocalQuery({
    this.text = '',
    this.textHits = const {},
    this.days,
    this.facets = const {},
    this.folder,
    this.camera,
    this.area,
  });

  /// Words that must each be in a file's name or folders, in any ASCII case; `*` and `?` are wildcards.
  final String text;

  /// The server assets whose pictures hold [text] (`SearchService.SearchText`),
  /// which find the items linked to them besides the names; not part of the
  /// query the user typed, so never kept.
  final Set<Uint8List> textHits;
  final Days? days;

  /// What the items must all be.
  final Set<Facet> facets;

  /// The folder the items are in, or in a subfolder of.
  final LocalFolder? folder;
  final Camera? camera;

  /// The map area the items are located in (the map as a search filter).

  /// Where the items must be located, if it matters.
  final Area? area;

  bool get isEmpty =>
      text.trim().isEmpty &&
      days == null &&
      facets.isEmpty &&
      folder == null &&
      camera == null &&
      area == null;

  /// This query with the filters given changed; `(value: null)` clears one.
  LocalQuery copyWith({
    String? text,
    Set<Uint8List>? textHits,
    ({Days? value})? days,
    Set<Facet>? facets,
    ({LocalFolder? value})? folder,
    ({Camera? value})? camera,
    ({Area? value})? area,
  }) => LocalQuery(
    text: text ?? this.text,
    textHits: textHits ?? this.textHits,
    days: days == null ? this.days : days.value,
    facets: facets ?? this.facets,
    folder: folder == null ? this.folder : folder.value,
    camera: camera == null ? this.camera : camera.value,
    area: area == null ? this.area : area.value,
  );
}

/// A box on the map in degrees; west greater than east crosses the
/// antimeridian.
// Every field is final: no `package:meta` here to say so with @immutable.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
class Area {
  /// The box from [west] to [east] and [south] to [north].
  const Area({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  /// The edges, in degrees.
  final double west;

  /// The southern edge.
  final double south;

  /// The eastern edge.
  final double east;

  /// The northern edge.
  final double north;

  @override
  bool operator ==(Object other) =>
      other is Area &&
      other.west == west &&
      other.south == south &&
      other.east == east &&
      other.north == north;

  @override
  int get hashCode => Object.hash(west, south, east, north);
}

/// The capture days from [first] to [last], both included, by the wall clock where each item was taken.
typedef Days = ({DateTime first, DateTime last});

/// A folder of a volume: its path, `/`-separated and ending in `/`, or empty for the volume itself.
typedef LocalFolder = ({String source, String volume, String dir});

typedef Camera = ({String? make, String? model});

enum Facet { photo, video, favorite, panorama, motionPhoto, screenshot }

/// Extensions of the videos a folder scan indexes, in lower case; a folder file has no MIME type.
final videoExtensions = 'mp4 mov m4v avi mkv webm 3gp mts m2ts'
    .split(' ')
    .toSet();

/// Whether [a] is a video, as [Facet.video] finds them.
bool isVideo(LocalAssetData a) => (a.mime ?? '').isEmpty
    ? videoExtensions.contains(a.path?.split('.').last.toLowerCase())
    : a.mime!.toLowerCase().startsWith('video/');

/// Whether [a] is a video, in SQL.
Expression<bool> videoOf(LocalAsset a) {
  final mime = coalesce([a.mime, const Constant('')]);
  return mime.like('video/%') |
      (mime.equals('') &
          Expression.or([
            for (final e in videoExtensions)
              coalesce([a.path, const Constant('')]).like('%.$e'),
          ]));
}

/// What [query] finds: [limit] items after the first [offset], newest first, and how many there are in all, which
/// a window past the end cannot tell (0). Hidden items only when [veiled].
Future<({int count, List<LocalAssetData> items})> searchPage(
  Replica db,
  LocalQuery query, {
  required int limit,
  int offset = 0,
  bool veiled = false,
}) async {
  final rows = await db
      .localSearch(
        limit,
        offset,
        filters: (a) =>
            _filters(db, query, a) &
            (veiled ? const Constant(true) : a.hidden.equals(0)),
      )
      .get();
  return (
    count: rows.firstOrNull?.total ?? 0,
    items: [for (final r in rows) r.r],
  );
}

Expression<bool> _filters(Replica db, LocalQuery q, LocalAsset a) {
  const empty = Constant('');
  // A MediaStore item's path is its folder, with its name apart; a folder file's path ends in its name.
  final path = coalesce([a.path, empty]);
  final file = path + coalesce([a.name, empty]);
  final video = videoOf(a);
  Expression<bool> tagged(String facet) =>
      (const Constant(',') + coalesce([a.facets, empty]) + const Constant(','))
          .like('%,${_pattern(facet)},%', escapeChar: r'\');
  final words = q.text.split(' ').where((w) => w.isNotEmpty).toList();
  return Expression.and([
    if (words.isNotEmpty)
      Expression.and([
            for (final word in words)
              file.like('%${_pattern(word)}%', escapeChar: r'\'),
          ]) |
          _readInPicture(db, words, a) |
          (q.textHits.isEmpty
              ? const Constant(false)
              : a.assetId.isIn(q.textHits)),
    if (q.days case (:final first, :final last)) _during(a, first, last),
    for (final facet in q.facets)
      switch (facet) {
        Facet.photo => video.not(),
        Facet.video => video,
        Facet.favorite => a.favorite.equals(1),
        Facet.panorama => tagged('panorama'),
        Facet.motionPhoto => tagged('motion_photo'),
        // What Android, Windows, macOS and Linux name screenshots and their folders; PhotoKit says so (M1-02).
        Facet.screenshot =>
          file.like('%screenshot%') | file.like('%screen shot%'),
      },
    if (q.folder case final f?)
      a.source.equals(f.source) &
          a.volume.equals(f.volume) &
          (f.dir.isEmpty
              ? const Constant(true)
              // Its path and every path below it: '0' follows '/'.
              : a.path.isBiggerOrEqualValue(f.dir) &
                    a.path.isSmallerThanValue(
                      '${f.dir.substring(0, f.dir.length - 1)}0',
                    )),
    if (q.camera case (:final make, :final model))
      a.make.equalsNullable(make) & a.model.equalsNullable(model),
    if (q.area case final b?)
      a.lat.isBetweenValues(b.south, b.north) &
          (b.west <= b.east
              ? a.lon.isBetweenValues(b.west, b.east)
              : a.lon.isBiggerOrEqualValue(b.west) |
                    a.lon.isSmallerOrEqualValue(b.east)),
  ]);
}

/// Whether every word is in the text on-device OCR read in the file as it is
/// now (`local_ml`), folded to lower case by Unicode, not ASCII's rules.
Expression<bool> _readInPicture(Replica db, List<String> words, LocalAsset a) {
  final m = db.localMl;
  return existsQuery(
    db.selectOnly(m)
      ..addColumns([m.localAssetId])
      ..where(
        m.localAssetId.equalsExp(a.id) &
            m.model.equals(ocrModel) &
            m.size.equalsExp(a.size) &
            m.mtime.equalsExp(a.mtime) &
            Expression.and([
              for (final word in words)
                m.ocrFolded.like(
                  '%${_pattern(word.toLowerCase())}%',
                  escapeChar: r'\',
                ),
            ]),
      ),
  );
}

/// Taken from the start of day [first] to the end of day [last]: by `taken_local`, or while extraction has not given
/// one by the platform's time, which this time zone turns into a wall clock.
Expression<bool> _during(LocalAsset a, DateTime first, DateTime last) {
  final start = DateTime(first.year, first.month, first.day);
  final end = DateTime(last.year, last.month, last.day + 1);
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  final platform = coalesce([a.taken, a.mtime]);
  return (a.takenLocal.isBiggerOrEqualValue(day(start)) &
          a.takenLocal.isSmallerThanValue(day(end))) |
      (a.takenLocal.isNull() &
          platform.isBiggerOrEqualValue(start.millisecondsSinceEpoch) &
          platform.isSmallerThanValue(end.millisecondsSinceEpoch));
}

String _pattern(String word) => word
    .replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')
    .replaceAll('*', '%')
    .replaceAll('?', '_');

/// Every camera that took items, with how many, the most used first.
Future<List<({Camera camera, int items})>> searchCameras(Replica db) async => [
  for (final c in await db.localCameras().get())
    (camera: (make: c.make, model: c.model), items: c.items),
];

/// What the diagnostic bundle says of the library (ADR-0115): its items by source, type and state, and by extension,
/// one the folder scan knows or `other`, and its folders by state. Never a name.
Future<Map<String, Map<String, int>>> libraryStatistics(Replica db) async {
  final items = <String, int>{}, extensions = <String, int>{};
  void count(Map<String, int> into, String key, int n) =>
      into[key] = (into[key] ?? 0) + n;
  final rows = await db.customSelect('''
    SELECT source, state, mime, count(*) AS n, CASE WHEN instr(f, '.') > 0
      THEN lower(replace(f, rtrim(f, replace(f, '.', '')), '')) ELSE '' END AS ext
    FROM (SELECT source, state, mime, coalesce(name, path, '') AS f FROM local_asset)
    GROUP BY source, state, mime, ext''').get();
  for (final row in rows) {
    final [source, state, ext] = [
      for (final c in ['source', 'state', 'ext']) row.read<String>(c),
    ];
    final mime = row.read<String?>('mime'), n = row.read<int>('n');
    final video = mime?.startsWith('video/') ?? videoExtensions.contains(ext);
    count(items, '$source ${video ? 'video' : 'image'} $state', n);
    count(extensions, mediaExtensions.contains(ext) ? ext : 'other', n);
  }
  return {
    'items': items,
    'extensions': extensions,
    'mediaSources': {
      for (final row
          in await db
              .customSelect(
                'SELECT state, count(*) AS n FROM media_source GROUP BY state',
              )
              .get())
        row.read<String>('state'): row.read<int>('n'),
    },
  };
}

/// The newest item of each of the last [years] earlier years with one taken
/// on [today]'s month and day, newest year first: what "on this day" shows
/// (docs/10-client-app.md §6.4), never a hidden or archived one.
Future<List<TimelineItemData>> onThisDay(
  Replica db,
  DateTime today, {
  int years = 6,
}) => db
    .customSelect(
      // SQLite takes the other columns of a group from the row of its MAX.
      'SELECT *, MAX(sort_key) FROM timeline_item '
      'WHERE day % 10000 = ?1 AND day < ?2 AND hidden + archived = 0 '
      'AND folder NOT IN (SELECT id FROM hidden_folder) '
      'GROUP BY day / 10000 ORDER BY day DESC LIMIT ?3',
      variables: [
        Variable(today.month * 100 + today.day),
        Variable(today.year * 10000),
        Variable(years),
      ],
      readsFrom: {db.localAsset, db.deviceFolder, db.deviceFolderMode},
    )
    .map((row) => db.timelineItem.map(row.data))
    .get();

/// A folder that holds items itself: with how many and the newest, which its
/// tile shows, and whether the user keeps it out of the library (ADR-0210).
typedef FolderEntry = ({
  LocalFolder folder,
  int items,
  TimelineItemData cover,
  bool excluded,
});

// The folder of a local_asset or timeline_item row: a MediaStore item's path,
// a folder file's path up to its name; NULL for PhotoKit.
const _dir =
    "CASE source WHEN 'folder' THEN rtrim(path, replace(path, '/', '')) "
    'ELSE path END';

/// The device's folders that hold present items, the excluded too, as they
/// change, in no particular order: the folders view arranges them.
Stream<List<FolderEntry>> folderEntries(Replica db, {bool veiled = false}) => db
    .customSelect(
      // SQLite takes the other columns of a group from the row of its MAX.
      'SELECT *, count(*) AS items, max(sort_key), '
      'folder IN (SELECT id FROM excluded_folder) AS excluded FROM '
      '(SELECT *, $_dir AS dir FROM timeline_item) WHERE dir IS NOT NULL '
      'AND (?1 OR hidden = 0) GROUP BY source, volume, dir',
      variables: [Variable(veiled)],
      readsFrom: {db.localAsset, db.deviceFolder, db.deviceFolderMode},
    )
    .map(
      (row) => (
        folder: (
          source: row.read<String>('source'),
          volume: row.read<String>('volume'),
          dir: row.read<String>('dir'),
        ),
        items: row.read<int>('items'),
        cover: db.timelineItem.map(row.data),
        excluded: row.read<int>('excluded') == 1,
      ),
    )
    .watch();

/// The present items in [folder] itself, none of its subfolders', as they
/// change: the user opened it, excluded or not.
Stream<List<LocalAssetData>> folderContents(
  Replica db,
  LocalFolder folder, {
  bool veiled = false,
}) => _present(db, veiled, 'source = ?1 AND volume = ?2 AND $_dir = ?3', [
  folder.source,
  folder.volume,
  folder.dir,
]);

/// The present favourites but those of the folders the library hides, as
/// they change.
Stream<List<LocalAssetData>> favouriteItems(
  Replica db, {
  bool veiled = false,
}) => _present(
  db,
  veiled,
  'favorite = 1 AND folder NOT IN (SELECT id FROM hidden_folder)',
  const [],
);

Stream<List<LocalAssetData>> _present(
  Replica db,
  bool veiled,
  String where,
  List<String> values,
) => db
    .customSelect(
      "SELECT * FROM local_asset WHERE state = 'present' AND trashed = 0 "
      '${veiled ? '' : 'AND hidden = 0 '}AND $where',
      variables: [for (final v in values) Variable(v)],
      readsFrom: {db.localAsset, db.deviceFolder, db.deviceFolderMode},
    )
    .map((row) => db.localAsset.map(row.data))
    .watch();
