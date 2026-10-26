// A photo only the server has downloads as its original or, once edited, as
// its current version (MIG-15, ADR-0128, ADR-0391).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/download/download.dart';
import 'package:photolib/features/download/download_action.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib_api/photolib_api.dart' show ServerError;
import 'package:photolib_data/photolib_data.dart';

import '../../support/fake_server.dart';

Uint8List id(int n) => Uint8List.fromList([for (var i = 0; i < 16; i++) n]);

Future<List<int>> read(DownloadFile file) async => [
  for (final chunk in await file.bytes.toList()) ...chunk,
];

void main() {
  late Replica db;
  late FakeServer server;
  final item = ThumbnailItem(
    'a',
    Uri(path: 'media/${uuidOf(id(1))}'),
    asset: id(1),
  );
  final base = 'media/${uuidOf(id(1))}';

  setUp(() async {
    db = Replica(NativeDatabase.memory());
    server = FakeServer()
      ..files['$base/original'] = utf8.encode('the original')
      ..files['$base/edit_export'] = utf8.encode('the edited one');
    await db.customStatement(
      'INSERT INTO asset (id, library_id, owner_id, original_filename, source, '
      'media_kind, taken_utc, current_version_id, created_at) VALUES (?, ?, ?, '
      "'IMG_0042.HEIC', 'upload', 'image', 1700000000000, ?, 0)",
      [id(1), id(9), id(8), id(12)],
    );
    for (final (n, kind) in [(11, 'original'), (12, 'edit')]) {
      await db.customStatement(
        'INSERT INTO asset_version (id, asset_id, kind, created_at) '
        'VALUES (?, ?, ?, 1)',
        [id(n), id(1), kind],
      );
    }
  });
  tearDown(() => db.close());

  test('an edited photo downloads as its original under its own name, or as '
      'the edited picture, a JPEG, under another', () async {
    final download = await serverDownloadOf(server, db, item);
    expect(download!.name, 'IMG_0042.HEIC');
    expect(download.editedName, 'IMG_0042_edit.jpg');
    final original = await download.original();
    expect(utf8.decode(await read(original)), 'the original');
    expect(
      original.modified,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(utf8.decode(await read(await download.edited!())), 'the edited one');
  });

  test('a photo whose current version is its original has no edited file; '
      'one that is not here, or no server photo, has no download', () async {
    await db.customStatement('UPDATE asset SET current_version_id = ?', [
      id(11),
    ]);
    Future<Download?> of(ThumbnailItem i) => serverDownloadOf(server, db, i);
    expect((await of(item))!.edited, isNull);
    expect(
      await of(
        ThumbnailItem('b', Uri(path: 'media/${uuidOf(id(5))}'), asset: id(5)),
      ),
      isNull,
    );
    expect(await of(ThumbnailItem('c', Uri.file('/nowhere/c.jpg'))), isNull);
  });

  test('the edited file is not made yet while the server renders it', () async {
    server.files.remove('$base/edit_export');
    final download = await serverDownloadOf(server, db, item);
    expect(download!.edited!(), throwsA(isA<ServerError>()));
  });
}
