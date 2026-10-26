import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/ml_host.dart';
import '../support/pump_app.dart';

void main() {
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
  late Replica db;

  Future<void> open(
    WidgetTester tester, {
    bool phone = false,
    bool platformText = false,
  }) async {
    db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    health = StreamController<Map<Object?, Object?>>();
    addTearDown(health.close);
    host = RecordingMlHost(
      phone: phone,
      target: phone ? 'android' : 'linux',
      platformText: platformText,
    );
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
              model: ocrModel,
              size: 1,
              mtime: 1,
              ocrText: 'Москва',
              ocrFolded: 'москва',
              rtFlags: 'onnxruntime 1.31.0 CPU fp32',
            ),
          );
    });
    await pumpApp(
      tester,
      replica: (_) => db,
      overrides: [
        deviceHealthProvider.overrideWith((ref) => health.stream),
        mlHostProvider.overrideWith((ref) async => host),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Search on this device'), 100);
    if (!phone || platformText) {
      await tester.scrollUntilVisible(find.text('Read text in photos'), 100);
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  const asked =
      'Downloads the text models (188 MB) from huggingface.co; '
      'finds the words in your photos';

  testWidgets('nothing downloads until the user agrees; then the four models '
      'download, in order, read the photos and stop when the user says', (
    tester,
  ) async {
    await open(tester);
    health.add(fine);
    await tester.pumpAndSettle();
    expect(find.text(asked), findsOneWidget);
    expect(host.calls, isEmpty);

    final downloaded = Completer<bool>();
    host.installing = (progress) {
      progress(7862832);
      return downloaded.future;
    };
    await tester.tapAndSettle(find.text('Read text in photos'));
    expect(host.calls, ['install det.onnx from mirror']);
    expect(find.textContaining('Downloading the text models:'), findsOneWidget);

    host.installing = null;
    downloaded.complete(true);
    await tester.pumpAndSettle();
    expect(host.calls.skip(1), [
      'install rec.onnx from mirror',
      'install rec.onnx from mirror',
      'install rec.onnx from mirror',
      [
        'start text ppocr-v5-det,ppocr-v5-rec-latin,ppocr-v5-rec-eslav,',
        'ppocr-v5-rec-chinese with backlog',
      ].join(),
      'go',
    ]);

    // How far it is: the photos read, of all the library shows.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Photos read for text: 1 of 3'), findsOneWidget);

    health.add({...fine, 'thermal': 3});
    await tester.pumpAndSettle();
    expect(host.calls.last, 'hold');

    await tester.tapAndSettle(find.text('Read text in photos'));
    expect(host.calls.last, 'stop text');
    await close(tester);
  });

  testWidgets('on a metered network the text models wait; a server without '
      'them says so', (tester) async {
    await open(tester);
    health.add({...fine, 'metered': true});
    host.installing = (_) async => false;
    await tester.pumpAndSettle();
    await tester.tapAndSettle(find.text('Read text in photos'));
    expect(find.text('The text models download on Wi-Fi'), findsOneWidget);
    expect(host.calls, isEmpty);

    await tester.scrollUntilVisible(
      find.text('Download over mobile data'),
      100,
    );
    await tester.tapAndSettle(find.text('Download over mobile data'));
    expect(host.calls, ['install det.onnx from mirror']);
    expect(
      find.text('Your server has not installed the text models'),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('a phone without text recognition of its own offers none', (
    tester,
  ) async {
    await open(tester, phone: true);
    health.add(fine);
    await tester.pumpAndSettle();
    expect(find.text('Read text in photos'), findsNothing);
    expect(host.calls, isEmpty);
    await close(tester);
  });

  testWidgets('a phone reads with the platform: nothing downloads, only new '
      'photos are read, and the device gates still hold', (tester) async {
    await open(tester, phone: true, platformText: true);
    health.add({...fine, 'metered': true});
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Uses your phone's own text recognition; nothing to download. "
        'Reads new photos',
      ),
      findsOneWidget,
    );
    expect(host.calls, isEmpty);

    await tester.tapAndSettle(find.text('Read text in photos'));
    expect(host.calls, ['start text ', 'go'], reason: 'no install, no backlog');

    health.add({...fine, 'powerSaving': true});
    await tester.pumpAndSettle();
    expect(host.calls.last, 'hold');

    await tester.tapAndSettle(find.text('Read text in photos'));
    expect(host.calls.last, 'stop text');
    await close(tester);
  });
}
