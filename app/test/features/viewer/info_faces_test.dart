import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib_api/photolib_api.dart' show halfFloats;

import 'package:photolib_data/photolib_data.dart';

void main() {
  late Replica db;
  final id = Uint8List(16)..[15] = 1;

  setUp(() async {
    db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: id,
            source: 'folder',
            volume: const Value('/r'),
            sourceId: '1',
            size: 1,
            mtime: 1,
            path: const Value('1.jpg'),
          ),
        );
    final face = DeviceFace(
      x: .25,
      y: .125,
      width: .5,
      height: .375,
      score: .9,
      landmarks: List.filled(10, .5),
      embedding: List.filled(4, .5),
    );
    for (final (model, packed) in [
      ('faces:yunet@2026may+sface@2021dec', packFaces(4, [face])),
      ('m@1', Float32List.fromList([1, 2, 3])),
    ]) {
      await db
          .into(db.localMl)
          .insert(
            LocalMlData(
              localAssetId: id,
              model: model,
              size: 1,
              mtime: 1,
              vec: halfFloats(packed),
              rtFlags: 'test',
            ),
          );
    }
  });

  test('the panel shows the faces found on the device, as boxes of the '
      'photo', () async {
    final facts = InfoFacts(db: db, faces: true);
    expect(facts.faces, isTrue);
    final faces = await facts.facesOf(id).first;
    expect(faces, hasLength(1));
    expect(faces.single.box.left, closeTo(.25, 1e-3));
    expect(faces.single.box.top, closeTo(.125, 1e-3));
    expect(faces.single.box.width, closeTo(.5, 1e-3));
    expect(faces.single.box.height, closeTo(.375, 1e-3));
    expect(faces.single.name, isNull);
    expect(await facts.facesOf(Uint8List(16)).first, isEmpty);
  });

  test('it shows none until the user agreed, whatever is kept', () async {
    final facts = InfoFacts(db: db);
    expect(facts.faces, isFalse);
    expect(await facts.facesOf(id).first, isEmpty);
  });
}
