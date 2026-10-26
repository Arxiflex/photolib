import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show CheckedPopupMenuItem;
import 'package:photolib/features/servers/hints.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/pump_app.dart';

void main() {
  late Replica db;
  late MemoryStore keystore;
  late List<({NetworkConfig config, String instance, Future<void> stop})>
  follows;
  Object? failure;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    keystore = MemoryStore();
    follows = [];
    failure = null;
  });
  tearDown(() => db.close());

  void keep(Account? account) => keystore.value = jsonEncode(
    SavedServer(
      endpoints: [Uri.parse('https://photos.example.org')],
      instance: 'instance-a',
      account: account,
    ).toJson(),
  );
  const ann = Account(name: 'ann', token: 'token-1', deviceId: 'device-1');

  Future<void> pump(WidgetTester tester) => pumpApp(
    tester,
    replica: (_) => db,
    serverStore: keystore,
    overrides: [
      followProvider.overrideWithValue((replica, config, instance, stop) {
        expect(replica, same(db));
        follows.add((config: config, instance: instance, stop: stop));
        return failure == null ? stop : Future.error(failure!);
      }),
    ],
  );

  /// Drift closes the library's queries on a timer.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<void> go(WidgetTester tester, List<AppLifecycleState> states) async {
    states.forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();
  }

  testWidgets('a signed-in app follows its server in the foreground only', (
    tester,
  ) async {
    keep(ann);
    await pump(tester);
    final first = follows.single;
    expect((first.config.session, first.instance), ('token-1', 'instance-a'));
    var stopped = false;
    unawaited(first.stop.then((_) => stopped = true));
    await go(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    expect((stopped, follows.length), (true, 1));
    await go(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(follows, hasLength(2));
    await end(tester);
  });

  testWidgets('without a session the app follows nothing; a revoked one '
      'signs it out', (tester) async {
    keep(null);
    await pump(tester);
    expect(follows, isEmpty);
    await end(tester);

    keep(ann);
    failure = ServerError(
      'unauthenticated',
      ErrorDetail(code: 'auth.session_revoked'),
    );
    await pump(tester);
    expect(follows, hasLength(1));
    expect(
      Accounts.fromJson(jsonDecode(keystore.value!) as Map).server?.account,
      isNull,
    );
    await end(tester);
  });

  testWidgets("a switch follows the other account's server into that "
      "account's replica only", (tester) async {
    final other = Replica(NativeDatabase.memory());
    addTearDown(other.close);
    final replicas = {standaloneReplica: db, 'replica-b': other};
    keystore.value = jsonEncode(
      Accounts([
        SavedServer(
          endpoints: [Uri.parse('https://photos.example.org')],
          instance: 'instance-a',
          account: ann,
        ),
        SavedServer(
          endpoints: [Uri.parse('https://nas.local')],
          instance: 'instance-b',
          account: const Account(
            name: 'bob',
            token: 'token-2',
            deviceId: 'device-2',
          ),
          replica: 'replica-b',
        ),
      ]).toJson(),
    );
    final followed = <(Replica, String)>[];
    await pumpApp(
      tester,
      replica: (ref) async =>
          replicas[await ref.watch(replicaNameProvider.future)]!,
      serverStore: keystore,
      overrides: [
        followProvider.overrideWithValue((replica, config, instance, stop) {
          followed.add((replica, instance));
          return stop;
        }),
      ],
    );
    await tester.tapAndSettle(find.byTooltip('Switch account'));
    await tester.tapAndSettle(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'nas.local'),
    );
    expect(followed, [(db, 'instance-a'), (other, 'instance-b')]);
    await end(tester);
  });
}
