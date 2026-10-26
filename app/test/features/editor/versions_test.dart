// Saving an edit of a photo only the server has (ADR-0391): a version that
// continues the current one, shown at once, made current, sent by the next
// sync; and none where the server cannot keep it.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/editor/versions.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/servers/sync.dart';
import 'package:photolib_api/photolib_api.dart' show GetServerInfoResponse;
import 'package:photolib_api/recipe.dart' as r;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_editor/edit.dart';

import '../../support/fake_server.dart';

Uint8List id(int n) => Uint8List.fromList([for (var i = 0; i < 16; i++) n]);

void main() {
  late Replica db;
  late int syncs;
  final item = ThumbnailItem(
    'a',
    Uri(path: 'media/${uuidOf(id(1))}'),
    asset: id(1),
  );

  ProviderContainer container({bool versions = true}) {
    final c = ProviderContainer(
      overrides: [
        replicaProvider.overrideWith((ref) => db),
        sessionProvider.overrideWithValue(
          FakeServer({
            'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
              capabilities: [if (versions) 'sync.versions.v1'],
            ),
          }),
        ),
        syncNowProvider.overrideWithValue(() async => syncs++),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    syncs = 0;
    db = Replica(NativeDatabase.memory());
    await db.customStatement(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, source, '
      'media_kind, current_version_id, created_at) '
      "VALUES (?, ?, ?, 'a.jpg', 'upload', 'image', ?, 0)",
      [id(1), id(9), id(8), id(11)],
    );
    await db.customStatement(
      'INSERT INTO asset_version (id, asset_id, kind, created_at) '
      "VALUES (?, ?, 'original', 1)",
      [id(11), id(1)],
    );
  });
  tearDown(() => db.close());

  Future<List<AssetVersionData>> versions() => (db.select(
    db.assetVersion,
  )..orderBy([(v) => OrderingTerm(expression: v.createdAt)])).get();

  test('an edit becomes a version that continues the current one, which it '
      'becomes, and asks for a sync; a second continues the first', () async {
    final save = container().read(saveVersionProvider);
    final first = await save(item, const Edit().rotated());
    expect(first, isNotNull);
    final second = await save(
      item,
      const Edit().cropped(const Rect.fromLTRB(0, 0, 0.5, 1)),
    );
    final [original, a, b] = await versions();
    expect([a.id, a.parentId, a.kind], [first, id(11), 'edit']);
    expect([b.id, b.parentId], [second, first]);
    expect(
      [
        for (final o in r.EditRecipe.fromBuffer(b.recipe!).operations)
          o.operationId,
      ],
      ['turn', 'crop'],
      reason: "the second edit continues the first one's steps",
    );
    expect(
      r.EditRecipe.fromBuffer(b.recipe!).provenance.tool,
      startsWith('photolib ('),
    );
    expect(original.recipe, isNull);
    final asset = await (db.select(
      db.asset,
    )..where((x) => x.id.equals(id(1)))).getSingle();
    expect(asset.currentVersionId, second);
    expect(syncs, 2);
    final queued = await db.select(db.outbox).get();
    expect(
      [for (final o in queued) o.entity],
      ['versions', 'assets', 'versions', 'assets'],
    );
  });

  test('a server that cannot keep versions gets none: nothing is recorded, '
      'nothing waits to be refused', () async {
    final saved = await container(versions: false)
        .read(saveVersionProvider)(item, const Edit().rotated());
    expect(saved, isNull);
    expect(await versions(), hasLength(1));
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(syncs, 0);
  });

  test('the server asset of an item is its own, or the one a device item is '
      'linked to, or none', () {
    final linked = ThumbnailItem('b', Uri.file('/p/b.jpg'), asset: id(2));
    expect(serverAssetOf(item), id(1));
    expect(serverAssetOf(linked), id(2));
    expect(serverAssetOf(ThumbnailItem('c', Uri.file('/p/c.jpg'))), isNull);
    expect(
      serverAssetOf(ThumbnailItem('d', Uri(path: 'media/not-a-uuid'))),
      isNull,
    );
    expect([isServerOnly(item), isServerOnly(linked)], [true, false]);
    expect(
      [
        canEditVersion(item, signedIn: true),
        canEditVersion(item, signedIn: false),
        canEditVersion(linked, signedIn: true),
      ],
      [true, false, false],
    );
  });
}
