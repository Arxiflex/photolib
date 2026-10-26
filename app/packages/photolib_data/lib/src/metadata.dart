import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:photolib_data/src/replica.dart';
import 'package:photolib_log/photolib_log.dart';

const _log = Logger('photolib.extract');

/// A file to read: its path, `/`-separated under `root`. The last segment is
/// its name and the others its folders, in which the capture-time resolver
/// reads dates too.
typedef MediaFile = ({String root, String path});

/// Reads the metadata of [files] off the calling isolate: in order, the values
/// of each one's `local_asset` row, or null when it cannot be read. [visible]
/// files are those the user is looking at.
typedef Extract =
    Future<List<LocalAssetCompanion?>> Function(
      List<MediaFile> files, {
      required bool visible,
    });

/// Fills in what the files of the device index say about themselves
/// (docs/10-client-app.md §5.2): visible items first, then the rest newest
/// first, [chunk] items per call of [extract] and per transaction. An item
/// waits while its `extracted` is NULL, which an indexer sets again when the
/// file changes, so a restart resumes where the last run stopped. A file that
/// cannot be read waits for the next pass, which a change of the index starts;
/// one read as nothing (the kernel panicked on it) is marked read, so that only
/// a change of the file sends it back.
class MetadataExtractor {
  /// Reads the items of [db] waiting for extraction with [extract].
  MetadataExtractor(this.db, this.extract, {this.chunk = 256});

  /// The replica whose device index it fills in.
  final Replica db;

  /// What reads the files.
  final Extract extract;

  /// How many items it reads at a time.
  final int chunk;
  final _visible = <Uint8List>[];
  StreamSubscription<void>? _changes;
  Future<void>? _running;
  var _again = false;
  var _stopped = false;
  var _healthy = true;

  /// Whether the device allows background work (docs/09-ml-and-search.md
  /// §3.4); while it does not, only visible items are read.
  bool get healthy => _healthy;
  set healthy(bool value) {
    _healthy = value;
    if (value) _wake();
  }

  /// Reads the waiting items among [ids], those on screen now, before any
  /// other.
  void prioritise(Iterable<Uint8List> ids) {
    _visible
      ..clear()
      ..addAll(ids);
    _wake();
  }

  /// Runs now, and again whenever the device index changes, until [stop].
  void start() {
    _changes ??= db
        .tableUpdates(
          TableUpdateQuery.onAllTables([db.localAsset, db.volumeCursor]),
        )
        .listen((_) => _wake());
    _wake();
  }

  /// Reads what waits and may be read now. One run at a time: a call during a
  /// run makes it run once more.
  Future<void> run() {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          try {
            await _pass();
          } on Exception catch (e, stack) {
            // The extractor failed, not a file: the next run tries again.
            _log.warning('extraction failed', error: e, stackTrace: stack);
          }
        } while (_again && !_stopped);
      } finally {
        _running = null;
      }
    }();
  }

  /// Stops once the chunk being read is stored.
  Future<void> stop() async {
    _stopped = true;
    await _changes?.cancel();
    await _running;
  }

  void _wake() {
    if (!_stopped) unawaited(run());
  }

  Future<void> _pass() async {
    // Below every sort key: COALESCE(taken, mtime), milliseconds.
    var (key, id) = (9007199254740991, Uint8List(0));
    while (!_stopped) {
      var rows = await _nextVisible();
      final visible = rows.isNotEmpty;
      if (!visible) {
        if (!_healthy) return;
        rows = [
          for (final r in await db.extractionQueue(key, id, chunk).get())
            (r.a, r.root!),
        ];
        if (rows.isEmpty) return;
        final last = rows.last.$1;
        // Past what this pass could not read.
        (key, id) = (last.taken ?? last.mtime, last.id);
      }
      final found = await extract([
        for (final (a, root) in rows)
          (
            root: root,
            path: a.source == 'folder' ? a.path! : '${a.path}${a.name}',
          ),
      ], visible: visible);
      await _store([for (final (a, _) in rows) a], found);
    }
  }

  Future<List<(LocalAssetData, String)>> _nextVisible() async {
    while (_visible.isNotEmpty) {
      final ids = _visible.take(chunk).toList();
      _visible.removeRange(0, ids.length);
      final rows = await db.extractionQueueOf(ids).get();
      if (rows.isNotEmpty) return [for (final r in rows) (r.a, r.root!)];
    }
    return const [];
  }

  /// Stores what was [found] in each of [rows] unless its file changed
  /// meanwhile; the platform's values stay.
  Future<void> _store(
    List<LocalAssetData> rows,
    List<LocalAssetCompanion?> found,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    Value<T> fill<T>(Object? had, Value<T> value) =>
        had == null ? value : const Value.absent();
    return db.batch((b) {
      for (final (i, row) in rows.indexed) {
        final f = found[i];
        if (f == null) continue;
        b.update(
          db.localAsset,
          f.copyWith(
            extracted: Value(now),
            width: fill(row.width, f.width),
            height: fill(row.height, f.height),
            orientation: fill(row.orientation, f.orientation),
            durationMs: fill(row.durationMs, f.durationMs),
          ),
          where: (a) =>
              a.id.equals(row.id) &
              a.size.equals(row.size) &
              a.mtime.equals(row.mtime),
        );
      }
    });
  }
}

