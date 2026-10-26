import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/offline/offline.dart';
import 'package:photolib/features/offline/pin_button.dart';
import 'package:photolib/features/offline/storage_page.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_data/photolib_data.dart';

import '../../support/pump_app.dart' show MemoryStore;

Uint8List _id(int n) => Uint8List(16)..[15] = n;

void main() {
  late MemoryStore policy;
  late MemoryStore pins;
  late StreamController<OfflineProgress> progress;

  setUp(() {
    policy = MemoryStore();
    pins = MemoryStore();
    progress = StreamController<OfflineProgress>.broadcast();
  });
  tearDown(() => progress.close());

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget page, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(400, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlinePolicyStoreProvider.overrideWithValue(policy),
          offlinePinsStoreProvider.overrideWithValue(pins),
          offlineProgressProvider.overrideWith((ref) => progress.stream),
          ...overrides,
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: appTheme(Brightness.light),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: page,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('the presets are offered and the choice is kept', (tester) async {
    final c = await pump(tester, const StoragePage());
    expect(find.text('Selected albums offline'), findsOneWidget);
    expect(find.text('Catalogue only'), findsOneWidget);
    expect(find.text('Space saver'), findsOneWidget);
    expect(find.text('Everything'), findsOneWidget);
    await tester.tap(find.text('Space saver'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePolicyProvider).preset, StoragePreset.spaceSaver);
    expect(policy.value, contains('spaceSaver'));
  });

  testWidgets('the budget is chosen from sizes and shows the usage', (
    tester,
  ) async {
    final c = await pump(tester, const StoragePage());
    progress.add(const OfflineProgress(used: 1200000000, budget: 5000000000));
    await tester.pumpAndSettle();
    expect(find.text('1.2 GB of 5 GB used'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 GB').last);
    await tester.pumpAndSettle();
    expect(c.read(offlinePolicyProvider).budget, 20000000000);
  });

  testWidgets('a pin says where it is and lets go with its space', (
    tester,
  ) async {
    final album = OfflinePin.album(_id(1), 'Trip');
    final c = await pump(tester, const StoragePage());
    c.read(offlinePinsProvider.notifier).pin(album);
    progress.add(
      const OfflineProgress(
        used: 3000000,
        budget: 5000000000,
        pins: {
          'album:00000000000000000000000000000001': PinProgress(
            files: 10,
            have: 4,
            bytes: 5000000,
            haveBytes: 3000000,
          ),
        },
        running: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('Downloading: 4 of 10'), findsOneWidget);

    progress.add(
      const OfflineProgress(
        pins: {
          'album:00000000000000000000000000000001': PinProgress(
            files: 10,
            have: 4,
            bytes: 5000000,
            haveBytes: 3000000,
          ),
        },
        waiting: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Will download when online'), findsOneWidget);

    progress.add(
      const OfflineProgress(
        pins: {
          'album:00000000000000000000000000000001': PinProgress(
            files: 10,
            have: 10,
            bytes: 5000000,
            haveBytes: 5000000,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Available offline (5 MB)'), findsOneWidget);

    progress.add(
      const OfflineProgress(
        pins: {
          'album:00000000000000000000000000000001': PinProgress(
            files: 6,
            have: 6,
            bytes: 3000000,
            haveBytes: 3000000,
            left: 4,
            leftBytes: 2000000,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Does not fit the budget: 2 MB more needed'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Stop keeping offline'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), isEmpty);
    expect(find.text('Trip'), findsNothing);
  });

  testWidgets('catalogue only says the pins wait', (tester) async {
    final album = OfflinePin.album(_id(1), 'Trip');
    final c = await pump(tester, const StoragePage());
    c.read(offlinePinsProvider.notifier).pin(album);
    c
        .read(offlinePolicyProvider.notifier)
        .setPreset(StoragePreset.catalogueOnly);
    await tester.pumpAndSettle();
    expect(
      find.text('Waiting: this preset keeps nothing offline'),
      findsOneWidget,
    );
  });

  testWidgets('a pin button keeps and lets go, and its status line shows', (
    tester,
  ) async {
    final album = OfflinePin.album(_id(2), 'Paris');
    final c = await pump(
      tester,
      Scaffold(
        body: Column(
          children: [
            OfflinePinButton(id: album.id, make: () => album),
            OfflineStatusLine(album.id),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsNothing);
    await tester.tap(find.byTooltip('Keep offline'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), [album]);
    expect(find.byIcon(Icons.push_pin), findsWidgets);
    expect(find.byTooltip('Stop keeping offline'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop keeping offline'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), isEmpty);
  });

  testWidgets('removing every offline copy asks first, with the exact size', (
    tester,
  ) async {
    final c = await pump(tester, const StoragePage());
    c.read(offlinePinsProvider.notifier).pin(OfflinePin.album(_id(1), 'Trip'));
    c.read(offlinePolicyProvider.notifier).setPreset(StoragePreset.spaceSaver);
    progress.add(const OfflineProgress(used: 7000000, budget: 5000000000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Remove offline copies'), 100);
    await tester.tap(find.text('Remove offline copies'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('7 MB'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), isNotEmpty);
    await tester.tap(find.text('Remove offline copies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), isEmpty);
    // A library kept whole would fill it again: back to pins only.
    expect(c.read(offlinePolicyProvider).preset, StoragePreset.travel);
  });

  testWidgets('the whole library and a person are kept from here too', (
    tester,
  ) async {
    final c = await pump(
      tester,
      const StoragePage(),
      overrides: [
        namedPeopleProvider.overrideWith(
          (ref) async => [(id: _id(9), name: 'Ann', photos: 12)],
        ),
      ],
    );
    await tester.scrollUntilVisible(find.text('Keep the whole library'), 100);
    await tester.tap(find.text('Keep the whole library'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider).single.kind, PinKind.library);
    await tester.tap(find.text('Keep the whole library'));
    await tester.pumpAndSettle();
    expect(c.read(offlinePinsProvider), isEmpty);

    await tester.scrollUntilVisible(find.text('Keep a person offline'), 100);
    await tester.tap(find.text('Keep a person offline'));
    await tester.pumpAndSettle();
    expect(find.text('12 items'), findsOneWidget);
    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    final pin = c.read(offlinePinsProvider).single;
    expect((pin.kind, pin.title), (PinKind.person, 'Ann'));
    expect(pin.target, _id(9));
  });

  testWidgets('with nobody named, the list of people says so', (tester) async {
    await pump(
      tester,
      const StoragePage(),
      overrides: [namedPeopleProvider.overrideWith((ref) async => [])],
    );
    await tester.scrollUntilVisible(find.text('Keep a person offline'), 100);
    await tester.tap(find.text('Keep a person offline'));
    await tester.pumpAndSettle();
    expect(find.text('No people are named yet.'), findsOneWidget);
  });
}
