@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart' show MemoryKeystore;
import 'package:test/test.dart';

import 'kernel.dart';

Uint8List _id(int n) => Uint8List(16)..buffer.asByteData().setUint32(12, n);

/// Item [n]: a MediaStore one when [name] is given, with [path] its folder; else a file of a desktop folder at [path].
LocalAssetCompanion _item(
  int n, {
  String path = 'DCIM/Camera/',
  String? name,
  String? volume,
  String? mime,
  int mtime = 0,
  int? taken,
  String? takenLocal,
  int? takenUtc,
  String state = 'present',
  bool trashed = false,
  bool favorite = false,
  bool hidden = false,
  bool archived = false,
  String? facets,
  String? make,
  String? model,
}) => LocalAssetCompanion.insert(
  id: _id(n),
  source: name == null ? 'folder' : 'mediastore',
  volume: Value(
    volume ?? (name == null ? '/home/me/Pictures' : 'external_primary'),
  ),
  sourceId: '$n',
  size: 1,
  mtime: mtime,
  path: Value(path),
  name: Value(name),
  mime: Value(mime),
  taken: Value(taken),
  takenLocal: Value(takenLocal),
  takenUtc: Value(takenUtc),
  state: Value(state),
  trashed: Value(trashed ? 1 : 0),
  favorite: Value(favorite ? 1 : 0),
  hidden: Value(hidden ? 1 : 0),
  archived: Value(archived ? 1 : 0),
  facets: Value(facets),
  make: Value(make),
  model: Value(model),
);

