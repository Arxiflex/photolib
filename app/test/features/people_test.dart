import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_health.dart';
import 'package:photolib/core/on_device_ml.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/fake_server.dart';
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
  late RecordingMlHost host;
  late Replica db;

  Future<void> open(
    WidgetTester tester, {
    FakeServer? server,
    bool decoder = true,
  }) async {
    db = Replica(NativeDatabase.memory());
    addTearDown(db.close);
    // Faces the device found before, and a result of another model.
    await tester.runAsync(() async {
      for (final model in ['faces:yunet@2026may+sface@2021dec', 'm@1']) {
        await db
            .into(db.localMl)
            .insert(
              LocalMlData(
                localAssetId: Uint8List(16)..[15] = model.length,
                model: model,
                size: 1,
                mtime: 1,
                rtFlags: 'onnxruntime 1.31.0 CPU fp32',
              ),
            );
      }
    });
    host = RecordingMlHost();
    await pumpApp(
      tester,
      replica: (_) => db,
      overrides: [
        deviceHealthProvider.overrideWith((ref) => Stream.value(fine)),
        mlHostProvider.overrideWith((ref) async => decoder ? host : null),
        if (server != null) sessionProvider.overrideWithValue(server),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.scrollTo(find.text('Find faces in my photos'));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('nothing about faces is downloaded, run or kept until the user '
      'agrees to the notice, and withdrawing deletes what was found', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.text('Off. Nothing about faces is computed until you agree.'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(host.calls, isEmpty);

    // The notice says what, where, how long and that it is optional.
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    expect(find.text('Find faces in your photos?'), findsOneWidget);
    expect(find.textContaining('biometric data'), findsOneWidget);
    expect(find.textContaining('your own server'), findsOneWidget);
    expect(find.textContaining('This is optional'), findsOneWidget);
    await tester.tapAndSettle(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(host.calls, isEmpty, reason: 'declined');
    expect(
      find.text('Off. Nothing about faces is computed until you agree.'),
      findsOneWidget,
    );

    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(host.calls.take(3), [
      'install face_detection_yunet_2026may.onnx from mirror',
      'install face_recognition_sface_2021dec.onnx from mirror',
      'faces yunet@2026may sface@2021dec with backlog',
    ]);
    expect(find.text('Finding faces on this device'), findsOneWidget);

    host.calls.clear();
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    expect(find.text('Stop finding faces?'), findsOneWidget);
    await tester.tapAndSettle(find.text('Delete and stop'));
    await tester.pumpAndSettle();
    expect(host.calls, contains('faces stop'));
    final left = await tester.runAsync(() => db.select(db.localMl).get());
    expect([for (final r in left!) r.model], ['m@1']);
    expect(
      find.text('Off. Nothing about faces is computed until you agree.'),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('a desktop without libvips says so instead of showing nothing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await open(tester, decoder: false);
    const line =
        'Face finding is unavailable: the image library (libvips) was not '
        'found. Reinstall Photolib, or install libvips and restart it.';
    expect(find.text(line), findsNothing, reason: 'off until agreed');
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(find.text(line), findsOneWidget);
    expect(host.calls, isEmpty, reason: 'no model downloads without a decoder');
    debugDefaultTargetPlatformOverride = null;
    await close(tester);
  });

  testWidgets('a phone without a host is not blamed on libvips', (
    tester,
  ) async {
    await open(tester, decoder: false);
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(find.textContaining('libvips'), findsNothing);
    await close(tester);
  });

  testWidgets('a signed-in user tells their server too, and withdrawing tells '
      'it again', (tester) async {
    final server = FakeServer({
      'FaceService/GetFaceConsent': (_) => GetFaceConsentResponse(
        state: FaceConsentState(noticeVersion: 1, available: true),
      ),
      'FaceService/SetFaceConsent': (request) => SetFaceConsentResponse(
        state: FaceConsentState(
          noticeVersion: 1,
          available: true,
          granted: (request as SetFaceConsentRequest).granted,
        ),
      ),
    });
    await open(tester, server: server);
    expect(server.requests('FaceService/SetFaceConsent'), isEmpty);
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('I agree'));
    await tester.pumpAndSettle();
    final agreed = server.requests<SetFaceConsentRequest>(
      'FaceService/SetFaceConsent',
    );
    expect([for (final r in agreed) (r.granted, r.noticeVersion)], [(true, 1)]);

    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('Delete and stop'));
    await tester.pumpAndSettle();
    final all = server.requests<SetFaceConsentRequest>(
      'FaceService/SetFaceConsent',
    );
    expect([for (final r in all) r.granted], [true, false]);
    await close(tester);
  });

  testWidgets('a server that cannot be told does not stop this device from '
      'honouring the answer, and says so', (tester) async {
    final server = FakeServer({
      'FaceService/SetFaceConsent': (_) => Unreachable('offline'),
    });
    await open(tester, server: server);
    await tester.tapAndSettle(find.text('Find faces in my photos'));
    await tester.tapAndSettle(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your server could not be told. Try again.'),
      findsOneWidget,
    );
    expect(host.calls, isNotEmpty, reason: 'this device found its answer');
    await close(tester);
  });
}
