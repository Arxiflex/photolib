import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photolib/app.dart';
import 'package:photolib/core/media_store.dart';
import 'package:photolib/core/photo_kit.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/core/share_inbox.dart';
import 'package:photolib/features/folders/folders.dart';
import 'package:photolib/features/library/timeline/buckets.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/features/viewer/viewer_page.dart';
import 'package:photolib/main.dart' as app;
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';

/// MediaStore as if the user granted access: without it, MediaStore still
/// answers, with the app's own items only.
class _Granted extends MediaStoreChannel {
  const new();

  @override
  Future<MediaAccess> access() async => MediaAccess.full;
}

Future<void> _launches(WidgetTester tester) async {
  final onError = FlutterError.onError;
  final platformOnError = PlatformDispatcher.instance.onError;
  final builder = ErrorWidget.builder;

  await app.main();
  final errors = <FlutterErrorDetails>[];
  final handler = FlutterError.onError!;
  FlutterError.onError = (details) {
    errors.add(details);
    handler(details);
  };
  await tester.pumpAndSettle();

  for (final (tab, content) in [
    ('Library', 'Your photos will appear here'),
    ('Collections', 'Albums'),
    ('Search', 'Search your library'),
  ]) {
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget, reason: tab);
  }

  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  expect(find.text('Theme'), findsOneWidget);

  FlutterError.onError = onError;
  PlatformDispatcher.instance.onError = platformOnError;
  ErrorWidget.builder = builder;
  expect(errors, isEmpty);
}

Future<void> _conforms(WidgetTester tester) async {
  final vault = await openVault();
  await vault.unlock();
  addTearDown(vault.lock);
  expect(
    await probeReplica(await vault.openReplica(name: 'conformance')),
    expectedProbe,
  );
  await storeMarkers(vault, await vault.openReplica(name: 'forensic'));
  await vault.lock();
  final storage = kIsWeb ? '' : (await getApplicationSupportDirectory()).path;
  expect(await markerHits(storage), isEmpty);
}

Future<void> _settings(WidgetTester tester) async {
  const folder = '/Photolib settings marker';
  Future<(ProviderContainer, Vault)> start() async {
    final vault = await openVault();
    await vault.unlock();
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          VaultText(() async => vault, 'settings'),
        ),
      ],
    );
    await container.read(settingsProvider.notifier).loaded;
    return (container, vault);
  }

  // The app quits once what it changed reached the store.
  Future<void> quit(ProviderContainer container, Vault vault) async {
    await Future<void>.delayed(Duration.zero);
    await vault.lock();
    container.dispose();
  }

  var (container, vault) = await start();
  // The settings this machine's app had, kept again after the test.
  final before = await container.read(settingsStoreProvider).read();
  addTearDown(() async {
    final (container, vault) = await start();
    await container.read(settingsStoreProvider).write(before);
    await quit(container, vault);
  });
  container.read(settingsProvider.notifier)
    ..setThemeMode(ThemeMode.dark)
    ..setDiagnostics(on: true)
    ..setDownloadFolder(folder)
    ..setLibraryView(
      const LibraryView(
        added: true,
        grouping: Grouping.month,
        density: Density.months,
      ),
    )
    ..setSearchColumns(6);
  await quit(container, vault);
  (container, vault) = await start();
  final read = container.read(settingsProvider);
  expect(
    [read.themeMode, read.diagnostics, read.downloadFolder],
    [ThemeMode.dark, true, folder],
  );
  expect(
    [read.library.added, read.library.grouping, read.library.density],
    [true, Grouping.month, Density.months],
  );
  expect(read.searchColumns, 6);
  await quit(container, vault);

  final storage = kIsWeb ? '' : (await getApplicationSupportDirectory()).path;
  expect([
    for (final MapEntry(:key, :value) in (await storedBytes(storage)).entries)
      if (latin1.decode(value) case final text
          when text.contains('settings marker') ||
              text.contains('settings marker'.split('').join('\x00')))
        key,
  ], isEmpty);
}

Future<void> _mediaStore(WidgetTester tester) async {
  const store = MediaStoreChannel();
  expect(await store.installId(), await store.installId());
  expect(await store.volumes(), contains('external_primary'));
  final vault = await openVault();
  await vault.unlock();
  addTearDown(vault.lock);
  final db = await vault.openReplica(name: 'media');
  await const _Granted().index(db);
  await const _Granted().index(db);
  expect([
    for (final s in await db.select(db.volumeCursor).get()) s.volume,
  ], contains('external_primary'));
}

Future<void> _photoKit(WidgetTester tester) async {
  const library = PhotoKitChannel();
  expect(await library.installId(), await library.installId());
  final vault = await openVault();
  await vault.unlock();
  addTearDown(vault.lock);
  final db = await vault.openReplica(name: 'photo_kit');
  // A full read, then the persistent history since its token.
  await library.index(db);
  await library.index(db);
  expect(await db.select(db.localAsset).get(), isNotEmpty);
  expect((await db.select(db.volumeCursor).getSingle()).source, 'photokit');
}

Future<void> _shareInbox(WidgetTester tester) async {
  Future<int> count() async => (jsonDecode(
    await const PhotoKitChannel().assets(0, 1 << 20),
  ) as List).length;
  final before = await count();
  final inbox = await Directory.systemTemp.createTemp('photolib-inbox-');
  addTearDown(() => inbox.delete(recursive: true));
  File('${inbox.path}/A/0/shared.jpg')
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 64)));
  File(
    '${inbox.path}/A/manifest.json',
  ).writeAsStringSync('{"items": [{"file": "0/shared.jpg", "kind": "photo"}]}');
  await drainInbox(inbox, const ShareInboxChannel().save);
  expect(inbox.listSync(), isEmpty);
  expect(await count(), before + 1);
}

