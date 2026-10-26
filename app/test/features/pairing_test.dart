import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/pairing.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

// Pairing (MOB-16, MOB-17): one link, or its QR code, brings a server's LAN
// and WAN addresses, the certificate it pins and its instance, so nobody
// types a URL.
void main() {
  final wan = Uri.parse('https://photos.example.org/photolib/');
  final lan = Uri.parse('http://192.168.1.10:8080/');
  final pin = '0f1e2d3c4b5a6978' * 4;
  final server = SavedServer(
    endpoints: [wan, lan],
    instance: '018f9d2e-7c1b-7d6e-9a3f-2b4c5d6e7f80',
    pin: pin,
  );

  test('a pairing link carries every address, the pin and the instance', () {
    final link = '${pairingLink(server)}';
    expect(link, startsWith('https://photos.example.org/photolib/#/pair?'));
    final paired = pairing('\n  $link  \n')!;
    expect(paired.endpoints, [wan.removeFragment(), lan]);
    expect((paired.pin, paired.instance), (pin, server.instance));
    expect(pairing('photos.example.org'), isNull);
  });

  test('a password setup link pairs too, and still sets the password', () {
    final link = '${pairingLink(server, (handle: 'ann', token: 'ab12'))}';
    expect(passwordSetup(link), (handle: 'ann', token: 'ab12'));
    expect(pairing(link)!.endpoints, [wan.removeFragment(), lan]);
    expect(pairing(link)!.pin, pin);
  });

  group('pasted into Add a server', () {
    late MemoryStore keystore;
    late List<String?> instances;
    setUp(() {
      keystore = MemoryStore();
      instances = [];
    });

    Future<void> add(WidgetTester tester, String epoch) async {
      final fake = FakeServer({
        'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
          epoch: epoch,
          authMethods: [AuthMethod.AUTH_METHOD_OPAQUE],
        ),
      });
      await pumpApp(
        tester,
        serverStore: keystore,
        overrides: [
          connectProvider.overrideWithValue((config, instance) {
            instances.add(instance);
            return fake;
          }),
          certificateProvider.overrideWithValue(
            (config, url) async => fail('no certificate to confirm'),
          ),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('Add a server'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Addresses'),
        '${pairingLink(server)}',
      );
      await tester.tapAndSettle(find.text('Connect'));
    }

    SavedServer? saved() => keystore.value == null
        ? null
        : Accounts.fromJson(jsonDecode(keystore.value!) as Map).server;

    testWidgets('a pairing link adds the server with its addresses and pin, '
        'asking nothing', (tester) async {
      await add(tester, '${server.instance}.0');
      expect(saved()!.endpoints, [wan.removeFragment(), lan]);
      expect((saved()!.pin, saved()!.instance), (pin, server.instance));
      expect(instances.first, server.instance);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('a server on this network is listed and added with a tap, '
        'with its LAN and WAN addresses', (tester) async {
      final fake = FakeServer({
        'ServerInfoService/GetServerInfo': (_) => GetServerInfoResponse(
          epoch: 'instance-a.0',
          authMethods: [AuthMethod.AUTH_METHOD_OPAQUE],
        ),
      });
      await pumpApp(
        tester,
        serverStore: keystore,
        overrides: [
          connectProvider.overrideWithValue((config, instance) => fake),
        ],
        nearby: [
          (name: 'photolib-018f9d2e', endpoints: [lan, wan], instance: 'i'),
        ],
      );
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('Add a server'));
      expect(find.text('Servers on this network'), findsOneWidget);
      await tester.tapAndSettle(find.text('photolib-018f9d2e'));
      expect(saved()!.endpoints, [lan, wan]);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('a pairing link answered by another server adds nothing', (
      tester,
    ) async {
      await add(tester, 'another-instance.0');
      expect(saved(), isNull);
      expect(find.text('The server does not answer.'), findsOneWidget);
    });
  });
}
