import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photolib/features/admin/remote_access.dart';
import 'package:photolib/features/servers/servers.dart';

import '../support/console.dart';
import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// check-host.net as its API answers: a request id, then each node's result,
/// null until it is done; [nodes] the results, in the order they come.
MockClient checker(List<Map<String, Object?>> nodes, List<Uri> asked) {
  var reads = 0;
  return MockClient((request) async {
    asked.add(request.url);
    if (request.url.path == '/check-http') {
      return http.Response(jsonEncode({'ok': 1, 'request_id': 'r1'}), 200);
    }
    final at = reads < nodes.length ? reads++ : nodes.length - 1;
    return http.Response(jsonEncode(nodes[at]), 200);
  });
}

const List<List<Object?>> ok = [
  [1, 0.12, 'OK', '200', '203.0.113.7'],
];
const List<List<Object?>> refused = [
  [0, 0.05, 'Connection refused', null, null],
];

// The test from outside (OPS-28) through check-host.net's nodes.
void main() {
  final url = Uri.parse('https://photos.example.org/healthz');

  test('passes once a node gets a 200, after the pending ones', () async {
    final asked = <Uri>[];
    final result = await checkFromOutside(
      checker([
        {'de1': null, 'us1': null},
        {'de1': refused, 'us1': null},
        {'de1': refused, 'us1': ok},
      ], asked),
      url,
      poll: Duration.zero,
    );
    expect(result.reachable, isTrue);
    expect(asked.first.queryParameters, {'host': '$url', 'max_nodes': '3'});
    expect(asked.first.host, 'check-host.net');
    expect(asked.skip(1).map((u) => u.path).toSet(), {'/check-result/r1'});
  });

  test(
    'fails once every node is done without a 200, or none in time',
    () async {
      final done = await checkFromOutside(
        checker([
          {
            'de1': refused,
            'us1': [
              [1, 0.2, 'Not Found', '404', '203.0.113.7'],
            ],
          },
        ], []),
        url,
        poll: Duration.zero,
      );
      expect(done.reachable, isFalse);
      expect(done.detail, contains('Connection refused'));
      final late = await checkFromOutside(
        checker([
          {'de1': null},
        ], []),
        url,
        poll: Duration.zero,
        polls: 3,
      );
      expect(late.reachable, isFalse);
    },
  );

  test('a check with the clock in 2100 passes as today', () {
    fakeAsync((time) {
      ({bool reachable, String detail})? result;
      unawaited(
        checkFromOutside(
          checker([
            {'de1': null},
            {'de1': ok},
          ], []),
          url,
        ).then((r) => result = r),
      );
      time.elapse(const Duration(seconds: 10));
      expect(result?.reachable, isTrue);
    }, initialTime: DateTime(2100));
  });

  testWidgets('the console fills each way in with this server and tests the '
      'public address only once the administrator agrees', (tester) async {
    final asked = <Uri>[];
    await openConsole(
      tester,
      FakeServer(),
      saved: SavedServer(
        endpoints: [
          Uri.parse('https://photos.example.org/'),
          Uri.parse('http://192.168.1.10:8080/'),
        ],
        instance: 'instance-a',
      ),
      overrides: [
        outsideProvider.overrideWithValue(
          checker([
            {'de1': ok},
          ], asked),
        ),
      ],
    );
    await section(tester, 'Remote access');
    await tester.tapAndSettle(find.text('Cloudflare Tunnel'));
    expect(find.textContaining('hostname: photos.example.org'), findsOneWidget);
    expect(
      find.textContaining('service: http://192.168.1.10:8080'),
      findsOneWidget,
    );
    await tester.tapAndSettle(find.text('Tailscale, Headscale'));
    expect(
      find.text('tailscale serve --bg http://127.0.0.1:8080'),
      findsOneWidget,
    );

    await tester.tapAndSettle(find.text('Test from outside'));
    expect(
      find.textContaining(
        'check-host.net will open https://photos.example.org/healthz',
      ),
      findsOneWidget,
    );
    await tester.tapAndSettle(find.text('Cancel'));
    expect(asked, isEmpty);
    await tester.tapAndSettle(find.text('Test from outside'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Reachable from outside.'), findsOneWidget);
    expect(asked, isNotEmpty);
  });
}
