import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/connection_check.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

// The connection check (OPS-29): each injected fault names its step, a plain
// cause, the next step and a fix one tap away.
void main() {
  late MemoryStore keystore;
  late Map<Uri, List<Finding>> findings;
  late List<NetworkConfig> checked;
  final lan = Uri.parse('http://192.168.1.10:8080/');
  final wan = Uri.parse('https://photos.example.org/');
  const fingerprint =
      '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0';

  setUp(() {
    keystore = MemoryStore(
      jsonEncode(
        SavedServer(
          endpoints: [wan, lan],
          instance: 'instance-a',
          account: const Account(
            name: 'ann',
            token: 'token-1',
            deviceId: 'device-1',
          ),
        ).toJson(),
      ),
    );
    checked = [];
    findings = {};
  });

  SavedServer saved() =>
      Accounts.fromJson(jsonDecode(keystore.value!) as Map).server!;

  /// Every step passes but those [failed] names, each with its finding.
  List<Finding> run(Map<CheckStep, Finding> failed) => [
    for (final step in CheckStep.values) failed[step] ?? Finding(step),
  ];

  /// The icons whose screen reader label is [state].
  Finder state(String state) => find.byWidgetPredicate(
    (widget) => widget is Icon && widget.semanticLabel == state,
  );

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      size: const Size(500, 1400),
      serverStore: keystore,
      overrides: [
        connectProvider.overrideWithValue((config, instance) => FakeServer()),
        checkProvider.overrideWithValue((config, endpoint, instance) {
          checked.add(config);
          return Stream.fromIterable(findings[endpoint] ?? run({}));
        }),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('photos.example.org'));
    await tester.tapAndSettle(find.text('Check the connection'));
  }

  for (final (name, finding, step, cause, fix) in [
    (
      'a wrong DNS name',
      const Finding(CheckStep.dns, fault: Fault.dnsFailed),
      "Finding the server's address",
      "The server's name does not lead to an address.",
      'Try again',
    ),
    (
      'an expired certificate',
      Finding(
        CheckStep.tls,
        fault: Fault.certificateExpired,
        date: DateTime(2026, 3, 2),
      ),
      'Secure connection and certificate',
      "The server's certificate expired on Mar 2, 2026.",
      'Copy details',
    ),
    (
      'a self-signed certificate without a pin',
      const Finding(
        CheckStep.tls,
        fault: Fault.selfSigned,
        fingerprint: fingerprint,
      ),
      'Secure connection and certificate',
      'The server uses a certificate of its own, which this device does not '
          'know yet.',
      'Trust',
    ),
    (
      'a bad token',
      const Finding(CheckStep.auth, fault: Fault.signedOut),
      'Your sign-in',
      'You are signed out of the server.',
      'Sign in',
    ),
    (
      "a proxy's 413",
      const Finding(CheckStep.upload, fault: Fault.uploadCap),
      'Large uploads through proxies',
      'A proxy on the way refuses large uploads, so backups go slower, in '
          'small pieces.',
      'Copy details',
    ),
    (
      'a metered network',
      const Finding(CheckStep.network, fault: Fault.metered),
      'Your network',
      'You are on a metered network, such as mobile data.',
      'Try again',
    ),
    (
      'a clock 10 minutes off',
      const Finding(CheckStep.clock, fault: Fault.clockSkew, minutes: 10),
      "Your device's clock",
      "This device's clock and the server's differ by more than five "
          'minutes.',
      'Try again',
    ),
  ]) {
    testWidgets('$name names its step, a plain cause and a fix', (
      tester,
    ) async {
      findings[wan] = run({finding.step: finding});
      await open(tester);
      final row = find.ancestor(
        of: find.text(cause),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: row, matching: find.text(step)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: state('Failed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(fix)),
        findsOneWidget,
      );
      expect(state('Failed'), findsOneWidget);
      expect(state('Passed'), findsNWidgets(CheckStep.values.length * 2 - 1));
    });
  }

  test('only mobile data, without Wi-Fi or Ethernet, is metered', () {
    final (mobile, wifi, ethernet, vpn) = (
      ConnectivityResult.mobile,
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
    );
    expect(
      [
        [mobile],
        [mobile, vpn],
        [mobile, wifi],
        [ethernet],
        [vpn],
        <ConnectivityResult>[],
      ].map(metered),
      [true, true, false, false, false, false],
    );
  });

  testWidgets('runs every step on every address, in order', (tester) async {
    findings[lan] = [
      const Finding(CheckStep.dns),
      const Finding(CheckStep.tcp, fault: Fault.refused),
      for (final step in CheckStep.values.skip(2)) Finding(step, ran: false),
    ];
    await open(tester);
    expect(checked.map((c) => c.session), ['token-1', 'token-1']);
    expect(find.text('$lan'), findsOneWidget);
    expect(find.text('$wan'), findsOneWidget);
    expect(find.text('Nothing answers at this address.'), findsOneWidget);
    expect(state('Not checked'), findsNWidgets(6));
    final top = tester.getTopLeft;
    expect(
      top(find.text('Reaching the server').first).dy,
      lessThan(top(find.text('Secure connection and certificate').first).dy),
    );
  });

  testWidgets('trusting a self-signed certificate pins its fingerprint once '
      'the user compared it, and checks again', (tester) async {
    findings[wan] = run({
      CheckStep.tls: const Finding(
        CheckStep.tls,
        fault: Fault.selfSigned,
        fingerprint: fingerprint,
      ),
    });
    await open(tester);
    await tester.tapAndSettle(find.text('Trust'));
    expect(find.textContaining('0F:1E:2D:3C'), findsOneWidget);
    await tester.tapAndSettle(find.text('Cancel'));
    expect(saved().pin, isNull);
    findings[wan] = run({});
    await tester.tapAndSettle(find.text('Trust'));
    await tester.tapAndSettle(find.text('Trust').last);
    expect(saved().pin, fingerprint);
    expect(saved().account?.token, 'token-1', reason: 'still signed in');
    expect(checked.last.pinnedCertificate, fingerprint);
    expect(state('Failed'), findsNothing);
  });

  testWidgets('a session the server does not take leads to signing in '
      'again', (tester) async {
    findings[wan] = run({
      CheckStep.auth: const Finding(CheckStep.auth, fault: Fault.signedOut),
    });
    await open(tester);
    await tester.tapAndSettle(find.text('Sign in'));
    expect(saved().account, isNull);
    expect(
      find.text('The server ended this session. Sign in again.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  testWidgets('copies what the administrator needs', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    findings[wan] = run({
      CheckStep.upload: const Finding(
        CheckStep.upload,
        fault: Fault.uploadCap,
        detail: 'HTTP 413 for 8388608 bytes',
      ),
    });
    await open(tester);
    await tester.tapAndSettle(find.text('Copy details'));
    expect(copied.single, contains('$wan'));
    expect(copied.single, contains('64 MB'));
    expect(copied.single, contains('HTTP 413 for 8388608 bytes'));
  });

  testWidgets('a server that does not answer offers the check', (tester) async {
    keystore.value = null;
    final server = FakeServer({
      'ServerInfoService/GetServerInfo': (_) => Unreachable('refused'),
    });
    await pumpApp(
      tester,
      serverStore: keystore,
      overrides: [
        connectProvider.overrideWithValue((config, instance) => server),
        certificateProvider.overrideWithValue((config, url) async => null),
        checkProvider.overrideWithValue((config, endpoint, instance) {
          checked.add(config);
          return Stream.fromIterable(run({}));
        }),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Add a server'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Addresses'),
      'nas.local',
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tapAndSettle(find.text('Check the connection'));
    expect(checked.single.endpoints, [Uri.parse('https://nas.local')]);
    expect(find.text('Connection check'), findsOneWidget);
    expect(find.text('Trust'), findsNothing);
  });
}
