import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/device_library.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_api/kernel.dart' as kernel;
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

void main() {
  late FakeServer server;
  late MemoryStore store;
  late List<(NetworkConfig, String?)> links;
  setUp(() {
    server = FakeServer();
    store = MemoryStore();
    links = [];
  });

  Future<void> pump(WidgetTester tester) => pumpApp(
    tester,
    serverStore: store,
    overrides: [
      connectProvider.overrideWithValue((config, instance) {
        links.add((config, instance));
        return server;
      }),
    ],
  );

  Accounts accounts() => store.value == null
      ? const Accounts([])
      : Accounts.fromJson(jsonDecode(store.value!) as Map);

  const ann = Account(
    name: 'ann',
    token: 'token-1',
    deviceId: 'device-1',
    admin: true,
  );

  /// Ann's account, as a build before several accounts kept it.
  void keep() => store.value = jsonEncode(
    SavedServer(
      endpoints: [Uri.parse('https://photos.example.org')],
      instance: 'instance-a',
      account: ann,
    ).toJson()..remove('replica'),
  );

  /// Ann's account on photos.example.org and Bob's on nas.local, which has
  /// a replica of its own.
  void keepTwo({int current = 0, bool signedIn = true}) =>
      store.value = jsonEncode(
        Accounts([
          SavedServer(
            endpoints: [Uri.parse('https://photos.example.org')],
            instance: 'instance-a',
            account: signedIn ? ann : null,
          ),
          SavedServer(
            endpoints: [Uri.parse('https://nas.local')],
            instance: 'instance-b',
            account: signedIn
                ? const Account(
                    name: 'bob',
                    token: 'token-2',
                    deviceId: 'device-2',
                  )
                : null,
            replica: 'replica-b',
          ),
        ], current: current).toJson(),
      );

  testWidgets(
    'adding a server keeps the others, signed in, and switches to it, '
    'on a replica of its own',
    (tester) async {
      keep();
      await pump(tester);
      expect(find.byTooltip('Switch account'), findsNothing);
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('Add a server'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Addresses'),
        'nas.local',
      );
      await tester.tapAndSettle(find.text('Connect'));
      expect(find.text('Sign in'), findsOneWidget);
      final kept = accounts();
      expect(
        [for (final s in kept.servers) (s.name, s.account?.token)],
        [('photos.example.org', 'token-1'), ('nas.local', null)],
      );
      expect(kept.current, 1);
      expect(kept.servers.first.replica, 'replica');
      expect(kept.servers.last.replica, matches(r'^replica-[0-9a-f]{16}$'));
      for (var page = 0; page < 2; page++) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(find.byTooltip('Switch account'), findsOneWidget);
    },
  );

  testWidgets(
    "the app bar switches accounts in one tap, and the server's page, "
    "calls and console are then the other account's",
    (tester) async {
      keepTwo();
      await pump(tester);
      await tester.tapAndSettle(find.byTooltip('Switch account'));
      expect(find.text('ann'), findsOneWidget);
      expect(find.text('nas.local'), findsOneWidget);
      await tester.tapAndSettle(
        find.widgetWithText(CheckedPopupMenuItem<int>, 'bob'),
      );
      expect(accounts().current, 1);
      await tester.tapAndSettle(find.byTooltip('Settings'));
      expect(find.text('Server administration'), findsNothing);
      await tester.tapAndSettle(find.text('nas.local'));
      expect(find.text('Signed in as bob'), findsOneWidget);
      expect(links.last.$2, 'instance-b');
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Settings opens the page of the account it switches to.
      await tester.tapAndSettle(find.text('photos.example.org'));
      expect(find.text('Signed in as ann'), findsOneWidget);
      expect(accounts().current, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollTo(find.text('Server administration'));
      await tester.tapAndSettle(find.text('Server administration'));
      await tester.tapAndSettle(find.widgetWithText(ListTile, 'Overview'));
      expect(
        links.where((l) => l.$1.session == 'token-1').map((l) => l.$2),
        everyElement('instance-a'),
      );
      expect(
        links.where((l) => l.$1.session == 'token-2').map((l) => l.$2),
        everyElement('instance-b'),
      );
    },
  );

  testWidgets("every account's kept session is renewed at start", (
    tester,
  ) async {
    keepTwo();
    server = FakeServer({
      'AuthService/RotateSession': (_) => RotateSessionResponse(
        session: Session(token: '${links.last.$1.session}-new'),
      ),
    });
    await pump(tester);
    expect(
      [for (final s in accounts().servers) s.account?.token],
      ['token-1-new', 'token-2-new'],
    );
  });

  test('a session that a server ends after the user switched away ends '
      "only that account's", () async {
    keepTwo();
    server = FakeServer({
      'AdminService/GetStatus': (_) =>
          ServerError('unauthenticated', ErrorDetail(code: 'session.required')),
    });
    final container = ProviderContainer.test(
      overrides: [
        serverStoreProvider.overrideWithValue(store),
        connectProvider.overrideWithValue((config, instance) => server),
        networkChangesProvider.overrideWithValue(const Stream.empty()),
      ],
    );
    await container.read(accountsProvider.future);
    final anns = container.read(sessionProvider)!;
    await container.read(accountsProvider.notifier).use(1);
    await expectLater(
      AdminServiceApi(anns).getStatus(null, GetStatusRequest()),
      throwsA(isA<ServerError>()),
    );
    await pumpEventQueue();
    final [a, b] = accounts().servers;
    expect(a.account, isNull);
    expect(b.account?.token, 'token-2');
    expect(accounts().current, 1);
    final shown = container.read(accountsProvider).requireValue;
    expect([for (final s in shown.servers) s.ended], [true, false]);
  });

  test('a setup that failed half-way on one server is not tried again on '
      "another's", () async {
    keepTwo(signedIn: false);
    var offline = true;
    server = FakeServer({
      'SetupService/CreateFirstAdmin': (_) => CreateFirstAdminResponse(
        passwordSetup: PasswordSetup(token: 'setup-${links.length}'),
      ),
      'AuthService/StartPasswordSetup': (_) =>
          offline ? Unreachable('timeout') : StartPasswordSetupResponse(),
    });
    final container = ProviderContainer.test(
      overrides: [
        serverStoreProvider.overrideWithValue(store),
        connectProvider.overrideWithValue((config, instance) {
          links.add((config, instance));
          return server;
        }),
        opaqueProvider.overrideWithValue(
          (_, _) async => kernel.OpaqueClientResponse(),
        ),
      ],
    );
    final accounts = container.read(accountsProvider.notifier);
    await container.read(accountsProvider.future);
    final ann = User(handle: 'ann');
    await expectLater(accounts.setUp('token-a', ann, 'pw'), throwsA(anything));
    await accounts.use(1);
    offline = false;
    await expectLater(accounts.setUp('token-b', ann, 'pw'), throwsA(anything));
    expect(
      [
        for (final r in server.requests<CreateFirstAdminRequest>(
          'SetupService/CreateFirstAdmin',
        ))
          r.setupToken,
      ],
      ['token-a', 'token-b'],
    );
  });

  testWidgets(
    'removing the account in use switches to the next, and removing the '
    "last leaves the device's own library",
    (tester) async {
      keepTwo(current: 1);
      await pump(tester);
      await tester.tapAndSettle(find.byTooltip('Settings'));
      await tester.tapAndSettle(find.text('nas.local'));
      await tester.tapAndSettle(find.text('Remove this server'));
      expect(
        [for (final s in accounts().servers) s.name],
        ['photos.example.org'],
      );
      expect(accounts().current, 0);
      expect(
        server
            .requests<RevokeDeviceRequest>('AuthService/RevokeDevice')
            .single
            .deviceId,
        'device-2',
      );
      await tester.tapAndSettle(find.text('photos.example.org'));
      await tester.tapAndSettle(find.text('Remove this server'));
      expect(store.value, isNull);
      expect(find.text('Add a server'), findsOneWidget);
    },
  );

  /// A library of one photo for Ann's account and one for Bob's, each in its
  /// replica.
  Future<Map<String, Replica>> twoLibraries(WidgetTester tester) async {
    final replicas = <String, Replica>{};
    for (final (name, day) in [
      (standaloneReplica, '2024-05-03'),
      ('replica-b', '2023-01-02'),
    ]) {
      final db = replicas[name] = Replica(NativeDatabase.memory());
      await db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16),
              source: 'folder',
              volume: const Value('/p'),
              sourceId: name,
              path: Value('$name.jpg'),
              name: Value('$name.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: Value('${day}T12:00:00'),
            ),
          );
    }
    keepTwo(signedIn: false);
    await pumpApp(
      tester,
      serverStore: store,
      replica: (ref) async =>
          replicas[await ref.watch(replicaNameProvider.future)]!,
      overrides: [
        thumbnailPipelineProvider.overrideWith(
          (ref) async => ThumbnailPipeline(),
        ),
      ],
    );
    addTearDown(() async {
      for (final db in replicas.values) {
        await db.close();
      }
    });
    return replicas;
  }

  Future<void> switchTo(WidgetTester tester, String server) async {
    await tester.tapAndSettle(find.byTooltip('Switch account'));
    await tester.tapAndSettle(
      find.widgetWithText(CheckedPopupMenuItem<int>, server),
    );
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets("a switch shows the other account's library alone, without "
      'the selection made in the first, which a switch back finds again', (
    tester,
  ) async {
    await twoLibraries(tester);
    expect(find.text('May 3, 2024'), findsOneWidget);
    final cell =
        tester.getTopLeft(find.byType(TimelineView)) + const Offset(60, 108);
    await tester.longPressAt(cell);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await switchTo(tester, 'nas.local');
    expect(find.text('Jan 2, 2023'), findsOneWidget);
    expect(find.text('May 3, 2024'), findsNothing);
    expect(find.text('1 selected'), findsNothing);
    await switchTo(tester, 'photos.example.org');
    expect(find.text('May 3, 2024'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    await stop(tester);
  });

  testWidgets('each account keeps a search of its own', (tester) async {
    await twoLibraries(tester);
    await tester.tapAndSettle(find.text('Search').last);
    await tester.enterText(find.byType(TextField), 'replica');
    // The search runs once typing pauses.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await switchTo(tester, 'nas.local');
    expect(find.widgetWithText(TextField, 'replica'), findsNothing);
    await switchTo(tester, 'photos.example.org');
    expect(find.widgetWithText(TextField, 'replica'), findsOneWidget);
    await stop(tester);
  });

  testWidgets("a switch indexes the device's library into the account's own "
      'replica', (tester) async {
    keepTwo(signedIn: false);
    final indexed = <String?>[];
    await pumpApp(
      tester,
      serverStore: store,
      overrides: [
        deviceLibraryProvider.overrideWithValue(_Library()),
        mediaIndexProvider.overrideWith(
          (ref) =>
              () async => indexed.add(ref.read(replicaNameProvider).value),
        ),
      ],
    );
    expect(indexed, [standaloneReplica]);
    await tester.tapAndSettle(find.byTooltip('Switch account'));
    await tester.tapAndSettle(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'nas.local'),
    );
    expect(indexed, [standaloneReplica, 'replica-b']);
  });
}

/// A device library that grants every photo.
class _Library implements DeviceLibrary {
  @override
  Future<MediaAccess> access() async => MediaAccess.full;

  @override
  Future<MediaAccess> requestAccess() async => MediaAccess.full;

  @override
  Future<void> Function()? get select => null;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> index(Replica replica) async {}
}
