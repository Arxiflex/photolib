import 'dart:async';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/upload/upload.dart';

import '../../support/pump_app.dart';
import '../../support/server_app.dart';

void main() {
  setUpServerApp();
  final dir = Directory.systemTemp.createTempSync('photolib-upload-ui-');
  tearDownAll(() => dir.deleteSync(recursive: true));

  XFile file(String name, List<int> bytes) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
    return XFile('${dir.path}/$name');
  }

  Future<void> pump(WidgetTester tester) => pumpServerApp(
    tester,
    overrides: [
      uploadPickerProvider.overrideWithValue(
        () async => [
          file('a.jpg', [1]),
          file('b.jpg', [2]),
        ],
      ),
    ],
  );

  testWidgets('the library offers no upload while signed out', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Upload photos and videos'), findsNothing);
  });

  testWidgets('an upload that hashes shows its progress', (tester) async {
    keep(ann);
    final hashing = Completer<String>();
    await pumpServerApp(
      tester,
      overrides: [
        uploadPickerProvider.overrideWithValue(
          () async => [
            file('a.jpg', [1]),
          ],
        ),
        uploadHasherProvider.overrideWithValue((file, progress) {
          progress(0.5);
          return hashing.future;
        }),
      ],
    );
    await tester.tap(find.byTooltip('Upload photos and videos'));
    await tester.pumpUntil(
      () => find.byType(LinearProgressIndicator).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );
    hashing.complete('cafe');
    await tester.pumpUntil(
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    expect(server.uploads.single.blake3, 'cafe');
  });

  testWidgets('the library offers uploads once signed in, and says how they '
      'went', (tester) async {
    keep(ann);
    await pump(tester);
    server.refuseUpload = 'b.jpg';
    await tester.tap(find.byTooltip('Upload photos and videos'));
    await tester.pumpUntil(
      () => find.text('Uploaded 1 of 2 · Failed: 1').evaluate().isNotEmpty,
    );
    expect(server.uploads.map((u) => u.path), ['a.jpg']);
    expect(find.text('Uploaded 1 of 2 · Failed: 1'), findsOneWidget);
    await tester.tapAndSettle(find.text('Clear'));
    expect(find.textContaining('Uploaded'), findsNothing);
  });
}
