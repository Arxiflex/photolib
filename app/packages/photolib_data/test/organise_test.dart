@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

import 'deletion_test.dart' show FakePlatform, id;

void main() {
  late Replica db;
  late FakePlatform folders;
  late FakePlatform store;
  MediaPlatform platformOf(String source) =>
      source == 'folder' ? folders : store;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    folders = FakePlatform();
    store = FakePlatform(expires: true);
  });
  tearDown(() => db.close());

  Future<void> add(int n, {String source = 'folder', int favorite = 0}) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: id(n),
          source: source,
          sourceId: '$n',
          size: 1,
          mtime: 0,
          favorite: Value(favorite),
        ),
      );

  Future<void> read(int n, int content) =>
      (db.update(db.localAsset)..where((a) => a.id.equals(id(n)))).write(
        LocalAssetCompanion(fingerprint: Value(Uint8List.fromList([content]))),
      );

  Future<LocalAssetData> row(int n) =>
      (db.select(db.localAsset)..where((a) => a.id.equals(id(n)))).getSingle();

  test('favourites, hidden and archived items are marked in the index, '
      'favourites on the platform first', () async {
    await add(1);
    await add(2, source: 'mediastore');
    await setFavorite(db, platformOf, [id(1), id(2)], value: true);
    await setHidden(db, [id(1)], value: true);
    await setArchived(db, [id(2)], value: true);
    expect(store.calls, ['favorite true 2']);
    expect(folders.calls, ['favorite true 1']);
    expect([(await row(1)).favorite, (await row(1)).hidden], [1, 1]);
    expect([(await row(2)).favorite, (await row(2)).archived], [1, 1]);
    await setHidden(db, [id(1)], value: false);
    expect((await row(1)).hidden, 0);
  });

  test('a favourite the platform refuses stays as it was', () async {
    await add(1, source: 'mediastore');
    store.refuse = true;
    await expectLater(
      setFavorite(db, platformOf, [id(1)], value: true),
      throwsStateError,
    );
    expect((await row(1)).favorite, 0);
  });

  test('an item moved or renamed under another row gets its state back by '
      'its content', () async {
    await add(1);
    await read(1, 7);
    await setFavorite(db, platformOf, [id(1)], value: true);
    await setHidden(db, [id(1)], value: true);
    // The file moves: its row goes, and the index finds it under another.
    await (db.delete(db.localAsset)..where((a) => a.id.equals(id(1)))).go();
    await add(2);
    expect((await row(2)).favorite, 0, reason: 'until its content is read');
    await read(2, 7);
    expect([(await row(2)).favorite, (await row(2)).hidden], [1, 1]);
    // Other content stays as it is.
    await add(3);
    await read(3, 8);
    expect((await row(3)).favorite, 0);
  });

  test('a favourite the platform had before its content was read is kept by '
      'it too, and one taken back is forgotten', () async {
    await add(1, source: 'mediastore', favorite: 1);
    await read(1, 7);
    expect(await db.select(db.keptState).get(), hasLength(1));
    await setFavorite(db, platformOf, [id(1)], value: false);
    expect(await db.select(db.keptState).get(), isEmpty);
    await add(2);
    await read(2, 7);
    expect((await row(2)).favorite, 0);
  });

  test('a fingerprint is the SHA-256 of the size, the first and the last '
      '4 KiB', () {
    final head = utf8.encode('head');
    final tail = utf8.encode('tail');
    final size = Uint8List(8)..buffer.asByteData().setUint64(0, 1 << 40);
    expect(
      fingerprint(1 << 40, head, tail),
      sha256.convert([...size, ...head, ...tail]).bytes,
    );
    expect(fingerprint(4, head, head), isNot(fingerprint(5, head, head)));
  });

  test("hidden is the index's own: a .nomedia hides nothing, hiding writes "
      'none, and a rescan keeps it', () async {
    final root = Directory.systemTemp.createTempSync('organise').path;
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    for (final name in ['a.jpg', 'b.jpg', '.nomedia']) {
      File('$root/$name').writeAsStringSync(name);
    }
    final indexer = FolderIndexer(db);
    await addFolder(db, root);
    await indexer.scan(root);
    Future<Map<String, int>> hidden() async => {
      for (final a in await db.select(db.localAsset).get()) a.path!: a.hidden,
    };
    expect(await hidden(), {'a.jpg': 0, 'b.jpg': 0});

    await setHidden(db, [
      for (final a in await db.select(db.localAsset).get())
        if (a.path == 'a.jpg') a.id,
    ], value: true);
    File('$root/a.jpg').writeAsStringSync('edited in place');
    File('$root/b.jpg').renameSync('$root/c.jpg');
    File('$root/.nomedia').deleteSync();
    await indexer.scan(root);

    expect(await hidden(), {'a.jpg': 1, 'c.jpg': 0});
    expect([
      for (final f in Directory(root).listSync()) f.uri.pathSegments.last,
    ], unorderedEquals(['a.jpg', 'c.jpg']));
  });
}