/// The frames a second of the device item [id] as they change: its file's,
/// else its server asset's (`asset.fps`).
Stream<double?> watchFrameRate(Replica db, Uint8List id) => db
    .customSelect(
      'SELECT COALESCE(l.frame_rate, a.fps) AS rate FROM local_asset l '
      'LEFT JOIN asset a ON a.id = l.asset_id WHERE l.id = ?',
      variables: [Variable.withBlob(id)],
      readsFrom: {db.localAsset, db.asset},
    )
    .watchSingleOrNull()
    .map((r) => r?.read<double?>('rate'));

/// Keeps [rate] as the frame rate of the device item [id], which extraction
/// never read, as of PhotoKit's videos.
Future<void> keepFrameRate(Replica db, Uint8List id, double rate) =>
    db.customUpdate(
      'UPDATE local_asset SET frame_rate = ? '
      'WHERE id = ? AND frame_rate IS NULL',
      variables: [Variable.withReal(rate), Variable.withBlob(id)],
      updates: {db.localAsset},
    );

/// Whether the file that starts with [head] is an animated image (FMT-13): a
/// GIF with a second frame or a looping extension, or cut off before either; a
/// WebP with VP8X's animation flag; a PNG with an animation control chunk of
/// frames before its image data; an AVIF image sequence.
bool isAnimated(List<int> head) {
  final data = head is Uint8List ? head : Uint8List.fromList(head);
  final text = String.fromCharCodes(data.take(64));
  if (text.startsWith('GIF8')) return _gifAnimated(data);
  if (text.startsWith('RIFF') && text.startsWith('WEBPVP8X', 8)) {
    return data.length > 20 && data[20] & 2 != 0;
  }
  final view = ByteData.sublistView(data);
  if (text.startsWith('\x89PNG')) {
    for (var at = 8; at + 16 <= data.length; at += 12 + view.getUint32(at)) {
      final type = String.fromCharCodes(data, at + 4, at + 8);
      if (type == 'acTL') return view.getUint32(at + 8) > 1;
      if (type == 'IDAT') return false;
    }
    return false;
  }
  // ISO BMFF: the brands of its ftyp box.
  if (data.length >= 16 && text.startsWith('ftyp', 4)) {
    final end = view.getUint32(0).clamp(16, data.length);
    for (var at = 8; at + 4 <= end; at += 4) {
      if (String.fromCharCodes(data, at, at + 4) == 'avis') return true;
    }
  }
  return false;
}

const _loops = {'NETSCAPE2.0', 'ANIMEXTS1.0'};

bool _gifAnimated(Uint8List gif) {
  if (gif.length < 13) return false;
  int table(int flags) => flags & 0x80 != 0 ? 3 << ((flags & 7) + 1) : 0;
  // Past sub-blocks of data from [start], to the byte after their end.
  int skip(int start) {
    var at = start;
    while (at < gif.length && gif[at] != 0) {
      at += gif[at] + 1;
    }
    return at + 1;
  }

  var at = 13 + table(gif[10]);
  var frames = 0;
  while (at < gif.length) {
    switch (gif[at]) {
      case 0x21 when at + 2 < gif.length:
        final label = String.fromCharCodes(gif.skip(at + 3).take(11));
        if (gif[at + 1] == 0xff && _loops.contains(label)) return true;
        at = skip(at + 2);
      case 0x2c when at + 10 < gif.length:
        if (++frames > 1) return true;
        at = skip(at + 11 + table(gif[at + 9]));
      case 0x3b:
        return false;
      default:
        return true; // cut off by the head, or damaged: the decoder tells
    }
  }
  return true;
}
