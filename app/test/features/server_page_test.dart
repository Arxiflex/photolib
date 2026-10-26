import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/server_pages.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/tiles.dart';

void main() {
  const passkey =
      'This server requires a passkey, which this version of Photolib '
      'cannot use yet.';
  const ended = 'The server ended this session. Sign in again.';
  for (final (state, account, tiles) in [
    ('signed out', null, <String>[]),
    (
      'signed in',
      const Account(name: 'ann', token: 't', deviceId: 'd'),
      ['Signed in as ann', 'Second factors', 'Your devices'],
    ),
    ('on a server that takes passkeys only', null, [passkey]),
    ('after the server ended the session', null, [ended]),
  ]) {
    testWidgets('the server page $state starts its tiles where its buttons '
        'do', (tester) async {
      final saved = SavedServer(
        endpoints: [Uri.parse('https://photos.example.org')],
        instance: 'instance-a',
        account: account,
        ended: tiles.contains(ended),
      );
      final server = FakeServer({
        if (tiles.contains(passkey))
          'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
            epoch: 'instance-a.0',
            authMethods: [AuthMethod.AUTH_METHOD_PASSKEY],
          ),
      });
      await pumpApp(
        tester,
        serverStore: MemoryStore(jsonEncode(saved.toJson())),
        overrides: [
          connectProvider.overrideWithValue((config, instance) => server),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('photos.example.org'));
      final start = tester
          .getTopLeft(find.widgetWithText(TextButton, 'Remove this server'))
          .dx;
      expect(tester.tileStarts(find.byType(ServerPage)), {
        'https://photos.example.org': start,
        'Check the connection': start,
        for (final tile in tiles) tile: start,
      });
    });
  }
}
