import 'dart:convert';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/admin/admin_page.dart';
import 'package:photolib/features/servers/servers.dart';

import 'fake_server.dart';
import 'pump_app.dart';

/// Opens the console from the settings, on a desktop-sized window.
Future<void> openConsole(
  WidgetTester tester,
  FakeServer server, {
  SavedServer? saved,
  List<Override> overrides = const [],
}) async {
  await pumpApp(
    tester,
    size: const Size(1200, 900),
    serverStore: MemoryStore(saved == null ? null : jsonEncode(saved.toJson())),
    overrides: [adminClientProvider.overrideWithValue(server), ...overrides],
  );
  await tester.tapAndSettle(find.byIcon(Icons.settings_outlined));
  await tester.scrollTo(find.text('Server administration'));
  await tester.tapAndSettle(find.text('Server administration'));
}

Future<void> section(WidgetTester tester, String name) =>
    tester.tapAndSettle(find.widgetWithText(ListTile, name));

Future<void> dialogField(WidgetTester tester, String label, String text) =>
    tester.enterText(find.widgetWithText(TextFormField, label), text);
