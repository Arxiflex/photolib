import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/media_store.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/pump_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  late Map<String, Object?> answers;
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.photolib/media_store'),
          (call) async {
            calls.add('${call.method} ${call.arguments}');
            return answers[call.method];
          },
        );
  });

  test('pages of MediaStore items arrive as flat lists', () async {
    answers = {
      'volumes': ['external_primary', '0000-0000'],
      'root': '/storage/emulated/0',
      'ids': Int64List.fromList([3, 9]),
      'items': [
        ...[3, 2, 1024, 1700000000000, 'a.jpg', 'image/jpeg', 'DCIM/'],
        ...['77', 'DCIM', 1600000000000, 4000, 3000, 90, null, true, false],
        null,
        ...[9, 5, 2048, 1700000001000, null, 'video/mp4', null, null, null],
        ...[null, null, null, null, 1500, false, true, 1800000000000],
      ],
    };
    const store = MediaStoreChannel();

    expect(await store.volumes(), ['external_primary', '0000-0000']);
    expect(await store.root('external_primary'), '/storage/emulated/0');
    expect(calls.last, 'root external_primary');
    expect(await store.ids('external_primary'), [3, 9]);
    final items = await store.items(
      'external_primary',
      since: 1,
      after: 2,
      limit: 2,
    );
    expect(calls.last, 'items [external_primary, 1, 2, 2]');
    String describe(MediaStoreItem i) =>
        '${i.id} ${i.generation} ${i.size} ${i.modified} ${i.name} ${i.mime} '
        '${i.path} ${i.bucketId} ${i.bucketName} ${i.taken} ${i.width} '
        '${i.height} ${i.orientation} ${i.durationMs} ${i.favorite} '
        '${i.trashed} ${i.expires}';
    expect(items.map(describe), [
      '3 2 1024 1700000000000 a.jpg image/jpeg DCIM/ 77 DCIM 1600000000000 '
          '4000 3000 90 null true false null',
      '9 5 2048 1700000001000  video/mp4    null null null null 1500 false '
          'true 1800000000000',
    ]);
  });

  test('calls while a run is going make one more run, not one each', () async {
    var runs = 0;
    final release = <Completer<void>>[];
    final index = Coalesced(() {
      runs++;
      return (release..add(Completer())).last.future;
    });

    final first = index();
    index();
    index();
    expect(runs, 1);
    release.last.complete();
    await pumpEventQueue();
    expect(runs, 2);
    release.last.complete();
    await first;
    expect(runs, 2);
  });

  for (final (granted, message) in [
    ('none', 'Photolib needs access to your photos and videos to show them.'),
    ('partial', 'Photolib sees only the photos and videos you selected.'),
  ]) {
    testWidgets('with $granted access the library says so until granted', (
      tester,
    ) async {
      answers = {'access': granted, 'requestAccess': 'full'};
      var indexed = 0;
      await pumpApp(
        tester,
        overrides: [
          deviceLibraryProvider.overrideWithValue(const MediaStoreChannel()),
          mediaIndexProvider.overrideWithValue(() async => indexed++),
        ],
      );
      expect(find.textContaining(message), findsOneWidget);
      expect(indexed, granted == 'none' ? 0 : 1);

      await tester.tapAndSettle(find.text('Allow access'));

      expect(calls, ['access null', 'requestAccess null']);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(indexed, granted == 'none' ? 1 : 2);
    });
  }
}
