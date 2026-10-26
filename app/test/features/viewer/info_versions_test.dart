// The edit history the info panel lists comes from the replica's versions
// (ADR-0391): what each changed is the kernel's comparison with the one it
// continues, and a revert is an edit of the asset.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

Uint8List id(int n) => Uint8List.fromList([for (var i = 0; i < 16; i++) n]);

r.Operation step(
  String name, {
  r.CropOperation? crop,
  r.AdjustOperation? adjust,
}) => r.Operation(operationId: name, crop: crop, adjust: adjust);

void main() {
  late Replica db;
  late Kernel kernel;
  late InfoFacts facts;
  var pushed = 0;
  setUp(() async {
    kernel = Kernel();
    db = Replica(NativeDatabase.memory());
    facts = InfoFacts(
      db: db,
      kernel: kernel.keyring().call,
      changed: () async => pushed++,
    );
    pushed = 0;
    await db.customStatement(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, '
      'source, media_kind, current_version_id, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
      [id(1), id(9), id(8), 'a.jpg', 'upload', 'image', id(13)],
    );
    await db.customStatement(
      'INSERT INTO local_asset (id, source, volume, source_id, path, size, '
      'mtime, state, asset_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [id(2), 'folder', '/p', '', 'a.jpg', 1, 1, 'present', id(1)],
    );
    Future<void> version(int n, String kind, int at, r.EditRecipe? recipe) {
      final parent = n == 1 ? null : id(9 + n);
      final label = n == 3 ? 'Warm' : null;
      return db.customStatement(
        'INSERT INTO asset_version (id, asset_id, parent_id, kind, label, '
        'recipe, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id(10 + n), id(1), parent, kind, label, recipe?.writeToBuffer(), at],
      );
    }

    final crop = r.EditRecipe(
      schemaVersion: 1,
      operations: [
        step(
          'crop',
          crop: r.CropOperation(x: 0.5, y: 0, width: 0.5, height: 1),
        ),
      ],
    );
    final warm = crop.deepCopy()
      ..operations.add(
        step('warm', adjust: r.AdjustOperation(temperature: 0.3)),
      );
    await version(1, 'original', 1000, null);
    await version(2, 'edit', 2000, crop);
    await version(3, 'edit', 3000, warm);
  });
  tearDown(() async {
    await db.close();
  });

  test('lists the versions of an item, a linked device item or the asset '
      'itself, with what each changed and the current one marked', () async {
    for (final of in [id(2), id(1)]) {
      final list = await facts.versions(of).first;
      expect([for (final v in list) v.label], ['Warm', '', '']);
      expect([for (final v in list) v.original], [false, false, true]);
      expect([for (final v in list) v.current], [true, false, false]);
      expect(
        [for (final v in list) v.time.millisecondsSinceEpoch],
        [3000, 2000, 1000],
        reason: 'newest first',
      );
      expect(
        [for (final v in list) v.changes],
        [
          ['adjust'],
          ['crop'],
          <String>[],
        ],
      );
    }
  });

  test(
    'lists nothing for an item that was never edited, or has no asset',
    () async {
      await db.customStatement("DELETE FROM asset_version WHERE kind = 'edit'");
      expect(await facts.versions(id(1)).first, isEmpty);
      expect(await facts.versions(id(7)).first, isEmpty);
      expect(await const InfoFacts().versions(id(1)).first, isEmpty);
    },
  );

  test('a revert makes an older version current by an edit of the asset, '
      'changes no version and asks for a sync', () async {
    final list = await facts.versions(id(2)).first;
    await facts.revert(id(2), list.last);
    final asset = await (db.select(
      db.asset,
    )..where((a) => a.id.equals(id(1)))).getSingle();
    expect(asset.currentVersionId, id(11));
    expect((await db.select(db.assetVersion).get()).length, 3);
    final queued = await db.select(db.outbox).get();
    expect([for (final o in queued) o.entity], ['assets']);
    expect(pushed, 1);
    expect((await facts.versions(id(2)).first).map((v) => v.current), [
      false,
      false,
      true,
    ]);
  });

  test("says what a version changed, in the kernel's words, whatever the "
      'steps', () {
    final call = kernel.keyring().call;
    r.EditRecipe recipe(List<r.Operation> steps) =>
        r.EditRecipe(schemaVersion: 1, operations: steps);
    final turn = r.Operation(
      operationId: 't',
      turn: r.TurnOperation(quarterTurns: 1),
    );
    final flip = r.Operation(operationId: 'f', flip: r.FlipOperation());
    expect(changedKinds(call, null, recipe([turn, flip])), ['turn', 'flip']);
    expect(changedKinds(call, recipe([turn]), recipe([turn])), isEmpty);
    expect(changedKinds(call, recipe([turn, flip]), recipe([flip, turn])), [
      'turn',
      'flip',
    ]);
    expect(changedKinds(call, recipe([turn]), recipe([])), ['turn']);
    expect(
      changedKinds(call, recipe([]), r.EditRecipe(schemaVersion: 9)),
      isEmpty,
    );
  });
}