void main() {
  final kernel = testKernel();
  late Replica db;
  setUp(() => db = Replica(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> add(List<LocalAssetCompanion> items) =>
      db.batch((b) => b.insertAll(db.localAsset, items));

  /// The numbers of the items [query] finds, in order, [limit] after the first [offset].
  Future<List<int>> found(
    LocalQuery query, {
    int limit = 1000,
    int offset = 0,
    bool veiled = false,
  }) async => [
    for (final a in (await searchPage(
      db,
      query,
      limit: limit,
      offset: offset,
      veiled: veiled,
    )).items)
      a.id.buffer.asByteData().getUint32(12),
  ];

  test('library statistics count items by source, type, state and '
      'extension, and folders by state, without a name', () async {
    await add([
      _item(1, path: 'Trip/IMG_0001.JPG'),
      _item(2, path: 'Trip/clip.mov', state: 'missing'),
      _item(3, path: 'v1.2/README'),
      _item(4, name: 'PXL_1.heic', mime: 'image/heic'),
      _item(5, name: 'VID_2.mp4', mime: 'video/mp4'),
    ]);
    await addFolder(db, '/home/me/Pictures');
    final statistics = await libraryStatistics(db);
    expect(statistics, {
      'items': {
        'folder image present': 2,
        'folder video missing': 1,
        'mediastore image present': 1,
        'mediastore video present': 1,
      },
      'extensions': {'jpg': 1, 'mov': 1, 'other': 1, 'heic': 1, 'mp4': 1},
      'mediaSources': {'scanning': 1},
    });
    for (final name in [
      'IMG',
      'clip',
      'README',
      'PXL',
      'VID',
      'Trip',
      'Pictures',
    ]) {
      expect('$statistics', isNot(contains(name)));
    }
  });

  test(
    'without filters every item in the library is found, newest first',
    () async {
      await add([
        _item(1, mtime: 5),
        _item(2, name: 'b.jpg', taken: 7, mtime: 1),
        _item(3, takenUtc: 6, mtime: 9),
        _item(4, mtime: 6),
        _item(5, mtime: 8, state: 'missing'),
        _item(6, name: 'f.jpg', mtime: 8, trashed: true),
        _item(7, mtime: 1, state: 'offline'),
      ]);
      expect(await found(const LocalQuery()), [2, 4, 3, 1, 7]);
      expect((await searchPage(db, const LocalQuery(), limit: 2)).count, 5);
      final past = await searchPage(
        db,
        const LocalQuery(),
        limit: 2,
        offset: 5,
      );
      expect(past.count, 0);
    },
  );

  test('the pictures whose text the server read are found beside the names, '
      'under every other filter', () async {
    final scan = _id(901);
    final sign = _id(902);
    final other = _id(903);
    await add([
      _item(1, path: 'Trip/scan.jpg', mtime: 9).copyWith(assetId: Value(scan)),
      _item(2, name: 'IMG_1.jpg', mtime: 8).copyWith(assetId: Value(sign)),
      _item(3, name: 'estacao.jpg', mtime: 7),
      _item(
        4,
        name: 'VID_4.mp4',
        mime: 'video/mp4',
        mtime: 6,
      ).copyWith(assetId: Value(sign)),
      _item(5, name: 'IMG_5.jpg', mtime: 5).copyWith(assetId: Value(other)),
      _item(6, name: 'IMG_6.jpg', mtime: 4),
    ]);
    LocalQuery query(Set<Uint8List> hits, {Set<Facet> facets = const {}}) =>
        LocalQuery(text: 'estacao', textHits: hits, facets: facets);
    expect(await found(query({})), [3], reason: 'no hit: the names only');
    expect(await found(query({scan, sign})), [1, 2, 3, 4]);
    expect(await found(query({scan, sign}, facets: {Facet.photo})), [
      1,
      2,
      3,
    ], reason: 'the filters still hold');
    expect(await found(LocalQuery(text: '  ', textHits: {scan})), [
      1,
      2,
      3,
      4,
      5,
      6,
    ], reason: 'without text the hits are not asked for');
  });

  test('the text on-device OCR read in a picture is found beside the names, '
      'in any case and script, as read from the file now', () async {
    await add([
      _item(1, name: 'IMG_1.jpg', mtime: 9),
      _item(2, name: 'IMG_2.jpg', mtime: 8),
      _item(3, name: 'IMG_3.jpg', mtime: 7),
      _item(4, name: 'IMG_4.jpg', mtime: 6),
      _item(5, name: 'IMG_5.jpg', mtime: 5),
      _item(6, name: 'lisboa.jpg', mtime: 4),
    ]);
    Future<void> read(
      int n,
      String? text, {
      int? mtime,
      String model = ocrModel,
    }) => db
        .into(db.localMl)
        .insert(
          LocalMlData(
            localAssetId: _id(n),
            model: model,
            size: 1,
            mtime: mtime ?? 10 - n,
            ocrText: text,
            ocrFolded: text?.toLowerCase(),
            failure: text == null ? 'unreadable by vips' : null,
            rtFlags: 'cpu',
          ),
        );
    await read(1, 'Lisboa Estação 2026');
    await read(2, 'Красная ПЛОЩАДЬ, Москва');
    await read(3, '東京駅 丸の内');
    // Not text: a failure, another model's row, and a file changed since.
    await read(4, null);
    await read(5, 'Lisboa', model: 'other@1');
    await db.customStatement('UPDATE local_asset SET mtime = 99 WHERE id = ?', [
      _id(5),
    ]);
    await read(5, 'Lisboa', mtime: 5);
    Future<List<int>> words(String text) => found(LocalQuery(text: text));
    expect(await words('lisboa'), [1, 6], reason: 'the text and the name');
    expect(await words('ESTAÇÃO'), [1], reason: 'Unicode folds');
    expect(await words('площадь москва'), [2], reason: 'every word, any order');
    expect(await words('красная'), [2]);
    expect(await words('東京'), [3], reason: 'a substring, as Chinese needs');
    expect(await words('lis*2026'), [1], reason: 'wildcards as for names');
    expect(await words('100%'), isEmpty, reason: '% is a character');
    expect(await words('img_4'), [4], reason: 'a failure leaves the names');
    expect(
      await found(const LocalQuery(text: 'lisboa', facets: {Facet.video})),
      isEmpty,
      reason: 'the filters still hold',
    );
  });

  test('hidden items are found, and counted in cameras, only while they '
      'are shown; archived ones always', () async {
    await add([
      _item(1, mtime: 1, make: 'Canon'),
      _item(2, path: 'Secret/a.jpg', mtime: 2, make: 'Leica', hidden: true),
      _item(3, mtime: 3, archived: true),
    ]);
    expect(await found(const LocalQuery()), [3, 1]);
    expect(await found(const LocalQuery(), veiled: true), [3, 2, 1]);
    expect(
      [for (final (:camera, items: _) in await searchCameras(db)) camera.make],
      ['Canon'],
    );
  });

  test(
    'every word is in the file name or its folders, in any case, with * and ? as wildcards',
    () async {
      await add([
        _item(1, name: 'IMG_2019.jpg', path: 'DCIM/Camera/', mtime: 9),
        _item(2, path: 'Trip 2019/beach.JPG', mtime: 8),
        _item(3, path: 'Trip 2020/IMG_2019_x.png', mtime: 7),
        _item(4, name: '100%_done.jpg', path: 'Download/', mtime: 6),
        _item(5, name: '100x done.jpg', path: 'Download/', mtime: 5),
        _item(6, path: 'a/b_c.jpg', mtime: 4),
        _item(7, path: r'a/b\c.jpg', mtime: 3),
      ]);
      Future<List<int>> words(String text) => found(LocalQuery(text: text));
      expect(await words('2019'), [1, 2, 3]);
      expect(await words('img_2019'), [1, 3]);
      expect(await words('  trip   img  '), [3]);
      expect(await words('camera'), [1]);
      expect(await words('*.jpg'), [1, 2, 4, 5, 6, 7]);
      expect(await words('trip 20?0'), [3]);
      expect(await words('100%'), [4]);
      expect(await words('b_c'), [6]);
      expect(await words(r'b\c'), [7]);
      expect(await words('external_primary'), isEmpty);
      expect(
        (await searchPage(db, const LocalQuery(text: 'IMG'), limit: 1)).count,
        2,
      );
    },
  );

  test(
    'a date range takes the local capture day, else the platform\'s time in this zone',
    () async {
      int ms(int day, [int extra = 0]) =>
          DateTime(2024, 3, day).millisecondsSinceEpoch + extra;
      await add([
        _item(1, takenLocal: '2024-03-09T23:59:59.999', mtime: 9),
        _item(2, takenLocal: '2024-03-10T00:00:00', mtime: 8),
        _item(3, takenLocal: '2024-03-12T23:59:59', mtime: 7),
        _item(4, takenLocal: '2024-03-13T00:00:00', mtime: 6),
        _item(5, name: 'e.jpg', taken: ms(10), mtime: 5),
        _item(6, mtime: ms(13, -1)),
        _item(7, mtime: ms(13)),
        _item(8, takenLocal: '2024-03-11T12:00:00', takenUtc: 2, mtime: ms(1)),
        _item(9, name: 'i.jpg', taken: ms(9, -1)),
      ]);
      final march = LocalQuery(
        days: (first: DateTime(2024, 3, 10, 18), last: DateTime(2024, 3, 12)),
      );
      expect(await found(march), [6, 5, 2, 3, 8]);
      expect((await searchPage(db, march, limit: 1)).count, 5);
    },
  );

  test(
    'facets: photos, videos, favourites, panoramas, motion photos and screenshots',
    () async {
      await add([
        _item(1, name: 'v.mp4', mime: 'video/mp4', mtime: 1),
        _item(2, path: 'clip.MOV', mtime: 2),
        _item(3, path: 'a.jpg', mtime: 3),
        _item(4, name: 'p.jpg', mime: 'image/jpeg', favorite: true, mtime: 4),
        _item(5, path: 'pano.jpg', facets: 'panorama', mtime: 5),
        _item(6, path: 'mp.jpg', facets: 'motion_photo,panorama', mtime: 6),
        _item(
          7,
          name: 'Screenshot_1.png',
          path: 'Pictures/Screenshots/',
          mtime: 7,
        ),
        _item(8, path: 'Desktop/Screen Shot 2020-01-01.png', mtime: 8),
        _item(
          9,
          path: 'motionXphoto.mp4.jpg',
          facets: 'motionXphoto',
          mtime: 9,
        ),
        _item(10, name: 'f.mp4', mime: 'video/mp4', favorite: true, mtime: 10),
      ]);
      Future<List<int>> only(Set<Facet> facets) =>
          found(LocalQuery(facets: facets));
      expect(await only({Facet.video}), [10, 2, 1]);
      expect(await only({Facet.photo}), [9, 8, 7, 6, 5, 4, 3]);
      expect(await only({Facet.favorite}), [10, 4]);
      expect(await only({Facet.panorama}), [6, 5]);
      expect(await only({Facet.motionPhoto}), [6]);
      expect(await only({Facet.screenshot}), [8, 7]);
      expect(await only({Facet.video, Facet.favorite}), [10]);
      expect(await only({Facet.photo, Facet.video}), isEmpty);
    },
  );

  test('a folder holds the items in it and in its subfolders', () async {
    const camera = '/media/me/Camera';
    await add([
      _item(1, name: 'a.jpg', path: 'DCIM/Camera/', mtime: 1),
      _item(2, name: 'b.jpg', path: 'DCIM/Camera/', mtime: 2),
      _item(3, name: 'c.jpg', path: 'DCIM/Camera/Sub/', mtime: 3),
      _item(4, name: 'd.jpg', path: 'DCIM/Camera-x/', mtime: 4),
      _item(5, name: 'e.jpg', path: 'DCIM/Camera0/', mtime: 5),
      _item(6, path: 'x.jpg', mtime: 6),
      _item(7, path: 'Trip/y.jpg', mtime: 7),
      _item(8, path: 'Trip/Day 1/z.jpg', mtime: 8),
      _item(9, path: 'Trip/gone.jpg', state: 'missing'),
      _item(10, path: 'DCIM/Camera/w.jpg', volume: camera, mtime: 10),
    ]);
    Future<List<int>> inFolder(String source, String volume, String dir) =>
        found(LocalQuery(folder: (source: source, volume: volume, dir: dir)));
    expect(await inFolder('mediastore', 'external_primary', 'DCIM/Camera/'), [
      3,
      2,
      1,
    ]);
    expect(await inFolder('folder', '/home/me/Pictures', ''), [8, 7, 6]);
    expect(await inFolder('folder', '/home/me/Pictures', 'Trip/'), [8, 7]);
    expect(await inFolder('folder', camera, 'DCIM/Camera/'), [10]);
  });

  test(
    'a camera is a make and model; the list has the most used first',
    () async {
      await add([
        _item(1, make: 'Canon', model: 'Canon EOS R5', mtime: 1),
        _item(2, make: 'Canon', model: 'Canon EOS R5', mtime: 2),
        _item(3, make: 'Apple', model: 'iPhone 15', mtime: 3),
        _item(4, model: 'X100V', mtime: 4),
        _item(5, mtime: 5),
        _item(6, make: 'Canon', model: 'Canon EOS R5', trashed: true),
      ]);
      expect(
        [
          for (final (:camera, :items) in await searchCameras(db))
            '${camera.make} ${camera.model} $items',
        ],
        ['Canon Canon EOS R5 2', 'null X100V 1', 'Apple iPhone 15 1'],
      );
      expect(
        await found(
          const LocalQuery(camera: (make: 'Canon', model: 'Canon EOS R5')),
        ),
        [2, 1],
      );
      expect(
        await found(const LocalQuery(camera: (make: null, model: 'X100V'))),
        [4],
      );
    },
  );

  test(
    'filters combine, every one holding, and pages follow each other',
    () async {
      await add([
        for (var n = 1; n <= 8; n++)
          _item(
            n,
            path: n.isEven ? 'Trip/IMG_$n.jpg' : 'Home/IMG_$n.mp4',
            takenLocal: '2024-0${n % 3 + 1}-01T12:00:00',
            favorite: n > 2,
            make: 'Canon',
            model: n < 7 ? 'R5' : 'R6',
            mtime: n,
          ),
      ]);
      final query = LocalQuery(
        text: 'img',
        days: (first: DateTime(2024), last: DateTime(2024, 2, 29)),
        facets: {Facet.photo, Facet.favorite},
        folder: (source: 'folder', volume: '/home/me/Pictures', dir: 'Trip/'),
        camera: (make: 'Canon', model: 'R5'),
      );
      expect(await found(query), [6, 4]);
      expect((await searchPage(db, query, limit: 1)).count, 2);
      expect(
        [
          for (final offset in [0, 3, 6])
            await found(const LocalQuery(), limit: 3, offset: offset),
        ],
        [
          [8, 7, 6],
          [5, 4, 3],
          [2, 1],
        ],
      );
    },
  );

  test(
    'every filter combination returns its count and first page in under 100 ms on 100,000 items',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final dir = await Directory.systemTemp.createTemp('photolib-search-');
      addTearDown(() => dir.delete(recursive: true));
      // As the app opens it: encrypted, through the vault.
      final vault = Vault(
        location: '${dir.path}/store',
        keystore: MemoryKeystore(),
        files: storeFiles('${dir.path}/store'),
        keyring: kernel.keyring,
      );
      await vault.unlock();
      addTearDown(vault.lock);
      final replica = await vault.openReplica();
      await _seed(replica, 100000);

      DateTime d(int y, [int m = 1, int day = 1]) => DateTime(y, m, day);
      const pixel = (make: 'Google', model: 'Pixel 7');
      const camera = (
        source: 'mediastore',
        volume: 'external_primary',
        dir: 'DCIM/Camera/',
      );
      final queries = <String, LocalQuery>{
        'nothing but the library': const LocalQuery(),
        'words': const LocalQuery(text: 'IMG_2019'),
        'an extension': const LocalQuery(text: '*.png'),
        'words found nowhere': const LocalQuery(text: 'no-such-file'),
        'a year': LocalQuery(days: (first: d(2019), last: d(2019, 12, 31))),
        'videos': const LocalQuery(facets: {Facet.video}),
        'favourites': const LocalQuery(facets: {Facet.favorite}),
        'panoramas': const LocalQuery(facets: {Facet.panorama}),
        'motion photos': const LocalQuery(facets: {Facet.motionPhoto}),
        'screenshots': const LocalQuery(facets: {Facet.screenshot}),
        'a device folder': const LocalQuery(folder: camera),
        'a desktop folder': const LocalQuery(
          folder: (source: 'folder', volume: '/home/me/Pictures', dir: '2018/'),
        ),
        'a camera': const LocalQuery(camera: pixel),
        'favourite videos of a year': LocalQuery(
          days: (first: d(2020), last: d(2020, 12, 31)),
          facets: {Facet.video, Facet.favorite},
        ),
        'photos of a camera in a folder one summer': LocalQuery(
          days: (first: d(2022, 6), last: d(2022, 8, 31)),
          facets: {Facet.photo},
          folder: camera,
          camera: pixel,
        ),
        'words in videos of a month': LocalQuery(
          text: 'VID',
          days: (first: d(2023, 7), last: d(2023, 7, 31)),
          facets: {Facet.video},
        ),
        'screenshots of a year': LocalQuery(
          days: (first: d(2021), last: d(2021, 12, 31)),
          facets: {Facet.screenshot},
        ),
        'panoramas by a camera': const LocalQuery(
          facets: {Facet.panorama},
          camera: (make: 'Canon', model: 'Canon EOS R6'),
        ),
        'everything': LocalQuery(
          text: 'IMG 20',
          days: (first: d(2015), last: d(2020, 12, 31)),
          facets: {Facet.photo, Facet.favorite, Facet.motionPhoto},
          folder: (
            source: 'mediastore',
            volume: 'external_primary',
            dir: 'DCIM/',
          ),
          camera: (make: 'Google', model: 'Pixel 8 Pro'),
        ),
      };
      final report = <String>[];
      final slow = <String>[];
      for (final MapEntry(key: name, value: query) in queries.entries) {
        // The first run warms up the JIT and the page cache.
        final (:count, :items) = await searchPage(replica, query, limit: 200);
        expect(items.length, min(count, 200));
        expect(count, name == 'words found nowhere' ? 0 : isPositive);
        // The fastest of seven, as the kernel's benchmarks take theirs: a loaded machine stalls every thread now and
        // then. The median is reported too.
        final times = <int>[];
        for (var i = 0; i < 7; i++) {
          final watch = Stopwatch()..start();
          await searchPage(replica, query, limit: 200);
          times.add(watch.elapsedMicroseconds);
        }
        final [fastest, _, _, median, ...] = [
          for (final t in times..sort()) t / 1000,
        ];
        report.add('$name: $count items, $fastest ms, median $median ms');
        if (fastest >= 100) slow.add(name);
      }
      print(report.join('\n'));
      expect(slow, isEmpty);
    },
    // Measures the machine: beside the rest of the suite at load 50 a filter
    // took over 100 ms.
    tags: 'alone',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

const _cameras = [
  ('Google', 'Pixel 7'),
  ('Google', 'Pixel 8 Pro'),
  ('Apple', 'iPhone 13'),
  ('Apple', 'iPhone 15 Pro'),
  ('samsung', 'SM-S911B'),
  ('Canon', 'Canon EOS R6'),
  ('Canon', 'Canon EOS 5D Mark IV'),
  ('SONY', 'ILCE-7M3'),
  ('FUJIFILM', 'X-T4'),
  ('NIKON CORPORATION', 'NIKON D750'),
  ('OLYMPUS CORPORATION', 'E-M10MarkII'),
  ('DJI', 'FC3582'),
];

/// [count] items over 15 years as a phone and two desktop folders hold them: 70% in MediaStore, mostly in its
/// camera folder, the rest in a folder per day; 90% extracted, with a camera.
Future<void> _seed(Replica db, int count) async {
  final random = Random(65);
  const buckets = [
    'DCIM/Camera/', 'DCIM/Camera/', 'DCIM/Camera/', 'DCIM/Camera/', //
    'Pictures/Screenshots/', 'Download/', 'Movies/', 'Pictures/Instagram/',
    'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images/',
  ];
  final start = DateTime.utc(2011).millisecondsSinceEpoch;
  const seconds = 15 * 365 * 24 * 3600;
  for (var n = 0; n < count; n += 10000) {
    await db.batch((b) {
      for (var i = n; i < min(count, n + 10000); i++) {
        final ms = start + random.nextInt(seconds) * 1000;
        final at = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
        final stamp = at
            .toIso8601String()
            .substring(0, 19)
            .replaceAll(RegExp('[-:]'), '')
            .replaceFirst('T', '_');
        final device = random.nextInt(10) < 7;
        final video = random.nextInt(10) == 0;
        final extracted = random.nextInt(10) > 0;
        final (make, model) = _cameras[random.nextInt(_cameras.length)];
        final bucket = buckets[random.nextInt(buckets.length)];
        final screenshot = bucket.contains('Screenshots');
        final name = video
            ? 'VID_$stamp.mp4'
            : screenshot
            ? 'Screenshot_$stamp.png'
            : 'IMG_$stamp.jpg';
        final odds = random.nextInt(100);
        b.insert(
          db.localAsset,
          LocalAssetCompanion.insert(
            id: _id(i),
            source: device ? 'mediastore' : 'folder',
            volume: Value(
              device
                  ? 'external_primary'
                  : i.isEven
                  ? '/home/me/Pictures'
                  : '/media/me/Camera',
            ),
            sourceId: '$i',
            size: 1,
            mtime: ms,
            path: Value(
              device
                  ? bucket
                  : '${at.year}/${at.toIso8601String().substring(0, 10)}/'
                        '${video ? 'MVI_${i % 10000}.MOV' : 'DSC0${i % 10000}.JPG'}',
            ),
            name: Value(device ? name : null),
            mime: Value(device ? (video ? 'video/mp4' : 'image/jpeg') : null),
            taken: Value(device ? ms : null),
            favorite: Value(device && odds < 3 ? 1 : 0),
            state: Value(odds == 99 ? 'missing' : 'present'),
            trashed: Value(device && odds == 98 ? 1 : 0),
            extracted: Value(extracted ? ms : null),
            takenLocal: Value(
              extracted ? at.toIso8601String().substring(0, 23) : null,
            ),
            takenUtc: Value(extracted ? ms : null),
            make: Value(extracted && !screenshot ? make : null),
            model: Value(extracted && !screenshot ? model : null),
            facets: Value(
              !extracted || video
                  ? null
                  : odds < 2
                  ? 'panorama'
                  : odds < 10
                  ? 'motion_photo'
                  : '',
            ),
          ),
        );
      }
    });
  }
}
