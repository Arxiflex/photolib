import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/app.dart';
import 'package:photolib/core/feature_flags.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/providers.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/settings/settings.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib_data/photolib_data.dart' show Vault;

import 'support/pump_app.dart';

void main() {
  const phone = Size(400, 800);
  const tablet = Size(700, 800);
  const desktop = Size(1280, 800);

  group('navigation', () {
    testWidgets('opens on the Library tab', (tester) async {
      await pumpApp(tester);
      expect(find.text('Your photos will appear here'), findsOneWidget);
    });

    for (final size in [phone, tablet, desktop]) {
      testWidgets('${size.width.toInt()} px wide: the same three tabs switch '
          'the page', (tester) async {
        await pumpApp(tester, size: size);
        for (final tab in ['Library', 'Collections', 'Search']) {
          expect(find.text(tab), findsOneWidget);
        }

        for (final (tab, page) in [
          ('Search', 'Search your library'),
          ('Collections', 'Albums'),
          ('Library', 'Your photos will appear here'),
        ]) {
          await tester.tapAndSettle(find.text(tab));
          expect(find.text(page), findsOneWidget);
        }
      });
    }

    testWidgets('a tab keeps its state while another is open', (tester) async {
      await pumpApp(tester);
      for (final label in [
        'Collections',
        'Customise',
        'Search',
        'Collections',
      ]) {
        await tester.tapAndSettle(find.text(label));
      }
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('an unknown address shows the error view', (tester) async {
      await pumpApp(tester);
      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/nope');
      await tester.pumpAndSettle();
      expect(find.text('This page does not exist'), findsOneWidget);
    });
  });

  group('keyboard', () {
    const ctrl = [LogicalKeyboardKey.controlLeft];

    testWidgets('/ opens Search and Ctrl+, the settings', (tester) async {
      await pumpApp(tester);
      await tester.pressKey(LogicalKeyboardKey.slash, character: '/');
      expect(find.text('Search your library'), findsOneWidget);

      await tester.pressKey(LogicalKeyboardKey.comma, modifiers: ctrl);
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('the command palette reaches every tab', (tester) async {
      await pumpApp(tester);
      await tester.pressKey(LogicalKeyboardKey.keyK, modifiers: ctrl);
      await tester.enterText(find.byType(TextField), 'coll');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Albums'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    testWidgets('a phone gets a bottom bar', (tester) async {
      await pumpApp(tester, size: phone);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet gets a compact rail', (tester) async {
      await pumpApp(tester, size: tablet);
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
    });

    testWidgets('a desktop gets an extended rail', (tester) async {
      await pumpApp(tester, size: desktop);
      expect(find.byType(NavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
    });

    testWidgets('a desktop keeps list pages at reading width', (tester) async {
      await pumpApp(tester, size: desktop);
      await tester.tapAndSettle(find.text('Collections'));
      expect(
        tester.getSize(find.byType(ListView)).width,
        lessThanOrEqualTo(640),
      );
    });
  });

  group('settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tapAndSettle(find.byTooltip('Settings'));
    }

    testWidgets('open from the app bar and close with back', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text('Theme'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Your photos will appear here'), findsOneWidget);
    });

    testWidgets("the first frame has the stored theme, or the system's "
        'when the vault is slow to answer or fails', (tester) async {
      for (final vault in ['answers', 'slow', 'fails']) {
        final answer = Completer<void>();
        final container = ProviderContainer(
          overrides: [
            vaultProvider.overrideWith(
              (ref) => vault == 'fails'
                  // As the keystore fails where no keyring runs.
                  ? Future.error(PlatformException(code: 'Libsecret error'))
                  : Completer<Vault>().future,
            ),
            replicaProvider.overrideWith(
              (ref) => Future.error(UnsupportedError('no replica')),
            ),
            settingsStoreProvider.overrideWithValue(
              MemoryStore('{"themeMode":"dark"}', answer.future),
            ),
          ],
        );
        final running = runPhotolib(container);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byType(MaterialApp),
          vault == 'fails' ? findsOneWidget : findsNothing,
          reason: vault,
        );
        if (vault == 'answers') answer.complete();
        if (vault == 'slow') await tester.pump(const Duration(seconds: 1));
        await running;
        await tester.pump();
        expect(
          Theme.of(tester.element(find.text('Library').first)).brightness,
          vault == 'answers' ? Brightness.dark : Brightness.light,
          reason: vault,
        );
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    });

    testWidgets('a store that cannot open is said on every tab and in '
        'Settings, and tried again on request', (tester) async {
      var fails = true;
      Future<T> open<T>(T value) => fails
          ? Future.error(PlatformException(code: 'Libsecret error'))
          : Future.value(value);
      await pumpApp(
        tester,
        vault: () => open(Completer<Vault>()).then((c) => c.future),
        settings: _Store(() => open('{"themeMode":"dark"}')),
      );
      const said =
          'The store on this device is unavailable: settings and collections '
          'are not kept';
      expect(find.text(said), findsOneWidget);
      await tester.tapAndSettle(find.text('Collections'));
      expect(find.text(said), findsOneWidget);
      await openSettings(tester);
      expect(find.text(said), findsOneWidget, reason: 'nothing set is kept');
      await tester.pageBack();
      await tester.pumpAndSettle();
      Brightness brightness() =>
          Theme.of(tester.element(find.text('Library').first)).brightness;
      expect(brightness(), Brightness.light);
      fails = false;
      await tester.tapAndSettle(find.text('Try again'));
      expect(find.text(said), findsNothing);
      expect(brightness(), Brightness.dark, reason: 'read again');
    });

    testWidgets('the app starts at once when the keystore asks for a '
        'passphrase, not after waiting for the settings it cannot read yet', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          vaultProvider.overrideWith((ref) async {
            // As the keystore asks, after the vault began to open.
            await Future<void>.value();
            await ref
                .read(passphrasePromptProvider.notifier)
                .ask(create: true, retry: false);
            return await Completer<Vault>().future;
          }),
          replicaProvider.overrideWith(
            (ref) => Future.error(UnsupportedError('no replica')),
          ),
        ],
      );
      addTearDown(container.dispose);
      final running = runPhotolib(container, wait: const Duration(hours: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MaterialApp), findsOneWidget);
      await running;
      await tester.pumpAndSettle();
      expect(find.textContaining('runs no keyring'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switch the whole app to the dark theme', (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.text('Theme'))).brightness;
      expect(brightness(), Brightness.light);

      await tester.tapAndSettle(find.text('Dark'));
      expect(brightness(), Brightness.dark);
    });

    testWidgets('a system asking for high contrast gets it', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpApp(tester);
      expect(
        Theme.of(tester.element(find.text('Library').first)).colorScheme,
        appTheme(Brightness.light, highContrast: true).colorScheme,
      );
    });

    testWidgets('a release build hides diagnostics unless the flag is on', (
      tester,
    ) async {
      await pumpApp(
        tester,
        overrides: [releaseBuildProvider.overrideWithValue(true)],
      );
      await openSettings(tester);
      await tester.scrollTo(find.text('Show diagnostics'));
      expect(find.text('Diagnostics'), findsNothing);
      expect(find.text('Timeline benchmark'), findsNothing);
    });

    testWidgets('diagnostics show the log and the benchmark', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          releaseBuildProvider.overrideWithValue(true),
          featureFlagsProvider.overrideWithValue(
            FeatureFlags.parse('diagnostics'),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(loggerProvider).child('sync').info('first sync');
      await openSettings(tester);
      await tester.scrollTo(find.text('Timeline benchmark'));
      expect(find.text('Timeline benchmark'), findsOneWidget);
      await tester.tapAndSettle(find.text('Diagnostics'));

      expect(find.textContaining('first sync'), findsOneWidget);
    });
  });
}

/// A vault object that [read] answers.
class _Store implements SecretStore {
  new(this._read);

  final Future<String?> Function() _read;

  @override
  Future<String?> read() => _read();

  @override
  Future<void> write(String? value) async {}
}
