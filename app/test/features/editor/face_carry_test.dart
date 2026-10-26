import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/editor/face_carry.dart';
import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib_api/photolib_api.dart' show halfFloats;
import 'package:photolib_data/photolib_data.dart';

// Face boxes against edits (ADR-0389): the boxes found in an original reach
// the copy an edit made of it, moved by the kernel exactly as the editor
// moved the pixels, before the copy is indexed and its own are found.
void main() {
  late Replica db;
  final original = Uint8List(16)..[15] = 1;
  final copy = Uint8List(16)..[15] = 2;
  const model = 'faces:yunet@2026may+sface@2021dec';

  Future<void> seed({int? faces = 1}) async {
    db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    Future<void> asset(Uint8List id, String path) => db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: id,
            source: 'folder',
            volume: const Value('/r'),
            sourceId: path,
            size: 1,
            mtime: 1,
            path: Value(path),
            width: const Value(800),
            height: const Value(600),
          ),
        );
    await asset(original, 'photo.jpg');
    await asset(copy, 'photo_edit.jpg');
    if (faces == null) return;
    // A face of a quarter of the photo's size at a quarter of the way in,
    // 200 × 150 pixels at (200, 150), and a second at the right edge.
    final found = [
      for (final box in [
        [.25, .25, .25, .25],
        [.875, .1, .125, .2],
      ].take(faces + 1))
        DeviceFace(
          x: box[0],
          y: box[1],
          width: box[2],
          height: box[3],
          score: .9,
          landmarks: List.filled(10, .5),
          embedding: [.6, .8],
        ),
    ];
    await db
        .into(db.localMl)
        .insert(
          LocalMlData(
            localAssetId: original,
            model: model,
            size: 1,
            mtime: 1,
            vec: halfFloats(packFaces(2, found)),
            rtFlags: 'test',
          ),
        );
  }

  Future<List<Rect>> shown() async => [
    for (final f in await InfoFacts(db: db, faces: true).facesOf(copy).first)
      f.box,
  ];

  void expectBoxes(List<Rect> got, List<List<double>> want) {
    expect(got, hasLength(want.length));
    for (final (i, r) in got.indexed) {
      expect(
        [r.left, r.top, r.width, r.height],
        [for (final v in want[i]) closeTo(v, 2e-3)],
      );
    }
  }

  test('a quarter turn moves the boxes of the original to the copy', () async {
    await seed(faces: 0);
    // 800 × 600 turned clockwise is 600 × 800: the box (200, 150) to (400, 300)
    // is (300, 200) to (450, 400).
    final carried = await carryFaces(
      db,
      original: original,
      copy: Uri.file('/r/photo_edit.jpg'),
      turns: 1,
      flip: false,
      crop: null,
    );
    expect(carried, 1);
    expectBoxes(await shown(), [
      [.5, .25, .25, .25],
    ]);
  });

  test('a mirror and a crop that cuts a face in half carry both, the cut one '
      'clipped', () async {
    await seed();
    // Mirrored, the first face (200..400 of 800) is at 400..600 and the second
    // (700..800) at 0..100. The crop from x = 50, 600 wide, holds the first
    // and half of the second, clipped to 50 pixels.
    final carried = await carryFaces(
      db,
      original: original,
      copy: Uri.file('/r/photo_edit.jpg'),
      turns: 0,
      flip: true,
      crop: const Rect.fromLTWH(50, 0, 600, 600),
    );
    expect(carried, 2);
    expectBoxes(await shown(), [
      [350 / 600, .25, 200 / 600, .25],
      [0, .1, 50 / 600, .2],
    ]);
  });

  test('a face the crop cuts away is not carried, and an original without '
      'faces carries none', () async {
    await seed(faces: 0);
    expect(
      await carryFaces(
        db,
        original: original,
        copy: Uri.file('/r/photo_edit.jpg'),
        turns: 0,
        flip: false,
        crop: const Rect.fromLTWH(500, 0, 300, 600),
      ),
      0,
    );
    expect(await shown(), isEmpty);
    await seed(faces: null);
    expect(
      await carryFaces(
        db,
        original: original,
        copy: Uri.file('/r/photo_edit.jpg'),
        turns: 1,
        flip: false,
        crop: null,
      ),
      0,
    );
  });

  test(
    'the copy found its own faces: they win over what was carried',
    () async {
      await seed(faces: 0);
      await carryFaces(
        db,
        original: original,
        copy: Uri.file('/r/photo_edit.jpg'),
        turns: 1,
        flip: false,
        crop: null,
      );
      await db
          .into(db.localMl)
          .insert(
            LocalMlData(
              localAssetId: copy,
              model: model,
              size: 1,
              mtime: 1,
              vec: halfFloats(
                packFaces(2, [
                  const DeviceFace(
                    x: .1,
                    y: .1,
                    width: .2,
                    height: .2,
                    score: .9,
                    landmarks: [],
                    embedding: [1, 0],
                  ),
                ]),
              ),
              rtFlags: 'test',
            ),
          );
      expectBoxes(await shown(), [
        [.1, .1, .2, .2],
      ]);
    },
  );
}
