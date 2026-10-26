// A photo only the server has is edited into a new version of it, not a copy
// (ADR-0391), and its history is read and reverted from the viewer.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/editor/versions.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/viewer/info_facts.dart';
import 'package:photolib_api/photolib_api.dart' show GetServerInfoResponse;
import 'package:photolib_editor/edit.dart';

import '../../support/fake_server.dart';
import '../../support/info_facts.dart';
import '../../support/viewer.dart';

void main() {
  const size = Size(1200, 800);
  final saved = <(ThumbnailItem, Edit)>[];
  setUp(saved.clear);

  FakeServer server({bool versions = true}) => FakeServer({
    'ServerInfoService/GetServerInfo': (_) =>
        GetServerInfoResponse(capabilities: [if (versions) 'sync.versions.v1']),
  });

  testWidgets('a photo only the server has is edited, and the edit is saved '
      'as a version, never as a copy; the viewer stays where it was', (
    tester,
  ) async {
    final position = await pumpViewer(
      tester,
      size: size,
      at: 1,
      server: true,
      overrides: [
        sessionProvider.overrideWithValue(server()),
        saveVersionProvider.overrideWithValue((item, edit) async {
          saved.add((item, edit));
          return Uint8List(16);
        }),
      ],
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Save copy'), findsNothing);
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    final (item, edit) = saved.single;
    expect(serverAssetOf(item), idOf(1));
    expect(edit.quarterTurns, 3);
    expect(position.value, 1);
    expect(find.text('Saved as a new version'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget, reason: 'edited again');
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Saved as a new version'), findsNothing);
  });

  testWidgets('a server that cannot keep versions says so and keeps the '
      'editor open with the edit', (tester) async {
    await pumpViewer(
      tester,
      size: size,
      server: true,
      overrides: [sessionProvider.overrideWithValue(server(versions: false))],
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('This server cannot keep versions of edited photos yet'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
  });

  testWidgets('without a session there is no version to save: the action is '
      'off', (tester) async {
    await pumpViewer(tester, size: size, server: true);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Rotate'), findsNothing, reason: 'no editor opened');
  });

  testWidgets('a file on the device is edited into a copy beside it, whatever '
      'the server holds of it', (tester) async {
    await pumpViewer(
      tester,
      size: size,
      assets: true,
      overrides: [sessionProvider.overrideWithValue(server())],
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Save copy'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
  });

  testWidgets('the history of a photo only the server has opens from ⋮, newest '
      'first, and an older version is reverted', (tester) async {
    final facts = FakeFacts(
      history: [
        InfoVersion('Original', DateTime(2026, 10, 20), original: true),
        InfoVersion('Crop', DateTime(2026, 10, 23), current: true),
      ],
    );
    await pumpViewer(
      tester,
      size: size,
      server: true,
      overrides: [
        sessionProvider.overrideWithValue(server()),
        infoFactsProvider.overrideWith((ref) async => facts),
      ],
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit history'));
    await tester.pumpAndSettle();
    expect(find.text('Crop · Current'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    await tester.tap(find.text('Revert'));
    await tester.pumpAndSettle();
    expect(facts.calls, ['revert Original']);
  });
}
