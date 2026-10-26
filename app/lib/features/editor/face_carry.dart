import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:photolib/core/kernel.dart'
    if (dart.library.js_interop) 'package:photolib/core/kernel_web.dart';
import 'package:photolib/features/editor/carried.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart' show halfFloats;
import 'package:photolib_data/photolib_data.dart';

/// Moves the faces found in [original] to its [copy], which an edit made by
/// [turns] quarter turns, a mirror if [flip] and the pixels [crop] of what that
/// gives (null: the whole), by the kernel, as the editor moved the pixels
/// (ADR-0389): boxes are kept relative to the original and so stay right on
/// the copy before it is indexed. A face with less than half of it left by the
/// crop is dropped. Returns how many faces were carried.
Future<int> carryFaces(
  Replica db, {
  required Uint8List original,
  required Uri copy,
  required int turns,
  required bool flip,
  required Rect? crop,
}) async {
  final row = await (db.select(
    db.localAsset,
  )..where((a) => a.id.equals(original))).getSingleOrNull();
  final rows =
      await (db.select(db.localMl)..where(
            (m) =>
                m.localAssetId.equals(original) &
                m.model.like('faces:%') &
                m.model.like('faces:carried').not(),
          ))
          .get();
  if (row == null || rows.isEmpty) return 0;
  // The photo as shown: upright, its orientation applied.
  final turned = (row.orientation ?? 1) >= 5;
  final (width, height) = (
    (turned ? row.height : row.width) ?? 0,
    (turned ? row.width : row.height) ?? 0,
  );
  if (width <= 0 || height <= 0) return 0;
  final found = [
    for (final r in rows)
      if (r.vec case final vec?) ...unpackFaces(halfFloatsToFloats(vec)),
  ];
  if (found.isEmpty) return 0;
  final mapped = await mapFaces(
    [
      for (final f in found)
        kernel.Face(
          x: f.x,
          y: f.y,
          width: f.width,
          height: f.height,
          landmarks: f.landmarks,
          score: f.score,
        ),
    ],
    width: width,
    height: height,
    turns: turns,
    flip: flip,
    crop: crop,
  );
  final kept = [
    for (final (i, (face, visible)) in mapped.indexed)
      if (visible)
        DeviceFace(
          x: face.x,
          y: face.y,
          width: face.width,
          height: face.height,
          score: face.score,
          landmarks: face.landmarks,
          embedding: found[i].embedding,
        ),
  ];
  if (kept.isEmpty) return 0;
  await db
      .into(db.localMl)
      .insert(
        LocalMlData(
          localAssetId: carryId(copy),
          model: carriedModel,
          size: 0,
          mtime: 0,
          vec: halfFloats(packFaces(kept.first.embedding.length, kept)),
          rtFlags: 'carried by an edit',
        ),
        mode: InsertMode.insertOrReplace,
      );
  return kept.length;
}
