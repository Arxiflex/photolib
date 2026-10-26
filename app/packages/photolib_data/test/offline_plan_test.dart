@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:test/test.dart';

Uint8List _id(int kind, int n) => Uint8List(16)
  ..[0] = kind
  ..[14] = n >> 8
  ..[15] = n & 255;

Uint8List _hash(int n) => Uint8List(32)..[0] = n & 255;

void main() {
  late Replica db;
  setUp(() async {
    db = Replica(NativeDatabase.memory());
    await db
        .into(db.library)
        .insert(
          LibraryCompanion.insert(
            id: _id(1, 1),
            ownerId: _id(2, 1),
            kind: 'managed',
            privacy: 'standard',
            access: 'rw',
            state: 'online',
          ),
        );
    await db
        .into(db.library)
        .insert(
          LibraryCompanion.insert(
            id: _id(1, 2),
            ownerId: _id(2, 1),
            kind: 'managed',
            privacy: 'private',
            access: 'rw',
            state: 'online',
          ),
        );
  });
  tearDown(() => db.close());

  // An asset with the files the server renders; a video also has its proxy.
  Future<void> asset(
    int n, {
    bool video = false,
    int library = 1,
    int taken = 0,
    bool trashed = false,
    bool locked = false,
    Set<String> missing = const {},
  }) async {
    await db
        .into(db.asset)
        .insert(
          AssetCompanion.insert(
            id: _id(3, n),
            libraryId: _id(1, library),
            ownerId: _id(2, 1),
            originalFilename: '$n.jpg',
            source: 'upload',
            mediaKind: video ? 'video' : 'image',
            createdAt: 1000 + n,
            takenUtc: Value(taken == 0 ? 1000 + n : taken),
            trashedAt: Value(trashed ? 5 : null),
            locked: Value(locked ? 1 : 0),
          ),
        );
    var f = 0;
    for (final (role, size) in [
      ('original', 1000),
      ('thumb_s', 10),
      ('thumb_m', 40),
      ('preview', 200),
      if (video) ('r1', 500),
      ('sidecar', 5),
    ]) {
      if (missing.contains(role)) continue;
      await db
          .into(db.assetFile)
          .insert(
            AssetFileCompanion.insert(
              id: _id(4, n * 10 + f++),
              assetId: _id(3, n),
              role: role,
              mime: 'image/jpeg',
              size: size,
              contentHash: Value(_hash(n + role.length)),
              state: 'present',
            ),
          );
    }
  }

  Future<void> album(int n, List<int> assets) async {
    await db
        .into(db.album)
        .insert(
          AlbumCompanion.insert(
            id: _id(5, n),
            ownerId: _id(2, 1),
            title: 'Album $n',
            createdAt: 1,
          ),
        );
    for (final (i, a) in assets.indexed) {
      await db
          .into(db.albumItem)
          .insert(
            AlbumItemCompanion.insert(
              id: _id(6, n * 100 + i),
              albumId: _id(5, n),
              kind: 'asset',
              assetId: Value(_id(3, a)),
              sortKey: 'k${i.toString().padLeft(4, '0')}',
            ),
          );
    }
  }

  OfflinePin albumPin(int n, {bool originals = false}) =>
      OfflinePin.album(_id(5, n), 'Album $n', originals: originals, created: n);

  Future<OfflinePlan> plan(
    StoragePolicy policy,
    List<OfflinePin> pins, {
    Future<List<Uint8List>> Function(OfflinePin)? search,
  }) => planOffline(db, policy, pins, search: search);

  List<String> roles(OfflinePlan p, int n) => [
    for (final f in p.files)
      if (_same(f.asset, _id(3, n))) f.role,
  ];

  group('the presets', () {
    test('keep what LIB-20 says: catalogue only, space saver, travel, all', () {
      const budget = 1 << 30;
      final pin = albumPin(1);
      final original = albumPin(1, originals: true);
      StoragePolicy of(StoragePreset p) =>
          StoragePolicy(preset: p, budget: budget);
      expect(of(StoragePreset.catalogueOnly).library, Keep.nothing);
      expect(of(StoragePreset.catalogueOnly).keepOf(pin), Keep.nothing);
      expect(of(StoragePreset.spaceSaver).library, Keep.previews);
      expect(of(StoragePreset.spaceSaver).keepOf(pin), Keep.previews);
      expect(of(StoragePreset.spaceSaver).keepOf(original), Keep.originals);
      expect(of(StoragePreset.travel).library, Keep.nothing);
      expect(of(StoragePreset.travel).keepOf(pin), Keep.previews);
      expect(of(StoragePreset.travel).keepOf(original), Keep.originals);
      expect(of(StoragePreset.everything).library, Keep.originals);
      expect(of(StoragePreset.everything).keepOf(pin), Keep.originals);
    });

    test('are stored as JSON and read back; unknown values fall back', () {
      const policy = StoragePolicy(
        preset: StoragePreset.spaceSaver,
        budget: 5 << 30,
      );
      expect(StoragePolicy.fromJson(policy.toJson()), policy);
      expect(StoragePolicy.fromJson(null), const StoragePolicy());
      expect(
        StoragePolicy.fromJson({'preset': 'from-the-future', 'budget': -3}),
        const StoragePolicy(),
      );
    });
  });

  group('pins', () {
    test('are stored as JSON and read back, whatever their kind', () {
      final pins = [
        albumPin(1, originals: true),
        OfflinePin.person(_id(7, 1), 'Ann', created: 2),
        OfflinePin.library(created: 3),
        OfflinePin.search({'text': 'beach'}, 'beach', id: 's1', created: 4),
      ];
      expect(OfflinePin.listFromJson(OfflinePin.listToJson(pins)), pins);
      expect(
        OfflinePin.listFromJson(<Object?>[
          1,
          {'kind': '?'},
          null,
        ]),
        isEmpty,
      );
      expect(OfflinePin.listFromJson('nope'), isEmpty);
    });
  });

  group('the plan', () {
    test(
      'a pinned album keeps its tiles first, then previews, in order',
      () async {
        for (var n = 1; n <= 3; n++) {
          await asset(n);
        }
        await album(1, [3, 1, 2]);
        final p = await plan(const StoragePolicy(), [albumPin(1)]);
        expect(
          [for (final f in p.files) f.role],
          [
            for (var i = 0; i < 3; i++) 'thumb_s',
            for (var i = 0; i < 3; i++) 'thumb_m',
            for (var i = 0; i < 3; i++) 'preview',
          ],
        );
        expect(
          [for (final f in p.files.take(3)) f.asset],
          [_id(3, 3), _id(3, 1), _id(3, 2)],
        );
        expect(p.files.first.size, 10);
        expect(p.files.first.hash, hexOf(_hash(3 + 'thumb_s'.length)));
      },
    );

    test(
      'a video keeps the proxy it plays, an original only when asked',
      () async {
        await asset(1, video: true);
        await album(1, [1]);
        const travel = StoragePolicy(); // the default preset
        expect(roles(await plan(travel, [albumPin(1)]), 1), [
          'thumb_s',
          'thumb_m',
          'preview',
          'r1',
        ]);
        expect(roles(await plan(travel, [albumPin(1, originals: true)]), 1), [
          'thumb_s',
          'thumb_m',
          'preview',
          'r1',
          'original',
        ]);
      },
    );

    test(
      'catalogue only plans nothing; travel without pins plans nothing',
      () async {
        await asset(1);
        await album(1, [1]);
        expect(
          (await plan(
            const StoragePolicy(preset: StoragePreset.catalogueOnly),
            [albumPin(1)],
          )).files,
          isEmpty,
        );
        expect((await plan(const StoragePolicy(), [])).files, isEmpty);
      },
    );

    test(
      'files the server lacks, trashed and locked assets are left out',
      () async {
        await asset(1, missing: {'preview'});
        await asset(2, trashed: true);
        await asset(3, locked: true);
        await asset(4);
        await album(1, [1, 2, 3, 4]);
        final p = await plan(const StoragePolicy(), [albumPin(1)]);
        expect(roles(p, 1), ['thumb_s', 'thumb_m']);
        expect(roles(p, 2), isEmpty);
        expect(roles(p, 3), isEmpty);
        expect(roles(p, 4), ['thumb_s', 'thumb_m', 'preview']);
      },
    );

    test(
      'the same file in two pins is planned once, for the first pin',
      () async {
        await asset(1);
        await album(1, [1]);
        await album(2, [1]);
        final p = await plan(const StoragePolicy(), [albumPin(1), albumPin(2)]);
        expect(p.files, hasLength(3));
        expect({for (final f in p.files) f.pin}, {albumPin(1).id});
      },
    );

    test('the library at space saver follows the pins, newest first', () async {
      await asset(1, taken: 100);
      await asset(2, taken: 300);
      await asset(3, taken: 200);
      await album(1, [1]);
      final p = await plan(
        const StoragePolicy(preset: StoragePreset.spaceSaver),
        [albumPin(1)],
      );
      final order = [
        for (final f in p.files)
          if (f.role == 'thumb_s') f.asset,
      ];
      expect(order, [_id(3, 1), _id(3, 2), _id(3, 3)]);
      expect(p.files.where((f) => f.role == 'original'), isEmpty);
      expect(p.files.first.pin, albumPin(1).id);
      expect(p.files.last.pin, OfflinePin.libraryId);
    });

    test('everything keeps the originals of the library', () async {
      await asset(1);
      final p = await plan(
        const StoragePolicy(preset: StoragePreset.everything),
        [],
      );
      expect(roles(p, 1), ['thumb_s', 'thumb_m', 'preview', 'original']);
    });

    test('a ceiling keeps previews where originals are not allowed', () async {
      await asset(1);
      await album(1, [1]);
      final p = await planOffline(
        db,
        const StoragePolicy(preset: StoragePreset.everything),
        [albumPin(1, originals: true)],
        ceiling: Keep.previews,
      );
      expect(p.files.map((f) => f.role).toSet(), {
        'thumb_s',
        'thumb_m',
        'preview',
      });
    });

    test('a person is pinned through the faces that name them', () async {
      for (var n = 1; n <= 3; n++) {
        await asset(n);
      }
      for (final (face, a, person) in [(1, 1, 1), (2, 2, 2), (3, 3, 1)]) {
        await db
            .into(db.face)
            .insert(
              FaceCompanion.insert(
                id: _id(8, face),
                assetId: _id(3, a),
                bbox: '0,0,1,1',
                personId: Value(_id(7, person)),
              ),
            );
      }
      final p = await plan(const StoragePolicy(), [
        OfflinePin.person(_id(7, 1), 'Ann', created: 1),
      ]);
      expect({for (final f in p.files) f.asset.last}, {1, 3});
    });

    test('a search is pinned through the assets its results name', () async {
      for (var n = 1; n <= 3; n++) {
        await asset(n);
      }
      final pin = OfflinePin.search({'text': 'x'}, 'x', id: 's1', created: 1);
      final p = await plan(
        const StoragePolicy(),
        [pin],
        search: (asked) async {
          expect(asked, pin);
          return [_id(3, 2), _id(3, 3), _id(3, 99)];
        },
      );
      expect({for (final f in p.files) f.asset.last}, {2, 3});
    });

    test(
      'files of a private library are marked, as they stay ciphertext',
      () async {
        await asset(1, library: 2);
        await asset(2);
        await album(1, [1, 2]);
        final p = await plan(const StoragePolicy(), [albumPin(1)]);
        expect(
          {for (final f in p.files) f.asset.last: f.private},
          {1: true, 2: false},
        );
      },
    );

    test(
      'keys name the content, so an edit is a new file and the old goes',
      () async {
        await asset(1);
        await album(1, [1]);
        const travel = StoragePolicy(); // the default preset
        final before = await plan(travel, [albumPin(1)]);
        await db.customStatement(
          'UPDATE asset_file SET content_hash = '
          "x'ff00000000000000000000000000000000000000000000000000000000000000' "
          "WHERE role = 'thumb_s'",
        );
        final after = await plan(travel, [albumPin(1)]);
        expect(
          {
            for (final f in before.files) f.key,
          }.intersection({for (final f in after.files) f.key}),
          hasLength(2),
        );
      },
    );
  });

  group('people', () {
    test('lists the named, shown, unmerged people with their photos', () async {
      for (var n = 1; n <= 3; n++) {
        await asset(n);
      }
      Future<void> person(int n, String? name, {int hidden = 0, int? into}) =>
          db
              .into(db.person)
              .insert(
                PersonCompanion.insert(
                  id: _id(7, n),
                  ownerId: _id(2, 1),
                  name: Value(name),
                  hidden: Value(hidden),
                  mergedInto: Value(into == null ? null : _id(7, into)),
                ),
              );
      await person(1, 'Ann');
      await person(2, null);
      await person(3, 'Bob', hidden: 1);
      await person(4, 'Ann again', into: 1);
      await person(5, 'Cy');
      for (final (face, a, who) in [
        (1, 1, 1),
        (2, 2, 1),
        (3, 2, 4),
        (4, 3, 5),
      ]) {
        await db
            .into(db.face)
            .insert(
              FaceCompanion.insert(
                id: _id(8, face),
                assetId: _id(3, a),
                bbox: '0,0,1,1',
                personId: Value(_id(7, who)),
              ),
            );
      }
      final people = await namedPeople(db);
      expect([for (final p in people) p.name], ['Ann', 'Cy']);
      expect([for (final p in people) p.photos], [2, 1]);
      expect(people.first.id, _id(7, 1));
    });
  });

  group('assets named', () {
    test('finds the server assets whose file names hold the text', () async {
      for (var n = 1; n <= 3; n++) {
        await asset(n);
      }
      await db.customStatement(
        "UPDATE asset SET original_filename = 'Beach_Day.JPG' WHERE rowid = 2",
      );
      await db.customStatement(
        "UPDATE asset SET original_filename = 'beach-100%.jpg', trashed_at = 5 "
        'WHERE rowid = 3',
      );
      expect(await assetsNamed(db, 'beach'), [_id(3, 2)]);
      expect(await assetsNamed(db, '100%'), isEmpty);
      expect(await assetsNamed(db, ''), isEmpty);
    });
  });

  group('the budget', () {
    Future<OfflinePlan> five() async {
      for (var n = 1; n <= 5; n++) {
        await asset(n);
      }
      await album(1, [1, 2, 3, 4, 5]);
      return await plan(const StoragePolicy(), [albumPin(1)]);
    }

    int sealed(int size) => size + 100;

    test(
      'chooses the files in order while they fit, and counts the rest',
      () async {
        final p = await five();
        // Five tiles of 10, five of 40, five previews of 200, 100 sealed each.
        final all = p.files.fold<int>(0, (a, f) => a + sealed(f.size));
        final fit = p.within(all, sealed);
        expect(fit.chosen, hasLength(15));
        expect(fit.left, isEmpty);

        final tight = p.within(5 * 110 + 5 * 140 + 2 * 300, sealed);
        expect(tight.chosen.where((f) => f.role == 'thumb_s'), hasLength(5));
        expect(tight.chosen.where((f) => f.role == 'thumb_m'), hasLength(5));
        expect(tight.chosen.where((f) => f.role == 'preview'), hasLength(2));
        expect(tight.left, hasLength(3));
        expect(tight.bytes, lessThanOrEqualTo(5 * 110 + 5 * 140 + 2 * 300));
        expect(tight.leftBytes, 3 * 300);
      },
    );

    test(
      'skips a file that does not fit and goes on with smaller ones',
      () async {
        final p = await five();
        final fit = p.within(5 * 110 + 5 * 140 + 150, sealed);
        expect(fit.chosen, hasLength(10));
        expect(fit.left, hasLength(5));
      },
    );

    test('a budget of nothing chooses nothing', () async {
      final p = await five();
      expect(p.within(0, sealed).chosen, isEmpty);
    });
  });
}

bool _same(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String hexOf(Uint8List b) =>
    [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