Future<void> _folders(WidgetTester tester) async {
  final folder = await Directory.systemTemp.createTemp('photolib-smoke-');
  addTearDown(() => folder.delete(recursive: true));
  for (final name in ['a.jpg', '2024/b.png', '2024/notes.txt']) {
    File('${folder.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(name);
  }
  Map<String, String> files() => {
    for (final f in folder.listSync(recursive: true).whereType<File>())
      f.path: '${f.readAsStringSync()} ${f.lastModifiedSync()}',
  };
  final before = files();
  final vault = await openVault();
  await vault.unlock();
  addTearDown(vault.lock);
  final db = await vault.openReplica(name: 'folders');
  for (final s in await db.select(db.mediaSource).get()) {
    await removeFolder(db, s.root);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        replicaProvider.overrideWith((ref) => db),
        folderPickerProvider.overrideWithValue(
          ({initialDirectory}) async => folder.path,
        ),
      ],
      child: const PhotolibApp(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Add folder'));
  await tester.pump();
  await tester.tap(find.byTooltip('Settings'));
  // The scan's progress bar never settles until the scan ends.
  for (var i = 0; i < 100 && find.text('2 items').evaluate().isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  expect(find.text('2 items'), findsOneWidget);
  expect(await db.select(db.localAsset).get(), hasLength(2));

  await tester.tap(find.byTooltip('Remove folder'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove'));
  await tester.pumpAndSettle();
  expect(find.text('2 items'), findsNothing);
  expect(await db.select(db.localAsset).get(), isEmpty);
  expect(files(), before);
}

Future<void> _drag(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  // tools/smoke.sh builds the other client, tools/desktop/xdnd.c.
  final xdnd = Platform.environment['XDND']!;
  // The other client's pointer, which the test binding would keep.
  binding.shouldPropagateDevicePointerEvents = true;
  final folder = await Directory.systemTemp.createTemp('photolib-drag-');
  addTearDown(() => folder.delete(recursive: true));
  final photo = File('${folder.path}/a.jpg')
    ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 64)));
  final vault = await openVault();
  await vault.unlock();
  addTearDown(vault.lock);
  final db = await vault.openReplica(name: 'drag');
  for (final s in await db.select(db.mediaSource).get()) {
    await removeFolder(db, s.root);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [replicaProvider.overrideWith((ref) => db)],
      child: const PhotolibApp(),
    ),
  );
  await tester.pumpAndSettle();
  Future<ProcessResult> run(List<String> arguments) async {
    final run = Process.run(xdnd, arguments);
    ProcessResult? result;
    unawaited(run.then((r) => result = r));
    while (result == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
    return result!;
  }

  final dropped = await run(['drop', '$pid', '${Uri.file(folder.path)}']);
  expect(dropped.stdout, contains('finished'), reason: '${dropped.stderr}');
  final timeline = find.byType(TimelineView);
  for (var i = 0; i < 100 && timeline.evaluate().isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  expect(
    [for (final s in await db.select(db.mediaSource).get()) s.root],
    [folder.path],
  );
  // At rest: the warm-up has kept the item's ThumbHash, which refreshes the
  // timeline within a second, and its progress is gone from above it.
  for (var i = 0; i < 100; i++) {
    final items = await db.select(db.localAsset).get();
    if (items.isNotEmpty && items.single.thumbhash != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  await tester.pumpAndSettle();

  final cell =
      tester.state<TimelineViewState>(timeline).cellOf(0).center *
      tester.view.devicePixelRatio;
  final caught = await run([
    'catch',
    '$pid',
    '${cell.dx.round()}',
    '${cell.dy.round()}',
  ]);
  expect(
    caught.stdout,
    contains('dropped ${photo.uri}'),
    reason: '${caught.stderr}',
  );
  // The click after the drag opens the item: the app knows the button
  // went up, which the drag hid from it.
  await tester.pumpAndSettle();
  binding.shouldPropagateDevicePointerEvents = false;
  expect(find.byType(ViewerPage), findsOneWidget);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches, walks the three tabs and opens Settings', _launches);
  testWidgets(
    'the store conforms on every target, and a copy of it holds no plaintext',
    _conforms,
  );
  testWidgets(
    'settings are read back after a restart, and a copy of the store holds '
    'none of them',
    _settings,
  );
  testWidgets(
    'MediaStore answers the indexer on an isolate of its own',
    _mediaStore,
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.android,
  );
  testWidgets(
    'PhotoKit answers the indexer on an isolate of its own',
    _photoKit,
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.iOS,
  );
  testWidgets(
    'a photo shared into the inbox lands in the Photos library',
    _shareInbox,
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.iOS,
  );
  testWidgets(
    'a folder added from the empty library is scanned, counted in Settings '
    'and removed without touching a file',
    _folders,
    skip:
        kIsWeb ||
        !const {
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform),
  );
  testWidgets(
    'a folder dragged in from another X11 client joins the library, and a '
    "cell dragged out to it drops its file, as with a file manager's windows",
    (tester) => _drag(tester, binding),
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.linux,
  );
}
