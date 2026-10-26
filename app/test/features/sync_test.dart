import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photolib/features/servers/sync.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';
import '../support/server_app.dart';

void main() {
  setUpServerApp();
  late Replica db;
  late List<(Replica, NetworkConfig, String)> synced;
  Object? failure;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    synced = [];
    failure = null;
  });
  tearDown(() => db.close());

  /// Drift closes the library's queries on a timer.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  final backedUp = <(Replica, NetworkConfig, String, String)>[];
  setUp(backedUp.clear);

  Future<void> pump(WidgetTester tester) => pumpServerApp(
    tester,
    replica: db,
    overrides: [
      syncProvider.overrideWithValue((db, config, instance) async {
        synced.add((db, config, instance));
        if (failure case final failure?) throw failure;
      }),
      backupProvider.overrideWithValue((db, config, instance, owner) async {
        backedUp.add((db, config, instance, owner));
      }),
    ],
  );

  testWidgets("after each sync, the folders go to the account's library", (
    tester,
  ) async {
    keep(ann.copyWith(userId: 'u-1'));
    await pump(tester);
    final (replica, config, instance, owner) = backedUp.single;
    expect(replica, same(db));
    expect((config.session, instance, owner), ('token-1', 'instance-a', 'u-1'));
    await tester.pump(const Duration(minutes: 5));
    expect(backedUp, hasLength(2));
    await end(tester);
  });

  testWidgets("a session kept without its account's id backs nothing up", (
    tester,
  ) async {
    keep(ann);
    await pump(tester);
    expect(synced, hasLength(1));
    expect(backedUp, isEmpty);
    await end(tester);
  });

  testWidgets('a signed-in app syncs its replica at start, then every five '
      'minutes', (tester) async {
    keep(ann);
    await pump(tester);
    final (replica, config, instance) = synced.single;
    expect(replica, same(db));
    expect((config.session, instance), ('token-1', 'instance-a'));
    expect(config.endpoints, [Uri.parse('https://photos.example.org')]);
    await tester.pump(const Duration(minutes: 5));
    expect(synced, hasLength(2));
    await end(tester);
  });

  testWidgets('a signed-in app syncs again on every resume', (tester) async {
    keep(ann);
    await pump(tester);
    expect(synced, hasLength(1));
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();
    expect(synced, hasLength(2));
    await end(tester);
  });

  testWidgets('signed out, the replica forgets what the server sent', (
    tester,
  ) async {
    await db.customStatement(
      "INSERT INTO sync_cursor VALUES ('albums', x'01', 1, 'instance-a.0')",
    );
    keep(ann);
    await pump(tester);
    expect(await db.select(db.syncCursor).get(), hasLength(1));
    failure = refused('unauthenticated', 'session.required');
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(await db.select(db.syncCursor).get(), isEmpty);
    await end(tester);
  });

  testWidgets('signing in syncs, signing out stops syncing', (tester) async {
    keep();
    server = FakeServer(login());
    await pump(tester);
    expect(synced, isEmpty);
    await openServer(tester);
    await signIn(tester, 'ann', 'pw');
    expect(synced.single.$2.session, 'token-1');
    await tester.tapAndSettle(find.text('Sign out'));
    await tester.pump(const Duration(minutes: 10));
    expect(synced, hasLength(1));
    await end(tester);
  });

  testWidgets('a sync the server answers with a revocation signs the app '
      'out; an unreachable one does not', (tester) async {
    keep(ann);
    failure = Unreachable('offline');
    await pump(tester);
    expect(saved()!.account, isNotNull);
    failure = refused('unauthenticated', 'session.required');
    await tester.pump(const Duration(minutes: 5));
    expect(saved()!.account, isNull);
    await openServer(tester);
    expect(
      find.text('The server ended this session. Sign in again.'),
      findsOneWidget,
    );
    await end(tester);
  });
}
