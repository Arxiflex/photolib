import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/app.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/library/timeline/layout.dart';
import 'package:photolib/features/library/timeline/pipeline.dart';
import 'package:photolib/features/library/timeline/providers.dart';
import 'package:photolib/features/library/timeline/timeline_view.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/ui/media_grid.dart';
import 'package:photolib_data/photolib_data.dart';
import 'package:photolib_data/testing.dart';
import 'package:photolib_kernel/photolib_kernel.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('every setting is read back after a restart, and kept only '
      'sealed in the store', (tester) async {
    final dir = Directory.systemTemp.createTempSync('settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final keystore = MemoryKeystore();
    final db = Replica(NativeDatabase.memory());
    addTearDown(db.close);

    // Waits for [future], whose files need real time, in the test's time.
    Future<T> wait<T>(Future<T> future) async {
      var done = false;
      final result = future.whenComplete(() => done = true);
      await tester.pumpUntil(() => done);
      return await result;
    }

    await wait(
      db
          .into(db.localAsset)
          .insert(
            LocalAssetCompanion.insert(
              id: Uint8List(16),
              source: 'folder',
              volume: const Value('/p'),
              sourceId: '1',
              path: const Value('1.jpg'),
              size: 1,
              mtime: 0,
              takenLocal: const Value('2024-05-03T12:00:00'),
            ),
          ),
    );

    // Starts the app over the store in [dir], its settings read.
    Future<(ProviderContainer, Vault)> start() async {
      final vault = Vault(
        location: dir.path,
        keystore: keystore,
        files: _SlowDisk(storeFiles(dir.path)),
        keyring: Kernel().keyring,
      );
      await wait(vault.unlock());
      await pumpApp(
        tester,
        replica: (_) => db,
        settings: VaultText(() async => vault, 'settings'),
        overrides: [
          releaseBuildProvider.overrideWithValue(true),
          thumbnailPipelineProvider.overrideWith(
            (ref) async => ThumbnailPipeline(),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PhotolibApp)),
      );
      await wait(container.read(settingsProvider.notifier).loaded);
      await tester.pumpAndSettle();
      return (container, vault);
    }

    // The app quits, and its store locks.
    Future<void> quit(Vault vault) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await wait(vault.lock());
    }

    Future<void> viewOption(String option) async {
      await tester.tapAndSettle(find.byTooltip('View options'));
      await tester.tapAndSettle(find.text(option));
    }

    Future<void> search(String text) async {
      await tester.tapAndSettle(find.text('Search'));
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }

    var (container, vault) = await start();
    await viewOption('Recently added');
    await viewOption('Group by month');
    await tester.tapAndSettle(find.byTooltip('Smaller thumbnails'));
    await search('jpg');
    await tester.tapAndSettle(find.byTooltip('Zoom out'));
    await tester.tapAndSettle(find.byTooltip('Settings'));
    await tester.tapAndSettle(find.text('Dark'));
    await tester.scrollTo(find.text('Show diagnostics'));
    await tester.tapAndSettle(find.text('Show diagnostics'));
    await tester.scrollUntilVisible(find.text('Only while charging'), 100);
    await tester.tapAndSettle(find.text('Only while charging'));
    await tester.scrollUntilVisible(find.text('Language'), -100);
    await tester.pump();
    await tester.tapAndSettle(find.text('Language'));
    await tester.tapAndSettle(find.text('Deutsch'));
    container
        .read(settingsProvider.notifier)
        .setDownloadFolder('/home/ana/Pictures');
    await quit(vault);

    (container, vault) = await start();
    expect(find.byTooltip('Einstellungen'), findsOneWidget);
    container.read(settingsProvider.notifier).setLanguage(null);
    await tester.pumpAndSettle();
    expect(
      tester.state<TimelineViewState>(find.byType(TimelineView)).density,
      Density.months,
    );
    expect(
      Theme.of(tester.element(find.text('Library').first)).brightness,
      Brightness.dark,
    );
    expect(
      container.read(settingsProvider).downloadFolder,
      '/home/ana/Pictures',
    );
    await tester.tapAndSettle(find.byTooltip('View options'));
    expect(
      [
        for (final item in tester.widgetList<CheckedPopupMenuItem<Object?>>(
          find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
        ))
          if (item.checked) (item.child! as Text).data,
      ],
      ['Recently added', 'Group by month'],
    );
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await search('jpg');
    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).columns, 6);
    // Tall enough to build every tile, now that the faces section is above
    // the diagnostics one.
    tester.view.physicalSize = const Size(800, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.tapAndSettle(find.byTooltip('Settings'));
    // The page builds what is near the screen: its tiles grew by Storage.
    await tester.scrollTo(find.text('Show diagnostics'));
    expect(
      [
        for (final tile in tester.widgetList<SwitchListTile>(
          find.byType(SwitchListTile, skipOffstage: false),
        ))
          ((tile.title! as Text).data, tile.value),
      ],
      [
        ('Search on this device', false),
        ('Only while charging', true),
        ('Find faces in my photos', false),
        ('Show diagnostics', true),
      ],
    );
    await quit(vault);

    final stored = latin1.decode([
      for (final bytes in (await wait(storedBytes(dir.path))).values) ...bytes,
    ]);
    expect(stored, isNot(contains('Pictures')));
    expect(stored, isNot(contains('themeMode')));
  });
}

/// [_files], each write first stalling a second of real time, as a loaded
/// machine's disk stalls an fsync: longer than a thousand pumps take.
class _SlowDisk implements StoreFiles {
  new(this._files);
  final StoreFiles _files;

  @override
  Future<Uint8List?> read(String name) => _files.read(name);

  @override
  Future<void> write(String name, Uint8List bytes) async {
    await Zone.root.run(() => Future<void>.delayed(const Duration(seconds: 1)));
    await _files.write(name, bytes);
  }

  @override
  Future<void> delete(String name) => _files.delete(name);

  @override
  Future<void> deleteAll(String prefix) => _files.deleteAll(prefix);

  @override
  Future<List<String>> list(String prefix) => _files.list(prefix);
}
