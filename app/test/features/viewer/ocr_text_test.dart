import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib_api/photolib_api.dart'
    show GetTextRequest, GetTextResponse;
import 'package:photolib_data/photolib_data.dart' show uuidOf;

import '../../support/fake_server.dart';
import '../../support/viewer.dart';

/// Text a picture can hold: markup that must stay what it is, text.
const payload = '<img src=x onerror=alert(1)>\n東京駅 丸の内';

void main() {
  const size = Size(1600, 600);
  const settings = Settings(bar: [ViewerAction.copyText]);

  late List<String> clipboard;
  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  FakeServer serverSaying(GetTextResponse answer) =>
      FakeServer({'SearchService/GetText': (_) => answer});

  testWidgets('a picture the server read shows its text as text, which '
      'copies as it is', (tester) async {
    final server = serverSaying(GetTextResponse(text: payload, read: true));
    await pumpViewer(
      tester,
      size: size,
      assets: true,
      settings: settings,
      overrides: [sessionProvider.overrideWithValue(server)],
    );
    await tester.tap(find.byTooltip('Copy text'));
    await tester.pumpAndSettle();
    expect(
      server.requests<GetTextRequest>('SearchService/GetText').single.assetId,
      uuidOf(idOf(0)),
    );
    expect(find.text('Text in this photo'), findsOneWidget);
    // Markup is a string of characters in a text widget, never parsed.
    final shown = find.byType(SelectableText);
    expect(tester.widget<SelectableText>(shown).data, payload);
    await tester.tap(find.widgetWithText(TextButton, 'Copy text'));
    await tester.pumpAndSettle();
    expect(clipboard, [payload]);
    expect(find.text('Text copied'), findsOneWidget);
  });

  testWidgets('a picture with no text, or not read yet, says so', (
    tester,
  ) async {
    for (final (answer, message) in [
      (GetTextResponse(read: true), 'No text found in this photo'),
      (GetTextResponse(), "This photo's text has not been read yet"),
    ]) {
      await pumpViewer(
        tester,
        size: size,
        assets: true,
        settings: settings,
        overrides: [sessionProvider.overrideWithValue(serverSaying(answer))],
      );
      await tester.tap(find.byTooltip('Copy text'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(clipboard, isEmpty);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('without a server, or for a picture it does not hold, the '
      'action is off in its place', (tester) async {
    Future<bool> enabled({required bool assets, FakeServer? server}) async {
      await pumpViewer(
        tester,
        size: size,
        assets: assets,
        settings: settings,
        overrides: [sessionProvider.overrideWithValue(server)],
      );
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.text_snippet_outlined),
      );
      await tester.pumpWidget(const SizedBox());
      return button.onPressed != null;
    }

    expect(await enabled(assets: true), isFalse, reason: 'signed out');
    expect(
      await enabled(assets: false, server: FakeServer()),
      isFalse,
      reason: 'a file only this device has',
    );
    expect(await enabled(assets: true, server: FakeServer()), isTrue);
  });
}
