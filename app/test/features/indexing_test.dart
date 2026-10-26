import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/settings/indexing.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/ml_host.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets('Settings say how far indexing on this device is, or what holds '
      'it back, as the device and the charging option change', (tester) async {
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      for (var n = 0; n < 3; n++) {
        await db
            .into(db.localAsset)
            .insert(
              LocalAssetCompanion.insert(
                id: Uint8List(16)..[15] = n,
                source: 'mediastore',
                sourceId: '$n',
                size: 1,
                mtime: 1,
                mime: const Value('image/jpeg'),
              ),
            );
      }
      await db
          .into(db.localMl)
          .insert(
            LocalMlData(
              localAssetId: Uint8List(16),
              model: 'm@1',
              size: 1,
              mtime: 1,
              rtFlags: 'onnxruntime 1.31.0 CPU fp16',
            ),
          );
    });
    final health = StreamController<Map<Object?, Object?>>();
    addTearDown(health.close);
    const fine = {
      'battery': 80,
      'charging': false,
      'powerSaving': false,
      'thermal': 0,
      'temperature': 30.0,
    };
    await pumpApp(
      tester,
      replica: (_) => db,
      overrides: [deviceHealthProvider.overrideWith((ref) => health.stream)],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.scrollUntilVisible(find.text('Only while charging'), 100);

    expect(find.text('Indexing on this device'), findsOneWidget);
    expect(find.text('Photos indexed: 1 of 3'), findsOneWidget);

    health.add({...fine, 'thermal': 3});
    await tester.pumpAndSettle();
    expect(find.text('Paused while the device is hot'), findsOneWidget);

    health.add(fine);
    await tester.pumpAndSettle();
    expect(find.text('Photos indexed: 1 of 3'), findsOneWidget);
    await tester.tapAndSettle(find.text('Only while charging'));
    expect(find.text('Paused until the device charges'), findsOneWidget);

    health.add({...fine, 'charging': true});
    await tester.pumpAndSettle();
    expect(find.text('Photos indexed: 1 of 3'), findsOneWidget);

    health.add({...fine, 'charging': true, 'powerSaving': true});
    await tester.pumpAndSettle();
    expect(find.text('Paused while battery saver is on'), findsOneWidget);

    await tester.tapAndSettle(find.text('Only while charging'));
    health.add({...fine, 'battery': 19});
    await tester.pumpAndSettle();
    expect(find.text('Paused while the battery is below 20%'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('before anything is indexed, Settings offer only the option', (
    tester,
  ) async {
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(
      () => db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16),
              source: 'mediastore',
              sourceId: '0',
              size: 1,
              mtime: 1,
            ),
          ),
    );
    final health = StreamController<Map<Object?, Object?>>();
    addTearDown(health.close);
    await pumpApp(
      tester,
      replica: (_) => db,
      overrides: [deviceHealthProvider.overrideWith((ref) => health.stream)],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    health.add({
      'battery': 80,
      'charging': false,
      'powerSaving': false,
      'thermal': 4,
      'temperature': 30.0,
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Only while charging'), 100);

    expect(find.text('Indexing on this device'), findsOneWidget);
    expect(find.textContaining('Photos indexed'), findsNothing);
    expect(find.textContaining('Paused'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  test('the progress follows a scan, which commits a directory at a time, '
      'at most once a second, ending with what the scan left', () async {
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    final app = ProviderContainer(
      overrides: [replicaProvider.overrideWith((ref) async => db)],
    );
    addTearDown(app.dispose);
    final totals = <int>[];
    // From before the first, so that n totals a second apart fit.
    final took = Stopwatch()..start();
    app.listen(
      indexingProgressProvider,
      (_, next) => totals.addAll([?next.value?.total]),
    );
    while (totals.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var n = 1; n <= 50; n++) {
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16)..[15] = n,
              source: 'folder',
              sourceId: '$n',
              size: 1,
              mtime: 1,
              mime: const Value('image/jpeg'),
            ),
          );
    }
    while (totals.last < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      totals.length,
      lessThanOrEqualTo(1 + took.elapsed.inSeconds),
      reason: 'each reads every item: 234 ms at a million',
    );
  });

  test('progress groups its digits as the language does', () {
    expect(
      lookupAppLocalizations(const Locale('en')).indexingProgress(1730, 2400),
      'Photos indexed: 1,730 of 2,400',
    );
    expect(
      lookupAppLocalizations(const Locale('de')).indexingProgress(1730, 2400),
      'Fotos indexiert: 1.730 von 2.400',
    );
  });

  group('searching on this device', () {
    const fine = {
      'battery': 80,
      'charging': false,
      'powerSaving': false,
      'thermal': 0,
      'temperature': 30.0,
      'memory': 8000000000,
      'metered': false,
    };
    late StreamController<Map<Object?, Object?>> health;
    late RecordingMlHost host;

    Future<Replica> open(
      WidgetTester tester, {
      bool phone = false,
      bool decoder = true,
    }) async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      health = StreamController<Map<Object?, Object?>>();
      addTearDown(health.close);
      host = RecordingMlHost(phone: phone);
      await pumpApp(
        tester,
        replica: (_) => db,
        overrides: [
          deviceHealthProvider.overrideWith((ref) => health.stream),
          mlHostProvider.overrideWith((ref) async => decoder ? host : null),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.scrollUntilVisible(find.text('Search on this device'), 100);
      return db;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    testWidgets('nothing downloads until the user agrees, naming the host; '
        'then the model downloads, runs and follows the gates', (tester) async {
      await open(tester);
      health.add(fine);
      await tester.pumpAndSettle();
      expect(
        find.text('Downloads the search model (186 MB) from huggingface.co'),
        findsOneWidget,
      );
      expect(host.calls, isEmpty);

      final downloaded = Completer<bool>();
      host.installing = (progress) {
        progress(93065838);
        return downloaded.future;
      };
      await tester.tapAndSettle(find.text('Search on this device'));
      expect(host.calls, ['install vision_model_fp16.onnx from mirror']);
      expect(find.text('Downloading the search model: 50%'), findsOneWidget);

      downloaded.complete(true);
      await tester.pumpAndSettle();
      expect(host.calls.skip(1), [
        'start siglip2-b16-256@onnx-d1114256 with backlog',
        'go',
      ]);
      health.add({...fine, 'thermal': 3});
      await tester.pumpAndSettle();
      expect(host.calls.last, 'hold');
      health.add({...fine, 'battery': 30});
      await tester.pumpAndSettle();
      expect(host.calls.last, 'go');

      await tester.tap(find.text('20%'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%').last);
      await tester.pumpAndSettle();
      expect(host.calls.last, 'hold');
      await tester.tapAndSettle(find.text('Search on this device'));
      expect(host.calls.skip(host.calls.length - 2), ['stop', 'schedule off']);
      await close(tester);
    });

    testWidgets('a desktop without libvips says why nothing is indexed', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await open(tester, decoder: false);
      health.add(fine);
      await tester.pumpAndSettle();
      const line =
          'Search and text reading are unavailable: the image library '
          '(libvips) was not found. Reinstall Photolib, or install libvips '
          'and restart it.';
      expect(find.text(line), findsNothing, reason: 'off until agreed');
      await tester.tapAndSettle(find.text('Search on this device'));
      await tester.pumpAndSettle();
      expect(find.text(line), findsOneWidget);
      await close(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on a metered network the model waits, unless the user '
        'allows it; a server without it says so', (tester) async {
      await open(tester);
      health.add({...fine, 'metered': true});
      host.installing = (_) async => false;
      await tester.pumpAndSettle();
      await tester.tapAndSettle(find.text('Search on this device'));
      expect(find.text('The search model downloads on Wi-Fi'), findsOneWidget);
      expect(host.calls, isEmpty);

      await tester.scrollUntilVisible(
        find.text('Download over mobile data'),
        100,
      );
      await tester.tapAndSettle(find.text('Download over mobile data'));
      expect(host.calls, ['install vision_model_fp16.onnx from mirror']);
      await tester.scrollUntilVisible(find.text('Search on this device'), -100);
      expect(
        find.text('Your server has not installed the search model'),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('a phone indexes its new captures in the foreground and its '
        'backlog in the background task, none in lite mode', (tester) async {
      final db = await open(tester, phone: true);
      health.add(fine);
      await tester.pumpAndSettle();
      await tester.tapAndSettle(find.text('Search on this device'));
      expect(host.calls, [
        'install vision_model_fp16.onnx from mirror',
        'start siglip2-b16-256@onnx-d1114256',
        'schedule on',
        'go',
      ]);

      host.calls.clear();
      expect(await tester.runAsync(() => host.background!()), isFalse);
      await tester.pumpAndSettle();
      expect(host.calls.take(5), [
        'stop',
        'start siglip2-b16-256@onnx-d1114256 with backlog',
        'go',
        'stop',
        'start siglip2-b16-256@onnx-d1114256',
      ]);

      // The OS ends the task before the backlog is done: more is left.
      await tester.runAsync(
        () => db
            .into(db.localAsset)
            .insert(
              LocalAssetCompanion.insert(
                id: Uint8List(16),
                source: 'folder',
                sourceId: '0',
                size: 1,
                mtime: 1,
              ),
            ),
      );
      bool? more;
      unawaited(host.background!().then((m) => more = m));
      await tester.pumpAndSettle();
      expect(more, isNull);
      host.stopBackground!();
      await tester.pump(const Duration(seconds: 1));
      expect(more, isTrue);
      await tester.pumpAndSettle();

      await tester.tapAndSettle(find.text('Search on this device'));
      host.calls.clear();
      health.add({...fine, 'memory': 2900000000});
      await tester.pumpAndSettle();
      expect(
        find.text('This device indexes only its new photos'),
        findsOneWidget,
      );
      await tester.tapAndSettle(find.text('Search on this device'));
      expect(host.calls, [
        'install vision_model_fp16.onnx from mirror',
        'start siglip2-b16-256@onnx-d1114256',
        'go',
      ]);
      await close(tester);
    });

    testWidgets('the photos it could not read are listed with why', (
      tester,
    ) async {
      final db = Replica(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.runAsync(() async {
        await db
            .into(db.localAsset)
            .insert(
              LocalAssetCompanion.insert(
                id: Uint8List(16),
                source: 'folder',
                sourceId: '0',
                size: 1,
                mtime: 1,
                name: const Value('broken.dng'),
              ),
            );
        await db
            .into(db.localMl)
            .insert(
              LocalMlData(
                localAssetId: Uint8List(16),
                model: 'm@1',
                size: 1,
                mtime: 1,
                failure: 'unreadable by vips 8.15.1',
                rtFlags: 'onnxruntime 1.31.0 CPU fp16',
              ),
            );
      });
      await pumpApp(tester, replica: (_) => db);
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.scrollTo(find.text('1 photo could not be read'));
      await tester.tapAndSettle(find.text('1 photo could not be read'));
      expect(find.text('broken.dng'), findsOneWidget);
      expect(find.text('unreadable by vips 8.15.1'), findsOneWidget);
      await close(tester);
    });
  });

  testWidgets('scrolling tells on-device ML, at most once a second', (
    tester,
  ) async {
    var told = 0;
    await pumpApp(
      tester,
      overrides: [interactionProvider.overrideWithValue(() => told++)],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(told, 1);
  });
}
