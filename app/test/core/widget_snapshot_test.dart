import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' show AppLifecycleState;
import 'package:photolib/core/replica.dart';
import 'package:photolib/core/widget_snapshot.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/real_time.dart';

void main() {
  late Replica db;
  late Directory dir;
  var n = 0;
  setUp(() {
    n = 0;
    db = Replica(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('widgets-');
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> photo(String taken) => db
      .into(db.localAsset)
      .insert(
        LocalAssetCompanion.insert(
          id: Uint8List(16)..[15] = ++n,
          source: 'photokit',
          sourceId: 'asset-$n',
          size: n,
          mtime: 0,
          takenLocal: Value(taken),
          takenUtc: Value(DateTime.parse('${taken}Z').millisecondsSinceEpoch),
        ),
      );

  group('the snapshot', () {
    final rendered = <String>[];
    setUp(rendered.clear);
    Future<Uint8List> render(ThumbnailItem item) async {
      rendered.add(item.uri.path);
      if (item.uri.path.endsWith('-3')) throw Exception('no thumbnail');
      return utf8.encode('png of ${item.uri.path}');
    }

    Map<String, Object?> snapshot() =>
        jsonDecode(File('${dir.path}/snapshot.json').readAsStringSync())
            as Map<String, Object?>;

    test('says what to show and holds its images, pre-rendered; an item '
        'without an image is left out', () async {
      await photo('2024-10-20T09:00:00');
      await photo('2019-10-20T12:00:00');
      await photo('2018-10-20T12:00:00');
      final items = await onThisDay(db, DateTime(2026, 10, 20));

      await writeWidgetSnapshot(dir, DateTime(2026, 10, 20), items, render);

      final shown = snapshot();
      expect(shown, {
        'version': 1,
        'date': '2026-10-20',
        'onThisDay': [
          {'year': 2024, 'image': isA<String>()},
          {'year': 2019, 'image': isA<String>()},
        ],
      });
      final images = [
        for (final entry in shown['onThisDay']! as List)
          File('${dir.path}/${(entry as Map)['image']}'),
      ];
      expect(images.map((f) => f.readAsStringSync()), [
        'png of asset-1',
        'png of asset-2',
      ]);
      expect(dir.listSync(), hasLength(3));
    });

    test('renders only what changed, and drops what it no longer '
        'shows', () async {
      await photo('2024-10-20T09:00:00');
      await photo('2023-10-21T12:00:00');
      Future<bool> write(DateTime day) async =>
          await writeWidgetSnapshot(dir, day, await onThisDay(db, day), render);
      // It says whether the widgets have anything new to show.
      expect(await write(DateTime(2026, 10, 20)), isTrue);
      expect(await write(DateTime(2026, 10, 20)), isFalse);
      expect(rendered, ['asset-1']);

      expect(await write(DateTime(2026, 10, 21)), isTrue);
      expect(rendered, ['asset-1', 'asset-2']);
      expect(snapshot()['date'], '2026-10-21');
      expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
        'snapshot.json',
        ((snapshot()['onThisDay']! as List).single as Map)['image'],
      });
    });
  });

  testWidgets('on iOS the app writes it into the App Group at start and '
      'whenever it leaves the screen, and has the widgets reload what '
      'changed', (tester) async {
    final group = Directory('${dir.path}/group')..createSync();
    var reloads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.photolib/inbox'),
      (call) async => switch (call.method) {
        'folder' => '${group.path}/Inbox',
        'reloadWidgets' => reloads++,
        _ => throw MissingPluginException(),
      },
    );
    final today = DateTime.now();
    File('${dir.path}/a.png')
        .writeAsBytesSync(img.encodePng(img.Image(width: 900, height: 600)));
    await db
        .into(db.localAsset)
        .insert(
          LocalAssetCompanion.insert(
            id: Uint8List(16),
            source: 'folder',
            volume: Value(dir.path),
            sourceId: 'a',
            path: const Value('a.png'),
            size: 1,
            mtime: 0,
            takenLocal: Value(
              DateTime(
                today.year - 3,
                today.month,
                today.day,
              ).toIso8601String(),
            ),
          ),
        );
    final container = ProviderContainer(
      overrides: [
        replicaProvider.overrideWith((ref) async => db),
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(originals: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final snapshot = File('${group.path}/Widgets/snapshot.json');

    Future<void> until(bool Function() done) =>
        tester.runAsync(() => realUntil(done));
    await until(() {
      container.read(widgetSnapshotProvider);
      return snapshot.existsSync();
    });
    final shown = (jsonDecode(snapshot.readAsStringSync()) as Map)['onThisDay'];
    expect(shown, [
      {'year': today.year - 3, 'image': isA<String>()},
    ]);
    final png = img.decodePng(
      File('${group.path}/Widgets/${((shown as List).single as Map)['image']}')
          .readAsBytesSync(),
    )!;
    expect([png.width, png.height], [768, 512]);
    await until(() => reloads > 0);
    expect(reloads, 1);

    snapshot.deleteSync();
    await until(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      return reloads > 1;
    });
    expect(snapshot.existsSync(), isTrue);
    expect(reloads, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
