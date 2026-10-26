import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/core/photo_kit.dart';
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
          const MethodChannel('org.photolib/photo_kit'),
          (call) async {
            calls.add('${call.method} ${call.arguments}');
            return answers[call.method];
          },
        );
  });

  test('pages of assets arrive as the JSON text SQLite writes', () async {
    answers = {
      'access': 'partial',
      'installId': 'install',
      'token': 'T1',
      'changedSince': ['A/L0/001', 'B/L0/001'],
      'assets': '[["A/L0/001"]]',
      'assetsOf': '[]',
    };
    const library = PhotoKitChannel();

    expect(await library.access(), MediaAccess.partial);
    expect(await library.installId(), 'install');
    expect(await library.token(), 'T1');
    expect(await library.changedSince('T0'), ['A/L0/001', 'B/L0/001']);
    expect(await library.assets(2000, 500), '[["A/L0/001"]]');
    expect(await library.assetsOf(['A/L0/001', 'B/L0/001']), '[]');
    answers['changedSince'] = null;
    expect(await library.changedSince('T0'), isNull);
    expect(calls, [
      'access null',
      'installId null',
      'token null',
      'changedSince T0',
      'assets [2000, 500]',
      'assetsOf [A/L0/001, B/L0/001]',
      'changedSince T0',
    ]);
  });

  testWidgets(
    'limited access is explained, with the picker to select more photos',
    (tester) async {
      answers = {'access': 'partial', 'requestAccess': 'partial'};
      await pumpApp(
        tester,
        overrides: [
          deviceLibraryProvider.overrideWithValue(const PhotoKitChannel()),
          mediaIndexProvider.overrideWithValue(() async {}),
        ],
      );
      expect(
        find.textContaining('Photolib sees only the photos and videos'),
        findsOneWidget,
      );

      await tester.tapAndSettle(find.text('Select more photos'));
      await tester.tapAndSettle(find.text('Allow access'));

      expect(calls, ['access null', 'select null', 'requestAccess null']);
      expect(find.byType(MaterialBanner), findsOneWidget);
    },
  );
}
