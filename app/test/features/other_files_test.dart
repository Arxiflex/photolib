import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/collections/other_files.dart';
import 'package:photolib/features/download/download.dart';
import 'package:photolib/features/download/download_action.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib_data/photolib_data.dart';

import '../support/fake_server.dart';
import '../support/pump_app.dart';

/// What it was given, by name.
class _Destination implements Destination {
  final saved = <String, String>{};

  @override
  Future<bool> save(
    String name,
    Stream<List<int>> bytes, {
    DateTime? modified,
  }) async {
    saved[name] = utf8.decode([await for (final chunk in bytes) ...chunk]);
    return true;
  }
}

void main() {
  late Replica db;
  late _Destination to;
  setUp(() {
    db = Replica(NativeDatabase.memory());
    to = _Destination();
  });
  tearDown(() => db.close());

  // Synced assets: a photo, a PDF, a trashed text and, newest, a song.
  Future<void> sync() async {
    for (final (n, name, kind, trashed) in [
      (1, 'IMG_1.jpg', 'image', null),
      (2, 'notes.pdf', '', null),
      (3, 'old.txt', '', 5),
      (4, 'song.ogg', '', null),
    ]) {
      final id = Uint8List(16)..[15] = n;
      await db
          .into(db.asset)
          .insert(
            AssetCompanion.insert(
              id: id,
              libraryId: Uint8List(16),
              ownerId: Uint8List(16),
              originalFilename: name,
              source: 'upload',
              mediaKind: kind,
              trashedAt: Value(trashed),
              createdAt: n,
            ),
          );
      await db
          .into(db.assetFile)
          .insert(
            AssetFileCompanion.insert(
              id: Uint8List(16)..[0] = n,
              assetId: id,
              role: 'original',
              mime: 'application/pdf',
              size: 52000,
              state: 'present',
            ),
          );
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // The replica's other files, without opening the replica pumpApp keeps.
  Override otherFiles() =>
      otherFilesProvider.overrideWith((ref) => db.otherFiles().watch());

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  test('the other files are those of the replica', () async {
    await sync();
    final container = ProviderContainer.test(
      overrides: [replicaProvider.overrideWith((ref) => db)],
    );
    final files = container.listen(otherFilesProvider.future, (_, _) {});
    expect(
      [for (final f in await files.read()) f.name],
      ['song.ogg', 'notes.pdf'],
    );
  });

  testWidgets('the collections list other files once the replica has some, '
      'and their page lists those not in the trash', (tester) async {
    Future<void> openCollections() async {
      await pumpApp(tester, overrides: [otherFiles()]);
      await tester.tapAndSettle(find.text('Collections'));
      await settle(tester);
    }

    await openCollections();
    expect(find.text('Other files'), findsNothing);
    await unmount(tester);

    await sync();
    await openCollections();
    expect(find.text('2'), findsOneWidget);
    await tester.tapAndSettle(find.text('Other files'));
    final top = tester.getTopLeft(find.text('song.ogg')).dy;
    expect(top, lessThan(tester.getTopLeft(find.text('notes.pdf')).dy));
    expect(find.text('52 kB'), findsNWidgets(2));
    expect(find.text('old.txt'), findsNothing);
    expect(find.text('IMG_1.jpg'), findsNothing);
    await unmount(tester);
  });

  Future<void> openOtherFiles(WidgetTester tester, {Link? session}) async {
    await sync();
    await pumpApp(
      tester,
      overrides: [
        otherFiles(),
        sessionProvider.overrideWithValue(session),
        destinationProvider.overrideWithValue(to),
      ],
    );
    await tester.tapAndSettle(find.text('Collections'));
    await settle(tester);
    await tester.tapAndSettle(find.text('Other files'));
    await settle(tester);
  }

  testWidgets('an other file downloads its original from the server, or '
      'says that it could not', (tester) async {
    final server = FakeServer();
    server.files['media/00000000-0000-0000-0000-000000000002/original'] = utf8
        .encode('%PDF');
    await openOtherFiles(tester, session: server);
    await tester.tap(find.byTooltip('Download').last);
    await settle(tester);
    expect(to.saved, {'notes.pdf': '%PDF'});
    expect(find.text('Saved notes.pdf'), findsOneWidget);

    server.files.clear();
    await tester.tap(find.byTooltip('Download').last);
    await settle(tester);
    expect(find.text("Couldn't download"), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('other files say when the local store cannot open, and Try '
      'again opens it again', (tester) async {
    await sync();
    var opens = 0;
    await pumpApp(
      tester,
      // The second open fails, as a browser's database worker can.
      replica: (ref) async =>
          ++opens == 2 ? throw StateError('database worker error') : db,
    );
    await tester.tapAndSettle(find.text('Collections'));
    await settle(tester);
    await tester.tapAndSettle(find.text('Other files'));
    await settle(tester);
    ProviderScope.containerOf(tester.element(find.byType(OtherFilesPage)))
        .invalidate(replicaProvider);
    await settle(tester);
    expect(
      find.text('Photolib could not open the library kept on this device'),
      findsOneWidget,
    );
    expect(find.text('song.ogg'), findsNothing);
    expect(opens, 2);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('song.ogg'), findsOneWidget);
    expect(opens, 3);
    await unmount(tester);
  });

  testWidgets('a query of other files that fails says so, and Try again runs '
      'it again', (tester) async {
    await sync();
    // As a browser's database worker can fail once the store is open.
    final query = StreamController<List<OtherFilesResult>>()
      ..add(await db.otherFiles().get());
    var runs = 0;
    await pumpApp(
      tester,
      overrides: [
        otherFilesProvider.overrideWith(
          (ref) => ++runs == 1 ? query.stream : db.otherFiles().watch(),
        ),
      ],
    );
    await tester.tapAndSettle(find.text('Collections'));
    await tester.tapAndSettle(find.text('Other files'));
    query.addError(StateError('database worker error'));
    await settle(tester);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('song.ogg'), findsNothing);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('song.ogg'), findsOneWidget);
    expect(runs, 2);
    await unmount(tester);
  });

  testWidgets('signed out, other files are listed without a download', (
    tester,
  ) async {
    await openOtherFiles(tester);
    expect(find.text('notes.pdf'), findsOneWidget);
    expect(find.byTooltip('Download'), findsNothing);
    await unmount(tester);
  });
}
