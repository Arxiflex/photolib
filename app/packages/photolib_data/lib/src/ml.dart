import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:photolib_api/photolib_api.dart' show halfFloats;
import 'package:photolib_data/photolib_data.dart';

/// The model id of the text on-device OCR reads (ADR-0388): the pipeline and
/// its models as one, as the server's `ppocr-v5` is, whichever engine reads
/// (the row's `rt_flags` names it: PP-OCR's runtime, or the phone's `mlkit` or
/// `vision`).
const ocrModel = 'ppocr-v5@1';

/// Reads the text of [items] off the calling isolate: in order, each one's
/// text, or null when it cannot be read.
typedef ReadText = Future<List<String?>> Function(List<LocalAssetData> items);

/// Runs a model on [items] off the calling isolate: in order, each one's
/// output, or null when it cannot be read.
typedef Embed = Future<List<Float32List?>> Function(List<LocalAssetData> items);

/// On-device ML over the device's photos (docs/09-ml-and-search.md §3.4,
/// ADR-0254): new captures first, then favourites, then the last 12 months,
/// then the rest, each newest first, [chunk] items per call of `embed` and per
/// transaction, every output kept in `local_ml` as half floats, the server's
/// precision, with [model] and [rtFlags]. An item waits while it has no row
/// for its file's present version, so that a restart, like a pause, resumes
/// where indexing stopped. One that cannot be read is kept as failed until its
/// file changes or another [decoder] reads.
class MlIndexer {
  /// Indexes [db]'s photos with [embed].
  MlIndexer(
    Replica db, {
    required String model,
    required String rtFlags,
    required Embed embed,
    String decoder = '',
    int chunk = 8,
    bool backlog = true,
    Duration idle = const Duration(seconds: 5),
    DateTime Function() clock = DateTime.now,
  }) : this._(db, model, rtFlags, embed, decoder, chunk, backlog, idle, clock);

  /// Indexes [db]'s photos with the text [read] finds in them, kept in
  /// `local_ml` as read and folded to lower case for the search to match.
  MlIndexer.text(
    Replica db, {
    required String model,
    required String rtFlags,
    required ReadText read,
    String decoder = '',
    int chunk = 8,
    bool backlog = true,
    Duration idle = const Duration(seconds: 5),
    DateTime Function() clock = DateTime.now,
  }) : this._(db, model, rtFlags, read, decoder, chunk, backlog, idle, clock);

  MlIndexer._(
    this.db,
    this.model,
    this.rtFlags,
    this._run,
    this.decoder,
    this.chunk,
    this.backlog,
    this.idle,
    this._clock,
  );

  /// The replica whose photos are indexed.
  final Replica db;

  /// The model's id@revision.
  final String model;

  /// The runtime, execution provider and precision that compute the outputs.
  final String rtFlags;

  // Embed or ReadText: each item's vector or text, null when it cannot be read.
  final Future<List<Object?>> Function(List<LocalAssetData>) _run;

  /// What decodes the photos it reads, such as `vips 8.15`.
  final String decoder;

  /// Items per call of the model.
  final int chunk;

  /// Whether it reads past the new captures, those the device index added in
  /// the last 24 hours: not in lite mode, nor in a phone's foreground.
  final bool backlog;

  /// How long after the user last scrolled or edited the next chunk waits.
  final Duration idle;

  final DateTime Function() _clock;
  Timer? _interaction;
  StreamSubscription<void>? _changes;
  Future<void>? _running;
  var _again = false;
  var _stopped = false;
  var _paused = false;

  /// Whether the device's gates hold indexing back: heat, a low battery, power
  /// saving, or no charger when it must charge. The chunk under way is stored,
  /// then nothing runs until they let it go.
  bool get paused => _paused;
  set paused(bool value) {
    _paused = value;
    if (!value) _wake();
  }

  /// The user scrolls or edits: the next chunk waits until [idle] after the
  /// last call.
  void interacted() {
    _interaction?.cancel();
    _interaction = Timer(idle, () {
      _interaction = null;
      _wake();
    });
  }

  bool get _held => _stopped || _paused || _interaction != null;

  /// Runs now, and again whenever the device index changes, until [stop].
  void start() {
    _changes ??= db
        .tableUpdates(TableUpdateQuery.onAllTables([db.localAsset]))
        .listen((_) => _wake());
    _wake();
  }

  /// Indexes what waits, unless paused. One run at a time: a call during a run
  /// makes it run once more.
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
          } on Object {
            // The runner failed, not an item: the next run tries again.
          }
        } while (_again && !_held);
      } finally {
        _running = null;
      }
    }();
  }

  /// Stops once the chunk under way is stored.
  Future<void> stop() async {
    _stopped = true;
    _interaction?.cancel();
    await _changes?.cancel();
    await _running;
  }

  void _wake() {
    if (!_stopped) unawaited(run());
  }

  Future<void> _pass() async {
    final now = _clock().toUtc();
    final year = now.subtract(const Duration(days: 365));
    for (var tier = 0; tier < (backlog ? 4 : 1); tier++) {
      // Above every position in the timeline.
      var (day, key, id) = (99999999, 9007199254740991, Uint8List(0));
      while (!_held) {
        final rows = await db
            .mlQueue(
              tier,
              now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
              year.year * 10000 + year.month * 100 + year.day,
              day,
              key,
              id,
              model,
              _failure,
              chunk,
              photo: (_, a) => videoOf(a).not(),
            )
            .get();
        if (rows.isEmpty) break;
        (day, key, id) = (rows.last.day, rows.last.sortKey, rows.last.a.id);
        final items = [for (final r in rows) r.a];
        await _store(items, await _run(items));
      }
    }
  }

  String get _failure => 'unreadable by $decoder';

  Future<void> _store(List<LocalAssetData> items, List<Object?> outputs) =>
      db.batch((b) {
        for (final (i, a) in items.indexed) {
          final out = outputs[i];
          final text = out is String ? out : null;
          b.insert(
            db.localMl,
            LocalMlData(
              localAssetId: a.id,
              model: model,
              size: a.size,
              mtime: a.mtime,
              vec: out is Float32List ? halfFloats(out) : null,
              ocrText: text,
              ocrFolded: text?.toLowerCase(),
              failure: out == null ? _failure : null,
              rtFlags: rtFlags,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
}

/// How far on-device ML has run [model], or with null the model it ran last:
/// the photos the library shows, those it read, and of them those it could
/// not.
Selectable<MlProgressResult> mlProgress(Replica db, String? model) =>
    db.mlProgress(model);

/// The photos the library shows that [model], or with null the model run
/// last, could not read, and why.
Selectable<MlFailuresResult> mlFailures(Replica db, String? model) =>
    db.mlFailures(model, photo: (_, _, a) => videoOf(a).not());

/// Forgets every face this device found (ADR-0389): the user withdrew, so no
/// box, landmark or embedding stays. Returns how many photos' faces went.
Future<int> deleteFaces(Replica db) =>
    (db.delete(db.localMl)..where((t) => t.model.like('faces:%'))).go();
