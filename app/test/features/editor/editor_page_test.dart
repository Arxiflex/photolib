import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/editor/editor_page.dart';
import 'package:photolib/features/editor/save_copy.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_editor/edit.dart';

/// A 40 × 30 picture, as the viewer hands the editor.
ui.Image picture() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff405060), BlendMode.src);
  return recorder.endRecording().toImageSync(40, 30);
}

final original = ThumbnailItem('1', Uri.file('/p/1.jpg'));
final copy = ThumbnailItem('2', Uri.file('/p/1_edit.jpg'));

/// The editor over a page that opens it, saving with [save]; its route's
/// result is `closed`.
Future<({Future<ThumbnailItem?> closed})> pumpEditor(
  WidgetTester tester,
  SaveCopy save,
) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [saveCopyProvider.overrideWithValue(save)],
      child: MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    ),
  );
  final result = navigator.currentState!.push(
    MaterialPageRoute<ThumbnailItem>(
      builder: (_) => EditorPage(item: original, image: picture()),
    ),
  );
  await tester.pumpAndSettle();
  return (closed: result);
}

void main() {
  testWidgets('rotates, mirrors and crops what it shows, and saves that as '
      'a copy', (tester) async {
    Edit? saved;
    final result = await pumpEditor(tester, (item, edit, time) async {
      saved = edit;
      return copy;
    });
    final save = find.widgetWithText(TextButton, 'Save copy');
    expect(tester.widget<TextButton>(save).onPressed, isNull);
    await tester.tap(find.byTooltip('Rotate'));
    await tester.tap(find.byTooltip('Flip'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 3);
    // Turned, the picture is 30 × 40, shown 360 px wide in its 400 px.
    final frame = tester.getRect(find.byKey(const ValueKey('crop')));
    expect(frame.width / frame.height, closeTo(0.75, 0.01));
    await tester.drag(
      find.byKey(const ValueKey(Offset(-1, -1))),
      Offset(frame.width / 2, frame.height / 4),
    );
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await result.closed, copy);
    expect((saved!.quarterTurns, saved!.flip), (3, true));
    expect(saved!.crop.left, closeTo(0.5, 0.05));
    expect(saved!.crop.top, closeTo(0.25, 0.05));
    expect((saved!.crop.right, saved!.crop.bottom), (1, 1));
  });

  testWidgets('auto-enhance previews its numbers through the shaders and '
      'saves them', (tester) async {
    Edit? saved;
    final result = await pumpEditor(tester, (item, edit, time) async {
      saved = edit;
      return copy;
    });
    final shown = tester.widget<RawImage>(find.byType(RawImage)).image;
    await tester.tap(find.byTooltip('Auto-enhance'));
    // The pixels, the shaders and their render come from the engine.
    await tester.runAsync(() async {
      while (tester.widget<RawImage>(find.byType(RawImage)).image == shown) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    final enhanced = tester.widget<RawImage>(find.byType(RawImage)).image!;
    final pixels = await tester.runAsync(enhanced.toByteData);
    final before = await tester.runAsync(shown!.toByteData);
    expect(pixels!.buffer.asUint8List(), isNot(before!.buffer.asUint8List()));
    await tester.tap(find.widgetWithText(TextButton, 'Save copy'));
    await tester.pumpAndSettle();
    expect(await result.closed, copy);
    expect(saved!.enhance!.exposure, isNot(0));
  });

  testWidgets('a square crop is the largest one centred', (tester) async {
    await pumpEditor(tester, (item, edit, time) async => copy);
    await tester.tap(find.byTooltip('Crop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle();
    final frame = tester.getRect(find.byKey(const ValueKey('crop')));
    expect(frame.width, closeTo(frame.height, 1));
    expect(
      frame.height,
      closeTo(tester.getSize(find.byType(RawImage)).height, 1),
    );
  });

  testWidgets('a failed save says so and keeps the edit', (tester) async {
    await pumpEditor(
      tester,
      (item, edit, time) async => throw StateError('the disk is full'),
    );
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save copy'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't save the copy"), findsOneWidget);
    expect(find.byType(EditorPage), findsOneWidget);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 3);
  });
  testWidgets('a cancelled save keeps the edit and says nothing', (
    tester,
  ) async {
    await pumpEditor(tester, (item, edit, time) async => null);
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save copy'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final save = find.widgetWithText(TextButton, 'Save copy');
    expect(tester.widget<TextButton>(save).onPressed, isNotNull);
  });
}
