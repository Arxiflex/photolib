import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:photolib_data/src/deletion.dart';
import 'package:photolib_data/src/replica.dart';

/// Marks the items of [ids] favourite, or not (ORG-11): first on the
/// platforms that keep favourites too, one request per source, so that a
/// refusal changes nothing; then in the index, which keeps it by content as
/// well (kept_state).
Future<void> setFavorite(
  Replica db,
  MediaPlatform Function(String source) platformOf,
  List<Uint8List> ids, {
  required bool value,
}) async {
  final rows = await rowsOf(db, ids, (_) => const Constant(true));
  for (final items in bySource(rows)) {
    await platformOf(items.first.source).favorite(items, value: value);
  }
  await _set(db, ids, LocalAssetCompanion(favorite: Value(value ? 1 : 0)));
}

/// Hides the items of [ids] from every view, or shows them again: Photolib's
/// own state, never a `.nomedia` or the OS's (ADR-0245).
Future<void> setHidden(
  Replica db,
  List<Uint8List> ids, {
  required bool value,
}) => _set(db, ids, LocalAssetCompanion(hidden: Value(value ? 1 : 0)));

/// Archives the items of [ids], which leaves them out of the timeline but in
/// search and folders (ORG-16), or not.
Future<void> setArchived(
  Replica db,
  List<Uint8List> ids, {
  required bool value,
}) => _set(db, ids, LocalAssetCompanion(archived: Value(value ? 1 : 0)));

Future<void> _set(Replica db, List<Uint8List> ids, LocalAssetCompanion to) =>
    db.transaction(() async {
      for (final chunk in chunked(ids)) {
        await (db.update(
          db.localAsset,
        )..where((a) => a.id.isIn(chunk))).write(to);
      }
    });

/// How much of each end of a file its [fingerprint] reads: little, as
/// extraction computes one for every item.
const int fingerprintEdge = 4 << 10;

/// What names a file's content for the state kept by it (ADR-0245): the
/// SHA-256 of its [size] (8 bytes, big-endian) and its first and last
/// [fingerprintEdge] bytes, [head] and [tail], which a move or rename keeps
/// and an edit changes.
Uint8List fingerprint(int size, List<int> head, List<int> tail) {
  late Digest digest;
  sha256.startChunkedConversion(
      ChunkedConversionSink.withCallback((d) => digest = d.single),
    )
    ..add(
      (ByteData(8)
            ..setUint32(0, size ~/ 0x100000000)
            ..setUint32(4, size % 0x100000000))
          .buffer
          .asUint8List(),
    )
    ..add(head)
    ..add(tail)
    ..close();
  return Uint8List.fromList(digest.bytes);
}
